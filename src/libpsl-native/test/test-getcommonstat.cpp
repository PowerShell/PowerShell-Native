// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

//! @brief Tests IsDirectory

#include <gtest/gtest.h>
#include <errno.h>
#include <unistd.h>
#include "isdirectory.h"
#include "getcommonstat.h"
#include <sys/types.h>
#include <sys/stat.h>

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
    int result = fscanf(p, "%d", &uid);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
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
    int result = fscanf(p, "%d", &gid);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(gid, cs.GroupId);
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
    int result = fscanf(p, "%ld", &inode);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(inode, cs.Inode);
}

TEST(GetCommonStat, GetMode)
{
    FILE *p;
    CommonStat cs;
    unsigned int mode = -1;
#if defined (__APPLE__)
    p = popen("/usr/bin/stat -f %p /", "r");
    int result = fscanf(p, "%o", &mode);
#else
    p = popen("/usr/bin/stat -c %f /", "r");
    int result = fscanf(p, "%x", &mode);
#endif
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(mode, cs.Mode);
}

TEST(GetCommonStat, GetSize)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %z /", "r");
#else
     p = popen("/usr/bin/stat -c %s /", "r");
#endif
    long size = -1;
    int result = fscanf(p, "%ld", &size);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(size, cs.Size);
}

TEST(GetCommonStat, GetBlockSize)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %k /", "r");
#else
     p = popen("/usr/bin/stat -c %o /", "r");
#endif
    long bSize = -1;
    int result = fscanf(p, "%ld", &bSize);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
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
    int result = fscanf(p, "%d", &bSize);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(bSize, cs.NumberOfBlocks);
}

TEST(GetCommonStat, GetLinkCount)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %l /", "r");
#else
     p = popen("/usr/bin/stat -c %h /", "r");
#endif
    int linkcount = -1;
    int result = fscanf(p, "%d", &linkcount);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
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
    int result = fscanf(p, "%d", &deviceId);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(deviceId, cs.DeviceId);
}

TEST(GetCommonStat, GetATime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %a /", "r");
#else
     p = popen("/usr/bin/stat -c %X /", "r");
#endif
    long aTime = -1;
    int result = fscanf(p, "%ld", &aTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(aTime, cs.AccessTime);
}

TEST(GetCommonStat, GetMTime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %m /", "r");
#else
     p = popen("/usr/bin/stat -c %Y /", "r");
#endif
    long mTime = -1;
    int result = fscanf(p, "%ld", &mTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(mTime, cs.ModifiedTime);
}

TEST(GetCommonStat, GetCTime)
{
    FILE *p;
    CommonStat cs;
#if defined (__APPLE__)
     p = popen("/usr/bin/stat -f %c /", "r");
#else
     p = popen("/usr/bin/stat -c %Z /", "r");
#endif
    long cTime = -1;
    int result = fscanf(p, "%ld", &cTime);
    pclose(p);
    GetCommonStat("/", &cs);
    EXPECT_EQ(result, 1);
    EXPECT_EQ(cTime, cs.ChangeTime);
}

TEST(GetCommonStat, Mode001)
{
    const std::string ftemplate = "/tmp/CommonStatModeF_XXXXXX";
    char fname[PATH_MAX];
    struct stat buffer;
    int fd;
    CommonStat cs;
    strcpy(fname, ftemplate.c_str());
    fd = mkstemp(fname);
    EXPECT_NE(fd, -1);
    chmod(fname, S_IRWXU | S_IRWXG | S_IROTH | S_IWOTH);
    stat(fname, &buffer);
    GetCommonStat(fname, &cs);
    unlink(fname);
    EXPECT_EQ(cs.Mode, buffer.st_mode);
}

TEST(GetCommonStat, Mode002)
{
    const std::string ftemplate = "/tmp/CommonStatModeF_XXXXXX";
    char fname[PATH_MAX];
    struct stat buffer;
    int fd;
    CommonStat cs;
    strcpy(fname, ftemplate.c_str());
    fd = mkstemp(fname);
    EXPECT_NE(fd, -1);
    chmod(fname, S_IRWXU | S_IRWXG | S_IROTH | S_IWOTH | S_ISUID );
    stat(fname, &buffer);
    GetCommonStat(fname, &cs);
    unlink(fname);
    EXPECT_EQ(cs.Mode, buffer.st_mode);
    EXPECT_EQ(cs.IsSetUid, 1);
}

TEST(GetCommonStat, Mode003)
{
    const std::string ftemplate = "/tmp/CommonStatModeF_XXXXXX";
    char fname[PATH_MAX];
    struct stat buffer;
    int fd;
    CommonStat cs;
    strcpy(fname, ftemplate.c_str());
    fd = mkstemp(fname);
    EXPECT_NE(fd, -1);
    chmod(fname, S_IRUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH | S_ISGID );
    stat(fname, &buffer);
    GetCommonStat(fname, &cs);
    unlink(fname);
    EXPECT_EQ(cs.Mode, buffer.st_mode);
    // don't check for IsSetGid as that can vary from platform based on file system
}

TEST(GetCommonStat, Mode004)
{
    const std::string ftemplate = "/tmp/CommonStatModeD_XXXXXX";
    char dname[PATH_MAX];
    struct stat buffer;
    char * fd;
    CommonStat cs;
    strcpy(dname, ftemplate.c_str());
    fd = mkdtemp(dname);
    EXPECT_NE(fd, ftemplate);
    chmod(dname, S_IRWXU | S_IRWXG | S_IROTH | S_IWOTH | S_ISVTX );
    stat(dname, &buffer);
    GetCommonStat(dname, &cs);
    rmdir(dname);
    EXPECT_EQ(cs.Mode, buffer.st_mode);
    EXPECT_EQ(cs.IsSticky, 1);
}

