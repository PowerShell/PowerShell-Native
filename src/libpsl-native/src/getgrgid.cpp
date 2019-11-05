// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

//! @brief returns the groupname for a gid

#include "getgrgid.h"

#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <grp.h>
#include <string.h>
#include <unistd.h>

//! @brief GetGrGid returns the groupname for a gid
//!
//! GetGrGid
//!
//! @param[in] gid
//! @parblock
//! The group identifier to lookup.
//! @endparblock
//!
//! @retval groupname as UTF-8 string, or NULL if unsuccessful
//!
char* GetGrGid(gid_t gid)
{
    int32_t ret = 0;
    struct group grp;
    struct group* result = NULL;
    char* buf;

    int buflen = sysconf(_SC_GETPW_R_SIZE_MAX);
    if (buflen < 1)
    {
        buflen = 2048;
    }

allocate:
    buf = (char*)calloc(buflen, sizeof(char));

    errno = 0;
    ret = getgrgid_r(gid, &grp, buf, buflen, &result);

    if (ret != 0)
    {
        if (errno == ERANGE)
        {
            free(buf);
            buflen *= 2;
            goto allocate;
        }
        return NULL;
    }

    // no group found
    if (result == NULL)
    {
        return NULL;
    }

    // allocate copy on heap so CLR can free it
    size_t userlen = strnlen(grp.gr_name, buflen);
    char* groupname = strndup(grp.gr_name, userlen);
    free(buf);
    return groupname;
}

