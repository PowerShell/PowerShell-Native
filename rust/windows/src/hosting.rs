// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{
    common::HostEnvironment,
    policy::INIT_FAILURE,
    win::{output, status_code, wide, wide_slice, Module, Ptr, Result, SetErrorMode, Wide},
};
use std::{ffi::CString, mem, ptr};
use windows::core::GUID;

pub const CONSOLE_ASSEMBLY: &str = "Microsoft.PowerShell.ConsoleHost, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";

type Initialize = unsafe extern "system" fn(
    *const u8,
    *const u8,
    i32,
    *const *const u8,
    *const *const u8,
    *mut Ptr,
    *mut u32,
) -> i32;
type Shutdown = unsafe extern "system" fn(Ptr, u32) -> i32;
type CreateDelegate =
    unsafe extern "system" fn(Ptr, u32, *const u8, *const u8, *const u8, *mut Ptr) -> i32;

pub struct CoreClr {
    _module: Module,
    handle: Ptr,
    domain: u32,
    shutdown: Shutdown,
    create_delegate: CreateDelegate,
    stopped: bool,
}
impl CoreClr {
    /// # Errors
    /// Returns a native or hosting error if loading or initializing `CoreCLR` fails.
    pub fn launch(environment: &HostEnvironment, friendly_name: &str) -> Result<Self> {
        let path = environment.runtime.join("CoreCLR.dll");
        let module = Module::load(&path)?;
        module.pin()?;
        let initialize: Initialize =
            unsafe { mem::transmute(module.symbol(c"coreclr_initialize")?) };
        let shutdown: Shutdown = unsafe { mem::transmute(module.symbol(c"coreclr_shutdown")?) };
        let create_delegate: CreateDelegate =
            unsafe { mem::transmute(module.symbol(c"coreclr_create_delegate")?) };
        let keys = [
            c"TRUSTED_PLATFORM_ASSEMBLIES".as_ptr().cast::<u8>(),
            c"APP_PATHS".as_ptr().cast(),
            c"APP_NI_PATHS".as_ptr().cast(),
        ];
        let assemblies =
            CString::new(environment.trusted_assemblies()?).map_err(|_| INIT_FAILURE)?;
        let values = [
            assemblies.as_ptr().cast::<u8>(),
            c"".as_ptr().cast(),
            c"".as_ptr().cast(),
        ];
        let mut executable = environment.assemblies.to_string_lossy().into_owned();
        if !executable.ends_with('\\') {
            executable.push('\\');
        }
        let executable = CString::new(executable).map_err(|_| INIT_FAILURE)?;
        let friendly_name = CString::new(friendly_name).map_err(|_| INIT_FAILURE)?;
        let mut handle = ptr::null_mut();
        let mut domain = 0;
        let hr = unsafe {
            initialize(
                executable.as_ptr().cast(),
                friendly_name.as_ptr().cast(),
                3,
                keys.as_ptr(),
                values.as_ptr(),
                &raw mut handle,
                &raw mut domain,
            )
        };
        if hr < 0 {
            return Err(status_code(hr));
        }
        Ok(Self {
            _module: module,
            handle,
            domain,
            shutdown,
            create_delegate,
            stopped: false,
        })
    }

    /// # Errors
    /// Returns a hosting error if the managed entry point cannot be resolved.
    pub fn delegate(&self, assembly: &str, class: &str, method: &str) -> Result<Ptr> {
        let assembly = CString::new(assembly).map_err(|_| INIT_FAILURE)?;
        let class = CString::new(class).map_err(|_| INIT_FAILURE)?;
        let method = CString::new(method).map_err(|_| INIT_FAILURE)?;
        let mut result = ptr::null_mut();
        let hr = unsafe {
            (self.create_delegate)(
                self.handle,
                self.domain,
                assembly.as_ptr().cast(),
                class.as_ptr().cast(),
                method.as_ptr().cast(),
                &raw mut result,
            )
        };
        if hr < 0 {
            Err(status_code(hr))
        } else if result.is_null() {
            Err(INIT_FAILURE)
        } else {
            Ok(result)
        }
    }

    /// # Errors
    /// Returns the HRESULT if `CoreCLR` cannot shut down.
    pub fn shutdown(&mut self) -> Result<()> {
        if self.stopped {
            return Ok(());
        }
        let hr = unsafe { (self.shutdown)(self.handle, self.domain) };
        if hr < 0 {
            return Err(status_code(hr));
        }
        self.stopped = true;
        Ok(())
    }
}
impl Drop for CoreClr {
    fn drop(&mut self) {
        let _ = self.shutdown();
    }
}

