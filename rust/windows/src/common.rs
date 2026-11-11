// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{
    policy::{
        exclude_tpa, host_config, installed_version, Version, CONSOLE_FAILURE,
        INCOMPATIBLE_VERSION, INIT_FAILURE, REGISTRY_FAILURE,
    },
    win::{
        expand, module_path, status_code, wide, ComApartment, Ptr, RegCloseKey, RegEnumKeyExW,
        RegOpenKeyExW, RegQueryValueExW, Result,
    },
};
use std::{
    path::{Path, PathBuf},
    ptr,
};
use windows::{
    core::{BSTR, VARIANT},
    Win32::{
        Data::Xml::MsXml::{DOMDocument60, IXMLDOMDocument},
        System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER},
    },
};

const ROOT: &str = r"SOFTWARE\Microsoft\PowerShell";
const HKLM: Ptr = -2_147_483_646isize as Ptr;

pub struct RegistryKey(Ptr);
impl RegistryKey {
    /// Managed callers should use Microsoft.Win32.RegistryKey.OpenSubKey/GetValue.
    ///
    /// # Errors
    /// Returns the native registry error if the key cannot be opened.
    pub fn open(path: &str) -> Result<Self> {
        let mut handle = ptr::null_mut();
        let error =
            unsafe { RegOpenKeyExW(HKLM, wide(path).as_ptr(), 0, 0x20019, &raw mut handle) };
        if error == 0 {
            Ok(Self(handle))
        } else {
            Err(status_code(error))
        }
    }

    /// # Errors
    /// Returns a registry error for missing, invalid, or unreadable string values.
    pub fn string(&self, name: &str) -> Result<String> {
        self.read_string(name, false)
    }

    /// # Errors
    /// Returns a registry error for missing, invalid, or concurrently changing values.
    pub fn read_string(&self, name: &str, allow_expand: bool) -> Result<String> {
        let name = wide(name);
        for _ in 0..4 {
            let mut kind = 0;
            let mut bytes = 0;
            let error = unsafe {
                RegQueryValueExW(
                    self.0,
                    name.as_ptr(),
                    ptr::null_mut(),
                    &raw mut kind,
                    ptr::null_mut(),
                    &raw mut bytes,
                )
            };
            if error != 0 {
                return Err(status_code(error));
            }
            if kind != 1 && !(allow_expand && kind == 2) {
                return Err(13);
            }
            if bytes == 0 || bytes % 2 != 0 {
                return Err(13);
            }
            let mut buffer = vec![0u16; bytes as usize / 2 + 1];
            let error = unsafe {
                RegQueryValueExW(
                    self.0,
                    name.as_ptr(),
                    ptr::null_mut(),
                    &raw mut kind,
                    buffer.as_mut_ptr().cast(),
                    &raw mut bytes,
                )
            };
            if error == 234 {
                continue;
            }
            if error != 0 {
                return Err(status_code(error));
            }
            if kind != 1 && !(allow_expand && kind == 2) {
                return Err(13);
            }
            let length = buffer.iter().position(|c| *c == 0).ok_or(13u32)?;
            if length == 0 {
                return Err(13);
            }
            return Ok(String::from_utf16_lossy(&buffer[..length]));
        }
        Err(234)
    }

    /// # Errors
    /// Returns the native registry error if enumeration fails.
    pub fn names(&self) -> Result<Vec<String>> {
        let mut result = Vec::new();
        let mut index = 0;
        loop {
            let mut buffer = [0; 256];
            let mut length = 256;
            let error = unsafe {
                RegEnumKeyExW(
                    self.0,
                    index,
                    buffer.as_mut_ptr(),
                    &raw mut length,
                    ptr::null_mut(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                )
            };
            if error == 259 {
                return Ok(result);
            }
            if error != 0 {
                return Err(status_code(error));
            }
            result.push(String::from_utf16_lossy(&buffer[..length as usize]));
            index += 1;
        }
    }
}
impl Drop for RegistryKey {
    fn drop(&mut self) {
        unsafe {
            RegCloseKey(self.0);
        }
    }
}

pub struct Engine {
    pub version: Version,
    pub version_text: String,
    pub runtime: String,
    pub key: RegistryKey,
}
impl Engine {
    /// # Errors
    /// Returns a host error for missing, incompatible, or malformed engine registration.
    pub fn open(requested: Option<Version>) -> Result<Self> {
        let selected = if let Some(version) = requested {
            version
        } else {
            let key = RegistryKey::open(ROOT).map_err(|_| REGISTRY_FAILURE)?;
            key.names()
                .map_err(|_| REGISTRY_FAILURE)?
                .iter()
                .filter_map(|name| Version::parse(name, false))
                .filter(|version| version.major > 0)
                .max_by_key(|version| version.major)
                .ok_or(REGISTRY_FAILURE)?
        };
        let path = format!(r"{ROOT}\{}", selected.registry_major());
        RegistryKey::open(&path).map_err(|e| {
            if e == 2 {
                INCOMPATIBLE_VERSION
            } else {
                REGISTRY_FAILURE
            }
        })?;
        let key = RegistryKey::open(&format!(r"{path}\PowerShellEngine"))
            .map_err(|_| REGISTRY_FAILURE)?;
        let version_text = key
            .string("PowerShellVersion")
            .map_err(|_| REGISTRY_FAILURE)?;
        let version = installed_version(&version_text).ok_or(REGISTRY_FAILURE)?;
        if selected
            .minor
            .zip(version.minor)
            .is_some_and(|(wanted, installed)| wanted > installed)
        {
            return Err(INCOMPATIBLE_VERSION);
        }
        let runtime = key.string("RuntimeVersion").map_err(|_| REGISTRY_FAILURE)?;
        Ok(Self {
            version,
            version_text,
            runtime,
            key,
        })
    }
    /// # Errors
    /// Returns a host error if the engine's string value cannot be read.
    pub fn value(&self, name: &str) -> Result<String> {
        self.key.string(name).map_err(|_| REGISTRY_FAILURE)
    }
    /// # Errors
    /// Returns a host error if the registered Framework installation is unavailable.
    pub fn validate_framework_installation(&self) -> Result<()> {
        if self
            .key
            .string("NetFrameworkV4IsInstalled")
            .is_ok_and(|value| value.starts_with("No"))
        {
            Err(INIT_FAILURE)
        } else {
            Ok(())
        }
    }
}

pub struct HostEnvironment {
    pub module: PathBuf,
    pub assemblies: PathBuf,
    pub runtime: PathBuf,
}
impl HostEnvironment {
    /// # Errors
    /// Returns a native error if the executable directory cannot be determined.
    pub fn discover() -> Result<Self> {
        let module = module_path(ptr::null_mut())?;
        let directory = module.parent().ok_or(INIT_FAILURE)?.to_path_buf();
        let (assemblies, runtime) =
            read_config(&directory).unwrap_or_else(|_| (directory.clone(), directory));
        Ok(Self {
            module,
            assemblies,
            runtime,
        })
    }

