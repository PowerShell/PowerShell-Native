// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{errno, invalid_pointer, set_errno};
use libc::{c_char, c_int, pid_t};
#[cfg(any(target_os = "macos", target_os = "freebsd"))]
use std::mem::MaybeUninit;
use std::ptr;

#[unsafe(no_mangle)]
pub extern "C" fn GetCurrentProcessId() -> pid_t {
    // Migration (.NET 5+): Environment.ProcessId.
    unsafe { libc::getpid() }
}

#[unsafe(no_mangle)]
pub extern "C" fn GetCurrentThreadId() -> pid_t {
    // Environment.CurrentManagedThreadId is not an OS thread ID.
    #[cfg(target_os = "linux")]
    unsafe {
        libc::syscall(libc::SYS_gettid) as pid_t
    }
    #[cfg(target_os = "macos")]
    {
        let mut id = 0u64;
        let error = unsafe { libc::pthread_threadid_np(0, &raw mut id) };
        if error != 0 {
            set_errno(error);
            return 0;
        }
        id as pid_t
    }
    #[cfg(target_os = "freebsd")]
    unsafe {
        libc::pthread_getthreadid_np()
    }
}

#[cfg(target_os = "macos")]
pub(crate) fn bsd_process_info(pid: pid_t) -> Result<libc::proc_bsdinfo, ()> {
    let mut info = MaybeUninit::<libc::proc_bsdinfo>::uninit();
    let length =
        c_int::try_from(size_of::<libc::proc_bsdinfo>()).expect("proc_bsdinfo size fits int");
    let result = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDTBSDINFO,
            0,
            info.as_mut_ptr().cast(),
            length,
        )
    };
    if result != length {
        if result >= 0 {
            set_errno(libc::ESRCH);
        }
        return Err(());
    }
    Ok(unsafe { info.assume_init() })
}

#[cfg(target_os = "freebsd")]
pub(crate) fn bsd_process_info(pid: pid_t) -> Result<libc::kinfo_proc, ()> {
    let mut mib = [libc::CTL_KERN, libc::KERN_PROC, libc::KERN_PROC_PID, pid];
    let mut info = MaybeUninit::<libc::kinfo_proc>::uninit();
    let mut length = size_of::<libc::kinfo_proc>();
    let result = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            mib.len() as u32,
            info.as_mut_ptr().cast(),
            &mut length,
            ptr::null_mut(),
            0,
        )
    };
    if result != 0 || length == 0 {
        if result == 0 {
            set_errno(libc::ESRCH);
        }
        return Err(());
    }
    Ok(unsafe { info.assume_init() })
}

