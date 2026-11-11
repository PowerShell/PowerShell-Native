// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

use crate::{
    common::RegistryKey,
    win::{
        expand, status_code, string, wide, ComApartment, GetCurrentProcess, GetModuleHandleW,
        GetStartupInfoW, IsWow64Process, LoadStringW, Result, SetConsoleTitleW, StartupInfo,
    },
};
use std::{path::Path, ptr};
use windows::{
    core::{Interface, GUID, PCWSTR, PROPVARIANT},
    Win32::{
        System::Com::{CoCreateInstance, IPersistFile, CLSCTX_INPROC_SERVER, STGM_READWRITE},
        UI::Shell::{
            Common::{IObjectArray, IObjectCollection},
            DestinationList, EnumerableObjectCollection, ICustomDestinationList,
            IShellLinkDataList, IShellLinkW,
            PropertiesSystem::{IPropertyStore, PROPERTYKEY},
            ShellLink, SLDF_ALLOW_LINK_TO_LINK, SLDF_RUNAS_USER,
        },
    },
};

const ISE: &str = r"%systemroot%\system32\windowspowershell\v1.0\powershell_ise.exe";
const TITLE: PROPERTYKEY = PROPERTYKEY {
    fmtid: GUID::from_u128(0xf29f85e0_4ff9_1068_ab91_08002b27b3d9),
    pid: 2,
};

fn resource(id: u32) -> windows::core::Result<String> {
    let mut buffer = vec![0; 1024];
    let length =
        unsafe { LoadStringW(GetModuleHandleW(ptr::null()), id, buffer.as_mut_ptr(), 1024) };
    if length <= 0 {
        return Err(windows::core::Error::from_win32());
    }
    Ok(String::from_utf16_lossy(
        &buffer[..length.unsigned_abs() as usize],
    ))
}

/// Windows shell links and jump lists have no direct cross-platform .NET equivalent.
unsafe fn shortcut(
    title: &str,
    path: &str,
    icon: &str,
    index: i32,
    elevation: bool,
) -> windows::core::Result<IShellLinkW> {
    let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;
    link.SetPath(PCWSTR(wide(path).as_ptr()))?;
    link.SetArguments(PCWSTR(wide("").as_ptr()))?;
    link.SetIconLocation(PCWSTR(wide(icon).as_ptr()), index)?;
    let properties: IPropertyStore = link.cast()?;
    properties.SetValue(&TITLE, &PROPVARIANT::from(title))?;
    properties.Commit()?;
    let data: IShellLinkDataList = link.cast()?;
    let mut flags = data.GetFlags()? | SLDF_ALLOW_LINK_TO_LINK.0 as u32;
    if elevation {
        flags |= SLDF_RUNAS_USER.0 as u32;
    }
    data.SetFlags(flags)?;
    Ok(link)
}

fn shortcut_path(startup: &StartupInfo) -> Result<String> {
    if startup.flags & 0x800 != 0 && !startup.title.is_null() {
        return Ok(unsafe { string(startup.title) });
    }
    let mut wow64 = 0;
    // Managed callers should use Environment.Is64BitOperatingSystem/Is64BitProcess.
    unsafe {
        IsWow64Process(GetCurrentProcess(), &raw mut wow64);
    }
    let name = if wow64 != 0 {
        "ConsoleHostShortcutTargetX86"
    } else {
        "ConsoleHostShortcutTarget"
    };
    if let Ok(key) = RegistryKey::open(r"SOFTWARE\Microsoft\PowerShell\3") {
        if let Ok(path) = key.read_string(name, true) {
            return expand(&path);
        }
    }
    let candidates: &[&str] = if wow64 != 0 {
        &[
            r"%AppData%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell(x86).lnk",
            r"%ProgramData%\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Windows PowerShell (x86).lnk",
            r"%ProgramData%\Microsoft\Windows\Start Menu\Programs\Accessories\Windows PowerShell\Windows PowerShell (x86).lnk",
        ]
    } else {
        &[
            r"%AppData%\Microsoft\Windows\Start Menu\Programs\Windows PowerShell\Windows PowerShell.lnk",
            r"%ProgramData%\Microsoft\Windows\Start Menu\Programs\System Tools\Windows PowerShell.lnk",
            r"%ProgramData%\Microsoft\Windows\Start Menu\Programs\Accessories\Windows PowerShell\Windows PowerShell.lnk",
        ]
    };
    for candidate in candidates {
        let path = expand(candidate)?;
        // Managed callers should use File.Exists.
        if Path::new(&path).is_file() {
            return Ok(path);
        }
    }
    expand(r"%windir%\System32\WindowsPowerShell\v1.0\powershell.exe")
}

pub fn initialize() -> Result<()> {
    let mut startup = StartupInfo::default();
    unsafe {
        GetStartupInfoW(&raw mut startup);
    }
    if startup.flags & 1 == 0 || startup.show == 0 {
        return Ok(());
    }
    let _apartment = ComApartment::new(false, false)?;
    let result = unsafe { create_list(&startup) };
    result.map_err(|error| status_code(error.code().0))
}

unsafe fn create_list(startup: &StartupInfo) -> windows::core::Result<()> {
    let list: ICustomDestinationList =
        CoCreateInstance(&DestinationList, None, CLSCTX_INPROC_SERVER)?;
    let mut slots = 0;
    let _removed: IObjectArray = list.BeginList(&raw mut slots)?;
    let transaction = (|| {
        if slots < 4 {
            return Ok(());
        }
        let target = shortcut_path(startup).map_err(|code| {
            windows::core::Error::from_hresult(windows::core::HRESULT::from_win32(code))
        })?;
        if startup.flags & 0x800 == 0 {
            let title = wide(&resource(109)?);
            SetConsoleTitleW(title.as_ptr());
        }
        let mut icon = expand(r"%windir%\System32\WindowsPowerShell\v1.0\powershell.exe")
            .unwrap_or_else(|_| target.clone());
        let mut index = 0;
        let original: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;
        let persisted: IPersistFile = original.cast()?;
        if persisted
            .Load(PCWSTR(wide(&target).as_ptr()), STGM_READWRITE)
            .is_ok()
        {
            let mut path = vec![0; 32768];
            original.GetIconLocation(&mut path, &raw mut index)?;
            let end = path.iter().position(|c| *c == 0).unwrap_or(path.len());
            icon = String::from_utf16_lossy(&path[..end]);
        }
        let collection: IObjectCollection =
            CoCreateInstance(&EnumerableObjectCollection, None, CLSCTX_INPROC_SERVER)?;
        collection.AddObject(&shortcut(&resource(118)?, &target, &icon, index, true)?)?;
        let ise = expand(ISE).unwrap_or_else(|_| ISE.to_string());
        if Path::new(&ise).is_file() {
            collection.AddObject(&shortcut(&resource(122)?, ISE, ISE, 0, true)?)?;
            collection.AddObject(&shortcut(&resource(101)?, ISE, ISE, 0, false)?)?;
        }
        let array: IObjectArray = collection.cast()?;
        list.AddUserTasks(&array)?;
        list.CommitList()
    })();
    if transaction.is_err() || slots < 4 {
        let _ = list.AbortList();
    }
    transaction
}
