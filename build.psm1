# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# On Unix paths is separated by colon
# On Windows paths is separated by semicolon
$script:TestModulePathSeparator = [System.IO.Path]::PathSeparator

#$dotnetCLIChannel = "release"
#$dotnetCLIRequiredVersion = $(Get-Content $PSScriptRoot/global.json | ConvertFrom-Json).Sdk.Version

# Track if tags have been sync'ed
$tagsUpToDate = $false

# Sync Tags
# When not using a branch in PowerShell/PowerShell, tags will not be fetched automatically
# Since code that uses Get-PSCommitID and Get-PSLatestTag assume that tags are fetched,
# This function can ensure that tags have been fetched.
# This function is used during the setup phase in tools/appveyor.psm1 and tools/travis.ps1
function Sync-PSTags
{
    param(
        [Switch]
        $AddRemoteIfMissing
    )

    $PowerShellRemoteUrl = "https://github.com/powershell/powershell.git"
    $upstreamRemoteDefaultName = 'upstream'
    $remotes = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote}
    $upstreamRemote = $null
    foreach($remote in $remotes)
    {
        $url = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote get-url $remote}
        if($url -eq $PowerShellRemoteUrl)
        {
            $upstreamRemote = $remote
            break
        }
    }

    if(!$upstreamRemote -and $AddRemoteIfMissing.IsPresent -and $remotes -notcontains $upstreamRemoteDefaultName)
    {
        $null = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" remote add $upstreamRemoteDefaultName $PowerShellRemoteUrl}
        $upstreamRemote = $upstreamRemoteDefaultName
    }
    elseif(!$upstreamRemote)
    {
        Write-Error "Please add a remote to PowerShell\PowerShell.  Example:  git remote add $upstreamRemoteDefaultName $PowerShellRemoteUrl" -ErrorAction Stop
    }

    $null = Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" fetch --tags --quiet $upstreamRemote}
    $script:tagsUpToDate=$true
}

# Gets the latest tag for the current branch
function Get-PSLatestTag
{
    [CmdletBinding()]
    param()
    # This function won't always return the correct value unless tags have been sync'ed
    # So, Write a warning to run Sync-PSTags
    if(!$tagsUpToDate)
    {
        Write-Warning "Run Sync-PSTags to update tags"
    }

    return (Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" describe --abbrev=0})
}

function Get-PSVersion
{
    [CmdletBinding()]
    param(
        [switch]
        $OmitCommitId
    )
    if($OmitCommitId.IsPresent)
    {
        return (Get-PSLatestTag) -replace '^v'
    }
    else
    {
        return (Get-PSCommitId) -replace '^v'
    }
}

function Get-PSCommitId
{
    [CmdletBinding()]
    param()
    # This function won't always return the correct value unless tags have been sync'ed
    # So, Write a warning to run Sync-PSTags
    if(!$tagsUpToDate)
    {
        Write-Warning "Run Sync-PSTags to update tags"
    }

    return (Start-NativeExecution {git --git-dir="$PSScriptRoot/.git" describe --dirty --abbrev=60})
}

function Get-EnvironmentInformation
{
    $environment = @{}
    # PowerShell Core will likely not be built on pre-1709 nanoserver
    if ($PSVersionTable.ContainsKey("PSEdition") -and "Core" -eq $PSVersionTable.PSEdition) {
        $environment += @{'IsCoreCLR' = $true}
        $environment += @{'IsLinux' = $IsLinux}
        $environment += @{'IsMacOS' = $IsMacOS}
        $environment += @{'IsWindows' = $IsWindows}
    } else {
        $environment += @{'IsCoreCLR' = $false}
        $environment += @{'IsLinux' = $false}
        $environment += @{'IsMacOS' = $false}
        $environment += @{'IsWindows' = $true}
    }

    if ($Environment.IsWindows)
    {
        $environment += @{'IsAdmin' = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)}
        # Can't use $env:HOME - not available on older systems (e.g. in AppVeyor)
        $environment += @{'nugetPackagesRoot' = "${env:HOMEDRIVE}${env:HOMEPATH}\.nuget\packages"}
    }
    else
    {
        $environment += @{'nugetPackagesRoot' = "${env:HOME}/.nuget/packages"}
    }

    if ($Environment.IsLinux) {
        $LinuxInfo = Get-Content /etc/os-release -Raw | ConvertFrom-StringData

        $environment += @{'LinuxInfo' = $LinuxInfo}
        $environment += @{'IsDebian' = $LinuxInfo.ID -match 'debian'}
        $environment += @{'IsDebian8' = $Environment.IsDebian -and $LinuxInfo.VERSION_ID -match '8'}
        $environment += @{'IsDebian9' = $Environment.IsDebian -and $LinuxInfo.VERSION_ID -match '9'}
        $environment += @{'IsUbuntu' = $LinuxInfo.ID -match 'ubuntu'}
        $environment += @{'IsUbuntu14' = $Environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '14.04'}
        $environment += @{'IsUbuntu16' = $Environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '16.04'}
        $environment += @{'IsUbuntu17' = $Environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '17.10'}
        $environment += @{'IsUbuntu18' = $Environment.IsUbuntu -and $LinuxInfo.VERSION_ID -match '18.04'}
        $environment += @{'IsCentOS' = $LinuxInfo.ID -match 'centos' -and $LinuxInfo.VERSION_ID -match '7'}
        $environment += @{'IsFedora' = $LinuxInfo.ID -match 'fedora' -and $LinuxInfo.VERSION_ID -ge 24}
        $environment += @{'IsOpenSUSE' = $LinuxInfo.ID -match 'opensuse'}
        $environment += @{'IsSLES' = $LinuxInfo.ID -match 'sles'}
        $environment += @{'IsOpenSUSE13' = $Environmenst.IsOpenSUSE -and $LinuxInfo.VERSION_ID  -match '13'}
        $environment += @{'IsOpenSUSE42.1' = $Environment.IsOpenSUSE -and $LinuxInfo.VERSION_ID  -match '42.1'}
        $environment += @{'IsRedHatFamily' = $Environment.IsCentOS -or $Environment.IsFedora}
        $environment += @{'IsSUSEFamily' = $Environment.IsSLES -or $Environment.IsOpenSUSE}
        $environment += @{'IsAlpine' = $LinuxInfo.ID -match 'alpine'}

        # Workaround for temporary LD_LIBRARY_PATH hack for Fedora 24
        # https://github.com/PowerShell/PowerShell/issues/2511
        if ($environment.IsFedora -and (Test-Path ENV:\LD_LIBRARY_PATH)) {
            Remove-Item -Force ENV:\LD_LIBRARY_PATH
            Get-ChildItem ENV:
        }
    }

    return [PSCustomObject] $environment
}

$Environment = Get-EnvironmentInformation

# Autoload (in current session) temporary modules used in our tests
$TestModulePath = Join-Path $PSScriptRoot "test/tools/Modules"
if ( -not $env:PSModulePath.Contains($TestModulePath) ) {
    $env:PSModulePath = $TestModulePath+$TestModulePathSeparator+$($env:PSModulePath)
}

