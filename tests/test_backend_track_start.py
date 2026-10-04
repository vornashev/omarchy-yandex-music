import queue
import threading
import unittest
from types import SimpleNamespace
from typing import Any, cast

from backend import backend


class Info:
    def __init__(self, name, codec, bitrate, calls):
        self.name = name
        self.codec = codec
        self.bitrate_in_kbps = bitrate
        self.direct_link = None
        self.calls = calls

    def get_direct_link(self):
        self.calls.append(self.name)
        self.direct_link = f"fake://{self.name}"
        return self.direct_link


class Track:
    def __init__(self, infos, requested):
        self.infos = infos
        self.requested = requested

    def get_download_info(self, get_direct_links=False):
        self.requested.append(get_direct_links)
        if get_direct_links:
            for info in self.infos:
                info.get_direct_link()
        return self.infos


class TrackStartTests(unittest.TestCase):
    def player(self, quality="best"):
        player = cast(Any, backend.Player.__new__(backend.Player))
        player.preferences = {"audioQuality": quality}
        player._api_call = lambda function, **kwargs: function()
        return player

    def test_only_the_played_variant_resolves_a_direct_link(self):
        for quality, variant, expected in (("best", 0, "mp3-320"), ("economy", 0, "mp3-128"),
                                           ("best", 1, "aac-192")):
            with self.subTest(quality=quality, variant=variant):
                calls, requested = [], []
                infos = [Info("mp3-128", "mp3", 128, calls), Info("aac-192", "aac", 192, calls),
                         Info("mp3-320", "mp3", 320, calls)]
                url = self.player(quality)._url(Track(infos, requested), variant=variant)
                self.assertEqual(url, f"fake://{expected}")
                self.assertEqual(requested, [False])
                self.assertEqual(calls, [expected])

    def test_library_requests_reuse_the_shared_session(self):
        calls = []

        class Session:
            def request(self, *args, **kwargs):
                calls.append(args)
                return SimpleNamespace(status_code=200, content=b"{}")

        request = backend.SessionRequest(cast(Any, Session()))
        self.assertEqual(request._request_wrapper("GET", "https://api/x", timeout=5), b"{}")
        self.assertEqual(calls, [("GET", "https://api/x")])

    def test_analytics_wait_until_the_track_has_started(self):
        player = self.player()
        player.lock = threading.RLock()
        player.telemetry_queue = queue.Queue()
        player.telemetry_hold_until = 0.0
        player.playback_loads = 1
        order = []
        player._enqueue_telemetry(lambda: order.append("telemetry"))
        threading.Thread(target=player._telemetry_worker, daemon=True).start()
        threading.Event().wait(.3)
        order.append("track started")
        with player.lock:
            player.playback_loads = 0
        player.telemetry_queue.join()
        self.assertEqual(order, ["track started", "telemetry"])


if __name__ == "__main__":
    unittest.main()
