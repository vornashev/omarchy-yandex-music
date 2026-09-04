import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

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
