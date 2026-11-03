import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

try:
    import cv2
except ImportError:
    # Lightweight fallback so the data/logic tests can run without camera libraries.
    import sys
    import types
    cv2 = types.ModuleType("cv2")
    cv2.EVENT_LBUTTONDOWN = 1
    cv2.COLOR_BGR2GRAY = 0
    cv2.cvtColor = lambda frame, _code: frame.mean(axis=2).astype(np.uint8)
    cv2.resize = lambda frame, _size: frame
    cv2.phaseCorrelate = lambda _first, _second: ((0.0, 0.0), 1.0)
    sys.modules["cv2"] = cv2

from bet_sizing import BetSizingControls
from card_flip_animation import CardFlipAnimation
from hand_history import HandHistory
from opponent_model import OpponentModel
from preflop_range_chart import PreflopRangeChart
from push_fold_table import PushFoldTable
from shake_reset import ShakeResetDetector
import poker_vision_assistant


class FakeCard:
    def __init__(self, rank, suit):
        self.rank = rank
        self.suit = suit

    def __str__(self):
        return self.rank + self.suit


class FeatureTests(unittest.TestCase):
    def test_hand_history_waits_for_stable_state_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "history.json"
            history = HandHistory(path=str(path), stable_frames=3)
            cards = [FakeCard("A", "s"), FakeCard("K", "s")]
            self.assertFalse(history.observe(cards, [], 20, 0, "CHECK"))
            self.assertFalse(history.observe(cards, [], 20, 0, "CHECK"))
            self.assertTrue(history.observe(cards, [], 20, 0, "CHECK"))
            self.assertFalse(history.observe(cards, [], 20, 0, "CHECK"))
            saved = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(len(saved), 1)
            self.assertEqual(saved[0]["player_cards"], ["As", "Ks"])

    def test_preflop_grid_combo_conventions_and_persistence(self):
        self.assertEqual(PreflopRangeChart.combo_at(0, 0), "AA")
        self.assertEqual(PreflopRangeChart.combo_at(0, 1), "AKs")
        self.assertEqual(PreflopRangeChart.combo_at(1, 0), "AKo")
        self.assertEqual(PreflopRangeChart.combo_for_cards(
            [FakeCard("A", "spades"), FakeCard("K", "spades")]
        ), "AKs")
        self.assertEqual(PreflopRangeChart.combo_for_cards(
            [FakeCard("A", "spades"), FakeCard("K", "hearts")]
        ), "AKo")
        with tempfile.TemporaryDirectory() as directory:
            chart = PreflopRangeChart(str(Path(directory) / "ranges.json"))
            chart.toggle_combo("AKs")
            loaded = PreflopRangeChart(str(Path(directory) / "ranges.json"))
            self.assertIn("AKs", loaded.ranges["UTG"])

    def test_opponent_profile_summary_is_manual_and_categorized(self):
        model = OpponentModel()
        with patch.object(model, "values", return_value=(40, 10)):
            self.assertIn("loose / passiv", model.summary())

    def test_bet_size_presets_calculate_fraction_of_pot(self):
        controls = BetSizingControls()
        controls.pot_size = 300
        for x, expected in [(30, 100), (150, 150), (260, 200), (380, 300)]:
            controls._on_mouse(cv2.EVENT_LBUTTONDOWN, x, 170, 0, None)
            self.assertEqual(controls.current_bet, expected)

    def test_push_fold_table_loads_user_data_by_position_and_stack(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "push_fold_tables.json"
            path.write_text(json.dumps({"BTN": {"10": {"push": ["A5s"], "call": ["99"]}}}),
                            encoding="utf-8")
            viewer = PushFoldTable(str(path))
            viewer.set_position_index(3)
            viewer.stack_bb = 10
            self.assertEqual(viewer._entry()["push"], ["A5s"])
            self.assertEqual(viewer._entry()["call"], ["99"])

    def test_card_flip_animation_tracks_card_changes(self):
        animation = CardFlipAnimation()
        with patch("card_flip_animation.time.monotonic", return_value=10.0):
            animation.update([FakeCard("A", "s")])
        self.assertEqual(animation.signature, ("As",))
        self.assertEqual(animation.started_at, 10.0)

    def test_shake_detector_does_not_reset_on_static_camera(self):
        detector = ShakeResetDetector()
        frame = np.zeros((120, 160, 3), dtype=np.uint8)
        self.assertFalse(detector.update(frame))
        self.assertFalse(detector.update(frame))


if __name__ == "__main__":
    unittest.main()

