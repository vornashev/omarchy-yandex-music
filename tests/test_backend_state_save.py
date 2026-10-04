import json
import threading
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from backend import backend


class StateSaveTests(unittest.TestCase):
    def test_concurrent_atomic_writes_keep_a_valid_file(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            first_at_replace = threading.Event()
            release_first = threading.Event()
            failures = []
            replace = Path.replace

            def pause_first_replace(source, target):
                if threading.current_thread().name == "first-writer":
                    first_at_replace.set()
                    if not release_first.wait(2):
                        raise AssertionError("first writer was not released")
                return replace(source, target)

            def write(value):
                try:
                    backend.atomic_json(path, {"value": value})
                except Exception as exc:
                    failures.append(exc)

            with patch.object(Path, "replace", pause_first_replace):
                first = threading.Thread(target=write, args=(1,), name="first-writer")
                first.start()
                try:
                    self.assertTrue(first_at_replace.wait(2))
                    second = threading.Thread(target=write, args=(2,), name="second-writer")
                    second.start()
                    second.join(2)
                    self.assertFalse(second.is_alive())
                finally:
                    release_first.set()
                    first.join(2)

            self.assertFalse(first.is_alive())
            self.assertEqual(failures, [])
            self.assertIn(json.loads(path.read_text())["value"], (1, 2))
            self.assertEqual(sorted(item.name for item in path.parent.iterdir()), ["state.json"])
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_concurrent_state_saves_keep_the_latest_snapshot(self):
        player = backend.Player()
        player.state.update(queueName="test", position=1, playing=False)

        first_in_write = threading.Event()
        release_first = threading.Event()
        failures = []
        real_write = backend.atomic_json

        def slow_first_write(path, value):
            if threading.current_thread().name == "first-save":
                first_in_write.set()
                if not release_first.wait(2):
                    raise AssertionError("first save was not released")
            real_write(path, value)

        def save():
            try:
                player._save_state(force=True)
            except Exception as exc:
                failures.append(exc)

        with TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            with patch.object(backend, "STATE_FILE", path), patch.object(
                backend, "atomic_json", side_effect=slow_first_write
            ):
                first = threading.Thread(target=save, name="first-save")
                first.start()
                try:
                    self.assertTrue(first_in_write.wait(2))
                    with player.lock:
                        player.state["position"] = 2
                    second = threading.Thread(target=save, name="second-save")
                    second.start()
                    # With serialization, the newer snapshot must wait for the first write.
                    second.join(0.1)
                finally:
                    release_first.set()
                    first.join(2)
                    second.join(2)

            self.assertFalse(first.is_alive())
            self.assertFalse(second.is_alive())
            self.assertEqual(failures, [])
            self.assertEqual(json.loads(path.read_text())["position"], 2)
