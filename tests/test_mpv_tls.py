"""Exercise production mpv launch against local HTTPS audio, without account data."""
import functools
import http.server
import json
import os
import shutil
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

from backend import backend


@unittest.skipUnless(shutil.which("mpv") and shutil.which("openssl"), "mpv and openssl required")
class MpvTlsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.addClassCleanup(cls.temp.cleanup)
        def openssl(*args):
            subprocess.run(["openssl", *args], cwd=cls.root, check=True,
                           capture_output=True, timeout=15)
        for name in ("ca", "untrusted"):
            openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", f"/CN={name}", "-keyout", f"{name}.key", "-out", f"{name}.crt",
                    "-addext", "basicConstraints=critical,CA:TRUE")
        for name, ca, hostname in (("valid", "ca", "localhost"),
                                   ("wrong-host", "ca", "wrong.example"),
                                   ("self-signed", "untrusted", "localhost")):
            openssl("req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", f"/CN={hostname}",
                    "-keyout", f"{name}.key", "-out", f"{name}.csr")
            (cls.root / f"{name}.ext").write_text(
                f"subjectAltName=DNS:{hostname}\nextendedKeyUsage=serverAuth\n")
            openssl("x509", "-req", "-in", f"{name}.csr", "-CA", f"{ca}.crt",
                    "-CAkey", f"{ca}.key", "-CAcreateserial", "-days", "1",
                    "-extfile", f"{name}.ext", "-out", f"{name}.crt")
        with wave.open(str(cls.root / "audio.wav"), "wb") as audio:
            audio.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
            audio.writeframes(b"\x00\x10" * 8000)

    def playback(self, certificate, expected):
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass
        handler = functools.partial(Handler, directory=str(self.root))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.root / f"{certificate}.crt", self.root / f"{certificate}.key")
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 5)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as home:
            ipc = Path(home) / "mpv.sock"
            player = backend.Player.__new__(backend.Player)
            player.mpv = None
            player.volume = 50
            player.control_lock = threading.RLock()
            # Observe the real core directly; no backend event workers or account state needed.
            player._ensure_mpv_events = lambda: None
            popen = subprocess.Popen
            def launch(args, **kwargs):
                # Only the output device and fixture trust root differ from production.
                return popen([*args, "--ao=null", f"--tls-ca-file={self.root / 'ca.crt'}"], **kwargs)
            config = Path(home) / "mpv"
            config.mkdir()
            (config / "mpv.conf").write_text("tls-verify=no\nstream-lavf-o=tls_verify=0\n")
            with patch.object(backend, "MPV_SOCKET", ipc), patch.object(backend.subprocess, "Popen", launch), \
                    patch.dict(os.environ, {"HOME": home, "XDG_CONFIG_HOME": home}):
                try:
                    player._ensure_mpv()
                    with socket.socket(socket.AF_UNIX) as events:
                        events.settimeout(8)
                        events.connect(str(ipc))
                        events.sendall((json.dumps({"command": ["loadfile",
                            f"https://localhost:{server.server_port}/audio.wav", "replace"]}) + "\n").encode())
                        with events.makefile("rb") as stream:
                            while True:
                                event = json.loads(stream.readline())
                                if event.get("event") == "file-loaded":
                                    result = "loaded"
                                    break
                                if event.get("event") == "end-file":
                                    result = event.get("reason")
                                    break
                        self.assertEqual(result, expected)
                finally:
                    if player.mpv:
                        player.mpv.terminate()
                        player.mpv.wait(timeout=5)

    def test_trusted_https_audio_loads_despite_insecure_user_config(self):
        self.playback("valid", "loaded")

    def test_untrusted_certificate_rejected(self):
        self.playback("self-signed", "error")

    def test_trusted_certificate_with_wrong_hostname_rejected(self):
        self.playback("wrong-host", "error")
