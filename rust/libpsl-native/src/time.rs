// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{invalid_pointer, set_errno};
use libc::c_int;

#[repr(C, packed(4))]
#[derive(Clone, Copy, Default)]
pub struct PrivateTm {
    pub Seconds: i32,
    pub Minutes: i32,
    pub Hour: i32,
    pub DayOfMonth: i32,
    pub Month: i32,
    pub Year: i32,
    pub DayOfWeek: i32,
    pub DayInYear: i32,
    pub IsDst: i32,
}

pub(crate) fn time_value(time: PrivateTm) -> Result<libc::timeval, ()> {
    let mut native: libc::tm = unsafe { std::mem::zeroed() };
    native.tm_sec = time.Seconds;
    native.tm_min = time.Minutes;
    native.tm_hour = time.Hour;
    native.tm_mday = time.DayOfMonth;
    native.tm_mon = time.Month;
    native.tm_year = time.Year;
    native.tm_wday = time.DayOfWeek;
    native.tm_yday = time.DayInYear;
    native.tm_isdst = time.IsDst;
    let seconds = unsafe { libc::mktime(&raw mut native) };
    if seconds == -1 {
        if crate::errno() == 0 {
            set_errno(libc::EOVERFLOW);
        }
        return Err(());
    }
    Ok(libc::timeval {
        tv_sec: seconds,
        tv_usec: 0,
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn SetDate(time: *const PrivateTm) -> c_int {
    if invalid_pointer(time) {
        return -1;
    }
    set_errno(0);
    // Preserve local-time/DST conversion without changing the process-wide locale.
    match time_value(unsafe { time.read_unaligned() }) {
        Ok(value) => unsafe { libc::settimeofday(&raw const value, std::ptr::null()) },
        Err(()) => -1,
    }
}
