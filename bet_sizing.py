"""Call amount input and pot-relative bet-size presets."""

import cv2
import numpy as np


class BetSizingControls:
    WINDOW_NAME = "Bet Sizing"

    def __init__(self):
        self.is_open = False
        self.pot_size = 100
        self.call_amount = 0
        self.proposed_bet = 0
        self.selected_fraction = None

    def toggle_window(self):
        self.is_open = not self.is_open
        if self.is_open:
            cv2.namedWindow(self.WINDOW_NAME, cv2.WINDOW_NORMAL)
            cv2.createTrackbar("Pot", self.WINDOW_NAME, self.pot_size, 10000, self._pot_changed)
            cv2.createTrackbar("Call amount", self.WINDOW_NAME, self.call_amount, 10000, self._call_changed)
            cv2.setMouseCallback(self.WINDOW_NAME, self._on_mouse)
        else:
            cv2.destroyWindow(self.WINDOW_NAME)

    def _pot_changed(self, value):
        self.pot_size = max(0, value)
        if self.selected_fraction is not None:
            self.proposed_bet = int(round(self.pot_size * self.selected_fraction))

    def _call_changed(self, value):
        self.call_amount = max(0, value)

    def _on_mouse(self, event, x, y, _flags, _param):
        if event != cv2.EVENT_LBUTTONDOWN or y < 160:
            return
        buttons = [(20, 1 / 3, "1/3 Pot"), (135, 1 / 2, "1/2 Pot"),
                   (250, 2 / 3, "2/3 Pot"), (365, 1.0, "Pot")]
        for left, fraction, _label in buttons:
            if left <= x <= left + 100:
                self.selected_fraction = fraction
                self.proposed_bet = int(round(self.pot_size * fraction))
                break

    def values(self):
        if self.is_open:
            self.pot_size = cv2.getTrackbarPos("Pot", self.WINDOW_NAME)
            self.call_amount = cv2.getTrackbarPos("Call amount", self.WINDOW_NAME)
            if self.selected_fraction is not None:
                self.proposed_bet = int(round(self.pot_size * self.selected_fraction))
        return float(self.pot_size), float(self.call_amount)

    def render(self):
        if not self.is_open:
            return
        image = np.full((220, 500, 3), (35, 35, 35), dtype=np.uint8)
        labels = [(20, "1/3 Pot"), (135, "1/2 Pot"), (250, "2/3 Pot"), (365, "Pot")]
        for left, label in labels:
            cv2.rectangle(image, (left, 165), (left + 100, 205), (75, 95, 125), -1)
            cv2.putText(image, label, (left + 7, 191), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (255, 255, 255), 1)
        pot, call = self.values()
        cv2.putText(image, "Pot {:.0f} | Call {:.0f} | Bet-Preset {:.0f}".format(
            pot, call, self.proposed_bet), (20, 145),
            cv2.FONT_HERSHEY_SIMPLEX, 0.47, (245, 245, 245), 1)
        cv2.imshow(self.WINDOW_NAME, image)
