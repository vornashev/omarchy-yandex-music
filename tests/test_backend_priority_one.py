import queue
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from backend import backend


class FakeClient:
    def __init__(self):
        self.calls = []
        self.radio_result = None

    def play_audio(self, *args, **kwargs):
        self.calls.append(("play_audio", args, kwargs))
        return True

    def rotor_station_feedback_radio_started(self, *args, **kwargs):
        self.calls.append(("radio_started", args, kwargs))
        return True

    def rotor_station_feedback_track_started(self, *args, **kwargs):
        self.calls.append(("started", args, kwargs))
        return True

    def rotor_station_feedback_track_finished(self, *args, **kwargs):
        self.calls.append(("finished", args, kwargs))
        return True

    def rotor_station_feedback_skip(self, *args, **kwargs):
        self.calls.append(("skip", args, kwargs))
        return True

    def users_dislikes_tracks_add(self, track_id):
        self.calls.append(("dislike_add", track_id))
        return True

    def users_dislikes_tracks_remove(self, track_id):
        self.calls.append(("dislike_remove", track_id))
        return True

    def users_likes_tracks_add(self, track_id):
        self.calls.append(("like_add", track_id))
        return True

    def users_likes_tracks_remove(self, track_id):
        self.calls.append(("like_remove", track_id))
        return True

    def rotor_station_tracks(self, station, **kwargs):
        self.calls.append(("radio_tracks", station, kwargs))
        return self.radio_result


