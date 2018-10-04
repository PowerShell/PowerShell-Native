# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

[cmdletbinding(DefaultParameterSetName = 'Build')]
param(
)

DynamicParam {
    # Add a dynamic parameter '-Name' which specifies the name of the build to run

    # Get the names of the builds.
    $buildJsonPath = (Join-Path -path $PSScriptRoot -ChildPath 'build.json')
    $build = Get-Content -Path $buildJsonPath | ConvertFrom-Json
    $names = @($build.Windows.Name)
    foreach ($name in $build.Linux.Name) {
        $names += $name
    }

    # Create the parameter attributes
    $ParameterAttr = New-Object "System.Management.Automation.ParameterAttribute"
    $ValidateSetAttr = New-Object "System.Management.Automation.ValidateSetAttribute" -ArgumentList $names
    $Attributes = New-Object "System.Collections.ObjectModel.Collection``1[System.Attribute]"
    $Attributes.Add($ParameterAttr) > $null
    $Attributes.Add($ValidateSetAttr) > $null

    # Create the parameter
    $Parameter = New-Object "System.Management.Automation.RuntimeDefinedParameter" -ArgumentList ("Name", [string], $Attributes)
    $Dict = New-Object "System.Management.Automation.RuntimeDefinedParameterDictionary"
    $Dict.Add("Name", $Parameter) > $null
    return $Dict
}

begin {
    $Name = $PSBoundParameters['Name']
}

end {

    $psReleaseBranch = 'master'
    $psReleaseFork = 'PowerShell'
    $psReleaseLocation = Join-Path -Path $PSScriptRoot -ChildPath 'PSRelease'
    if (Test-Path $psReleaseLocation) {
        Remove-Item -Path $psReleaseLocation -Recurse -Force
    }

    $gitBinFullPath = (Get-Command -Name git).Source
    if (-not $gitBinFullPath) {
        throw "Git is required to proceed. Install from 'https://git-scm.com/download/win'"
    }

    Write-Verbose "cloning -b $psReleaseBranch --quiet https://github.com/$psReleaseFork/PSRelease.git" -verbose
    & $gitBinFullPath clone -b $psReleaseBranch --quiet https://github.com/$psReleaseFork/PSRelease.git $psReleaseLocation

    Push-Location -Path $PWD.Path
    try {
        Set-Location $psReleaseLocation
        & $gitBinFullPath  submodule update --init --recursive --quiet
    }
    finally {
        Pop-Location
    }

    $unresolvedRepoRoot = Join-Path -Path $PSScriptRoot '../..'
    $resolvedRepoRoot = (Resolve-Path -Path $unresolvedRepoRoot).ProviderPath

    try {
        Write-Verbose "Starting build at $resolvedRepoRoot  ..." -Verbose
        Import-Module "$psReleaseLocation/vstsBuild" -Force
        Import-Module "$psReleaseLocation/dockerBasedBuild" -Force
        Clear-VstsTaskState

        Invoke-Build -RepoPath $resolvedRepoRoot -BuildJsonPath "tools/releaseBuild/build.json" -Name $Name
    }
    catch {
        Write-VstsError -Error $_
    }
    finally {
        $testResultPath = Get-ChildItem $env:AGENT_TEMPDIRECTORY -Recurse -Filter 'native-tests.xml'

        if ($testResultPath -and (Test-Path $testResultPath)) {
            Write-Host "##vso[results.publish type=JUnit;mergeResults=true;runTitle=Native Test Results;publishRunAttachments=true;resultFiles=$testResultPath;]"
        }
        else {
            Write-Verbose -Verbose "Test results file was not found."
        }

        Write-VstsTaskState
        exit 0
    }
}
