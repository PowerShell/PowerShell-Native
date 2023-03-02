// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#include "pal_config.h"
#include "getppid.h"

#include <sys/user.h>
#include <sys/param.h>

#if HAVE_SYSCONF
// do nothing
#elif HAVE_SYS_SYSCTL_H
#include <sys/sysctl.h>
#endif

#if __FreeBSD__
#include <sys/types.h>
#include <sys/sysctl.h>
#endif

//! @brief GetPPid returns the parent process id for a process
//!
//! GetPPid
//!
//! @param[in] pid
//! @parblock
//! The process id to query for it's parent.
//! @endparblock
//!
//! @retval the parent process id, or UINT_MAX if unsuccessful
//!
pid_t GetPPid(pid_t pid)
{
#if defined (__APPLE__) && defined(__MACH__) || defined(__FreeBSD__)
    const pid_t PIDUnknown = UINT_MAX;
    struct kinfo_proc info;
    size_t length = sizeof(struct kinfo_proc);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
        return PIDUnknown;
    if (length == 0)
        return PIDUnknown;
#if defined (__APPLE__) && defined(__MACH__)
    return info.kp_eproc.e_ppid;
#elif defined(__FreeBSD__)
    return info.ki_ppid;
#endif
#else

    return UINT_MAX;

#endif
}
