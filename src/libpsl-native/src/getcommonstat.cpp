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

// Provide a common structure for the various different stat structures
int GetCommonStat(const char* path, struct CommonStat* commonStat)
{
    struct stat st;
    struct CommonStat cs;
    if (GetStat(path, &st) == 0)
    {
        cs.Inode = st.st_ino;
        cs.IsDirectory = S_ISDIR(st.st_mode);
        cs.IsFile = S_ISREG(st.st_mode);
        cs.IsBlockDevice = S_ISBLK(st.st_mode);
        cs.IsCharacterDevice = S_ISCHR(st.st_mode);
        cs.IsNamedPipe = S_ISFIFO(st.st_mode);
        cs.IsSocket = S_ISSOCK(st.st_mode);
        cs.Mode = st.st_mode;
        cs.UserId = st.st_uid;
        cs.GroupId = st.st_gid;
        commonStat = &cs;
        return 0;
    }
    return -1;
}
