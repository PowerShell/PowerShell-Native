// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use std::{
    ffi::{c_void, CStr},
    os::windows::ffi::{OsStrExt, OsStringExt},
    path::PathBuf,
    ptr,
};

pub type Ptr = *mut c_void;
pub type Wide = *const u16;
pub type Result<T> = std::result::Result<T, u32>;

#[link(name = "kernel32")]
extern "system" {
    pub fn LoadLibraryExW(name: Wide, file: Ptr, flags: u32) -> Ptr;
    pub fn GetModuleHandleW(name: Wide) -> Ptr;
    pub fn GetModuleHandleExW(flags: u32, name: Wide, module: *mut Ptr) -> i32;
    pub fn GetModuleFileNameW(module: Ptr, name: *mut u16, size: u32) -> u32;
    pub fn GetProcAddress(module: Ptr, name: *const u8) -> Ptr;
    pub fn FreeLibrary(module: Ptr) -> i32;
    pub fn GetLastError() -> u32;
    pub fn ExpandEnvironmentStringsW(source: Wide, target: *mut u16, count: u32) -> u32;
    pub fn SetErrorMode(mode: u32) -> u32;
    pub fn SetThreadUILanguage(language: u16) -> u16;
    #[cfg(not(feature = "coreclr"))]
    pub fn GetStartupInfoW(info: *mut StartupInfo);
    #[cfg(not(feature = "coreclr"))]
    pub fn SetConsoleTitleW(title: Wide) -> i32;
    #[cfg(not(feature = "coreclr"))]
    pub fn IsWow64Process(process: Ptr, wow64: *mut i32) -> i32;
    #[cfg(not(feature = "coreclr"))]
    pub fn GetCurrentProcess() -> Ptr;
    pub fn GetStdHandle(kind: u32) -> Ptr;
    pub fn GetFileType(handle: Ptr) -> u32;
    pub fn WriteConsoleW(
        handle: Ptr,
        text: Wide,
        length: u32,
        written: *mut u32,
        reserved: Ptr,
    ) -> i32;
    pub fn WriteFile(
        handle: Ptr,
        data: *const u8,
        count: u32,
        written: *mut u32,
        overlapped: Ptr,
    ) -> i32;
    pub fn FormatMessageW(
        flags: u32,
        source: Ptr,
        id: u32,
        language: u32,
        buffer: *mut u16,
        size: u32,
        arguments: *const usize,
    ) -> u32;
}
#[link(name = "user32")]
extern "system" {
    #[cfg(not(feature = "coreclr"))]
    pub fn LoadStringW(instance: Ptr, id: u32, buffer: *mut u16, length: i32) -> i32;
}
#[link(name = "advapi32")]
extern "system" {
    pub fn RegOpenKeyExW(parent: Ptr, name: Wide, options: u32, access: u32, key: *mut Ptr) -> i32;
    pub fn RegQueryValueExW(
        key: Ptr,
        name: Wide,
        reserved: Ptr,
        kind: *mut u32,
        data: *mut u8,
        bytes: *mut u32,
    ) -> i32;
    pub fn RegEnumKeyExW(
        key: Ptr,
        index: u32,
        name: *mut u16,
        length: *mut u32,
        reserved: Ptr,
        class: *mut u16,
        class_length: *mut u32,
        time: Ptr,
    ) -> i32;
    pub fn RegCloseKey(key: Ptr) -> i32;
}

#[repr(C)]
#[derive(Default)]
#[cfg(not(feature = "coreclr"))]
pub struct StartupInfo {
    pub size: u32,
    pub reserved: *mut u16,
    pub desktop: *mut u16,
    pub title: *mut u16,
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
    pub chars_x: u32,
    pub chars_y: u32,
    pub fill: u32,
    pub flags: u32,
    pub show: u16,
    pub reserved_bytes: u16,
    pub reserved_data: *mut u8,
    pub input: Ptr,
    pub output: Ptr,
    pub error: Ptr,
}

pub fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}
pub fn path_wide(path: &std::path::Path) -> Vec<u16> {
    path.as_os_str().encode_wide().chain(Some(0)).collect()
}
pub unsafe fn wide_slice<'a>(text: Wide) -> &'a [u16] {
    if text.is_null() {
        return &[];
    }
    let mut size = 0;
    while *text.add(size) != 0 {
        size += 1;
    }
    std::slice::from_raw_parts(text, size)
}
#[cfg(not(feature = "coreclr"))]
pub unsafe fn string(text: Wide) -> String {
    String::from_utf16_lossy(wide_slice(text))
}

/// Managed callers should use Environment.ExpandEnvironmentVariables.
pub fn expand(text: &str) -> Result<String> {
    let text = wide(text);
    unsafe {
        let size = ExpandEnvironmentStringsW(text.as_ptr(), ptr::null_mut(), 0);
        if size == 0 {
            return Err(GetLastError());
        }
        let mut value = vec![0; size as usize];
        let count = ExpandEnvironmentStringsW(text.as_ptr(), value.as_mut_ptr(), size);
        if count == 0 {
            return Err(GetLastError());
        }
        if count > size {
            return Err(122);
        }
        Ok(String::from_utf16_lossy(&value[..count as usize - 1]))
    }
}

