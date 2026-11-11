// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#[cfg(windows)]
pub mod common;
#[cfg(windows)]
pub mod hosting;
#[cfg(windows)]
pub mod launcher;
pub mod policy;
#[cfg(all(windows, not(feature = "coreclr")))]
mod shell;
#[cfg(windows)]
mod win;
