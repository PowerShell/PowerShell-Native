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
# Run from rust/ so Cargo loads .cargo/config.toml, including static CRT linkage.
Set-Location rust

# CoreCLR launcher (default).
cargo build -p powershell-native-windows --release --target x86_64-pc-windows-msvc

# Legacy .NET Framework launcher.
cargo build -p powershell-native-windows --release --target x86_64-pc-windows-msvc --no-default-features
```

Both configurations produce `powershell.exe`; build/deploy them separately.
MSVC x86 (`i686-pc-windows-msvc`) is also supported. Both MSVC targets statically
link the CRT, so the launcher itself does not require the Visual C++
redistributable. CI inspects the packaged executable's imports to enforce this;
managed payloads and their native dependencies retain their own prerequisites.
ARM64 is not validated;
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
This legacy API resolves `Start` by name without an overload signature.
PowerShell payloads with overloaded `UnmanagedPSEntry.Start` methods, including
PowerShell 7, are not compatible with that preserved contract.
`RemotePowerShellConfig.txt` can provide `PSHOMEDIR=` and `CORECLRDIR=`.
UTF-8 configuration files are accepted with or without a leading BOM.
Both paths must exist before environment expansion, as in the original host.
Otherwise the executable directory is used. TPA enumeration retains the
native-DLL exclusion list and system CoreClrPowerShellExt fallback.
Native CoreCLR stdout (help, debugger prompt, and verbose messages) is
byte-oriented UTF-8 when redirected, so it can share a stream with managed
command output. Legacy resource diagnostics on stderr retain UTF-16LE.

**.NET Framework:** the selected CLR and PowerShell registry configuration must
be installed. The host retains `CorBindToRuntimeEx`, `ICorRuntimeHost`, default
AppDomain activation, Automation invocation, legacy argument processing,
console-file version selection, and Windows PE restrictions. Framework CLR
destruction does not stop the CLR.
The managed entry point must be COM-visible and expose `Start` through
`IDispatch`, matching the original C++ host. Windows PowerShell 5.1 is not
supported: its console-host assembly disables COM visibility. This port does
not add reflection-based hosting to accommodate that incompatible payload.

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
# From rust/:
cargo test -p powershell-native-windows
cargo test -p powershell-native-windows --no-default-features
cargo clippy -p powershell-native-windows --all-targets -- -D warnings -D clippy::pedantic
cargo clippy -p powershell-native-windows --all-targets --no-default-features -- -D warnings -D clippy::pedantic
```

Portable tests cover version formats/overflow, registry-family mappings,
parameter abbreviations/Unicode dashes, native TPA exclusions, and configuration
fallback. Windows-only tests cover Automation layout, null dispatch/unknown
variants, and launcher behavior. Compile-fail documentation tests enforce private
variant storage and prevent arbitrary COM interface queries through the safe API.
The Windows CI jobs build/link both launcher configurations and architectures
with SDK resources. Pester v5 checks the packaged executable's architecture,
version resources, native CoreCLR help and missing-runtime errors, successful
CoreCLR command execution, Unicode/empty/quoted/spaced arguments, positive and
negative managed exit codes, and native Framework argument rejection.
Regression coverage also checks BOM-prefixed external-payload configuration
in both setting orders and byte-oriented redirected help/debug/verbose output.
CoreCLR startup is also tested with symlinked core-library and console-host
assemblies; creating Windows symbolic links requires Developer Mode or the
symbolic-link privilege.
Framework integration tests compile a COM-visible C# fixture with the installed
.NET Framework compiler and exercise actual CLR startup, AppDomain activation,
object unwrapping, argument marshaling, and signed managed exit codes on x86/x64.
They require .NET Framework 4 and its `csc.exe`, not Windows PowerShell 5.1.
The CoreCLR jobs use checksum-verified PowerShell 6.0.5
runtime/managed payloads on x86 and x64 to exercise the original three-argument
entry point. That end-of-life payload is a compatibility test fixture, not a
deployment recommendation. Extract the matching architecture's official ZIP
before running CoreCLR tests locally:

```powershell
Install-Module Pester -RequiredVersion 5.9.0 -Scope CurrentUser -Repository PSGallery
./tests/Invoke-Tests.ps1 -ExecutablePath ./target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration coreclr -Architecture x64 -CoreClrPayloadPath C:/payloads/powershell-6.0.5-win-x64 -ResultPath ../artifacts/test-results/windows.xml
```

CI packages these launchers under `artifacts/rust/win-<arch>-<configuration>/`,
separate from the existing C++ CoreCLR binaries and WSMan plugin under
`artifacts/cpp/win-<arch>-coreclr/`. Pester NUnit XML is retained on failures.
The lightweight manual smoke script checks CoreCLR help or Framework native
argument rejection, without requiring an installed managed PowerShell payload:

```powershell
./windows/tests/launcher-smoke.ps1 -ExecutablePath ./target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration coreclr
# After building the Framework configuration:
./windows/tests/launcher-smoke.ps1 -ExecutablePath ./target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration framework
```

Explorer integration requires a desktop session and is not covered by headless CI.

Explicit registry version requests are honored rather than being cleared before
lookup, and Automation arrays carry their proper `VT_ARRAY | VT_BSTR` tag.
Diagnostics without insertion arguments use literal message templates or a
hexadecimal error fallback rather than unsafe missing-argument substitution.
