// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::win::{message, output, wide, GetModuleHandleW, Result, SetThreadUILanguage};
#[cfg(feature = "coreclr")]
use crate::{
    common::HostEnvironment,
    hosting::{CoreClr, CONSOLE_ASSEMBLY},
    policy::INIT_FAILURE,
    win::{status_code, Wide},
};
#[cfg(not(feature = "coreclr"))]
use crate::{
    common::{console_version, Engine, RegistryKey},
    hosting::{AutomationVariant, FrameworkClr},
    policy::{parameter_matches, Version, BAD_COMMAND_LINE},
    win::ComApartment,
};
#[cfg(feature = "coreclr")]
use std::mem;
use std::{os::windows::ffi::OsStrExt, ptr};

#[must_use]
pub fn run() -> u32 {
    // Managed callers should use Environment.GetCommandLineArgs.
    let arguments: Vec<Vec<u16>> = std::env::args_os()
        .skip(1)
        .map(|arg| arg.encode_wide().chain(Some(0)).collect())
        .collect();
    unsafe {
        SetThreadUILanguage(0);
    }
    #[cfg(feature = "coreclr")]
    let result = core(&arguments);
    #[cfg(not(feature = "coreclr"))]
    let result = framework(&arguments);
    match result {
        Ok(code) => code,
        Err(code) => {
            let module = unsafe { GetModuleHandleW(ptr::null()) };
            output(&message(module, code, &[]), false);
            code
        }
    }
}

fn text(argument: &[u16]) -> String {
    String::from_utf16_lossy(
        &argument[..argument
            .iter()
            .position(|c| *c == 0)
            .unwrap_or(argument.len())],
    )
}

#[cfg(feature = "coreclr")]
fn core(arguments: &[Vec<u16>]) -> Result<u32> {
    let mut index = 0;
    let mut verbose = false;
    let mut debug = false;
    let mut help = false;
    while let Some(argument) = arguments.get(index) {
        let argument = text(argument).to_ascii_lowercase();
        let matches = |name: &str| name.starts_with(&argument);
        let skip_value;
        if matches("-verbose") {
            verbose = true;
            skip_value = false;
        } else if argument == "/?" || argument == "-?" {
            help = true;
            skip_value = false;
        } else if matches("-debug") {
            debug = true;
            skip_value = false;
        } else if argument == "-version" || matches("-psconsolefile") || matches("-runtimeversion")
        {
            skip_value = true;
        } else {
            break;
        }
        index += 1;
        if skip_value && index < arguments.len() {
            index += 1;
        }
    }
    if debug {
        output(
            &wide("Attach the debugger to powershell.exe and press Enter to continue\r\n"),
            true,
        );
        let mut line = String::new();
        std::io::stdin()
            .read_line(&mut line)
            .map_err(|_| INIT_FAILURE)?;
    }
    if help {
        output(&wide("USAGE: powershell [-Verbose] [-Debug] [-File <filePath> <args>] [-Command] <CommandLine>\r\n\r\nCoreCLR is loaded beside powershell.exe or from RemotePowerShellConfig.txt.\r\n"), true);
        return Ok(u32::MAX);
    }
    let environment = HostEnvironment::discover()?;
    let mut host = CoreClr::launch(&environment, "powershell")?;
    let start: unsafe extern "system" fn(Wide, *const Wide, i32) -> i32 = unsafe {
        mem::transmute(host.delegate(
            CONSOLE_ASSEMBLY,
            "Microsoft.PowerShell.UnmanagedPSEntry",
            "Start",
        )?)
    };
    let managed: Vec<Wide> = arguments[index..]
        .iter()
        .map(std::vec::Vec::as_ptr)
        .collect();
    let count = i32::try_from(managed.len()).map_err(|_| INIT_FAILURE)?;
    let code = status_code(unsafe { start(ptr::null(), managed.as_ptr(), count) });
    host.shutdown()?;
    if verbose {
        output(&wide("Execution succeeded\r\n"), true);
    }
    Ok(code)
}

#[cfg(not(feature = "coreclr"))]
#[derive(Default)]
struct LegacyOptions {
    version: Option<Version>,
    runtime: Option<String>,
    console: Option<Vec<u16>>,
    skip: usize,
}

