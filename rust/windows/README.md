# Windows launcher and hosting in Rust

This package replaces the Windows native **launcher and shared hosting code**.
It builds `powershell.exe` and the internal Rust library `powershell_native_host`.
The WSMan plugin is deliberately **not ported**: `pwrshplugin.dll` and its eleven
exports continue to use the unchanged C++ implementation and original build.
No C/C++ source is compiled as part of this Rust package.

## Builds

Use a Visual Studio Developer Command Prompt on Windows with Rust, the MSVC
linker/import libraries, and Windows SDK `mc.exe`/`rc.exe` on PATH. The SDK
include directories must be set by the developer environment.

```powershell
# CoreCLR launcher (default).
cargo build --manifest-path rust/Cargo.toml -p powershell-native-windows --release --target x86_64-pc-windows-msvc

# Legacy .NET Framework launcher.
cargo build --manifest-path rust/Cargo.toml -p powershell-native-windows --release --target x86_64-pc-windows-msvc --no-default-features
```

Both configurations produce `powershell.exe`; build/deploy them separately.
MSVC x86 (`i686-pc-windows-msvc`) is also supported. ARM64 is not validated;
GNU/MinGW targets are rejected. `build.rs` embeds the original launcher
messages, manifest, and icons from `src/powershell-native/nativemsh/pwrshexe`.
Keep those resource inputs present. The version resource identifies this
Rust package rather than claiming the original Windows product version.

Cross-`cargo check` from non-Windows hosts explicitly skips resource compilation.
A successful cross-check does not establish Windows linker/runtime parity.

## Deployment and hosting contracts

**CoreCLR:** deploy matching `CoreCLR.dll`, managed PowerShell assemblies, and
their runtime dependencies. The host retains `coreclr_initialize`,
`coreclr_create_delegate`, `coreclr_shutdown`, and the existing managed `Start`
entry point; it does not switch existing payloads to hostfxr.
`RemotePowerShellConfig.txt` can provide `PSHOMEDIR=` and `CORECLRDIR=`.
Both paths must exist before environment expansion, as in the original host.
Otherwise the executable directory is used. TPA enumeration retains the
native-DLL exclusion list and system CoreClrPowerShellExt fallback.

**.NET Framework:** the selected CLR and PowerShell registry configuration must
be installed. The host retains `CorBindToRuntimeEx`, `ICorRuntimeHost`, default
AppDomain activation, Automation invocation, legacy argument processing,
console-file version selection, and Windows PE restrictions. Framework CLR
destruction does not stop the CLR.

**Shell integration:** shortcut discovery/icons and taskbar administrator/ISE
tasks are retained. Unavailable Explorer integration is nonfatal, including
Server Core, WinPE, and service sessions.

Assuming a caller runs on .NET 11 does not remove these payload dependencies.
.NET 11 does not replace .NET Framework hosting for legacy managed payloads.

## Source mapping and migration

| Original component | Rust implementation |
| --- | --- |
| Shared launcher configuration, registry, version/XML parsing | `src/common.rs`, `src/policy.rs`, `src/win.rs` |
| `ClrHostWrapper`, COM CLR hosting/Automation | `src/hosting.rs` |
| `MainEntry`, `CssMainEntry`, argument processing | `src/launcher.rs`, `src/main.rs` |
| `ShellIntegration` | `src/shell.rs` |
| Launcher message/resource build steps | `build.rs`, referencing original resource inputs |
| `entrypoints`, `PwrshPlugin`, `PwrshPluginMediator`, worker hosting | **Unchanged original C++; excluded from this port** |

Managed migration comments reference `System.Version`,
`Microsoft.Win32.RegistryKey`, `System.Xml.XmlReader`, `Environment`, `Process`,
`NativeLibrary`, `Directory`/`File`/`Path`, `Console`, and `Win32Exception`.
Legacy native COM CLR hosting and Explorer jump-list COM contracts do not have
direct equivalent managed APIs.

## Validation

```powershell
cargo test --manifest-path rust/Cargo.toml -p powershell-native-windows
cargo test --manifest-path rust/Cargo.toml -p powershell-native-windows --no-default-features
cargo clippy --manifest-path rust/Cargo.toml -p powershell-native-windows --all-targets -- -D warnings -D clippy::pedantic
cargo clippy --manifest-path rust/Cargo.toml -p powershell-native-windows --all-targets --no-default-features -- -D warnings -D clippy::pedantic
```

Portable tests cover version formats/overflow, registry-family mappings,
parameter abbreviations/Unicode dashes, native TPA exclusions, and configuration
fallback. Windows-only tests cover Automation layout and launcher behavior.
The Windows CI jobs build/link both launcher configurations and architectures
with SDK resources. Pester v5 checks the packaged executable's architecture,
version resources, native CoreCLR help and missing-runtime errors, and installed
Windows PowerShell startup/exit-code propagation through the Framework host:

```powershell
Install-Module Pester -RequiredVersion 5.5.0 -Scope CurrentUser -Repository PSGallery
./rust/tests/Invoke-Tests.ps1 -ExecutablePath ./rust/target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration coreclr -Architecture x64 -ResultPath ./artifacts/test-results/windows.xml
```

CI packages these launchers under `artifacts/rust/win-<arch>-<configuration>/`,
separate from the existing C++ CoreCLR binaries and WSMan plugin under
`artifacts/cpp/win-<arch>-coreclr/`. Pester NUnit XML is retained on failures.
The lightweight manual smoke script is also available:

```powershell
./rust/windows/tests/launcher-smoke.ps1 -ExecutablePath ./rust/target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration coreclr
# After building the Framework configuration:
./rust/windows/tests/launcher-smoke.ps1 -ExecutablePath ./rust/target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration framework
```

CoreCLR managed startup still requires Windows runtime verification with
matching managed payloads; Explorer integration requires a desktop session.

Explicit registry version requests are honored rather than being cleared before
lookup, and Automation arrays carry their proper `VT_ARRAY | VT_BSTR` tag.
Diagnostics without insertion arguments use literal message templates or a
hexadecimal error fallback rather than unsafe missing-argument substitution.
