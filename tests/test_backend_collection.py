import threading
import time
import unittest
from collections import OrderedDict
from types import SimpleNamespace

from backend import backend


def album(id_="10"):
    return SimpleNamespace(id=str(id_), title="Album", artists=[], year=2024,
                           original_release_year=None, release_date="", genre="",
                           type="album", track_count=1, cover_uri="", og_image="")


def track(id_, album_id="10"):
    return SimpleNamespace(id=str(id_), title=f"Track {id_}", artists=[],
                           albums=[album(album_id)], duration_ms=120_000, cover_uri="")


def short(id_, album_id="10", embedded=None):
    return SimpleNamespace(id=str(id_), album_id=str(album_id), track=embedded,
                           track_id=f"{id_}:{album_id}")


def playlist(kind="7", rows=None, revision=3, title="Mine"):
    values = list(rows or [])
    return SimpleNamespace(kind=str(kind), uid="42", owner=SimpleNamespace(uid="42", name="Me"),
                           title=title, track_count=len(values), tracks=values,
                           revision=revision, playlist_uuid=f"uuid-{kind}", cover=None,
                           og_image="", image="")


class FakeCollectionClient:
    account_uid = "42"

    def __init__(self):
        self.current = playlist(rows=[short("1"), short("2")], revision=5)
        self.calls = []
        self.conflict_once = False
        self.delete_conflict_once = False
        self.partial_mutation_response = False
        self.recommended = [track("8"), track("9")]
        self.membership_playlists = {}

    def users_playlists(self, kind):
        if isinstance(kind, list):
            self.calls.append(("batch", tuple(str(value) for value in kind)))
            return [self.membership_playlists.get(str(value), self.current)
                    for value in kind]
        self.calls.append(("fetch", str(kind), self.current.revision))
        return self.membership_playlists.get(str(kind), self.current)

    def users_playlists_insert_track(self, kind, track_id, album_id, at=0, revision=1):
        self.calls.append(("insert", str(kind), str(track_id), str(album_id), at, revision))
        if self.conflict_once:
            self.conflict_once = False
            self.current.revision += 1
            raise RuntimeError("409 revision conflict")
        rows = list(self.current.tracks)
        rows.insert(at, short(track_id, album_id))
        self.current = playlist(kind, rows, revision + 1, self.current.title)
        if self.partial_mutation_response:
            response = playlist(kind, [], revision + 1, self.current.title)
            response.track_count = len(rows)
            return response
        return self.current

    def users_playlists_delete_track(self, kind, from_, to, revision=1):
        self.calls.append(("delete", str(kind), from_, to, revision))
        if self.delete_conflict_once:
            self.delete_conflict_once = False
            self.current.revision += 1
            raise RuntimeError("409 revision conflict")
        rows = list(self.current.tracks)
        del rows[from_:to]
        self.current = playlist(kind, rows, revision + 1, self.current.title)
        if self.partial_mutation_response:
            response = playlist(kind, [], revision + 1, self.current.title)
            response.track_count = len(rows)
            return response
        return self.current

    def users_playlists_create(self, title, visibility="public"):
        self.calls.append(("create", title, visibility))
        self.current = playlist("11", [], revision=1, title=title)
        return self.current

    def users_playlists_recommendations(self, kind):
        self.calls.append(("recommendations", str(kind)))
        return SimpleNamespace(tracks=list(self.recommended), batch_id="batch")

    def tracks(self, ids):
        self.calls.append(("tracks", list(ids)))
        return [track(str(value).split(":", 1)[0]) for value in ids]


