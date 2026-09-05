import hashlib
import json
import os
import socket
import subprocess
import tempfile
import textwrap
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import patch

from backend import backend


ROOT = Path(__file__).resolve().parents[1]


class FakeResponse:
    def __init__(self, chunks, headers=None):
        self.chunks = chunks
        self.headers = headers or {"content-type": "image/jpeg"}
        self.closed = False

    def raise_for_status(self):
        return None

    def iter_content(self, chunk_size):
        self.chunk_size = chunk_size
        yield from self.chunks

    def close(self):
        self.closed = True


class SecurityBoundaryTests(unittest.TestCase):
    def test_recv_line_accepts_message_at_limit(self):
        sender, receiver = socket.socketpair()
        with sender, receiver:
            sender.sendall(b"12345\n")
            self.assertEqual(backend.recv_line(receiver, 5, "test IPC"), b"12345")

    def test_recv_line_rejects_oversized_message(self):
        sender, receiver = socket.socketpair()
        with sender, receiver:
            sender.sendall(b"123456\n")
            with self.assertRaisesRegex(RuntimeError, "превышает допустимый размер"):
                backend.recv_line(receiver, 5, "test IPC")

    def test_recv_line_requires_terminator(self):
        sender, receiver = socket.socketpair()
        sender.sendall(b"partial")
        sender.close()
        with receiver:
            with self.assertRaisesRegex(RuntimeError, "закрыто до конца"):
                backend.recv_line(receiver, 10, "test IPC")

    def test_streamed_http_json_rejects_oversized_body(self):
        response = FakeResponse([b'{"a"', b':123}'], {"content-type": "application/json"})
        with self.assertRaisesRegex(ValueError, "exceeds size limit"):
            backend.read_http_json(cast(Any, response), 5, "test HTTP")

    def test_streamed_http_json_rejects_oversized_content_length(self):
        response = FakeResponse([], {"content-type": "application/json", "content-length": "6"})
        with self.assertRaisesRegex(ValueError, "exceeds size limit"):
            backend.read_http_json(cast(Any, response), 5, "test HTTP")

    def test_network_probe_streams_and_closes_json_response(self):
        response = FakeResponse([b'{"result":{"account":', b'{"serviceAvailable":true,"region":1}}}'])
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.network = {}
        with patch.object(backend.requests, "get", return_value=response) as get:
            player._probe_network()
        get.assert_called_once_with(backend.API_STATUS_URL, timeout=(3, 5), stream=True)
        self.assertTrue(player.network["available"])
        self.assertTrue(response.closed)

    def test_refresh_token_streams_and_closes_json_response(self):
        response = FakeResponse([b'{"access_token":"new",', b'"refresh_token":"next"}'])
        player = backend.Player.__new__(backend.Player)
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch.object(backend, "TOKEN_FILE", Path(temporary) / "token.json"),
                patch.object(backend.requests, "post", return_value=response) as post,
            ):
                self.assertEqual(player._refresh_token({"refresh_token": "old"}), "new")
            self.assertTrue((Path(temporary) / "token.json").exists())
        self.assertTrue(post.call_args.kwargs["stream"])
        self.assertTrue(response.closed)

    def test_wave_settings_stream_json_before_using_result(self):
        response = FakeResponse([b'{"result":', b'"ok"}'])
        track = object()
        station_result = SimpleNamespace(
            sequence=[SimpleNamespace(track=track)], batch_id="batch"
        )
        player = cast(Any, backend.Player.__new__(backend.Player))
        player.client = SimpleNamespace(
            base_url="https://example.test",
            _request=SimpleNamespace(headers={}, proxies={}),
            rotor_station_tracks=lambda station: station_result,
        )
        player.preferences = {"waveMood": "all", "waveDiversity": "default", "waveLanguage": "any"}
        player._api_call = lambda function: function()
        player._loading = lambda function, kind: function()
        player._set_error = lambda error: self.fail(error)
        queue_calls = []
        player._set_queue = lambda *args: queue_calls.append(args)
        with patch.object(backend.requests, "post", return_value=response) as post:
            player.play_wave()
        self.assertTrue(post.call_args.kwargs["stream"])
        self.assertTrue(response.closed)
        self.assertEqual(queue_calls[0], ([track], "Моя волна", "user:onyourwave", "batch"))

    def test_notification_cover_streams_with_a_hard_limit(self):
        response = FakeResponse([b"1234", b"56"])
        player = backend.Player.__new__(backend.Player)
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch.object(backend, "RUNTIME", Path(temporary)),
                patch.object(backend, "NOTIFICATION_COVER_MAX_BYTES", 5),
                patch.object(backend.requests, "get", return_value=response) as get,
            ):
                self.assertEqual(player._notification_cover("https://example.test/cover"), "audio-x-generic")
            get.assert_called_once_with("https://example.test/cover", timeout=10, stream=True)
            self.assertFalse(list(Path(temporary).rglob("*.jpg")))
            self.assertFalse(list(Path(temporary).rglob("*.tmp")))
        self.assertTrue(response.closed)

    def test_notification_cover_atomically_caches_valid_image(self):
        response = FakeResponse([b"12", b"345"])
        player = backend.Player.__new__(backend.Player)
        with tempfile.TemporaryDirectory() as temporary:
            with (
                patch.object(backend, "RUNTIME", Path(temporary)),
                patch.object(backend, "NOTIFICATION_COVER_MAX_BYTES", 5),
                patch.object(backend.requests, "get", return_value=response),
            ):
                result = player._notification_cover("https://example.test/cover")
            cover = Path(result)
            self.assertEqual(cover.read_bytes(), b"12345")
            self.assertEqual(cover.stat().st_mode & 0o777, 0o600)
        self.assertTrue(response.closed)

    def test_installer_uses_only_hash_locked_binary_dependencies(self):
        installer = (ROOT / "install.sh").read_text()
        self.assertNotIn("--upgrade pip", installer)
        self.assertNotIn("pip install --disable-pip-version-check --quiet --upgrade", installer)
        for option in ("--require-hashes", "--only-binary=:all:", "--no-deps"):
            self.assertIn(option, installer)

        requirements = (ROOT / "requirements.txt").read_text()
        self.assertNotIn("git+", requirements)
        logical_lines = []
        current = ""
        for raw_line in requirements.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            current = f"{current} {line.rstrip('\\').strip()}".strip()
            if not line.endswith("\\"):
                logical_lines.append(current)
                current = ""
        self.assertTrue(logical_lines)
        for requirement in logical_lines:
            self.assertIn("--hash=sha256:", requirement)

    def test_installer_rebuilds_changed_dependencies_then_uses_fast_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            runtime = Path(temporary) / "runtime"
            fake_bin = Path(temporary) / "bin"
            log = Path(temporary) / "commands.log"
            home.mkdir()
            runtime.mkdir()
            fake_bin.mkdir()
            python = fake_bin / "python"
            python.write_text(textwrap.dedent("""\
                #!/usr/bin/env bash
                set -eu
                if [[ "${1:-}" == "-m" && "${2:-}" == "venv" ]]; then
                  mkdir -p "$3/bin"
                  cp "$0" "$3/bin/python"
                  chmod 755 "$3/bin/python"
                  exit 0
                fi
                printf 'python %s\\n' "$*" >>"$INSTALLER_TEST_LOG"
            """))
            python.chmod(0o755)
            for command in ("mpv", "systemctl"):
                executable = fake_bin / command
                executable.write_text("#!/usr/bin/env bash\nprintf '%s %s\\n' \"$(basename \"$0\")\" \"$*\" >>\"$INSTALLER_TEST_LOG\"\n")
                executable.chmod(0o755)
            environment = {
                **os.environ,
                "HOME": str(home),
                "XDG_RUNTIME_DIR": str(runtime),
                "PATH": f"{fake_bin}:{os.environ['PATH']}",
                "INSTALLER_TEST_LOG": str(log),
            }
            command = [str(ROOT / "install.sh"), "--backend-only"]
            subprocess.run(command, check=True, env=environment, capture_output=True, text=True)
            first_log = log.read_text()
            self.assertIn("--require-hashes", first_log)
            self.assertEqual(first_log.count("python -m pip install"), 1)

            subprocess.run(command, check=True, env=environment, capture_output=True, text=True)
            self.assertEqual(log.read_text().count("python -m pip install"), 1)

            dependency_marker = home / ".local/share/omarchy-yandex-music/.installed-dependencies"
            dependency_marker.write_text("stale\n")
            subprocess.run(command, check=True, env=environment, capture_output=True, text=True)
            self.assertEqual(log.read_text().count("python -m pip install"), 2)

    def test_vendored_yandex_music_wheel_matches_lock(self):
        wheel = ROOT / "vendor/yandex_music-3.1.0b2-py3-none-any.whl"
        digest = hashlib.sha256(wheel.read_bytes()).hexdigest()
        self.assertEqual(digest, "2f200b887b2be33b37f4eb05a4762703b11fe334205c16d7fac29f24d8a52e31")
        self.assertIn(digest, (ROOT / "requirements.txt").read_text())
        provenance = json.loads((ROOT / "vendor/yandex_music-3.1.0b2.origin.json").read_text())
        self.assertEqual(
            provenance["vcs_info"]["commit_id"],
            "0fa54f2d32084a9e461bce41890d1c9ab70d91aa",
        )

    def test_cli_bounds_service_response(self):
        cli = (ROOT / "bin/omarchy-yandex-music").read_text()
        self.assertIn("IPC_RESPONSE_MAX_BYTES", cli)
        self.assertIn("IPC_RESPONSE_MAX_BYTES - len(data) + 1", cli)


if __name__ == "__main__":
    unittest.main()
