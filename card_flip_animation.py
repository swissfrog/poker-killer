"""Kleine OpenCV-Karten-Reveal-Animation fuer neue Erkennungen."""

import math
import time

import cv2


class CardFlipAnimation:
    def __init__(self, duration=0.55):
        self.duration = duration
        self.signature = None
        self.started_at = 0.0

    def update(self, cards):
        signature = tuple(str(card) for card in cards)
        if signature != self.signature:
            self.signature = signature
            self.started_at = time.monotonic()

    def draw(self, frame, cards, x=20, y=150):
        self.update(cards)
        elapsed = time.monotonic() - self.started_at
        progress = min(1.0, elapsed / self.duration) if cards else 1.0
        width = max(4, int(76 * abs(math.cos(progress * math.pi))))
        for index, card in enumerate(cards[:5]):
            left = x + index * 86
            cv2.rectangle(frame, (left, y), (left + width, y + 88), (235, 235, 230), -1)
            if progress > 0.5:
                cv2.putText(frame, str(card), (left + 8, y + 53),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.8, (40, 40, 40), 2)
