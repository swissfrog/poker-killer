"""Parser and validation for mobile card entry."""

import re

from poker_logic import PokerLogic


SUIT_CODES = {
    "s": "spades", "♠": "spades",
    "h": "hearts", "♥": "hearts",
    "d": "diamonds", "♦": "diamonds",
    "c": "clubs", "♣": "clubs",
}
RANKS = set(PokerLogic.RANK_VALUES)


def parse_cards(text):
    """Parse tokens such as As Kh 10d 7c into PokerLogic card tuples."""
    tokens = (text or "").replace(",", " ").split()
    cards = []
    for token in tokens:
        token = token.strip()
        if len(token) < 2:
            raise ValueError("Karte '{}' ist unvollstaendig.".format(token))
        suit_code = token[-1]
        suit = SUIT_CODES.get(suit_code.lower(), SUIT_CODES.get(suit_code))
        rank_text = token[:-1].upper()
        rank = "10" if rank_text in ("T", "10") else rank_text
        if rank not in RANKS or suit is None:
            raise ValueError("Unbekannte Karte '{}'. Nutze z. B. As, Kh, 10d oder 7c.".format(token))
        cards.append((rank, suit))
    return cards


def validate_deal(hole_text, board_text):
    hole = parse_cards(hole_text)
    board = parse_cards(board_text)
    if len(hole) != 2:
        raise ValueError("Bitte genau zwei Hole Cards eintragen.")
    if len(board) not in (0, 3, 4, 5):
        raise ValueError("Das Board braucht 0 oder 3 bis 5 Karten.")
    PokerLogic.validate_cards(hole + board)
    return hole, board
