"""Manual card entry and correction UI for the OpenCV application."""

import cv2
import numpy as np


class CardCorrectionUI:
    WINDOW_NAME = "Karten pruefen und korrigieren"

    def __init__(self, card_class):
        self.card_class = card_class
        self.player_slots = [None, None]
        self.board_slots = [None, None, None, None, None]
        self.is_open = False
        self.confirmed = False
        self.status = "Karten pruefen und danach bestaetigen."

    @staticmethod
    def _same(card_a, card_b):
        return card_a is not None and card_b is not None and (
            card_a.rank, card_a.suit
        ) == (card_b.rank, card_b.suit)

    def load_cards(self, player_cards, community_cards):
        self.player_slots = [None, None]
        self.board_slots = [None, None, None, None, None]
        for index, card in enumerate(player_cards[:2]):
            self.player_slots[index] = card
        board = list(community_cards) + list(player_cards[2:])
        for index, card in enumerate(board[:5]):
            self.board_slots[index] = card
        self.confirmed = False
        self.status = "Kameraerkennung geladen; bitte pruefen und bestaetigen."

    def cards(self):
        return ([card for card in self.player_slots if card is not None],
                [card for card in self.board_slots if card is not None])

    def apply_card(self, zone, slot, rank, suit):
        slots = self.player_slots if zone == "player" else self.board_slots if zone == "board" else None
        if slots is None or not 0 <= slot < len(slots):
            return False, "Ungueltiger Bereich oder Kartenplatz."
        if rank not in self.card_class.RANKS or suit not in self.card_class.SUITS:
            return False, "Ungueltiger Kartenwert."
        candidate = self.card_class(rank, suit)
        for other_zone in (self.player_slots, self.board_slots):
            for index, existing in enumerate(other_zone):
                if other_zone is slots and index == slot:
                    continue
                if self._same(candidate, existing):
                    return False, "Diese Karte ist bereits eingetragen."
        slots[slot] = candidate
        self.confirmed = False
        self.status = "Karte gesetzt. Vor einer Empfehlung bitte bestaetigen."
        return True, self.status

    def clear_slot(self, zone, slot):
        slots = self.player_slots if zone == "player" else self.board_slots if zone == "board" else None
        if slots is None or not 0 <= slot < len(slots):
            return False
        slots[slot] = None
        self.confirmed = False
        self.status = "Kartenplatz geleert; bitte erneut bestaetigen."
        return True

    def confirm(self):
        player, board = self.cards()
        if len(player) != 2:
            self.status = "Bestaetigung abgelehnt: genau zwei Hole Cards benoetigt."
            self.confirmed = False
            return False
        if len(board) in (1, 2):
            self.status = "Bestaetigung abgelehnt: Board braucht 0 oder 3 bis 5 Karten."
            self.confirmed = False
            return False
        try:
            from poker_logic import PokerLogic
            PokerLogic.validate_cards(player + board)
        except ValueError as exc:
            self.status = "Bestaetigung abgelehnt: {}".format(exc)
            self.confirmed = False
            return False
        self.confirmed = True
        self.status = "Karten bestaetigt."
        return True

    def open(self, player_cards=None, community_cards=None):
        if not self.is_open:
            if player_cards is not None or community_cards is not None:
                self.load_cards(player_cards or [], community_cards or [])
            cv2.namedWindow(self.WINDOW_NAME, cv2.WINDOW_NORMAL)
            cv2.createTrackbar("Bereich 0=Hand 1=Board", self.WINDOW_NAME, 0, 1, lambda _v: None)
            cv2.createTrackbar("Platz", self.WINDOW_NAME, 0, 4, lambda _v: None)
            cv2.createTrackbar("Rang", self.WINDOW_NAME, 12, 12, lambda _v: None)
            cv2.createTrackbar("Farbe", self.WINDOW_NAME, 0, 3, lambda _v: None)
            cv2.setMouseCallback(self.WINDOW_NAME, self._on_mouse)
            self.is_open = True

    def close(self):
        if self.is_open:
            cv2.destroyWindow(self.WINDOW_NAME)
            self.is_open = False

    def _on_mouse(self, event, x, y, _flags, _param):
        if event != cv2.EVENT_LBUTTONDOWN or y < 255:
            return
        if 20 <= x < 175:
            zone_index = cv2.getTrackbarPos("Bereich 0=Hand 1=Board", self.WINDOW_NAME)
            zone = "board" if zone_index else "player"
            slot = cv2.getTrackbarPos("Platz", self.WINDOW_NAME)
            slot = min(slot, 4 if zone == "board" else 1)
            ranks = self.card_class.RANKS
            suits = self.card_class.SUITS
            rank_index = cv2.getTrackbarPos("Rang", self.WINDOW_NAME)
            suit_index = cv2.getTrackbarPos("Farbe", self.WINDOW_NAME)
            ok, message = self.apply_card(zone, slot, ranks[rank_index], suits[suit_index])
            self.status = message
        elif 185 <= x < 340:
            zone_index = cv2.getTrackbarPos("Bereich 0=Hand 1=Board", self.WINDOW_NAME)
            zone = "board" if zone_index else "player"
            slot = cv2.getTrackbarPos("Platz", self.WINDOW_NAME)
            slot = min(slot, 4 if zone == "board" else 1)
            self.clear_slot(zone, slot)
        elif 350 <= x < 510:
            self.confirm()

    def render(self):
        image = np.full((320, 720, 3), (32, 32, 32), dtype=np.uint8)
        cv2.putText(image, "Karten manuell pruefen / eintragen", (18, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, (245, 245, 245), 2)
        cv2.putText(image, "Bereich und Platz waehlen, Rang/Farbe einstellen, dann Taste druecken.",
                    (18, 62), cv2.FONT_HERSHEY_SIMPLEX, 0.43, (220, 220, 220), 1)
        player, board = self.cards()
        cv2.putText(image, "Hand (2): " + " ".join(str(card) for card in player), (20, 105),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (120, 240, 140), 1)
        cv2.putText(image, "Board (0 oder 3-5): " + " ".join(str(card) for card in board), (20, 135),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (120, 220, 240), 1)
        buttons = [(20, 175, "Setzen"), (185, 330, "Platz leeren"), (350, 510, "Bestaetigen")]
        for left, right, label in buttons:
            cv2.rectangle(image, (left, 260), (right, 302), (65, 95, 125), -1)
            cv2.putText(image, label, (left + 8, 287), cv2.FONT_HERSHEY_SIMPLEX, 0.48, (255, 255, 255), 1)
        cv2.putText(image, self.status, (20, 235), cv2.FONT_HERSHEY_SIMPLEX, 0.43,
                    (60, 230, 120) if self.confirmed else (0, 190, 240), 1)
        return image

    def show(self):
        if self.is_open:
            cv2.imshow(self.WINDOW_NAME, self.render())
