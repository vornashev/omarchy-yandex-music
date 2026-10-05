import threading
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from backend import backend


class FakeClient:
    behavior = "expire"

    def __init__(self, *args, **kwargs):
        pass

    def device_auth(self, on_code, should_cancel=None, **kwargs):
        on_code(SimpleNamespace(verification_url="https://example.invalid/device",
                                user_code="GQ7I-VNBJ", expires_in=300))
        if FakeClient.behavior == "cancel":
            while not should_cancel():
                time.sleep(0.01)
            raise RuntimeError("cancelled by caller")
        raise RuntimeError("timed out after 300s waiting for user confirmation")


def make_player():
    player = backend.Player.__new__(backend.Player)
    player.lock = threading.RLock()
    player.http = None
    player.errors = []
    player.state = {"authPending": False, "authUrl": "", "authCode": "", "error": "",
                    "authExpiresAt": 0.0, "authExpired": False}
    player._set_error = lambda message: player.errors.append(message)
    return player


def wait_until(predicate, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


class DeviceAuthStateTests(unittest.TestCase):
    def test_cancel_restart_rejects_late_code_token_and_error(self):
        for outcome in ("token", "error", "connect"):
            with self.subTest(outcome=outcome), TemporaryDirectory() as directory:
                player = make_player()
                player.state.update(authenticated=False, connecting=False)
                player.client = None
                player.session_generation = 0
                player._load_playlists = lambda: None
                player._load_liked_ids = lambda: None
                player._load_disliked_ids = lambda: None
                workers = []
                token_file = Path(directory) / "token.json"

                def restart():
                    player.cancel_authentication()
                    player.authenticate()

                class LateClient:
                    me = None

                    def __init__(self, *args, **kwargs):
                        pass

                    def device_auth(self, on_code, should_cancel):
                        if outcome != "connect":
                            restart()
                        on_code(SimpleNamespace(verification_url="https://example.invalid/old",
                                                user_code="OLD-CODE", expires_in=300))
                        if outcome == "error":
                            raise RuntimeError("timed out after cancelled poll")
                        return SimpleNamespace(access_token="synthetic-old-token",
                                               refresh_token=None, expires_in=300)

                    def init(self):
                        restart()
                        return self

                with patch.object(backend, "Client", LateClient), \
                        patch.object(backend, "SessionRequest", lambda http: None), \
                        patch.object(backend, "TOKEN_FILE", token_file), \
                        patch.object(backend.threading, "Thread",
                                     lambda target, **kwargs: SimpleNamespace(
                                         start=lambda: workers.append(target))):
                    player.authenticate()
                    workers[0]()
                self.assertFalse(token_file.exists(), "cancelled OAuth must not persist its token")
                self.assertIsNone(player.client)
                self.assertFalse(player.state["authenticated"])
                self.assertTrue(player.state["authPending"], "late worker must not clear the new attempt")
                self.assertEqual(player.state["authCode"], "")
                self.assertFalse(player.state["authExpired"])
                self.assertEqual(player.errors, [])

    def test_expired_code_is_reported_without_a_raw_error(self):
        player = make_player()
        FakeClient.behavior = "expire"
        with patch.object(backend, "Client", FakeClient), \
                patch.object(backend, "SessionRequest", lambda http: None):
            player.authenticate()
            self.assertTrue(wait_until(lambda: player.state["authExpired"]))
        self.assertFalse(player.state["authPending"])
        self.assertEqual(player.state["authCode"], "")
        self.assertEqual(player.errors, [])

    def test_code_and_expiry_are_published_while_waiting(self):
        player = make_player()
        FakeClient.behavior = "cancel"
        with patch.object(backend, "Client", FakeClient), \
                patch.object(backend, "SessionRequest", lambda http: None):
            player.authenticate()
            self.assertTrue(wait_until(lambda: player.state["authCode"] == "GQ7I-VNBJ"))
            self.assertGreater(player.state["authExpiresAt"], time.time() + 250)
            self.assertTrue(player.state["authPending"])
            player.cancel_authentication()
            self.assertFalse(player.state["authPending"])
            self.assertEqual(player.state["authCode"], "")
            time.sleep(0.1)
        self.assertFalse(player.state["authExpired"])
        self.assertEqual(player.errors, [])


if __name__ == "__main__":
    unittest.main()
