// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#![cfg(all(windows, not(feature = "coreclr")))]

use powershell_native_host::hosting::{AutomationVariant, FrameworkClr};
use std::{env, path::PathBuf, process::Command};
use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_MULTITHREADED};

#[test]
fn framework_activates_a_com_visible_payload_and_preserves_arguments_and_exit_codes() {
    struct Apartment;
    impl Drop for Apartment {
        fn drop(&mut self) {
            unsafe {
                CoUninitialize();
            }
        }
    }

    let compiler = PathBuf::from(env::var_os("WINDIR").expect("Windows directory is required"))
        .join(r"Microsoft.NET\Framework\v4.0.30319\csc.exe");
    let executable = env::current_exe().unwrap();
    let assembly = executable
        .parent()
        .unwrap()
        .join("PowerShellNativeFrameworkFixture.dll");
    let compilation = Command::new(compiler)
        .args(["/nologo", "/target:library"])
        .arg(format!("/out:{}", assembly.display()))
        .arg(
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("tests")
                .join("FrameworkEntry.cs"),
        )
        .output()
        .expect(".NET Framework C# compiler is required for the hosting fixture");
    assert!(
        compilation.status.success(),
        "Framework fixture compilation failed: {} {}",
        String::from_utf8_lossy(&compilation.stdout),
        String::from_utf8_lossy(&compilation.stderr)
    );

    unsafe {
        CoInitializeEx(None, COINIT_MULTITHREADED).ok().unwrap();
    }
    let _apartment = Apartment;
    let host = FrameworkClr::launch("v4.0.30319").unwrap();
    let instance = host
        .instance(
            "PowerShellNativeFrameworkFixture",
            "PowerShellNative.Tests.FrameworkEntry",
        )
        .unwrap();
    let arguments: Vec<Vec<u16>> = [
        "",
        "two words",
        "quote\"value",
        "trailing\\",
        "\u{03bb}\u{1f600}",
    ]
    .iter()
    .map(|argument| argument.encode_utf16().chain([0]).collect())
    .collect();
    for exit_code in [37_i32, -37] {
        let console: Vec<u16> = exit_code.to_string().encode_utf16().collect();
        let mut parameters = [
            AutomationVariant::strings(&arguments).unwrap(),
            AutomationVariant::bstr(Some(&console)).unwrap(),
        ];
        let result = instance.invoke("Start", &mut parameters).unwrap();
        assert_eq!(
            result.int_result().unwrap(),
            u32::from_ne_bytes(exit_code.to_ne_bytes())
        );
    }
}
