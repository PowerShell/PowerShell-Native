// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! @brief Tests Isfile

#include <gtest/gtest.h>
#include <errno.h>
#include <unistd.h>
#include "isfile.h"

TEST(IsFileTest, RootIsFile)
{
    // IsFile implementation is actually PathExists.
    // So adjusting the test accordingly.
    EXPECT_TRUE(IsFile("/"));
}

TEST(IsFileTest, BinLsIsFile)
{
    EXPECT_TRUE(IsFile("/bin/ls"));
}

TEST(IsFileTest, CannotGetOwnerOfFakeFile)
{
    EXPECT_FALSE(IsFile("SomeMadeUpFileNameThatDoesNotExist"));
    EXPECT_EQ(errno, ENOENT);
}
