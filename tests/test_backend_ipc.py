import json
import socket
import unittest
from unittest.mock import patch

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