#[cfg(not(feature = "coreclr"))]
fn legacy_options(arguments: &[Vec<u16>]) -> Result<LegacyOptions> {
    let mut options = LegacyOptions::default();
    let mut index = 0;
    let mut explicit_version = None;
    if arguments
        .first()
        .is_some_and(|arg| parameter_matches(&text(arg), "version"))
    {
        index += 1;
        let version = arguments.get(index).ok_or(BAD_COMMAND_LINE)?;
        explicit_version = Some(Version::parse(&text(version), true).ok_or(BAD_COMMAND_LINE)?);
        options.version = explicit_version;
        index += 1;
        options.skip = index;
    }
    let server = explicit_version.is_none()
        && arguments.get(index).is_some_and(|arg| {
            parameter_matches(&text(arg), "servermode") || parameter_matches(&text(arg), "s")
        });
    if server {
        options.version = Some(Version {
            major: 2,
            minor: None,
        });
        // Keep -ServerMode and everything following it for the managed parser.
        return Ok(options);
    }
    if arguments
        .get(index)
        .is_some_and(|arg| parameter_matches(&text(arg), "runtimeversion"))
    {
        index += 1;
        options.runtime = Some(text(arguments.get(index).ok_or(BAD_COMMAND_LINE)?));
        index += 1;
        options.skip = index;
    }
    if arguments
        .get(index)
        .is_some_and(|arg| parameter_matches(&text(arg), "psconsolefile"))
    {
        index += 1;
        let console = arguments.get(index).ok_or(BAD_COMMAND_LINE)?;
        let version = console_version(&text(console))?;
        options.console = Some(console.clone());
        options.version = explicit_version.or(Some(version));
        index += 1;
        options.skip = index;
    }
    if explicit_version.is_none() {
        // The inbox host defaults to the v3 registry family, even with -PSConsoleFile.
        options.version = Some(Version {
            major: 3,
            minor: None,
        });
    }
    Ok(options)
}

#[cfg(not(feature = "coreclr"))]
fn framework(arguments: &[Vec<u16>]) -> Result<u32> {
    // Shell registration is opportunistic in the original host too; an unavailable
    // explorer shell (Server Core, WinPE, service session) must not prevent startup.
    let _ = crate::shell::initialize();
    let options = legacy_options(arguments)?;
    if options.version.is_some_and(|v| v.major <= 2)
        && RegistryKey::open(r"SYSTEM\CurrentControlSet\Control\MiniNT").is_ok()
    {
        return Err(35);
    }
    let engine = Engine::open(options.version)?;
    engine.validate_framework_installation()?;
    let runtime = options.runtime.as_deref().unwrap_or(&engine.runtime);
    if options.runtime.is_some() {
        let module = unsafe { GetModuleHandleW(ptr::null()) };
        let runtime = wide(runtime);
        output(&message(module, 36, &[runtime.as_ptr() as usize]), false);
    }
    let _apartment = ComApartment::new(true, true)?;
    let host = FrameworkClr::launch(runtime)?;
    let instance = host.instance(
        &engine.value("ConsoleHostAssemblyName")?,
        "Microsoft.PowerShell.UnmanagedPSEntry",
    )?;
    let console = options
        .console
        .as_ref()
        .map(|value| &value[..value.len() - 1]);
    // IDispatch argument order is reversed: string[] then the console file.
    let mut parameters = [
        AutomationVariant::strings(&arguments[options.skip..])?,
        AutomationVariant::bstr(console)?,
    ];
    instance.invoke("Start", &mut parameters)?.int_result()
}

#[cfg(all(test, not(feature = "coreclr")))]
mod tests {
    use super::*;

    fn arguments(values: &[&str]) -> Vec<Vec<u16>> {
        values.iter().map(|value| wide(value)).collect()
    }

    #[test]
    fn framework_keeps_managed_arguments_and_strips_native_options() {
        let args = arguments(&[
            "-Version",
            "2.0",
            "-RuntimeVersion",
            "v2.0.50727",
            "-NoProfile",
        ]);
        let options = legacy_options(&args).unwrap();
        assert_eq!(
            options.version,
            Some(Version {
                major: 2,
                minor: Some(0)
            })
        );
        assert_eq!(options.runtime.as_deref(), Some("v2.0.50727"));
        assert_eq!(options.skip, 4);
    }

    #[test]
    fn framework_defaults_and_server_mode() {
        let options = legacy_options(&arguments(&["-NoProfile"])).unwrap();
        assert_eq!(
            options.version,
            Some(Version {
                major: 3,
                minor: None
            })
        );
        assert_eq!(options.skip, 0);
        let options = legacy_options(&arguments(&["-ServerMode"])).unwrap();
        assert_eq!(
            options.version,
            Some(Version {
                major: 2,
                minor: None
            })
        );
        assert_eq!(options.skip, 0);
    }

    #[test]
    fn framework_rejects_missing_or_invalid_native_option_values() {
        for args in [
            vec!["-Version"],
            vec!["-Version", "invalid"],
            vec!["-RuntimeVersion"],
        ] {
            assert!(matches!(
                legacy_options(&arguments(&args)),
                Err(BAD_COMMAND_LINE)
            ));
        }
    }
}
