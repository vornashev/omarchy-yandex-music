import json
import os
import ssl
import subprocess
import threading
import time
import unittest
from collections import OrderedDict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from backend import backend


class LrclibTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.certificates = TemporaryDirectory()
        directory = Path(cls.certificates.name)
        cls.cert = directory / "cert.pem"
        cls.key = directory / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost",
            "-keyout", str(cls.key), "-out", str(cls.cert),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        cls.certificates.cleanup()

    def setUp(self):
        self.home = TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        environment = patch.dict(os.environ, HOME=self.home.name, CURL_CA_BUNDLE=str(self.cert))
        environment.start()
        self.addCleanup(environment.stop)
        self.responses = deque()
        self.records = []
        self.held = threading.Event()
        self.released = threading.Event()
        self.tokens = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_GET(self):
                parsed = urlsplit(self.path)
                name = parse_qs(parsed.query).get("track_name", [""])[0]
                owner.records.append((parsed.path, name, time.monotonic()))
                if name == "Hold":
                    owner.held.set()
                    self.connection.settimeout(4)
                    try:
                        self.connection.recv(1)
                    except OSError:
                        pass
                    finally:
                        owner.released.set()
                    return
                status, body, known_length, delay = owner.responses.popleft() if owner.responses else (
                    200, json.dumps({"syncedLyrics": "[00:01.25]Synthetic"}).encode(), True, 0)
                if status == 0: return
                if delay: time.sleep(delay)
                self.send_response(status)
                if known_length:
                    self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                try:
                    self.wfile.write(body)
                except OSError:
                    pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.player = backend.Player.__new__(backend.Player)
        self.http = self.player._lrclib_json
        self.player._lrclib_json = lambda url, params, load: self.http(
            f"https://localhost:{self.server.server_port}{urlsplit(url).path}", params, load)
        self.track = SimpleNamespace(id="fixture", title="Fixture", artists=[SimpleNamespace(name="Synthetic")])

    def tearDown(self):
        for token in self.tokens:
            token.cancel()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def token(self):
        token = backend.LyricsLoad()
        self.tokens.append(token)
        return token

    def reply(self, status, payload, *, known_length=True, delay=0):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.responses.append((status, body, known_length, delay))

    def test_temporary_outage_recovers_with_increasing_bounded_delays(self):
        self.reply(503, b"temporary")
        self.reply(502, b"temporary")
        self.reply(200, {"syncedLyrics": "[00:10.47]Recovered"})
        result = self.player._fetch_lrclib_synced(self.track, self.token())
        self.assertEqual(backend.Player._parse_lrc(result), [{"time": 10.47, "text": "Recovered"}])
        self.assertEqual([row[0] for row in self.records], ["/api/get"] * 3)
        self.assertGreaterEqual(self.records[1][2] - self.records[0][2], 0.9)
        self.assertGreaterEqual(self.records[2][2] - self.records[1][2], 1.9)

    def test_timeout_and_connection_reset_recover_within_the_shared_retry_budget(self):
        self.reply(200, {}, delay=0.6)
        self.reply(0, b"")
        self.reply(200, {"syncedLyrics": "[00:03.5]Recovered"})
        with (patch.object(backend, "LRCLIB_TIMEOUT", 0.2),
              patch.object(backend, "LRCLIB_RETRY_DELAYS", (0, 0))):
            result = self.player._fetch_lrclib_synced(self.track, self.token())
        self.assertEqual(backend.Player._parse_lrc(result), [{"time": 3.5, "text": "Recovered"}])
        self.assertEqual([row[0] for row in self.records], ["/api/get"] * 3)

    def test_get_and_search_share_two_retries_instead_of_multiplying_them(self):
        self.reply(503, b"temporary")
        self.reply(404, b"missing")
        self.reply(503, b"temporary")
        self.reply(503, b"still unavailable")
        with patch.object(backend, "LRCLIB_RETRY_DELAYS", (0, 0)):
            with self.assertRaises(backend.requests.HTTPError):
                self.player._fetch_lrclib_synced(self.track, self.token())
        self.assertEqual([row[0] for row in self.records], ["/api/get", "/api/get", "/api/search", "/api/search"])

    def test_missing_or_untimed_results_and_permanent_errors_do_not_retry(self):
        for status in (401, 403, 429):
            with self.subTest(status=status):
                self.records.clear()
                self.reply(status, b"rejected")
                with self.assertRaises(backend.requests.HTTPError):
                    self.player._fetch_lrclib_synced(self.track, self.token())
                self.assertEqual([row[0] for row in self.records], ["/api/get"])
        for first in ((404, b"missing"), (200, {"syncedLyrics": None})):
            self.records.clear()
            self.reply(*first)
            self.reply(200, [])
            self.assertEqual(self.player._fetch_lrclib_synced(self.track, self.token()), "")
            self.assertEqual([row[0] for row in self.records], ["/api/get", "/api/search"])

    def test_oversized_known_unknown_length_and_invalid_json_are_rejected_without_retry(self):
        for body, known_length in ((b"x" * 4096, True), (b"x" * 4096, False), (b"not json", True)):
            with self.subTest(known_length=known_length, size=len(body)):
                self.records.clear()
                self.reply(200, body, known_length=known_length)
                with patch.object(backend, "HTTP_JSON_MAX_BYTES", 128):
                    with self.assertRaises(ValueError):
                        self.player._fetch_lrclib_synced(self.track, self.token())
                self.assertEqual([row[0] for row in self.records], ["/api/get"])

    def test_cancellation_interrupts_backoff_without_another_http_request(self):
        self.reply(503, b"temporary")
        token = self.token()
        entered = threading.Event()
        original_wait = token.cancelled.wait
        errors = []
        def wait(delay):
            entered.set()
            return original_wait(delay)
        def run():
            try:
                self.player._fetch_lrclib_synced(self.track, token)
            except Exception as exc:
                errors.append(type(exc))
        with patch.object(token.cancelled, "wait", side_effect=wait):
            worker = threading.Thread(target=run, daemon=True)
            worker.start()
            self.assertTrue(entered.wait(2))
            token.cancel()
            worker.join(0.5)
        self.assertFalse(worker.is_alive())
        self.assertEqual(errors, [backend.LyricsCancelled])
        self.assertEqual([row[0] for row in self.records], ["/api/get"])

    def test_switching_tracks_aborts_active_http_and_loads_new_without_waiting(self):
        class Client:
            def tracks_lyrics(self, *args, **kwargs):
                return None
            def track_supplement(self, *args):
                return None
        p = self.player
        p.lock = threading.RLock()
        p.api_lock = threading.Lock()
        p.client = Client()
        p.queue = [SimpleNamespace(id=ident, title=title, artists=self.track.artists)
                   for ident, title in (("old", "Hold"), ("new", "New"))]
        p.index = 0
        p.detached_track = None
        p.preferences = {"showBarLyrics": True}
        p.lyrics_generation = 0
        p.lyrics_loading = {}
        p.lyrics_cache = OrderedDict()
        p.lyrics_cache_dir = Path(self.home.name) / "lyrics"
        p.state = {"error": "", "loadingStage": ""}
        p.lyrics()
        self.assertTrue(self.held.wait(2))
        old = p.lyrics_loading["old"]
        self.tokens.append(old)
        p.index = 1
        started = time.monotonic()
        p.lyrics()
        deadline = started + 1.5
        while time.monotonic() < deadline and "new" in p.lyrics_loading:
            time.sleep(0.01)
        result = p.lyrics()
        self.assertTrue(result["synced"])
        self.assertEqual(result["trackId"], "new")
        self.assertEqual(result["lines"][0]["time"], 1.25)
        self.assertTrue(self.released.wait(0.5), "old HTTPS connection is closed, not merely ignored")
        self.assertNotIn("old", p.lyrics_cache)
        self.assertFalse((p.lyrics_cache_dir / "old.json").exists())
        self.assertEqual([row[1] for row in self.records], ["Hold", "New"])


if __name__ == "__main__":
    unittest.main()
