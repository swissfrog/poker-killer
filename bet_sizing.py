"""Pot-relative Bet-Sizing-Regler und anklickbare Presets."""

import cv2
import numpy as np


class BetSizingControls:
    WINDOW_NAME = "Bet Sizing"

    def __init__(self):
        self.is_open = False
        self.pot_size = 100
        self.current_bet = 0
        self.selected_fraction = None

    def toggle_window(self):
        self.is_open = not self.is_open
        if self.is_open:
            cv2.namedWindow(self.WINDOW_NAME, cv2.WINDOW_NORMAL)
            cv2.createTrackbar("Pot", self.WINDOW_NAME, self.pot_size, 10000, self._pot_changed)
            cv2.createTrackbar("Current bet", self.WINDOW_NAME, self.current_bet, 10000, self._bet_changed)
            cv2.setMouseCallback(self.WINDOW_NAME, self._on_mouse)
        else:
            cv2.destroyWindow(self.WINDOW_NAME)

    def _pot_changed(self, value):
        self.pot_size = max(0, value)
        if self.selected_fraction is not None:
            self.current_bet = int(round(self.pot_size * self.selected_fraction))

    def _bet_changed(self, value):
        self.current_bet = max(0, value)
        self.selected_fraction = None

    def _on_mouse(self, event, x, y, _flags, _param):
        if event != cv2.EVENT_LBUTTONDOWN or y < 160:
            return
        buttons = [(20, 1 / 3, "1/3 Pot"), (135, 1 / 2, "1/2 Pot"),
                   (250, 2 / 3, "2/3 Pot"), (365, 1.0, "Pot")]
        for left, fraction, _label in buttons:
            if left <= x <= left + 100:
                self.selected_fraction = fraction
                self.current_bet = int(round(self.pot_size * fraction))
                break

    def values(self):
        if self.is_open:
            self.pot_size = cv2.getTrackbarPos("Pot", self.WINDOW_NAME)
            if self.selected_fraction is None:
                self.current_bet = cv2.getTrackbarPos("Current bet", self.WINDOW_NAME)
            else:
                self.current_bet = int(round(self.pot_size * self.selected_fraction))
        return float(self.pot_size), float(self.current_bet)

    def render(self):
        if not self.is_open:
            return
        image = np.full((220, 500, 3), (35, 35, 35), dtype=np.uint8)
        labels = [(20, "1/3 Pot"), (135, "1/2 Pot"), (250, "2/3 Pot"), (365, "Pot")]
        for left, label in labels:
            cv2.rectangle(image, (left, 165), (left + 100, 205), (75, 95, 125), -1)
            cv2.putText(image, label, (left + 7, 191), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (255, 255, 255), 1)
        pot, bet = self.values()
        cv2.putText(image, "Ausgewaehlter Einsatz: {:.0f}".format(bet), (20, 145),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (245, 245, 245), 1)
        cv2.imshow(self.WINDOW_NAME, image)
