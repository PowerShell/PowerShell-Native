# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
param(
    [Parameter(Mandatory)]
    [string] $LibraryPath
)

BeforeAll {
    Add-Type -Path "$PSScriptRoot/NativeMethods.cs"
    [PowerShell.Native.Tests.NativeMethods]::Load((Resolve-Path $LibraryPath).Path)
}

Describe 'Rust Unix library exports' {
    It 'exports <Name> with the original symbol name' -ForEach @(
        'CreateHardLink', 'CreateSymLink', 'FollowSymLink', 'ForkAndExecProcess',
        'GetCommonStat', 'GetCommonLStat', 'GetComputerName', 'GetCurrentProcessId',
        'GetCurrentThreadId', 'GetErrorCategory', 'GetFileOwner', 'GetGrGid',
        'GetInodeData', 'GetLinkCount', 'GetLStat', 'GetPPid', 'GetPwUid',
        'GetStat', 'GetUserFromPid', 'IsDirectory', 'IsExecutable', 'IsFile',
        'IsSameFileSystemItem', 'IsSymLink', 'KillProcess', 'Native_OpenLog',
        'Native_SysLog', 'Native_CloseLog', 'SetDate', 'WaitPid'
    ).ForEach({ @{ Name = $_ } }) {
        [PowerShell.Native.Tests.NativeMethods]::Export($Name) | Should -Not -Be ([IntPtr]::Zero)
    }
}

Describe 'Rust managed/native ABI' {
    It 'preserves normalized stat and time layouts' {
        [System.Runtime.InteropServices.Marshal]::SizeOf([type][PowerShell.Native.Tests.CommonStat]) | Should -Be 112
        [System.Runtime.InteropServices.Marshal]::OffsetOf([type][PowerShell.Native.Tests.CommonStat], 'DeviceId').ToInt32() | Should -Be 64
        [System.Runtime.InteropServices.Marshal]::OffsetOf([type][PowerShell.Native.Tests.CommonStat], 'IsSticky').ToInt32() | Should -Be 108
        [System.Runtime.InteropServices.Marshal]::SizeOf([type][PowerShell.Native.Tests.PrivateTm]) | Should -Be 36
    }

    It 'returns native process and thread identities' {
        [PowerShell.Native.Tests.NativeMethods]::GetCurrentProcessId() | Should -Be $PID
        [PowerShell.Native.Tests.NativeMethods]::GetCurrentThreadId() | Should -BeGreaterThan 0
        $parent = [PowerShell.Native.Tests.NativeMethods]::GetPPid($PID)
        if ($IsLinux) { $parent | Should -Be -1 } else { $parent | Should -BeGreaterThan 0 }
    }

    It 'marshals and releases returned UTF-8 strings repeatedly' {
        foreach ($iteration in 1..100) {
            [PowerShell.Native.Tests.NativeMethods]::GetComputerName() | Should -Be ([System.Net.Dns]::GetHostName())
        }
        $uid = [PowerShell.Native.Tests.NativeMethods]::getuid()
        $name = [PowerShell.Native.Tests.NativeMethods]::GetPwUid($uid)
        $name | Should -Not -BeNullOrEmpty
        [PowerShell.Native.Tests.NativeMethods]::GetUserFromPid($PID) | Should -Be $name
        [PowerShell.Native.Tests.NativeMethods]::GetGrGid([PowerShell.Native.Tests.NativeMethods]::getgid()) | Should -Not -BeNullOrEmpty
    }

    It 'preserves PowerShell error categories' {
        [PowerShell.Native.Tests.NativeMethods]::GetErrorCategory(2) | Should -Be 13
        [PowerShell.Native.Tests.NativeMethods]::GetErrorCategory(13) | Should -Be 18
        [PowerShell.Native.Tests.NativeMethods]::GetErrorCategory(22) | Should -Be 5
    }
}

