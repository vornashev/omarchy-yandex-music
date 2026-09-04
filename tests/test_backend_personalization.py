import threading
import time
import unittest
from collections import OrderedDict
from types import SimpleNamespace
from typing import Any
from unittest.mock import Mock

from backend import backend


def artist(id_, name):
    return SimpleNamespace(id=str(id_), name=name, genres=[], cover=None, og_image="", op_image="")


def album(id_, title):
    return SimpleNamespace(
        id=str(id_), title=title, type="album", artists=[artist(1, "Artist")],
        year=2024, original_release_year=None, release_date="2024-01-02", genre="pop",
        track_count=1, cover_uri="", og_image="",
    )


def track(id_, title=None):
    return SimpleNamespace(
        id=str(id_), title=title or f"Track {id_}", artists=[artist(1, "Artist")],
        albums=[album(10, "Album")], cover_uri="", duration_ms=120_000,
    )


def playlist(kind, title, tracks=None, owner=7):
    return SimpleNamespace(
        playlist_uuid=f"uuid-{kind}", uid=owner, kind=kind,
        owner=SimpleNamespace(uid=owner, name="Owner"), title=title,
        track_count=len(tracks or []), cover=None, og_image="", image="",
        tracks=list(tracks or []),
    )


class FakePersonalizationClient:
    def __init__(self):
        self.calls = []
        self.personal = {
            name: SimpleNamespace(ready=True, data=playlist(index + 1, title, [track(index + 1)]))
            for index, (name, title) in enumerate(backend.PERSONAL_PLAYLISTS)
        }
        self.history = SimpleNamespace(history_tabs=[])
        self.history_resolved = SimpleNamespace(items=[])
        self.liked_albums: Any = []
        self.liked_artists: Any = []
        self.liked_playlists: Any = []
        self.stations: Any = []
        self.station_tracks: Any = None

    def playlists_personal(self, playlist_id):
        self.calls.append(("personal", playlist_id))
        value = self.personal[playlist_id]
        if isinstance(value, Exception):
            raise value
        return value

    def music_history(self, full_models_count=0):
        self.calls.append(("history", full_models_count))
        return self.history

    def music_history_items(self, **kwargs):
        self.calls.append(("history_items", kwargs))
        if self.history_resolved.items:
            return self.history_resolved
        items = []
        for track_id, album_id in kwargs.get("track_ids") or []:
            item_id = SimpleNamespace(track_id=str(track_id), album_id=str(album_id),
                                      id=None, uid=None, kind=None, seeds=None)
            items.append(SimpleNamespace(type="track", data=SimpleNamespace(
                item_id=item_id, full_model=track(track_id))))
        return SimpleNamespace(items=items)

    def users_likes_albums(self):
        self.calls.append(("liked_albums",))
        return self.liked_albums

    def users_likes_artists(self):
        self.calls.append(("liked_artists",))
        return self.liked_artists

    def users_likes_playlists(self):
        self.calls.append(("liked_playlists",))
        return self.liked_playlists

    def rotor_stations_list(self):
        self.calls.append(("stations",))
        return self.stations

    def rotor_station_tracks(self, station):
        self.calls.append(("station_tracks", station))
        if isinstance(self.station_tracks, Exception):
            raise self.station_tracks
        return self.station_tracks

    def tracks(self, ids):
        self.calls.append(("tracks", list(ids)))
        return []


