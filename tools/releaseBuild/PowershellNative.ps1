# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

[CmdletBinding()]

param (

    [Parameter(Mandatory, ParameterSetName = 'Build')]
    [ValidateSet('x64', 'x86', 'x64_arm', 'x64_arm64', 'linux-x64', 'osx', 'linux-arm', 'linux-arm64', 'linux-musl-x64')]
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
    Write-Verbose -Verbose "Starting PowerShellNative.ps1 Arch: $Arch, Config: $Configuration, Repo: $RepoRoot, Target: $TargetLocation"
    Import-Module $RepoRoot/build.psm1 -Force
    #$binOut = New-Item -Path $TargetLocation/$Arch -ItemType Directory -Force
    $binOut = New-Item -Path $TargetLocation -ItemType Directory -Force
    Write-Verbose "Created output directory: $binOut" -Verbose

    if ($Arch -eq 'linux-x64' -or $Arch -eq 'osx' -or $Arch -eq 'linux-musl-x64') {

        Write-Verbose "Starting Build for: $Arch" -Verbose

        Start-PSBootstrap
        Start-BuildNativeUnixBinaries

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-unix"
        Compress-Archive -Path $buildOutputPath/libpsl-native.* -DestinationPath "$TargetLocation/$Arch-symbols.zip" -Verbose

        $testResultPath = Join-Path $RepoRoot -ChildPath 'src/libpsl-native/test/native-tests.xml'

        if (Test-Path $testResultPath) {
            Copy-Item $testResultPath -Destination $TargetLocation -Verbose -Force
        }
    }
    elseif ($Arch -eq 'linux-arm') {
        Start-PSBootstrap -BuildLinuxArm
        Start-BuildNativeUnixBinaries -BuildLinuxArm

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-unix"
        Compress-Archive -Path $buildOutputPath/libpsl-native.* -DestinationPath "$TargetLocation/$Arch-symbols.zip" -Verbose
    }
    elseif ($Arch -eq 'linux-arm64') {
        Start-PSBootstrap -BuildLinuxArm64
        Start-BuildNativeUnixBinaries -BuildLinuxArm64

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-unix"
        Compress-Archive -Path $buildOutputPath/libpsl-native.* -DestinationPath "$TargetLocation/$Arch-symbols.zip" -Verbose
    }
    else {
        Write-Verbose "Starting Start-PSBootstrap" -Verbose
        Start-PSBootstrap -BuildWindowsNative
        Write-Verbose "Starting Start-BuildNativeWindowsBinaries" -Verbose
        Start-BuildNativeWindowsBinaries -Configuration $Configuration -Arch $Arch -Clean
        Write-Verbose "Completed Start-BuildNativeWindowsBinaries" -Verbose

        $buildOutputPath = Join-Path $RepoRoot "src/powershell-win-core"
        Compress-Archive -Path "$buildOutputPath/*.dll" -DestinationPath "$TargetLocation/$Arch-symbols.zip" -Verbose

        if ($Symbols.IsPresent) {
            Compress-Archive -Path "$buildOutputPath/*.pdb" -DestinationPath "$TargetLocation/$Arch-symbols.zip" -Update -Verbose
        }
    }
}

