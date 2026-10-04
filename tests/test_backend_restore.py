import tempfile
import threading
import unittest
from pathlib import Path
from typing import Any, cast
from unittest.mock import patch

import requests

from backend import backend


def restoring_player(connect):
    player = cast(Any, backend.Player.__new__(backend.Player))
    player.lock = threading.RLock()
    player.restore_lock = threading.Lock()
    player.client = None
    player.state = {"authenticated": False, "authPending": False, "connecting": False, "error": ""}
    player._load_token = lambda: {"access_token": "token"}
    player._connect = connect
    player._restore_queue = lambda: None
    errors = []
    player._set_error = errors.append
    return player, errors


class RestoreRetryTests(unittest.TestCase):
    def setUp(self):
        self.delays = patch.object(backend, "RESTORE_RETRY_DELAYS", (0, 0, 0))
        self.delays.start()
        self.addCleanup(self.delays.stop)

    def test_transient_network_error_is_retried_until_connected(self):
        calls = []

        def connect(token):
            calls.append(token)
            if len(calls) < 3:
                raise requests.ConnectionError("Temporary failure in name resolution")

        player, errors = restoring_player(connect)
        player._restore_session_with_retry()
        self.assertEqual(len(calls), 3)
        self.assertEqual(errors, [])

    def test_persistent_offline_state_reports_a_retry_hint(self):
        calls = []

        def connect(token):
            calls.append(token)
            raise requests.ConnectionError("Network is unreachable")

        player, errors = restoring_player(connect)
        player._restore_session_with_retry()
        self.assertEqual(len(calls), len(backend.RESTORE_RETRY_DELAYS) + 1)
        self.assertEqual(errors, [backend.RESTORE_OFFLINE_MESSAGE])

    def test_other_errors_are_reported_without_retrying(self):
        calls = []

        def connect(token):
            calls.append(token)
            raise RuntimeError("Unauthorized")

        player, errors = restoring_player(connect)
        player._restore_session_with_retry()
        self.assertEqual(len(calls), 1)
        self.assertIn("Unauthorized", errors[0])

    def test_reconnect_is_ignored_while_signed_in(self):
        player, _ = restoring_player(lambda token: None)
        player.client = object()
        player.state["authenticated"] = True
        with patch.object(backend.threading, "Thread") as thread:
            player.reconnect()
        thread.assert_not_called()

    def test_reconnect_restarts_restore_for_a_saved_session(self):
        player, _ = restoring_player(lambda token: None)
        with tempfile.TemporaryDirectory() as temporary:
            token = Path(temporary) / "token.json"
            token.write_text("{}")
            with patch.object(backend, "TOKEN_FILE", token), patch.object(backend.threading, "Thread") as thread:
                player.reconnect()
        thread.assert_called_once()
        self.assertTrue(player.state["connecting"])


if __name__ == "__main__":
    unittest.main()
