import threading
import time
import unittest
from collections import OrderedDict
from types import SimpleNamespace

from backend import backend


class FakeTrackInfoClient:
    def __init__(self, full_info=None, credits=None):
        self.full_info = full_info
        self.credits = credits
        self.calls = []

    @staticmethod
    def resolve(value):
        if isinstance(value, Exception):
            raise value
        return value

    def tracks_full_info(self, track_id):
        self.calls.append(("full_info", str(track_id)))
        return self.resolve(self.full_info)

    def tracks_credits(self, track_id):
        self.calls.append(("credits", str(track_id)))
        return self.resolve(self.credits)


class TrackInfoTests(unittest.TestCase):
    def make_player(self, client, track=None):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.queue = [track or SimpleNamespace(id="42")]
        player.index = 0
        player.detached_track = None
        player.track_info_cache = OrderedDict()
        player.track_info_loading = set()
        player.track_info_generation = 0
        player.state = {"loadingStage": "", "error": "existing player state"}
        return player

    @staticmethod
    def wait_for_info(player):
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            response = player.track_info()
            if not response["loading"]:
                return response
            time.sleep(0.01)
        raise AssertionError("track info worker did not finish")

    def test_track_info_normalizes_album_metadata_and_credits(self):
        album = SimpleNamespace(
            id=7,
            title="Album",
            year=2024,
            original_release_year=None,
            release_date="2024-05-06T00:00:00+00:00",
            genre="rock",
            labels=[SimpleNamespace(name="Label"), "Second Label"],
            track_position=SimpleNamespace(index=3, volume=2),
            description="Album description",
            short_description="",
        )
        track = SimpleNamespace(
            id="42",
            title="Track",
            artists=[SimpleNamespace(id=1, name="Artist")],
            albums=[album],
            major=SimpleNamespace(name="Major"),
            duration_ms=185_000,
            version="Live",
            explicit=True,
            content_warning="explicit",
            short_description="",
        )
        full_info = SimpleNamespace(track=track, aliases=["Alias"])
        credits = SimpleNamespace(
            credits=[
                SimpleNamespace(title="Автор музыки", value="Composer"),
                SimpleNamespace(title="Лейбл", value="Label"),
            ]
        )
        client = FakeTrackInfoClient(full_info, credits)
        player = self.make_player(client, track)

        self.assertTrue(player.track_info()["loading"])
        response = self.wait_for_info(player)
        cached = player.track_info()

        self.assertTrue(response["available"])
        self.assertEqual(response["artists"], [{"id": "1", "name": "Artist"}])
        self.assertEqual(response["album"], "Album")
        self.assertEqual(response["albumId"], "7")
        self.assertEqual(response["year"], "2024")
        self.assertEqual(response["releaseDate"], "2024-05-06")
        self.assertEqual(response["labels"], ["Label", "Second Label", "Major"])
        self.assertEqual(response["trackNumber"], 3)
        self.assertEqual(response["discNumber"], 2)
        self.assertEqual(response["duration"], 185)
        self.assertEqual(response["version"], "Live")
        self.assertTrue(response["explicit"])
        self.assertEqual(response["aliases"], ["Alias"])
        self.assertEqual(response["description"], "Album description")
        self.assertEqual(response["credits"][0]["value"], "Composer")
        self.assertEqual(cached, response)
        self.assertEqual(client.calls, [("full_info", "42"), ("credits", "42")])

    def test_partial_api_errors_stay_out_of_global_player_error(self):
        track = SimpleNamespace(
            id="42", title="Track", artists=[], albums=[], duration_ms=100_000
        )
        client = FakeTrackInfoClient(RuntimeError("full info failed"), RuntimeError("credits failed"))
        player = self.make_player(client, track)

        player.track_info()
        response = self.wait_for_info(player)

        self.assertTrue(response["available"])
        self.assertIn("Часть сведений недоступна", response["error"])
        self.assertEqual(player.state["error"], "existing player state")

    def test_track_info_cache_keeps_only_recent_entries(self):
        player = self.make_player(FakeTrackInfoClient())
        entry = {"available": False}

        for index in range(backend.TRACK_INFO_CACHE_MAX_ENTRIES + 2):
            player._store_track_info_locked(str(index), entry)

        self.assertEqual(len(player.track_info_cache), backend.TRACK_INFO_CACHE_MAX_ENTRIES)
        self.assertNotIn("0", player.track_info_cache)
        self.assertNotIn("1", player.track_info_cache)


if __name__ == "__main__":
    unittest.main()
