// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#[cfg(windows)]
fn main() {
    std::process::exit(i32::from_ne_bytes(
        powershell_native_host::launcher::run().to_ne_bytes(),
    ));
}

#[cfg(not(windows))]
fn main() {
    eprintln!("powershell-native-windows requires Windows");
    std::process::exit(1);
}
