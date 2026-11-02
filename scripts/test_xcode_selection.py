import plistlib
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import select_xcode


class XcodeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def app(self, name, version):
        app = self.root / name
        (app / 'Contents/Developer').mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': version}))
        return app / 'Contents/Developer'

    def test_selects_supported_stable_sdk_without_probing_every_app(self):
        self.app('Xcode_26.0.app', '26.0')
        selected = self.app('Xcode_26.6.app', '26.6')
        self.app('Xcode_27_beta.app', '27.0')
        with patch('select_xcode.subprocess.run', return_value=SimpleNamespace(returncode=0, stdout='Xcode 26.6\n')) as run:
            self.assertEqual(select_xcode.select_xcode(self.root), selected)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.kwargs['env']['DEVELOPER_DIR'], str(selected))
        self.assertLessEqual(run.call_args.kwargs['timeout'], 60)

    def test_timed_out_toolchain_falls_back_to_next_supported_sdk(self):
        self.app('Xcode_26.6.app', '26.6')
        fallback = self.app('Xcode_26.5.app', '26.5')
        with patch('select_xcode.subprocess.run', side_effect=[subprocess.TimeoutExpired('xcodebuild', 45), SimpleNamespace(returncode=0, stdout='Xcode 26.5\n')]):
            self.assertEqual(select_xcode.select_xcode(self.root), fallback)

    def test_older_sdk_is_rejected_before_probe(self):
        self.app('Xcode_26.0.app', '26.0')
        with patch('select_xcode.subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, '26.4'):
                select_xcode.select_xcode(self.root)
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