#[link(name = "mscoree")]
extern "system" {
    fn CorBindToRuntimeEx(
        version: Wide,
        flavor: Wide,
        flags: u32,
        class: *const GUID,
        interface: *const GUID,
        result: *mut Ptr,
    ) -> i32;
}
#[link(name = "oleaut32")]
extern "system" {
    fn SysAllocStringLen(text: Wide, length: u32) -> *mut u16;
    fn SysFreeString(text: *mut u16);
    fn VariantClear(variant: *mut AutomationVariant) -> i32;
    fn SafeArrayCreate(kind: u16, dimensions: u32, bounds: *const ArrayBound) -> Ptr;
    fn SafeArrayPutElement(array: Ptr, indices: *const i32, value: Ptr) -> i32;
    fn SafeArrayDestroy(array: Ptr) -> i32;
}

#[repr(C)]
struct ArrayBound {
    elements: u32,
    lower_bound: i32,
}

#[repr(C)]
pub union VariantValue {
    pub pointer: Ptr,
    pub signed: i64,
    pub int: i32,
    pub uint: u32,
    layout: [usize; 2],
}
#[repr(C)]
pub struct AutomationVariant {
    pub kind: u16,
    reserved: [u16; 3],
    pub value: VariantValue,
}
impl Default for AutomationVariant {
    fn default() -> Self {
        Self {
            kind: 0,
            reserved: [0; 3],
            value: VariantValue { layout: [0; 2] },
        }
    }
}
impl Drop for AutomationVariant {
    fn drop(&mut self) {
        unsafe {
            VariantClear(self);
        }
    }
}
impl AutomationVariant {
    /// # Errors
    /// Returns a host error if the string is too large or cannot be allocated.
    pub fn bstr(text: Option<&[u16]>) -> Result<Self> {
        let string = if let Some(text) = text {
            let length = u32::try_from(text.len()).map_err(|_| INIT_FAILURE)?;
            let string = unsafe { SysAllocStringLen(text.as_ptr(), length) };
            if string.is_null() {
                return Err(0x8007_000e);
            }
            string
        } else {
            ptr::null_mut()
        };
        Ok(Self {
            kind: 8,
            reserved: [0; 3],
            value: VariantValue {
                pointer: string.cast(),
            },
        })
    }
    /// Managed callers should pass string[] directly; no SAFEARRAY marshaling is necessary.
    ///
    /// # Errors
    /// Returns a host or Automation error if array conversion or allocation fails.
    pub fn strings(arguments: &[Vec<u16>]) -> Result<Self> {
        let count = i32::try_from(arguments.len()).map_err(|_| INIT_FAILURE)?;
        let bounds = ArrayBound {
            elements: count.unsigned_abs(),
            lower_bound: 0,
        };
        let array = unsafe { SafeArrayCreate(8, 1, &raw const bounds) };
        if array.is_null() {
            return Err(0x8007_000e);
        }
        for (index, argument) in (0..count).zip(arguments) {
            let length = argument
                .iter()
                .position(|c| *c == 0)
                .unwrap_or(argument.len());
            let value = match Self::bstr(Some(&argument[..length])) {
                Ok(value) => value,
                Err(error) => {
                    unsafe {
                        SafeArrayDestroy(array);
                    }
                    return Err(error);
                }
            };
            let hr = unsafe { SafeArrayPutElement(array, &raw const index, value.value.pointer) };
            if hr < 0 {
                unsafe {
                    SafeArrayDestroy(array);
                }
                return Err(status_code(hr));
            }
        }
        Ok(Self {
            kind: 0x2008,
            reserved: [0; 3],
            value: VariantValue { pointer: array },
        })
    }
    /// # Errors
    /// Returns a type mismatch for a non-integer Automation result.
    pub fn int_result(&self) -> Result<u32> {
        unsafe {
            match self.kind {
                3 | 19 | 22 | 23 => Ok(self.value.uint),
                _ => Err(0x8002_0005),
            }
        }
    }
    /// # Errors
    /// Returns a COM error if the variant does not contain a dispatch object.
    pub fn dispatch(&self) -> Result<ComObject> {
        if self.kind != 9 && self.kind != 13 {
            return Err(0x8002_0005);
        }
        let pointer = unsafe { self.value.pointer };
        if pointer.is_null() {
            return Err(INIT_FAILURE);
        }
        let object = ComObject(pointer);
        let result = object.query(&IID_DISPATCH);
        mem::forget(object); // The variant owns its original reference.
        result
    }
}

#[repr(C)]
struct DispatchParameters {
    arguments: *mut AutomationVariant,
    named_arguments: *mut i32,
    count: u32,
    named_count: u32,
}
#[repr(C)]
#[derive(Default)]
struct ExceptionInfo {
    code: u16,
    reserved: u16,
    source: *mut u16,
    description: *mut u16,
    help: *mut u16,
    help_context: u32,
    reserved_pointer: Ptr,
    deferred: Ptr,
    status: i32,
}
impl Drop for ExceptionInfo {
    fn drop(&mut self) {
        unsafe {
            SysFreeString(self.source);
            SysFreeString(self.description);
            SysFreeString(self.help);
        }
    }
}