    /// Managed callers should use Directory.EnumerateFiles and Path.Combine.
    ///
    /// # Errors
    /// Returns a host error if no trusted assemblies can be located.
    pub fn trusted_assemblies(&self) -> Result<String> {
        let collect = |directory: &Path| -> Vec<PathBuf> {
            std::fs::read_dir(directory)
                .into_iter()
                .flatten()
                .filter_map(|entry| {
                    let entry = entry.ok()?;
                    let path = entry.path();
                    let name = entry.file_name().to_string_lossy().into_owned();
                    if entry.file_type().ok()?.is_file()
                        && name.to_ascii_lowercase().ends_with(".dll")
                        && !exclude_tpa(&name)
                    {
                        Some(path)
                    } else {
                        None
                    }
                })
                .collect()
        };
        let mut paths = collect(&self.runtime);
        if paths.is_empty() {
            paths = collect(Path::new(&expand(
                r"%windir%\system32\CoreClrPowerShellExt\v1.0\",
            )?));
        }
        if paths.is_empty() {
            return Err(INIT_FAILURE);
        }
        Ok(paths
            .iter()
            .map(|p| p.to_string_lossy())
            .collect::<Vec<_>>()
            .join(";"))
    }
}

/// Managed callers should use File.ReadLines, Directory.Exists and Environment.ExpandEnvironmentVariables.
fn read_config(directory: &Path) -> Result<(PathBuf, PathBuf)> {
    let text = std::fs::read_to_string(directory.join("RemotePowerShellConfig.txt"))
        .map_err(|_| INIT_FAILURE)?;
    // The original checks existence before expanding environment variables.
    let (assemblies, runtime) =
        host_config(&text, |value| Path::new(value).exists()).ok_or(INIT_FAILURE)?;
    Ok((
        PathBuf::from(expand(&assemblies)?),
        PathBuf::from(expand(&runtime)?),
    ))
}

/// Managed callers should use System.Xml.XmlReader with DtdProcessing.Prohibit.
///
/// # Errors
/// Returns a COM or host error if document creation or parsing fails.
pub fn xml_document(source: &str, file: bool) -> Result<IXMLDOMDocument> {
    unsafe {
        let document: IXMLDOMDocument =
            CoCreateInstance(&DOMDocument60, None, CLSCTX_INPROC_SERVER)
                .map_err(|e| status_code(e.code().0))?;
        document
            .Setasync(windows::Win32::Foundation::VARIANT_BOOL(0))
            .map_err(|e| status_code(e.code().0))?;
        let loaded = if file {
            document.load(&VARIANT::from(source))
        } else {
            document.loadXML(&BSTR::from(source))
        }
        .map_err(|e| status_code(e.code().0))?;
        if !loaded.as_bool() {
            return Err(CONSOLE_FAILURE);
        }
        Ok(document)
    }
}

/// # Errors
/// Returns a console-file error if the requested XML node cannot be read.
pub fn xml_value(document: &IXMLDOMDocument, query: &str) -> Result<String> {
    unsafe {
        document
            .selectSingleNode(&BSTR::from(query))
            .and_then(|node| node.text())
            .map(|s| s.to_string())
            .map_err(|_| CONSOLE_FAILURE)
    }
}

/// # Errors
/// Returns a console-file error for invalid paths, XML, schemas, or versions.
pub fn console_version(path: &str) -> Result<Version> {
    if !path.to_ascii_lowercase().ends_with(".psc1") {
        return Err(CONSOLE_FAILURE);
    }
    let _apartment = ComApartment::new(true, false).map_err(|_| CONSOLE_FAILURE)?;
    let document = xml_document(path, true).map_err(|_| CONSOLE_FAILURE)?;
    if xml_value(&document, "/PSConsoleFile/@ConsoleSchemaVersion")? != "1.0" {
        return Err(CONSOLE_FAILURE);
    }
    Version::parse(
        &xml_value(&document, "/PSConsoleFile/PSVersion/text()")?,
        true,
    )
    .ok_or(CONSOLE_FAILURE)
}
