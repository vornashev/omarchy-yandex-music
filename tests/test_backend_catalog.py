import threading
import time
import unittest
from collections import OrderedDict
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from types import SimpleNamespace
from unittest.mock import Mock, patch

from backend import backend


def artist(id_, name):
    return SimpleNamespace(id=id_, name=name, genres=[], cover=None, og_image="", op_image="")


def album(id_, title, type_="album", tracks=None):
    return SimpleNamespace(
        id=id_, title=title, type=type_, meta_type="music", artists=[artist(1, "Artist")],
        year=2024, original_release_year=None, release_date="2024-01-02", genre="pop",
        track_count=len(tracks or []), cover_uri="", og_image="", volumes=[tracks or []],
    )


def track(id_, title=None, album_model=None):
    return SimpleNamespace(
        id=str(id_), title=title or f"Track {id_}", artists=[artist(1, "Artist")],
        albums=[album_model] if album_model else [], cover_uri="", duration_ms=120_000,
    )


class FakeCatalogClient:
    def __init__(self):
        self.calls = []
        self.search_pages = {}
        self.suggest_results = {}
        self.album_summary: Any = []
        self.album_detail: Any = None
        self.artist_brief: Any = None
        self.artist_info: Any = None
        self.artist_about: Any = None
        self.artist_tracks_result: Any = None
        self.artist_track_pages = {}
        self.direct_pages = {}
        self.discography_pages = {}
        self.similar_result: Any = None
        self.playlist_result: Any = None
        self.user_playlist_result: Any = None
        self.track_models = {}

    def search(self, query, type_="all", page=0):
        self.calls.append(("search", query, type_, page))
        value = self.search_pages.get((type_, page))
        if isinstance(value, Exception):
            raise value
        return value

    def search_suggest(self, query):
        self.calls.append(("suggest", query))
        value = self.suggest_results.get(query)
        if callable(value):
            return value()
        if isinstance(value, Exception):
            raise value
        return value

    def tracks(self, ids):
        ids = [str(value) for value in ids]
        self.calls.append(("tracks", ids))
        return [self.track_models[value] for value in ids if value in self.track_models]

    def albums(self, album_id):
        self.calls.append(("albums", str(album_id)))
        return self.album_summary

    def albums_with_tracks(self, album_id):
        self.calls.append(("album_tracks", str(album_id)))
        return self.album_detail

    def artists_brief_info(self, artist_id):
        self.calls.append(("artist_brief", str(artist_id)))
        return self.artist_brief

    def artists_info(self, artist_id):
        self.calls.append(("artist_info", str(artist_id)))
        return self.artist_info

    def artists_about(self, artist_id):
        self.calls.append(("artist_about", str(artist_id)))
        return self.artist_about

    def artists_tracks(self, artist_id, page=0, page_size=20):
        self.calls.append(("artist_tracks", str(artist_id), page, page_size))
        return self.artist_track_pages.get(page, self.artist_tracks_result)

    def artists_direct_albums(self, artist_id, page=0, page_size=20):
        self.calls.append(("direct", str(artist_id), page, page_size))
        return self.direct_pages.get(page)

    def artists_discography_albums(self, artist_id, page=0, page_size=20):
        self.calls.append(("discography", str(artist_id), page, page_size))
        return self.discography_pages.get(page)

    def artists_similar(self, artist_id):
        self.calls.append(("similar", str(artist_id)))
        return self.similar_result

    def playlist(self, uuid):
        self.calls.append(("playlist", uuid))
        return self.playlist_result

    def users_playlists(self, kind, user_id=None):
        self.calls.append(("users_playlist", str(kind), str(user_id)))
        return self.user_playlist_result