#[unsafe(no_mangle)]
pub extern "C" fn GetPPid(pid: pid_t) -> pid_t {
    #[cfg(target_os = "macos")]
    {
        bsd_process_info(pid).map_or(-1, |info| info.pbi_ppid as pid_t)
    }
    #[cfg(target_os = "freebsd")]
    {
        bsd_process_info(pid).map_or(-1, |info| info.ki_ppid)
    }
    #[cfg(target_os = "linux")]
    {
        // The original Linux implementation returns UINT_MAX for every PID.
        let _ = pid;
        -1
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn KillProcess(pid: pid_t) -> bool {
    // Migration: Process.GetProcessById(pid).Kill() for positive, individual PIDs.
    // Keep kill() for zero/negative process-group selectors and errno semantics.
    unsafe { libc::kill(pid, libc::SIGKILL) == 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn WaitPid(pid: pid_t, nohang: bool) -> pid_t {
    // Migration: Process.WaitForExit[Async] for processes owned by System.Diagnostics.
    // Do not mix .NET's reaper with waitpid() for the same child.
    unsafe { libc::waitpid(pid, ptr::null_mut(), if nohang { libc::WNOHANG } else { 0 }) }
}

fn retry(mut call: impl FnMut() -> c_int) -> c_int {
    loop {
        let result = call();
        if result >= 0 || errno() != libc::EINTR {
            return result;
        }
    }
}

fn close(fd: c_int) {
    if fd >= 0 {
        // Do not retry close after EINTR: the descriptor may already have been reused.
        unsafe { libc::close(fd) };
    }
}

fn pipe(fds: &mut [c_int; 2]) -> c_int {
    #[cfg(target_os = "linux")]
    let result = retry(|| unsafe { libc::pipe2(fds.as_mut_ptr(), libc::O_CLOEXEC) });
    #[cfg(not(target_os = "linux"))]
    let result = retry(|| unsafe { libc::pipe(fds.as_mut_ptr()) });
    if result < 0 {
        return -1;
    }
    for fd in fds.iter_mut() {
        // Keep pipe FDs clear of stdin/out/err, including when those were closed.
        if *fd <= libc::STDERR_FILENO {
            let duplicate = retry(|| unsafe { libc::fcntl(*fd, libc::F_DUPFD_CLOEXEC, 3) });
            if duplicate < 0 {
                let error = errno();
                close(fds[0]);
                close(fds[1]);
                *fds = [-1, -1];
                set_errno(error);
                return -1;
            }
            close(*fd);
            *fd = duplicate;
        }
        #[cfg(not(target_os = "linux"))]
        if retry(|| unsafe { libc::fcntl(*fd, libc::F_SETFD, libc::FD_CLOEXEC) }) < 0 {
            let error = errno();
            close(fds[0]);
            close(fds[1]);
            *fds = [-1, -1];
            set_errno(error);
            return -1;
        }
    }
    0
}

#[allow(clippy::too_many_arguments)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ForkAndExecProcess(
    filename: *const c_char,
    argv: *const *const c_char,
    envp: *const *const c_char,
    cwd: *const c_char,
    redirectStdin: c_int,
    redirectStdout: c_int,
    redirectStderr: c_int,
    creationFlags: c_int,
    childPid: *mut c_int,
    stdinFd: *mut c_int,
    stdoutFd: *mut c_int,
    stderrFd: *mut c_int,
) -> c_int {
    // Migration: Process.Start(ProcessStartInfo) for ordinary launches/redirection.
    // No managed equivalent preserves the child-only SUPPRESS_PROCESS_SIGINT flag.
    for output in [childPid, stdinFd, stdoutFd, stderrFd] {
        if !output.is_null() {
            unsafe { output.write(-1) };
        }
    }
    if invalid_pointer(filename)
        || invalid_pointer(argv)
        || invalid_pointer(envp)
        || [childPid, stdinFd, stdoutFd, stderrFd]
            .iter()
            .any(|p| invalid_pointer(*p))
    {
        return -1;
    }
    if [redirectStdin, redirectStdout, redirectStderr]
        .iter()
        .any(|flag| *flag & !1 != 0)
    {
        set_errno(libc::EINVAL);
        return -1;
    }
    if unsafe { libc::access(filename, libc::X_OK) } != 0 {
        return -1;
    }

    let mut pipes = [[-1; 2]; 3];
    for (index, redirect) in [redirectStdin, redirectStdout, redirectStderr]
        .iter()
        .enumerate()
    {
        if *redirect != 0 && pipe(&mut pipes[index]) != 0 {
            let error = errno();
            for pair in pipes {
                close(pair[0]);
                close(pair[1]);
            }
            set_errno(error);
            return -1;
        }
    }

    let mut action: libc::sigaction = unsafe { std::mem::zeroed() };
    action.sa_sigaction = libc::SIG_IGN;
    unsafe { libc::sigemptyset(&raw mut action.sa_mask) };
    let pid = unsafe { libc::fork() };
    if pid == 0 {
        // After fork, use only async-signal-safe libc calls; no allocation, locks,
        // panicking, destructors, or return to the managed/Rust runtime.
        for (pair, target) in [
            (pipes[0], libc::STDIN_FILENO),
            (pipes[1], libc::STDOUT_FILENO),
            (pipes[2], libc::STDERR_FILENO),
        ] {
            let source = if target == libc::STDIN_FILENO {
                pair[0]
            } else {
                pair[1]
            };
            if source >= 0 && retry(|| unsafe { libc::dup2(source, target) }) < 0 {
                unsafe { libc::_exit(if errno() != 0 { errno() } else { 1 }) };
            }
        }
        if !cwd.is_null() && retry(|| unsafe { libc::chdir(cwd) }) < 0 {
            unsafe { libc::_exit(if errno() != 0 { errno() } else { 1 }) };
        }
        if creationFlags & 1 != 0
            && unsafe { libc::sigaction(libc::SIGINT, &raw const action, ptr::null_mut()) } < 0
        {
            unsafe { libc::_exit(if errno() != 0 { errno() } else { 1 }) };
        }
        unsafe {
            libc::execve(filename, argv, envp);
            libc::_exit(if errno() != 0 { errno() } else { 1 });
        }
    }

    let error = errno();
    close(pipes[0][0]);
    close(pipes[1][1]);
    close(pipes[2][1]);
    if pid < 0 {
        close(pipes[0][1]);
        close(pipes[1][0]);
        close(pipes[2][0]);
        set_errno(error);
        return -1;
    }
    unsafe {
        childPid.write(pid);
        stdinFd.write(pipes[0][1]);
        stdoutFd.write(pipes[1][0]);
        stderrFd.write(pipes[2][0]);
    }
    0
}
