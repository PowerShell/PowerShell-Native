// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#pragma once

#include "pal.h"
#include <sys/types.h>

PAL_BEGIN_EXTERNC

pid_t WaitPid(pid_t pid, bool nohang);

PAL_END_EXTERNC
