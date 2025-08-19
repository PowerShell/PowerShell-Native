// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#pragma once

#include "pal.h"

#include <sys/types.h>

PAL_BEGIN_EXTERNC

char* GetUserFromPid(pid_t pid);

PAL_END_EXTERNC
