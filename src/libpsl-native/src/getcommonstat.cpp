// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

//! @brief returns the stat of a file

#include "getcommonstat.h"

#include <errno.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>
#include <string.h>
#include <unistd.h>

#include <stdio.h>

// Provide a common structure for the various different stat structures.
// This should be safe to call on all platforms
int GetCommonLStat(const char* path, struct CommonStat* commonStat)
{
    struct stat st;
    assert(path);
    errno = 0;
    if (lstat(path, &st) == 0)
    {
        commonStat->Inode = st.st_ino;
        commonStat->Mode = st.st_mode;
        commonStat->UserId = st.st_uid;
        commonStat->GroupId = st.st_gid;
        commonStat->HardlinkCount = st.st_nlink;
        commonStat->Size = st.st_size;
        commonStat->AccessTime = st.st_atimespec.tv_sec;
        commonStat->ModifiedTime = st.st_mtimespec.tv_sec;
        commonStat->CreationTime = st.st_ctimespec.tv_sec;
        commonStat->BlockSize = st.st_blksize;
        commonStat->DeviceId = st.st_dev;
        commonStat->NumberOfBlocks = st.st_blocks;
        commonStat->IsBlockDevice = S_ISBLK(st.st_mode);
        commonStat->IsCharacterDevice = S_ISCHR(st.st_mode);
        commonStat->IsDirectory = S_ISDIR(st.st_mode);
        commonStat->IsFile = S_ISREG(st.st_mode);
        commonStat->IsNamedPipe = S_ISFIFO(st.st_mode);
        commonStat->IsSocket = S_ISSOCK(st.st_mode);
        commonStat->IsSymbolicLink = S_ISLNK(st.st_mode);
        return 0;
    }
    return -1;
}

// Provide a common structure for the various different stat structures.
// This should be safe to call on all platforms
int GetCommonStat(const char* path, struct CommonStat* commonStat)
{
    struct stat st;
    assert(path);
    errno = 0;
    if (stat(path, &st) == 0)
    {
        commonStat->Inode = st.st_ino;
        commonStat->Mode = st.st_mode;
        commonStat->UserId = st.st_uid;
        commonStat->GroupId = st.st_gid;
        commonStat->HardlinkCount = st.st_nlink;
        commonStat->Size = st.st_size;
        commonStat->AccessTime = st.st_atimespec.tv_sec;
        commonStat->ModifiedTime = st.st_mtimespec.tv_sec;
        commonStat->CreationTime = st.st_ctimespec.tv_sec;
        commonStat->BlockSize = st.st_blksize;
        commonStat->DeviceId = st.st_dev;
        commonStat->NumberOfBlocks = st.st_blocks;
        commonStat->IsBlockDevice = S_ISBLK(st.st_mode);
        commonStat->IsCharacterDevice = S_ISCHR(st.st_mode);
        commonStat->IsDirectory = S_ISDIR(st.st_mode);
        commonStat->IsFile = S_ISREG(st.st_mode);
        commonStat->IsNamedPipe = S_ISFIFO(st.st_mode);
        commonStat->IsSocket = S_ISSOCK(st.st_mode);
        commonStat->IsSymbolicLink = S_ISLNK(st.st_mode);
        return 0;
    }
    return -1;
}

