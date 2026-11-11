# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
param(
    [Parameter(Mandatory)]
    [string] $ExecutablePath,
    [Parameter(Mandatory)]
    [ValidateSet('coreclr', 'framework')]
    [string] $Configuration
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'The launcher smoke test requires Windows and PowerShell 7 or newer.'
}
$executable = (Resolve-Path $ExecutablePath).Path
$version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
if ($version.FileVersion -ne '0.1.0' -or $version.OriginalFilename -ne 'powershell.exe') {
    throw 'Launcher version resources were not embedded correctly.'
}

$process = [System.Diagnostics.Process]::new()
$started = $false
try {
    $process.StartInfo.FileName = $executable
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = if ($Configuration -eq 'coreclr') {
        [System.Text.Encoding]::UTF8
    } else {
        [System.Text.Encoding]::Unicode
    }
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode
    $arguments = if ($Configuration -eq 'coreclr') {
        @('-?')
    } else {
        @('-Version', 'invalid')
    }
    foreach ($argument in $arguments) {
        $process.StartInfo.ArgumentList.Add($argument)
    }
    $started = $process.Start()
    if (-not $started) { throw 'Launcher process did not start.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'Launcher did not finish within 30 seconds.'
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errorText = $stderr.GetAwaiter().GetResult()
    if ($Configuration -eq 'coreclr') {
        if ($process.ExitCode -ne -1 -or $output -notmatch 'USAGE: powershell') {
            throw "CoreCLR native help failed ($($process.ExitCode)): $output $errorText"
        }
    } elseif ($process.ExitCode -ne -196608 -or $errorText -notmatch 'PowerShell native host error 0xfffd0000') {
        throw "Framework native argument rejection failed ($($process.ExitCode)): $output $errorText"
    }
} finally {
    if ($started -and -not $process.HasExited) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $process.Dispose()
}
'Launcher resources and native smoke checks passed.'
