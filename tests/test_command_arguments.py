"""Exercise QML var signals, process argv and the production CLI without an account."""
import json
from pathlib import Path
import shutil
import socketserver
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CommandArgumentsTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("quickshell"), "quickshell is required")
    def test_qml_signal_to_cli_preserves_arguments_and_fifo(self):
        cases = [
            ("play_catalog_track", ["entity", 0], {"source": "entity", "index": 0}),
            ("play_catalog_track", ["search", 1], {"source": "search", "index": 1}),
            ("catalog_search", ["all", "слова с пробелами, ещё"],
             {"type": "all", "query": "слова с пробелами, ещё"}),
            ("catalog_playlist", ["", "123", "7"], {"uuid": "", "owner": "123", "kind": "7"}),
            ("play_station", ["artist:42", "Станция, название"],
             {"station": "artist:42", "title": "Станция, название"}),
            ("playlist_memberships", ["entity", 0, "42", ""],
             {"source": "entity", "index": 0, "trackId": "42", "albumId": ""}),
            ("playlist_add_track", ["7", "entity", 0, "42", "10"],
             {"kind": "7", "source": "entity", "index": 0, "trackId": "42", "albumId": "10"}),
            ("playlist_create", ["entity", 0, "42", "", "Мой плейлист, 1"],
             {"source": "entity", "index": 0, "trackId": "42", "albumId": "", "title": "Мой плейлист, 1"}),
            ("playlist_delete_track", ["7", "entity", 0, "42", "10"],
             {"kind": "7", "source": "entity", "index": 0, "trackId": "42", "albumId": "10"}),
            ("playlist_recommendations", ["7", "Плейлист, ещё один"],
             {"kind": "7", "title": "Плейлист, ещё один"}),
            ("catalog_album", "одно значение, с пробелами", {"albumId": "одно значение, с пробелами"}),
            ("catalog_album", "", {"albumId": ""}),
            ("play_library_track", 0, {"index": 0}),
            ("pause", None, {}),
            ("pause", [], {}),
        ]
        entries = [{"command": command, "argument": argument} for command, argument, _ in cases]
        entries.extend([
            {"command": "pause"},  # undefined, distinct from null and an empty sequence
            {"intent": "playCatalogTrack", "argument": ["entity", 1]},
            {"command": "play_catalog_track", "argument": ["entity", -1],
             "error": "Некорректный индекс трека каталога"},
        ])
        expected_requests = [{"command": command, **payload} for command, _, payload in cases]
        expected_requests.extend([
            {"command": "pause"},
            {"command": "play_catalog_track", "source": "entity", "index": 1},
            {"command": "play_catalog_track", "source": "entity", "index": -1},
        ])
        expected_argv = []
        for command, argument, _ in cases:
            args = argument if isinstance(argument, list) else [] if argument is None else [argument]
            expected_argv.append([command, *map(str, args)])
        expected_argv.extend([["pause"], ["play_catalog_track", "entity", "1"],
                              ["play_catalog_track", "entity", "-1"]])

        requests = []

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                request = json.loads(self.rfile.readline())
                if request["command"] != "status":
                    requests.append(request)
                response = ({"error": "Некорректный индекс трека каталога"}
                            if request.get("index") == -1 else {"ok": True})
                self.wfile.write((json.dumps(response) + "\n").encode())

        with tempfile.TemporaryDirectory(prefix="ym-argv-") as directory:
            probe = Path(directory)
            home = probe / "home"
            runtime = probe / "runtime"
            runtime.mkdir(mode=0o700)
            cli_dir = home / ".local/bin"
            cli_dir.mkdir(parents=True)
            plugin_dir = home / ".config/omarchy/plugins/vornashev.yandex-music"
            plugin_dir.mkdir(parents=True)
            bootstrap = plugin_dir / "bootstrap.sh"
            bootstrap.write_text("#!/bin/sh\nexit 0\n")
            bootstrap.chmod(0o755)
            shutil.copytree(ROOT / "qml/controllers", probe / "controllers")
            shutil.copyfile(ROOT / "tests/fixtures/command_arguments.qml", probe / "shell.qml")
            shutil.copyfile(ROOT / "bin/omarchy-yandex-music", cli_dir / "production_cli.py")
            # Record exact argv, then execute the unmodified production parser.
            cli = cli_dir / "omarchy-yandex-music"
            cli.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "with open(os.environ['COMMAND_ARGV_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "os.execv(sys.executable, [sys.executable, "
                "str(Path(__file__).with_name('production_cli.py')), *sys.argv[1:]])\n"
            )
            cli.chmod(0o755)
            argv_log = probe / "argv.jsonl"
            env = {
                "HOME": str(home), "PATH": "/usr/bin:/bin",
                "XDG_RUNTIME_DIR": str(runtime), "XDG_CONFIG_HOME": str(home / ".config"),
                "XDG_CACHE_HOME": str(home / ".cache"), "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software", "QSG_RENDER_LOOP": "basic",
                "LANG": "C.UTF-8",
                "COMMAND_CASES": json.dumps(entries), "COMMAND_ARGV_LOG": str(argv_log),
            }
            with socketserver.UnixStreamServer(str(runtime / "omarchy-yandex-music.sock"), Handler) as server:
                worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.05})
                worker.start()
                try:
                    result = subprocess.run(
                        [shutil.which("quickshell"), "-p", str(probe / "shell.qml"), "--no-color"],
                        env=env, capture_output=True, text=True, timeout=30,
                    )
                except subprocess.TimeoutExpired as exc:
                    self.fail(f"QML command fixture timed out: {exc.stdout!r} {exc.stderr!r}")
                finally:
                    server.shutdown()
                    worker.join(timeout=5)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn(f"COMMAND_ARGUMENTS_OK {len(entries)}", output)
            self.assertNotRegex(output, r"ReferenceError|TypeError|SyntaxError|COMMAND_ARGUMENTS_FAILED")
            argv = [json.loads(line) for line in argv_log.read_text().splitlines()]
            self.assertEqual([args for args in argv if args[0] != "status"], expected_argv)
            self.assertEqual(requests, expected_requests)
