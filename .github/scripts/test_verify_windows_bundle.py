from pathlib import Path
import tempfile
import unittest

from verify_windows_bundle import REQUIRED_FILES, verify_bundle


class WindowsBundleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def fill_bundle(self):
        for name in REQUIRED_FILES:
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"release")

    def test_missing_files(self):
        with self.assertRaisesRegex(ValueError, "Missing or empty"):
            verify_bundle(self.root)

    def test_empty_file(self):
        self.fill_bundle()
        (self.root / "data/app.so").write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "data/app.so"):
            verify_bundle(self.root)

    def test_release(self):
        self.fill_bundle()
        report = verify_bundle(self.root)
        self.assertIn("6 files", report)
        self.assertIn("flutter_windows.dll", report)

    def test_debug_kernel(self):
        self.fill_bundle()
        (self.root / "data/flutter_assets/kernel_blob.bin").write_bytes(b"debug")
        with self.assertRaisesRegex(ValueError, "Debug kernel"):
            verify_bundle(self.root)


if __name__ == "__main__":
    unittest.main()