Describe 'Rust filesystem behavior' {
    BeforeEach {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $directory
        $file = Join-Path $directory "native-$([char]0x03bb).txt"
        [System.IO.File]::WriteAllText($file, 'native data')
        $hard = Join-Path $directory 'hard'
        $link = Join-Path $directory 'link'
    }

    It 'preserves one-byte booleans and legacy existence semantics' {
        [PowerShell.Native.Tests.NativeMethods]::IsDirectory($directory) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::IsDirectory($file) | Should -BeFalse
        [PowerShell.Native.Tests.NativeMethods]::IsFile($directory) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::IsFile($file) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::IsFile("$file-missing") | Should -BeFalse
        [PowerShell.Native.Tests.NativeMethods]::IsExecutable('/bin/sh') | Should -BeTrue
    }

    It 'creates hard links with matching inode, device, and link count' {
        [PowerShell.Native.Tests.NativeMethods]::CreateHardLink($hard, $file) | Should -Be 0
        [PowerShell.Native.Tests.NativeMethods]::IsSameFileSystemItem($file, $hard) | Should -BeTrue
        [ulong] $device = 0; [ulong] $inode = 0
        [ulong] $otherDevice = 0; [ulong] $otherInode = 0
        [PowerShell.Native.Tests.NativeMethods]::GetInodeData($file, [ref]$device, [ref]$inode) | Should -Be 0
        [PowerShell.Native.Tests.NativeMethods]::GetInodeData($hard, [ref]$otherDevice, [ref]$otherInode) | Should -Be 0
        $device | Should -Be $otherDevice
        $inode | Should -Be $otherInode
        $count = 0
        [PowerShell.Native.Tests.NativeMethods]::GetLinkCount($file, [ref]$count) | Should -Be 0
        $count | Should -Be 2
    }

    It 'distinguishes stat from lstat and resolves symlinks' {
        [PowerShell.Native.Tests.NativeMethods]::CreateSymLink($link, $file) | Should -Be 0
        [PowerShell.Native.Tests.NativeMethods]::IsSymLink($link) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::IsSameFileSystemItem($file, $link) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::FollowSymLink($link) | Should -Be (Get-Item $file).FullName
        $stat = [PowerShell.Native.Tests.CommonStat]::new()
        [PowerShell.Native.Tests.NativeMethods]::GetCommonStat($link, [ref]$stat) | Should -Be 0
        $stat.IsFile | Should -Be 1
        $stat.Size | Should -Be 11
        [PowerShell.Native.Tests.NativeMethods]::GetCommonLStat($link, [ref]$stat) | Should -Be 0
        $stat.IsSymbolicLink | Should -Be 1
    }

    It 'retains dangling link existence and raw-target fallback' {
        $missing = Join-Path $directory 'missing'
        [PowerShell.Native.Tests.NativeMethods]::CreateSymLink($link, $missing) | Should -Be 0
        [PowerShell.Native.Tests.NativeMethods]::IsFile($link) | Should -BeTrue
        [PowerShell.Native.Tests.NativeMethods]::IsDirectory($link) | Should -BeFalse
        [PowerShell.Native.Tests.NativeMethods]::FollowSymLink($link) | Should -Be $missing
    }

    It 'supports native raw stat buffers and file ownership' {
        $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(512)
        try {
            [PowerShell.Native.Tests.NativeMethods]::GetStat($file, $buffer) | Should -Be 0
            [PowerShell.Native.Tests.NativeMethods]::GetLStat($file, $buffer) | Should -Be 0
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
        [PowerShell.Native.Tests.NativeMethods]::GetFileOwner($file) | Should -Be ([PowerShell.Native.Tests.NativeMethods]::GetUserFromPid($PID))
    }

    It 'preserves native errno for missing paths' {
        $count = 0
        $result = [PowerShell.Native.Tests.NativeMethods]::GetLinkCount("$file-missing", [ref]$count)
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        $result | Should -Be -1
        $errorCode | Should -Be 2
    }
}

Describe 'Rust safe failure and logging paths' {
    It 'rejects null process arguments and initializes all outputs' {
        $child = $inputFd = $outputFd = $errorFd = 42
        $result = [PowerShell.Native.Tests.NativeMethods]::ForkAndExecProcess(
            [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero,
            0, 0, 0, 0, [ref]$child, [ref]$inputFd, [ref]$outputFd, [ref]$errorFd)
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        $result | Should -Be -1
        $errorCode | Should -Be 22
        $child | Should -Be -1
        $inputFd | Should -Be -1
        $outputFd | Should -Be -1
        $errorFd | Should -Be -1
    }

    It 'rejects a null time without changing the system clock' {
        $result = [PowerShell.Native.Tests.NativeMethods]::SetDate([IntPtr]::Zero)
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        $result | Should -Be -1
        $errorCode | Should -Be 22
    }

    It 'reports errors for nonexistent processes without touching other children' {
        [PowerShell.Native.Tests.NativeMethods]::KillProcess([int]::MaxValue) | Should -BeFalse
        [PowerShell.Native.Tests.NativeMethods]::WaitPid([int]::MaxValue, $true) | Should -Be -1
    }

    It 'accepts literal format characters in log messages' {
        [PowerShell.Native.Tests.NativeMethods]::Native_OpenLog('powershell-rust-pester', 8)
        try {
            { [PowerShell.Native.Tests.NativeMethods]::Native_SysLog(6, 'Pester literal %s %n') } | Should -Not -Throw
        } finally {
            [PowerShell.Native.Tests.NativeMethods]::Native_CloseLog()
        }
    }
}
