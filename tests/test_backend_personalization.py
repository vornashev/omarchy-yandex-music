import threading
import json
import tempfile
import time
import unittest
from collections import OrderedDict
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import Mock, patch

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

    def test_collection_reactivation_keeps_pages_and_does_not_touch_playback(self):
        client = FakePersonalizationClient()
        client.personal["daily"].data.tracks = [track(i) for i in range(123)]
        player = self.make_player(client)
        player.state.update(loading=True, loadingKind="track", loadingStage="audioStream",
                            queueName="Старая очередь", queueSourceKind="album", queueSourceArg="99")
        original_queue = list(player.queue)
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=target)):
            player.browse_personal_playlist("daily")
            self.assertEqual(len(player.library_results), 50)
            self.assertEqual(player.state["libraryDuration"], -1)
            player.load_more_library()
            player.browse_personal_playlist("missedLikes")
            player.browse_personal_playlist("daily")
        self.assertEqual([row.id for row in player.library_results], [str(i) for i in range(100)])
        self.assertEqual(player.state["libraryBrowseKind"], "browse_personal")
        self.assertEqual(player.state["libraryBrowseArg"], "daily")
        self.assertTrue(player.state["libraryFromCache"])
        self.assertEqual(player.queue, original_queue)
        self.assertEqual(player.state["queueSourceArg"], "99")
        self.assertEqual(player.state["loadingKind"], "track")
        self.assertEqual(player.state["loadingStage"], "audioStream")

    def test_late_collection_reply_cannot_overwrite_active_identity(self):
        player = self.make_player(FakePersonalizationClient())
        with patch.object(backend.threading, "Thread") as worker:
            player.browse_personal_playlist("daily")
            old_reply = worker.call_args.kwargs["target"]
            player.browse_personal_playlist("missedLikes")
            worker.call_args.kwargs["target"]()
            old_reply()
        self.assertEqual(player.state["libraryBrowseArg"], "missedLikes")
        self.assertEqual(player.state["libraryBrowseName"], "Тайник")
        self.assertEqual([row.id for row in player.library_results], ["2"])

    def test_shuffle_uses_full_light_index_and_continues_every_page(self):
        client = FakePersonalizationClient()
        client.personal["daily"].data.tracks = [track(i) for i in range(123)]
        player = self.make_player(client)
        player.set_preference = lambda key, value: player.preferences.update({key: value})
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=target)), \
                patch.object(backend.random, "shuffle", side_effect=lambda rows: rows.reverse()), \
                patch.object(player, "_save_state"), patch.object(player, "_play_current"), \
                patch.object(player, "_schedule_preload"):
            player.browse_personal_playlist("daily")
            player.play_library_collection("shuffle")
            self.assertEqual([row.id for row in player.queue], [str(i) for i in range(122, 72, -1)])
            self.assertEqual(len(player.queue_source), 73)
            self.assertEqual(player._next_target_locked(True), 1)
            player.index = 49
            self.assertEqual(player._next_target_locked(True), "collection")
            player._extend_collection(advance=True)
            self.assertEqual(player.index, 50)
            player.index = 99
            player._extend_collection(advance=True)
        self.assertEqual([row.id for row in player.queue], [str(i) for i in range(122, -1, -1)])
        self.assertEqual(player.queue_source, [])
        self.assertEqual(player.state["queueSourceKind"], "browse_personal")
        self.assertEqual(player.state["queueSourceArg"], "daily")
        self.assertEqual(len(player.library_results), 50)
        self.assertEqual(player.state["libraryBrowseArg"], "daily")

    def test_queue_source_and_lazy_tail_survive_restore_without_private_files(self):
        player = self.make_player(FakePersonalizationClient())
        player.client.tracks = lambda ids: [track(value) for value in ids]
        player.preferences.update(restoreVolume=True, restoreQueue=True,
                                  restorePosition=True, autoResume=False)
        player.save_lock = threading.Lock()
        player.last_saved_at = 0
        player.volume = 60; player.muted = False
        player.state.update(position=17, playing=False, queueName="Подборка")
        player.queue_source = [SimpleNamespace(id="tail", album_id="10")]
        player.queue_collection_key = "personal:daily"
        player.queue_collection_shuffled = True
        player.state.update(queueSourceKind="browse_personal", queueSourceArg="daily",
                            queueSourceName="Подборка")
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(backend, "STATE_FILE", Path(directory) / "state.json"), \
                patch.object(player, "_play_current"):
            player._save_state(True)
            saved = json.loads(backend.STATE_FILE.read_text())
            self.assertEqual(saved["queueRemaining"], [["tail", "10"]])
            player.state.update(queueSourceKind="album", queueSourceArg="other")
            player.queue_source = []
            player._restore_queue()
        self.assertEqual(player.state["queueSourceKind"], "browse_personal")
        self.assertEqual(player.state["queueSourceArg"], "daily")
        self.assertEqual(player.state["queueSourceName"], "Подборка")
        self.assertEqual(player.queue_source[0].id, "tail")
        self.assertTrue(player.queue_collection_shuffled)

    def test_cached_owned_start_and_source_transitions_are_explicit(self):
        player = self.make_player(FakePersonalizationClient())
        player.library_source = [track(1), track(2)]
        player.library_results = list(player.library_source)
        player.library_offset = 2
        player.active_library_cache_key = "playlist:7"
        player.state.update(libraryBrowseName="Свой", libraryPlaylistKind="7", libraryEditable=True)
        player._store_collection_cache_locked()
        with player.lock:
            player._reset_library_locked()
        player.play_playlist("7")
        with patch.object(player, "_save_state"), patch.object(player, "_play_current"), \
                patch.object(player, "_report_radio_started"):
            player.play_library_track(1)
            self.assertEqual(player.state["queueSourceKind"], "playlist")
            self.assertEqual(player.state["queueSourceArg"], "7")
            self.assertEqual(player.index, 1)
            player._set_queue([track(3)], "Волна", station="user:onyourwave")
            self.assertEqual(player.state["queueSourceKind"], "wave")
            self.assertEqual(player.state["queueSourceArg"], "")
            player._set_queue([track(4)], "Альбом", source_kind="album", source_arg="42")
        self.assertEqual(player.state["queueSourceKind"], "album")
        self.assertEqual(player.state["queueSourceArg"], "42")

    def test_search_queue_browse_preserves_new_search_and_original_provenance(self):
        player = self.make_player(FakePersonalizationClient())
        player.catalog = player._empty_catalog()
        player.catalog["search"].update(query="Новый поиск", fieldText="Новый поиск")
        player.catalog_search_models = {"tracks": [track("new")]}
        player.queue = [track(i) for i in range(75)]
        player.queue_source = [track(i) for i in range(75, 123)]
        player.state.update(queueName="Поиск: исходный", queueSourceName="Поиск: исходный",
                            queueSourceKind="search", queueSourceArg="исходный")
        original_queue = list(player.queue)
        original_tail = list(player.queue_source)
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=target)):
            player.handle({"command": "browse_queue_source"})
            self.assertEqual(player.state["libraryBrowseKind"], "browse_queue_source")
            self.assertEqual(player.state["libraryBrowseArg"], "")
            self.assertEqual(player.state["libraryBrowseName"], "Поиск: исходный")
            self.assertEqual([row.id for row in player.library_results], [str(i) for i in range(50)])
            player.load_more_library()
            player.browse_personal_playlist("daily")
            player.browse_queue_source()
        self.assertEqual([row.id for row in player.library_results], [str(i) for i in range(100)])
        self.assertEqual(player.queue, original_queue)
        self.assertEqual(player.queue_source, original_tail)
        self.assertEqual(player.catalog["search"]["query"], "Новый поиск")
        self.assertEqual(player.catalog_search_models["tracks"][0].id, "new")
        with patch.object(player, "_save_state"), patch.object(player, "_play_current"):
            player.play_library_track(42)
        self.assertEqual(player.state["queueSourceKind"], "search")
        self.assertEqual(player.state["queueSourceArg"], "исходный")
        self.assertEqual(player.state["queueSourceName"], "Поиск: исходный")
        self.assertEqual(player.index, 42)
        self.assertEqual(len(player.queue_source), 23)

    def test_browse_and_source_status_contains_no_heavy_rows(self):
        player = self.make_player(FakePersonalizationClient())
        player.playlists = []; player.network = {}; player.search_results = []
        player.catalog_revision = 0; player.catalog = player._empty_catalog()
        player.collection_revision = 0; player.collection = player._empty_collection()
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=target)):
            player.browse_personal_playlist("daily")
        status = player.status()
        self.assertEqual(status["libraryBrowseKind"], "browse_personal")
        self.assertEqual(status["libraryBrowseArg"], "daily")
        self.assertEqual(status["libraryDuration"], 120)
        self.assertNotIn("libraryTracks", status)
        self.assertNotIn("queueTracks", status)
        self.assertNotIn("queueRemaining", status)

    @staticmethod
    def wait_until(predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        raise AssertionError("background personalization worker did not finish")

    def test_home_metadata_stays_in_details_not_status(self):
        player = self.make_player(FakePersonalizationClient())
        player.playlists = []; player.network = {}; player.search_results = []
        player.catalog_revision = 0; player.catalog = player._empty_catalog()
        player.collection_revision = 0; player.collection = player._empty_collection()
        with patch.object(backend.threading, "Thread") as worker:
            player.handle({"command": "library_home"})
            worker.call_args.kwargs["target"]()
        status = player.status()
        details = player.status(include_queue=True)
        self.assertNotIn("libraryHub", status)
        self.assertEqual(status["libraryHubRevision"], details["libraryHub"]["revision"])
        self.assertEqual([row["personalId"] for row in details["libraryHub"]["items"]],
                         [identifier for identifier, _ in backend.PERSONAL_PLAYLISTS])
        details["libraryHub"]["items"].clear()
        self.assertEqual(len(player.library_hub["items"]), len(backend.PERSONAL_PLAYLISTS))
        with patch.object(backend.threading, "Thread") as worker:
            player.handle({"command": "library_home_refresh"})
            self.assertTrue(player.library_hub["loading"])
            worker.call_args.kwargs["target"]()
        self.assertEqual(len(player.client.calls), 2 * len(backend.PERSONAL_PLAYLISTS))

    def test_home_loads_only_personal_metadata_and_reuses_it_for_browse(self):
        client = FakePersonalizationClient()
        for generated in client.personal.values():
            generated.data.cover = SimpleNamespace(uri="covers.invalid/%%")
            generated.data.fetch_tracks = Mock(side_effect=AssertionError("eager tracks"))
        player = self.make_player(client)
        player._set_queue = Mock()
        original_queue = list(player.queue)
        original_state = dict(player.state)
        self.assertEqual(client.calls, [])

        with patch.object(backend.threading, "Thread") as worker:
            player.library_home()
            self.assertEqual(player.library_hub["view"], "home")
            self.assertTrue(player.library_hub["loading"])
            self.assertFalse(player.library_hub["homeLoaded"])
            player.library_home()
            worker.assert_called_once()
            worker.call_args.kwargs["target"]()

        rows = player.library_hub["items"]
        self.assertTrue(player.library_hub["homeLoaded"])
        self.assertEqual([row["personalId"] for row in rows],
                         [identifier for identifier, _ in backend.PERSONAL_PLAYLISTS])
        self.assertTrue(all(row["artUrl"] == "https://covers.invalid/400x400" for row in rows))
        self.assertEqual(client.calls, [("personal", identifier)
                                       for identifier, _ in backend.PERSONAL_PLAYLISTS])
        self.assertEqual(player.state, original_state)
        self.assertEqual(player.queue, original_queue)
        self.assertEqual(player.queue_revision, 0)
        player._set_queue.assert_not_called()
        for generated in client.personal.values():
            generated.data.fetch_tracks.assert_not_called()

        calls = list(client.calls)
        player.library_section("personal")
        self.assertEqual(player.library_hub["view"], "section")
        self.assertEqual(player.library_hub["items"], rows)
        player.library_back()
        self.assertEqual(player.library_hub["view"], "home")
        self.assertEqual(player.library_hub["items"], rows)
        self.assertTrue(player.library_hub["homeLoaded"])
        for playlist_id, title in (("daily", "Плейлист дня"), ("podcasts", "Подкасты недели")):
            player.handle({"command": "browse_personal", "playlistId": playlist_id})
            self.wait_until(lambda: not player.state["libraryLoading"])
            self.assertEqual(player.state["libraryBrowseName"], title)
            self.assertEqual(player.library_results, client.personal[playlist_id].data.tracks)
            self.assertEqual(client.calls, calls)
            self.assertEqual(player.queue, original_queue)
            player._set_queue.assert_not_called()

    def test_home_pending_generation_is_reloaded_and_old_ready_model_removed(self):
        client = FakePersonalizationClient()
        player = self.make_player(client)
        with patch.object(backend.threading, "Thread") as worker:
            player.library_home()
            worker.call_args.kwargs["target"]()
            client.personal["daily"].ready = False
            player.library_home(force=True)
            worker.call_args.kwargs["target"]()
            row = player.library_hub["items"][0]
            self.assertFalse(row["available"])
            self.assertFalse(row["generationReady"])
            self.assertNotIn("daily", player.personal_playlist_models)
            self.assertTrue(player.library_hub["homeLoaded"])
            player.library_back()
            self.assertFalse(player.library_hub["items"][0]["available"])
            client.personal["daily"].ready = True
            player.library_section("personal")
            self.assertTrue(player.library_hub["loading"])
            worker.call_args.kwargs["target"]()
        self.assertTrue(player.library_hub["items"][0]["available"])
        self.assertEqual(len(client.calls), 3 * len(backend.PERSONAL_PLAYLISTS))

    def test_home_cache_expires_without_fetching_on_back(self):
        client = FakePersonalizationClient()
        player = self.make_player(client)
        with patch.object(backend.threading, "Thread") as worker:
            player.library_section("personal")
            worker.call_args.kwargs["target"]()
            player.library_home()
            self.assertFalse(player.library_hub["loading"])
            worker.assert_called_once()
            player.library_hub_cache["personal"]["storedAt"] -= backend.LIBRARY_HUB_CACHE_TTL + 1
            player.library_back()
            self.assertFalse(player.library_hub["homeLoaded"])
            self.assertEqual(player.library_hub["items"], [])
            self.assertEqual(player.personal_playlist_models, {})
            self.assertEqual(len(client.calls), len(backend.PERSONAL_PLAYLISTS))
            player.library_home()
            self.assertTrue(player.library_hub["loading"])
            worker.call_args.kwargs["target"]()
        self.assertEqual(len(client.calls), 2 * len(backend.PERSONAL_PLAYLISTS))

    def test_home_partial_and_failure_remain_local_and_retryable(self):
        client = FakePersonalizationClient()
        player = self.make_player(client)
        original_state = dict(player.state)
        client.personal["daily"] = RuntimeError("secret raw response")
        with patch.object(backend.threading, "Thread") as worker:
            player.library_home()
            worker.call_args.kwargs["target"]()
            self.assertEqual({row["personalId"] for row in player.library_hub["items"]},
                             {"missedLikes", "recentTracks", "neverHeard", "podcasts"})
            self.assertTrue(player.library_hub["warning"])
            self.assertEqual(player.library_hub["error"], "")
            for key in client.personal:
                client.personal[key] = RuntimeError("secret raw response")
            player.library_home()
            self.assertTrue(player.library_hub["loading"])
            worker.call_args.kwargs["target"]()
        self.assertTrue(player.library_hub["homeLoaded"])
        self.assertTrue(player.library_hub["error"])
        self.assertNotIn("secret", player.library_hub["error"])
        self.assertEqual(player.library_hub["items"], [])
        self.assertEqual(player.personal_playlist_models, {})
        self.assertEqual(player.state, original_state)
        error = player.library_hub["error"]
        with patch.object(backend.threading, "Thread") as worker:
            player.library_section("albums")
            worker.call_args.kwargs["target"]()
            calls = list(client.calls)
            player.library_back()
            self.assertTrue(player.library_hub["homeLoaded"])
            self.assertEqual(player.library_hub["error"], error)
            self.assertEqual(client.calls, calls)
            player.library_home()
            self.assertTrue(player.library_hub["loading"])
            worker.call_args.kwargs["target"]()
        self.assertEqual(player.library_hub["error"], error)

    def test_home_responses_cannot_publish_after_navigation_refresh_or_client_change(self):
        for transition in ("section", "back", "refresh", "client"):
            with self.subTest(transition=transition):
                client = FakePersonalizationClient()
                player = self.make_player(client)
                original = client.playlists_personal

                def interrupted(playlist_id):
                    result = original(playlist_id)
                    if transition == "section":
                        player.library_section("albums")
                    elif transition == "back":
                        player.library_back()
                    elif transition == "refresh":
                        player.library_home(force=True)
                    else:
                        player.client = FakePersonalizationClient()
                    return result

                client.playlists_personal = interrupted
                with patch.object(backend.threading, "Thread") as worker:
                    player.library_home()
                    worker.call_args.kwargs["target"]()
                    self.assertEqual(player.library_hub_cache, {})
                    self.assertEqual(player.personal_playlist_models, {})
                    self.assertEqual(player.library_hub["items"], [])
                    self.assertEqual(client.calls, [("personal", "daily")])
                    if transition in ("section", "refresh"):
                        client.playlists_personal = original
                        worker.call_args.kwargs["target"]()
                        self.assertFalse(player.library_hub["loading"])
                        if transition == "refresh":
                            self.assertEqual(len(player.library_hub["items"]), len(backend.PERSONAL_PLAYLISTS))
                        else:
                            self.assertEqual(player.library_hub["section"], "albums")
                    elif transition == "back":
                        self.assertFalse(player.library_hub["homeLoaded"])

    def test_sections_load_lazily_and_personal_playlists_are_cached(self):
        client = FakePersonalizationClient()
        player = self.make_player(client)

        player.library_section("personal")
        self.wait_until(lambda: not player.library_hub["loading"])

        self.assertEqual([call[0] for call in client.calls],
                         ["personal"] * len(backend.PERSONAL_PLAYLISTS))
        self.assertEqual([row["personalId"] for row in player.library_hub["items"]],
                         [value for value, _title in backend.PERSONAL_PLAYLISTS])
        self.assertTrue(all(row["available"] for row in player.library_hub["items"]))
        self.assertEqual(len(player.personal_playlist_models), len(backend.PERSONAL_PLAYLISTS))
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
        self.wait_until(lambda: not player.state["libraryLoading"])
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
        self.wait_until(lambda: not player.state["libraryLoading"])

        self.assertIn("не сформирован Яндекс Музыкой", player.state["libraryError"])
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
