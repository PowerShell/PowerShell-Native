# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
param(
    [Parameter(Mandatory)]
    [string] $ExecutablePath,
    [Parameter(Mandatory)]
    [ValidateSet('coreclr', 'framework')]
    [string] $Configuration,
    [Parameter(Mandatory)]
    [ValidateSet('x64', 'x86')]
    [string] $Architecture,
    [string] $CoreClrPayloadPath
)

BeforeAll {
    function Invoke-Launcher {
        param([string] $Path, [string[]] $Arguments)
        $process = [System.Diagnostics.Process]::new()
        $started = $false
        try {
            $process.StartInfo.FileName = $Path
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.CreateNoWindow = $true
            $process.StartInfo.RedirectStandardOutput = $true
            $process.StartInfo.RedirectStandardError = $true
            $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::Unicode
            $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::Unicode
            foreach ($argument in $Arguments) { $process.StartInfo.ArgumentList.Add($argument) }
            $started = $process.Start()
            if (-not $started) { throw 'Launcher did not start.' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(30000)) {
                throw 'Launcher did not finish within 30 seconds.'
            }
            @{
                ExitCode = $process.ExitCode
                Output = $stdout.GetAwaiter().GetResult()
                Error = $stderr.GetAwaiter().GetResult()
            }
        } finally {
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                $process.WaitForExit()
            }
            $process.Dispose()
        }
    }
    if ($Configuration -eq 'coreclr') {
        $coreClrHome = Join-Path $TestDrive 'coreclr'
        New-Item -ItemType Directory $coreClrHome > $null
        Copy-Item "$CoreClrPayloadPath/*" $coreClrHome -Recurse
        $coreClrExecutable = Join-Path $coreClrHome 'powershell.exe'
        Copy-Item $ExecutablePath $coreClrExecutable
        $argumentScript = Join-Path $TestDrive 'arguments.ps1'
        @'
param([string] $ResultPath, [int] $ExitCode)
[pscustomobject] @{
    Arguments = @($args)
    Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding utf8
exit $ExitCode
'@ | Set-Content -LiteralPath $argumentScript -Encoding utf8
    }
}

Describe 'Packaged Rust Windows launcher' {
    It 'has the requested PE architecture' {
        $reader = [System.IO.BinaryReader]::new([System.IO.File]::OpenRead($ExecutablePath))
        try {
            $reader.ReadUInt16() | Should -Be 0x5a4d
            $reader.BaseStream.Position = 0x3c
            $header = $reader.ReadInt32()
            $reader.BaseStream.Position = $header
            $reader.ReadUInt32() | Should -Be 0x00004550
            $expected = if ($Architecture -eq 'x64') { 0x8664 } else { 0x014c }
            $reader.ReadUInt16() | Should -Be $expected
        } finally {
            $reader.Dispose()
        }
    }

    It 'contains launcher version resources' {
        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath)
        $version.FileVersion | Should -Be '0.1.0'
        $version.OriginalFilename | Should -Be 'powershell.exe'
        $version.FileDescription | Should -Be 'PowerShell native Rust host'
    }

    It 'does not package a Rust WSMan plugin' {
        Join-Path (Split-Path $ExecutablePath) 'pwrshplugin.dll' | Should -Not -Exist
    }

    if ($Configuration -eq 'coreclr') {
        It 'prints native help for <Argument> without requiring CoreCLR' -ForEach @(
            @{ Argument = '-?' }
            @{ Argument = '/?' }
        ) {
            $result = Invoke-Launcher -Path $ExecutablePath -Arguments $Argument
            $result.ExitCode | Should -Be -1 -Because "$($result.Output) $($result.Error)"
            $result.Output | Should -Match 'USAGE: powershell'
        }

        It 'reports a missing runtime instead of succeeding' {
            $isolated = Join-Path $TestDrive 'powershell.exe'
            Copy-Item $ExecutablePath $isolated
            $result = Invoke-Launcher -Path $isolated -Arguments '-NoProfile'
            $result.ExitCode | Should -Not -Be 0
            $result.Error | Should -Match 'PowerShell native host error'
        }

        It 'runs managed CoreCLR PowerShell, preserves arguments, and propagates exit <ExitCode>' -ForEach @(
            @{ ExitCode = 37 }
            @{ ExitCode = -37 }
        ) {
            $resultFile = Join-Path $TestDrive "arguments-$ExitCode.json"
            $expected = @('', 'two words', 'quote"value', 'trailing\', "$([char]0x03bb)$([char]::ConvertFromUtf32(0x1f600))")
            $result = Invoke-Launcher -Path $coreClrExecutable -Arguments (@(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argumentScript, $resultFile, "$ExitCode"
            ) + $expected)
            $result.ExitCode | Should -Be $ExitCode -Because "$($result.Output) $($result.Error)"
            $resultFile | Should -Exist
            $actual = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
            $actual.Architecture | Should -Be $Architecture
            $actual.Arguments.Count | Should -Be $expected.Count
            for ($index = 0; $index -lt $expected.Count; $index++) {
                $actual.Arguments[$index] | Should -BeExactly $expected[$index]
            }
        }
    } else {
        It 'starts installed Windows PowerShell and propagates its managed exit code' {
            $result = Invoke-Launcher -Path $ExecutablePath -Arguments @(
                '-NoLogo', '-NoProfile', '-NonInteractive', '-Command', 'exit 37'
            )
            $result.ExitCode | Should -Be 37 -Because "$($result.Output) $($result.Error)"
        }
    }
}