function Test-Win10SDK {
    # The Windows 10 SDK is installed to "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x64",
    # but the directory may exist even if the SDK has not been installed.
    #
    # A slightly more robust check is for the mc.exe binary within that directory.
    # It is only present if the SDK is installed.

    return (Test-Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\mc.exe")
}

function Get-LatestWinSDK {
    $latestSDKPath = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10*" | Sort-Object -Descending | Select-Object -First 1

    ## Always use x64 as we expect to build on an x64 build machine.
    $archSpecificPath = Join-Path $latestSDKPath -ChildPath "x64"
    return $archSpecificPath
}

function Start-BuildNativeWindowsBinaries {
    param(
        [ValidateSet('Debug', 'Release')]
        [string]$Configuration = 'Release',

        # The `x64_arm` syntax is the build environment for VS2017, `x64` means the host is an x64 machine and will use
        # the x64 built tool.  The `arm` refers to the target architecture when doing cross compilation.
        [ValidateSet('x64', 'x86', 'x64_arm64', 'x64_arm')]
        [string]$Arch = 'x64',

        [switch]$Clean
    )

    if (-not $Environment.IsWindows) {
        Write-Warning -Message "'Start-BuildNativeWindowsBinaries' is only supported on Windows platforms"
        return
    }

    # cmake is needed to build pwsh.exe
    if (-not (precheck 'cmake' $null)) {
        throw 'cmake not found. Run "Start-PSBootstrap -BuildWindowsNative". You can also install it from https://chocolatey.org/packages/cmake'
    }

    Use-MSBuild

    # mc.exe is Message Compiler for native resources
    if (-Not (Test-Win10SDK)) {
        throw 'Win 10 SDK not found. Run "Start-PSBootstrap -BuildWindowsNative" or install Microsoft Windows 10 SDK from https://developer.microsoft.com/en-US/windows/downloads/windows-10-sdk'
    }

    if ($env:VS140COMNTOOLS -ne $null) {
        $vcPath = (Get-Item(Join-Path -Path "$env:VS140COMNTOOLS" -ChildPath '../../vc')).FullName
    }
    Write-Verbose -Verbose "VCPath: $vcPath"

    $alternateVCPath = (Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2017" -Filter "VC" -Directory -Recurse).FullName
    Write-Verbose -Verbose "alternateVCPath: $alternateVCPath"

    $atlBaseFound = $false

    if ($alternateVCPath) {
        foreach($candidatePath in $alternateVCPath) {
            Write-Verbose -Verbose "Looking under $candidatePath"
            $atlMfcIncludePath = @(Get-ChildItem -Path $candidatePath -Recurse -Filter 'atlbase.h' -File)

            $atlMfcIncludePath | ForEach-Object {
                if($_.FullName.EndsWith('atlmfc\include\atlbase.h')) {
                    Write-Verbose -Verbose "ATLF MFC found under $($_.FullName)"
                    $atlBaseFound = $true
                    break
                }
            }
        }
    } elseif ($vcPath) {
        $atlMfcIncludePath = Join-Path -Path $vcPath -ChildPath 'atlmfc/include'
        if(Test-Path -Path "$atlMfcIncludePath\atlbase.h") {
            Write-Verbose -Verbose "ATLF MFC found under $atlMfcIncludePath\atlbase.h"
            $atlBaseFound = $true
        }
    } else {
        Write-Verbose -Verbose "PATH: $env:PATH"
        throw "Visual Studio tools not found in PATH."
    }

    # atlbase.h is included in the pwrshplugin project
    if (-not $atlBaseFound) {
        throw "Could not find Visual Studio include file atlbase.h at $atlMfcIncludePath. Please ensure the optional feature 'Microsoft Foundation Classes for C++' is installed."
    }

    # vcvarsall.bat is used to setup environment variables
    $vcvarsallbatPath = "$vcPath\vcvarsall.bat"
    $vcvarsallbatPathVS2017 = ( Get-ChildItem $alternateVCPath -Filter vcvarsall.bat -Recurse -File | Select-Object -First 1).FullName

    if(Test-Path $vcvarsallbatPathVS2017)
    {
        # prefer VS2017 path
        $vcvarsallbatPath = $vcvarsallbatPathVS2017
    }

    if ([string]::IsNullOrEmpty($vcvarsallbatPath) -or (Test-Path -Path $vcvarsallbatPath) -eq $false) {
        throw "Could not find Visual Studio vcvarsall.bat at $vcvarsallbatPath. Please ensure the optional feature 'Common Tools for Visual C++' is installed."
    }

    Write-Log "Start building native Windows binaries"

    if ($Clean) {
        Push-Location .
        try {
            Set-Location $PSScriptRoot
            git clean -fdx
            Remove-Item $HOME\source\cmakecache.txt -ErrorAction SilentlyContinue
        }
        finally {
            Pop-Location
        }
    }

    try {
        Push-Location "$PSScriptRoot\src\powershell-native"

        # setup cmakeGenerator
        $cmakeGeneratorPlatform = ""
        if ($Arch -eq 'x86') {
            $cmakeGenerator = 'Visual Studio 15 2017'
            $cmakeArch = 'x86'
        } elseif ($Arch -eq 'x64_arm') {
            $cmakeGenerator = 'Visual Studio 15 2017 ARM'
            $cmakeArch = 'arm'
        } elseif ($Arch -eq 'x64_arm64') {
            $cmakeGenerator = 'Visual Studio 15 2017'
            $cmakeArch = 'arm64'
            $cmakeGeneratorPlatform = "-A ARM64"
        } else {
            $cmakeGenerator = 'Visual Studio 15 2017 Win64'
            $cmakeArch = 'x64'
        }

        # Compile native resources
        $currentLocation = Get-Location
        $savedPath = $env:PATH
        $sdkPath = Get-LatestWinSDK

        try {
            $env:PATH = "$sdkPath;$env:PATH"
            $mcFound = Get-Command mc.exe
            Write-Log "MC Found = $($mcFound.Source)"

            @("nativemsh\pwrshplugin") | ForEach-Object {
                $nativeResourcesFolder = $_
                Get-ChildItem $nativeResourcesFolder -Filter "*.mc" | ForEach-Object {
                    $command = @"
cmd.exe /C cd /d "$currentLocation" "&" "$vcvarsallbatPath" "$Arch" "&" mc.exe -o -d -c -U "$($_.FullName)" -h "$currentLocation\$nativeResourcesFolder" -r "$currentLocation\$nativeResourcesFolder"
"@
                    Write-Log "  Executing mc.exe Command: $command"
                    Start-NativeExecution { Invoke-Expression -Command:$command } -VerboseOutputOnError
                }
            }
        }
        finally {
            $env:PATH = $savedPath
        }

        # make sure we use version we installed and not from VS
        $cmakePath = (Get-Command cmake).Source
        # Disabling until I figure out if it is necessary
        # $overrideFlags = "-DCMAKE_USER_MAKE_RULES_OVERRIDE=$PSScriptRoot\src\powershell-native\windows-compiler-override.txt"
        $overrideFlags = ""
        $command = @"
cmd.exe /C cd /d "$currentLocation" "&" "$vcvarsallbatPath" "$Arch" "&" "$cmakePath" "$overrideFlags" -DBUILD_ONECORE=ON -DBUILD_TARGET_ARCH=$cmakeArch -G "$cmakeGenerator" $cmakeGeneratorPlatform "$currentLocation" "&" msbuild ALL_BUILD.vcxproj "/p:Configuration=$Configuration"
"@
        Write-Log "  Executing Build Command: $command"
        Start-NativeExecution { Invoke-Expression -Command:$command }

        # Copy the binaries from the local build directory to the packaging directory
        $FilesToCopy = @('pwrshplugin.dll', 'pwrshplugin.pdb')
        $dstPath = "$PSScriptRoot\src\powershell-win-core"

        if(-not (Test-Path $dstPath))
        {
            New-Item -ItemType Directory -Path $dstPath -Force > $null
        }

        $FilesToCopy | ForEach-Object {
            $srcPath = [IO.Path]::Combine((Get-Location), "bin", $Configuration, "CoreClr/$_")

            Write-Log "  Copying $srcPath to $dstPath"
            Copy-Item $srcPath $dstPath
        }

        #
        #   Build the ETW manifest resource-only binary
        #
        $location = "$PSScriptRoot\src\PowerShell.Core.Instrumentation"
        Set-Location -Path $location

        Remove-Item $HOME\source\cmakecache.txt -ErrorAction SilentlyContinue

        $command = @"
cmd.exe /C cd /d "$location" "&" "$vcvarsallbatPath" "$Arch" "&" "$cmakePath" "$overrideFlags" -DBUILD_ONECORE=ON -DBUILD_TARGET_ARCH=$cmakeArch -G "$cmakeGenerator" $cmakeGeneratorPlatform "$location" "&" msbuild ALL_BUILD.vcxproj "/p:Configuration=$Configuration"
"@
        Write-Log "  Executing Build Command for PowerShell.Core.Instrumentation: $command"
        Start-NativeExecution { Invoke-Expression -Command:$command }
<#
        # Copy the binary to the packaging directory
        # NOTE: No PDB file; it's a resource-only DLL.
        # VS2017 puts this in $HOME\source
        $srcPath = [IO.Path]::Combine($HOME, "source", $Configuration, 'PowerShell.Core.Instrumentation.dll')
        Copy-Item -Path $srcPath -Destination $dstPat
#>

        $builtBinary = (Get-ChildItem -Path $location -Filter 'PowerShell.Core.Instrumentation.dll' -Recurse | Select-Object -First 1).FullName

        if(-not (Test-Path $builtBinary))
        {
            throw "PowerShell.Core.Instrumentation was not found under $location"
        }
        else
        {
            Copy-Item $builtBinary -Destination $dstPath -Force
        }


    } finally {
        Pop-Location
    }
}

function Start-BuildNativeUnixBinaries {
    param (
        [switch] $BuildLinuxArm,
        [switch] $BuildLinuxArm64
    )

    if (-not $Environment.IsLinux -and -not $Environment.IsMacOS) {
        Write-Warning -Message "'Start-BuildNativeUnixBinaries' is only supported on Linux/macOS platforms"
        return
    }

    if (($BuildLinuxArm -or $BuildLinuxArm64) -and -not $Environment.IsUbuntu) {
        throw "Cross compiling for linux-arm/linux-arm64 are only supported on Ubuntu environment"
    }

    # Verify we have all tools in place to do the build
    $precheck = $true
    foreach ($Dependency in 'cmake', 'make', 'g++') {
        $precheck = $precheck -and (precheck $Dependency "Build dependency '$Dependency' not found. Run 'Start-PSBootstrap'.")
    }

    if ($BuildLinuxArm) {
        foreach ($Dependency in 'arm-linux-gnueabihf-gcc', 'arm-linux-gnueabihf-g++') {
            $precheck = $precheck -and (precheck $Dependency "Build dependency '$Dependency' not found. Run 'Start-PSBootstrap'.")
        }
    } elseif ($BuildLinuxArm64) {
        foreach ($Dependency in 'aarch64-linux-gnu-gcc', 'aarch64-linux-gnu-g++') {
            $precheck = $precheck -and (precheck $Dependency "Build dependency '$Dependency' not found. Run 'Start-PSBootstrap'.")
        }
    }

    # Abort if any precheck failed
    if (-not $precheck) {
        return
    }

    # Build native components
    $Ext = if ($Environment.IsLinux) {
        "so"
    } elseif ($Environment.IsMacOS) {
        "dylib"
    }

    $Native = "$PSScriptRoot/src/libpsl-native"
    $Lib = "$PSScriptRoot/src/powershell-unix/libpsl-native.$Ext"
    Write-Log "Start building $Lib"

    git clean -qfdX $Native

    # the stat tests rely on stat(1). On most platforms, this is /usr/bin/stat,
    # but on alpine it is in /bin. Be sure that /usr/bin/stat exists, or
    # create a link from /bin/stat. If /bin/stat is missing, we'll have to fail the build

    if ( ! (Test-Path /usr/bin/stat) ) {
        if ( Test-Path /bin/stat ) {
            New-Item -Type SymbolicLink -Path /usr/bin/stat -Target /bin/stat
        }
        else {
            throw "Cannot create symlink to stat(1)"
        }
    }

    try {
        Push-Location $Native
        if ($BuildLinuxArm) {
            Start-NativeExecution { cmake -DCMAKE_TOOLCHAIN_FILE="./arm.toolchain.cmake" . }
            Start-NativeExecution { make -j }
        }
        elseif ($BuildLinuxArm64) {
            Start-NativeExecution { cmake -DCMAKE_TOOLCHAIN_FILE="./arm64.toolchain.cmake" . }
            Start-NativeExecution { make -j }
        }
        elseif ($IsMacOS) {
            Start-NativeExecution { cmake -DCMAKE_TOOLCHAIN_FILE="./macos.toolchain.cmake" . }
            Start-NativeExecution { make -j }
            Start-NativeExecution { ctest --verbose }
        }
        else {
            Start-NativeExecution { cmake -DCMAKE_BUILD_TYPE=Debug . }
            Start-NativeExecution { make -j }
            Start-NativeExecution { ctest --verbose }
        }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $Lib)) {
        throw "Compilation of $Lib failed"
    }
}

<#
.SYNOPSIS
 Expand the zip files, create NuGet package layout and then pack the nuget package.
#>
function Start-BuildPowerShellNativePackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackageRoot,

        [Parameter(Mandatory = $true)]
        [string] $Version,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $WindowsX64ZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $WindowsX86ZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $WindowsARMZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $WindowsARM64ZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $LinuxZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $LinuxARMZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $LinuxARM64ZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $LinuxAlpineZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $macOSZipPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string] $psrpZipPath,

        [Parameter(Mandatory = $true)]
        [string] $NuGetOutputPath,

        [switch] $SkipCleanup = $false
    )

    if(-not (Test-Path $PackageRoot))
    {
        Write-Log "Creating PackageRoot: $PackageRoot as it does not exist."
    }

    $tempExtractionPath = New-Item -ItemType Directory -Path "$env:TEMP\$(New-Guid)" -Force

    Write-Log "Created tempExtractionPath: $tempExtractionPath"

    $BinFolderX64 = Join-Path $tempExtractionPath "x64"
    $BinFolderX86 = Join-Path $tempExtractionPath "x86"
    $BinFolderARM = Join-Path $tempExtractionPath "ARM"
    $BinFolderARM64 = Join-Path $tempExtractionPath "ARM64"
    $BinFolderLinux = Join-Path $tempExtractionPath "Linux"
    $BinFolderLinuxARM = Join-Path $tempExtractionPath "LinuxARM"
    $BinFolderLinuxARM64 = Join-Path $tempExtractionPath "LinuxARM64"
    $BinFolderLinuxAlpine = Join-Path $tempExtractionPath "LinuxAlpine"
    $BinFolderMacOS = Join-Path $tempExtractionPath "MacOS"
    $BinFolderPSRP = Join-Path $tempExtractionPath "PSRP"

    Expand-Archive -Path $WindowsX64ZipPath -DestinationPath $BinFolderX64 -Force
    Expand-Archive -Path $WindowsX86ZipPath -DestinationPath $BinFolderX86 -Force
    Expand-Archive -Path $WindowsARMZipPath -DestinationPath $BinFolderARM -Force
    Expand-Archive -Path $WindowsARM64ZipPath -DestinationPath $BinFolderARM64 -Force
    Expand-Archive -Path $LinuxZipPath -DestinationPath $BinFolderLinux -Force
    Expand-Archive -Path $LinuxAlpineZipPath -DestinationPath $BinFolderLinuxAlpine -Force
    Expand-Archive -Path $LinuxARMZipPath -DestinationPath $BinFolderLinuxARM -Force
    Expand-Archive -Path $LinuxARM64ZipPath -DestinationPath $BinFolderLinuxARM64 -Force
    Expand-Archive -Path $macOSZipPath -DestinationPath $BinFolderMacOS -Force
    Expand-Archive -Path $psrpZipPath -DestinationPath $BinFolderPSRP -Force

    PlaceWindowsNativeBinaries -PackageRoot $PackageRoot -BinFolderX64 $BinFolderX64 -BinFolderX86 $BinFolderX86 -BinFolderARM $BinFolderARM -BinFolderARM64 $BinFolderARM64

    PlaceUnixBinaries -PackageRoot $PackageRoot -BinFolderLinux $BinFolderLinux -BinFolderLinuxARM $BinFolderLinuxARM -BinFolderLinuxARM64 $BinFolderLinuxARM64 -BinFolderOSX $BinFolderMacOS -BinFolderPSRP $BinFolderPSRP -BinFolderLinuxAlpine $BinFolderLinuxAlpine

    $Nuspec = @'
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2011/10/nuspec.xsd">
    <metadata>
        <id>Microsoft.PowerShell.Native</id>
        <version>{0}</version>
        <authors>Microsoft</authors>
        <owners>Microsoft,PowerShell</owners>
        <requireLicenseAcceptance>false</requireLicenseAcceptance>
        <description>Native binaries for PowerShell Core</description>
        <projectUrl>https://github.com/PowerShell/PowerShell-Native</projectUrl>
        <icon>{1}</icon>
        <license type="expression">MIT</license>
        <tags>PowerShell</tags>
        <language>en-US</language>
        <copyright>&#169; Microsoft Corporation. All rights reserved.</copyright>
        <contentFiles>
            <files include="**/*" buildAction="None" copyToOutput="true" flatten="false" />
        </contentFiles>
    </metadata>