class CatalogTests(unittest.TestCase):
    def make_player(self, client):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.catalog_generation = 0
        player.suggestion_generation = 0
        player.catalog_revision = 0
        player.catalog = player._empty_catalog()
        player.catalog_search_models = {name: [] for name in backend.CATALOG_SECTIONS}
        player.catalog_entity_tracks = []
        player.catalog_entity_source = []
        player.catalog_entity_offset = 0
        player.catalog_cache = OrderedDict()
        player.search_results = []
        player.state = {"loadingStage": "", "error": "player error stays"}
        player.queue = [track("old")]
        player.queue_source = []
        player.queue_extending = False
        player.queue_advance_pending = False
        player.queue_advance_automatic = False
        player.queue_generation = 0
        player.queue_revision = 0
        player.queue_collection_key = ""
        player.queue_artist_id = ""
        player.queue_artist_page = 0
        player.queue_artist_has_more = False
        player.detached_track = None
        player.radio_station = ""
        player.preferences = {"playbackMode": "repeatQueue"}
        player.playback_report = None
        player.index = 0
        return player

    @staticmethod
    def wait_until(predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        raise AssertionError("background catalog worker did not finish")

    @staticmethod
    def search_result(**sections):
        values = {}
        for name, rows in sections.items():
            values[name] = SimpleNamespace(results=rows, total=len(rows), per_page=max(1, len(rows)))
        return SimpleNamespace(**values)

    def test_all_and_typed_search_use_sdk_types_and_four_sections(self):
        for type_ in backend.CATALOG_TYPES:
            with self.subTest(type_=type_):
                client = FakeCatalogClient()
                result = self.search_result(
                    tracks=[track(1)], artists=[artist(2, "Two")],
                    albums=[album(3, "Three")], playlists=[SimpleNamespace(
                        playlist_uuid="u", uid=4, kind=5, owner=None, title="Five",
                        track_count=0, cover=None, og_image="", image="")],
                )
                client.search_pages[(type_, 0)] = result
                player = self.make_player(client)
                player.catalog_search("query", type_)
                self.wait_until(lambda: not player.catalog["search"]["loading"])
                self.assertEqual(client.calls[0], ("search", "query", type_, 0))
                self.assertEqual(set(player.catalog["search"]["sections"]), set(backend.CATALOG_SECTIONS))

    def test_search_load_more_appends_without_duplicates(self):
        client = FakeCatalogClient()
        first = self.search_result(tracks=[track(1), track(2)])
        first.tracks.total = 3
        second = self.search_result(tracks=[track(2), track(3)])
        second.tracks.total = 3
        client.search_pages[("track", 0)] = first
        client.search_pages[("track", 1)] = second
        player = self.make_player(client)
        player.catalog_search("query", "track")
        self.wait_until(lambda: not player.catalog["search"]["loading"])
        player.catalog_load_more()
        self.wait_until(lambda: not player.catalog["search"]["loadingMore"])
        rows = player.catalog["search"]["sections"]["tracks"]["items"]
        self.assertEqual([row["trackId"] for row in rows], ["1", "2", "3"])
        self.assertEqual(player.catalog["search"]["page"], 1)

    def test_suggestions_threshold_and_stale_generation(self):
        client = FakeCatalogClient()
        started = threading.Event()
        release = threading.Event()

        def old_result():
            started.set()
            release.wait(1)
            return SimpleNamespace(suggestions=["old"])

        client.suggest_results["old"] = old_result
        client.suggest_results["new"] = SimpleNamespace(suggestions=["new", "new"])
        player = self.make_player(client)
        player.catalog_suggest(" x ", 1)
        self.assertFalse(any(call[0] == "suggest" for call in client.calls))
        player.catalog_suggest("old", 2)
        self.assertTrue(started.wait(1))
        player.catalog_suggest("new", 3)
        release.set()
        self.wait_until(lambda: player.catalog["suggestions"]["items"] == ["new"])
        self.assertEqual(player.catalog["suggestions"]["query"], "new")
        self.assertEqual(player.catalog["suggestions"]["generation"], 3)

    def test_short_tracks_are_resolved_in_one_batch_and_keep_order(self):
        client = FakeCatalogClient()
        client.track_models = {"1": track(1), "2": track(2)}
        player = self.make_player(client)
        rows = [SimpleNamespace(track=None, track_id="2:22"),
                SimpleNamespace(track=track("embedded"), track_id="embedded:33"),
                SimpleNamespace(track=None, track_id="1:11")]
        resolved = player._tracks_from_short_page(rows, client, update_loading=False)
        self.assertEqual([value.id for value in resolved], ["2", "embedded", "1"])
        self.assertEqual([call for call in client.calls if call[0] == "tracks"],
                         [("tracks", ["2", "1"])])

    def test_album_navigation_is_partial_safe_and_non_autoplay(self):
        client = FakeCatalogClient()
        model = album(7, "Album", tracks=[track(1), track(2)])
        client.album_summary = [model]
        client.album_detail = model
        player = self.make_player(client)
        old_queue = list(player.queue)
        player._set_queue = Mock()
        player.catalog_album("7")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))
        entity = player.catalog["entity"]
        self.assertEqual(entity["title"], "Album")
        self.assertEqual(entity["artists"][0]["id"], "1")
        self.assertEqual([row["trackId"] for row in entity["tracks"]], ["1", "2"])
        self.assertEqual(old_queue, player.queue)
        player._set_queue.assert_not_called()
        self.assertIn(("albums", "7"), client.calls)
        self.assertIn(("album_tracks", "7"), client.calls)

    def test_artist_page_uses_all_endpoints_and_classifies_releases(self):
        client = FakeCatalogClient()
        identity = artist(8, "Artist Eight")
        client.artist_brief = SimpleNamespace(artist=identity, popular_tracks=[], similar_artists=[], all_covers=[])
        client.artist_info = SimpleNamespace(artist=identity, covers=[], description="Biography")
        client.artist_about = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_tracks_result = SimpleNamespace(tracks=[track(1)])
        releases = [album(10, "LP", "album"), album(11, "Single", "single")]
        page = SimpleNamespace(albums=releases, pager=SimpleNamespace(total=2, per_page=20))
        client.direct_pages[0] = page
        client.discography_pages[0] = page
        client.similar_result = SimpleNamespace(
            artist=identity,
            similar_artists=[artist(index, f"Similar {index}") for index in range(9, 24)])
        player = self.make_player(client)
        player._set_queue = Mock()
        player.catalog_artist("8")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))
        entity = player.catalog["entity"]
        self.assertEqual(entity["description"], "Biography")
        self.assertEqual([row["title"] for row in entity["albums"]], ["LP"])
        self.assertEqual([row["title"] for row in entity["singles"]], ["Single"])
        self.assertEqual(entity["similar"][0]["id"], "9")
        self.assertEqual(len(entity["similar"]), 10)
        self.assertEqual(entity["releaseHasMore"], {"albums": False, "singles": False})
        self.assertEqual([call[0] for call in client.calls], [
            "artist_brief", "artist_info", "artist_about", "artist_tracks",
            "direct", "discography", "similar",
        ])
        player._set_queue.assert_not_called()

    def test_artist_popular_playback_keeps_pagination_context(self):
        client = FakeCatalogClient()
        identity = artist(8, "Artist Eight")
        first_tracks = [track(index) for index in range(1, 21)]
        client.artist_brief = SimpleNamespace(
            artist=identity, popular_tracks=[], similar_artists=[], all_covers=[])
        client.artist_info = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_about = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_track_pages[0] = SimpleNamespace(
            tracks=first_tracks, pager=SimpleNamespace(total=22, per_page=20))
        empty_releases = SimpleNamespace(
            albums=[], pager=SimpleNamespace(total=0, per_page=20))
        client.direct_pages[0] = empty_releases
        client.discography_pages[0] = empty_releases
        client.similar_result = SimpleNamespace(artist=identity, similar_artists=[])
        player = self.make_player(client)
        set_queue = Mock()
        player._set_queue = set_queue
        player._url = Mock(return_value="https://audio.invalid/temporary")

        player.catalog_artist("8")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))
        self.assertEqual(len(player.catalog["entity"]["tracks"]), 20)
        self.assertTrue(player.catalog["entity"]["popularHasMore"])
        player.play_catalog_track("entity", 19)
        self.wait_until(lambda: set_queue.call_count == 1)

        kwargs = set_queue.call_args.kwargs
        self.assertEqual(kwargs["artist_id"], "8")
        self.assertEqual(kwargs["artist_page"], 0)
        self.assertTrue(kwargs["artist_has_more"])

    def test_artist_queue_loads_track_21_instead_of_repeating_first_page(self):
        client = FakeCatalogClient()
        client.artist_track_pages[1] = SimpleNamespace(
            tracks=[track(20), track(21), track(22)],
            pager=SimpleNamespace(total=22, per_page=20))
        player = self.make_player(client)
        player.queue = [track(index) for index in range(1, 21)]
        player.index = 19
        player.queue_artist_id = "8"
        player.queue_artist_page = 0
        player.queue_artist_has_more = True
        player._finish_playback_reporting = Mock()
        player._save_state = Mock()
        player._play_current = Mock()

        player.next(automatic=True)
        self.wait_until(lambda: not player.queue_extending and len(player.queue) == 22)

        self.assertEqual([row.id for row in player.queue],
                         [str(index) for index in range(1, 23)])
        self.assertEqual(player.index, 20)
        self.assertEqual(player.queue_artist_page, 1)
        self.assertFalse(player.queue_artist_has_more)
        self.assertIn(("artist_tracks", "8", 1, 20), client.calls)
        player._play_current.assert_called_once()

    def test_single_known_album_does_not_offer_an_extra_page(self):
        client = FakeCatalogClient()
        identity = artist(8, "Artist Eight")
        client.artist_brief = SimpleNamespace(
            artist=identity, popular_tracks=[], similar_artists=[], all_covers=[])
        client.artist_info = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_about = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_tracks_result = SimpleNamespace(tracks=[])
        one_album = SimpleNamespace(
            albums=[album(10, "Only Album")],
            pager=SimpleNamespace(total=1, per_page=1))
        client.direct_pages[0] = one_album
        client.discography_pages[0] = one_album
        client.similar_result = SimpleNamespace(artist=identity, similar_artists=[])
        player = self.make_player(client)

        player.catalog_artist("8")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))
        self.assertEqual([row["title"] for row in player.catalog["entity"]["albums"]],
                         ["Only Album"])
        self.assertEqual(player.catalog["entity"]["releaseHasMore"],
                         {"albums": False, "singles": False})
        calls_before = list(client.calls)
        player.catalog_artist_more("albums")
        self.assertEqual(client.calls, calls_before)

    def test_artist_album_and_single_pages_load_independently(self):
        client = FakeCatalogClient()
        identity = artist(8, "Artist Eight")
        client.artist_brief = SimpleNamespace(artist=identity, popular_tracks=[], similar_artists=[], all_covers=[])
        client.artist_info = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_about = SimpleNamespace(artist=identity, covers=[], description="")
        client.artist_tracks_result = SimpleNamespace(tracks=[])
        first = SimpleNamespace(
            albums=[album(10, "LP 1"), album(11, "Single 1", "single")],
            pager=SimpleNamespace(total=40, per_page=20),
        )
        second = SimpleNamespace(
            albums=[album(12, "LP 2"), album(13, "Single 2", "single")],
            pager=SimpleNamespace(total=40, per_page=20),
        )
        client.direct_pages = {0: first, 1: second}
        client.discography_pages = {0: first, 1: second}
        client.similar_result = SimpleNamespace(artist=identity, similar_artists=[])
        player = self.make_player(client)
        player.catalog_artist("8")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))

        player.catalog_artist_more("albums")
        self.wait_until(lambda: not player.catalog["entity"]["releaseLoading"]["albums"])
        self.assertEqual([row["title"] for row in player.catalog["entity"]["albums"]],
                         ["LP 1", "LP 2"])
        self.assertEqual([row["title"] for row in player.catalog["entity"]["singles"]],
                         ["Single 1"])

        player.catalog_artist_more("singles")
        self.wait_until(lambda: not player.catalog["entity"]["releaseLoading"]["singles"])
        self.assertEqual([row["title"] for row in player.catalog["entity"]["singles"]],
                         ["Single 1", "Single 2"])
        self.assertEqual(player.catalog["entity"]["releasePages"], {"albums": 1, "singles": 1})

    def test_catalog_error_messages_cover_expected_http_failures(self):
        player = self.make_player(FakeCatalogClient())
        cases = [
            (RuntimeError("401 unauthorized raw"), "Сессия истекла"),
            (RuntimeError("404 not-found raw"), "не найден"),
            (RuntimeError("415 unsupported-media-type raw"), "временно недоступ"),
            (RuntimeError("429 too-many-requests raw"), backend.RATE_LIMIT_MESSAGE),
        ]
        for error, expected in cases:
            with self.subTest(error=str(error)):
                message = player._catalog_error(error, "Альбом")
                self.assertIn(expected, message)
                self.assertNotIn("raw", message)

    def test_playlist_resolves_uuid_or_owner_kind_without_autoplay(self):
        for use_uuid in (True, False):
            with self.subTest(use_uuid=use_uuid):
                client = FakeCatalogClient()
                model = SimpleNamespace(
                    playlist_uuid="uuid", uid=2, kind=3, owner=SimpleNamespace(uid=2, name="Owner"),
                    title="Playlist", track_count=1, cover=None, og_image="", image="",
                    tracks=[track(1)], description="", description_formatted="",
                )
                client.playlist_result = model
                client.user_playlist_result = model
                player = self.make_player(client)
                player._set_queue = Mock()
                player.catalog_playlist("uuid" if use_uuid else "", "2", "3")
                self.wait_until(lambda: not player.catalog["entity"].get("loading"))
                self.assertEqual(player.catalog["entity"]["tracks"][0]["trackId"], "1")
                expected = ("playlist", "uuid") if use_uuid else ("users_playlist", "3", "2")
                self.assertIn(expected, client.calls)
                player._set_queue.assert_not_called()

    def test_back_preserves_search_models_and_explicit_play_is_only_queue_action(self):
        client = FakeCatalogClient()
        client.search_pages[("track", 0)] = self.search_result(tracks=[track(1)])
        client.album_summary = [album(7, "Album")]
        client.album_detail = album(7, "Album")
        player = self.make_player(client)
        player.catalog_search("saved", "track")
        self.wait_until(lambda: not player.catalog["search"]["loading"])
        saved = player.catalog["search"].copy()
        raw = list(player.catalog_search_models["tracks"])
        player.catalog_album("7")
        self.wait_until(lambda: not player.catalog["entity"].get("loading"))
        player.catalog_back()
        self.assertEqual(player.catalog["search"], saved)
        self.assertEqual(player.catalog_search_models["tracks"], raw)
        player._url = Mock(return_value="https://audio.invalid/temporary")
        set_queue = Mock()
        player._set_queue = set_queue
        player.play_catalog_track("search", 0)
        self.wait_until(lambda: set_queue.call_count == 1)
        set_queue.assert_called_once()

    def test_catalog_playback_prepare_failure_preserves_queue(self):
        client = FakeCatalogClient()
        player = self.make_player(client)
        player.catalog_search_models["tracks"] = [track(1)]
        old_queue = list(player.queue)
        player._url = Mock(side_effect=RuntimeError("404 raw playback response"))
        player._set_queue = Mock()
        player.play_catalog_track("search", 0)
        self.wait_until(lambda: str(player.catalog["search"].get("error", "")) != "")
        player._set_queue.assert_not_called()
        self.assertEqual(player.queue, old_queue)
        self.assertNotIn("raw", player.catalog["search"]["error"])

    def test_handled_failure_stays_catalog_local(self):
        client = FakeCatalogClient()
        client.search_pages[("all", 0)] = RuntimeError('{"status": 415, "secret": "raw"}')
        player = self.make_player(client)
        player.catalog_search("query", "all")
        self.wait_until(lambda: not player.catalog["search"]["loading"])
        message = player.catalog["search"]["error"]
        self.assertIn("временно недоступ", message)
        self.assertNotIn("secret", message)
        self.assertEqual(player.state["error"], "player error stays")

    def test_catalog_cache_is_bounded_and_logout_clears_session_data(self):
        player = self.make_player(FakeCatalogClient())
        player.catalog["entity"] = {"type": "album", "id": "1", "loading": False}
        for index in range(backend.CATALOG_CACHE_MAX_ENTRIES + 2):
            player._store_catalog_entity_locked(f"album:{index}")
        self.assertEqual(len(player.catalog_cache), backend.CATALOG_CACHE_MAX_ENTRIES)

        player.stop = Mock()
        player._publish_mpris = Mock()
        player.playlists = []; player.artist_results = []; player.library_results = []
        player.lyrics_cache = OrderedDict(); player.lyrics_loading = set(); player.lyrics_generation = 0
        player.track_info_cache = OrderedDict(); player.track_info_loading = set(); player.track_info_generation = 0
        player.library_source = []; player.library_offset = 0; player.library_generation = 0; player.library_revision = 0
        player.active_library_cache_key = ""; player.collection_cache = {}
        player.liked_ids = set(); player.liked_rows = []; player.liked_rows_at = 0; player.disliked_ids = set()
        player.queue_source = []; player.queue_extending = False; player.queue_advance_pending = False
        player.queue_generation = 0; player.queue_revision = 0; player.queue_collection_key = ""
        player.detached_track = None; player.radio_station = ""; player.radio_batch_id = ""
        player.radio_track_batches = {}; player.radio_extending = False; player.playback_report = None
        player.state.update(authenticated=True, authPending=False, loading=False)
        with TemporaryDirectory() as directory:
            token_file = Path(directory) / "token.json"
            state_file = Path(directory) / "state.json"
            token_file.write_text("test token")
            state_file.write_text("test state")
            with (patch.object(backend, "TOKEN_FILE", token_file),
                  patch.object(backend, "STATE_FILE", state_file)):
                player.logout()
            self.assertFalse(token_file.exists())
            self.assertFalse(state_file.exists())
        self.assertEqual(player.catalog_cache, OrderedDict())
        self.assertEqual(player.catalog_search_models["tracks"], [])
        self.assertEqual(player.catalog["suggestions"]["items"], [])


if __name__ == "__main__":
    unittest.main()
