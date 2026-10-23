#!/usr/bin/env python3
"""Validate release metadata and source hygiene without external packages."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(
    r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?"
)
EXCLUDED = {".git", ".build", ".swiftpm", "build", "dist", "DerivedData", "FrameTrail.xcodeproj"}
TEXT_SUFFIXES = {".swift", ".py", ".sh", ".json", ".yml", ".yaml", ".plist", ".md", ".txt", ".xcprivacy", ".sql", ".ts", ".toml", ".svg"}


def semantic_version(value):
    value = value.removeprefix("v")
    match = SEMVER.fullmatch(value)
    if not match:
        raise ValueError(f"Invalid semantic version: {value}")
    return value, ".".join(match.group(index) for index in (1, 2, 3))


def source_files():
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED for part in relative.parts) or not path.is_file():
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in {".gitignore", "LICENSE", "VERSION"}:
            yield path


def validate(version=None):
    errors = []
    declared = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    expected, base = semantic_version(version or declared)
    if expected != declared:
        errors.append(f"Release {expected} differs from VERSION {declared}")
    specification = (ROOT / "project.yml").read_text(encoding="utf-8")
    if not re.search(rf'MARKETING_VERSION:\s*"{re.escape(base)}"\s*$', specification, re.MULTILINE):
        errors.append(f"project.yml MARKETING_VERSION must be {base}")
    for path in source_files():
        data = path.read_bytes()
        try:
            source = data.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"Not UTF-8: {path.relative_to(ROOT)}")
            continue
        if source and not source.splitlines()[-1].strip():
            errors.append(f"Blank final line: {path.relative_to(ROOT)}")
        if path.suffix == ".json":
            try:
                json.loads(source)
            except json.JSONDecodeError as error:
                errors.append(f"Invalid JSON in {path.relative_to(ROOT)}: {error}")
        if path.suffix in {".plist", ".xcprivacy"}:
            try:
                plistlib.loads(data)
            except (plistlib.InvalidFileException, ValueError) as error:
                errors.append(f"Invalid plist in {path.relative_to(ROOT)}: {error}")
    icon = ROOT / "FrameTrail/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    data = icon.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (1024, 1024):
        errors.append("App icon must be a 1024 x 1024 PNG")
    if data[25] != 2:
        errors.append("App icon must be opaque RGB")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"Validated {expected}: metadata, source endings, JSON, plists, icon.")


def self_test():
    for value in ("1.0.0", "1.0.0-beta.1", "0.1.0-rc.2+build.5", "v1.0.0-beta.1"):
        semantic_version(value)
    for value in ("01.0.0", "1.0", "1.0.0-01", "1.0.0-beta..1", "1.0.0;rm"):
        try:
            semantic_version(value)
        except ValueError:
            continue
        raise AssertionError(f"Accepted invalid version: {value}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version")
    arguments = parser.parse_args()
    try:
        self_test()
        validate(arguments.version)
    except (OSError, ValueError) as failure:
        sys.exit(str(failure))
