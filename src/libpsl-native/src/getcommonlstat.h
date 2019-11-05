// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include "pal.h"

#include <sys/stat.h>

#include "getcommonstat.h"

PAL_BEGIN_EXTERNC

int32_t GetLStat(const char* path, struct stat* buf);
int GetCommonLStat(const char* path, CommonStat* cs);

PAL_END_EXTERNC

