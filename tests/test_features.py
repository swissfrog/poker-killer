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
from card_correction import CardCorrectionUI
from poker_logic import PokerLogic
from poker_vision_assistant import Card
from android_app.card_input import parse_cards, validate_deal
from opponent_ranges import opening_range


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
            self.assertEqual(controls.proposed_bet, expected)
            self.assertEqual(controls.call_amount, 0)

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

    def test_hand_evaluator_ranks_categories_and_best_five_cards(self):
        royal = [
            Card("A", "hearts"), Card("K", "hearts"), Card("Q", "hearts"),
            Card("J", "hearts"), Card("10", "hearts"), Card("2", "clubs"),
            Card("3", "diamonds"),
        ]
        self.assertEqual(PokerLogic.evaluate_hand(royal), ("Straight Flush", 8))
        wheel = [Card("A", "clubs"), Card("2", "diamonds"), Card("3", "hearts"),
                 Card("4", "spades"), Card("5", "clubs")]
        self.assertEqual(PokerLogic.evaluate_hand(wheel), ("Straight", 4))
        two_trips = [
            Card("9", "hearts"), Card("9", "diamonds"), Card("9", "clubs"),
            Card("8", "hearts"), Card("8", "diamonds"), Card("8", "clubs"),
            Card("A", "spades"),
        ]
        self.assertEqual(PokerLogic.evaluate_hand(two_trips), ("Full House", 6))

    def test_hand_evaluator_rejects_duplicate_cards(self):
        cards = [Card("A", "spades"), Card("A", "spades")]
        with self.assertRaises(ValueError):
            PokerLogic.rank_hand(cards)

    def test_manual_card_correction_blocks_duplicates_and_requires_valid_board(self):
        editor = CardCorrectionUI(Card)
        self.assertTrue(editor.apply_card("player", 0, "A", "spades")[0])
        self.assertTrue(editor.apply_card("player", 1, "K", "hearts")[0])
        self.assertFalse(editor.apply_card("board", 0, "A", "spades")[0])
        self.assertTrue(editor.confirm())
        self.assertTrue(editor.apply_card("board", 0, "2", "clubs")[0])
        self.assertFalse(editor.confirm())

    def test_equity_is_reproducible_and_position_changes_call_margin(self):
        aces = [Card("A", "spades"), Card("A", "hearts")]
        equity_a = PokerLogic.calculate_equity(aces, [], samples=120)
        equity_b = PokerLogic.calculate_equity(aces, [], samples=120)
        self.assertEqual(equity_a, equity_b)
        self.assertGreater(equity_a[0], 0.70)
        with patch.object(PokerLogic, "calculate_equity", return_value=(0.22, 0.01)):
            early = PokerLogic.recommend(aces, [], 100, 25, "UTG")
            button = PokerLogic.recommend(aces, [], 100, 25, "BTN")
        self.assertIn("FOLD", early[0])
        self.assertIn("CALL", button[0])
        self.assertIn("Pot Odds", button[1])
        self.assertIn("BTN", button[1])

    def test_mobile_card_parser_accepts_short_and_unicode_suits(self):
        self.assertEqual(parse_cards("As Kh 10d 7c"), [
            ("A", "spades"), ("K", "hearts"), ("10", "diamonds"), ("7", "clubs")
        ])
        self.assertEqual(parse_cards("A♠ K♥"), [("A", "spades"), ("K", "hearts")])

    def test_mobile_deal_validation_rejects_duplicates_and_incomplete_board(self):
        with self.assertRaises(ValueError):
            validate_deal("As As", "")
        with self.assertRaises(ValueError):
            validate_deal("As Kh", "2c 3d")
        hole, board = validate_deal("As Kh", "2c 3d 4h")
        self.assertEqual(len(hole), 2)
        self.assertEqual(len(board), 3)

    def test_bundled_opening_ranges_cover_six_max_positions(self):
        for position in ("LJ", "HJ", "CO", "BTN", "SB"):
            hand_range = opening_range(position)
            self.assertTrue(hand_range)
            self.assertIn("AA", hand_range)
            self.assertTrue(all(0.0 < frequency <= 1.0 for frequency in hand_range.values()))
        with self.assertRaises(ValueError):
            opening_range("UTG")

    def test_equity_accepts_a_weighted_opponent_range(self):
        hero = [("K", "spades"), ("K", "hearts")]
        weighted_range = {"AA": 1.0}
        result_a = PokerLogic.calculate_equity(hero, [], samples=80, opponent_range=weighted_range)
        result_b = PokerLogic.calculate_equity(hero, [], samples=80, opponent_range=weighted_range)
        self.assertEqual(result_a, result_b)
        self.assertGreaterEqual(result_a[0], 0.0)
        self.assertLessEqual(result_a[0], 1.0)

    def test_recommendation_reuses_supplied_equity(self):
        cards = [Card("A", "spades"), Card("A", "hearts")]
        with patch.object(PokerLogic, "calculate_equity") as calculate:
            PokerLogic.recommend(cards, [], 100, 20, "BTN", equity_result=(0.6, 0.01))
            calculate.assert_not_called()


if __name__ == "__main__":
    unittest.main()

