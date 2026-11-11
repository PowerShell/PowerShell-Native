# Rust native implementations

The projects in this directory are additive replacements for the native sources.
The existing C++ build and packaging are unchanged.

`windows` provides the Windows launcher and shared CoreCLR/.NET Framework
hosting code; see its [build and deployment notes](windows/README.md).
The **WSMan plugin remains in its original C++ implementation**, as requested.
This workspace does not build or replace `pwrshplugin.dll`.

## libpsl-native

`libpsl-native` implements all 30 declared C entry points in
`src/libpsl-native/src`. Function names, C calling conventions, one-byte native
booleans, `CommonStat` field widths/layout, and packed `private_tm` layout are
preserved. Existing C headers remain the ABI specification.

Functions with public .NET replacements have migration comments at their
implementations, including .NET 11's `File.CreateHardLink`. Partial replacements
are explicitly distinguished from equivalent behavior.

| Original C++ implementation | Rust module |
| --- | --- |
| `createhardlink`, `createsymlink`, `followsymlink`, `getcommonstat`, `getcommonlstat`, `getstat`, `getlstat`, `getinodedata`, `getlinkcount`, `getfileowner`, `getcomputername`, `isfile`, `isdirectory`, `issymlink`, `issamefilesystemitem`, `isexecutable` | `libpsl-native/src/filesystem.rs` |
| `getpwuid`, `getgrgid`, `getuserfrompid` | `libpsl-native/src/accounts.rs` |
| `createprocess`, `getcurrentprocessorid` (exports **GetCurrentProcessId**), `getcurrentthreadid`, `getppid`, `killprocess`, `waitpid` | `libpsl-native/src/process.rs` |
| `nativesyslog` | `libpsl-native/src/logging.rs` |
| `setdate` | `libpsl-native/src/time.rs` |
| `geterrorcategory` | `libpsl-native/src/lib.rs` |

Returned strings use the **host libc allocator**, not Rust-owned `CString`
allocations. They can still be freed by the existing .NET LPStr marshaller.
Failures set the host's thread-local errno for `SetLastError = true` P/Invokes.
Use UTF-8 string marshalling, as in the original Unix interface. Raw `GetStat`
and `GetLStat` expose the target's native `struct stat`; managed callers should
continue using the normalized variants instead.

The port fixes unsafe failure paths rather than reproducing memory corruption:
failed link-count queries do not read uninitialized memory; symlink buffers grow
instead of overflowing; null arguments return `EINVAL`; account lookup retries
use the `_r` function's returned error and release temporary buffers.
`SetDate` retains local-time/DST conversion but does not mutate the host's
process-wide locale. The Linux `GetPPid` unknown-result behavior is preserved.

macOS logging uses the Apple SDK's `_os_log_impl` backend and packed public-string
argument format to preserve unified logging, subsystem/category, severity, and
`%{public}s` visibility without compiling a C/C++ shim.

### Local builds

Run Cargo **from this directory** so `.cargo/config.toml` is loaded:

```sh
cd rust
cargo test -p psl-native
cargo clippy --workspace --all-targets -- -D warnings -D clippy::pedantic
cargo build --release -p psl-native
```

Cargo names the library `libpsl_native.dylib` on macOS and `libpsl_native.so`
on Linux. Install/package it as **`libpsl-native.dylib`** or
**`libpsl-native.so`** respectively to retain the existing P/Invoke name.
macOS builds need the Apple command-line developer tools.

### Linux x64 and arm64

Per the compatibility decision, **musl is host-linked, not embedded statically**.
Embedding a second libc would invalidate the unchanged allocator/errno contract.
Rust dependencies are linked into each shared library. Choose the artifact
matching the architecture **and libc of the .NET process**; a musl library is
not a drop-in replacement in a glibc process.

The cross-build driver uses Rust target standard libraries, Zig 0.15.2, and
`cargo-zigbuild` 0.24.1. Install missing prerequisites:

```sh
rustup target add \
  x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu \
  x86_64-unknown-linux-musl aarch64-unknown-linux-musl
cargo install cargo-zigbuild --version 0.24.1 --locked
python3 -m pip install ziglang==0.15.2
python3 build-linux.py
```

`cargo-zigbuild` can discover a Python-installed Zig; alternatively place the
`zig` executable on `PATH`. `python3 build-linux.py --target linux-musl-arm64`
builds just that variant. Do not override the musl `-crt-static` target setting.
Use `--output ../artifacts/rust` to package under a different output root.

