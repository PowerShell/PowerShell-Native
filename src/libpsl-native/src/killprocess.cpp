// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! @brief kill a process with SIGKILL

#include "killprocess.h"

#include <sys/types.h>
#include <signal.h>

//! @brief kill a process with SIGKILL
//!
//! KillProcess
//!
//! @param[in] pid
//! @parblock
//! The target PID to kill.
//! @endparblock
//!
//! @retval true if signal successfully sent, false otherwise
//!
bool KillProcess(pid_t pid)
{
    return kill(pid, SIGKILL) == 0;
}
