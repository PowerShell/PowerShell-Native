// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

// Independent caller: all function pointer types come from the original headers.
#include <sys/time.h>
#include <syslog.h>
#include <unistd.h>
#include <dlfcn.h>
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <cstddef>
#include "createhardlink.h"
#include "createsymlink.h"
#include "followsymlink.h"
#include "createprocess.h"
#include "getcommonstat.h"
#include "getcommonlstat.h"
#include "getcomputername.h"
#include "getcurrentprocessorid.h"
#include "getcurrentthreadid.h"
#include "geterrorcategory.h"
#include "getfileowner.h"
#include "getgrgid.h"
#include "getinodedata.h"
#include "getlinkcount.h"
#include "getlstat.h"
#include "getppid.h"
#include "getpwuid.h"
#include "getstat.h"
#include "getuserfrompid.h"
#include "isdirectory.h"
#include "isexecutable.h"
#include "isfile.h"
#include "issamefilesystemitem.h"
#include "issymlink.h"
#include "killprocess.h"
#include "nativesyslog.h"
#include "setdate.h"
#include "waitpid.h"

template<typename T> T symbol(void* library, const char* name)
{
    dlerror();
    void* address = dlsym(library, name);
    const char* error = dlerror();
    if (error != nullptr) {
        std::fprintf(stderr, "%s: %s\n", name, error);
        abort();
    }
    return reinterpret_cast<T>(address);
}

#define LOAD(name) auto name = symbol<decltype(&::name)>(library, #name); (void)name

int main(int argc, char** argv)
{
    static_assert(sizeof(CommonStat) == 112, "CommonStat size");
    static_assert(offsetof(CommonStat, DeviceId) == 64, "CommonStat device");
    static_assert(offsetof(CommonStat, IsSticky) == 108, "CommonStat flags");
    static_assert(sizeof(private_tm) == 36, "private_tm size");
    assert(argc == 2);
    void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (library == nullptr) {
        std::fprintf(stderr, "%s\n", dlerror());
        return 1;
    }
    LOAD(CreateHardLink);
    LOAD(CreateSymLink);
    LOAD(FollowSymLink);
    LOAD(ForkAndExecProcess);
    LOAD(GetCommonStat);
    LOAD(GetCommonLStat);
    LOAD(GetComputerName);
    LOAD(GetCurrentProcessId);
    LOAD(GetCurrentThreadId);
    LOAD(GetErrorCategory);
    LOAD(GetFileOwner);
    LOAD(GetGrGid);
    LOAD(GetInodeData);
    LOAD(GetLinkCount);
    LOAD(GetLStat);
    LOAD(GetPPid);
    LOAD(GetPwUid);
    LOAD(GetStat);
    LOAD(GetUserFromPid);
    LOAD(IsDirectory);
    LOAD(IsExecutable);
    LOAD(IsFile);
    LOAD(IsSameFileSystemItem);
    LOAD(IsSymLink);
    LOAD(KillProcess);
    LOAD(Native_OpenLog);
    LOAD(Native_SysLog);
    LOAD(Native_CloseLog);
    LOAD(SetDate);
    LOAD(WaitPid);

    char path[] = "/tmp/psl-rust-abi-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);
    assert(write(fd, "native", 6) == 6);
    assert(close(fd) == 0);
    struct stat expected = {};
    struct stat raw = {};
    CommonStat normalized = {};
    assert(stat(path, &expected) == 0);
    assert(GetStat(path, &raw) == 0);
    assert(raw.st_ino == expected.st_ino && raw.st_size == expected.st_size);
    assert(GetCommonStat(path, &normalized) == 0);
    assert(normalized.Inode == static_cast<int64_t>(expected.st_ino));
    assert(normalized.Size == expected.st_size && normalized.IsFile == 1);
    assert(normalized.UserId == static_cast<int>(expected.st_uid));
    uint64_t device = 0, inode = 0;
    assert(GetInodeData(path, &device, &inode) == 0);
    assert(device == static_cast<uint64_t>(expected.st_dev));
    assert(inode == static_cast<uint64_t>(expected.st_ino));
    int32_t links = 0;
    assert(GetLinkCount(path, &links) == 0 && links == expected.st_nlink);
    assert(IsFile(path) && !IsDirectory(path) && !IsSymLink(path));
    assert(IsSameFileSystemItem(path, path));
    assert(IsDirectory("/tmp") && IsExecutable("/bin/sh"));
    assert(GetCurrentProcessId() == getpid() && GetCurrentThreadId() > 0);

    char* host = GetComputerName();
    char* owner = GetFileOwner(path);
    char* user = GetPwUid(geteuid());
    char* group = GetGrGid(getegid());
    assert(host && *host && owner && user && group);
    assert(strcmp(owner, user) == 0);
    free(host);
    free(owner);
    free(user);
    free(group);
    errno = 0;
    assert(GetCommonStat(nullptr, &normalized) == -1 && errno == EINVAL);
    errno = 0;
    assert(SetDate(nullptr) == -1 && errno == EINVAL);
    assert(GetErrorCategory(ENOENT) == 13);

    char shell[] = "/bin/sh";
    char option[] = "-c";
    char command[] = "printf '%s' \"$PSL_ABI_TEST\"";
    char setting[] = "PSL_ABI_TEST=interop";
    char* arguments[] = {shell, option, command, nullptr};
    char* environment[] = {setting, nullptr};
    int32_t pid = -1, input = -1, output = -1, error = -1;
    assert(ForkAndExecProcess(shell, arguments, environment, "/tmp", 0, 1, 0,
                             1, &pid, &input, &output, &error) == 0);
    assert(pid > 0 && input == -1 && output >= 0 && error == -1);
    char buffer[32] = {};
    assert(read(output, buffer, sizeof(buffer)) == 7);
    assert(strcmp(buffer, "interop") == 0);
    assert(close(output) == 0);
    assert(WaitPid(pid, false) == pid);

    Native_OpenLog("powershell-rust-abi", LOG_USER);
    Native_SysLog(LOG_NOTICE, "Rust C ABI literal %s %n");
    Native_CloseLog();
    assert(unlink(path) == 0);
    assert(dlclose(library) == 0);
    std::puts("All 30 exports resolved; original-header ABI and host allocation/errno verified.");
    return 0;
}
