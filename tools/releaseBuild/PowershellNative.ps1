# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

[CmdletBinding()]

param (

    [Parameter(Mandatory, ParameterSetName = 'Build')]
    [ValidateSet('x64', 'x86', 'x64_arm', 'x64_arm64', 'linux-x64', 'osx', 'linix-arm')]
    [string]
    $Arch,

    [Parameter(Mandatory, ParameterSetName = 'Build')]
    [ValidateSet('Release', 'Debug')]
    [string]
    $Configuration,

    [switch] $Symbols,

    [Parameter(Mandatory, ParameterSetName = 'Build')]
    $RepoRoot,

    [Parameter(Mandatory, ParameterSetName = 'Build')]
    $TargetLocation
)

end {

    Import-Module $RepoRoot/build.psm1 -Force
    $binOut = New-Item -Path $TargetLocation/$Arch -ItemType Directory -Force
    Write-Verbose "Created output directory: $binOut" -Verbose

    if ($Arch -eq 'linux-x64' -or $Arch -eq 'osx') {
        Start-PSBootstrap
        Start-BuildNativeUnixBinaries

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-unix"
        Copy-Item $buildOutputPath/libpsl-native.* $binOut -Verbose
    }
    elseif ($Arch -eq 'linux-arm') {
        Start-PSBootstrap -BuildLinuxArm
        Start-BuildNativeUnixBinaries -BuildLinuxArm

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-unix"
        Copy-Item $buildOutputPath/libpsl-native.* $binOut -Verbose
    }
    else {
        Start-PSBootstrap -BuildWindowsNative
        Start-BuildNativeWindowsBinaries -Configuration $Configuration -Arch $Arch

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-win-core"
        Copy-Item "$buildOutputPath/*.dll" $binOut -Verbose

        if ($Symbols.IsPresent) {
            Copy-Item "$buildOutputPath/*.pdb" $binOut -Verbose
        }
    }
}

