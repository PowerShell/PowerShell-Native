// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::invalid_pointer;
use libc::{c_char, c_int};

#[cfg(not(target_os = "macos"))]
mod platform {
    use super::{c_char, c_int};
    use std::ffi::{CStr, CString};
    use std::sync::Mutex;

    // openlog may retain ident rather than copying it.
    static IDENTITY: Mutex<Option<CString>> = Mutex::new(None);

    pub unsafe fn open(ident: *const c_char, facility: c_int) {
        let identity = unsafe { CStr::from_ptr(ident) }.to_owned();
        let mut retained = IDENTITY.lock().unwrap_or_else(|_| std::process::abort());
        unsafe {
            libc::openlog(
                identity.as_ptr(),
                libc::LOG_NDELAY | libc::LOG_PID,
                facility,
            );
        };
        *retained = Some(identity);
    }

    pub unsafe fn write(priority: c_int, message: *const c_char) {
        // The message must never be treated as the format string.
        unsafe { libc::syslog(priority, c"%s".as_ptr(), message) };
    }

    pub fn close() {
        let mut retained = IDENTITY.lock().unwrap_or_else(|_| std::process::abort());
        unsafe { libc::closelog() };
        *retained = None;
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use super::{c_char, c_int};
    use std::ffi::c_void;
    use std::sync::atomic::{AtomicPtr, Ordering};

    static LOG: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());

    // This is the SDK's os_log macro backend, not a printf-style variadic ABI.
    unsafe extern "C" {
        fn os_log_create(subsystem: *const c_char, category: *const c_char) -> *mut c_void;
        fn os_log_type_enabled(log: *mut c_void, kind: u8) -> bool;
        fn _os_log_impl(
            dso: *const u8,
            log: *mut c_void,
            kind: u8,
            format: *const c_char,
            buffer: *const u8,
            length: u32,
        );
        static __dso_handle: u8;
    }

    #[used]
    #[unsafe(link_section = "__TEXT,__oslogstring,cstring_literals")]
    static FORMAT: [u8; 11] = *b"%{public}s\0";

    #[repr(C, packed)]
    struct StringArgument {
        summary: u8,
        count: u8,
        descriptor: u8,
        size: u8,
        value: *const c_char,
    }

    pub unsafe fn open(ident: *const c_char, _facility: c_int) {
        let log = unsafe { os_log_create(c"com.microsoft.powershell".as_ptr(), ident) };
        LOG.store(log, Ordering::Release);
    }

    pub unsafe fn write(priority: c_int, message: *const c_char) {
        let log = LOG.load(Ordering::Acquire);
        if log.is_null() {
            crate::set_errno(libc::EINVAL);
            return;
        }
        let kind = match priority {
            libc::LOG_EMERG | libc::LOG_ALERT | libc::LOG_CRIT => 0x11,
            libc::LOG_ERR => 0x10,
            libc::LOG_DEBUG => 0x02,
            _ => 0x00,
        };
        if unsafe { os_log_type_enabled(log, kind) } {
            let argument = StringArgument {
                summary: 0x02, // Has a non-scalar argument.
                count: 1,
                descriptor: 0x22, // String (2), explicitly public (2).
                size: u8::try_from(size_of::<*const c_char>()).expect("pointer size fits u8"),
                value: message,
            };
            unsafe {
                _os_log_impl(
                    &raw const __dso_handle,
                    log,
                    kind,
                    FORMAT.as_ptr().cast(),
                    (&raw const argument).cast(),
                    u32::try_from(size_of::<StringArgument>()).expect("log payload size fits u32"),
                );
            };
        }
    }

    // Preserve the original macOS close operation, which is intentionally a no-op.
    pub fn close() {}
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn Native_OpenLog(ident: *const c_char, facility: c_int) {
    if !invalid_pointer(ident) {
        unsafe { platform::open(ident, facility) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn Native_SysLog(priority: c_int, message: *const c_char) {
    if !invalid_pointer(message) {
        unsafe { platform::write(priority, message) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn Native_CloseLog() {
    platform::close();
}
