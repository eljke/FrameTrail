#!/usr/bin/env python3
"""Select an installed, stable Xcode with the Foundation Models SDK."""

import os
from pathlib import Path
import re
import subprocess
import sys


def main():
    candidates = []
    for app in Path("/Applications").glob("Xcode*.app"):
        if "beta" in app.name.lower():
            continue
        developer = app / "Contents/Developer"
        environment = dict(os.environ, DEVELOPER_DIR=str(developer))
        result = subprocess.run(
            ["xcodebuild", "-version"], env=environment, capture_output=True, text=True
        )
        match = re.search(r"^Xcode (\d+(?:\.\d+)*)", result.stdout)
        if result.returncode == 0 and match:
            version = tuple(int(part) for part in match.group(1).split("."))
            if version[0] >= 26:
                candidates.append((version, developer))
    if not candidates:
        sys.exit("A stable Xcode 26 or later is required.")
    xcode_26 = [candidate for candidate in candidates if candidate[0][0] == 26]
    print(max(xcode_26 or candidates)[1])


if __name__ == "__main__":
    main()
