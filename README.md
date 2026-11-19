# PowerShell-Native

PowerShell-Native contains the native libraries used by PowerShell for Unix
platform integration, Windows event logging, and Windows remoting. The release
pipeline builds platform-specific binaries and packages them together as the
`Microsoft.PowerShell.Native` NuGet package.

## Projects

### libpsl-native

[libpsl-native](src/libpsl-native) is the Unix platform support library called
from PowerShell's managed code through P/Invoke. It wraps native operating
system functionality, including file metadata and ownership, symbolic and hard
links, process operations, user and group lookup, and syslog.

- **Platforms:** Linux (glibc and musl) and macOS.
- **Outputs:** `libpsl-native.so` on Linux and `libpsl-native.dylib` on macOS.
- **Build and tests:** CMake and Make, with Google Test tests run through CTest.
- **Release variants:** Linux x64, musl x64, ARM, ARM64, and a universal macOS
  library containing both x86_64 and arm64 code.

### PowerShell.Core.Instrumentation

[PowerShell.Core.Instrumentation](src/PowerShell.Core.Instrumentation) provides
PowerShell's Windows Event Tracing for Windows (ETW) event resources. Its event
manifest defines the provider, events, channels, and messages used for logging.
The Windows SDK message compiler (`mc.exe`) generates resources from the
manifest, and CMake builds a resource-only DLL with no executable entry point.

- **Platform:** Windows.
- **Output:** `PowerShell.Core.Instrumentation.dll`.
- **Release variants:** x64, x86, and ARM64, built alongside the remoting plugin.
- **Manifest registration:** [RegisterManifest.ps1](src/PowerShell.Core.Instrumentation/RegisterManifest.ps1)
  registers or unregisters the manifest from an elevated Windows process.
  Registration requires the manifest and DLL together; unregister the manifest
  before replacing a registered DLL.

### pwrshplugin

[pwrshplugin](src/powershell-native/nativemsh/pwrshplugin) is the Windows Remote
Management (WinRM) plugin for hosting PowerShell remote sessions. It supplies
the native WinRM entry points and runtime-hosting integration that connect
WinRM to PowerShell's managed remoting implementation. It links against the
shared `pwrshcommon` native code.

- **Platform:** Windows; this is the WinRM remoting component, not SSH remoting.
- **Outputs:** `pwrshplugin.dll` and its `pwrshplugin.pdb` debugging symbols.
- **Build:** CMake, Visual C++/MSBuild, and Windows SDK resource tools, using
  `BUILD_ONECORE=ON` in the release build.
- **Release variants:** x64, x86, and ARM64 (cross-compiled with `x64_arm64`).

## Release pipeline

