// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

fn execute(tool: &str, arguments: &[&std::ffi::OsStr], directory: &Path) {
    let status = Command::new(tool)
        .args(arguments)
        .current_dir(directory)
        .status()
        .unwrap_or_else(|e| panic!("cannot run Windows SDK tool {tool}: {e}"));
    assert!(status.success(), "{tool} failed with {status}");
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    assert!(
        env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc"),
        "Windows builds require the MSVC ABI and Windows SDK resource tools"
    );
    if !cfg!(windows) {
        println!(
            "cargo:warning=cross-check only: Windows resources require mc.exe/rc.exe on Windows"
        );
        return;
    }
    let source = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap())
        .join("../../src/powershell-native/nativemsh/pwrshexe")
        .canonicalize()
        .unwrap();
    println!("cargo:rerun-if-changed={}", source.display());
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    execute(
        "mc.exe",
        &[
            std::ffi::OsStr::new("-h"),
            out.as_os_str(),
            std::ffi::OsStr::new("-r"),
            out.as_os_str(),
            source.join("NativeMsh.mc").as_os_str(),
        ],
        &out,
    );
    let mut resource = fs::read_to_string(source.join("MshResources.rc")).unwrap();
    resource = resource.replace("#include \"version.rc\"", "");
    for (name, actual) in [
        ("powershell.exe.manifest", "PowerShell.exe.manifest"),
        ("monad.ico", "Monad.ico"),
        (
            "powershell_securitybadge.ico",
            "PowerShell_securitybadge.ico",
        ),
    ] {
        resource = resource.replace(
            &format!("\"{name}\""),
            &format!(
                "\"{}\"",
                source
                    .join(actual)
                    .display()
                    .to_string()
                    .replace('\\', "\\\\")
            ),
        );
    }
    resource = resource.replace("\"nativemsh.rc\"", "\"NativeMsh.rc\"");
    resource.push_str(
        r#"
1 VERSIONINFO
 FILEVERSION 0,1,0,0
 PRODUCTVERSION 0,1,0,0
 FILEFLAGSMASK 0x3fL
 FILEFLAGS 0
 FILEOS 0x40004L
 FILETYPE 1
 FILESUBTYPE 0
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904b0"
  BEGIN
   VALUE "FileDescription", "PowerShell native Rust host\0"
   VALUE "FileVersion", "0.1.0\0"
   VALUE "InternalName", "powershell\0"
   VALUE "OriginalFilename", "powershell.exe\0"
   VALUE "ProductName", "PowerShell\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x409, 1200
 END
END
"#,
    );
    let rc = out.join("powershell.rc");
    let res = out.join("powershell.res");
    fs::write(&rc, resource).unwrap();
    execute(
        "rc.exe",
        &[
            std::ffi::OsStr::new("/nologo"),
            std::ffi::OsStr::new("/fo"),
            res.as_os_str(),
            rc.as_os_str(),
        ],
        &out,
    );
    println!("cargo:rustc-link-arg-bin=powershell={}", res.display());
}
