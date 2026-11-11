# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
param(
    [Parameter(Mandatory)]
    [string] $LibraryPath
)

$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class PslAbiSmoke
{
    [DllImport("libpsl-native", SetLastError = true)]
    private static extern int GetCurrentProcessId();

    [DllImport("libpsl-native", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.LPStr)]
    private static extern string GetComputerName();

    [DllImport("libpsl-native", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.I1)]
    private static extern bool IsDirectory([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("libpsl-native", SetLastError = true)]
    private static extern int GetLinkCount([MarshalAs(UnmanagedType.LPUTF8Str)] string path,
                                          out int count);

    public static void Run(string path)
    {
        IntPtr library = NativeLibrary.Load(path);
        NativeLibrary.SetDllImportResolver(typeof(PslAbiSmoke).Assembly,
            (name, assembly, searchPath) => name == "libpsl-native" ? library : IntPtr.Zero);
        if (GetCurrentProcessId() != Environment.ProcessId)
            throw new Exception("Process ID ABI mismatch");
        for (int i = 0; i < 100; i++)
            if (string.IsNullOrEmpty(GetComputerName()))
                throw new Exception("LPStr return marshalling failed");
        if (!IsDirectory("/tmp"))
            throw new Exception("One-byte native bool marshalling failed");
        int count;
        if (GetLinkCount(null, out count) != -1 || Marshal.GetLastPInvokeError() != 22)
            throw new Exception("Host errno was not preserved");
        // Keep the handle alive: the runtime caches resolved P/Invoke addresses.
    }
}
'@
[PslAbiSmoke]::Run((Resolve-Path $LibraryPath).Path)
'Existing C# P/Invoke string/bool/errno contracts verified.'
