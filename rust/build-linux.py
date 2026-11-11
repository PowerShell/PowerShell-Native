#!/usr/bin/env python3
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

"""Build the four libc/architecture-specific shared libraries, not static archives."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
TARGETS = {
    "linux-x64": "x86_64-unknown-linux-gnu.2.28",
    "linux-arm64": "aarch64-unknown-linux-gnu.2.28",
    "linux-musl-x64": "x86_64-unknown-linux-musl",
    "linux-musl-arm64": "aarch64-unknown-linux-musl",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TARGETS, action="append")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts")
    args = parser.parse_args()
    for rid in args.target or TARGETS:
        target = TARGETS[rid]
        subprocess.run(
            [
                "cargo", "zigbuild", "--locked", "--release",
                "--package", "psl-native", "--target", target,
            ],
            cwd=ROOT,
            check=True,
        )
        base_target = target.split(".")[0]
        target_dir = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "target"))
        if not target_dir.is_absolute():
            target_dir = ROOT / target_dir
        source = target_dir / base_target / "release" / "libpsl_native.so"
        destination = args.output.resolve() / rid / "libpsl-native.so"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        print(destination, flush=True)


if __name__ == "__main__":
    main()
