// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

//! @brief Unit tests for GetUserFromPid

#include <gtest/gtest.h>
#include <grp.h>
#include "getgrgid.h"

TEST(GetGrGid, Success)
{
    char* expected = getgrgid(getegid())->gr_name;
    EXPECT_STREQ(GetGrGid(getegid()), expected);
}

