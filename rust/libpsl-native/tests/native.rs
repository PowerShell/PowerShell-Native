// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#![cfg(unix)]
#![allow(clippy::unnecessary_cast)] // libc typedef widths differ between target platforms.

use psl_native::*;
use std::ffi::{CStr, CString};
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};

// Concurrent first forks can crash macOS libSystem's child-side initialization.
#[cfg(target_os = "macos")]
static FORK_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

struct Fixture(PathBuf);

impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let directory = std::env::temp_dir().join(format!(
            "psl-rust-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&directory).unwrap();
        Self(directory)
    }

    fn path(&self, name: &str) -> PathBuf {
        self.0.join(name)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

fn path(value: &Path) -> CString {
    CString::new(value.as_os_str().as_bytes()).unwrap()
}

unsafe fn take_string(value: *mut libc::c_char) -> String {
    assert!(!value.is_null(), "native string lookup failed");
    let string = unsafe { CStr::from_ptr(value) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { libc::free(value.cast()) };
    string
}

fn last_errno() -> libc::c_int {
    std::io::Error::last_os_error().raw_os_error().unwrap()
}

#[test]
fn common_stat_layout_matches_c_abi() {
    assert_eq!(size_of::<CommonStat>(), 112);
    assert_eq!(std::mem::offset_of!(CommonStat, Inode), 0);
    assert_eq!(std::mem::offset_of!(CommonStat, Size), 24);
    assert_eq!(std::mem::offset_of!(CommonStat, DeviceId), 64);
    assert_eq!(std::mem::offset_of!(CommonStat, IsSticky), 108);
    assert_eq!(size_of::<PrivateTm>(), 36);
    assert_eq!(align_of::<PrivateTm>(), 4);
}

#[test]
// Check the legacy ABI's deliberately signed/truncated metadata against libc.
#[allow(clippy::cast_sign_loss, clippy::cast_possible_truncation)]
fn metadata_links_and_identity() {
    let f = Fixture::new();
    let file = f.path("file");
    fs::write(&file, b"native test").unwrap();
    fs::set_permissions(&file, fs::Permissions::from_mode(0o751)).unwrap();
    let file_c = path(&file);
    let hard = path(&f.path("hard"));
    let link = path(&f.path("link"));
    unsafe {
        assert_eq!(CreateHardLink(hard.as_ptr(), file_c.as_ptr()), 0);
        assert_eq!(CreateSymLink(link.as_ptr(), file_c.as_ptr()), 0);
        assert!(IsSameFileSystemItem(file_c.as_ptr(), hard.as_ptr()));
        assert!(IsSameFileSystemItem(file_c.as_ptr(), link.as_ptr()));
        assert!(IsFile(file_c.as_ptr()));
        assert!(!IsDirectory(file_c.as_ptr()));
        assert!(!IsSymLink(hard.as_ptr()));
        assert!(IsSymLink(link.as_ptr()));
        assert!(IsExecutable(file_c.as_ptr()));
        assert!(!IsSameFileSystemItem(
            file_c.as_ptr(),
            c"/nonexistent/psl-rust".as_ptr()
        ));

        let mut stat = CommonStat::default();
        assert_eq!(GetCommonStat(link.as_ptr(), &raw mut stat), 0);
        let metadata = fs::metadata(&file).unwrap();
        assert_eq!(stat.Inode as u64, metadata.ino());
        assert_eq!(stat.Mode as u32, metadata.mode());
        assert_eq!(stat.UserId as u32, metadata.uid());
        assert_eq!(stat.GroupId as u32, metadata.gid());
        assert_eq!(stat.HardlinkCount, 2);
        assert_eq!(stat.Size, 11);
        assert_eq!(stat.AccessTime, metadata.atime());
        assert_eq!(stat.ModifiedTime, metadata.mtime());
        assert_eq!(stat.ChangeTime, metadata.ctime());
        assert_eq!(stat.BlockSize as u64, metadata.blksize());
        assert_eq!(stat.DeviceId, metadata.dev() as i32);
        assert_eq!(stat.NumberOfBlocks as u64, metadata.blocks());
        assert_eq!(stat.IsFile, 1);
        assert_eq!(stat.IsSymbolicLink, 0);
        assert_eq!(GetCommonLStat(link.as_ptr(), &raw mut stat), 0);
        assert_eq!(stat.IsFile, 0);
        assert_eq!(stat.IsSymbolicLink, 1);
        assert_eq!(stat.HardlinkCount, 1);

        let mut device = 0;
        let mut inode = 0;
        assert_eq!(
            GetInodeData(link.as_ptr(), &raw mut device, &raw mut inode),
            0
        );
        assert_eq!(device, metadata.dev());
        assert_eq!(inode, metadata.ino());
        let mut count = 0;
        assert_eq!(GetLinkCount(file_c.as_ptr(), &raw mut count), 0);
        assert_eq!(count, 2);
        assert_eq!(GetLinkCount(link.as_ptr(), &raw mut count), 0);
        assert_eq!(count, 1);
        assert_eq!(
            take_string(FollowSymLink(link.as_ptr())),
            fs::canonicalize(file).unwrap().to_str().unwrap()
        );
        assert!(FollowSymLink(file_c.as_ptr()).is_null());

        let mut native = std::mem::MaybeUninit::uninit();
        assert_eq!(GetStat(file_c.as_ptr(), native.as_mut_ptr()), 0);
        assert_eq!(native.assume_init().st_ino as u64, metadata.ino());
        assert_eq!(GetLStat(link.as_ptr(), native.as_mut_ptr()), 0);
        assert_eq!(native.assume_init().st_mode & libc::S_IFMT, libc::S_IFLNK);
    }
}

#[test]
fn directories_dangling_links_special_entries_and_errors() {
    let f = Fixture::new();
    let root = path(&f.0);
    let dangling = path(&f.path("dangling"));
    let directory_link = path(&f.path("directory-link"));
    let missing = path(&f.path("missing"));
    let fifo = path(&f.path("fifo"));
    unsafe {
        assert!(IsFile(root.as_ptr()));
        assert!(IsDirectory(root.as_ptr()));
        assert_eq!(CreateSymLink(directory_link.as_ptr(), root.as_ptr()), 0);
        assert!(IsDirectory(directory_link.as_ptr()));
        assert_eq!(CreateSymLink(dangling.as_ptr(), c"missing".as_ptr()), 0);
        assert!(IsFile(dangling.as_ptr()));
        assert!(IsSymLink(dangling.as_ptr()));
        assert!(!IsDirectory(dangling.as_ptr()));
        assert_eq!(take_string(FollowSymLink(dangling.as_ptr())), "missing");
        assert_eq!(libc::mkfifo(fifo.as_ptr(), 0o600), 0);
        assert!(IsFile(fifo.as_ptr()));
        let mut stat = CommonStat::default();
        assert_eq!(GetCommonStat(fifo.as_ptr(), &raw mut stat), 0);
        assert_eq!(stat.IsNamedPipe, 1);
        assert_eq!(stat.IsFile, 0);
        assert!(!IsFile(missing.as_ptr()));
        assert_eq!(last_errno(), libc::ENOENT);
        assert_eq!(GetCommonStat(missing.as_ptr(), &raw mut stat), -1);
        assert_eq!(last_errno(), libc::ENOENT);
        assert_eq!(GetCommonLStat(missing.as_ptr(), &raw mut stat), -1);
        assert_eq!(last_errno(), libc::ENOENT);
        let mut count = 42;
        assert_eq!(GetLinkCount(missing.as_ptr(), &raw mut count), -1);
        assert_eq!(count, 42);
        assert_eq!(GetCommonStat(root.as_ptr(), ptr::null_mut()), -1);
        assert_eq!(last_errno(), libc::EINVAL);
        assert_eq!(CreateHardLink(ptr::null(), root.as_ptr()), -1);
        assert_eq!(last_errno(), libc::EINVAL);
        assert_eq!(SetDate(ptr::null()), -1);
        assert_eq!(last_errno(), libc::EINVAL);
    }
}

#[test]
fn canonicalization_includes_parent_symlinks_and_raw_fallback() {
    let f = Fixture::new();
    fs::create_dir(f.path("directory")).unwrap();
    fs::write(f.path("directory/file"), b"content").unwrap();
    symlink("directory", f.path("parent")).unwrap();
    symlink("file", f.path("directory/link")).unwrap();
    symlink("not-there", f.path("directory/dangling")).unwrap();
    let long_target = "a".repeat(900);
    symlink(&long_target, f.path("long-dangling")).unwrap();
    unsafe {
        assert_eq!(
            take_string(FollowSymLink(path(&f.path("parent/link")).as_ptr())),
            fs::canonicalize(f.path("directory/file"))
                .unwrap()
                .to_str()
                .unwrap()
        );
        assert_eq!(
            take_string(FollowSymLink(path(&f.path("parent/dangling")).as_ptr())),
            "not-there"
        );
        assert_eq!(
            take_string(FollowSymLink(path(&f.path("long-dangling")).as_ptr())),
            long_target
        );
    }
}

#[test]
fn account_lookup_host_and_thread_identity() {
    let fixture = Fixture::new();
    let owned_file = fixture.path("owner");
    fs::write(&owned_file, "").unwrap();
    unsafe {
        let user = take_string(GetPwUid(libc::getuid()));
        assert_ne!(user, "");
        assert_ne!(take_string(GetGrGid(libc::getgid())), "");
        assert_eq!(
            take_string(GetFileOwner(path(&owned_file).as_ptr())),
            take_string(GetPwUid(fs::metadata(&owned_file).unwrap().uid()))
        );
        assert_eq!(
            take_string(GetUserFromPid(libc::getpid())),
            take_string(GetPwUid(libc::geteuid()))
        );
        assert_ne!(take_string(GetComputerName()), "");
        assert_eq!(GetCurrentProcessId(), libc::getpid());
        assert_ne!(GetCurrentThreadId(), 0);
        #[cfg(target_os = "linux")]
        {
            assert_eq!(
                libc::c_long::from(GetCurrentThreadId()),
                libc::syscall(libc::SYS_gettid)
            );
            assert_eq!(GetPPid(libc::getpid()), -1);
        }
        #[cfg(any(target_os = "macos", target_os = "freebsd"))]
        assert_eq!(GetPPid(libc::getpid()), libc::getppid());
    }
}

#[test]
fn error_category_mapping() {
    for (error, category) in [
        (libc::EINVAL, 5),
        (libc::ENOENT, 13),
        (libc::ESRCH, 13),
        (libc::EINTR, 14),
        (libc::EACCES, 18),
        (libc::EPERM, 18),
        (libc::EBUSY, 0),
        (0, 0),
    ] {
        assert_eq!(GetErrorCategory(error), category);
    }
}

unsafe fn spawn(args: &[&CStr], cwd: Option<&CStr>, flags: i32) -> (i32, i32, i32, i32) {
    #[cfg(target_os = "macos")]
    let _fork_guard = FORK_LOCK.lock().unwrap();
    let mut pointers: Vec<_> = args.iter().map(|arg| arg.as_ptr()).collect();
    pointers.push(ptr::null());
    let env = [c"PSL_RUST_TEST=present".as_ptr(), ptr::null()];
    let mut pid = -1;
    let mut input = -1;
    let mut output = -1;
    let mut error = -1;
    assert_eq!(
        unsafe {
            ForkAndExecProcess(
                c"/bin/sh".as_ptr(),
                pointers.as_ptr(),
                env.as_ptr(),
                cwd.map_or(ptr::null(), CStr::as_ptr),
                1,
                1,
                1,
                flags,
                &raw mut pid,
                &raw mut input,
                &raw mut output,
                &raw mut error,
            )
        },
        0,
        "spawn failed: {}",
        std::io::Error::last_os_error()
    );
    (pid, input, output, error)
}

unsafe fn read_fd(fd: i32) -> String {
    use std::io::Read;
    use std::os::fd::FromRawFd;
    let mut file = unsafe { fs::File::from_raw_fd(fd) };
    let mut text = String::new();
    file.read_to_string(&mut text).unwrap();
    text
}

#[test]
fn spawning_redirection_environment_and_working_directory() {
    let fixture = Fixture::new();
    let directory = path(&fixture.0);
    unsafe {
        let (pid, input, output, error) = spawn(
            &[c"sh", c"-c", c"read value; printf '%s:%s\\n' \"$value\" \"$PSL_RUST_TEST\"; pwd; printf 'stderr' >&2"],
            Some(&directory), 0,
        );
        assert_eq!(libc::write(input, c"stdin\n".as_ptr().cast(), 6), 6);
        libc::close(input);
        let text = read_fd(output);
        assert!(text.starts_with("stdin:present\n"));
        assert!(text.contains(fixture.0.file_name().unwrap().to_str().unwrap()));
        assert_eq!(read_fd(error), "stderr");
        assert_eq!(WaitPid(pid, false), pid);
        assert_eq!(WaitPid(pid, true), -1);
        assert_eq!(last_errno(), libc::ECHILD);
    }
}

#[test]
fn child_only_sigint_suppression() {
    unsafe {
        let mut before: libc::sigaction = std::mem::zeroed();
        assert_eq!(
            libc::sigaction(libc::SIGINT, ptr::null(), &raw mut before),
            0
        );
        // A child inheriting SIG_IGN must survive its own SIGINT.
        let (pid, input, output, error) =
            spawn(&[c"sh", c"-c", c"kill -INT $$; printf survived"], None, 1);
        libc::close(input);
        let text = read_fd(output);
        let diagnostic = read_fd(error);
        let mut status = 0;
        assert_eq!(libc::waitpid(pid, &raw mut status, 0), pid);
        assert!(
            libc::WIFEXITED(status),
            "child terminated abnormally (wait status {status:#x}): {diagnostic}"
        );
        assert_eq!(libc::WEXITSTATUS(status), 0, "{diagnostic}");
        assert_eq!(text, "survived");
        assert_eq!(diagnostic, "");
        let mut after: libc::sigaction = std::mem::zeroed();
        assert_eq!(
            libc::sigaction(libc::SIGINT, ptr::null(), &raw mut after),
            0
        );
        assert_eq!(before.sa_sigaction, after.sa_sigaction);
        assert_eq!(before.sa_flags, after.sa_flags);
    }
}

#[test]
fn failed_exec_exits_without_returning_into_the_host() {
    #[cfg(target_os = "macos")]
    let _fork_guard = FORK_LOCK.lock().unwrap();
    let fixture = Fixture::new();
    let invalid_program = fixture.path("not-an-executable-image");
    fs::write(&invalid_program, b"not an executable").unwrap();
    fs::set_permissions(&invalid_program, fs::Permissions::from_mode(0o700)).unwrap();
    let filename = path(&invalid_program);
    let argv = [filename.as_ptr(), ptr::null()];
    let env = [ptr::null()];
    unsafe {
        let mut pid = -1;
        let mut input = -1;
        let mut output = -1;
        let mut error = -1;
        assert_eq!(
            ForkAndExecProcess(
                filename.as_ptr(),
                argv.as_ptr(),
                env.as_ptr(),
                ptr::null(),
                0,
                0,
                0,
                0,
                &raw mut pid,
                &raw mut input,
                &raw mut output,
                &raw mut error,
            ),
            0
        );
        assert!(pid > 0);
        assert_eq!((input, output, error), (-1, -1, -1));
        let mut status = 0;
        assert_eq!(libc::waitpid(pid, &raw mut status, 0), pid);
        assert!(
            libc::WIFEXITED(status),
            "child terminated abnormally (wait status {status:#x})"
        );
        assert_eq!(libc::WEXITSTATUS(status), libc::ENOEXEC);
    }
}

#[test]
fn nonblocking_wait_and_kill() {
    unsafe {
        let (pid, input, output, error) = spawn(&[c"sh", c"-c", c"read value"], None, 0);
        assert_eq!(WaitPid(pid, true), 0);
        assert!(KillProcess(pid));
        assert_eq!(WaitPid(pid, false), pid);
        libc::close(input);
        assert_eq!(read_fd(output), "");
        assert_eq!(read_fd(error), "");
    }
}

#[test]
fn invalid_spawn_initializes_available_outputs() {
    unsafe {
        let mut pid = 123;
        let mut input = 123;
        let mut output = 123;
        let mut error = 123;
        assert_eq!(
            ForkAndExecProcess(
                ptr::null(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                0,
                0,
                0,
                0,
                &raw mut pid,
                &raw mut input,
                &raw mut output,
                &raw mut error,
            ),
            -1
        );
        assert_eq!(last_errno(), libc::EINVAL);
        assert_eq!((pid, input, output, error), (-1, -1, -1, -1));
    }
}

#[test]
fn native_logging_accepts_literal_format_characters() {
    unsafe {
        Native_OpenLog(c"psl-native-rust-test".as_ptr(), libc::LOG_USER);
        Native_SysLog(libc::LOG_DEBUG, c"literal 100% %s %n".as_ptr());
        Native_CloseLog();
    }
}