/// Managed callers should use Environment.ProcessPath or Process.MainModule.FileName.
pub fn module_path(module: Ptr) -> Result<PathBuf> {
    let mut buffer = vec![0; 512];
    loop {
        let capacity = u32::try_from(buffer.len()).map_err(|_| 206u32)?;
        let count = unsafe { GetModuleFileNameW(module, buffer.as_mut_ptr(), capacity) };
        if count == 0 {
            return Err(unsafe { GetLastError() });
        }
        if (count as usize) < buffer.len() {
            return Ok(std::ffi::OsString::from_wide(&buffer[..count as usize]).into());
        }
        if buffer.len() >= 32768 {
            return Err(206);
        }
        buffer.resize(buffer.len() * 2, 0);
    }
}

pub struct Module(pub Ptr);
impl Module {
    /// Managed callers should use NativeLibrary.Load/GetExport/Free.
    pub fn load(path: &std::path::Path) -> Result<Self> {
        let name = path_wide(path);
        let handle = unsafe { LoadLibraryExW(name.as_ptr(), ptr::null_mut(), 0) };
        if handle.is_null() {
            Err(unsafe { GetLastError() })
        } else {
            Ok(Self(handle))
        }
    }
    pub fn symbol(&self, name: &CStr) -> Result<Ptr> {
        let address = unsafe { GetProcAddress(self.0, name.as_ptr().cast()) };
        if address.is_null() {
            Err(unsafe { GetLastError() })
        } else {
            Ok(address)
        }
    }
    pub fn pin(&self) -> Result<()> {
        let path = module_path(self.0)?;
        let name = path_wide(&path);
        let mut handle = ptr::null_mut();
        if unsafe { GetModuleHandleExW(1, name.as_ptr(), &raw mut handle) } == 0 {
            Err(unsafe { GetLastError() })
        } else {
            Ok(())
        }
    }
}
impl Drop for Module {
    fn drop(&mut self) {
        unsafe {
            FreeLibrary(self.0);
        }
    }
}

pub struct ComApartment(bool);
impl ComApartment {
    pub fn new(multithreaded: bool, tolerate_changed_mode: bool) -> Result<Self> {
        use windows::Win32::System::Com::{
            CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED,
        };
        let hr = unsafe {
            CoInitializeEx(
                None,
                if multithreaded {
                    COINIT_MULTITHREADED
                } else {
                    COINIT_APARTMENTTHREADED
                },
            )
        };
        if hr.is_ok() {
            Ok(Self(true))
        } else if tolerate_changed_mode && status_code(hr.0) == 0x8001_0106 {
            Ok(Self(false))
        } else {
            Err(status_code(hr.0))
        }
    }
}
impl Drop for ComApartment {
    fn drop(&mut self) {
        if self.0 {
            unsafe {
                windows::Win32::System::Com::CoUninitialize();
            }
        }
    }
}

/// Managed callers should use Win32Exception(error).Message.
pub fn message(module: Ptr, code: u32, arguments: &[usize]) -> Vec<u16> {
    let mut buffer = vec![0; 32768];
    let flags = (if module.is_null() { 0x1000 } else { 0x800 })
        | if arguments.is_empty() { 0x200 } else { 0x2000 };
    let count = unsafe {
        FormatMessageW(
            flags,
            module,
            code,
            0,
            buffer.as_mut_ptr(),
            32768,
            arguments.as_ptr(),
        )
    };
    if count == 0 {
        return wide(&format!("PowerShell native host error 0x{code:08x}\r\n"));
    }
    buffer.truncate(count as usize);
    buffer.push(0);
    buffer
}

/// Managed callers should use Console.Write/Console.Error.Write. Legacy resource diagnostics
/// remain UTF-16 when redirected; `CoreCLR` stdout uses `core_stdout` instead.
pub fn output(text: &[u16], stdout: bool) {
    let count = text.iter().position(|c| *c == 0).unwrap_or(text.len());
    unsafe {
        let handle = GetStdHandle(status_code(if stdout { -11 } else { -12 }));
        let mut offset = 0;
        while offset < count {
            let chunk = u32::try_from((count - offset).min(u32::MAX as usize / 2))
                .expect("output chunk fits DWORD");
            let mut written = 0;
            let result = if GetFileType(handle) & !0x8000 == 2 {
                WriteConsoleW(
                    handle,
                    text[offset..].as_ptr(),
                    chunk,
                    &raw mut written,
                    ptr::null_mut(),
                )
            } else {
                let result = WriteFile(
                    handle,
                    text[offset..].as_ptr().cast(),
                    chunk * 2,
                    &raw mut written,
                    ptr::null_mut(),
                );
                written /= 2;
                result
            };
            if result == 0 || written == 0 {
                break;
            }

            offset += written as usize;
        }
    }
}

/// Managed callers should use Console.Write. Share byte-oriented UTF-8 output with the
/// managed `CoreCLR` payload when redirected; Rust handles Unicode console output directly.
///
/// # Errors
/// Returns the native I/O error if stdout cannot be written or flushed.
#[cfg(feature = "coreclr")]
pub fn core_stdout(text: &str) -> Result<()> {
    use std::io::Write;

    let mut stdout = std::io::stdout().lock();
    stdout
        .write_all(text.as_bytes())
        .and_then(|()| stdout.flush())
        .map_err(|error| {
            error
                .raw_os_error()
                .map_or(crate::policy::INIT_FAILURE, status_code)
        })
}

// HRESULTs and process statuses are signed/unsigned views of the same 32 bits.
pub fn status_code(value: i32) -> u32 {
    u32::from_ne_bytes(value.to_ne_bytes())
}
