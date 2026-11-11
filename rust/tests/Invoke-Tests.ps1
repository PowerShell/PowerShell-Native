# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
[CmdletBinding(DefaultParameterSetName = 'Unix')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Unix')]
    [string] $LibraryPath,
    [Parameter(Mandatory, ParameterSetName = 'Windows')]
    [string] $ExecutablePath,
    [Parameter(Mandatory, ParameterSetName = 'Windows')]
    [ValidateSet('coreclr', 'framework')]
    [string] $Configuration,
    [Parameter(Mandatory, ParameterSetName = 'Windows')]
    [ValidateSet('x64', 'x86')]
    [string] $Architecture,
    [Parameter(Mandatory)]
    [string] $ResultPath
)

$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -ErrorAction Stop
$data = if ($PSCmdlet.ParameterSetName -eq 'Unix') {
    if ($IsWindows) { throw 'Unix library tests cannot run in a Windows process.' }
    @{ Path = "$PSScriptRoot/NativeLibrary.Tests.ps1"; Data = @{ LibraryPath = (Resolve-Path $LibraryPath).Path } }
} else {
    if (-not $IsWindows) { throw 'Windows launcher tests require Windows.' }
    @{
        Path = "$PSScriptRoot/WindowsLauncher.Tests.ps1"
        Data = @{ ExecutablePath = (Resolve-Path $ExecutablePath).Path; Configuration = $Configuration; Architecture = $Architecture }
    }
}
$settings = New-PesterConfiguration
$settings.Run.Container = New-PesterContainer @data
$settings.Run.PassThru = $true
$settings.Output.Verbosity = 'Detailed'
$settings.TestResult.Enabled = $true
$settings.TestResult.OutputFormat = 'NUnitXml'
$resultFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultPath)
New-Item -ItemType Directory -Force (Split-Path -Parent $resultFile) > $null
$settings.TestResult.OutputPath = $resultFile
$result = Invoke-Pester -Configuration $settings
if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0 -or $result.SkippedCount -gt 0) {
    throw "Pester failed: $($result.FailedCount) failed, $($result.SkippedCount) skipped, $($result.TotalCount) total."
}
