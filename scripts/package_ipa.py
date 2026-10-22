#!/usr/bin/env python3
"""Package an unsigned device app for AltStore re-signing."""

import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import sys
import zipfile

from validate import semantic_version


def package(app, version, output, max_size_mb):
    version, base = semantic_version(version)
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("--app must point to a built iPhoneOS .app directory")
    metadata = plistlib.loads((app / "Info.plist").read_bytes())
    if metadata["CFBundleShortVersionString"] != base:
        raise ValueError("Built app version does not match the release tag")
    if metadata.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Only a device build can be packaged as a release IPA")
    executable = app / metadata["CFBundleExecutable"]
    if not executable.is_file():
        raise ValueError("Built app executable is missing")
    files = sorted(path for path in app.rglob("*") if path.is_file() or path.is_symlink())
    app_size = sum(path.lstat().st_size for path in files)
    ceiling = max_size_mb * 1024 * 1024
    if app_size > ceiling:
        raise ValueError(f"App is {app_size / 1024 / 1024:.1f} MiB; limit is {max_size_mb} MiB")
    output.mkdir(parents=True, exist_ok=True)
    ipa = output / f"FrameTrail-{version}.ipa"
    try:
        with zipfile.ZipFile(ipa, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files:
                name = (Path("Payload") / app.name / path.relative_to(app)).as_posix()
                if path.is_symlink():
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, os.readlink(path))
                else:
                    archive.write(path, name)
        if ipa.stat().st_size > ceiling:
            raise ValueError(f"IPA exceeds {max_size_mb} MiB")
    except Exception:
        ipa.unlink(missing_ok=True)
        raise
    with ipa.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    (output / f"{ipa.name}.sha256").write_text(f"{checksum}  {ipa.name}\n", encoding="utf-8")
    print(f"Packaged {ipa.name}: {ipa.stat().st_size / 1024 / 1024:.2f} MiB; app {app_size / 1024 / 1024:.2f} MiB")
    return ipa


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--max-size-mb", type=int, default=40)
    arguments = parser.parse_args()
    try:
        package(arguments.app, arguments.version, arguments.output, arguments.max_size_mb)
    except (OSError, ValueError, KeyError) as failure:
        sys.exit(str(failure))