class PersonalizationTests(unittest.TestCase):
    def make_player(self, client):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.state = {
            "authenticated": True, "loading": False, "loadingKind": "", "loadingStage": "", "error": "",
            "artistBrowseName": "", "libraryBrowseName": "", "libraryTotal": 0,
            "libraryHasMore": False, "libraryLoadingMore": False, "libraryFromCache": False,
        }
        player.library_hub_generation = 0
        player.library_hub_revision = 0
        player.library_hub = player._empty_library_hub()
        player.library_hub_tracks = []
        player.library_hub_source = []
        player.library_hub_offset = 0
        player.library_hub_cache = OrderedDict()
        player.personal_playlist_models = {}
        player.library_generation = 0
        player.library_revision = 0
        player.library_source = []
        player.library_results = []
        player.library_result_refs = []
        player.library_offset = 0
        player.active_library_cache_key = ""
        player.collection_cache = {}
        player.artist_results = []
        player.queue = [track("old")]
        player.queue_source = []
        player.queue_generation = 0
        player.queue_revision = 0
        player.queue_collection_key = ""
        player.queue_artist_id = ""
        player.queue_artist_page = 0
        player.queue_artist_has_more = False
        player.queue_extending = False
        player.queue_advance_pending = False
        player.queue_advance_automatic = False
        player.detached_track = None
        player.radio_station = ""
        player.radio_batch_id = ""
        player.radio_track_batches = {}
        player.radio_extending = False
        player.radio_advance_pending = False
        player.playback_report = None
        player.index = 0
        player.preferences = {"playbackMode": "repeatQueue"}
        return player

    @staticmethod
    def wait_until(predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        raise AssertionError("background personalization worker did not finish")

    def test_sections_load_lazily_and_personal_playlists_are_cached(self):
        client = FakePersonalizationClient()
        player = self.make_player(client)

        player.library_section("personal")
        self.wait_until(lambda: not player.library_hub["loading"])

        self.assertEqual([call[0] for call in client.calls], ["personal"] * 4)
        self.assertEqual([row["personalId"] for row in player.library_hub["items"]],
                         [value for value, _title in backend.PERSONAL_PLAYLISTS])
        self.assertTrue(all(row["available"] for row in player.library_hub["items"]))
        self.assertEqual(len(player.personal_playlist_models), 4)
        call_count = len(client.calls)
        player.library_back()
        player.library_section("personal")
        self.assertFalse(player.library_hub["loading"])
        self.assertEqual(len(client.calls), call_count)

    def test_stale_personal_generation_is_disabled_but_not_cached(self):
        client = FakePersonalizationClient()
        client.personal["missedLikes"].ready = False
        player = self.make_player(client)

        player.library_section("personal")
        self.wait_until(lambda: not player.library_hub["loading"])

        row = next(value for value in player.library_hub["items"]
                   if value["personalId"] == "missedLikes")
        self.assertFalse(row["available"])
        self.assertFalse(row["generationReady"])
        self.assertNotIn("missedLikes", player.personal_playlist_models)

        client.personal["missedLikes"].ready = True
        player.browse_personal_playlist("missedLikes")
        self.wait_until(lambda: not player.state["loading"])
        self.assertEqual(player.state["libraryBrowseName"], "Тайник")
        self.assertIn("missedLikes", player.personal_playlist_models)

    def test_stale_personal_generation_has_specific_error_when_still_pending(self):
        client = FakePersonalizationClient()
        client.personal["missedLikes"] = SimpleNamespace(
            ready=False, data=playlist(2, "Тайник", []))
        player = self.make_player(client)

        player.library_section("personal")
        self.wait_until(lambda: not player.library_hub["loading"])
        player.browse_personal_playlist("missedLikes")
        self.wait_until(lambda: not player.state["loading"])

        self.assertIn("не сформирован Яндекс Музыкой", player.state["error"])
        self.assertEqual(player.state["libraryBrowseName"], "")

    def test_history_resolves_and_displays_fifty_items_per_page(self):
        client = FakePersonalizationClient()
        unresolved = []
        for index in range(125):
            item_id = SimpleNamespace(track_id=str(index + 1), album_id="10",
                                      id=None, uid=None, kind=None, seeds=None)
            unresolved.append(SimpleNamespace(type="track", data=SimpleNamespace(
                item_id=item_id, full_model=None)))
        client.history = SimpleNamespace(history_tabs=[SimpleNamespace(
            date="Сегодня", items=[SimpleNamespace(context=None, tracks=unresolved)])])
        player = self.make_player(client)

        player.library_section("history")
        self.wait_until(lambda: not player.library_hub["loading"])
        self.assertEqual(len(player.library_hub["items"]), 50)
        self.assertEqual(player.library_hub["total"], 125)
        self.assertTrue(player.library_hub["hasMore"])
        self.assertEqual(len(client.calls[-1][1]["track_ids"]), 50)

        player.library_section_more()
        self.wait_until(lambda: not player.library_hub["loadingMore"])
        self.assertEqual(len(player.library_hub["items"]), 100)
        self.assertEqual(len(client.calls[-1][1]["track_ids"]), 50)
        self.assertTrue(player.library_hub["hasMore"])

        player.library_section_more()
        self.wait_until(lambda: not player.library_hub["loadingMore"])
        self.assertEqual(len(player.library_hub["items"]), 125)
        self.assertEqual(len(client.calls[-1][1]["track_ids"]), 25)
        self.assertFalse(player.library_hub["hasMore"])
        self.assertEqual([row["trackIndex"] for row in player.library_hub["items"]],
                         list(range(125)))

    def test_liked_entity_sections_normalize_without_replacing_queue(self):
        client = FakePersonalizationClient()
        client.liked_albums = [SimpleNamespace(album=album(2, "Liked Album"))]
        client.liked_artists = [SimpleNamespace(artist=artist(3, "Liked Artist"))]
        client.liked_playlists = [SimpleNamespace(playlist=playlist(4, "Liked Playlist"))]
        player = self.make_player(client)
        original_queue = list(player.queue)

        expected = [("albums", "album"), ("artists", "artist"), ("playlists", "playlist")]
        for section, entity_type in expected:
            player.library_section(section)
            self.wait_until(lambda: not player.library_hub["loading"])
            self.assertEqual(player.library_hub["items"][0]["entityType"], entity_type)
            self.assertEqual(player.queue, original_queue)

    def test_history_uses_one_batch_resolver_and_explicit_track_playback(self):
        client = FakePersonalizationClient()
        item_id = SimpleNamespace(track_id="5", album_id="10", id=None, uid=None, kind=None, seeds=None)
        unresolved = SimpleNamespace(type="track", data=SimpleNamespace(item_id=item_id, full_model=None))
        resolved = SimpleNamespace(type="track", data=SimpleNamespace(item_id=item_id, full_model=track(5)))
        group = SimpleNamespace(context=None, tracks=[unresolved])
        client.history = SimpleNamespace(history_tabs=[SimpleNamespace(date="Сегодня", items=[group])])
        client.history_resolved = SimpleNamespace(items=[resolved])
        player = self.make_player(client)

        player.library_section("history")
        self.wait_until(lambda: not player.library_hub["loading"])

        self.assertEqual(len([call for call in client.calls if call[0] == "history_items"]), 1)
        self.assertEqual(player.library_hub["items"][0]["trackId"], "5")
        self.assertEqual(player.library_hub["items"][0]["historyDate"], "Сегодня")
        player._url = Mock(return_value="https://audio.invalid/temporary")
        set_queue = Mock()
        player._set_queue = set_queue
        player.play_library_hub_track(0)
        self.wait_until(lambda: set_queue.call_count == 1)
        set_queue.assert_called_once()

    def test_station_catalog_requires_explicit_play_action(self):
        client = FakePersonalizationClient()
        station = SimpleNamespace(
            id=SimpleNamespace(type="genre", tag="rock"), id_for_from="genre-rock",
            name="Рок", full_image_url="//avatars.invalid/%%", icon=None,
        )
        client.stations = [SimpleNamespace(station=station, explanation="Энергичная музыка")]
        station_tracks = SimpleNamespace(
            sequence=[SimpleNamespace(track=track(9))], batch_id="batch-1")
        client.station_tracks = station_tracks
        player = self.make_player(client)
        set_queue = Mock()
        player._set_queue = set_queue

        player.library_section("stations")
        self.wait_until(lambda: not player.library_hub["loading"])
        self.assertEqual(player.library_hub["items"][0]["stationId"], "genre:rock")
        set_queue.assert_not_called()

        player.play_station("genre:rock", "Рок")
        self.wait_until(lambda: set_queue.call_count == 1)
        set_queue.assert_called_once_with(
            [station_tracks.sequence[0].track], "Рок", "genre:rock", "batch-1")

    def test_station_failure_is_friendly_and_hides_raw_response(self):
        client = FakePersonalizationClient()
        client.station_tracks = RuntimeError('{"status": 404, "secret": "raw"}')
        player = self.make_player(client)

        player.play_station("genre:missing", "Missing")
        self.wait_until(lambda: not player.state["loading"])

        self.assertIn("не найден", player.state["error"])
        self.assertNotIn("secret", player.state["error"])

    def test_stale_section_response_cannot_replace_newer_section(self):
        client = FakePersonalizationClient()
        release = threading.Event()

        def slow_albums():
            release.wait(1)
            return [SimpleNamespace(album=album(8, "Old"))]

        client.users_likes_albums = slow_albums
        player = self.make_player(client)
        player.library_section("albums")
        player.library_section("artists")
        self.wait_until(lambda: not player.library_hub["loading"])
        release.set()
        time.sleep(0.05)

        self.assertEqual(player.library_hub["section"], "artists")
        self.assertEqual(player.library_hub["items"], [])

    def test_local_section_error_hides_raw_response(self):
        client = FakePersonalizationClient()
        failure = RuntimeError('{"status": 415, "secret": "raw"}')

        def fail():
            raise failure

        client.users_likes_albums = fail
        player = self.make_player(client)
        player.state["error"] = "player error stays"
        player.library_section("albums")
        self.wait_until(lambda: not player.library_hub["loading"])

        self.assertIn("временно недоступ", player.library_hub["error"])
        self.assertNotIn("secret", player.library_hub["error"])
        self.assertEqual(player.state["error"], "player error stays")


if __name__ == "__main__":
    unittest.main()
