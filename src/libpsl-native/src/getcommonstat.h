// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include "pal.h"

#include <sys/stat.h>

PAL_BEGIN_EXTERNC

struct CommonStat
{
    long Inode;
    int Mode;
    int UserId;
    int GroupId;
    int IsDirectory;
    int IsFile;
    int IsSymbolicLink;
    int IsBlockDevice;
    int IsCharacterDevice;
    int IsNamedPipe;
    int IsSocket;
};

int32_t GetStat(const char* path, struct stat* buf);
int GetCommonStat(const char* path, CommonStat* cs);

PAL_END_EXTERNC
