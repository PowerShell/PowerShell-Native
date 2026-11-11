// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{copy_string, invalid_pointer, set_errno};
use libc::{c_char, c_int, stat};
use std::mem::MaybeUninit;
use std::ptr;

#[repr(C)]
#[derive(Debug, Default)]
pub struct CommonStat {
    pub Inode: i64,
    pub Mode: c_int,
    pub UserId: c_int,
    pub GroupId: c_int,
    pub HardlinkCount: c_int,
    pub Size: i64,
    pub AccessTime: i64,
    pub ModifiedTime: i64,
    pub ChangeTime: i64,
    pub BlockSize: i64,
    pub DeviceId: c_int,
    pub NumberOfBlocks: c_int,
    pub IsDirectory: c_int,
    pub IsFile: c_int,
    pub IsSymbolicLink: c_int,
    pub IsBlockDevice: c_int,
    pub IsCharacterDevice: c_int,
    pub IsNamedPipe: c_int,
    pub IsSocket: c_int,
    pub IsSetUid: c_int,
    pub IsSetGid: c_int,
    pub IsSticky: c_int,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetStat(path: *const c_char, buffer: *mut stat) -> c_int {
    if invalid_pointer(path) || invalid_pointer(buffer) {
        return -1;
    }
    set_errno(0);
    unsafe { libc::stat(path, buffer) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetLStat(path: *const c_char, buffer: *mut stat) -> c_int {
    if invalid_pointer(path) || invalid_pointer(buffer) {
        return -1;
    }
    set_errno(0);
    unsafe { libc::lstat(path, buffer) }
}

pub(crate) unsafe fn read_stat(path: *const c_char, follow: bool) -> Result<stat, c_int> {
    let mut buffer = MaybeUninit::uninit();
    let result = if follow {
        unsafe { GetStat(path, buffer.as_mut_ptr()) }
    } else {
        unsafe { GetLStat(path, buffer.as_mut_ptr()) }
    };
    if result == 0 {
        Ok(unsafe { buffer.assume_init() })
    } else {
        Err(result)
    }
}

// The fixed legacy ABI deliberately narrows/reinterprets native metadata fields.
#[allow(
    clippy::unnecessary_cast,
    clippy::cast_lossless,
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap
)]
fn common_stat(st: &stat) -> CommonStat {
    let kind = st.st_mode & libc::S_IFMT;
    CommonStat {
        Inode: st.st_ino as i64,
        Mode: st.st_mode as c_int,
        UserId: st.st_uid as c_int,
        GroupId: st.st_gid as c_int,
        HardlinkCount: st.st_nlink as c_int,
        Size: st.st_size,
        AccessTime: st.st_atime,
        ModifiedTime: st.st_mtime,
        ChangeTime: st.st_ctime,
        BlockSize: st.st_blksize as i64,
        DeviceId: st.st_dev as c_int,
        NumberOfBlocks: st.st_blocks as c_int,
        IsDirectory: c_int::from(kind == libc::S_IFDIR),
        IsFile: c_int::from(kind == libc::S_IFREG),
        IsSymbolicLink: c_int::from(kind == libc::S_IFLNK),
        IsBlockDevice: c_int::from(kind == libc::S_IFBLK),
        IsCharacterDevice: c_int::from(kind == libc::S_IFCHR),
        IsNamedPipe: c_int::from(kind == libc::S_IFIFO),
        IsSocket: c_int::from(kind == libc::S_IFSOCK),
        // Preserve the original ABI's equality tests, including combined flags.
        IsSetUid: c_int::from(st.st_mode & 0xE00 == libc::S_ISUID),
        IsSetGid: c_int::from(st.st_mode & 0xE00 == libc::S_ISGID),
        IsSticky: c_int::from(st.st_mode & 0xE00 == libc::S_ISVTX),
    }
}

unsafe fn get_common(path: *const c_char, output: *mut CommonStat, follow: bool) -> c_int {
    if invalid_pointer(output) {
        return -1;
    }
    match unsafe { read_stat(path, follow) } {
        Ok(st) => {
            unsafe { output.write(common_stat(&st)) };
            0
        }
        Err(result) => result,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetCommonStat(path: *const c_char, output: *mut CommonStat) -> c_int {
    // Migration: FileInfo and File.GetUnixFileMode cover only part of this metadata.
    unsafe { get_common(path, output, true) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetCommonLStat(path: *const c_char, output: *mut CommonStat) -> c_int {
    unsafe { get_common(path, output, false) }
}

#[unsafe(no_mangle)]
#[allow(clippy::unnecessary_cast, clippy::cast_sign_loss)] // Preserve the native dev_t bit pattern, including signed macOS device IDs.
pub unsafe extern "C" fn GetInodeData(
    path: *const c_char,
    device: *mut u64,
    inode: *mut u64,
) -> c_int {
    if invalid_pointer(device) || invalid_pointer(inode) {
        return -1;
    }
    match unsafe { read_stat(path, true) } {
        Ok(st) => {
            unsafe {
                device.write(st.st_dev as u64);
                inode.write(st.st_ino as u64);
            }
            0
        }
        Err(result) => result,
    }
}

#[unsafe(no_mangle)]
#[allow(
    clippy::unnecessary_cast,
    clippy::cast_lossless,
    clippy::cast_possible_truncation,
    clippy::cast_possible_wrap
)] // The legacy API returns a C int, even when nlink_t is wider.
pub unsafe extern "C" fn GetLinkCount(path: *const c_char, count: *mut c_int) -> c_int {
    if invalid_pointer(count) {
        return -1;
    }
    match unsafe { read_stat(path, false) } {
        Ok(st) => {
            unsafe { count.write(st.st_nlink as c_int) };
            0
        }
        Err(result) => result,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn IsFile(path: *const c_char) -> bool {
    // Migration (.NET 7+): Path.Exists(path), NOT File.Exists; includes dangling links.
    unsafe { read_stat(path, false).is_ok() }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn IsDirectory(path: *const c_char) -> bool {
    // Migration: Directory.Exists(path) follows links to directories.
    unsafe { read_stat(path, true) }.is_ok_and(|st| st.st_mode & libc::S_IFMT == libc::S_IFDIR)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn IsSymLink(path: *const c_char) -> bool {
    // Migration (.NET 6+): FileSystemInfo.LinkTarget != null; handle I/O errors.
    unsafe { read_stat(path, false) }.is_ok_and(|st| st.st_mode & libc::S_IFMT == libc::S_IFLNK)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn IsExecutable(path: *const c_char) -> bool {
    // File.GetUnixFileMode is not equivalent to access(X_OK), which also checks ACLs.
    !invalid_pointer(path) && unsafe { libc::access(path, libc::X_OK) == 0 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn IsSameFileSystemItem(first: *const c_char, second: *const c_char) -> bool {
    let Ok(a) = (unsafe { read_stat(first, true) }) else {
        return false;
    };
    let Ok(b) = (unsafe { read_stat(second, true) }) else {
        return false;
    };
    a.st_dev == b.st_dev && a.st_ino == b.st_ino
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn CreateHardLink(link: *const c_char, target: *const c_char) -> c_int {
    // Migration (.NET 11+): File.CreateHardLink(link, target).
    if invalid_pointer(link) || invalid_pointer(target) {
        return -1;
    }
    unsafe { libc::link(target, link) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn CreateSymLink(link: *const c_char, target: *const c_char) -> c_int {
    // Migration (.NET 6+): File.CreateSymbolicLink or Directory.CreateSymbolicLink.
    if invalid_pointer(link) || invalid_pointer(target) {
        return -1;
    }
    set_errno(0);
    unsafe { libc::symlink(target, link) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn FollowSymLink(path: *const c_char) -> *mut c_char {
    // Migration (.NET 6+): ResolveLinkTarget(path, true) and LinkTarget for most uses.
    // Exact realpath canonicalization + raw readlink fallback differs from that API.
    if !unsafe { IsSymLink(path) } {
        return ptr::null_mut();
    }
    let resolved = unsafe { libc::realpath(path, ptr::null_mut()) };
    if !resolved.is_null() {
        return resolved;
    }
    let mut size = 256usize;
    loop {
        let output = unsafe { libc::malloc(size + 1) }.cast::<c_char>();
        if output.is_null() {
            set_errno(libc::ENOMEM);
            return output;
        }
        let length = unsafe { libc::readlink(path, output, size) };
        if length < 0 {
            let error = crate::errno();
            unsafe { libc::free(output.cast()) };
            set_errno(error);
            return ptr::null_mut();
        }
        let length = length.unsigned_abs();
        if length < size {
            unsafe { output.add(length).write(0) };
            return output;
        }
        unsafe { libc::free(output.cast()) };
        let Some(next) = size
            .checked_mul(2)
            .filter(|n| *n <= isize::MAX as usize / 2)
        else {
            set_errno(libc::ENAMETOOLONG);
            return ptr::null_mut();
        };
        size = next;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn GetFileOwner(path: *const c_char) -> *mut c_char {
    match unsafe { read_stat(path, true) } {
        Ok(st) => unsafe { crate::GetPwUid(st.st_uid) },
        Err(_) => ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn GetComputerName() -> *mut c_char {
    // Migration: Dns.GetHostName(); Environment.MachineName drops the Unix domain suffix.
    let mut size = 256usize;
    loop {
        let mut buffer = vec![0 as c_char; size];
        set_errno(0);
        if unsafe { libc::gethostname(buffer.as_mut_ptr(), size) } == 0 && buffer.contains(&0) {
            return unsafe { copy_string(buffer.as_ptr()) };
        }
        let error = crate::errno();
        if error != 0 && error != libc::ENAMETOOLONG && error != libc::EINVAL {
            return ptr::null_mut();
        }
        if size >= 1024 * 1024 {
            set_errno(libc::ENAMETOOLONG);
            return ptr::null_mut();
        }
        size *= 2;
    }
}
