import json
import socket
import threading
import unittest
from unittest.mock import Mock, patch

from backend import backend


class FakeConnection:
    def __init__(self, chunks, *, broken_reply=False):
        self.chunks = list(chunks)
        self.broken_reply = broken_reply
        self.sent = b""
        self.timeouts = []
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.closed = True

    def settimeout(self, timeout):
        self.timeouts.append(timeout)

    def recv(self, size):
        value = self.chunks.pop(0)
        if isinstance(value, Exception):
            raise value
        if len(value) > size:
            self.chunks.insert(0, value[size:])
            return value[:size]
        return value

    def sendall(self, data):
        if self.broken_reply:
            raise BrokenPipeError("peer closed")
        self.sent += data

    def response(self):
        return json.loads(self.sent.splitlines()[0])


class FakePlayer:
    def __init__(self, response=None):
        self.requests = []
        self.response = response

    def handle(self, request):
        self.requests.append(request)
        return self.response or {"ok": True, "value": request["command"]}


class IpcConnectionTests(unittest.TestCase):
    @staticmethod
    def make_playback_player():
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.client = object()
        player.catalog = player._empty_catalog()
        player.catalog_search_models = {"tracks": [object()]}
        player.catalog_entity_tracks = [object()]
        player.catalog_generation = 0
        player.library_results = [object()]
        player.library_source = list(player.library_results)
        player.library_offset = 1
        player.library_origin = ("likes", "")
        player.active_library_cache_key = "likes"
        player.state = {"libraryBrowseName": "Test", "error": ""}
        player._set_queue = Mock()
        player._url = Mock()
        return player

    def test_invalid_playback_indices_return_errors_without_changing_playback(self):
        player = self.make_playback_player()
        requests = [
            {"command": command, **extra, **index}
            for command, extra in (("play_catalog_track", {"source": "entity"}),
                                   ("play_catalog_track", {"source": "search"}),
                                   ("play_library_track", {}))
            for index in ({}, {"index": -1}, {"index": 1}, {"index": "invalid"})
        ]
        for request in requests:
            with self.subTest(request=request):
                conn = FakeConnection([(json.dumps(request) + "\n").encode()])
                backend._serve_connection(conn, player.handle)
                self.assertIn("индекс", conn.response().get("error", "").lower())
                self.assertNotIn("ok", conn.response())
        player._set_queue.assert_not_called()
        player._url.assert_not_called()
        self.assertEqual(player.state, {"libraryBrowseName": "Test", "error": ""})

    def test_invalid_catalog_source_returns_an_error(self):
        player = self.make_playback_player()
        for source in (None, "", "entity,0", "unknown"):
            with self.subTest(source=source):
                request = {"command": "play_catalog_track", "index": 0}
                if source is not None:
                    request["source"] = source
                conn = FakeConnection([(json.dumps(request) + "\n").encode()])
                backend._serve_connection(conn, player.handle)
                self.assertIn("источник", conn.response().get("error", "").lower())
                self.assertNotIn("ok", conn.response())
        player._set_queue.assert_not_called()
        player._url.assert_not_called()

    def test_transport_accepts_a_plain_command_handler(self):
        conn = FakeConnection([b'{"command":"status"}\n'])

        def handle(request):
            return {"ok": request == {"command": "status"}}

        backend._serve_connection(conn, handle)
        self.assertEqual(conn.response(), {"ok": True})

    def test_incomplete_request_times_out_and_next_request_works(self):
        player = FakePlayer()
        stalled = FakeConnection([b'{"command":', socket.timeout("deadline")])
        with patch.object(backend, "IPC_READ_TIMEOUT", 0.1):
            backend._serve_connection(stalled, player.handle)
        self.assertIn("время ожидания", stalled.response()["error"].lower())
        self.assertEqual(player.requests, [])
        self.assertTrue(stalled.closed)
        self.assertLessEqual(stalled.timeouts[0], 0.1)

        following = FakeConnection([b'{"command":"status"}\n'])
        backend._serve_connection(following, player.handle)
        self.assertEqual(following.response(), {"ok": True, "value": "status"})
        self.assertEqual(player.requests, [{"command": "status"}])

    def test_trickle_request_has_absolute_deadline(self):
        conn = FakeConnection([b"a", b"b", b"c"])
        with patch.object(backend, "IPC_READ_TIMEOUT", 0.1), patch.object(
            backend.time, "monotonic", side_effect=[0.0, 0.0, 0.06, 0.11]
        ):
            backend._serve_connection(conn, FakePlayer().handle)
        self.assertIn("время ожидания", conn.response()["error"].lower())
        self.assertTrue(conn.closed)

    def test_oversized_request_is_rejected_without_dispatch(self):
        player = FakePlayer()
        conn = FakeConnection([b'{"command":"' + b"x" * 70 + b'"}\n'])
        with patch.object(backend, "IPC_REQUEST_MAX_BYTES", 64):
            backend._serve_connection(conn, player.handle)
        self.assertIn("слишком длин", conn.response()["error"].lower())
        self.assertEqual(player.requests, [])

    def test_fragmented_request_and_large_reply_succeed(self):
        conn = FakeConnection([b'{"command":', b'"details"}\n'])
        player = FakePlayer({"data": "x" * 8192})
        backend._serve_connection(conn, player.handle)
        self.assertEqual(len(conn.response()["data"]), 8192)
        self.assertEqual(player.requests, [{"command": "details"}])
        self.assertTrue(conn.closed)

    def test_broken_reply_socket_does_not_raise(self):
        conn = FakeConnection([b'{"command":"status"}\n'], broken_reply=True)
        backend._serve_connection(conn, FakePlayer().handle)
        self.assertTrue(conn.closed)
