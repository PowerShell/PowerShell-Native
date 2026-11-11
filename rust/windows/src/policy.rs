// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

pub const INIT_FAILURE: u32 = 0xffff_0000;
pub const BAD_COMMAND_LINE: u32 = 0xfffd_0000;
pub const CONSOLE_FAILURE: u32 = 0xfffc_0000;
pub const REGISTRY_FAILURE: u32 = 0xfffb_0000;
pub const INCOMPATIBLE_VERSION: u32 = 0xfffa_0000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Version {
    pub major: i32,
    pub minor: Option<i32>,
}

fn component(text: &str) -> Option<i32> {
    if text.is_empty() || !text.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let text = text.trim_start_matches('0');
    if text.is_empty() {
        return Some(0);
    }
    text.parse().ok()
}

impl Version {
    /// .NET callers should use System.Version.TryParse (and validate the required fields).
    #[must_use]
    pub fn parse(text: &str, allow_minor: bool) -> Option<Self> {
        let mut fields = text.split('.');
        let major = component(fields.next()?)?;
        let minor = match fields.next() {
            Some(text) => Some(component(text)?),
            None => None,
        };
        if !allow_minor && minor.is_some() {
            return None;
        }
        // NativeMsh accepts suffixes after a successfully parsed minor component.
        Some(Self { major, minor })
    }

    #[must_use]
    pub fn registry_major(self) -> i32 {
        match self.major {
            2 => 1,
            4 | 5 => 3,
            other => other,
        }
    }
}

/// Strict registry version format: major.minor[.build[.revision]].
pub fn installed_version(text: &str) -> Option<Version> {
    let fields = text.split('.').map(component).collect::<Option<Vec<_>>>()?;
    if !(2..=4).contains(&fields.len()) {
        return None;
    }
    Some(Version {
        major: fields[0],
        minor: Some(fields[1]),
    })
}

#[must_use]
pub fn parameter_matches(argument: &str, parameter: &str) -> bool {
    let mut chars = argument.chars();
    if !matches!(
        chars.next(),
        Some('-' | '\u{2013}' | '\u{2014}' | '\u{2015}')
    ) {
        return false;
    }
    let tail = chars.as_str();
    !tail.is_empty()
        && parameter
            .to_ascii_lowercase()
            .starts_with(&tail.to_ascii_lowercase())
}

#[must_use]
pub fn exclude_tpa(name: &str) -> bool {
    let name = name.to_ascii_lowercase();
    name.starts_with("mscordaccore_")
        || [
            "clretwrc.dll",
            "clrgc.dll",
            "clrgcexp.dll",
            "clrjit.dll",
            "coreclr.dll",
            "d3dcompiler_47_cor3.dll",
            "getfilesiginforedist.dll",
            "hostfxr.dll",
            "hostpolicy.dll",
            "ijwhost.dll",
            "microsoft.management.infrastructure.native.unmanaged.dll",
            "microsoft.powershell.graphicalhost.dll",
            "pwsh.dll",
            "mscordaccore.dll",
            "mscordbi.dll",
            "mscorrc.dll",
            "msquic.dll",
            "penimc_cor3.dll",
            "powershell.core.instrumentation.dll",
            "presentationnative_cor3.dll",
            "pwrshplugin.dll",
            "sni.dll",
            "system.io.compression.native.dll",
            "vcruntime140_cor3.dll",
            "wpfgfx_cor3.dll",
        ]
        .contains(&name.as_str())
}