class PriorityOneTests(unittest.TestCase):
    def setUp(self):
        self.track = SimpleNamespace(
            id="42", duration_ms=180_000, albums=[SimpleNamespace(id="7")]
        )

    def make_player(self, radio=True):
        player = backend.Player.__new__(backend.Player)
        player.lock = threading.RLock()
        player.api_lock = threading.Lock()
        player.client = FakeClient()
        player.queue = [self.track]
        player.index = 0
        player.detached_track = None
        player.radio_station = "user:onyourwave" if radio else ""
        player.radio_batch_id = "batch"
        player.radio_track_batches = {self.track.id: "batch"} if radio else {}
        player.playback_report = None
        player.state = {
            "position": 0,
            "duration": 180,
            "playing": True,
            "stopped": False,
            "liked": True,
            "disliked": False,
            "error": "",
        }
        player.liked_ids = {self.track.id}
        player.disliked_ids = set()
        player.queue_collection_key = ""
        player.queue_source = []
        player.collection_cache = {}
        player.active_library_cache_key = ""
        player.library_source = []
        player.library_results = []
        player.library_offset = 0
        player.library_revision = 0
        player.liked_rows = []
        player.liked_rows_at = 0
        player.queue_revision = 0
        player.operations = []
        player._enqueue_telemetry = lambda *operations: player.operations.extend(operations)
        player._save_state = lambda *args, **kwargs: None
        player.next_calls = 0
        player.next = lambda *args, **kwargs: setattr(
            player, "next_calls", player.next_calls + 1
        )
        return player

    @staticmethod
    def flush_telemetry(player):
        operations = player.operations
        player.operations = []
        for operation in operations:
            operation()

    def make_audio_player(self, radio=False):
        player = self.make_player(radio=radio)
        player.control_lock = threading.RLock()
        player.session_generation = 1
        player.queue_generation = 1
        player.play_generation = 5
        player.completed_generation = -1
        player.queue_artist_id = ""
        player.queue_artist_has_more = False
        player.queue_extending = False
        player.preferences = {"audioQuality": "best", "playbackMode": "repeatQueue"}
        player.audio_cache = Mock()
        player.audio_cache.lookup.return_value = None
        player.preload_candidate = None
        player.prepared_entry = None
        player.active_entry_id = 10
        player.active_cache_path = None
        player.mpv_events_connected = threading.Event()
        player.mpv_events_connected.set()
        player.had_file = True
        player.muted = False
        player._metadata = lambda track: {"title": str(track.id), "artist": "Artist",
                                           "trackId": str(track.id), "duration": 180}
        player._publish_mpris = lambda: None
        player._notify_track = lambda meta: None
        player._maybe_extend_radio = lambda: None
        player._maybe_extend_collection = lambda: None
        player._wait_mpv_ready = lambda: None
        player.commands = []
        def command(command, *args):
            player.commands.append(command)
            if command[-1] == "playlist": return [{"id": 10, "playing": True}]
            if command[-1] == "time-pos": return .1
            return None
        player._mpv_command = command
        return player

    @staticmethod
    def immediate_threads():
        return patch.object(backend.threading, "Thread",
            side_effect=lambda target, daemon: SimpleNamespace(start=target))

    def test_ready_cache_starts_without_audio_network_request(self):
        player = self.make_audio_player()
        player.audio_cache.lookup.return_value = Path("/tmp/ready.audio")
        player._url = Mock(side_effect=AssertionError("network must not be used"))
        with self.immediate_threads(): player._play_current()
        self.assertIn(["loadfile", "/tmp/ready.audio", "replace"], player.commands)
        player._url.assert_not_called()
        self.assertTrue(player.state["playing"])

    def test_local_open_failure_invalidates_cache_then_uses_network(self):
        player = self.make_audio_player()
        cached = Path("/tmp/corrupt.audio")
        player.audio_cache.lookup.return_value = cached
        player._wait_mpv_ready = Mock(side_effect=[RuntimeError("broken audio"), None])
        player._url = Mock(return_value="https://audio.test/fresh")
        with self.immediate_threads(): player._play_current()
        player.audio_cache.invalidate.assert_called_once_with(cached)
        self.assertEqual([c for c in player.commands if c[0] == "loadfile"], [
            ["loadfile", str(cached), "replace"], ["loadfile", "https://audio.test/fresh", "replace"]])
        self.assertEqual(player.next_calls, 0)

    def test_network_fallback_preserves_initial_url_seek_and_pause(self):
        player = self.make_audio_player()
        player._url = Mock(side_effect=AssertionError("prepared URL must be used"))
        with self.immediate_threads():
            player._play_current(initial_url="https://audio.test/initial", resume_position=35,
                                 start_paused=True)
        self.assertIn(["loadfile", "https://audio.test/initial", "replace"], player.commands)
        self.assertIn(["seek", 35, "absolute"], player.commands)
        self.assertIn(["set_property", "pause", True], player.commands)
        self.assertFalse(player.state["playing"])

    def test_stop_cancels_a_loader_that_has_not_started(self):
        player = self.make_audio_player()
        workers = []
        with patch.object(backend.threading, "Thread", side_effect=lambda target, daemon:
                          SimpleNamespace(start=lambda: workers.append(target))):
            player._play_current()
        player.stop()
        workers[0]()
        self.assertFalse(any(c[0] == "loadfile" for c in player.commands))
        self.assertTrue(player.state["stopped"])
        player.audio_cache.cancel.assert_called()
        player.audio_cache.protect.assert_called_with(set())

    def test_stale_url_resolution_cannot_play_after_stop(self):
        player = self.make_audio_player()
        def url(*args, **kwargs):
            player.stop()
            return "https://audio.test/stale"
        player._url = url
        with self.immediate_threads(): player._play_current()
        self.assertFalse(any(c[0] == "loadfile" for c in player.commands))

    def test_shuffle_uses_the_preselected_candidate_for_manual_next(self):
        player = self.make_audio_player()
        player.queue.extend([SimpleNamespace(id="43"), SimpleNamespace(id="44")])
        player.preferences["playbackMode"] = "shuffle"
        player._play_current = Mock()
        del player.next
        with patch.object(backend.random, "choice", return_value=2) as choose:
            player._schedule_preload()
            self.assertEqual(player.preload_candidate["index"], 2)
            player.next()
        self.assertEqual(player.index, 2)
        self.assertEqual(choose.call_count, 1)

    def test_next_policy_covers_modes_queue_boundaries_and_detached_track(self):
        player = self.make_audio_player()
        player.queue.append(SimpleNamespace(id="43"))
        player.preferences["playbackMode"] = "repeatTrack"
        self.assertEqual(player._next_target_locked(True), 0)
        self.assertEqual(player._next_target_locked(False), 1)
        player.detached_track = self.track
        self.assertEqual(player._next_target_locked(True), 1)
        player.detached_track = None
        player.index = 1
        for mode, expected in (("order", "end"), ("repeatQueue", 0), ("repeatTrack", 1)):
            player.preferences["playbackMode"] = mode
            self.assertEqual(player._next_target_locked(True), expected)
        player.preferences["playbackMode"] = "order"
        player.queue_source = [object()]
        self.assertEqual(player._next_target_locked(True), "collection")
        player.queue_source = []
        player.queue_artist_id = "artist"
        player.queue_artist_has_more = True
        self.assertEqual(player._next_target_locked(True), "artist")
        player.radio_station = "station"
        self.assertEqual(player._next_target_locked(True), "radio")

    def prepare_entry(self, player):
        next_track = SimpleNamespace(id="43", duration_ms=180_000, albums=[SimpleNamespace(id="7")])
        player.queue.append(next_track)
        player.prepared_entry = {"signature": player._preload_signature_locked(), "index": 1,
                                 "id": 11, "path": Path("/tmp/next.audio"), "track": next_track}
        return next_track

    def test_eof_and_file_loaded_commit_once_without_loadfile_replace(self):
        player = self.make_audio_player(radio=True)
        self.prepare_entry(player)
        player.state.update(position=179, positionObservedAt=backend.time.time())
        player._begin_playback_reporting(self.track)
        player._mpv_end_file({"event": "end-file", "playlist_entry_id": 10, "reason": "eof"})
        self.assertEqual(player.index, 0)
        with self.immediate_threads(): player._mpv_file_loaded(11)
        player._mpv_file_loaded(11)
        player._complete_playback(5)
        self.flush_telemetry(player)
        self.assertEqual(player.index, 1)
        self.assertEqual(player.state["trackId"], "43")
        self.assertEqual(player.next_calls, 0)
        self.assertFalse(any(c[0] == "loadfile" for c in player.commands))
        self.assertEqual([c[0] for c in player.client.calls],
                         ["play_audio", "started", "play_audio", "finished", "play_audio", "started"])

    def test_event_and_monitor_cannot_advance_the_same_generation_twice(self):
        player = self.make_audio_player()
        player.state.update(position=179, positionObservedAt=backend.time.time())
        event = {"playlist_entry_id": 10, "reason": "eof"}
        player._mpv_end_file(event)
        player._mpv_end_file(event)
        player._complete_playback(5)
        self.assertEqual(player.next_calls, 1)

    def test_premature_eof_recovers_stream_without_false_skip_or_finish(self):
        player = self.make_audio_player(radio=True)
        self.prepare_entry(player)
        player._play_current = Mock()
        player.state.update(position=35, positionObservedAt=backend.time.time())
        player._begin_playback_reporting(self.track)
        player._mpv_end_file({"playlist_entry_id": 10, "reason": "eof"})
        player._play_current.assert_called_once_with(resume_position=35, start_paused=False)
        self.assertIsNotNone(player.playback_report)
        self.assertEqual(player.next_calls, 0)

    def test_prepared_file_error_falls_back_to_network_for_same_track(self):
        player = self.make_audio_player()
        self.prepare_entry(player)
        player._play_current = Mock()
        player._mpv_end_file({"playlist_entry_id": 11, "reason": "error"})
        player.audio_cache.invalidate.assert_called_once_with(Path("/tmp/next.audio"))
        self.assertEqual(player.index, 1)
        player._play_current.assert_called_once_with()
        self.assertEqual(player.next_calls, 0)

    def test_rapid_manual_next_ignores_late_file_loaded_for_previous_choice(self):
        player = self.make_audio_player()
        self.prepare_entry(player)
        player.queue.append(SimpleNamespace(id="44"))
        player._play_current = Mock()
        del player.next
        player.next()
        player.next()
        player._mpv_file_loaded(11)
        self.assertEqual(player.index, 2)
        self.assertIsNone(player.prepared_entry)
        player._play_current.assert_called_once_with()

    def test_stop_ignores_queued_mpv_events_and_extension_completion(self):
        player = self.make_audio_player()
        self.prepare_entry(player)
        generation = player.queue_generation
        player._play_current = Mock()
        player.stop()
        player._mpv_file_loaded(11)
        player._mpv_end_file({"playlist_entry_id": 10, "reason": "eof"})
        player._continue_extended(generation)
        player._play_current.assert_not_called()
        self.assertTrue(player.state["stopped"])

    def test_shutdown_keeps_position_and_auto_resume_state(self):
        player = self.make_audio_player()
        self.prepare_entry(player)
        player.state.update(position=35, playing=True, stopped=False)
        saved = []
        player._save_state = lambda *args: saved.append(dict(player.state))
        player.shutdown()
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0]["position"], 35)
        self.assertTrue(saved[0]["playing"])
        self.assertFalse(saved[0]["stopped"])
        self.assertIsNone(player.prepared_entry)
        player.audio_cache.close.assert_called_once_with()
        self.assertIn(["quit"], player.commands)

    def test_background_rate_limit_is_not_retried_and_does_not_change_ui(self):
        player = self.make_audio_player()
        self.track.get_download_info = Mock(side_effect=RuntimeError("HTTP 429"))
        with self.assertRaisesRegex(RuntimeError, "429"):
            player._audio_source(self.track, background=True)
        self.assertEqual(self.track.get_download_info.call_count, 1)
        self.assertNotIn("loadingStage", player.state)
        player.api_lock.acquire()
        try:
            with self.assertRaisesRegex(RuntimeError, "foreground"):
                player._audio_source(self.track, background=True)
        finally: player.api_lock.release()
        self.assertEqual(self.track.get_download_info.call_count, 1)

    def test_quality_and_queue_changes_invalidate_preload_callbacks(self):
        player = self.make_audio_player()
        player.queue.append(SimpleNamespace(id="43"))
        player._schedule_preload()
        first_request = player.audio_cache.schedule.call_args.args[0][0]
        self.assertTrue(first_request.valid())
        with patch.object(backend, "atomic_json"):
            player.set_preference("audioQuality", "economy")
        self.assertFalse(first_request.valid())
        request = player.audio_cache.schedule.call_args.args[0][0]
        self.assertEqual(request.identity.quality, "economy")
        player.queue_generation += 1
        self.assertFalse(request.valid())

    def test_previous_uses_previous_index_and_cancels_prepared_track(self):
        player = self.make_audio_player()
        self.prepare_entry(player)
        player.index = 1
        player._play_current = Mock()
        player.previous()
        self.assertEqual(player.index, 0)
        player._play_current.assert_called_once_with()

    def test_ready_preload_is_installed_after_event_connection_recovers(self):
        player = self.make_audio_player()
        player.queue.append(SimpleNamespace(id="43"))
        player.mpv_events_connected.clear()
        player._schedule_preload()
        request = player.audio_cache.schedule.call_args.args[0][0]
        request.ready(Path("/tmp/ready-next.audio"))
        self.assertFalse(any(c[0] == "loadfile" for c in player.commands))
        player.mpv_events_connected.set()
        player._schedule_preload()
        self.assertIn(["loadfile", "/tmp/ready-next.audio", "append"], player.commands)

    def test_logout_invalidates_session_and_clears_account_audio(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(backend, "PREFERENCES_FILE", Path(temporary) / "preferences.json"), \
                 patch.object(backend, "TOKEN_FILE", Path(temporary) / "token.json"), \
                 patch.object(backend, "STATE_FILE", Path(temporary) / "state.json"), \
                 patch.object(backend, "AudioCache", return_value=Mock()), \
                 patch.object(backend, "MprisBridge", return_value=Mock()), \
                 patch.object(backend.threading, "Thread", return_value=SimpleNamespace(start=lambda: None)):
                player = backend.Player()
                player.client = SimpleNamespace(account_uid="account-7")
                player._mpv_command = lambda *args: None
                player._save_state = lambda *args: None
                session = player.session_generation
                player.logout()
                self.assertGreater(player.session_generation, session)
                self.assertIsNone(player.client)
                self.assertTrue(player.state["stopped"])
                player.audio_cache.clear_account.assert_called_once_with("account-7")

    def test_play_pause_restarts_current_track_after_stop(self):
        player = self.make_player(radio=False)
        player.play_calls = 0
        player._mpv_command = lambda command: command[-1] == "idle-active"
        player._play_current = lambda: setattr(
            player, "play_calls", player.play_calls + 1
        )

        player.pause()

        self.assertEqual(player.play_calls, 1)

    def test_stop_releases_stream_and_keeps_track_ready_from_start(self):
        player = self.make_player(radio=False)
        player.state["position"] = 42
        player.had_file = True
        player.active_ticks = 3
        commands = []
        player._finish_playback_reporting = lambda **kwargs: None
        player._mpv_command = lambda command, *args: commands.append(command)
        player._publish_mpris = lambda: None

        player.stop()

        self.assertEqual(commands, [["stop"]])
        self.assertFalse(player.state["playing"])
        self.assertTrue(player.state["stopped"])
        self.assertEqual(player.state["position"], 0)
        self.assertFalse(player.had_file)
        self.assertEqual(player.active_ticks, 0)
        self.assertEqual(player.index, 0)

    def test_best_effort_api_does_not_retry_or_change_loading_state(self):
        player = self.make_player()
        player.state["loadingStage"] = "audioStream"
        attempts = 0

        def rate_limited():
            nonlocal attempts
            attempts += 1
            raise RuntimeError("HTTP 429 too-many-requests")

        with self.assertRaisesRegex(RuntimeError, "временно ограничила запросы"):
            player._api_call(
                rate_limited, retry_rate_limit=False, update_loading=False
            )

        self.assertEqual(attempts, 1)
        self.assertEqual(player.state["loadingStage"], "audioStream")


    def test_audio_url_variants_cycle_through_sorted_alternatives(self):
        player = self.make_player(radio=False)
        player.preferences = {"audioQuality": "best"}
        infos = [
            SimpleNamespace(codec="aac", bitrate_in_kbps=192, direct_link="aac-192"),
            SimpleNamespace(codec="mp3", bitrate_in_kbps=320, direct_link="mp3-320"),
            SimpleNamespace(codec="flac", bitrate_in_kbps=1000, direct_link="flac-1000"),
        ]
        self.track.get_download_info = lambda **kwargs: list(infos)

        urls = [player._url(self.track, variant=attempt) for attempt in range(4)]

        self.assertEqual(urls, ["mp3-320", "aac-192", "flac-1000", "mp3-320"])

    def test_stalled_audio_variants_are_cancelled_before_advancing(self):
        player = self.make_player(radio=False)
        player.queue.append(SimpleNamespace(id="43", duration_ms=180_000, albums=[]))
        player.play_generation = 0
        player.consecutive_failures = 0
        player.muted = False
        player._metadata = lambda track: {"title": "Track", "artist": "Artist"}
        player._url = lambda track, variant=0: f"variant-{variant}"
        commands = []
        player._mpv_command = lambda command, *args: commands.append(command)
        player._wait_mpv_ready = lambda: (_ for _ in ()).throw(
            RuntimeError("stream timeout"))
        errors = []
        player._set_error = errors.append

        with patch.object(
                backend.threading, "Thread",
                side_effect=lambda target, daemon: SimpleNamespace(start=target)):
            player._play_current()

        self.assertEqual(
            [command for command in commands if command[0] == "loadfile"],
            [["loadfile", f"variant-{index}", "replace"] for index in range(3)],
        )
        self.assertEqual(
            [command for command in commands if command[0] == "stop"],
            [["stop"], ["stop"], ["stop"]],
        )
        self.assertEqual(player.next_calls, 1)
        self.assertEqual(errors, [])

    def run_monitor_once(self, player):
        def sleep_once(_):
            if sleep_once.called: raise KeyboardInterrupt
            sleep_once.called = True
        sleep_once.called = False
        with patch.object(backend.time, "sleep", side_effect=sleep_once), \
             patch.object(backend, "MPV_SOCKET", SimpleNamespace(exists=lambda: True)):
            with self.assertRaises(KeyboardInterrupt):
                player._monitor()

    def test_wave_loading_does_not_block_automatic_next_on_idle(self):
        player = self.make_player()
        player.mpv = SimpleNamespace(poll=lambda: None)
        player.had_file = True
        player.active_ticks = 3
        player.last_playback_progress_at = backend.time.monotonic()
        player.state.update(loading=True, loadingKind="wave", position=178)
        player._mpv_command = lambda command, *args: command[-1] == "idle-active"

        self.run_monitor_once(player)

        self.assertEqual(player.next_calls, 1)

    def test_monitor_recognizes_playback_before_three_seconds(self):
        player = self.make_player()
        player.mpv = SimpleNamespace(poll=lambda: None)
        player.had_file = False
        player.active_ticks = 0
        player.last_playback_position = 0.0
        player.last_playback_progress_at = backend.time.monotonic()
        player.state.update(loading=False, loadingKind="")
        player.volume = 70
        player.muted = False
        player._publish_mpris = lambda: None
        values = {"idle-active": False, "pause": False, "time-pos": 1,
                  "duration": 180, "volume": 70, "mute": False}
        player._mpv_command = lambda command, *args: values[command[-1]]

        self.run_monitor_once(player)

        self.assertTrue(player.had_file)

    def test_stalled_active_stream_is_reopened_without_skipping(self):
        player = self.make_player()
        player.mpv = SimpleNamespace(poll=lambda: None)
        player.had_file = True
        player.active_ticks = 3
        player.last_playback_position = 35.0
        player.last_playback_progress_at = backend.time.monotonic() - backend.AUDIO_STALL_TIMEOUT - 1
        player.state.update(loading=False, loadingKind="", position=35)
        player.volume = 70
        player.muted = False
        reopened = []
        player._play_current = lambda **kwargs: reopened.append(kwargs)
        values = {"idle-active": False, "pause": False, "time-pos": 35,
                  "duration": 180, "volume": 70, "mute": False}
        player._mpv_command = lambda command, *args: values[command[-1]]

        self.run_monitor_once(player)

        self.assertEqual(reopened, [{"resume_position": 35}])
        self.assertEqual(player.next_calls, 0)

    def make_radio_prefetch_player(self):
        player = self.make_audio_player(radio=True)
        del player._maybe_extend_radio
        player.queue = [SimpleNamespace(id=str(i), duration_ms=180_000)
                        for i in range(42, 47)]
        player.radio_track_batches = {track.id: "batch" for track in player.queue}
        player.radio_extending = False
        player.radio_advance_pending = False
        player.telemetry_queue = queue.Queue()
        player.state.update(loading=False, loadingKind="")
        player.client.radio_result = SimpleNamespace(
            sequence=[SimpleNamespace(track=SimpleNamespace(id=str(i), duration_ms=180_000))
                      for i in range(47, 52)], batch_id="next-batch")
        return player

    def test_entering_last_radio_track_prefetches_batch_and_prepares_next_audio(self):
        for manual in (False, True):
            with self.subTest(manual=manual):
                player = self.make_radio_prefetch_player()
                player.index = 3
                with self.immediate_threads():
                    player._activate_track(player.queue[3], player.play_generation)
                self.assertFalse(any(call[0] == "radio_tracks" for call in player.client.calls))
                player.prepared_entry = {
                    "signature": player._preload_signature_locked(), "index": 4,
                    "id": 11, "path": Path("/tmp/fifth.audio"), "track": player.queue[4]}
                if manual:
                    del player.next
                    player.next()
                with self.immediate_threads():
                    player._mpv_file_loaded(11)

                self.assertEqual(player.index, 4)
                self.assertEqual(len(player.queue), 10)
                self.assertEqual(player.state["trackId"], "46")
                self.assertFalse(player.state["loading"])
                radio_calls = [call for call in player.client.calls if call[0] == "radio_tracks"]
                self.assertEqual(radio_calls, [("radio_tracks", "user:onyourwave", {"queue": "46"})])
                self.assertEqual(player.radio_track_batches["47"], "next-batch")
                requests = player.audio_cache.schedule.call_args.args[0]
                self.assertEqual(player.preload_candidate["index"], 5)
                self.assertTrue(requests[0].valid())
                requests[0].ready(Path("/tmp/sixth.audio"))
                self.assertEqual(player.prepared_entry["index"], 5)
                self.assertEqual(player.prepared_entry["track"].id, "47")
                self.assertIn(["loadfile", "/tmp/sixth.audio", "append"], player.commands)

    def test_radio_prefetch_coalesces_and_advances_if_next_is_requested_while_loading(self):
        player = self.make_radio_prefetch_player()
        player.index = 4
        pending = []
        player._play_current = Mock()
        del player.next
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=lambda: pending.append(target))):
            player._maybe_extend_radio()
            player._maybe_extend_radio()
            self.assertFalse(player.state["loading"])
            player.next()
        self.assertEqual(len(pending), 1)
        pending[0]()
        self.assertEqual(player.index, 5)
        self.assertEqual(len(player.queue), 10)
        self.assertFalse(player.radio_extending)
        player._play_current.assert_called_once_with()

    def test_radio_prefetch_ignores_result_after_queue_is_replaced(self):
        player = self.make_radio_prefetch_player()
        player.index = 4
        pending = []
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=lambda: pending.append(target))):
            player._maybe_extend_radio()
        player.queue_generation += 1
        player.queue = [self.track]
        player.radio_station = ""
        pending[0]()
        self.assertEqual(player.queue, [self.track])
        player.audio_cache.schedule.assert_not_called()

    def test_radio_prefetch_does_not_extend_regular_queue_or_detached_track(self):
        player = self.make_radio_prefetch_player()
        player.index = 4
        player._extend_radio = Mock()
        player.detached_track = self.track
        player._maybe_extend_radio()
        player.detached_track = None
        player.radio_station = ""
        player._maybe_extend_radio()
        player._extend_radio.assert_not_called()

    def test_radio_batch_hands_loading_to_next_track(self):
        player = self.make_player()
        player.queue_generation = 0
        player.radio_extending = False
        player.radio_advance_pending = False
        player.telemetry_queue = queue.Queue()
        player.state.update(loading=True, loadingKind="wave", loadingStage="")
        next_track = SimpleNamespace(id="43", duration_ms=120_000)
        getattr(player, "client").radio_result = SimpleNamespace(
            sequence=[SimpleNamespace(track=next_track)], batch_id="next-batch")
        observed = []

        def play_current(resume_position=0, start_paused=False, initial_url=""):
            observed.append((player.state["loadingKind"], player.index,
                             player.queue_revision, len(player.queue)))
            player.state.update(loading=False, loadingKind="", loadingStage="")

        player._play_current = play_current
        with patch.object(backend.threading, "Thread",
                          side_effect=lambda target, daemon: SimpleNamespace(start=target)):
            player._extend_radio(advance=True)

        self.assertEqual(observed, [("track", 1, 1, 2)])
        self.assertFalse(player.state["loading"])
        self.assertEqual(player.state["loadingKind"], "")
        self.assertEqual(player.radio_track_batches["43"], "next-batch")

    def test_radio_start_uses_best_effort_queue(self):
        player = self.make_player()
        player._report_radio_started("user:onyourwave", "batch")
        self.flush_telemetry(player)

        self.assertEqual(player.client.calls[0][0], "radio_started")
        self.assertEqual(player.client.calls[0][2]["from_"], backend.RADIO_REPORT_FROM)
        self.assertEqual(player.client.calls[0][2]["batch_id"], "batch")

    def test_wave_start_and_skip_reporting_is_ordered(self):
        player = self.make_player()
        with patch.object(backend.time, "monotonic", side_effect=[10.0, 50.0]):
            player._begin_playback_reporting(self.track)
            self.flush_telemetry(player)
            player.state["position"] = 40
            player._finish_playback_reporting(finished=False)
            self.flush_telemetry(player)

        self.assertEqual(
            [call[0] for call in player.client.calls],
            ["play_audio", "started", "play_audio", "skip"],
        )
        end_report = player.client.calls[-2][2]
        self.assertEqual(end_report["total_played_seconds"], 5)
        self.assertEqual(end_report["end_position_seconds"], 40)
        self.assertEqual(
            player.client.calls[0][2]["play_id"], end_report["play_id"]
        )
        self.assertEqual(player.client.calls[-1][2]["batch_id"], "batch")

    def test_reopening_same_stream_does_not_report_a_second_start(self):
        player = self.make_player()
        with patch.object(backend.time, "monotonic", side_effect=[10.0, 11.0]):
            player._begin_playback_reporting(self.track)
            self.flush_telemetry(player)
            player._begin_playback_reporting(self.track)
            self.flush_telemetry(player)

        self.assertEqual(
            [call[0] for call in player.client.calls], ["play_audio", "started"]
        )
        self.assertEqual(player.playback_report["playedSeconds"], 1.0)

    def test_finished_track_reports_full_end_position(self):
        player = self.make_player()
        with patch.object(backend.time, "monotonic", side_effect=[10.0, 12.0]):
            player._begin_playback_reporting(self.track)
            self.flush_telemetry(player)
            player.state["position"] = 178
            player._finish_playback_reporting(finished=True)
            self.flush_telemetry(player)

        self.assertEqual(player.client.calls[-1][0], "finished")
        self.assertEqual(player.client.calls[-2][2]["end_position_seconds"], 180)

    def test_track_radio_uses_current_track_as_station_seed(self):
        player = self.make_player(radio=False)
        recommended = [SimpleNamespace(id="100"), SimpleNamespace(id="101")]
        player.client.radio_result = SimpleNamespace(
            sequence=[SimpleNamespace(track=track) for track in recommended],
            batch_id="radio-batch",
        )
        captured = {}

        def run_loading(operation, kind):
            captured["loadingKind"] = kind
            operation()

        def set_queue(tracks, name, station, batch_id):
            captured.update(
                tracks=tracks, name=name, station=station, batchId=batch_id
            )

        player._loading = run_loading
        player._set_queue = set_queue

        player.play_track_radio()

        self.assertEqual(captured["loadingKind"], "radio")
        self.assertEqual(captured["tracks"], recommended)
        self.assertEqual(captured["name"], "Радио по треку")
        self.assertEqual(captured["station"], "track:42")
        self.assertEqual(captured["batchId"], "radio-batch")
        self.assertEqual(player.client.calls, [("radio_tracks", "track:42", {})])

    def test_dislike_removes_like_and_advances_wave(self):
        player = self.make_player()
        player.toggle_dislike()

        self.assertEqual(player.disliked_ids, {"42"})
        self.assertEqual(player.liked_ids, set())
        self.assertFalse(player.state["liked"])
        self.assertTrue(player.state["disliked"])
        self.assertEqual(player.next_calls, 1)
        self.assertEqual(player.client.calls, [("dislike_add", "42")])

    def test_like_removes_dislike(self):
        player = self.make_player(radio=False)
        player.liked_ids = set()
        player.disliked_ids = {"42"}
        player.state.update(liked=False, disliked=True)
        player.toggle_like()

        self.assertEqual(player.liked_ids, {"42"})
        self.assertEqual(player.disliked_ids, set())
        self.assertTrue(player.state["liked"])
        self.assertFalse(player.state["disliked"])
        self.assertEqual(player.client.calls, [("like_add", "42")])

    def test_dislike_can_be_removed_without_advancing(self):
        player = self.make_player(radio=False)
        player.liked_ids = set()
        player.disliked_ids = {"42"}
        player.state.update(liked=False, disliked=True)
        player.toggle_dislike()

        self.assertEqual(player.disliked_ids, set())
        self.assertFalse(player.state["disliked"])
        self.assertEqual(player.next_calls, 0)
        self.assertEqual(player.client.calls, [("dislike_remove", "42")])


if __name__ == "__main__":
    unittest.main()
