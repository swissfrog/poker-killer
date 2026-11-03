"""Opt-infaehige Erkennung einer kurzen, abwechselnden Kamerabewegung."""

import time

import cv2
import numpy as np


class ShakeResetDetector:
    def __init__(self, threshold=18.0, window_seconds=0.8, required_swings=3):
        self.threshold = threshold
        self.window_seconds = window_seconds
        self.required_swings = required_swings
        self.previous = None
        self.movements = []

    def update(self, frame):
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.resize(gray, (160, 120)).astype(np.float32)
        if self.previous is None:
            self.previous = gray
            return False
        shift, _response = cv2.phaseCorrelate(self.previous, gray)
        self.previous = gray
        dx, dy = shift
        magnitude = (dx * dx + dy * dy) ** 0.5
        now = time.monotonic()
        if magnitude >= self.threshold:
            axis = "x" if abs(dx) >= abs(dy) else "y"
            direction = 1 if (dx if axis == "x" else dy) > 0 else -1
            self.movements.append((now, axis, direction))
        self.movements = [item for item in self.movements if now - item[0] <= self.window_seconds]
        if len(self.movements) < self.required_swings:
            return False
        recent = self.movements[-self.required_swings:]
        alternating = all(
            recent[index][1] == recent[index - 1][1]
            and recent[index][2] != recent[index - 1][2]
            for index in range(1, len(recent))
        )
        if alternating:
            self.movements.clear()
            return True
        return False
