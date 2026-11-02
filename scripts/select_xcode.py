#!/usr/bin/env python3
"""Select an installed, stable Xcode with the Foundation Models SDK."""

import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def select_xcode(applications=Path("/Applications")):
    candidates = []
    for app in applications.glob("Xcode*.app"):
        if "beta" in app.name.lower():
            continue
        try:
            metadata = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            version = tuple(int(part) for part in metadata["CFBundleShortVersionString"].split("."))
        except (OSError, ValueError, KeyError, plistlib.InvalidFileException):
            continue
        if version >= (26, 4):
            candidates.append((version, app / "Contents/Developer"))
    for _, developer in sorted(candidates, key=lambda item: (item[0][0] == 26, item[0]), reverse=True):
        environment = dict(os.environ, DEVELOPER_DIR=str(developer))
        try:
            result = subprocess.run(
                ["xcodebuild", "-version"], env=environment, capture_output=True, text=True, timeout=45
            )
        except subprocess.TimeoutExpired:
            print(f"Skipping unresponsive Xcode: {developer}", file=sys.stderr)
            continue
        match = re.search(r"^Xcode (\d+(?:\.\d+)*)", result.stdout)
        if result.returncode == 0 and match:
            actual = tuple(int(part) for part in match.group(1).split("."))
            if actual >= (26, 4):
                return developer
    raise ValueError("A responsive stable Xcode 26.4 or later is required.")


if __name__ == "__main__":
    try:
        print(select_xcode())
    except ValueError as error:
        sys.exit(str(error))
