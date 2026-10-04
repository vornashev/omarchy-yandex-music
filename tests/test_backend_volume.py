import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from backend import backend


class VolumeCurveTests(unittest.TestCase):
    def test_low_percentages_map_to_audible_gain(self):
        for percent, gain in ((0, 0), (7, 20), (15, 32), (50, 66), (100, 100)):
            with self.subTest(percent=percent):
                self.assertAlmostEqual(backend.volume_percent_to_gain(percent), gain, delta=1)

    def test_every_ui_percentage_survives_a_round_trip_through_mpv(self):
        for percent in range(101):
            gain = backend.volume_percent_to_gain(percent)
            self.assertEqual(backend.gain_to_volume_percent(gain), percent)

    def test_out_of_range_values_are_clamped(self):
        self.assertEqual(backend.volume_percent_to_gain(-5), 0)
        self.assertEqual(backend.volume_percent_to_gain(150), 100)
        self.assertEqual(backend.gain_to_volume_percent(130), 100)


class VolumePreferenceTests(unittest.TestCase):
    def test_bar_volume_visibility_persists_without_changing_player_volume(self):
        with tempfile.TemporaryDirectory() as temporary:
            preferences_file = Path(temporary) / "preferences.json"
            preferences_file.write_text(json.dumps({"showControls": False}))
            with patch.object(backend, "PREFERENCES_FILE", preferences_file):
                player = backend.Player.__new__(backend.Player)
                player.lock = threading.RLock()
                player.preferences = player._load_preferences()
                player.state = {"volume": 37, "muted": True}

                # Existing installations retain their visible bar volume control.
                self.assertTrue(player.preferences["showVolume"])
                for value, expected in (("false", False), ("true", True)):
                    with self.subTest(value=value):
                        player.set_preference("showVolume", value)
                        self.assertIs(player.state["preferences"]["showVolume"], expected)
                        saved = json.loads(preferences_file.read_text())
                        self.assertIs(saved["showVolume"], expected)
                        restored = player._load_preferences()
                        self.assertIs(restored["showVolume"], expected)
                        self.assertFalse(restored["showControls"])
                        self.assertEqual(player.state["volume"], 37)
                        self.assertTrue(player.state["muted"])


if __name__ == "__main__":
    unittest.main()
