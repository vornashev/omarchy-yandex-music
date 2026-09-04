import threading
import time
import unittest
from collections import OrderedDict
from types import SimpleNamespace

from backend import backend


class FakeLyrics:
    def __init__(self, content, writers=None):
        self.content = content
        self.writers = writers or []
        self.fetches = 0

    def fetch_lyrics(self):
        self.fetches += 1
        return self.content


class FakeLyricsClient:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def tracks_lyrics(self, track_id, format_="TEXT"):
        self.calls.append((str(track_id), format_))
        response = self.responses[format_]
        if isinstance(response, Exception):
            raise response
        return response


class NotFoundError(RuntimeError):
    pass


class LyricsTests(unittest.TestCase):
    def make_player(self, client):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.queue = [SimpleNamespace(id="42")]
        player.index = 0
        player.detached_track = None
        player.lyrics_cache = OrderedDict()
        player.lyrics_loading = set()
        player.lyrics_generation = 0
        player.state = {"loadingStage": "", "error": "existing player state"}
        return player

    @staticmethod
    def wait_for_lyrics(player):
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            response = player.lyrics()
            if not response["loading"]:
                return response
            time.sleep(0.01)
        raise AssertionError("lyrics worker did not finish")

    def test_lrc_parser_supports_offsets_multiple_timestamps_and_enhanced_tags(self):
        content = """[ar:Artist]\n[offset:+250]\n[00:01.50]First line\n[00:03:25][00:04.000]Second <00:03.50>line\n"""

        self.assertEqual(
            backend.Player._parse_lrc(content),
            [
                {"time": 1.75, "text": "First line"},
                {"time": 3.5, "text": "Second line"},
                {"time": 4.25, "text": "Second line"},
            ],
        )

    def test_synced_lyrics_load_on_demand_and_are_reused_from_memory(self):
        lrc = FakeLyrics("[00:01.00]First\n[00:05.50]Second", ["Writer"])
        client = FakeLyricsClient({"LRC": lrc, "TEXT": FakeLyrics("unused")})
        player = self.make_player(client)

        self.assertTrue(player.lyrics()["loading"])
        response = self.wait_for_lyrics(player)
        cached = player.lyrics()

        self.assertTrue(response["available"])
        self.assertTrue(response["synced"])
        self.assertEqual(response["format"], "LRC")
        self.assertEqual(response["writers"], ["Writer"])
        self.assertEqual(response["lines"][1], {"time": 5.5, "text": "Second"})
        self.assertEqual(cached, response)
        self.assertEqual(client.calls, [("42", "LRC")])
        self.assertEqual(lrc.fetches, 1)

    def test_plain_text_is_used_when_lrc_has_no_timestamps(self):
        client = FakeLyricsClient(
            {"LRC": FakeLyrics("First without timing"),
             "TEXT": FakeLyrics("First\n\nSecond", ["Writer"])}
        )
        player = self.make_player(client)

        player.lyrics()
        response = self.wait_for_lyrics(player)

        self.assertTrue(response["available"])
        self.assertFalse(response["synced"])
        self.assertEqual(response["format"], "TEXT")
        self.assertEqual(
            response["lines"],
            [
                {"time": -1, "text": "First"},
                {"time": -1, "text": ""},
                {"time": -1, "text": "Second"},
            ],
        )
        self.assertEqual(client.calls, [("42", "LRC"), ("42", "TEXT")])

    def test_missing_lyrics_do_not_change_the_player_error(self):
        client = FakeLyricsClient(
            {"LRC": NotFoundError("404 lyrics not found"),
             "TEXT": NotFoundError("404 lyrics not found")}
        )
        player = self.make_player(client)

        player.lyrics()
        response = self.wait_for_lyrics(player)

        self.assertFalse(response["available"])
        self.assertEqual(response["error"], "")
        self.assertEqual(player.state["error"], "existing player state")

    def test_lyrics_cache_keeps_only_recent_entries(self):
        player = self.make_player(FakeLyricsClient({}))
        entry = {"available": False, "lines": []}

        for index in range(backend.LYRICS_CACHE_MAX_ENTRIES + 2):
            player._store_lyrics_locked(str(index), entry)

        self.assertEqual(len(player.lyrics_cache), backend.LYRICS_CACHE_MAX_ENTRIES)
        self.assertNotIn("0", player.lyrics_cache)
        self.assertNotIn("1", player.lyrics_cache)


if __name__ == "__main__":
    unittest.main()