const IID_DISPATCH: GUID = GUID::from_u128(0x00020400_0000_0000_c000_000000000046);
const IID_APPDOMAIN: GUID = GUID::from_u128(0x05f696dc_2b29_3663_ad8b_c4389cf2a713);
const CLSID_COR_RUNTIME: GUID = GUID::from_u128(0xcb2f6723_ab3a_11d2_9c40_00c04fa30a3e);
const IID_COR_RUNTIME: GUID = GUID::from_u128(0xcb2f6722_ab3a_11d2_9c40_00c04fa30a3e);
const IID_NULL: GUID = GUID::zeroed();

pub struct ComObject(Ptr);
impl ComObject {
    unsafe fn slot(&self, index: usize) -> Ptr {
        *(*(self.0 as *const *const Ptr)).add(index)
    }
    /// # Errors
    /// Returns the HRESULT if the requested COM interface is unavailable.
    pub fn query(&self, iid: &GUID) -> Result<Self> {
        let query: unsafe extern "system" fn(Ptr, *const GUID, *mut Ptr) -> i32 =
            unsafe { mem::transmute(self.slot(0)) };
        let mut result = ptr::null_mut();
        let hr = unsafe { query(self.0, iid, &raw mut result) };
        if hr < 0 {
            Err(status_code(hr))
        } else if result.is_null() {
            Err(INIT_FAILURE)
        } else {
            Ok(Self(result))
        }
    }

    /// # Errors
    /// Returns a COM or Automation error if name resolution or invocation fails.
    pub fn invoke(
        &self,
        name: &str,
        arguments: &mut [AutomationVariant],
    ) -> Result<AutomationVariant> {
        let get_id: unsafe extern "system" fn(
            Ptr,
            *const GUID,
            *const Wide,
            u32,
            u32,
            *mut i32,
        ) -> i32 = unsafe { mem::transmute(self.slot(5)) };
        let invoke: unsafe extern "system" fn(
            Ptr,
            i32,
            *const GUID,
            u32,
            u16,
            *mut DispatchParameters,
            *mut AutomationVariant,
            *mut ExceptionInfo,
            *mut u32,
        ) -> i32 = unsafe { mem::transmute(self.slot(6)) };
        let name = wide(name);
        let mut id = 0;
        let hr = unsafe { get_id(self.0, &IID_NULL, &name.as_ptr(), 1, 0x800, &raw mut id) };
        if hr < 0 {
            return Err(status_code(hr));
        }
        let mut parameters = DispatchParameters {
            arguments: arguments.as_mut_ptr(),
            named_arguments: ptr::null_mut(),
            count: u32::try_from(arguments.len()).map_err(|_| INIT_FAILURE)?,
            named_count: 0,
        };
        let mut result = AutomationVariant::default();
        let mut exception = ExceptionInfo::default();
        let mut argument_error = 0;
        let hr = unsafe {
            invoke(
                self.0,
                id,
                &IID_NULL,
                0x800,
                1,
                &raw mut parameters,
                &raw mut result,
                &raw mut exception,
                &raw mut argument_error,
            )
        };
        if hr < 0 {
            if !exception.deferred.is_null() {
                let fill: unsafe extern "system" fn(*mut ExceptionInfo) -> i32 =
                    unsafe { mem::transmute(exception.deferred) };
                unsafe {
                    fill(&raw mut exception);
                }
            }
            if !exception.description.is_null() {
                let description = unsafe { wide_slice(exception.description) };
                output(description, false);
            }
            Err(status_code(hr))
        } else {
            Ok(result)
        }
    }
}
impl Drop for ComObject {
    fn drop(&mut self) {
        let release: unsafe extern "system" fn(Ptr) -> u32 =
            unsafe { mem::transmute(self.slot(2)) };
        unsafe {
            release(self.0);
        }
    }
}

pub struct FrameworkClr {
    host: ComObject,
}
impl FrameworkClr {
    /// # Errors
    /// Returns the HRESULT if binding or starting the selected Framework CLR fails.
    pub fn launch(runtime: &str) -> Result<Self> {
        let mut host = ptr::null_mut();
        unsafe {
            SetErrorMode(1);
        }
        let hr = unsafe {
            CorBindToRuntimeEx(
                wide(runtime).as_ptr(),
                wide("wks").as_ptr(),
                4,
                &CLSID_COR_RUNTIME,
                &IID_COR_RUNTIME,
                &raw mut host,
            )
        };
        if hr < 0 {
            return Err(status_code(hr));
        }
        if host.is_null() {
            return Err(INIT_FAILURE);
        }
        let host = ComObject(host);
        let start: unsafe extern "system" fn(Ptr) -> i32 = unsafe { mem::transmute(host.slot(10)) };
        let hr = unsafe { start(host.0) };
        if hr < 0 {
            return Err(status_code(hr));
        }
        Ok(Self { host })
    }

