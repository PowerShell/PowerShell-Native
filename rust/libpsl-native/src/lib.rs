// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#![cfg(unix)]
#![allow(non_snake_case)]
// Every exported function accepts the same raw pointers as the original C ABI.
#![allow(clippy::missing_safety_doc)]

mod accounts;
mod filesystem;
mod logging;
mod process;
mod time;

pub use accounts::*;
pub use filesystem::*;
pub use logging::*;
pub use process::*;
pub use time::*;

use libc::{c_char, c_int};

pub(crate) fn set_errno(value: c_int) {
    unsafe {
        *errno_ptr() = value;
    }
}

pub(crate) fn errno() -> c_int {
    unsafe { *errno_ptr() }
}

unsafe fn errno_ptr() -> *mut c_int {
    #[cfg(target_os = "linux")]
    unsafe {
        libc::__errno_location()
    }
    #[cfg(any(target_os = "macos", target_os = "freebsd"))]
    unsafe {
        libc::__error()
    }
}

pub(crate) fn invalid_pointer<T>(pointer: *const T) -> bool {
    if pointer.is_null() {
        set_errno(libc::EINVAL);
        true
    } else {
        false
    }
}

// Use the host libc allocator: the existing LPStr marshaller frees these strings.
pub(crate) unsafe fn copy_string(value: *const c_char) -> *mut c_char {
    unsafe { libc::strdup(value) }
}

#[unsafe(no_mangle)]
pub extern "C" fn GetErrorCategory(error: c_int) -> c_int {
    // Migration: this PowerShell-specific mapping can be a C# switch; no P/Invoke needed.
    match error {
        libc::EINVAL => 5,
        libc::ENOENT | libc::ESRCH => 13,
        libc::EINTR => 14,
        libc::EACCES | libc::EPERM => 18,
        _ => 0,
    }
}