| Artifact directory | Architecture | Host runtime |
| --- | --- | --- |
| `artifacts/linux-x64/libpsl-native.so` | x86-64 | glibc 2.28+ |
| `artifacts/linux-arm64/libpsl-native.so` | AArch64 | glibc 2.28+ |
| `artifacts/linux-musl-x64/libpsl-native.so` | x86-64 | musl |
| `artifacts/linux-musl-arm64/libpsl-native.so` | AArch64 | musl |

Account-name resolution follows the host libc: glibc NSS providers are not
available in musl builds. Loading musl in a glibc .NET process does not solve
that limitation and is unsupported.

### ABI smoke test

The independent C++ smoke test uses the **original headers**, loads the library
with `dlopen`, resolves every declared entry point, verifies metadata against
native `stat`, checks errno, and frees returned strings from the caller.
It is a test client, not part of the Rust library:

```sh
c++ -std=c++11 -I../src/libpsl-native/src \
  libpsl-native/tests/abi.cpp -o target/psl-abi
target/psl-abi target/release/libpsl_native.dylib
```

On Linux append `-ldl` to the compile command and pass the `.so` path.
Run on each Linux architecture/libc to verify runtime behavior, not just
cross-compilation. Do not exercise `SetDate` with real input on a shared host:
it changes the system clock when privileged.

With PowerShell installed, the managed smoke test additionally checks unchanged
LPStr return ownership, one-byte bools, and `SetLastError` marshalling:

```powershell
./libpsl-native/tests/abi.ps1 -LibraryPath ./target/release/libpsl_native.dylib
```

## Side-by-side CI and Pester v5

`.github/workflows/rust-native.yml` builds the existing C++ code alongside Rust
without changing the existing Azure Pipelines or C++ sources. Each uploaded
artifact preserves separate repository-root output directories:

| Directory | Contents |
| --- | --- |
| `artifacts/cpp/<rid>/` | Existing C++ binaries, including the unchanged Windows WSMan plugin |
| `artifacts/rust/<rid>/` | Rust Unix library or Windows launcher; no Rust WSMan plugin |
| `artifacts/test-results/` | Pester NUnit XML results, uploaded even when a test fails |

Linux jobs build x64/arm64 for glibc and musl, macOS jobs build Intel/Apple
Silicon, and Windows jobs build x86/x64 launchers in both CoreCLR and Framework
configurations. The Windows C++ baseline remains its existing CoreCLR build,
packaged as `win-<arch>-coreclr`; the Rust launcher is packaged as
`win-<arch>-<configuration>`.

Both crates inherit a workspace-wide deny-pedantic Clippy policy. CI checks all
targets, including tests and build scripts, with warnings treated as errors;
Windows checks both feature configurations and Linux checks both libc targets.
Narrow, documented lint exceptions retain deliberate C ABI bit reinterpretations
and narrowing conversions. Formatting and native Rust tests are also enforced.

CI installs Pester 5.5.0 and exercises the **packaged Rust binaries**, not only
intermediate Cargo outputs. Unix tests check all 30 exported names, managed
layouts, UTF-8/returned-string ownership, native booleans, errno, filesystem
behavior, identities, safe failure paths, and logging. Windows tests check PE
architecture/resources, native help, missing-runtime errors, and Framework
startup/managed exit-code propagation. The runner fails on failed, empty, or
skipped test runs.

Pester runs on both glibc Linux architectures, both macOS architectures, every
Windows configuration, and x64 Alpine/musl using a musl PowerShell host.
PowerShell 7.7.0 has no published standalone musl-arm64 host, so that variant
instead receives native Rust tests and the original-header C++ ABI test inside
arm64 Alpine. Both musl libraries are exercised in real musl processes; they
must not be loaded into a glibc PowerShell process. Cross-compilation alone is
not a substitute for these runtime checks.

Run Unix tests in a fresh PowerShell process matching the library's architecture
and libc:

```powershell
Install-Module Pester -RequiredVersion 5.5.0 -Scope CurrentUser -Repository PSGallery
./tests/Invoke-Tests.ps1 -LibraryPath ./target/release/libpsl_native.dylib -ResultPath ./test-results/native.xml
```

For Windows:

```powershell
./tests/Invoke-Tests.ps1 -ExecutablePath ./target/x86_64-pc-windows-msvc/release/powershell.exe -Configuration coreclr -Architecture x64 -ResultPath ./test-results/windows.xml
```

Use `-Configuration framework` for a launcher built with `--no-default-features`
and `-Architecture x86` for an `i686-pc-windows-msvc` build.