/// Managed callers can use File.ReadLines and Directory.Exists for this legacy configuration.
pub fn host_config(text: &str, mut exists: impl FnMut(&str) -> bool) -> Option<(String, String)> {
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let mut assemblies = None;
    let mut runtime = None;
    for line in text.lines().map(str::trim) {
        let (destination, value) = if let Some(value) = line.strip_prefix("PSHOMEDIR=") {
            (&mut assemblies, value)
        } else if let Some(value) = line.strip_prefix("CORECLRDIR=") {
            (&mut runtime, value)
        } else {
            continue;
        };
        let value = value.trim();
        if !value.is_empty() && exists(value) {
            *destination = Some(value.to_owned());
        }
    }
    Some((assemblies?, runtime?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_versions_and_registry_mapping() {
        for (text, major, minor) in [
            ("2", 2, None),
            ("00000000000003.0", 3, Some(0)),
            ("5.1.999", 5, Some(1)),
            ("2147483647", i32::MAX, None),
        ] {
            assert_eq!(Version::parse(text, true), Some(Version { major, minor }));
        }
        for text in [
            "",
            "-1",
            "+1",
            " 3",
            "3.",
            "3.x",
            "2147483648",
            "1.2147483648",
        ] {
            assert!(Version::parse(text, true).is_none(), "{text}");
        }
        assert!(Version::parse("3.0", false).is_none());
        assert_eq!(Version::parse("2", true).unwrap().registry_major(), 1);
        assert_eq!(Version::parse("5", true).unwrap().registry_major(), 3);
    }

    #[test]
    fn registry_requires_full_valid_dotnet_version() {
        for text in ["3.0", "5.1.19041.1", "0.0"] {
            assert!(installed_version(text).is_some());
        }
        for text in ["3", "3.0.x", "3.0.1.2.3", "3.-1", "3.0."] {
            assert!(installed_version(text).is_none());
        }
    }

    #[test]
    fn parameter_abbreviations_and_unicode_dashes() {
        assert!(parameter_matches("\u{2014}VER", "version"));
        assert!(parameter_matches("-p", "psconsolefile"));
        for text in ["-", "/version", "-versionlong", "version"] {
            assert!(!parameter_matches(text, "version"));
        }
    }

    #[test]
    fn trusted_assemblies_exclude_native_images() {
        assert!(exclude_tpa("CORECLR.DLL"));
        assert!(exclude_tpa("mscordaccore_amd64_amd64_11.0.dll"));
        assert!(!exclude_tpa("System.Management.Automation.dll"));
        assert!(!exclude_tpa("System.Private.CoreLib.dll"));
    }

    #[test]
    fn config_requires_both_existing_paths() {
        assert!(host_config("PSHOMEDIR=C:\\PowerShell", |_| true).is_none());
        assert!(host_config("PSHOMEDIR=\nCORECLRDIR=C:\\CLR", |_| true).is_none());
        assert!(host_config("pshomedir=C:\\PowerShell\nCORECLRDIR=C:\\CLR", |_| true).is_none());
        assert!(
            host_config("PSHOMEDIR=C:\\missing\nCORECLRDIR=C:\\CLR", |p| !p
                .ends_with("missing"))
            .is_none()
        );
    }

    #[test]
    fn config_ignores_comments_and_keeps_last_valid_value() {
        let text = "#PSHOMEDIR=bad\r\nPSHOMEDIR= first \r\nCORECLRDIR= CLR\r\n\
                    PSHOMEDIR=second\r\nPSHOMEDIR=missing\r\n";
        assert_eq!(
            host_config(text, |p| p != "missing"),
            Some(("second".into(), "CLR".into()))
        );
    }

    #[test]
    fn config_accepts_a_leading_utf8_bom_in_either_setting_order() {
        for text in [
            "\u{feff}PSHOMEDIR=C:\\PowerShell\r\nCORECLRDIR=C:\\CLR\r\n",
            "\u{feff}CORECLRDIR=C:\\CLR\r\nPSHOMEDIR=C:\\PowerShell\r\n",
        ] {
            assert_eq!(
                host_config(text, |_| true),
                Some(("C:\\PowerShell".into(), "C:\\CLR".into()))
            );
        }
        assert_eq!(
            host_config("PSHOMEDIR=C:\\\u{feff}payload\nCORECLRDIR=C:\\CLR", |_| {
                true
            }),
            Some(("C:\\\u{feff}payload".into(), "C:\\CLR".into()))
        );
    }

    #[test]
    fn config_checks_unexpanded_environment_variable_path() {
        let mut observed = Vec::new();
        assert_eq!(
            host_config("PSHOMEDIR=%PSHOME%\nCORECLRDIR=%CLR%", |p| {
                observed.push(p.to_owned());
                true
            }),
            Some(("%PSHOME%".into(), "%CLR%".into()))
        );
        assert_eq!(observed, ["%PSHOME%", "%CLR%"]);
    }
}