class CollectionTests(unittest.TestCase):
    def make_player(self, client):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.state = {"loading": False, "loadingKind": "", "loadingStage": "", "error": "",
                        "libraryBrowseName": "", "libraryPlaylistKind": "",
                        "libraryEditable": False, "libraryTotal": 0,
                        "libraryHasMore": False, "libraryLoadingMore": False,
                        "libraryFromCache": False}
        player.collection_generation = 0
        player.collection_revision = 0
        player.collection = player._empty_collection()
        player.collection_recommendation_tracks = []
        player.playlists = [{"kind": "7", "title": "Mine", "count": 2,
                             "owner": "42", "uuid": "uuid-7"}]
        player.queue = [track("1")]
        player.index = 0
        player.detached_track = None
        player.queue_revision = 4
        player.library_results = []
        player.library_result_refs = []
        player.library_source = []
        player.library_offset = 0
        player.library_revision = 0
        player.library_generation = 0
        player.artist_results = []
        player.active_library_cache_key = ""
        player.collection_cache = {}
        player.library_hub_tracks = []
        player.library_hub_cache = OrderedDict()
        player.catalog_search_models = {name: [] for name in backend.CATALOG_SECTIONS}
        player.catalog_entity_tracks = []
        player.catalog_entity_source = []
        player.catalog_entity_offset = 0
        player.catalog_cache = OrderedDict()
        player.catalog = player._empty_catalog()
        player.catalog_revision = 0
        player.library_hub_revision = 0
        player.library_hub = player._empty_library_hub()
        player.search_results = []
        player.network = {}
        return player

    @staticmethod
    def wait(player, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not player.collection["busy"]:
                return
            time.sleep(0.01)
        raise AssertionError("collection worker did not finish")

    @staticmethod
    def wait_memberships(player, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not player.collection["membershipLoading"]:
                return
            time.sleep(0.01)
        raise AssertionError("membership worker did not finish")

    def test_empty_owned_playlist_can_open_for_recommendations_without_autoplay(self):
        client = FakeCollectionClient()
        client.current = playlist(rows=[], revision=2, title="Empty")
        client.current.fetch_tracks = lambda: []
        player = self.make_player(client)
        player._loading = lambda function, kind: function()
        original_queue = list(player.queue)

        player.play_playlist("7")

        self.assertEqual(player.state["libraryBrowseName"], "Empty")
        self.assertTrue(player.state["libraryEditable"])
        self.assertEqual(player.library_results, [])
        self.assertEqual(player.queue, original_queue)

    def test_add_uses_latest_revision_appends_and_preserves_queue(self):
        client = FakeCollectionClient()
        player = self.make_player(client)
        player.queue = [track("3")]
        original_queue = list(player.queue)

        player.playlist_add_track("7", "queue", 0, "3", "10")
        self.wait(player)

        insert = [call for call in client.calls if call[0] == "insert"][-1]
        self.assertEqual(insert[1:5], ("7", "3", "10", 2))
        self.assertEqual(insert[-1], 5)
        self.assertEqual(player.queue, original_queue)
        self.assertEqual(player.queue_revision, 4)
        self.assertIn("добавлен", player.collection["message"])
        self.assertEqual(player.playlists[0]["count"], 3)

    def test_revision_conflict_refetches_and_retries_once(self):
        client = FakeCollectionClient()
        client.conflict_once = True
        player = self.make_player(client)
        player.queue = [track("3")]

        player.playlist_add_track("7", "queue", 0, "3", "10")
        self.wait(player)

        inserts = [call for call in client.calls if call[0] == "insert"]
        self.assertEqual([call[-1] for call in inserts], [5, 6])
        self.assertEqual(len([call for call in client.calls if call[0] == "fetch"]), 2)
        self.assertEqual(player.collection["error"], "")

    def test_memberships_are_checked_in_one_batch_and_preserve_queue(self):
        client = FakeCollectionClient()
        client.membership_playlists = {
            "7": playlist("7", [short("1"), short("2")], revision=5, title="First"),
            "8": playlist("8", [short("3")], revision=2, title="Second"),
        }
        player = self.make_player(client)
        player.playlists = [
            {"kind": "7", "title": "First", "count": 2, "owner": "42", "uuid": "u7"},
            {"kind": "8", "title": "Second", "count": 1, "owner": "42", "uuid": "u8"},
        ]
        original_queue = list(player.queue)

        player.playlist_memberships("queue", 0, "1", "10")
        self.wait_memberships(player)

        self.assertEqual(client.calls[0], ("batch", ("7", "8")))
        self.assertEqual(player.collection["memberships"], {"7": True, "8": False})
        self.assertEqual(player.collection["membershipTrackId"], "1")
        self.assertEqual(player.queue, original_queue)

    def test_closed_membership_check_cannot_restore_private_snapshot(self):
        client = FakeCollectionClient()
        player = self.make_player(client)
        entered = threading.Event()
        release = threading.Event()
        original_fetch = client.users_playlists

        def delayed_fetch(kind):
            if isinstance(kind, list):
                entered.set()
                release.wait(1)
            return original_fetch(kind)

        client.users_playlists = delayed_fetch
        player.playlist_memberships("queue", 0, "1", "10")
        self.assertTrue(entered.wait(1))
        player.collection_clear()
        release.set()
        time.sleep(0.03)

        self.assertFalse(player.collection["membershipLoading"])
        self.assertEqual(player.collection["memberships"], {})
        self.assertEqual(player.collection["membershipTrackId"], "")

    def test_duplicate_insert_is_skipped_even_if_ui_state_is_stale(self):
        client = FakeCollectionClient()
        player = self.make_player(client)

        player.playlist_add_track("7", "queue", 0, "1", "10")
        self.wait(player)

        self.assertFalse(any(call[0] == "insert" for call in client.calls))
        self.assertEqual(player.collection["memberships"], {"7": True})
        self.assertIn("уже есть", player.collection["message"])

    def test_create_is_private_and_adds_selected_track(self):
        client = FakeCollectionClient()
        player = self.make_player(client)

        player.playlist_create("Road trip", "queue", 0, "1", "10")
        self.wait(player)

        self.assertIn(("create", "Road trip", "private"), client.calls)
        insert = [call for call in client.calls if call[0] == "insert"][-1]
        self.assertEqual(insert[1], "11")
        self.assertEqual(insert[4:], (0, 1))
        self.assertEqual(player.playlists[0]["kind"], "11")
        self.assertIn("создан", player.collection["message"])

    def test_create_add_retries_once_after_revision_conflict(self):
        client = FakeCollectionClient()
        client.conflict_once = True
        player = self.make_player(client)

        player.playlist_create("Retry", "queue", 0, "1", "10")
        self.wait(player)

        inserts = [call for call in client.calls if call[0] == "insert"]
        self.assertEqual([call[-1] for call in inserts], [1, 2])
        self.assertEqual(player.collection["error"], "")
        self.assertIn("создан", player.collection["message"])

    def test_delete_uses_duplicate_occurrence_and_half_open_range(self):
        client = FakeCollectionClient()
        rows = [short("1"), short("2"), short("1")]
        client.current = playlist(rows=rows, revision=9)
        player = self.make_player(client)
        player.active_library_cache_key = "playlist:7"
        player.library_source = rows
        player.library_results = [track("1"), track("2"), track("1")]
        player.library_result_refs = [("1", "10"), ("2", "10"), ("1", "10")]
        player.library_offset = 3
        player.state.update(libraryBrowseName="Mine", libraryPlaylistKind="7",
                            libraryEditable=True, libraryTotal=3)
        original_queue = list(player.queue)

        player.playlist_delete_track("7", "library", 2, "1", "10")
        self.wait(player)

        self.assertIn(("delete", "7", 2, 3, 9), client.calls)
        self.assertEqual(len(player.library_results), 2)
        self.assertEqual(player.queue, original_queue)
        self.assertIn("удалён", player.collection["message"])

    def test_delete_refreshes_rows_when_mutation_response_is_partial(self):
        client = FakeCollectionClient()
        rows = [short("1"), short("2"), short("3"), short("4")]
        client.current = playlist(rows=rows, revision=4)
        client.partial_mutation_response = True
        player = self.make_player(client)
        player.active_library_cache_key = "playlist:7"
        player.library_source = rows
        player.library_results = [track(str(index)) for index in range(1, 5)]
        player.library_result_refs = [(str(index), "10") for index in range(1, 5)]
        player.library_offset = 4
        player.state.update(libraryBrowseName="Mine", libraryPlaylistKind="7",
                            libraryEditable=True, libraryTotal=4)

        player.playlist_delete_track("7", "library", 1, "2", "10")
        self.wait(player)

        self.assertEqual(player.state["libraryTotal"], 3)
        self.assertEqual([player._track_id(row) for row in player.library_results],
                         ["1", "3", "4"])
        self.assertEqual(player.library_result_refs,
                         [("1", "10"), ("3", "10"), ("4", "10")])

    def test_delete_preserves_playlist_album_reference_for_same_track_id(self):
        client = FakeCollectionClient()
        rows = [short("1", "20"), short("1", "10"), short("1", "10")]
        client.current = playlist(rows=rows, revision=4)
        player = self.make_player(client)
        result_refs = []
        resolved = player._tracks_from_short_page(rows, client, result_refs=result_refs)
        self.assertEqual(result_refs, [("1", "20"), ("1", "10"), ("1", "10")])
        player.active_library_cache_key = "playlist:7"
        player.library_source = rows
        player.library_results = resolved
        player.library_result_refs = result_refs
        player.library_offset = 3
        player.state.update(libraryBrowseName="Mine", libraryPlaylistKind="7",
                            libraryEditable=True, libraryTotal=3)

        player.playlist_delete_track("7", "library", 0, "1", "20")
        self.wait(player)

        self.assertIn(("delete", "7", 0, 1, 4), client.calls)
        self.assertEqual([(row.id, row.album_id) for row in client.current.tracks],
                         [("1", "10"), ("1", "10")])

    def test_delete_conflict_refreshes_but_waits_for_user_retry(self):
        client = FakeCollectionClient()
        client.delete_conflict_once = True
        player = self.make_player(client)
        player.active_library_cache_key = "playlist:7"
        player.library_source = list(client.current.tracks)
        player.library_results = [track("1"), track("2")]
        player.library_result_refs = [("1", "10"), ("2", "10")]
        player.library_offset = 2
        player.state.update(libraryBrowseName="Mine", libraryPlaylistKind="7",
                            libraryEditable=True, libraryTotal=2)

        player.playlist_delete_track("7", "library", 0, "1", "10")
        self.wait(player)

        self.assertEqual(len([call for call in client.calls if call[0] == "delete"]), 1)
        self.assertIn("изменился", player.collection["error"])
        self.assertEqual(player.library_revision, 1)
        self.assertEqual(len(player.library_results), 2)

    def test_recommendations_are_lazy_and_do_not_start_playback(self):
        client = FakeCollectionClient()
        player = self.make_player(client)
        original_queue = list(player.queue)

        player.playlist_recommendations("7", "Mine")
        self.wait(player)

        self.assertEqual([row["trackId"] for row in player.collection["recommendations"]], ["8", "9"])
        self.assertEqual(player.queue, original_queue)
        self.assertFalse(any(call[0] == "insert" for call in client.calls))

        player.playlist_add_track("7", "recommendation", 0, "8", "10")
        self.wait(player)
        self.assertEqual([row["trackId"] for row in player.collection["recommendations"]], ["9"])

    def test_stale_client_result_cannot_restore_closed_snapshot(self):
        client = FakeCollectionClient()
        player = self.make_player(client)
        entered = threading.Event()
        release = threading.Event()
        finished = threading.Event()
        original_insert = client.users_playlists_insert_track
        original_refresh = player._refresh_open_playlist_views

        def delayed_insert(*args, **kwargs):
            entered.set()
            release.wait(1)
            return original_insert(*args, **kwargs)

        def observed_refresh(*args, **kwargs):
            original_refresh(*args, **kwargs)
            finished.set()

        client.users_playlists_insert_track = delayed_insert
        player._refresh_open_playlist_views = observed_refresh
        player.queue = [track("3")]
        player.playlist_add_track("7", "queue", 0, "3", "10")
        self.assertTrue(entered.wait(1))
        player.collection_clear()
        player.client = FakeCollectionClient()
        release.set()
        self.assertTrue(finished.wait(1))

        self.assertFalse(player.collection["busy"])
        self.assertEqual(player.collection["message"], "")
        self.assertEqual(player.collection["recommendations"], [])

    def test_stale_target_is_rejected_without_api_mutation(self):
        client = FakeCollectionClient()
        player = self.make_player(client)

        player.playlist_add_track("7", "queue", 0, "stale", "10")
        time.sleep(0.03)

        self.assertFalse(any(call[0] == "insert" for call in client.calls))
        self.assertEqual(player.collection_revision, 1)
        self.assertIn("изменился", player.collection["error"])

    def test_collection_payload_is_details_only(self):
        client = FakeCollectionClient()
        player = self.make_player(client)

        compact = player.status()
        detailed = player.status(include_queue=True)

        self.assertNotIn("collection", compact)
        self.assertIn("collectionRevision", compact)
        self.assertIn("collection", detailed)


if __name__ == "__main__":
    unittest.main()