Official pipeline: [Pipelines - Runs for PowerShell-Native-Official](https://msazure.visualstudio.com/One/_build?definitionId=431663).

[.pipelines/release.yml](.pipelines/release.yml) is the Azure DevOps/OneBranch
release entry point. It has `trigger: none`, so it does not automatically run
on repository pushes; queue it through the configured Azure DevOps pipeline.
It relies on the governed templates in
`OneBranch.Pipelines/GovernedTemplates`, as well as OneBranch pools, signing
services, and publishing credentials. It is not a standalone GitHub Actions
workflow or a script that can run unchanged on a developer machine.

### Parameters

| Parameter | Default | Purpose |
| --- | --- | --- |
| `OfficialBuild` | `false` | Selects the official rather than nonofficial OneBranch cross-platform template, sets the release environment to `Production` rather than `Test`, and enables the final NuGet push. The official template is restricted to Production-classified pipelines. |
| `disableNetworkIsolation` | `false` | Passes the network-isolation override to the governed template's feature flags. |

### Build configurations: Docker versus host

There are eight packaged platform configurations. Dockerfile image builds and
OneBranch-managed job containers are distinct: a regular `pool.type: linux`
or `windows` job does **not** imply a bare host build. These jobs use the
configured `LinuxContainerImage` or `WindowsContainerImage`. Only the macOS
configuration explicitly selects a hosted VM without a container.

| Stage / job | Target configuration / NuGet RID | Execution environment | Build output |
| --- | --- | --- | --- |
| `WinBuildAndSign` / `Build_Sign_x64` | Windows x64 / `win-x64` | OneBranch Windows container, Visual Studio 2022 | Instrumentation DLL, plugin DLL and PDB |
| `WinBuildAndSign` / `Build_Sign_x86` | Windows x86 / `win-x86` | OneBranch Windows container, Visual Studio 2022 | Instrumentation DLL, plugin DLL and PDB |
| `WinBuildAndSign` / `Build_Sign_x64_arm64` | Windows ARM64 / `win-arm64` | OneBranch Windows container; x64-to-ARM64 cross-compilation | Instrumentation DLL, plugin DLL and PDB |
| `LinuxMuslBuild` / `Linux_musl_x64` | Alpine Linux x64 / `linux-musl-x64` | Explicit Docker build using [docker/alpine/Dockerfile](docker/alpine/Dockerfile) | `libpsl-native.so` linked against musl |
| `LinuxRockyBuild` / `Linux_rocky_x64` | Rocky Linux x64 / `linux-x64` | Explicit Docker build using [docker/rocky/Dockerfile](docker/rocky/Dockerfile) | `libpsl-native.so` linked against glibc |
| `LinuxBuild` / `Build_Linux_arm64` | Linux ARM64 / `linux-arm64` | OneBranch Azure Linux container on an ARM64 host, using native GCC | `libpsl-native.so` |
| `LinuxBuildARM` / `Build_Linux_arm` | Linux ARM / `linux-arm` | OneBranch Ubuntu 22.04 container; cross-compiles with `arm-linux-gnueabihf` | `libpsl-native.so` |
| `LinuxBuild` / `Build_osx` | macOS universal x86_64 + arm64 / `osx` | Host machine: Azure Pipelines `macOS-latest` VM | Universal `libpsl-native.dylib` |

The Windows builds explicitly use `Release`. The Unix CMake project also sets
`CMAKE_BUILD_TYPE` to `Release`, even though the generic Linux helper passes
`-DCMAKE_BUILD_TYPE=Debug`. The macOS toolchain sets both output architectures;
the pipeline does not create separate macOS x64 and ARM64 packages.

### Docker and container images

The following inventory covers the release entry point, its job templates,
and both Dockerfiles:

| Image | Use |
| --- | --- |
| `mcr.microsoft.com/onebranch/azurelinux/build:3.0` | Default Linux job container; used by the Linux ARM64 build and by both Docker builds' preparation and extraction jobs. |
| `onebranch.azurecr.io/windows/ltsc2022/vse2022:latest` | Windows job container for native compilation/signing and NuGet packaging. |
| `onebranch.azurecr.io/linux/ubuntu-2204:latest` | Linux ARM cross-compilation job container. |
| `mcr.microsoft.com/dotnet/sdk:10.0-alpine` | Alpine Dockerfile build-stage base image; also configured as the musl stage image and the Docker template's default Linux image parameter. |
| `onebranch.azurecr.io/linux/rockylinux:latest` | Rocky Dockerfile build-stage base image. The pipeline and Docker template parameter also refer to it without a tag (`onebranch.azurecr.io/linux/rockylinux`), which implies `latest`. |
| `scratch` | Empty final export stage in both Dockerfiles; contains only `libpsl-native.so`. It is not a pulled build-tool image. |

The pipeline also creates the intermediate images `psnative-alpine` and
`psnative-rocky`, tagged with `$(Build.BuildId)`. It saves them as
`docker-images/psnative-alpine.tar` and `docker-images/psnative-rocky.tar`
pipeline artifacts. These are binary transport images, not PowerShell runtime
images. Images under `onebranch.azurecr.io` require access to that registry.

### Build, sign, package, and publish

1. **Build Windows binaries.**
   [build-sign-windows.yml](.pipelines/templates/build-sign-windows.yml) calls
   `Start-PSBootstrap -BuildWindowsNative` and
   `Start-BuildNativeWindowsBinaries -Configuration Release` for each Windows
   architecture. It stages DLLs and PDBs, runs CodeQL around compilation, and
   requests DLL signing with the `external_distribution` profile.
2. **Build Alpine and Rocky Linux binaries in Docker.**
   [build-docker.yml](.pipelines/templates/build-docker.yml) creates three jobs
   per stage: `PrepareDockerBuild` stages the source context; the image-build
   job runs the corresponding multi-stage Dockerfile and saves an image tar;
   `ExtractLibPSL` downloads that tar, extracts the exported library, and
   stages `libpsl-native.so`.
3. **Build Linux ARM/ARM64 and macOS binaries.**
   [build-linux.yml](.pipelines/templates/build-linux.yml) bootstraps
   dependencies and calls `Start-BuildNativeUnixBinaries` with the appropriate
   ARM switch, or without a switch on macOS. Unix outputs are staged from
   `src/powershell-unix`; macOS explicitly uploads the `drop_osx` artifact.
4. **Assemble and sign NuGet.**
   `Build_Nuget` depends on all five platform build stages.
   [build-nuget.yml](.pipelines/templates/build-nuget.yml) downloads the eight
   configurations, archives them, and calls the packaging helpers in
   [build.psm1](build.psm1). Rocky Linux supplies the generic `linux-x64`
   library; Alpine supplies `linux-musl-x64`. Native files are placed under
   `runtimes/<RID>/native` in `Microsoft.PowerShell.Native`. Windows PDBs are
   excluded from those runtime folders and published separately to the
   Azure DevOps symbol server. The job packs and signs the `.nupkg`.
5. **Publish official releases.**
   `Release_NuGet` downloads the package artifact. Its NuGet push task runs
   only when `OfficialBuild` is `true` and previous work succeeded, using the
   `PowerShellNuGetOrgPush` service connection. Nonofficial runs do not push
   to NuGet.

[setVersion.yml](.pipelines/templates/setVersion.yml) derives the package
version from a release branch such as `release/v1.2.3` when `PACKAGE_VERSION`
is unset or `fromBranch`. Otherwise, including non-release branches, the
current template uses `99.99.99`; an arbitrary `PACKAGE_VERSION` value is not
used as a literal version override.

The governed pipeline also configures native-code SDL checks, including
credential scanning, BinSkim, CodeQL, and SBOM generation. Some checks are
overridden per configuration in the job templates.

## Building locally

The shared build commands live in [build.psm1](build.psm1). Run them from the
repository root in PowerShell (`pwsh`). Initialize the Google Test submodule
when cloning:

```powershell
git clone --recurse-submodules https://github.com/PowerShell/PowerShell-Native.git
Set-Location .\PowerShell-Native
Import-Module .\build.psm1 -Force
```

### Linux and macOS

Install PowerShell first. Linux builds require CMake, Make, and GCC/G++;
macOS builds require the Apple developer toolchain and Homebrew for bootstrap
dependencies. The bootstrap helper installs platform dependencies and
initializes Google Test:

```powershell
Start-PSBootstrap
Start-BuildNativeUnixBinaries
```

Use `-NoSudo` with bootstrap when running as root in a container. For Linux
ARM, pass `-BuildLinuxArm` to both commands on a supported Ubuntu build
environment. For ARM64, pass `-BuildLinuxArm64` to both commands and use an
ARM64 environment, matching the release pipeline's native compiler setup.

The helper builds the Unix library into `src/powershell-unix` and runs
`ctest --verbose` for the non-ARM build paths. ARM build paths do not run
CTest. To rerun configured tests:

```powershell
Push-Location .\src\libpsl-native
ctest --verbose
Pop-Location
```

Google Test writes its XML report to
`src/libpsl-native/test/native-tests.xml`.

### Windows

Install Visual Studio 2022 with the C++ build tools, ATL/MFC components, the
Windows 10 SDK (including `mc.exe`), and CMake. Install ARM64 tools as well
when targeting ARM64. Then run:

```powershell
Start-PSBootstrap -BuildWindowsNative
Start-BuildNativeWindowsBinaries -Configuration Release -Arch x64
```

Use `-Arch x86` or `-Arch x64_arm64` for the other release targets. The helper
stages the instrumentation DLL, plugin DLL, and plugin PDB in
`src/powershell-win-core`. Local compilation does not perform OneBranch
signing or publishing.

> **Build cleanup:** Work in a disposable clone or save local work first.
> The Unix helper removes ignored build files beneath `src/libpsl-native`,
> bootstrap refreshes the Google Test checkout, and the Windows helper's
> optional `-Clean` switch runs `git clean -fdx` across the repository.

## Contributing, security, and license

- Read the [contribution guidance](.github/CONTRIBUTING.md) and
  [Code of Conduct](CODE_OF_CONDUCT.md) before participating.
- Report security issues according to the [Security Policy](.github/SECURITY.md).
- This repository is licensed under the [MIT License](LICENSE.txt).
