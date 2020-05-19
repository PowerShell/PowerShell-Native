// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#include "getcurrentprocessorid.h"

#include <unistd.h>

pid_t GetCurrentProcessId()
{
    return getpid();
}