    /// # Errors
    /// Returns a COM or Automation error if managed object activation fails.
    pub fn instance(&self, assembly: &str, class: &str) -> Result<ComObject> {
        let get_domain: unsafe extern "system" fn(Ptr, *mut Ptr) -> i32 =
            unsafe { mem::transmute(self.host.slot(13)) };
        let mut domain = ptr::null_mut();
        let hr = unsafe { get_domain(self.host.0, &raw mut domain) };
        if hr < 0 {
            return Err(status_code(hr));
        }
        if domain.is_null() {
            return Err(INIT_FAILURE);
        }
        let domain = ComObject(domain).query(&IID_APPDOMAIN)?;
        // _AppDomain is InterfaceIsIUnknown, NOT IDispatch. Slots 3..6 are its explicit
        // dispatch compatibility members; CreateInstance(string,string) is slot 37.
        // Contract: .NET Framework mscorlib System._AppDomain (iappdomain.cs).
        let create: unsafe extern "system" fn(Ptr, *mut u16, *mut u16, *mut Ptr) -> i32 =
            unsafe { mem::transmute(domain.slot(37)) };
        let assembly = AutomationVariant::bstr(Some(&assembly.encode_utf16().collect::<Vec<_>>()))?;
        let class = AutomationVariant::bstr(Some(&class.encode_utf16().collect::<Vec<_>>()))?;
        let mut handle = ptr::null_mut();
        let hr = unsafe {
            create(
                domain.0,
                assembly.value.pointer.cast(),
                class.value.pointer.cast(),
                &raw mut handle,
            )
        };
        if hr < 0 {
            return Err(status_code(hr));
        }
        if handle.is_null() {
            return Err(INIT_FAILURE);
        }
        let handle = ComObject(handle).query(&IID_DISPATCH)?;
        let unwrapped = handle.invoke("Unwrap", &mut [])?;
        unwrapped.dispatch()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn automation_layout() {
        assert_eq!(
            mem::size_of::<AutomationVariant>(),
            if cfg!(target_pointer_width = "64") {
                24
            } else {
                16
            }
        );
        assert_eq!(mem::offset_of!(AutomationVariant, value), 8);
    }

    #[test]
    fn automation_null_objects_are_rejected_without_releasing_null() {
        for kind in [9, 13] {
            let variant = AutomationVariant {
                kind,
                reserved: [0; 3],
                value: VariantValue {
                    pointer: ptr::null_mut(),
                },
            };
            assert!(matches!(variant.dispatch(), Err(INIT_FAILURE)));
        }
    }

    #[test]
    fn automation_non_objects_report_type_mismatch() {
        let variant = AutomationVariant::default();
        assert!(matches!(variant.dispatch(), Err(0x8002_0005)));
    }

    #[test]
    fn automation_string_array_preserves_utf16_and_bounds() {
        #[link(name = "oleaut32")]
        extern "system" {
            fn SafeArrayGetDim(array: Ptr) -> u32;
            fn SafeArrayGetLBound(array: Ptr, dimension: u32, bound: *mut i32) -> i32;
            fn SafeArrayGetUBound(array: Ptr, dimension: u32, bound: *mut i32) -> i32;
            fn SafeArrayGetElement(array: Ptr, index: *const i32, value: Ptr) -> i32;
        }
        let arguments = [wide("first"), wide(""), wide("\u{03bb}\u{1f600}")];
        let variant = AutomationVariant::strings(&arguments).unwrap();
        assert_eq!(variant.kind, 0x2008);
        unsafe {
            let array = variant.value.pointer;
            assert_eq!(SafeArrayGetDim(array), 1);
            let mut bound = -1;
            assert_eq!(SafeArrayGetLBound(array, 1, &raw mut bound), 0);
            assert_eq!(bound, 0);
            assert_eq!(SafeArrayGetUBound(array, 1, &raw mut bound), 0);
            assert_eq!(bound, 2);
            for (index, expected) in arguments.iter().enumerate() {
                let mut value: *mut u16 = ptr::null_mut();
                assert_eq!(
                    SafeArrayGetElement(
                        array,
                        &i32::try_from(index).unwrap(),
                        (&raw mut value).cast()
                    ),
                    0
                );
                let actual = wide_slice(value).to_vec();
                SysFreeString(value);
                assert_eq!(actual, expected[..expected.len() - 1]);
            }
        }
    }
}
