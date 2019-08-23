// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

//! @brief Tests IsDirectory

#include <gtest/gtest.h>
#include <errno.h>
#include <unistd.h>
#include "isdirectory.h"
#include "getcommonstat.h"

TEST(GetCommonStat, RootIsDirectory)
{
    CommonStat cs;
    GetCommonStat("/", &cs);
    bool isDir = IsDirectory("/");
    bool fromCommonStat = (bool)cs.IsDirectory;
    EXPECT_EQ(isDir, fromCommonStat);
}

TEST(GetCommonStat, BinLsIsNotDirectory)
{
    CommonStat cs;
    GetCommonStat("/bin/ls", &cs);
    bool isDir = IsDirectory("/bin/ls");
    bool fromCommonStat = (bool)cs.IsDirectory;
    EXPECT_EQ(isDir, fromCommonStat);
}


TEST(GetCommonStat, ReturnsFalseForFakeDirectory)
{
    CommonStat cs;
    int badDir = GetCommonStat("/A/Really/Bad/Directory",&cs);
    EXPECT_EQ(badDir, -1);
}

TEST(GetCommonStat, GetOwnerIdOfRoot)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %u /", "r");
#else
     p = popen("/usr/bin/stat -c %u /", "r");
#endif
    int uid = -1;
    fscanf(p, "%d", &uid);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(uid, cs.UserId);
}

TEST(GetCommonStat, GetGroupId)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %g /", "r");
#else
     p = popen("/usr/bin/stat -c %g /", "r");
#endif
    int gid = -1;
    fscanf(p, "%d", &gid);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(gid, cs.UserId);
}

TEST(GetCommonStat, GetInodeNumber)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %i /", "r");
#else
     p = popen("/usr/bin/stat -c %i /", "r");
#endif
    long inode = -1;
    fscanf(p, "%ld", &inode);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(inode, cs.Inode);
}

TEST(GetCommonStat, GetSize)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %z /", "r");
#else
     p = popen("/usr/bin/stat -c %z /", "r");
#endif
    long size = -1;
    fscanf(p, "%ld", &size);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(size, cs.Size);
}

TEST(GetCommonStat, GetBlockSize)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %k /", "r");
#else
     p = popen("/usr/bin/stat -c %k /", "r");
#endif
    long bSize = -1;
    fscanf(p, "%ld", &bSize);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(bSize, cs.BlockSize);
}

TEST(GetCommonStat, GetBlockCount)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %b /", "r");
#else
     p = popen("/usr/bin/stat -c %b /", "r");
#endif
    int bSize = -1;
    fscanf(p, "%d", &bSize);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(bSize, cs.NumberOfBlocks);
}

TEST(GetCommonStat, GetLinkCount)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %l /", "r");
#else
     p = popen("/usr/bin/stat -c %l /", "r");
#endif
    int linkcount = -1;
    fscanf(p, "%d", &linkcount);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(linkcount, cs.HardlinkCount);
}

TEST(GetCommonStat, GetDeviceId)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %d /", "r");
#else
     p = popen("/usr/bin/stat -c %d /", "r");
#endif
    int deviceId = -1;
    fscanf(p, "%d", &deviceId);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(deviceId, cs.DeviceId);
}

TEST(GetCommonStat, GetATime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %a /", "r");
#else
     p = popen("/usr/bin/stat -c %a /", "r");
#endif
    long aTime = -1;
    fscanf(p, "%ld", &aTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(aTime, cs.AccessTime);
}

TEST(GetCommonStat, GetMTime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %m /", "r");
#else
     p = popen("/usr/bin/stat -c %m /", "r");
#endif
    long mTime = -1;
    fscanf(p, "%ld", &mTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(mTime, cs.ModifiedTime);
}

TEST(GetCommonStat, GetCTime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %c /", "r");
#else
     p = popen("/usr/bin/stat -c %c /", "r");
#endif
    long cTime = -1;
    fscanf(p, "%ld", &cTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(cTime, cs.CreationTime);
}