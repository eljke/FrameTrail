#!/usr/bin/env python3
"""Exercise IPA contents, release boundaries, and reproducible icon metadata."""

import hashlib
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from package_ipa import package
from validate import self_test


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[1] / "build/delivery-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=scratch)
        self.root = Path(self.directory.name)
        self.app = self.root / "FrameTrail.app"
        self.app.mkdir()
        self.metadata = {
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "CFBundleExecutable": "FrameTrail",
        }
        self.save_metadata()
        (self.app / "FrameTrail").write_bytes(b"device executable fixture")

    def tearDown(self):
        self.directory.cleanup()

    def save_metadata(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.metadata))

    def test_ipa_contains_payload_and_checksum(self):
        ipa = package(self.app, "v1.0.0-beta.1", self.root / "dist", 40)
        with zipfile.ZipFile(ipa) as archive:
            self.assertEqual(set(archive.namelist()), {
                "Payload/FrameTrail.app/Info.plist", "Payload/FrameTrail.app/FrameTrail"
            })
            self.assertEqual(archive.read("Payload/FrameTrail.app/FrameTrail"), b"device executable fixture")
        expected = hashlib.sha256(ipa.read_bytes()).hexdigest()
        self.assertEqual((ipa.parent / f"{ipa.name}.sha256").read_text(), f"{expected}  {ipa.name}\n")

    def test_simulator_cannot_be_released(self):
        self.metadata["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.save_metadata()
        with self.assertRaisesRegex(ValueError, "device build"):
            package(self.app, "1.0.0-beta.1", self.root / "dist", 40)

    def test_tag_must_match_app_version(self):
        with self.assertRaisesRegex(ValueError, "version"):
            package(self.app, "1.1.0-beta.1", self.root / "dist", 40)

    def test_oversized_app_cannot_be_released(self):
        (self.app / "large.bin").write_bytes(b"x" * 1024 * 1024)
        with self.assertRaisesRegex(ValueError, "limit"):
            package(self.app, "1.0.0-beta.1", self.root / "dist", 1)

    def test_semantic_versions(self):
        self_test()


if __name__ == "__main__":
    unittest.main()
