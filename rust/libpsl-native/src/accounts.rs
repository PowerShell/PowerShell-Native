// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{copy_string, set_errno};
use libc::{c_char, gid_t, pid_t, uid_t};
use std::{mem::MaybeUninit, ptr};

fn initial_buffer_size(key: libc::c_int) -> usize {
    let size = unsafe { libc::sysconf(key) };
    usize::try_from(size)
        .ok()
        .filter(|size| *size > 0)
        .unwrap_or(2048)
}

fn grow_buffer(size: usize) -> Option<usize> {
    let next = size
        .checked_mul(2)
        .filter(|size| isize::try_from(*size).is_ok());
    if next.is_none() {
        set_errno(libc::ENOMEM);
    }
    next
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetPwUid(uid: uid_t) -> *mut c_char {
    // Environment.UserName resolves only the current user, not an arbitrary UID.
    let mut size = initial_buffer_size(libc::_SC_GETPW_R_SIZE_MAX);
    loop {
        let mut storage = vec![0u8; size];
        let mut entry = MaybeUninit::<libc::passwd>::uninit();
        let mut result = ptr::null_mut();
        set_errno(0);
        let error = unsafe {
            libc::getpwuid_r(
                uid,
                entry.as_mut_ptr(),
                storage.as_mut_ptr().cast(),
                storage.len(),
                &raw mut result,
            )
        };
        if error == libc::ERANGE {
            let Some(next) = grow_buffer(size) else {
                return ptr::null_mut();
            };
            size = next;
            continue;
        }
        if error != 0 {
            set_errno(error);
            return ptr::null_mut();
        }
        if result.is_null() {
            return ptr::null_mut();
        }
        return unsafe { copy_string((*result).pw_name) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetGrGid(gid: gid_t) -> *mut c_char {
    let mut size = initial_buffer_size(libc::_SC_GETGR_R_SIZE_MAX);
    loop {
        let mut storage = vec![0u8; size];
        let mut entry = MaybeUninit::<libc::group>::uninit();
        let mut result = ptr::null_mut();
        set_errno(0);
        let error = unsafe {
            libc::getgrgid_r(
                gid,
                entry.as_mut_ptr(),
                storage.as_mut_ptr().cast(),
                storage.len(),
                &raw mut result,
            )
        };
        if error == libc::ERANGE {
            let Some(next) = grow_buffer(size) else {
                return ptr::null_mut();
            };
            size = next;
            continue;
        }
        if error != 0 {
            set_errno(error);
            return ptr::null_mut();
        }
        if result.is_null() {
            return ptr::null_mut();
        }
        return unsafe { copy_string((*result).gr_name) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetUserFromPid(pid: pid_t) -> *mut c_char {
    #[cfg(target_os = "linux")]
    {
        // Preserve the original proc-directory owner contract rather than reading a UID field.
        let path = format!("/proc/{pid}\0");
        unsafe { crate::GetFileOwner(path.as_ptr().cast()) }
    }
    #[cfg(target_os = "macos")]
    {
        match crate::process::bsd_process_info(pid) {
            Ok(info) => unsafe { GetPwUid(info.pbi_uid) },
            Err(()) => ptr::null_mut(),
        }
    }
    #[cfg(target_os = "freebsd")]
    {
        match crate::process::bsd_process_info(pid) {
            Ok(info) => unsafe { GetPwUid(info.ki_uid) },
            Err(_) => ptr::null_mut(),
        }
    }
}
