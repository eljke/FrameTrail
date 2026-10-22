#!/usr/bin/env python3
"""Print an available iPhone simulator UUID for the selected Xcode."""

import json
import re
import subprocess
import sys


def main():
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        check=True, capture_output=True, text=True
    )
    candidates = []
    for runtime, devices in json.loads(result.stdout)["devices"].items():
        match = re.search(r"iOS-(\d+)-(\d+)", runtime)
        if not match or int(match.group(1)) < 26:
            continue
        version = tuple(int(part) for part in match.groups())
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        sys.exit("No available iOS 26+ iPhone simulator. Install an iOS runtime in Xcode.")
    print(max(candidates)[2])


if __name__ == "__main__":
    main()
