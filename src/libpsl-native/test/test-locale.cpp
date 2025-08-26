// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! @brief Unit tests for linux locale

#include <gtest/gtest.h>
#include <langinfo.h>
#include <locale.h>
#include <string>
#include <stdio.h>
//! Test fixture for LocaleTest

class LocaleTest : public ::testing::Test
{
};

TEST_F(LocaleTest, Success)
{
    setlocale(LC_ALL, "");
    ASSERT_FALSE(nl_langinfo(CODESET) == NULL);
    // originally test expected UTF-8. should this change?
    #if defined (__APPLE__)
    ASSERT_STREQ(nl_langinfo(CODESET), "UTF-8");
    #else
    ASSERT_STREQ(nl_langinfo(CODESET), "ANSI_X3.4-1968");
    #endif
}
