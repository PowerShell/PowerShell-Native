// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include "pal.h"

#include <sys/stat.h>

PAL_BEGIN_EXTERNC

struct CommonStat
{
    int64_t Inode;
    int Mode;
    int UserId;
    int GroupId;
    int HardlinkCount;
    int64_t Size;
    int64_t AccessTime;
    int64_t ModifiedTime;
    int64_t ChangeTime;
    int64_t BlockSize;
    int DeviceId;
    int NumberOfBlocks;
    int IsDirectory;
    int IsFile;
    int IsSymbolicLink;
    int IsBlockDevice;
    int IsCharacterDevice;
    int IsNamedPipe;
    int IsSocket;
    int IsSetUid;
    int IsSetGid;
    int IsSticky;
};

int32_t GetStat(const char* path, struct stat* buf);
int GetCommonStat(const char* path, CommonStat* cs);

PAL_END_EXTERNC

