// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! @brief wait for a child process to stop or terminate

#include "waitpid.h"

#include <sys/types.h>
#include <sys/wait.h>

//! @brief wait for a child process to stop or terminate
//!
//! WaitPid
//!
//! @param[in] pid
//! @parblock
//! The target PID to wait for.
//! @endparblock
//!
//! @param[in] nohang
//! @parblock
//! Whether to block while waiting for the process.
//! @endparblock
//!
//! @retval PID of exited child, or -1 if error
//!
pid_t WaitPid(pid_t pid, bool nohang)
{
    return waitpid(pid, NULL, nohang ? WNOHANG : 0);
}