</package>
'@

    $iconFileName = "Powershell_black_64.png"
    $iconPath = Join-Path $PSScriptRoot -ChildPath "assets\$iconFileName" -Resolve

    Copy-Item $iconPath (Join-Path $PackageRoot -ChildPath $iconFileName) -Verbose

    $Nuspec -f $Version, $iconFileName | Out-File -FilePath (Join-Path $PackageRoot -ChildPath 'Microsoft.PowerShell.Native.nuspec') -Force

    if(-not (Test-Path $NuGetOutputPath))
    {
        $null = New-Item $NuGetOutputPath -Force -Verbose -ItemType Directory
    }

    try {
        Push-Location $PackageRoot
        nuget.exe pack . -OutputDirectory $NuGetOutputPath
    }
    finally {
        Pop-Location
    }

    if(-not $SkipCleanup -and (Test-Path $tempExtractionPath))
    {
        Remove-Item $tempExtractionPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
 Copy the binaries for the PowerShell Native nuget package to appropriate runtime folders.
#>
function PlaceUnixBinaries
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $PackageRoot,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderLinux,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderLinuxARM,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderLinuxARM64,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderLinuxAlpine,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderOSX,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderPSRP
    )

    $RuntimePathLinux = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/linux-x64/native') -Force
    $RuntimePathLinuxARM = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/linux-arm/native') -Force
    $RuntimePathLinuxARM64 = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/linux-arm64/native') -Force
    $RuntimePathLinuxAlpine = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/linux-musl-x64/native') -Force
    $RuntimePathOSX = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/osx/native') -Force

    Copy-Item "$BinFolderLinux\*" -Destination $RuntimePathLinux -Verbose
    Copy-Item "$BinFolderLinuxARM\*" -Destination $RuntimePathLinuxARM -Verbose
    Copy-Item "$BinFolderLinuxARM64\*" -Destination $RuntimePathLinuxARM64 -Verbose
    Copy-Item "$BinFolderLinuxAlpine\*" -Destination $RuntimePathLinuxAlpine -Verbose
    Copy-Item "$BinFolderOSX\*" -Destination $RuntimePathOSX -Verbose

    ## LinuxARM is not supported by PSRP
    Get-ChildItem -Recurse $BinFolderPSRP/*.dylib | ForEach-Object { Copy-Item $_.FullName -Destination $RuntimePathOSX -Verbose }
    Get-ChildItem -Recurse $BinFolderPSRP/*.so | ForEach-Object { Copy-Item $_.FullName -Destination $RuntimePathLinux -Verbose }

    Copy-Item $BinFolderPSRP/version.txt -Destination "$PackageRoot/PSRP_version.txt" -Verbose
}

<#
.SYNOPSIS
 Copy the binaries for the PowerShell Native nuget package to appropriate runtime folders.
#>
function PlaceWindowsNativeBinaries
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $PackageRoot,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderX64,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderX86,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderARM,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        $BinFolderARM64
    )

    $RuntimePathX64 = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/win-x64/native') -Force
    $RuntimePathX86 = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/win-x86/native') -Force
    $RuntimePathARM = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/win-arm/native') -Force
    $RuntimePathARM64 = New-Item -ItemType Directory -Path (Join-Path $PackageRoot -ChildPath 'runtimes/win-arm64/native') -Force

    Copy-Item "$BinFolderX64\*" -Destination $RuntimePathX64 -Verbose -Exclude '*.pdb'
    Copy-Item "$BinFolderX86\*" -Destination $RuntimePathX86 -Verbose -Exclude '*.pdb'
    Copy-Item "$BinFolderARM\*" -Destination $RuntimePathARM -Verbose -Exclude '*.pdb'
    Copy-Item "$BinFolderARM64\*" -Destination $RuntimePathARM64 -Verbose -Exclude '*.pdb'
}

<#
.SYNOPSIS
Publish the specified Nuget Package to MyGet feed.

.DESCRIPTION
The specified nuget package is published to the powershell.myget.org/powershell-core feed.

.PARAMETER PackagePath
Path to the NuGet Package.

.PARAMETER ApiKey
API key for powershell.myget.org
#>
function Publish-NugetToMyGet
{
    param(
        [Parameter(Mandatory = $true)]
        [string] $PackagePath,

        [Parameter(Mandatory = $true)]
        [string] $ApiKey
    )

    $nuget = Get-Command -Type Application nuget -ErrorAction SilentlyContinue

    if($nuget -eq $null)
    {
        throw 'nuget application is not available in PATH'
    }

    Get-ChildItem $PackagePath | ForEach-Object {
        Write-Log "Pushing $_ to PowerShell Myget"
        Start-NativeExecution { nuget push $_.FullName -Source 'https://powershell.myget.org/F/powershell-core/api/v2/package' -ApiKey $ApiKey } > $null
    }
}

function Start-PSBuild {
    [CmdletBinding()]
    param(
        # When specified this switch will stops running dev powershell
        # to help avoid compilation error, because file are in use.
        [switch]$StopDevPowerShell,

        [switch]$Restore,
        [string]$Output,
        [switch]$ResGen,
        [switch]$TypeGen,
        [switch]$Clean,
        [switch]$PSModuleRestore,
        [switch]$CI,

        # this switch will re-build only System.Management.Automation.dll
        # it's useful for development, to do a quick changes in the engine
        [switch]$SMAOnly,

        # These runtimes must match those in project.json
        # We do not use ValidateScript since we want tab completion
        # If this parameter is not provided it will get determined automatically.
        [ValidateSet("win7-x64",
                     "win7-x86",
                     "osx-arm64",
                     "osx-x64",
                     "linux-x64",
                     "linux-arm",
                     "linux-arm64",
                     "win-arm",
                     "win-arm64")]
        [string]$Runtime,

        [ValidateSet('Debug', 'Release', 'CodeCoverage', '')] # We might need "Checked" as well
        [string]$Configuration,

        [switch]$CrossGen,

        [ValidatePattern("^v\d+\.\d+\.\d+(-\w+(\.\d+)?)?$")]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseTag
    )

    if (($Runtime -eq "linux-arm" -or $Runtime -eq "linux-arm64") -and -not $Environment.IsUbuntu) {
        throw "Cross compiling for linux-arm/linux-arm64 are only supported on Ubuntu environment"
    }

    if ("win-arm","win-arm64" -contains $Runtime -and -not $Environment.IsWindows) {
        throw "Cross compiling for win-arm or win-arm64 is only supported on Windows environment"
    }

    function Stop-DevPowerShell {
        Get-Process pwsh* |
            Where-Object {
                $_.Modules |
                Where-Object {
                    $_.FileName -eq (Resolve-Path $script:Options.Output).Path
                }
            } |
        Stop-Process -Verbose
    }

    if ($Clean) {
        Write-Log "Cleaning your working directory. You can also do it with 'git clean -fdX'"
        Push-Location $PSScriptRoot
        try {
            git clean -fdX
            # Extra cleaning is required to delete the CMake temporary files.
            # These are not cleaned when using "X" and cause CMake to retain state, leading to
            # mis-configured environment issues when switching between x86 and x64 compilation
            # environments.
            git clean -fdx .\src\powershell-native
        } finally {
            Pop-Location
        }
    }

    # Add .NET CLI tools to PATH
    Find-Dotnet

    # Verify we have .NET SDK in place to do the build, and abort if the precheck failed
    $precheck = precheck 'dotnet' "Build dependency 'dotnet' not found in PATH. Run Start-PSBootstrap. Also see: https://dotnet.github.io/getting-started/"
    if (-not $precheck) {
        return
    }

    # Verify if the dotnet in-use is the required version
    $dotnetCLIInstalledVersion = (dotnet --version)
    If ($dotnetCLIInstalledVersion -ne $dotnetCLIRequiredVersion) {
        Write-Warning @"
The currently installed .NET Command Line Tools is not the required version.

Installed version: $dotnetCLIInstalledVersion
Required version: $dotnetCLIRequiredVersion

Fix steps:

1. Remove the installed version from:
    - on windows '`$env:LOCALAPPDATA\Microsoft\dotnet'
    - on macOS and linux '`$env:HOME/.dotnet'
2. Run Start-PSBootstrap or Install-Dotnet
3. Start-PSBuild -Clean
`n
"@
        return
    }

    # set output options
    $OptionsArguments = @{
        CrossGen=$CrossGen
        Output=$Output
        Runtime=$Runtime
        Configuration=$Configuration
        Verbose=$true
        SMAOnly=[bool]$SMAOnly
        PSModuleRestore=$PSModuleRestore
    }
    $script:Options = New-PSOptions @OptionsArguments

    if ($StopDevPowerShell) {
        Stop-DevPowerShell
    }

    # setup arguments
    $Arguments = @("publish","--no-restore","/property:GenerateFullPaths=true")
    if ($Output) {
        $Arguments += "--output", $Output
    }
    elseif ($SMAOnly) {
        $Arguments += "--output", (Split-Path $script:Options.Output)
    }

    $Arguments += "--configuration", $Options.Configuration
    $Arguments += "--framework", $Options.Framework

    if (-not $SMAOnly) {
        # libraries should not have runtime
        $Arguments += "--runtime", $Options.Runtime
    }

    if ($ReleaseTag) {
        $ReleaseTagToUse = $ReleaseTag -Replace '^v'
        $Arguments += "/property:ReleaseTag=$ReleaseTagToUse"
    }

    # handle Restore
    Restore-PSPackage -Options $Options -Force:$Restore

    # handle ResGen
    # Heuristic to run ResGen on the fresh machine
    if ($ResGen -or -not (Test-Path "$PSScriptRoot/src/Microsoft.PowerShell.ConsoleHost/gen")) {
        Write-Log "Run ResGen (generating C# bindings for resx files)"
        Start-ResGen
    }

    # Handle TypeGen
    # .inc file name must be different for Windows and Linux to allow build on Windows and WSL.
    $incFileName = "powershell_$($Options.Runtime).inc"
    if ($TypeGen -or -not (Test-Path "$PSScriptRoot/src/TypeCatalogGen/$incFileName")) {
        Write-Log "Run TypeGen (generating CorePsTypeCatalog.cs)"
        Start-TypeGen -IncFileName $incFileName
    }

    # Get the folder path where pwsh.exe is located.
    $publishPath = Split-Path $Options.Output -Parent
    try {
        # Relative paths do not work well if cwd is not changed to project
        Push-Location $Options.Top
        Write-Log "Run dotnet $Arguments from $pwd"
        Start-NativeExecution { dotnet $Arguments }

        if ($CrossGen) {
            Start-CrossGen -PublishPath $publishPath -Runtime $script:Options.Runtime
            Write-Log "pwsh.exe with ngen binaries is available at: $($Options.Output)"
        } else {
            Write-Log "PowerShell output: $($Options.Output)"
        }
    } finally {
        Pop-Location
    }

    # publish netcoreapp2.1 reference assemblies
    try {
        Push-Location "$PSScriptRoot/src/TypeCatalogGen"
        $refAssemblies = Get-Content -Path $incFileName | Where-Object { $_ -like "*microsoft.netcore.app*" } | ForEach-Object { $_.TrimEnd(';') }
        $refDestFolder = Join-Path -Path $publishPath -ChildPath "ref"

        if (Test-Path $refDestFolder -PathType Container) {
            Remove-Item $refDestFolder -Force -Recurse -ErrorAction Stop
        }
        New-Item -Path $refDestFolder -ItemType Directory -Force -ErrorAction Stop > $null
        Copy-Item -Path $refAssemblies -Destination $refDestFolder -Force -ErrorAction Stop
    } finally {
        Pop-Location
    }

    if ($Environment.IsRedHatFamily) {
        # add two symbolic links to system shared libraries that libmi.so is dependent on to handle
        # platform specific changes. This is the only set of platforms needed for this currently
        # as Ubuntu has these specific library files in the platform and macOS builds for itself
        # against the correct versions.
        if ( ! (test-path "$publishPath/libssl.so.1.0.0")) {
            $null = New-Item -Force -ItemType SymbolicLink -Target "/lib64/libssl.so.10" -Path "$publishPath/libssl.so.1.0.0" -ErrorAction Stop
        }
        if ( ! (test-path "$publishPath/libcrypto.so.1.0.0")) {
            $null = New-Item -Force -ItemType SymbolicLink -Target "/lib64/libcrypto.so.10" -Path "$publishPath/libcrypto.so.1.0.0" -ErrorAction Stop
        }
    }

    if ($Environment.IsWindows) {
        ## need RCEdit to modify the binaries embedded resources
        if (-not (Test-Path "~/.rcedit/rcedit-x64.exe")) {
            throw "RCEdit is required to modify pwsh.exe resources, please run 'Start-PSBootStrap' to install"
        }

        $ReleaseVersion = ""
        if ($ReleaseTagToUse) {
            $ReleaseVersion = $ReleaseTagToUse
        } else {
            $ReleaseVersion = (Get-PSCommitId -WarningAction SilentlyContinue) -replace '^v'
        }
        # in VSCode, depending on where you started it from, the git commit id may be empty so provide a default value
        if (!$ReleaseVersion) {
            $ReleaseVersion = "6.0.0"
            $fileVersion = "6.0.0"
        } else {
            $fileVersion = $ReleaseVersion.Split("-")[0]
        }

        # in VSCode, the build output folder doesn't include the name of the exe so we have to add it for rcedit
        $pwshPath = $Options.Output
        if (!$pwshPath.EndsWith("pwsh.exe")) {
            $pwshPath = Join-Path $Options.Output "pwsh.exe"
        }

        Start-NativeExecution { & "~/.rcedit/rcedit-x64.exe" $pwshPath --set-icon "$PSScriptRoot\assets\Powershell_black.ico" `
            --set-file-version $fileVersion --set-product-version $ReleaseVersion --set-version-string "ProductName" "PowerShell Core 6" `
            --set-version-string "LegalCopyright" "(c) Microsoft Corporation." `
            --application-manifest "$PSScriptRoot\assets\pwsh.manifest" } | Write-Verbose
    }

    # download modules from powershell gallery.
    #   - PowerShellGet, PackageManagement, Microsoft.PowerShell.Archive
    if ($PSModuleRestore) {
        Restore-PSModuleToBuild -PublishPath $publishPath
    }

    # Restore the Pester module
    if ($CI) {
        Restore-PSPester -Destination (Join-Path $publishPath "Modules")
    }
}

function Restore-PSPackage
{
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter()]
        [string[]] $ProjectDirs,

        [ValidateNotNullOrEmpty()]
        [Parameter()]
        $Options = (Get-PSOptions -DefaultToNew),

        [switch] $Force
    )

    if (-not $ProjectDirs)
    {
        $ProjectDirs = @($Options.Top, "$PSScriptRoot/src/TypeCatalogGen", "$PSScriptRoot/src/ResGen", "$PSScriptRoot/src/Modules")
    }

    if ($Force -or (-not (Test-Path "$($Options.Top)/obj/project.assets.json"))) {

        $RestoreArguments = @("--runtime",$Options.Runtime,"--verbosity")
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            $RestoreArguments += "detailed"
        } else {
            $RestoreArguments += "quiet"
        }

        $ProjectDirs | ForEach-Object {
            Write-Log "Run dotnet restore $_ $RestoreArguments"
            Start-NativeExecution { dotnet restore $_ $RestoreArguments }
        }
    }
}

function Restore-PSModuleToBuild
{
    param(
        [Parameter(Mandatory)]
        [string]
        $PublishPath
    )

    Write-Log "Restore PowerShell modules to $publishPath"
    $modulesDir = Join-Path -Path $publishPath -ChildPath "Modules"
    Copy-PSGalleryModules -Destination $modulesDir
}

function Restore-PSPester
{
    param(
        [ValidateNotNullOrEmpty()]
        [string] $Destination = ([IO.Path]::Combine((Split-Path (Get-PSOptions -DefaultToNew).Output), "Modules"))
    )
    Save-Module -Name Pester -Path $Destination -Repository PSGallery -RequiredVersion "4.2"
}

function Compress-TestContent {
    [CmdletBinding()]
    param(
        $Destination
    )

    $null = Publish-PSTestTools
    $powerShellTestRoot =  Join-Path $PSScriptRoot 'test'
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    [System.IO.Compression.ZipFile]::CreateFromDirectory($powerShellTestRoot, $resolvedPath)
}

function New-PSOptions {
    [CmdletBinding()]
    param(
        [ValidateSet("Debug", "Release", "CodeCoverage", '')]
        [string]$Configuration,

        [ValidateSet("netcoreapp2.1")]
        [string]$Framework,

        # These are duplicated from Start-PSBuild
        # We do not use ValidateScript since we want tab completion
        [ValidateSet("",
                     "win7-x86",
                     "win7-x64",
                     "osx-arm64",
                     "osx-x64",
                     "linux-x64",
                     "linux-arm",
                     "linux-arm64",
                     "win-arm",
                     "win-arm64")]
        [string]$Runtime,

        [switch]$CrossGen,

        [string]$Output,

        [switch]$SMAOnly,

        [switch]$PSModuleRestore
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    $ConfigWarningMsg = "The passed-in Configuration value '{0}' is not supported on '{1}'. Use '{2}' instead."
    if (-not $Configuration) {
        $Configuration = 'Debug'
    } else {
        switch ($Configuration) {
            "CodeCoverage" {
                if(-not $Environment.IsWindows) {
                    $Configuration = "Debug"
                    Write-Warning ($ConfigWarningMsg -f $switch.Current, $Environment.LinuxInfo.PRETTY_NAME, $Configuration)
                }
            }
        }
    }
    Write-Verbose "Using configuration '$Configuration'"

    $PowerShellDir = if (!$Environment.IsWindows) {
        "powershell-unix"
    } else {
        "powershell-win-core"
    }
    $Top = [IO.Path]::Combine($PSScriptRoot, "src", $PowerShellDir)
    Write-Verbose "Top project directory is $Top"

    if (-not $Framework) {
        $Framework = "netcoreapp2.1"
        Write-Verbose "Using framework '$Framework'"
    }

    if (-not $Runtime) {
        if ($Environment.IsLinux) {
            $Runtime = "linux-x64"
        } elseif ($Environment.IsMacOS) {
            if ($PSVersionTable.OS.Contains('ARM64')) {
                $Runtime = "osx-arm64"
            }
            else {
                $Runtime = "osx-x64"
            }
        } else {
            $RID = dotnet --info | ForEach-Object {
                if ($_ -match "RID") {
                    $_ -split "\s+" | Select-Object -Last 1
                }
            }

            # We plan to release packages targetting win7-x64 and win7-x86 RIDs,
            # which supports all supported windows platforms.
            # So we, will change the RID to win7-<arch>
            $Runtime = $RID -replace "win\d+", "win7"
        }

        if (-not $Runtime) {
            Throw "Could not determine Runtime Identifier, please update dotnet"
        } else {
            Write-Verbose "Using runtime '$Runtime'"
        }
    }

    $Executable = if ($Environment.IsLinux -or $Environment.IsMacOS) {
        "pwsh"
    } elseif ($Environment.IsWindows) {
        "pwsh.exe"
    }

    # Build the Output path
    if (!$Output) {
        $Output = [IO.Path]::Combine($Top, "bin", $Configuration, $Framework, $Runtime, "publish", $Executable)
    }

    if ($SMAOnly)
    {
        $Top = [IO.Path]::Combine($PSScriptRoot, "src", "System.Management.Automation")
    }

    $RootInfo = @{RepoPath = $PSScriptRoot}

    # the valid root is the root of the filesystem and the folder PowerShell
    $RootInfo['ValidPath'] = Join-Path -Path ([system.io.path]::GetPathRoot($RootInfo.RepoPath)) -ChildPath 'PowerShell'

    if($RootInfo.RepoPath -ne $RootInfo.ValidPath)
    {
        $RootInfo['Warning'] = "Please ensure your repo is at the root of the file system and named 'PowerShell' (example: '$($RootInfo.ValidPath)'), when building and packaging for release!"
        $RootInfo['IsValid'] = $false
    }
    else
    {
        $RootInfo['IsValid'] = $true
    }

    return @{ RootInfo = [PSCustomObject]$RootInfo
              Top = $Top
              Configuration = $Configuration
              Framework = $Framework
              Runtime = $Runtime
              Output = $Output
              CrossGen = $CrossGen.IsPresent
              PSModuleRestore = $PSModuleRestore.IsPresent }
}

# Get the Options of the last build
function Get-PSOptions {
    param(
        [Parameter(HelpMessage='Defaults to New-PSOption if a build has not ocurred.')]
        [switch]
        $DefaultToNew
    )

    if(!$script:Options -and $DefaultToNew.IsPresent)
    {
        return New-PSOptions
    }

    return $script:Options
}

function Set-PSOptions {
    param(
        [PSObject]
        $Options
    )

    $script:Options = $Options
}

function Get-PSOutput {
    [CmdletBinding()]param(
        [hashtable]$Options
    )
    if ($Options) {
        return $Options.Output
    } elseif ($script:Options) {
        return $script:Options.Output
    } else {
        return (New-PSOptions).Output
    }
}

function Get-PesterTag {
    param ( [Parameter(Position=0)][string]$testbase = "$PSScriptRoot/test/powershell" )
    $alltags = @{}
    $warnings = @()

    get-childitem -Recurse $testbase -File | Where-Object {$_.name -match "tests.ps1"}| ForEach-Object {
        $fullname = $_.fullname
        $tok = $err = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$tok,[ref]$err)
        $des = $ast.FindAll({$args[0] -is "System.Management.Automation.Language.CommandAst" -and $args[0].CommandElements[0].Value -eq "Describe"},$true)
        foreach( $describe in $des) {
            $elements = $describe.CommandElements
            $lineno = $elements[0].Extent.StartLineNumber
            $foundPriorityTags = @()
            for ( $i = 0; $i -lt $elements.Count; $i++) {
                if ( $elements[$i].extent.text -match "^-t" ) {
                    $vAst = $elements[$i+1]
                    if ( $vAst.FindAll({$args[0] -is "System.Management.Automation.Language.VariableExpressionAst"},$true) ) {
                        $warnings += "TAGS must be static strings, error in ${fullname}, line $lineno"
                    }
                    $values = $vAst.FindAll({$args[0] -is "System.Management.Automation.Language.StringConstantExpressionAst"},$true).Value
                    $values | ForEach-Object {
                        if (@('REQUIREADMINONWINDOWS', 'REQUIRESUDOONUNIX', 'SLOW') -contains $_) {
                            # These are valid tags also, but they are not the priority tags
                        }
                        elseif (@('CI', 'FEATURE', 'SCENARIO') -contains $_) {
                            $foundPriorityTags += $_
                        }
                        else {
                            $warnings += "${fullname} includes improper tag '$_', line '$lineno'"
                        }

                        $alltags[$_]++
                    }
                }
            }
            if ( $foundPriorityTags.Count -eq 0 ) {
                $warnings += "${fullname}:$lineno does not include -Tag in Describe"
            }
            elseif ( $foundPriorityTags.Count -gt 1 ) {
                $warnings += "${fullname}:$lineno includes more then one scope -Tag: $foundPriorityTags"
            }
        }
    }
    if ( $Warnings.Count -gt 0 ) {
        $alltags['Result'] = "Fail"
    }
    else {
        $alltags['Result'] = "Pass"
    }
    $alltags['Warnings'] = $warnings
    $o = [pscustomobject]$alltags
    $o.psobject.TypeNames.Add("DescribeTagsInUse")
    $o
}

function Publish-PSTestTools {
    [CmdletBinding()]
    param()

    Find-Dotnet

    $tools = @(
        @{Path="${PSScriptRoot}/test/tools/TestExe";Output="testexe"}
        @{Path="${PSScriptRoot}/test/tools/WebListener";Output="WebListener"}
    )

    $Options = Get-PSOptions -DefaultToNew

    # Publish tools so it can be run by tests
    foreach ($tool in $tools)
    {
        Push-Location $tool.Path
        try {
            dotnet publish --output bin --configuration $Options.Configuration --framework $Options.Framework --runtime $Options.Runtime
            $toolPath = Join-Path -Path $tool.Path -ChildPath "bin"

            if ( -not $env:PATH.Contains($toolPath) ) {
                $env:PATH = $toolPath+$TestModulePathSeparator+$($env:PATH)
            }
        } finally {
            Pop-Location
        }
    }
}

function Start-PSPester {
    [CmdletBinding(DefaultParameterSetName='default')]
    param(
        [string]$OutputFormat = "NUnitXml",
        [string]$OutputFile = "pester-tests.xml",
        [string[]]$ExcludeTag = 'Slow',
        [string[]]$Tag = @("CI","Feature"),
        [string[]]$Path = @("$PSScriptRoot/test/common","$PSScriptRoot/test/powershell"),
        [switch]$ThrowOnFailure,
        [string]$binDir = (Split-Path (Get-PSOptions -DefaultToNew).Output),
        [string]$powershell = (Join-Path $binDir 'pwsh'),
        [string]$Pester = ([IO.Path]::Combine($binDir, "Modules", "Pester")),
        [Parameter(ParameterSetName='Unelevate',Mandatory=$true)]
        [switch]$Unelevate,
        [switch]$Quiet,
        [switch]$Terse,
        [Parameter(ParameterSetName='PassThru',Mandatory=$true)]
        [switch]$PassThru,
        [Parameter(ParameterSetName='PassThru',HelpMessage='Run commands on Linux with sudo.')]
        [switch]$Sudo,
        [switch]$IncludeFailingTest
    )

    $getModuleResults = Get-Module -ListAvailable -Name $Pester -ErrorAction SilentlyContinue
    if (-not $getModuleResults)
    {
        Write-Warning @"
Pester module not found.
Restore the module to '$Pester' by running:
    Restore-PSPester
"@
        return;
    }

    if (-not ($getModuleResults | Where-Object { $_.Version -ge "4.2" } )) {
        Write-Warning @"
No Pester module of version 4.2 and higher.
Restore the required module version to '$Pester' by running:
    Restore-PSPester
"@
        return;
    }

    if ($IncludeFailingTest.IsPresent)
    {
        $Path += "$PSScriptRoot/tools/failingTests"
    }

    # we need to do few checks and if user didn't provide $ExcludeTag explicitly, we should alternate the default
    if ($Unelevate)
    {
        if (-not $Environment.IsWindows)
        {
            throw '-Unelevate is currently not supported on non-Windows platforms'
        }

        if (-not $Environment.IsAdmin)
        {
            throw '-Unelevate cannot be applied because the current user is not Administrator'
        }

        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireAdminOnWindows'
        }
    }
    elseif ($Environment.IsWindows -and (-not $Environment.IsAdmin))
    {
        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireAdminOnWindows'
        }
    }
    elseif (-not $Environment.IsWindows -and (-not $Sudo.IsPresent))
    {
        if (-not $PSBoundParameters.ContainsKey('ExcludeTag'))
        {
            $ExcludeTag += 'RequireSudoOnUnix'
        }
    }
    elseif (-not $Environment.IsWindows -and $Sudo.IsPresent)
    {
        if (-not $PSBoundParameters.ContainsKey('Tag'))
        {
            $Tag = 'RequireSudoOnUnix'
        }
    }

    Write-Verbose "Running pester tests at '$path' with tag '$($Tag -join ''', ''')' and ExcludeTag '$($ExcludeTag -join ''', ''')'" -Verbose
    Publish-PSTestTools | ForEach-Object {Write-Host $_}

    # All concatenated commands/arguments are suffixed with the delimiter (space)

    # Disable telemetry for all startups of pwsh in tests
    $command = "`$env:POWERSHELL_TELEMETRY_OPTOUT = 1;"
    if ($Terse)
    {
        $command += "`$ProgressPreference = 'silentlyContinue'; "
    }

    # Autoload (in subprocess) temporary modules used in our tests
    $command += '$env:PSModulePath = '+"'$TestModulePath$TestModulePathSeparator'" + '+$($env:PSModulePath);'

    # Windows needs the execution policy adjusted
    if ($Environment.IsWindows) {
        $command += "Set-ExecutionPolicy -Scope Process Unrestricted; "
    }

    $command += "Import-Module '$Pester'; "

    if ($Unelevate)
    {
        $outputBufferFilePath = [System.IO.Path]::GetTempFileName()
    }

    $command += "Invoke-Pester "

    $command += "-OutputFormat ${OutputFormat} -OutputFile ${OutputFile} "
    if ($ExcludeTag -and ($ExcludeTag -ne "")) {
        $command += "-ExcludeTag @('" + (${ExcludeTag} -join "','") + "') "
    }
    if ($Tag) {
        $command += "-Tag @('" + (${Tag} -join "','") + "') "
    }
    # sometimes we need to eliminate Pester output, especially when we're
    # doing a daily build as the log file is too large
    if ( $Quiet ) {
        $command += "-Quiet "
    }
    if ( $PassThru ) {
        $command += "-PassThru "
    }

    $command += "'" + ($Path -join "','") + "'"
    if ($Unelevate)
    {
        $command += " *> $outputBufferFilePath; '__UNELEVATED_TESTS_THE_END__' >> $outputBufferFilePath"
    }

    Write-Verbose $command

    $script:nonewline = $true
    $script:inerror = $false
    function Write-Terse([string] $line)
    {
        $trimmedline = $line.Trim()
        if ($trimmedline.StartsWith("[+]")) {
            Write-Host "+" -NoNewline -ForegroundColor Green
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("[?]")) {
            Write-Host "?" -NoNewline -ForegroundColor Cyan
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("[!]")) {
            Write-Host "!" -NoNewline -ForegroundColor Gray
            $script:nonewline = $true
            $script:inerror = $false
        }
        elseif ($trimmedline.StartsWith("Executing script ")) {
            # Skip lines where Pester reports that is executing a test script
            return
        }
        elseif ($trimmedline -match "^\d+(\.\d+)?m?s$") {
            # Skip the time elapse like '12ms', '1ms', '1.2s' and '12.53s'
            return
        }
        else {
            if ($script:nonewline) {
                Write-Host "`n" -NoNewline
            }
            if ($trimmedline.StartsWith("[-]") -or $script:inerror) {
                Write-Host $line -ForegroundColor Red
                $script:inerror = $true
            }
            elseif ($trimmedline.StartsWith("VERBOSE:")) {
                Write-Host $line -ForegroundColor Yellow
                $script:inerror = $false
            }
            elseif ($trimmedline.StartsWith("Describing") -or $trimmedline.StartsWith("Context")) {
                Write-Host $line -ForegroundColor Magenta
                $script:inerror = $false
            }
            else {
                Write-Host $line -ForegroundColor Gray
            }
            $script:nonewline = $false
        }
    }

    # To ensure proper testing, the module path must not be inherited by the spawned process
    try {
        $originalModulePath = $env:PSModulePath
        $originalTelemetry = $env:POWERSHELL_TELEMETRY_OPTOUT
        $env:POWERSHELL_TELEMETRY_OPTOUT = 1
        if ($Unelevate)
        {
            Start-UnelevatedProcess -process $powershell -arguments @('-noprofile', '-c', $Command)
            $currentLines = 0
            while ($true)
            {
                $lines = Get-Content $outputBufferFilePath | Select-Object -Skip $currentLines
                if ($Terse)
                {
                    foreach ($line in $lines)
                    {
                        Write-Terse -line $line
                    }
                }
                else
                {
                    $lines | Write-Host
                }
                if ($lines | Where-Object { $_ -eq '__UNELEVATED_TESTS_THE_END__'})
                {
                    break
                }

                $count = ($lines | measure-object).Count
                if ($count -eq 0)
                {
                    Start-Sleep -Seconds 1
                }
                else
                {
                    $currentLines += $count
                }
            }
        }
        else
        {
            if ($PassThru.IsPresent)
            {
                $passThruFile = [System.IO.Path]::GetTempFileName()
                try
                {
                    $command += "|Export-Clixml -Path '$passThruFile' -Force"

                    $passThruCommand = {& $powershell -noprofile -c $command }
                    if ($Sudo.IsPresent) {
                        $passThruCommand =  {& sudo $powershell -noprofile -c $command }
                    }

                    $writeCommand = { Write-Host $_ }
                    if ($Terse)
                    {
                        $writeCommand = { Write-Terse $_ }
                    }

                    Start-NativeExecution -sb $passThruCommand | ForEach-Object $writeCommand
                    Import-Clixml -Path $passThruFile | Where-Object {$_.TotalCount -is [Int32]}
                }
                finally
                {
                    Remove-Item $passThruFile -ErrorAction SilentlyContinue -Force
                }
            }
            else
            {
                if ($Terse)
                {
                    Start-NativeExecution -sb {& $powershell -noprofile -c $command} | ForEach-Object { Write-Terse -line $_ }
                }
                else
                {
                    Start-NativeExecution -sb {& $powershell -noprofile -c $command}
                }
            }
        }
    } finally {
        $env:PSModulePath = $originalModulePath
        $env:POWERSHELL_TELEMETRY_OPTOUT = $originalTelemetry
        if ($Unelevate)
        {
            Remove-Item $outputBufferFilePath
        }
    }

    if($ThrowOnFailure)
    {
        Test-PSPesterResults -TestResultsFile $OutputFile
    }
}

function script:Start-UnelevatedProcess
{
    param(
        [string]$process,
        [string[]]$arguments
    )
    if (-not $Environment.IsWindows)
    {
        throw "Start-UnelevatedProcess is currently not supported on non-Windows platforms"
    }

    runas.exe /trustlevel:0x20000 "$process $arguments"
}

function Show-PSPesterError
{
    [CmdletBinding(DefaultParameterSetName='xml')]
    param (
        [Parameter(ParameterSetName='xml',Mandatory)]
        [Xml.XmlElement]$testFailure,
        [Parameter(ParameterSetName='object',Mandatory)]
        [PSCustomObject]$testFailureObject
        )

    if ($PSCmdLet.ParameterSetName -eq 'xml')
    {
        $description = $testFailure.description
        $name = $testFailure.name
        $message = $testFailure.failure.message
        $stackTrace = $testFailure.failure."stack-trace"
    }
    elseif ($PSCmdLet.ParameterSetName -eq 'object')
    {
        $description = $testFailureObject.Describe + '/' + $testFailureObject.Context
        $name = $testFailureObject.Name
        $message = $testFailureObject.FailureMessage
        $stackTrace = $testFailureObject.StackTrace
    }
    else
    {
        throw 'Unknown Show-PSPester parameter set'
    }

    Write-Log -Error ("Description: " + $description)
    Write-Log -Error ("Name:        " + $name)
    Write-Log -Error "message:"
    Write-Log -Error $message
    Write-Log -Error "stack-trace:"
    Write-Log -Error $stackTrace

}

function Test-XUnitTestResults
{
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestResultsFile
    )

    if(-not (Test-Path $TestResultsFile))
    {
        throw "File not found $TestResultsFile"
    }

    try
    {
        $results = [xml] (Get-Content $TestResultsFile)
    }
    catch
    {
        throw "Cannot convert $TestResultsFile to xml : $($_.message)"
    }

    $failedTests = $results.assemblies.assembly.collection | Where-Object failed -gt 0

    if(-not $failedTests)
    {
        return $true
    }

    foreach($failure in $failedTests)
    {
        $description = $failure.test.type
        $name = $failure.test.method
        $message = $failure.test.failure.message.'#cdata-section'
        $stackTrace = $failure.test.failure.'stack-trace'.'#cdata-section'

        Write-Log -Error ("Description: " + $description)
        Write-Log -Error ("Name:        " + $name)
        Write-Log -Error "message:"
        Write-Log -Error $message
        Write-Log -Error "stack-trace:"
        Write-Log -Error $stackTrace
    }

    throw "$($failedTests.failed) tests failed"
}

#
# Read the test result file and
# Throw if a test failed
function Test-PSPesterResults
{
    [CmdletBinding(DefaultParameterSetName='file')]
    param(
        [Parameter(ParameterSetName='file')]
        [string]$TestResultsFile = "pester-tests.xml",
        [Parameter(ParameterSetName='file')]
        [string]$TestArea = 'test/powershell',
        [Parameter(ParameterSetName='PesterPassThruObject',Mandatory)]
        [pscustomobject] $ResultObject
        )

    if($PSCmdLet.ParameterSetName -eq 'file')
    {
        if(!(Test-Path $TestResultsFile))
        {
            throw "Test result file '$testResultsFile' not found for $TestArea."
        }

        $x = [xml](Get-Content -raw $testResultsFile)
        if ([int]$x.'test-results'.failures -gt 0)
        {
            Write-Log -Error "TEST FAILURES"
            # switch between methods, SelectNode is not available on dotnet core
            if ( "System.Xml.XmlDocumentXPathExtensions" -as [Type] )
            {
                $failures = [System.Xml.XmlDocumentXPathExtensions]::SelectNodes($x."test-results",'.//test-case[@result = "Failure"]')
            }
            else
            {
                $failures = $x.SelectNodes('.//test-case[@result = "Failure"]')
            }
            foreach ( $testfail in $failures )
            {
                Show-PSPesterError -testFailure $testfail
            }
            throw "$($x.'test-results'.failures) tests in $TestArea failed"
        }
    }
    elseif ($PSCmdLet.ParameterSetName -eq 'PesterPassThruObject')
    {
        if ($ResultObject.TotalCount -le 0)
        {
            throw 'NO TESTS RUN'
        }
        elseif ($ResultObject.FailedCount -gt 0)
        {
            Write-Log -Error 'TEST FAILURES'

            $ResultObject.TestResult | Where-Object {$_.Passed -eq $false} | ForEach-Object {
                Show-PSPesterError -testFailureObject $_
            }

            throw "$($ResultObject.FailedCount) tests in $TestArea failed"
        }
    }
}

function Start-PSxUnit {
    [CmdletBinding()]param(
        [string] $SequentialTestResultsFile = "SequentialXUnitResults.xml",
        [string] $ParallelTestResultsFile = "ParallelXUnitResults.xml"
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    $Content = Split-Path -Parent (Get-PSOutput)
    if (-not (Test-Path $Content)) {
        throw "PowerShell must be built before running tests!"
    }

    if (Test-Path $SequentialTestResultsFile) {
        Remove-Item $SequentialTestResultsFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $ParallelTestResultsFile) {
        Remove-Item $ParallelTestResultsFile -Force -ErrorAction SilentlyContinue
    }

    try {
        Push-Location $PSScriptRoot/test/csharp

        # Path manipulation to obtain test project output directory
        dotnet restore

        if(-not $Environment.IsWindows)
        {
            if($Environment.IsMacOS)
            {
                $nativeLib = "$Content/libpsl-native.dylib"
            }
            else
            {
                $nativeLib = "$Content/libpsl-native.so"
            }

            $requiredDependencies = @(
                $nativeLib,
                "$Content/Microsoft.Management.Infrastructure.dll",
                "$Content/System.Text.Encoding.CodePages.dll"
            )

            if((Test-Path $requiredDependencies) -notcontains $false)
            {
                $options = Get-PSOptions -DefaultToNew
                $Destination = "bin/$($options.configuration)/$($options.framework)"
                New-Item $Destination -ItemType Directory -Force > $null
                Copy-Item -Path $requiredDependencies -Destination $Destination -Force
            }
            else
            {
                throw "Dependencies $requiredDependencies not met."
            }
        }

        # Run sequential tests first, and then run the tests that can execute in parallel
        dotnet xunit -configuration $Options.configuration -xml $SequentialTestResultsFile -namespace "PSTests.Sequential" -parallel none
        dotnet xunit -configuration $Options.configuration -xml $ParallelTestResultsFile -namespace "PSTests.Parallel" -nobuild
    }
    finally {
        Pop-Location
    }
}

function Install-Dotnet {
    [CmdletBinding()]
    param(
        [string]$Channel = $dotnetCLIChannel,
        [string]$Version = $dotnetCLIRequiredVersion,
        [switch]$NoSudo
    )

    # This allows sudo install to be optional; needed when running in containers / as root
    # Note that when it is null, Invoke-Expression (but not &) must be used to interpolate properly
    $sudo = if (!$NoSudo) { "sudo" }

    $obtainUrl = "https://raw.githubusercontent.com/dotnet/cli/master/scripts/obtain"

    # Install for Linux and OS X
    if ($Environment.IsLinux -or $Environment.IsMacOS) {
        # Uninstall all previous dotnet packages
        $uninstallScript = if ($Environment.IsUbuntu) {
            "dotnet-uninstall-debian-packages.sh"
        } elseif ($Environment.IsMacOS) {
            "dotnet-uninstall-pkgs.sh"
        }

        if ($uninstallScript) {
            Start-NativeExecution {
                curl -sO $obtainUrl/uninstall/$uninstallScript
                Invoke-Expression "$sudo bash ./$uninstallScript"
            }
        } else {
            Write-Warning "This script only removes prior versions of dotnet for Ubuntu 14.04 and OS X"
        }

        # Install new dotnet 1.1.0 preview packages
        $installScript = "dotnet-install.sh"
        Start-NativeExecution {
            curl -sO $obtainUrl/$installScript
            bash ./$installScript -c $Channel -v $Version
        }
    } elseif ($Environment.IsWindows) {
        Remove-Item -ErrorAction SilentlyContinue -Recurse -Force ~\AppData\Local\Microsoft\dotnet
        $installScript = "dotnet-install.ps1"
        Invoke-WebRequest -Uri $obtainUrl/$installScript -OutFile $installScript

        if (-not $Environment.IsCoreCLR) {
            & ./$installScript -Channel $Channel -Version $Version
        } else {
            # dotnet-install.ps1 uses APIs that are not supported in .NET Core, so we run it with Windows PowerShell
            $fullPSPath = Join-Path -Path $env:windir -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
            $fullDotnetInstallPath = Join-Path -Path $pwd.Path -ChildPath $installScript
            Start-NativeExecution { & $fullPSPath -NoLogo -NoProfile -File $fullDotnetInstallPath -Channel $Channel -Version $Version }
        }
    }
}

function Get-RedHatPackageManager {
    if ($Environment.IsCentOS) {
        "yum install -y -q"
    } elseif ($Environment.IsFedora) {
        "dnf install -y -q"
    } else {
        throw "Error determining package manager for this distribution."
    }
}

function Start-PSBootstrap {
    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High")]
    param(
        [string]$Channel = $dotnetCLIChannel,
        # we currently pin dotnet-cli version, and will
        # update it when more stable version comes out.
        [string]$Version = $dotnetCLIRequiredVersion,
        [switch]$Package,
        [switch]$NoSudo,
        [switch]$BuildWindowsNative,
        [switch]$BuildLinuxArm,
        [switch]$BuildLinuxArm64,
        [switch]$Force
    )

    Write-Log "Installing libpsl-native build dependencies"

    Push-Location $PSScriptRoot/tools

    try {
        if ($Environment.IsLinux -or $Environment.IsMacOS) {
            # This allows sudo install to be optional; needed when running in containers / as root
            # Note that when it is null, Invoke-Expression (but not &) must be used to interpolate properly
            $sudo = if (!$NoSudo) { "sudo" }

            try {
                # Update googletest submodule for linux native cmake
                Push-Location $PSScriptRoot
                $Submodule = "$PSScriptRoot/src/libpsl-native/test/googletest"
                Remove-Item -Path $Submodule -Recurse -Force -ErrorAction SilentlyContinue
                git submodule --quiet update --init -- $submodule
            } finally {
                Pop-Location
            }

            if (($BuildLinuxArm -or $BuildLinuxArm64) -and -not $Environment.IsUbuntu) {
                Write-Error "Cross compiling for linux-arm/linux-arm64 are only supported on Ubuntu environment"
                return
            }

            # Install ours and .NET's dependencies
            $Deps = @()
            if ($Environment.IsUbuntu -or $Environment.IsDebian) {
                # Build tools
                $Deps += "curl", "g++", "cmake", "make"

                if ($BuildLinuxArm) {
                    $Deps += "gcc-arm-linux-gnueabihf", "g++-arm-linux-gnueabihf"
                } elseif ($BuildLinuxArm64) {
                    $Deps += "gcc-aarch64-linux-gnu", "g++-aarch64-linux-gnu"
                }

                # .NET Core required runtime libraries
                $Deps += "libunwind8"
                if ($Environment.IsUbuntu14) { $Deps += "libicu52" }
                elseif ($Environment.IsUbuntu16) { $Deps += "libicu55" }

                # Packaging tools
                if ($Package) { $Deps += "ruby-dev", "groff", "libffi-dev" }

                # Install dependencies
                # change the fontend from apt-get to noninteractive
                $originalDebianFrontEnd=$env:DEBIAN_FRONTEND
                $env:DEBIAN_FRONTEND='noninteractive'
                try {
                    Start-NativeExecution {
                        Invoke-Expression "$sudo apt-get update -qq"
                        Invoke-Expression "$sudo apt-get install -y -qq $Deps"
                    }
                }
                finally {
                    # change the apt frontend back to the original
                    $env:DEBIAN_FRONTEND=$originalDebianFrontEnd
                }
            } elseif ($Environment.IsRedHatFamily) {
                # Build tools
                $Deps += "which", "curl", "gcc-c++", "cmake", "make"

                # .NET Core required runtime libraries
                $Deps += "libicu", "libunwind"

                # Packaging tools
                if ($Package) { $Deps += "ruby-devel", "rpm-build", "groff", 'libffi-devel' }

                $PackageManager = Get-RedHatPackageManager

                $baseCommand = "$sudo $PackageManager"

                # On OpenSUSE 13.2 container, sudo does not exist, so don't use it if not needed
                if($NoSudo)
                {
                    $baseCommand = $PackageManager
                }

                # Install dependencies
                Start-NativeExecution {
                    Invoke-Expression "$baseCommand $Deps"
                }
            } elseif ($Environment.IsSUSEFamily) {
                # Build tools
                # we're using a flag which requires an up to date compiler
                $Deps += "gcc7", "cmake", "make", "gcc7-c++"

                # Packaging tools
                if ($Package) { $Deps += "ruby-devel", "rpmbuild", "groff", 'libffi-devel' }

                $PackageManager = "zypper --non-interactive install"
                $baseCommand = "$sudo $PackageManager"

                # On OpenSUSE 13.2 container, sudo does not exist, so don't use it if not needed
                if($NoSudo)
                {
                    $baseCommand = $PackageManager
                }

                # Install dependencies
                Start-NativeExecution {
                    Invoke-Expression "$baseCommand $Deps"
                }

                # After installation, create the appropriate symbolic links
                foreach ($compiler in "gcc-7","g++-7") {
                    $itemPath = "/usr/bin/${compiler}"
                    $name = $compiler -replace "-7"
                    $linkPath = "/usr/bin/${name}"
                    $link = Get-Item -Path $linkPath -ErrorAction SilentlyContinue
                    if ($link) {
                        if ($link.Target) { # Symbolic link - remove it
                            Remove-Item -Force -Path $linkPath
                        }
                    }
                    New-Item -Type SymbolicLink -Target $itemPath -Path $linkPath
                }

            } elseif ($Environment.IsMacOS) {
                precheck 'brew' "Bootstrap dependency 'brew' not found, must install Homebrew! See http://brew.sh/"

                # Build tools
                $Deps += "cmake"

                # .NET Core required runtime libraries
                $Deps += "openssl"

                # Install dependencies
                # ignore exitcode, because they may be already installed
                Start-NativeExecution { brew install $Deps } -IgnoreExitcode

                # Install patched version of curl
                Start-NativeExecution { brew install curl --with-openssl --with-gssapi } -IgnoreExitcode
            } elseif ($Environment.IsAlpine) {
                $Deps += "build-base", "gcc", "abuild", "binutils", "git", "python", "bash", "cmake"

                # Install dependencies
                Start-NativeExecution { apk update }
                Start-NativeExecution { apk add $Deps }
            }

            # Install [fpm](https://github.com/jordansissel/fpm) and [ronn](https://github.com/rtomayko/ronn)
            if ($Package) {
                try {
                    # We cannot guess if the user wants to run gem install as root on linux and windows,
                    # but macOs usually requires sudo
                    $gemsudo = ''
                    if($Environment.IsMacOS) {
                        $gemsudo = $sudo
                    }
                    Start-NativeExecution ([ScriptBlock]::Create("$gemsudo gem install fpm -v 1.9.3"))
                    Start-NativeExecution ([ScriptBlock]::Create("$gemsudo gem install ronn -v 0.7.3"))
                } catch {
                    Write-Warning "Installation of fpm and ronn gems failed! Must resolve manually."
                }
            }
        }

        # Try to locate dotnet-SDK before installing it
        <#
        Find-Dotnet

        # Install dotnet-SDK
        $dotNetExists = precheck 'dotnet' $null
        $dotNetVersion = [string]::Empty
        if($dotNetExists) {
            $dotNetVersion = (dotnet --version)
        }

        if(!$dotNetExists -or $dotNetVersion -ne $dotnetCLIRequiredVersion -or $Force.IsPresent) {
            if($Force.IsPresent) {
                Write-Log "Installing dotnet due to -Force."
            }
            elseif(!$dotNetExistis) {
                Write-Log "dotnet not present.  Installing dotnet."
            }
            else {
                Write-Log "dotnet out of date ($dotNetVersion).  Updating dotnet."
            }

            $DotnetArguments = @{ Channel=$Channel; Version=$Version; NoSudo=$NoSudo }
            Install-Dotnet @DotnetArguments
        }
        else {
            Write-Log "dotnet is already installed.  Skipping installation."
        }
        #>

        # Install Windows dependencies if `-Package` or `-BuildWindowsNative` is specified
        if ($Environment.IsWindows) {
            <#
            ## The VSCode build task requires 'pwsh.exe' to be found in Path
            if (-not (Get-Command -Name pwsh.exe -CommandType Application -ErrorAction SilentlyContinue))
            {
                Write-Log "pwsh.exe not found. Install latest PowerShell Core release and add it to Path"
                $psInstallFile = [System.IO.Path]::Combine($PSScriptRoot, "tools", "install-powershell.ps1")
                & $psInstallFile -AddToPath
            }

            ## need RCEdit to modify the binaries embedded resources
            if (-not (Test-Path "~/.rcedit/rcedit-x64.exe"))
            {
                Write-Log "Install RCEdit for modifying exe resources"
                $rceditUrl = "https://github.com/electron/rcedit/releases/download/v1.0.0/rcedit-x64.exe"
                New-Item -Path "~/.rcedit" -Type Directory -Force > $null

                ## need to specify TLS version 1.2 since GitHub API requires it
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                Invoke-WebRequest -OutFile "~/.rcedit/rcedit-x64.exe" -Uri $rceditUrl
            }
            #>

            if ($BuildWindowsNative) {
                Write-Log "Install Windows dependencies for building PSRP plugin"

                $machinePath = [Environment]::GetEnvironmentVariable('Path', 'MACHINE')
                $newMachineEnvironmentPath = $machinePath

                $cmakePresent = precheck 'cmake' $null
                $sdkPresent = Test-Win10SDK

                # Install cmake
                #$cmakePath = "${env:ProgramFiles}\CMake\bin"
                if($cmakePresent) {
                    Write-Log "Cmake is already installed."
                } else {
                    throw "Cmake not present."
                }

                if ($sdkPresent) {
                    Write-Log "Windows 10 SDK is already installed."
                }
                else {
                    throw "Windows 10 SDK not present."
                }
            }
        }
    } finally {
        Pop-Location
    }
}

function Publish-NuGetFeed
{
    param(
        [string]$OutputPath = "$PSScriptRoot/nuget-artifacts",
        [ValidatePattern("^v\d+\.\d+\.\d+(-\w+(\.\d+)?)?$")]
        [ValidateNotNullOrEmpty()]
        [string]$ReleaseTag
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    ## We update 'project.assets.json' files with new version tag value by 'GetPSCoreVersionFromGit' target.
    $TopProject = (New-PSOptions).Top
    if ($ReleaseTag) {
        $ReleaseTagToUse = $ReleaseTag -Replace '^v'
        dotnet restore $TopProject "/property:ReleaseTag=$ReleaseTagToUse"
    } else {
        dotnet restore $TopProject
    }

    try {
        Push-Location $PSScriptRoot
        @(
'Microsoft.PowerShell.Commands.Management',
'Microsoft.PowerShell.Commands.Utility',
'Microsoft.PowerShell.Commands.Diagnostics',
'Microsoft.PowerShell.ConsoleHost',
'Microsoft.PowerShell.Security',
'System.Management.Automation',
'Microsoft.PowerShell.CoreCLR.Eventing',
'Microsoft.WSMan.Management',
'Microsoft.WSMan.Runtime',
'Microsoft.PowerShell.SDK'
        ) | ForEach-Object {
            if ($ReleaseTag) {
                dotnet pack "src/$_" --output $OutputPath "/property:IncludeSymbols=true;ReleaseTag=$ReleaseTagToUse"
            } else {
                dotnet pack "src/$_" --output $OutputPath
            }
        }
    } finally {
        Pop-Location
    }
}

function Start-DevPowerShell {
    param(
        [string[]]$ArgumentList = '',
        [switch]$LoadProfile,
        [string]$binDir = (Split-Path (New-PSOptions).Output),
        [switch]$NoNewWindow,
        [string]$Command,
        [switch]$KeepPSModulePath
    )

    try {
        if ((-not $NoNewWindow) -and ($Environment.IsCoreCLR)) {
            Write-Warning "Start-DevPowerShell -NoNewWindow is currently implied in PowerShellCore edition https://github.com/PowerShell/PowerShell/issues/1543"
            $NoNewWindow = $true
        }

        if (-not $LoadProfile) {
            $ArgumentList = @('-noprofile') + $ArgumentList
        }

        if (-not $KeepPSModulePath) {
            if (-not $Command) {
                $ArgumentList = @('-NoExit') + $ArgumentList
            }
            $Command = '$env:PSModulePath = Join-Path $env:DEVPATH Modules; ' + $Command
        }

        if ($Command) {
            $ArgumentList = $ArgumentList + @("-command $Command")
        }

        $env:DEVPATH = $binDir

        # splatting for the win
        $startProcessArgs = @{
            FilePath = "$binDir\pwsh"
            ArgumentList = "$ArgumentList"
        }

        if ($NoNewWindow) {
            $startProcessArgs.NoNewWindow = $true
            $startProcessArgs.Wait = $true
        }

        Start-Process @startProcessArgs
    } finally {
        if($env:DevPath)
        {
            Remove-Item env:DEVPATH
        }

        if ($ZapDisable) {
            Remove-Item env:COMPLUS_ZapDisable
        }
    }
}

function Start-TypeGen
{
    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        $IncFileName = 'powershell.inc'
    )

    # Add .NET CLI tools to PATH
    Find-Dotnet

    # This custom target depends on 'ResolveAssemblyReferencesDesignTime', whose definition can be found in the sdk folder.
    # To find the available properties of '_ReferencesFromRAR' when switching to a new dotnet sdk, follow the steps below:
    #   1. create a dummy project using the new dotnet sdk.
    #   2. build the dummy project with this command:
    #      dotnet msbuild .\dummy.csproj /t:ResolveAssemblyReferencesDesignTime /fileLogger /noconsolelogger /v:diag
    #   3. search '_ReferencesFromRAR' in the produced 'msbuild.log' file. You will find the properties there.
    $GetDependenciesTargetPath = "$PSScriptRoot/src/Microsoft.PowerShell.SDK/obj/Microsoft.PowerShell.SDK.csproj.TypeCatalog.targets"
    $GetDependenciesTargetValue = @'
<Project>
    <Target Name="_GetDependencies"
            DependsOnTargets="ResolveAssemblyReferencesDesignTime">
        <ItemGroup>
            <_RefAssemblyPath Include="%(_ReferencesFromRAR.HintPath)%3B"  Condition=" '%(_ReferencesFromRAR.NuGetPackageId)' != 'Microsoft.Management.Infrastructure' "/>
        </ItemGroup>
        <WriteLinesToFile File="$(_DependencyFile)" Lines="@(_RefAssemblyPath)" Overwrite="true" />
    </Target>
</Project>
'@
    Set-Content -Path $GetDependenciesTargetPath -Value $GetDependenciesTargetValue -Force -Encoding Ascii

    Push-Location "$PSScriptRoot/src/Microsoft.PowerShell.SDK"
    try {
        $ps_inc_file = "$PSScriptRoot/src/TypeCatalogGen/$IncFileName"
        dotnet msbuild .\Microsoft.PowerShell.SDK.csproj /t:_GetDependencies "/property:DesignTimeBuild=true;_DependencyFile=$ps_inc_file" /nologo
    } finally {
        Pop-Location
    }

    Push-Location "$PSScriptRoot/src/TypeCatalogGen"
    try {
        dotnet run ../System.Management.Automation/CoreCLR/CorePsTypeCatalog.cs $IncFileName
    } finally {
        Pop-Location
    }
}

function Start-ResGen
{
    [CmdletBinding()]
    param()

    # Add .NET CLI tools to PATH
    Find-Dotnet

    Push-Location "$PSScriptRoot/src/ResGen"
    try {
        Start-NativeExecution { dotnet run } | Write-Verbose
    } finally {
        Pop-Location
    }
}

function Find-Dotnet() {
    $originalPath = $env:PATH
    $dotnetPath = if ($Environment.IsWindows) { "$env:LocalAppData\Microsoft\dotnet" } else { "$env:HOME/.dotnet" }

    # If there dotnet is already in the PATH, check to see if that version of dotnet can find the required SDK
    # This is "typically" the globally installed dotnet
    if (precheck dotnet) {
        # Must run from within repo to ensure global.json can specify the required SDK version
        Push-Location $PSScriptRoot
        $dotnetCLIInstalledVersion = (dotnet --version)
        Pop-Location
        if ($dotnetCLIInstalledVersion -ne $dotnetCLIRequiredVersion) {
            Write-Warning "The 'dotnet' in the current path can't find SDK version ${dotnetCLIRequiredVersion}, prepending $dotnetPath to PATH."
            # Globally installed dotnet doesn't have the required SDK version, prepend the user local dotnet location
            $env:PATH = $dotnetPath + [IO.Path]::PathSeparator + $env:PATH
        }
    }
    else {
        Write-Warning "Could not find 'dotnet', appending $dotnetPath to PATH."
        $env:PATH += [IO.Path]::PathSeparator + $dotnetPath
    }

    if (-not (precheck 'dotnet' "Still could not find 'dotnet', restoring PATH.")) {
        $env:PATH = $originalPath
    }
}

<#
    This is one-time conversion. We use it for to turn GetEventResources.txt into GetEventResources.resx

    .EXAMPLE Convert-TxtResourceToXml -Path Microsoft.PowerShell.Commands.Diagnostics\resources
#>
function Convert-TxtResourceToXml
{
    param(
        [string[]]$Path
    )

    process {
        $Path | ForEach-Object {
            Get-ChildItem $_ -Filter "*.txt" | ForEach-Object {
                $txtFile = $_.FullName
                $resxFile = Join-Path (Split-Path $txtFile) "$($_.BaseName).resx"
                $resourceHashtable = ConvertFrom-StringData (Get-Content -Raw $txtFile)
                $resxContent = $resourceHashtable.GetEnumerator() | ForEach-Object {
@'
  <data name="{0}" xml:space="preserve">
    <value>{1}</value>
  </data>
'@ -f $_.Key, $_.Value
                } | Out-String
                Set-Content -Path $resxFile -Value ($script:RESX_TEMPLATE -f $resxContent)
            }
        }
    }
}

function script:Use-MSBuild {
    # TODO: we probably should require a particular version of msbuild, if we are taking this dependency
    # msbuild v14 and msbuild v4 behaviors are different for XAML generation
    $frameworkMsBuildLocation = "${env:SystemRoot}\Microsoft.Net\Framework\v4.0.30319\msbuild"

    $msbuild = get-command msbuild -ErrorAction SilentlyContinue
    if ($msbuild) {
        # all good, nothing to do
        return
    }

    if (-not (Test-Path $frameworkMsBuildLocation)) {
        throw "msbuild not found in '$frameworkMsBuildLocation'. Install Visual Studio 2015."
    }

    Set-Alias msbuild $frameworkMsBuildLocation -Scope Script
}

function script:Write-Log
{
    param
    (
        [Parameter(Position=0, Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $message,

        [switch] $error
    )
    if ($error)
    {
        Write-Host -Foreground Red $message
    }
    else
    {
        Write-Host -Foreground Green $message
    }
    #reset colors for older package to at return to default after error message on a compilation error
    [console]::ResetColor()
}
function script:precheck([string]$command, [string]$missedMessage) {
    $c = Get-Command $command -ErrorAction SilentlyContinue
    if (-not $c) {
        if (-not [string]::IsNullOrEmpty($missedMessage))
        {
            Write-Warning $missedMessage
        }
        return $false
    } else {
        return $true
    }
}

# this function wraps native command Execution
# for more information, read https://mnaoumov.wordpress.com/2015/01/11/execution-of-external-commands-in-powershell-done-right/
function script:Start-NativeExecution
{
    param(
        [scriptblock]$sb,
        [switch]$IgnoreExitcode,
        [switch]$VerboseOutputOnError
    )
    $backupEAP = $script:ErrorActionPreference
    $script:ErrorActionPreference = "Continue"
    try {
        if($VerboseOutputOnError.IsPresent)
        {
            $output = & $sb 2>&1
        }
        else
        {
            & $sb
        }

        # note, if $sb doesn't have a native invocation, $LASTEXITCODE will
        # point to the obsolete value
        if ($LASTEXITCODE -ne 0 -and -not $IgnoreExitcode) {
            if($VerboseOutputOnError.IsPresent -and $output)
            {
                $output | Out-String | Write-Verbose -Verbose
            }

            # Get caller location for easier debugging
            $caller = Get-PSCallStack -ErrorAction SilentlyContinue
            if($caller)
            {
                $callerLocationParts = $caller[1].Location -split ":\s*line\s*"
                $callerFile = $callerLocationParts[0]
                $callerLine = $callerLocationParts[1]

                $errorMessage = "Execution of {$sb} by ${callerFile}: line $callerLine failed with exit code $LASTEXITCODE"
                throw $errorMessage
            }
            throw "Execution of {$sb} failed with exit code $LASTEXITCODE"
        }
    } finally {
        $script:ErrorActionPreference = $backupEAP
    }
}

function Start-CrossGen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory= $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PublishPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("win7-x86",
                     "win7-x64",
                     "osx-arm64",
                     "osx-x64",
                     "linux-x64",
                     "linux-arm",
                     "linux-arm64",
                     "win-arm",
                     "win-arm64")]
        [string]
        $Runtime
    )

    function Generate-CrossGenAssembly {
        param (
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $AssemblyPath,
            [Parameter(Mandatory= $true)]
            [ValidateNotNullOrEmpty()]
            [String]
            $CrossgenPath
        )

        $outputAssembly = $AssemblyPath.Replace(".dll", ".ni.dll")
        $platformAssembliesPath = Split-Path $AssemblyPath -Parent
        $crossgenFolder = Split-Path $CrossgenPath
        $niAssemblyName = Split-Path $outputAssembly -Leaf

        try {
            Push-Location $crossgenFolder

            # Generate the ngen assembly
            Write-Verbose "Generating assembly $niAssemblyName"
            Start-NativeExecution {
                & $CrossgenPath /MissingDependenciesOK /in $AssemblyPath /out $outputAssembly /Platform_Assemblies_Paths $platformAssembliesPath
            } | Write-Verbose

            <#
            # TODO: Generate the pdb for the ngen binary - currently, there is a hard dependency on diasymreader.dll, which is available at %windir%\Microsoft.NET\Framework\v4.0.30319.
            # However, we still need to figure out the prerequisites on Linux.
            Start-NativeExecution {
                & $CrossgenPath /Platform_Assemblies_Paths $platformAssembliesPath  /CreatePDB $platformAssembliesPath /lines $platformAssembliesPath $niAssemblyName
            } | Write-Verbose
            #>
        } finally {
            Pop-Location
        }
    }

    if (-not (Test-Path $PublishPath)) {
        throw "Path '$PublishPath' does not exist."
    }

    # Get the path to crossgen
    $crossGenExe = if ($Environment.IsWindows) { "crossgen.exe" } else { "crossgen" }

    # The crossgen tool is only published for these particular runtimes
    $crossGenRuntime = if ($Environment.IsWindows) {
        if ($Runtime -match "-x86") {
            "win-x86"
        } elseif ($Runtime -match "-x64") {
            "win-x64"
        } elseif (!($env:PROCESSOR_ARCHITECTURE -match "arm")) {
            throw "crossgen for 'win-arm' and 'win-arm64' must be run on that platform"
        }
    } elseif ($Runtime -eq "linux-arm") {
        throw "crossgen is not available for 'linux-arm'"
    } elseif ($Runtime -eq "linux-arm64") {
        throw "crossgen is not available for 'linux-arm64'"
    } elseif ($Environment.IsLinux) {
        "linux-x64"
    } elseif ($Runtime -eq "osx-arm64") {
        "osx-arm64"
    } elseif ($Environment.IsMacOS) {
        "osx-x64"
    }

    if (-not $crossGenRuntime) {
        throw "crossgen is not available for this platform"
    }

    $dotnetRuntimeVersion = $script:Options.Framework -replace 'netcoreapp'

    # Get the CrossGen.exe for the correct runtime with the latest version
    $crossGenPath = Get-ChildItem $script:Environment.nugetPackagesRoot $crossGenExe -Recurse | `
                        Where-Object { $_.FullName -match $crossGenRuntime } | `
                        Where-Object { $_.FullName -match $dotnetRuntimeVersion } | `
                        Sort-Object -Property FullName -Descending | `
                        Select-Object -First 1 | `
                        ForEach-Object { $_.FullName }
    if (-not $crossGenPath) {
        throw "Unable to find latest version of crossgen.exe. 'Please run Start-PSBuild -Clean' first, and then try again."
    }
    Write-Verbose "Matched CrossGen.exe: $crossGenPath" -Verbose

    # Crossgen.exe requires the following assemblies:
    # mscorlib.dll
    # System.Private.CoreLib.dll
    # clrjit.dll on Windows or libclrjit.so/dylib on Linux/OS X
    $crossGenRequiredAssemblies = @("mscorlib.dll", "System.Private.CoreLib.dll")

    $crossGenRequiredAssemblies += if ($Environment.IsWindows) {
         "clrjit.dll"
    } elseif ($Environment.IsLinux) {
        "libclrjit.so"
    } elseif ($Environment.IsMacOS) {
        "libclrjit.dylib"
    }

    # Make sure that all dependencies required by crossgen are at the directory.
    $crossGenFolder = Split-Path $crossGenPath
    foreach ($assemblyName in $crossGenRequiredAssemblies) {
        if (-not (Test-Path "$crossGenFolder\$assemblyName")) {
            Copy-Item -Path "$PublishPath\$assemblyName" -Destination $crossGenFolder -Force -ErrorAction Stop
        }
    }

    # Common assemblies used by Add-Type or assemblies with high JIT and no pdbs to crossgen
    $commonAssembliesForAddType = @(
        "Microsoft.CodeAnalysis.CSharp.dll"
        "Microsoft.CodeAnalysis.dll"
        "System.Linq.Expressions.dll"
        "Microsoft.CSharp.dll"
        "System.Runtime.Extensions.dll"
        "System.Linq.dll"
        "System.Collections.Concurrent.dll"
        "System.Collections.dll"
        "Newtonsoft.Json.dll"
        "System.IO.FileSystem.dll"
        "System.Diagnostics.Process.dll"
        "System.Threading.Tasks.Parallel.dll"
        "System.Security.AccessControl.dll"
        "System.Text.Encoding.CodePages.dll"
        "System.Private.Uri.dll"
        "System.Threading.dll"
        "System.Security.Principal.Windows.dll"
        "System.Console.dll"
        "Microsoft.Win32.Registry.dll"
        "System.IO.Pipes.dll"
        "System.Diagnostics.FileVersionInfo.dll"
        "System.Collections.Specialized.dll"
    )

    # Common PowerShell libraries to crossgen
    $psCoreAssemblyList = @(
        "Microsoft.PowerShell.Commands.Utility.dll",
        "Microsoft.PowerShell.Commands.Management.dll",
        "Microsoft.PowerShell.Security.dll",
        "Microsoft.PowerShell.CoreCLR.Eventing.dll",
        "Microsoft.PowerShell.ConsoleHost.dll",
        "Microsoft.PowerShell.PSReadLine.dll",
        "System.Management.Automation.dll"
    )

    # Add Windows specific libraries
    if ($Environment.IsWindows) {
        $psCoreAssemblyList += @(
            "Microsoft.WSMan.Management.dll",
            "Microsoft.WSMan.Runtime.dll",
            "Microsoft.PowerShell.Commands.Diagnostics.dll",
            "Microsoft.Management.Infrastructure.CimCmdlets.dll"
        )
    }

    $fullAssemblyList = $commonAssembliesForAddType + $psCoreAssemblyList

    foreach ($assemblyName in $fullAssemblyList) {
        $assemblyPath = Join-Path $PublishPath $assemblyName
        Generate-CrossGenAssembly -CrossgenPath $crossGenPath -AssemblyPath $assemblyPath
    }

    #
    # With the latest dotnet.exe, the default load context is only able to load TPAs, and TPA
    # only contains IL assembly names. In order to make the default load context able to load
    # the NI PS assemblies, we need to replace the IL PS assemblies with the corresponding NI
    # PS assemblies, but with the same IL assembly names.
    #
    Write-Verbose "PowerShell Ngen assemblies have been generated. Deploying ..." -Verbose
    foreach ($assemblyName in $fullAssemblyList) {

        # Remove the IL assembly and its symbols.
        $assemblyPath = Join-Path $PublishPath $assemblyName
        $symbolsPath = [System.IO.Path]::ChangeExtension($assemblyPath, ".pdb")

        Remove-Item $assemblyPath -Force -ErrorAction Stop

        # No symbols are available for Microsoft.CodeAnalysis.CSharp.dll, Microsoft.CodeAnalysis.dll,
        # Microsoft.CodeAnalysis.VisualBasic.dll, and Microsoft.CSharp.dll.
        if ($commonAssembliesForAddType -notcontains $assemblyName) {
            Remove-Item $symbolsPath -Force -ErrorAction Stop
        }

        # Rename the corresponding ni.dll assembly to be the same as the IL assembly
        $niAssemblyPath = [System.IO.Path]::ChangeExtension($assemblyPath, "ni.dll")
        Rename-Item $niAssemblyPath $assemblyPath -Force -ErrorAction Stop
    }
}

# Cleans the PowerShell repo - everything but the root folder
function Clear-PSRepo
{
    [CmdletBinding()]
    param()

    Get-ChildItem $PSScriptRoot\* -Directory | ForEach-Object {
        Write-Verbose "Cleaning $_ ..."
        git clean -fdX $_
    }
}

# Install PowerShell modules such as PackageManagement, PowerShellGet
function Copy-PSGalleryModules
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Destination
    )

    if (!$Destination.EndsWith("Modules")) {
        throw "Installing to an unexpected location"
    }

    Find-DotNet
    Restore-PSPackage

    $cache = dotnet nuget locals global-packages -l
    if ($cache -match "info : global-packages: (.*)") {
        $nugetCache = $matches[1]
    }
    else {
        throw "Can't find nuget global cache"
    }

    $psGalleryProj = [xml](Get-Content -Raw $PSScriptRoot\src\Modules\PSGalleryModules.csproj)

    foreach ($m in $psGalleryProj.Project.ItemGroup.PackageReference) {
        $name = $m.Include
        $version = $m.Version
        Write-Log "Name='$Name', Version='$version', Destination='$Destination'"

        # Remove the build revision from the src (nuget drops it).
        $srcVer = if ($version -match "(\d+.\d+.\d+).\d+") {
            $matches[1]
        } else {
            $version
        }

        # Remove semantic version in the destination directory
        $destVer = if ($version -match "(\d+.\d+.\d+)-.+") {
            $matches[1]
        } else {
            $version
        }

        # Nuget seems to always use lowercase in the cache
        $src = "$nugetCache/$($name.ToLower())/$srcVer"
        $dest = "$Destination/$name/$destVer"

        Remove-Item -Force -ErrorAction Ignore -Recurse "$Destination/$name"
        New-Item -Path $dest -ItemType Directory -Force -ErrorAction Stop > $null
        $dontCopy = '*.nupkg', '*.nupkg.sha512', '*.nuspec', 'System.Runtime.InteropServices.RuntimeInformation.dll'
        Copy-Item -Exclude $dontCopy -Recurse $src/* $dest
    }
}

function Merge-TestLogs
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_})]
        [string]$XUnitLogPath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_})]
        [string[]]$NUnitLogPath,

        [Parameter()]
        [ValidateScript({Test-Path $_})]
        [string[]]$AdditionalXUnitLogPath,

        [Parameter()]
        [string]$OutputLogPath
    )

    # Convert all the NUnit logs into single object
    $convertedNUnit = ConvertFrom-PesterLog -logFile $NUnitLogPath

    $xunit = [xml] (Get-Content $XUnitLogPath -ReadCount 0 -Raw)

    $strBld = [System.Text.StringBuilder]::new($xunit.assemblies.InnerXml)

    foreach($assembly in $convertedNUnit.assembly)
    {
        $strBld.Append($assembly.ToString()) | Out-Null
    }

    foreach($path in $AdditionalXUnitLogPath)
    {
        $addXunit = [xml] (Get-Content $path -ReadCount 0 -Raw)
        $strBld.Append($addXunit.assemblies.InnerXml) | Out-Null
    }

    $xunit.assemblies.InnerXml = $strBld.ToString()
    $xunit.Save($OutputLogPath)
}

function ConvertFrom-PesterLog {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0)]
        [string[]]$Logfile,
        [Parameter()][switch]$IncludeEmpty,
        [Parameter()][switch]$MultipleLog
    )
    <#
Convert our test logs to
xunit schema - top level assemblies
Pester conversion
foreach $r in "test-results"."test-suite".results."test-suite"
assembly
    name = $r.Description
    config-file = log file (this is the only way we can determine between admin/nonadmin log)
    test-framework = Pester
    environment = top-level "test-results.environment.platform
    run-date = date (doesn't exist in pester except for beginning)
    run-time = time
    time =
#>

    BEGIN {
        # CLASSES
        class assemblies {
            # attributes
            [datetime]$timestamp
            # child elements
            [System.Collections.Generic.List[testAssembly]]$assembly
            assemblies() {
                $this.timestamp = [datetime]::now
                $this.assembly = [System.Collections.Generic.List[testAssembly]]::new()
            }
            static [assemblies] op_Addition([assemblies]$ls, [assemblies]$rs) {
                $newAssembly = [assemblies]::new()
                $newAssembly.assembly.AddRange($ls.assembly)
                $newAssembly.assembly.AddRange($rs.assembly)
                return $newAssembly
            }
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.AppendLine('<assemblies timestamp="{0:MM}/{0:dd}/{0:yyyy} {0:HH}:{0:mm}:{0:ss}">' -f $this.timestamp)
                foreach ( $a in $this.assembly  ) {
                    $sb.Append("$a")
                }
                $sb.AppendLine("</assemblies>");
                return $sb.ToString()
            }
            # use Write-Output to emit these into the pipeline
            [array]GetTests() {
                return $this.Assembly.collection.test
            }
        }

        class testAssembly {
            # attributes
            [string]$name # path to pester file
            [string]${config-file}
            [string]${test-framework} # Pester
            [string]$environment
            [string]${run-date}
            [string]${run-time}
            [decimal]$time
            [int]$total
            [int]$passed
            [int]$failed
            [int]$skipped
            [int]$errors
            testAssembly ( ) {
                $this."config-file" = "no config"
                $this."test-framework" = "Pester"
                $this.environment = $script:environment
                $this."run-date" = $script:rundate
                $this."run-time" = $script:runtime
                $this.collection = [System.Collections.Generic.List[collection]]::new()
            }
            # child elements
            [error[]]$error
            [System.Collections.Generic.List[collection]]$collection
            [string]ToString() {
                $sb = [System.Text.StringBuilder]::new()
                $sb.AppendFormat('  <assembly name="{0}" ', $this.name)
                $sb.AppendFormat('environment="{0}" ', [security.securityelement]::escape($this.environment))
                $sb.AppendFormat('test-framework="{0}" ', $this."test-framework")
                $sb.AppendFormat('run-date="{0}" ', $this."run-date")
                $sb.AppendFormat('run-time="{0}" ', $this."run-time")
                $sb.AppendFormat('total="{0}" ', $this.total)
                $sb.AppendFormat('passed="{0}" ', $this.passed)
                $sb.AppendFormat('failed="{0}" ', $this.failed)
                $sb.AppendFormat('skipped="{0}" ', $this.skipped)
                $sb.AppendFormat('time="{0}" ', $this.time)
                $sb.AppendFormat('errors="{0}" ', $this.errors)
                $sb.AppendLine(">")
                if ( $this.error ) {
                    $sb.AppendLine("    <errors>")
                    foreach ( $e in $this.error ) {
                        $sb.AppendLine($e.ToString())
                    }
                    $sb.AppendLine("    </errors>")
                } else {
                    $sb.AppendLine("    <errors />")
                }
                foreach ( $col in $this.collection ) {
                    $sb.AppendLine($col.ToString())
                }
                $sb.AppendLine("  </assembly>")
                return $sb.ToString()
            }
        }

        class collection {
            # attributes
            [string]$name
            [decimal]$time
            [int]$total
            [int]$passed
            [int]$failed
            [int]$skipped
            # child element
            [System.Collections.Generic.List[test]]$test
            # constructor
            collection () {
                $this.test = [System.Collections.Generic.List[test]]::new()
            }
            [string]ToString() {
                $sb = [Text.StringBuilder]::new()
                if ( $this.test.count -eq 0 ) {
                    $sb.AppendLine("    <collection />")
                } else {
                    $sb.AppendFormat('    <collection total="{0}" passed="{1}" failed="{2}" skipped="{3}" name="{4}" time="{5}">' + "`n",
                        $this.total, $this.passed, $this.failed, $this.skipped, [security.securityelement]::escape($this.name), $this.time)
                    foreach ( $t in $this.test ) {
                        $sb.AppendLine("    " + $t.ToString());
                    }
                    $sb.Append("    </collection>")
                }
                return $sb.ToString()
            }
        }

        class errors {
            [error[]]$error
        }
        class error {
            # attributes
            [string]$type
            [string]$name
            # child elements
            [failure]$failure
            [string]ToString() {
                $sb = [system.text.stringbuilder]::new()
                $sb.AppendLine('<error type="{0}" name="{1}" >' -f $this.type, [security.securityelement]::escape($this.Name))
                $sb.AppendLine($this.failure -as [string])
                $sb.AppendLine("</error>")
                return $sb.ToString()
            }
        }

        class cdata {
            [string]$text
            cdata ( [string]$s ) { $this.text = $s }
            [string]ToString() {
                return '<![CDATA[' + [security.securityelement]::escape($this.text) + ']]>'
            }
        }

        class failure {
            [string]${exception-type}
            [cdata]$message
            [cdata]${stack-trace}
            failure ( [string]$message, [string]$stack ) {
                $this."exception-type" = "Pester"
                $this.Message = [cdata]::new($message)
                $this."stack-trace" = [cdata]::new($stack)
            }
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.AppendLine("        <failure>")
                $sb.AppendLine("          <message>" + ($this.message -as [string]) + "</message>")
                $sb.AppendLine("          <stack-trace>" + ($this."stack-trace" -as [string]) + "</stack-trace>")
                $sb.Append("        </failure>")
                return $sb.ToString()
            }
        }

        enum resultenum {
            Pass
            Fail
            Skip
        }

        class trait {
            # attributes
            [string]$name
            [string]$value
        }
        class traits {
            [trait[]]$trait
        }
        class test {
            # attributes
            [string]$name
            [string]$type
            [string]$method
            [decimal]$time
            [resultenum]$result
            # child elements
            [trait[]]$traits
            [failure]$failure
            [cdata]$reason # skip reason
            [string]ToString() {
                $sb = [text.stringbuilder]::new()
                $sb.appendformat('  <test name="{0}" type="{1}" method="{2}" time="{3}" result="{4}"',
                    [security.securityelement]::escape($this.name), [security.securityelement]::escape($this.type),
                    [security.securityelement]::escape($this.method), $this.time, $this.result)
                if ( $this.failure ) {
                    $sb.AppendLine(">")
                    $sb.AppendLine($this.failure -as [string])
                    $sb.append('      </test>')
                } else {
                    $sb.Append("/>")
                }
                return $sb.ToString()
            }
        }

        function convert-pesterlog ( [xml]$x, $logpath, [switch]$includeEmpty ) {
            <#$resultMap = @{
                Success = "Pass"
                Ignored = "Skip"
                Failure = "Fail"
            }#>

            $resultMap = @{
                Success = "Pass"
                Ignored = "Skip"
                Failure = "Fail"
                Inconclusive = "Skip"
            }

            $configfile = $logpath
            $runtime = $x."test-results".time
            $environment = $x."test-results".environment.platform + "-" + $x."test-results".environment."os-version"
            $rundate = $x."test-results".date
            $suites = $x."test-results"."test-suite".results."test-suite"
            $assemblies = [assemblies]::new()
            foreach ( $suite in $suites ) {
                $tCases = $suite.SelectNodes(".//test-case")
                # only create an assembly group if we have tests
                if ( $tCases.count -eq 0 -and ! $includeEmpty ) { continue }
                $tGroup = $tCases | Group-Object result
                $total = $tCases.Count
                $asm = [testassembly]::new()
                $asm.environment = $environment
                $asm."run-date" = $rundate
                $asm."run-time" = $runtime
                $asm.Name = $suite.name
                $asm."config-file" = $configfile
                $asm.time = $suite.time
                $asm.total = $suite.SelectNodes(".//test-case").Count
                $asm.Passed = $tGroup|? {$_.Name -eq "Success"} | % {$_.Count}
                $asm.Failed = $tGroup|? {$_.Name -eq "Failure"} | % {$_.Count}
                $asm.Skipped = $tGroup|? { $_.Name -eq "Ignored" } | % {$_.Count}
                $asm.Skipped += $tGroup|? { $_.Name -eq "Inconclusive" } | % {$_.Count}
                $c = [collection]::new()
                $c.passed = $asm.Passed
                $c.failed = $asm.failed
                $c.skipped = $asm.skipped
                $c.total = $asm.total
                $c.time = $asm.time
                $c.name = $asm.name
                foreach ( $tc in $suite.SelectNodes(".//test-case")) {
                    if ( $tc.result -match "Success|Ignored|Failure" ) {
                        $t = [test]::new()
                        $t.name = $tc.Name
                        $t.time = $tc.time
                        $t.method = $tc.description # the pester actually puts the name of the "it" as description
                        $t.type = $suite.results."test-suite".description | Select-Object -First 1
                        $t.result = $resultMap[$tc.result]
                        if ( $tc.failure ) {
                            $t.failure = [failure]::new($tc.failure.message, $tc.failure."stack-trace")
                        }
                        $null = $c.test.Add($t)
                    }
                }
                $null = $asm.collection.add($c)
                $assemblies.assembly.Add($asm)
            }
            $assemblies
        }

        # convert it to our object model
        # a simple conversion
        function convert-xunitlog {
            param ( $x, $logpath )
            $asms = [assemblies]::new()
            $asms.timestamp = $x.assemblies.timestamp
            foreach ( $assembly in $x.assemblies.assembly ) {
                $asm = [testAssembly]::new()
                $asm.environment = $assembly.environment
                $asm."test-framework" = $assembly."test-framework"
                $asm."run-date" = $assembly."run-date"
                $asm."run-time" = $assembly."run-time"
                $asm.total = $assembly.total
                $asm.passed = $assembly.passed
                $asm.failed = $assembly.failed
                $asm.skipped = $assembly.skipped
                $asm.time = $assembly.time
                $asm.name = $assembly.name
                foreach ( $coll in $assembly.collection ) {
                    $c = [collection]::new()
                    $c.name = $coll.name
                    $c.total = $coll.total
                    $c.passed = $coll.passed
                    $c.failed = $coll.failed
                    $c.skipped = $coll.skipped
                    $c.time = $coll.time
                    foreach ( $t in $coll.test ) {
                        $test = [test]::new()
                        $test.name = $t.name
                        $test.type = $t.type
                        $test.method = $t.method
                        $test.time = $t.time
                        $test.result = $t.result
                        $c.test.Add($test)
                    }
                    $null = $asm.collection.add($c)
                }
                $null = $asms.assembly.add($asm)
            }
            $asms
        }
        $Logs = @()
    }

    PROCESS {
        #### MAIN ####
        foreach ( $log in $Logfile ) {
            foreach ( $logpath in (resolve-path $log).path ) {
                write-progress "converting file $logpath"
                if ( ! $logpath) { throw "Cannot resolve $Logfile" }
                $x = [xml](get-content -raw -readcount 0 $logpath)

                if ( $x.psobject.properties['test-results'] ) {
                    $Logs += convert-pesterlog $x $logpath -includeempty:$includeempty
                } elseif ( $x.psobject.properties['assemblies'] ) {
                    $Logs += convert-xunitlog $x $logpath -includeEmpty:$includeEmpty
                } else {
                    write-error "Cannot determine log type"
                }
            }
        }
    }

    END {
        if ( $MultipleLog ) {
            $Logs
        } else {
            $combinedLog = $Logs[0]
            for ( $i = 1; $i -lt $logs.count; $i++ ) {
                $combinedLog += $Logs[$i]
            }
            $combinedLog
        }
    }
}

# Save PSOptions to be restored by Restore-PSOptions
function Save-PSOptions {
    param(
        [ValidateScript({$parent = Split-Path $_;if($parent){Test-Path $parent}else{return $true}})]
        [ValidateNotNullOrEmpty()]
        [string]
        $PSOptionsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'psoptions.json'),

        [ValidateNotNullOrEmpty()]
        [object]
        $Options = (Get-PSOptions -DefaultToNew)
    )

    $Options | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 -FilePath $PSOptionsPath
}

# Restore PSOptions
# Optionally remove the PSOptions file
function Restore-PSOptions {
    param(
        [ValidateScript({Test-Path $_})]
        [string]
        $PSOptionsPath = (Join-Path -Path $PSScriptRoot -ChildPath 'psoptions.json'),
        [switch]
        $Remove
    )

    $options = Get-Content -Path $PSOptionsPath | ConvertFrom-Json

    if($Remove)
    {
        # Remove PSOptions.
        # The file is only used to set the PSOptions.
        Remove-Item -Path $psOptionsPath
    }

    Set-PSOptions -Options $options
}

$script:RESX_TEMPLATE = @'
<?xml version="1.0" encoding="utf-8"?>
<root>
  <!--
    Microsoft ResX Schema

    Version 2.0

    The primary goals of this format is to allow a simple XML format
    that is mostly human readable. The generation and parsing of the
    various data types are done through the TypeConverter classes
    associated with the data types.

    Example:

    ... ado.net/XML headers & schema ...
    <resheader name="resmimetype">text/microsoft-resx</resheader>
    <resheader name="version">2.0</resheader>
    <resheader name="reader">System.Resources.ResXResourceReader, System.Windows.Forms, ...</resheader>
    <resheader name="writer">System.Resources.ResXResourceWriter, System.Windows.Forms, ...</resheader>
    <data name="Name1"><value>this is my long string</value><comment>this is a comment</comment></data>
    <data name="Color1" type="System.Drawing.Color, System.Drawing">Blue</data>
    <data name="Bitmap1" mimetype="application/x-microsoft.net.object.binary.base64">
        <value>[base64 mime encoded serialized .NET Framework object]</value>
    </data>
    <data name="Icon1" type="System.Drawing.Icon, System.Drawing" mimetype="application/x-microsoft.net.object.bytearray.base64">
        <value>[base64 mime encoded string representing a byte array form of the .NET Framework object]</value>
        <comment>This is a comment</comment>
    </data>

    There are any number of "resheader" rows that contain simple
    name/value pairs.

    Each data row contains a name, and value. The row also contains a
    type or mimetype. Type corresponds to a .NET class that support
    text/value conversion through the TypeConverter architecture.
    Classes that don't support this are serialized and stored with the
    mimetype set.

    The mimetype is used for serialized objects, and tells the
    ResXResourceReader how to depersist the object. This is currently not
    extensible. For a given mimetype the value must be set accordingly:

    Note - application/x-microsoft.net.object.binary.base64 is the format
    that the ResXResourceWriter will generate, however the reader can
    read any of the formats listed below.

    mimetype: application/x-microsoft.net.object.binary.base64
    value   : The object must be serialized with
            : System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
            : and then encoded with base64 encoding.

    mimetype: application/x-microsoft.net.object.soap.base64
    value   : The object must be serialized with
            : System.Runtime.Serialization.Formatters.Soap.SoapFormatter
            : and then encoded with base64 encoding.

    mimetype: application/x-microsoft.net.object.bytearray.base64
    value   : The object must be serialized into a byte array
            : using a System.ComponentModel.TypeConverter
            : and then encoded with base64 encoding.
    -->
  <xsd:schema id="root" xmlns="" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">
    <xsd:import namespace="http://www.w3.org/XML/1998/namespace" />
    <xsd:element name="root" msdata:IsDataSet="true">
      <xsd:complexType>
        <xsd:choice maxOccurs="unbounded">
          <xsd:element name="metadata">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" />
              </xsd:sequence>
              <xsd:attribute name="name" use="required" type="xsd:string" />
              <xsd:attribute name="type" type="xsd:string" />
              <xsd:attribute name="mimetype" type="xsd:string" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="assembly">
            <xsd:complexType>
              <xsd:attribute name="alias" type="xsd:string" />
              <xsd:attribute name="name" type="xsd:string" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="data">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
                <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" msdata:Ordinal="1" />
              <xsd:attribute name="type" type="xsd:string" msdata:Ordinal="3" />
              <xsd:attribute name="mimetype" type="xsd:string" msdata:Ordinal="4" />
              <xsd:attribute ref="xml:space" />
            </xsd:complexType>
          </xsd:element>
          <xsd:element name="resheader">
            <xsd:complexType>
              <xsd:sequence>
                <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
              </xsd:sequence>
              <xsd:attribute name="name" type="xsd:string" use="required" />
            </xsd:complexType>
          </xsd:element>
        </xsd:choice>
      </xsd:complexType>
    </xsd:element>
  </xsd:schema>
  <resheader name="resmimetype">
    <value>text/microsoft-resx</value>
  </resheader>
  <resheader name="version">
    <value>2.0</value>
  </resheader>
  <resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
  <resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
  </resheader>
{0}
</root>
'@
