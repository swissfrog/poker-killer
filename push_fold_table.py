"""Viewer fuer importierte Push/Fold-Tabellen. Es werden keine Nash-Daten erfunden."""

import json
from pathlib import Path

import cv2
import numpy as np


class PushFoldTable:
    WINDOW_NAME = "Push/Fold Tabelle"
    POSITIONS = ["UTG", "MP", "CO", "BTN", "SB", "BB"]
    STACKS = [5, 10, 15, 20, 25]

    def __init__(self, path="push_fold_tables.json"):
        self.path = Path(path)
        self.position = "UTG"
        self.stack_bb = 10
        self.is_open = False
        self.tables = self._load()

    def _load(self):
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except (OSError, json.JSONDecodeError):
            return {}

    def reload(self):
        self.tables = self._load()

    def set_position_index(self, index):
        if 0 <= index < len(self.POSITIONS):
            self.position = self.POSITIONS[index]

    def set_stack_index(self, index):
        if 0 <= index < len(self.STACKS):
            self.stack_bb = self.STACKS[index]

    def cycle_stack(self, direction):
        index = self.STACKS.index(self.stack_bb)
        self.stack_bb = self.STACKS[(index + direction) % len(self.STACKS)]

    def toggle_window(self):
        self.is_open = not self.is_open
        if self.is_open:
            cv2.namedWindow(self.WINDOW_NAME, cv2.WINDOW_NORMAL)
        else:
            cv2.destroyWindow(self.WINDOW_NAME)

    def _entry(self):
        position_table = self.tables.get(self.position, {})
        return position_table.get(str(self.stack_bb), position_table.get(self.stack_bb))

    def render(self, player_cards=None):
        image = np.full((520, 620, 3), (30, 30, 30), dtype=np.uint8)
        cv2.putText(image, "Push/Fold - {} | {} BB".format(self.position, self.stack_bb),
                    (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.72, (245, 245, 245), 2)
        cv2.putText(image, "Position: 1-6 | Stack: Q/W/E/R/T (5/10/15/20/25 BB)",
                    (20, 68), cv2.FONT_HERSHEY_SIMPLEX, 0.43, (210, 210, 210), 1)
        cv2.putText(image, "Datenquelle: push_fold_tables.json; ohne Datei keine Nash-Aussage",
                    (20, 94), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 190, 230), 1)
        entry = self._entry()
        if not isinstance(entry, dict):
            cv2.putText(image, "Keine Tabelle fuer diese Position/Stacktiefe geladen.",
                        (20, 155), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (235, 235, 235), 1)
            cv2.putText(image, "Add push_fold_tables.json with position/stack entries.",
                        (20, 190), cv2.FONT_HERSHEY_SIMPLEX, 0.43, (190, 190, 190), 1)
            return image
        push = set(entry.get("push", []))
        call = set(entry.get("call", []))
        cv2.putText(image, "Push: {}".format(", ".join(sorted(push)) or "—"),
                    (20, 135), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (90, 230, 120), 1)
        cv2.putText(image, "Call: {}".format(", ".join(sorted(call)) or "—"),
                    (20, 158), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (100, 190, 250), 1)
        current = PreflopCombo.combo(player_cards or [])
        left, top, cell_w, cell_h = 35, 205, 42, 24
        for row in range(13):
            for column in range(13):
                combo = PreflopCombo.at(row, column)
                x, y = left + column * cell_w, top + row * cell_h
                color = (50, 130, 55) if combo in push else (45, 105, 150) if combo in call else (55, 55, 55)
                if combo == current:
                    color = (0, 180, 220)
                cv2.rectangle(image, (x, y), (x + cell_w - 2, y + cell_h - 2), color, -1)
                cv2.putText(image, combo, (x + 3, y + 16), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (255,255,255), 1)
        return image


class PreflopCombo:
    RANKS = ["A", "K", "Q", "J", "T", "9", "8", "7", "6", "5", "4", "3", "2"]

    @classmethod
    def at(cls, row, column):
        if row == column:
            return cls.RANKS[row] * 2
        if row < column:
            return cls.RANKS[row] + cls.RANKS[column] + "s"
        return cls.RANKS[column] + cls.RANKS[row] + "o"

    @classmethod
    def combo(cls, cards):
        if len(cards) < 2:
            return None
        a, b = cards[:2]
        r1, r2 = ("T" if a.rank == "10" else a.rank), ("T" if b.rank == "10" else b.rank)
        if r1 not in cls.RANKS or r2 not in cls.RANKS:
            return None
        if r1 == r2:
            return r1 * 2
        high, low = sorted((r1, r2), key=cls.RANKS.index)
        return high + low + ("s" if a.suit == b.suit else "o")
