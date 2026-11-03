"""Interaktives, nutzerdefiniertes 13x13 Preflop-Range-Raster."""

import json
from pathlib import Path

import cv2
import numpy as np


class PreflopRangeChart:
    RANKS = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]
    POSITIONS = ["UTG", "MP", "CO", "BTN", "SB", "BB"]
    WINDOW_NAME = "Preflop Range Chart"

    def __init__(self, path="preflop_ranges.json"):
        self.path = Path(path)
        self.position = "UTG"
        self.is_open = False
        self.ranges = self._load()

    def _load(self):
        if not self.path.exists():
            return {position: set() for position in self.POSITIONS}
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return {position: set(data.get(position, [])) for position in self.POSITIONS}
        except (OSError, json.JSONDecodeError, AttributeError):
            return {position: set() for position in self.POSITIONS}

    def _save(self):
        data = {position: sorted(self.ranges[position]) for position in self.POSITIONS}
        temporary_path = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary_path.replace(self.path)

    @classmethod
    def combo_at(cls, row, column):
        if row == column:
            return cls.RANKS[row] + cls.RANKS[column]
        if row < column:
            return cls.RANKS[row] + cls.RANKS[column] + "s"
        return cls.RANKS[column] + cls.RANKS[row] + "o"

    @staticmethod
    def _rank_symbol(rank):
        return "T" if rank == "10" else rank

    @classmethod
    def combo_for_cards(cls, cards):
        if len(cards) < 2:
            return None
        first, second = cards[:2]
        rank_a = cls._rank_symbol(first.rank)
        rank_b = cls._rank_symbol(second.rank)
        if rank_a not in cls.RANKS or rank_b not in cls.RANKS:
            return None
        if rank_a == rank_b:
            return rank_a + rank_b
        if cls.RANKS.index(rank_a) < cls.RANKS.index(rank_b):
            high, low = rank_a, rank_b
        else:
            high, low = rank_b, rank_a
        suited = first.suit == second.suit
        return high + low + ("s" if suited else "o")

    def toggle_combo(self, combo):
        current = self.ranges[self.position]
        if combo in current:
            current.remove(combo)
        else:
            current.add(combo)
        try:
            self._save()
        except OSError as exc:
            print("Range konnte nicht gespeichert werden: {}".format(exc))

    def set_position_index(self, index):
        if 0 <= index < len(self.POSITIONS):
            self.position = self.POSITIONS[index]

    def toggle_window(self):
        self.is_open = not self.is_open
        if self.is_open:
            cv2.namedWindow(self.WINDOW_NAME, cv2.WINDOW_NORMAL)
            cv2.setMouseCallback(self.WINDOW_NAME, self._on_mouse)
        else:
            cv2.destroyWindow(self.WINDOW_NAME)

    def _on_mouse(self, event, x, y, _flags, _param):
        if event != cv2.EVENT_LBUTTONDOWN:
            return
        left, top, cell_w, cell_h = 58, 104, 44, 28
        column = (x - left) // cell_w
        row = (y - top) // cell_h
        if 0 <= row < 13 and 0 <= column < 13:
            self.toggle_combo(self.combo_at(row, column))

    def render(self, player_cards=None):
        image = np.full((500, 700, 3), (30, 30, 30), dtype=np.uint8)
        cv2.putText(image, "Preflop Range - {}".format(self.position), (20, 32),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.75, (245, 245, 245), 2)
        cv2.putText(image, "Position wechseln: Tasten 1-6 | Zelle klicken: Range umschalten",
                    (20, 64), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (210, 210, 210), 1)
        cv2.putText(image, "Gruen = in eigener Range | aktuelle Hand gelb markiert",
                    (20, 86), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (210, 210, 210), 1)

        current_combo = self.combo_for_cards(player_cards or [])
        left, top, cell_w, cell_h = 58, 104, 44, 28
        for row in range(13):
            cv2.putText(image, self.RANKS[row], (28, top + row * cell_h + 19),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.43, (220, 220, 220), 1)
            cv2.putText(image, self.RANKS[row], (left + row * cell_w + 14, 98),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.43, (220, 220, 220), 1)
            for column in range(13):
                combo = self.combo_at(row, column)
                x1, y1 = left + column * cell_w, top + row * cell_h
                selected = combo in self.ranges[self.position]
                active_hand = combo == current_combo
                color = (40, 130, 45) if selected else (55, 55, 55)
                if active_hand:
                    color = (0, 180, 220)
                cv2.rectangle(image, (x1, y1), (x1 + cell_w - 2, y1 + cell_h - 2), color, -1)
                cv2.rectangle(image, (x1, y1), (x1 + cell_w - 2, y1 + cell_h - 2),
                              (105, 105, 105), 1)
                cv2.putText(image, combo, (x1 + 4, y1 + 19),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.38, (255, 255, 255), 1)
        count = len(self.ranges[self.position])
        cv2.putText(image, "{} Kombinationen in der eigenen Range".format(count), (20, 490),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, (235, 235, 235), 1)
        return image
