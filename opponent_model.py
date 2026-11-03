"""Manuelles Gegnerprofil mit VPIP/PFR-Reglern."""

import cv2


class OpponentModel:
    def __init__(self):
        self.window_name = "Gegnerprofil (manuelle Schaetzung)"
        self._created = False

    def create_controls(self):
        if self._created:
            return
        cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
        cv2.createTrackbar("VPIP %", self.window_name, 25, 100, lambda _value: None)
        cv2.createTrackbar("PFR %", self.window_name, 18, 100, lambda _value: None)
        self._created = True

    def values(self):
        self.create_controls()
        vpip = cv2.getTrackbarPos("VPIP %", self.window_name)
        pfr = min(cv2.getTrackbarPos("PFR %", self.window_name), vpip)
        return vpip, pfr

    def summary(self):
        vpip, pfr = self.values()
        style = "loose" if vpip >= 35 else "tight" if vpip < 20 else "mittel"
        if vpip == 0:
            aggression = "keine PFR-Daten"
        else:
            ratio = pfr / float(vpip)
            aggression = "aggressiv" if ratio >= 0.65 else "passiv" if ratio <= 0.35 else "ausgeglichen"
        return "Manuelles Profil: {} / {} (VPIP {}%, PFR {}%)".format(
            style, aggression, vpip, pfr
        )
