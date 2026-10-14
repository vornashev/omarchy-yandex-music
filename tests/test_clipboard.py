"""Exercise the real reader against finite, streaming and stalled pipe producers."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

READER = Path(__file__).resolve().parents[1] / "bin" / "read-clipboard.py"
LIMIT = 16 * 1024


class ClipboardTests(unittest.TestCase):
    def read(self, body, primary=False):
        with tempfile.TemporaryDirectory() as directory:
            provider = Path(directory) / "wl-paste"
            provider.write_text(f"#!{sys.executable}\nimport os, sys, time\n" + body)
            provider.chmod(0o755)
            start = time.monotonic()
            result = subprocess.run(
                [sys.executable, "-B", str(READER), *(["--primary"] if primary else [])],
                env={**os.environ, "PATH": directory}, capture_output=True, timeout=4)
            elapsed = time.monotonic() - start
        return result, elapsed

    def test_utf8_selection_and_primary(self):
        for primary in (False, True):
            with self.subTest(primary=primary):
                result, _ = self.read(
                    f"assert ('--primary' in sys.argv) == {primary!r}\n"
                    "os.write(1, 'Поиск 🎵\\nвторая строка'.encode('utf-8'))\n", primary)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(json.loads(result.stdout), "Поиск 🎵\nвторая строка")

    def test_exact_byte_boundary(self):
        result, _ = self.read(f"os.write(1, b'a' * {LIMIT})\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout), "a" * LIMIT)

    def test_oversized_and_infinite_providers_rejected_without_partial_text(self):
        for body in (f"os.write(1, b'a' * {LIMIT + 1})\n",
                     "while True: os.write(1, b'a' * 4096)\n"):
            with self.subTest(body=body):
                result, elapsed = self.read(body)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertLess(elapsed, 2.5)

    def test_deadline_is_total_not_per_chunk(self):
        for body in ("time.sleep(30)\n",
                     "while True:\n os.write(1, b'a')\n time.sleep(0.05)\n"):
            with self.subTest(body=body):
                result, elapsed = self.read(body)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
                self.assertLess(elapsed, 2.5)

    def test_invalid_utf8_and_failed_transfer_rejected(self):
        for body in ("os.write(1, b'\\xff')\n",
                     "os.write(1, b'partial')\nsys.exit(1)\n"):
            with self.subTest(body=body):
                result, _ = self.read(body)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, b"")
