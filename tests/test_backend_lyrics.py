import json
import os
import threading
import time
import unittest
from collections import OrderedDict
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import Mock, patch

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

    def track_supplement(self, track_id):
        return None


class NotFoundError(RuntimeError):
    pass


class LyricsTests(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        home = patch.dict(os.environ, HOME=str(self.home))
        home.start()
        self.addCleanup(home.stop)
        network = patch.object(backend.requests, "get", side_effect=AssertionError("unexpected network"))
        self.http_get = network.start()
        self.addCleanup(network.stop)
        transport = patch.object(backend.Player, "_lrclib_json", side_effect=AssertionError("unexpected LRCLIB network"))
        transport.start()
        self.addCleanup(transport.stop)

    def make_player(self, client):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = client
        player.queue = [SimpleNamespace(id="42")]
        player.index = 0
        player.detached_track = None
        player.lyrics_cache = OrderedDict()
        player.lyrics_loading = {}
        player.lyrics_generation = 0
        player.lyrics_cache_dir = self.home / "lyrics"
        player.preferences = {"showBarLyrics": False}
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

    @staticmethod
    def entry():
        return {"available": True, "synced": True, "format": "LRC",
                "writers": ["Writer"], "lines": [{"time": 1.0, "text": "Line"}], "error": ""}

    def complete_load(self, player, *, force=False, prefetch=False):
        with patch.object(backend.threading, "Thread") as worker:
            if prefetch:
                player._prefetch_lyrics(player._track_id(player.queue[player.index]))
            else:
                self.assertTrue(player.lyrics(force=force)["loading"])
            worker.assert_called_once()
            worker.call_args.kwargs["target"]()
        return player.lyrics()

    def test_prefetch_is_opt_in_but_explicit_requests_work_when_disabled(self):
        player = self.make_player(FakeLyricsClient(
            {"LRC": NotFoundError("missing"), "TEXT": None}))
        player.queue = [SimpleNamespace(id=str(index), title="Title",
                                        artists=[SimpleNamespace(name="Artist")])
                        for index in range(2)]
        with (patch.object(backend.threading, "Thread") as worker,
              patch.object(player, "_read_disk_lyrics") as disk):
            for track in player.queue:
                player._prefetch_lyrics(track.id)
            worker.assert_not_called()
            disk.assert_not_called()
        self.assertEqual(player.client.calls, [])
        self.http_get.assert_not_called()
        with patch.object(player, "_fetch_lrclib_synced", return_value="[00:01]Line") as lrclib:
            self.assertTrue(self.complete_load(player)["synced"])
            self.assertTrue(self.complete_load(player, force=True)["synced"])
            self.assertEqual(lrclib.call_count, 2)
        player.preferences["showBarLyrics"] = True
        player.index = 1
        with patch.object(player, "_fetch_lrclib_synced", return_value="[00:01]Line") as lrclib:
            self.assertTrue(self.complete_load(player, prefetch=True)["synced"])
            lrclib.assert_called_once()

    def test_transient_errors_stay_local_are_not_persisted_and_can_be_retried(self):
        missing = NotFoundError("missing")
        for failed in ("LRC", "TEXT", "supplement", "LRCLIB"):
            with self.subTest(failed=failed):
                client = FakeLyricsClient({"LRC": missing, "TEXT": missing})
                player = self.make_player(client)
                failure = RuntimeError("temporary outage")
                if failed in client.responses:
                    client.responses[failed] = failure
                elif failed == "supplement":
                    client.track_supplement = Mock(side_effect=failure)
                else:
                    player._fetch_lrclib_synced = Mock(side_effect=failure)
                response = self.complete_load(player)
                self.assertFalse(response["available"])
                self.assertEqual(player.state["error"], "existing player state")
                self.assertFalse((player.lyrics_cache_dir / "42.json").exists())
                client.responses["LRC"] = FakeLyrics("[00:01]Recovered")
                response = self.complete_load(player, force=True)
                self.assertTrue(response["available"])
                self.assertEqual(response["error"], "")
                self.assertTrue((player.lyrics_cache_dir / "42.json").exists())
                (player.lyrics_cache_dir / "42.json").unlink()

    def test_lyrics_errors_never_expose_request_urls_or_source_details(self):
        secret = "private-track-and-artist"
        response = backend.requests.Response()
        response.status_code = 503
        response.url = f"https://lrclib.net/api/search?track_name={secret}"
        failures = [
            backend.requests.HTTPError(f"503 Server Error for url: {response.url}", response=response),
            backend.requests.Timeout(f"Timed out: {response.url}"),
            backend.requests.ConnectionError(f"Connection failed: {response.url}"),
            ValueError(f"Invalid response: {secret}"),
            RuntimeError(f"Unknown failure: {response.url}"),
        ]
        for prefetch in (False, True):
            messages = []
            for failure in failures:
                with self.subTest(prefetch=prefetch, failure=type(failure).__name__):
                    client = FakeLyricsClient({"LRC": failure, "TEXT": failure})
                    player = self.make_player(client)
                    player.preferences["showBarLyrics"] = True
                    result = self.complete_load(player, prefetch=prefetch)
                    messages.append(result["error"])
                    self.assertFalse(result["available"])
                    self.assertNotIn(secret, json.dumps(result))
                    self.assertNotIn("https://", result["error"])
            self.assertNotEqual(messages[0], messages[1])
            self.assertNotEqual(messages[1], messages[2])

    def test_successful_fallback_wins_over_transient_source_failure(self):
        client = FakeLyricsClient({"LRC": RuntimeError("temporary"), "TEXT": FakeLyrics("Plain")})
        player = self.make_player(client)
        response = self.complete_load(player)
        self.assertTrue(response["available"])
        self.assertEqual(response["format"], "TEXT")
        self.assertEqual(response["error"], "")
        self.assertIsNotNone(player._read_disk_lyrics("42"))

    def test_negative_and_error_disk_records_are_removed_and_reloaded(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Recovered")}))
        for error in ("", "temporary outage"):
            with self.subTest(error=error):
                player.lyrics_cache.clear()
                path = player.lyrics_cache_dir / "42.json"
                backend.atomic_json(path, {"available": False, "synced": False, "format": "",
                                           "writers": [], "lines": [], "error": error})
                self.assertIsNone(player._read_disk_lyrics("42"))
                self.assertFalse(path.exists())
                self.assertTrue(self.complete_load(player)["available"])
        player._store_lyrics_locked("missing", {"available": False, "lines": [], "error": ""})
        self.assertFalse((player.lyrics_cache_dir / "missing.json").exists())

    def test_disk_hits_obey_ram_lru_without_rewriting_files(self):
        for route in ("prefetch", "lyrics", "status"):
            with self.subTest(route=route):
                player = self.make_player(FakeLyricsClient({}))
                player.preferences["showBarLyrics"] = True
                player.playlists = []; player.search_results = []; player.network = {}
                for name in ("queue_revision", "library_revision", "library_hub_revision",
                             "catalog_revision", "collection_revision"):
                    setattr(player, name, 0)
                count = backend.LYRICS_CACHE_MAX_ENTRIES + 2
                for index in range(count):
                    player._write_disk_lyrics(str(index), self.entry())
                paths = list(player.lyrics_cache_dir.glob("*.json"))
                mtimes = {path: path.stat().st_mtime_ns for path in paths}
                with patch.object(backend, "atomic_json") as write:
                    for index in range(count):
                        player.queue = [SimpleNamespace(id=str(index))]
                        if route == "prefetch":
                            player._prefetch_lyrics(str(index))
                        elif route == "lyrics":
                            self.assertTrue(player.lyrics()["available"])
                        else:
                            self.assertTrue(player.status()["lyrics"]["available"])
                        self.assertLessEqual(len(player.lyrics_cache), backend.LYRICS_CACHE_MAX_ENTRIES)
                    write.assert_not_called()
                self.assertEqual(list(player.lyrics_cache), [str(i) for i in range(2, count)])
                self.assertEqual(mtimes, {path: path.stat().st_mtime_ns for path in paths})

    def test_disk_cache_is_private_atomic_and_evicts_oldest_mtime(self):
        player = self.make_player(FakeLyricsClient({}))
        count = backend.LYRICS_DISK_CACHE_MAX_ENTRIES
        for index in range(count):
            player._write_disk_lyrics(str(index), self.entry())
            os.utime(player.lyrics_cache_dir / f"{index}.json", ns=(index + 1, index + 1))
        player._read_disk_lyrics("0")
        with patch.object(backend, "atomic_json", wraps=backend.atomic_json) as write:
            player._write_disk_lyrics("new", self.entry())
            write.assert_called_once()
        self.assertEqual(len(list(player.lyrics_cache_dir.glob("*.json"))), count)
        self.assertFalse((player.lyrics_cache_dir / "0.json").exists())
        self.assertTrue((player.lyrics_cache_dir / "1.json").exists())
        self.assertEqual(player.lyrics_cache_dir.stat().st_mode & 0o777, 0o700)
        self.assertEqual((player.lyrics_cache_dir / "new.json").stat().st_mode & 0o777, 0o600)

    def test_disk_reads_reject_invalid_shapes_and_oversized_records(self):
        player = self.make_player(FakeLyricsClient({}))
        invalid = [[], {}, {**self.entry(), "writers": "Writer"},
                   {**self.entry(), "synced": "yes"}, {**self.entry(), "format": "TEXT"},
                   {**self.entry(), "error": "failed"}, {**self.entry(), "lines": []}]
        for line in (None, {}, {"time": 1, "text": None}, {"time": True, "text": "Line"},
                     {"time": "1", "text": "Line"}, {"time": float("nan"), "text": "Line"},
                     {"time": float("inf"), "text": "Line"}, {"time": -1, "text": "Line"}):
            invalid.append({**self.entry(), "lines": [line]})
        invalid.append({**self.entry(), "lines": [{"time": 2, "text": "A"}, {"time": 1, "text": "B"}]})
        path = player.lyrics_cache_dir / "42.json"
        for entry in invalid:
            with self.subTest(entry=entry):
                backend.atomic_json(path, entry)
                self.assertIsNone(player._read_disk_lyrics("42"))
                self.assertFalse(path.exists())
        backend.atomic_json(path, self.entry())
        with patch.object(backend, "HTTP_JSON_MAX_BYTES", 16):
            self.assertIsNone(player._read_disk_lyrics("42"))
        self.assertFalse(path.exists())
        plain = {**self.entry(), "synced": False, "format": "TEXT", "syncedLookupComplete": True,
                 "lines": [{"time": -1, "text": "Plain"}]}
        backend.atomic_json(path, plain)
        self.assertEqual(player._read_disk_lyrics("42"), plain)

    def test_track_ids_cannot_escape_disk_cache_on_read_write_or_refresh(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Line")}))
        outside = self.home / "outside.json"
        backend.atomic_json(outside, self.entry())
        original = outside.read_bytes()
        for track_id in ("../outside", str(outside.with_suffix("")), "../../outside", "nested/track"):
            with self.subTest(track_id=track_id):
                self.assertIsNone(player._read_disk_lyrics(track_id))
                player._write_disk_lyrics(track_id, self.entry())
                player.queue = [SimpleNamespace(id=track_id)]
                self.assertTrue(self.complete_load(player, force=True)["available"])
                self.assertEqual(outside.read_bytes(), original)
        self.assertFalse(player.lyrics_cache_dir.exists())

    def test_logout_removes_disk_cache_preserves_preferences_and_rejects_stale_load(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Line")}))
        player.stop = Mock()
        player._publish_mpris = Mock()
        for name in ("catalog_generation", "suggestion_generation", "catalog_revision",
                     "track_info_generation", "library_generation", "library_revision",
                     "library_hub_generation", "library_hub_revision", "collection_generation",
                     "collection_revision", "queue_generation", "queue_revision"):
            setattr(player, name, 0)
        for name in ("catalog_cache", "track_info_cache", "library_hub_cache", "personal_playlist_models"):
            setattr(player, name, {})
        player.track_info_loading = set()
        preferences = self.home / "preferences.json"
        token = self.home / "token.json"
        state = self.home / "state.json"
        backend.atomic_json(preferences, player.preferences)
        original = preferences.read_bytes()
        token.write_text("fake token")
        state.write_text("fake state")
        player._write_disk_lyrics("old", self.entry())
        with patch.object(backend.threading, "Thread") as worker:
            player.lyrics()
            pending = worker.call_args.kwargs["target"]
        with (patch.object(backend, "TOKEN_FILE", token),
              patch.object(backend, "STATE_FILE", state),
              patch.object(backend, "PREFERENCES_FILE", preferences)):
            player.logout()
            pending()
        self.assertFalse(player.lyrics_cache_dir.exists())
        self.assertEqual(player.lyrics_cache, {})
        self.assertEqual(player.lyrics_loading, {})
        self.assertEqual(preferences.read_bytes(), original)
        self.assertEqual(player.preferences, {"showBarLyrics": False})
        self.assertFalse(token.exists())
        self.assertFalse(state.exists())

    def test_replaced_client_cannot_publish_pending_lyrics(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Line")}))
        with patch.object(backend.threading, "Thread") as worker:
            player.lyrics()
            pending = worker.call_args.kwargs["target"]
        player.client = FakeLyricsClient({})
        pending()
        self.assertEqual(player.lyrics_cache, {})
        self.assertFalse(player.lyrics_cache_dir.exists())

    def test_sdk_lyrics_calls_remain_serialized(self):
        client = FakeLyricsClient({"LRC": NotFoundError("missing"), "TEXT": None})
        player = self.make_player(client)
        def check_lock(*args, **kwargs):
            self.assertTrue(player.api_lock.locked())
        client.tracks_lyrics = Mock(side_effect=check_lock)
        client.track_supplement = Mock(side_effect=check_lock)
        self.complete_load(player)
        self.assertEqual(client.tracks_lyrics.call_count, 2)
        client.track_supplement.assert_called_once()

    def test_untimed_yandex_lrc_does_not_block_lrclib_sync(self):
        player = self.make_player(FakeLyricsClient(
            {"LRC": FakeLyrics("Untimed"), "TEXT": FakeLyrics("Unused")}))
        with patch.object(player, "_fetch_lrclib_synced", return_value="[00:10.47]Timed"):
            result = self.complete_load(player)
        self.assertTrue(result["synced"])
        self.assertEqual(result["lines"], [{"time": 10.47, "text": "Timed"}])
        self.assertEqual(player.client.calls, [("42", "LRC")])

    def test_legacy_plain_cache_is_replaced_by_a_fresh_synced_lookup(self):
        player = self.make_player(FakeLyricsClient({"LRC": None, "TEXT": None}))
        backend.atomic_json(player.lyrics_cache_dir / "42.json", {
            "available": True, "synced": False, "format": "TEXT",
            "writers": [], "lines": [{"time": -1, "text": "Old plain"}], "error": ""})
        with patch.object(player, "_fetch_lrclib_synced", return_value="[00:01.25]Timed"):
            result = self.complete_load(player)
        self.assertTrue(result["synced"])
        self.assertEqual(result["lines"][0]["time"], 1.25)
        self.assertTrue(player._read_disk_lyrics("42")["synced"])

    def test_failed_sync_with_plain_fallback_is_retried_on_return_not_saved_as_final(self):
        player = self.make_player(FakeLyricsClient({"LRC": None, "TEXT": FakeLyrics("Plain")}))
        player.queue.append(SimpleNamespace(id="43"))
        with patch.object(player, "_fetch_lrclib_synced", side_effect=[
            backend.requests.Timeout("temporary"), "", "[00:02.5]Recovered",
        ]):
            self.assertFalse(self.complete_load(player)["synced"])
            self.assertFalse((player.lyrics_cache_dir / "42.json").exists())
            player.index = 1
            self.complete_load(player)
            player.index = 0
            result = self.complete_load(player)
        self.assertTrue(result["synced"])
        self.assertEqual(result["lines"][0]["time"], 2.5)

    def test_track_switch_and_return_cannot_let_an_old_worker_replace_a_new_load(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:00.125]Current")}))
        player.queue.append(SimpleNamespace(id="43"))
        with patch.object(backend.threading, "Thread") as worker:
            player.lyrics()
            old_a = player.lyrics_loading["42"]
            finish_old_a = worker.call_args.kwargs["target"]
            player.index = 1
            player.lyrics()
            old_b = player.lyrics_loading["43"]
            finish_old_b = worker.call_args.kwargs["target"]
            player.index = 0
            player.lyrics()
            new_a = player.lyrics_loading["42"]
            finish_new_a = worker.call_args.kwargs["target"]
            self.assertTrue(old_a.cancelled.is_set())
            self.assertTrue(old_b.cancelled.is_set())
            finish_old_a()
            finish_old_b()
            self.assertIs(player.lyrics_loading["42"], new_a)
            self.assertEqual(player.client.calls, [])
            finish_new_a()
        self.assertEqual(player.lyrics()["lines"], [{"time": 0.125, "text": "Current"}])
        self.assertNotIn("43", player.lyrics_cache)

    def test_enabling_subtitles_mid_track_prefetches_current_and_existing_next_candidate(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Line")}))
        player.queue = [SimpleNamespace(id=str(index)) for index in range(3)]
        player.preferences["playbackMode"] = "shuffle"
        player.preload_candidate = {"signature": "existing", "index": 2}
        player._preload_signature_locked = Mock(return_value="existing")
        with (patch.object(backend, "PREFERENCES_FILE", self.home / "preferences.json"),
              patch.object(backend.threading, "Thread") as worker):
            player.set_preference("showBarLyrics", True)
            self.assertEqual(worker.call_count, 2)
            self.assertEqual(set(player.lyrics_loading), {"0", "2"})
            for call in worker.call_args_list:
                call.kwargs["target"]()
        self.assertEqual(player.client.calls, [("0", "LRC"), ("2", "LRC")])
        self.assertTrue(player.lyrics_cache["0"]["available"])
        self.assertTrue(player.lyrics_cache["2"]["available"])

    def test_disabling_subtitles_cancels_unstarted_prefetch_but_allows_explicit_load(self):
        player = self.make_player(FakeLyricsClient({"LRC": FakeLyrics("[00:01]Line")}))
        player.queue.append(SimpleNamespace(id="43"))
        with (patch.object(backend, "PREFERENCES_FILE", self.home / "preferences.json"),
              patch.object(backend.threading, "Thread") as worker):
            player.set_preference("showBarLyrics", True)
            pending = [call.kwargs["target"] for call in worker.call_args_list]
            self.assertEqual(len(pending), 2)
            player.set_preference("showBarLyrics", False)
            for load in pending:
                load()
            self.assertEqual(worker.call_count, 2)
        self.assertEqual(player.client.calls, [])
        self.assertEqual(player.lyrics_loading, {})
        self.assertEqual(player.lyrics_cache, {})
        self.assertFalse(player.lyrics_cache_dir.exists())
        self.assertTrue(self.complete_load(player)["available"])

    def test_disabling_subtitles_cancels_started_prefetch_without_cancelling_manual_load(self):
        player = self.make_player(FakeLyricsClient({}))
        player.preferences["showBarLyrics"] = True
        def disable_during_fetch(*args, **kwargs):
            player.set_preference("showBarLyrics", False)
            return FakeLyrics("[00:01]Manual")
        player.client.tracks_lyrics = Mock(side_effect=disable_during_fetch)
        with (patch.object(backend, "PREFERENCES_FILE", self.home / "preferences.json"),
              patch.object(backend.threading, "Thread") as worker):
            player._prefetch_lyrics("42")
            worker.call_args.kwargs["target"]()
            self.assertEqual(player.lyrics_cache, {})
            self.assertEqual(player.lyrics_loading, {})
            self.assertFalse(player.lyrics_cache_dir.exists())
        with patch.object(backend, "PREFERENCES_FILE", self.home / "preferences.json"):
            self.assertTrue(self.complete_load(player)["synced"])


if __name__ == "__main__":
    unittest.main()
