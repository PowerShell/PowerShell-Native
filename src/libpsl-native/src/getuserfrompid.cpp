// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "pal.h"
#include "pal_config.h"
#include "getfileowner.h"
#include "getpwuid.h"
#include "getuserfrompid.h"

#include <string>
#include <sstream>
#include <errno.h>

#if __APPLE__
#include <sys/sysctl.h>
#elif HAVE_SYSCONF
// do nothing
#elif HAVE_SYS_SYSCTL_H
#include <sys/sysctl.h>
#endif

#if __FreeBSD__
#include <sys/user.h>
#endif

char* GetUserFromPid(pid_t pid)
{

#if defined(__linux__)

    // Get effective owner of pid from procfs
    std::stringstream ss;
    ss << "/proc/" << pid;
    std::string path;
    ss >> path;

    return GetFileOwner(path.c_str());

#elif (defined(__APPLE__) && defined(__MACH__)) || defined(__FreeBSD__)

    // Get effective owner of pid from sysctl
    struct kinfo_proc oldp;
    size_t oldlenp = sizeof(oldp);
    int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    u_int namelen = sizeof(name)/sizeof(int);

    // Read-only query
    int ret = sysctl(name, namelen, &oldp, &oldlenp, NULL, 0);
    if (ret != 0 || oldlenp == 0)
    {
        return NULL;
    }

#if defined(__FreeBSD__)
    return GetPwUid(oldp.ki_uid);
#else
    return GetPwUid(oldp.kp_eproc.e_ucred.cr_uid);
#endif

#else

    return NULL;

#endif

}
