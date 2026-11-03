"""Texas Hold'em hand ranking and a reproducible equity estimate."""

from itertools import combinations
import math
import random


class PokerLogic:
    CATEGORY_NAMES = {
        8: "Straight Flush",
        7: "Four of a Kind",
        6: "Full House",
        5: "Flush",
        4: "Straight",
        3: "Three of a Kind",
        2: "Two Pair",
        1: "Pair",
        0: "High Card",
    }
    RANK_VALUES = {rank: value for value, rank in enumerate(
        ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"], 2
    )}
    SUITS = ("hearts", "diamonds", "clubs", "spades")

    @staticmethod
    def _parts(card):
        if isinstance(card, tuple) and len(card) == 2:
            return card[0], card[1]
        return card.rank, card.suit

    @classmethod
    def card_key(cls, card):
        rank, suit = cls._parts(card)
        if rank not in cls.RANK_VALUES or suit not in cls.SUITS:
            raise ValueError("Invalid card: {} {}".format(rank, suit))
        return rank, suit

    @classmethod
    def validate_cards(cls, cards):
        keys = [cls.card_key(card) for card in cards]
        if len(keys) != len(set(keys)):
            raise ValueError("Duplicate cards are not allowed")

    @classmethod
    def _rank_five(cls, cards):
        parts = [cls.card_key(card) for card in cards]
        values = [cls.RANK_VALUES[rank] for rank, _suit in parts]
        counts = {}
        for value in values:
            counts[value] = counts.get(value, 0) + 1
        groups = sorted(((count, value) for value, count in counts.items()), reverse=True)
        unique = sorted(set(values), reverse=True)
        flush = len(set(suit for _rank, suit in parts)) == 1
        straight_high = None
        if len(unique) == 5:
            if unique[0] - unique[-1] == 4:
                straight_high = unique[0]
            elif unique == [14, 5, 4, 3, 2]:
                straight_high = 5

        if flush and straight_high:
            return (8, straight_high)
        if groups[0][0] == 4:
            quad = groups[0][1]
            kicker = max(value for value in values if value != quad)
            return (7, quad, kicker)
        if groups[0][0] == 3 and groups[1][0] == 2:
            return (6, groups[0][1], groups[1][1])
        if flush:
            return (5,) + tuple(unique)
        if straight_high:
            return (4, straight_high)
        if groups[0][0] == 3:
            trips = groups[0][1]
            kickers = sorted((value for value in values if value != trips), reverse=True)
            return (3, trips) + tuple(kickers)
        pairs = sorted((value for value, count in counts.items() if count == 2), reverse=True)
        if len(pairs) == 2:
            kicker = next(value for value, count in counts.items() if count == 1)
            return (2, pairs[0], pairs[1], kicker)
        if len(pairs) == 1:
            pair = pairs[0]
            kickers = sorted((value for value in values if value != pair), reverse=True)
            return (1, pair) + tuple(kickers)
        return (0,) + tuple(unique)

    @classmethod
    def rank_hand(cls, cards):
        """Return a lexicographically comparable rank for 2–7 distinct cards."""
        if not 2 <= len(cards) <= 7:
            raise ValueError("A hand must contain between 2 and 7 cards")
        cls.validate_cards(cards)
        if len(cards) >= 5:
            return max(cls._rank_five(combo) for combo in combinations(cards, 5))
        parts = [cls.card_key(card) for card in cards]
        values = [cls.RANK_VALUES[rank] for rank, _suit in parts]
        counts = {}
        for value in values:
            counts[value] = counts.get(value, 0) + 1
        groups = sorted(((count, value) for value, count in counts.items()), reverse=True)
        if groups[0][0] == 4:
            quad = groups[0][1]
            kickers = [value for value in values if value != quad]
            return (7, quad, max(kickers) if kickers else 0)
        if groups[0][0] == 3:
            return (3, groups[0][1]) + tuple(sorted((v for v in values if v != groups[0][1]), reverse=True))
        pairs = sorted((value for value, count in counts.items() if count == 2), reverse=True)
        if len(pairs) == 2:
            return (2, pairs[0], pairs[1])
        if len(pairs) == 1:
            return (1, pairs[0]) + tuple(sorted((v for v in values if v != pairs[0]), reverse=True))
        return (0,) + tuple(sorted(values, reverse=True))

    @classmethod
    def evaluate_hand(cls, cards):
        rank = cls.rank_hand(cards)
        return cls.CATEGORY_NAMES[rank[0]], rank[0]

    @classmethod
    def best_five(cls, cards):
        if not 2 <= len(cards) <= 7:
            raise ValueError("A hand must contain between 2 and 7 cards")
        cls.validate_cards(cards)
        if len(cards) < 5:
            return list(cards)
        return list(max(combinations(cards, 5), key=cls._rank_five))

    @classmethod
    def calculate_equity(cls, hole_cards, community_cards, samples=600):
        """Monte Carlo equity versus a uniformly random opponent hand."""
        if len(hole_cards) != 2:
            raise ValueError("Exactly two hole cards are required")
        if len(community_cards) not in (0, 3, 4, 5):
            raise ValueError("Board must have 0, 3, 4, or 5 cards")
        known = list(hole_cards) + list(community_cards)
        cls.validate_cards(known)
        used = {cls.card_key(card) for card in known}
        deck = [(rank, suit) for rank in cls.RANK_VALUES for suit in cls.SUITS if (rank, suit) not in used]
        seed_text = "|".join("{}{}".format(*cls.card_key(card)) for card in known)
        seed = sum((index + 1) * ord(char) for index, char in enumerate(seed_text))
        rng = random.Random(seed)
        wins = ties = 0
        runout_count = 5 - len(community_cards)
        for _ in range(max(1, samples)):
            draw = rng.sample(deck, 2 + runout_count)
            opponent = draw[:2]
            final_board = list(community_cards) + draw[2:]
            hero_rank = cls.rank_hand(list(hole_cards) + final_board)
            opponent_rank = cls.rank_hand(opponent + final_board)
            if hero_rank > opponent_rank:
                wins += 1
            elif hero_rank == opponent_rank:
                ties += 1
        equity = (wins + ties * 0.5) / float(max(1, samples))
        error = math.sqrt(equity * (1.0 - equity) / max(1, samples))
        return equity, error

    @classmethod
    def recommend(cls, hole_cards, community_cards, pot_size, call_amount, position):
        """Explain a pot-odds decision under a random-opponent assumption."""
        equity, error = cls.calculate_equity(hole_cards, community_cards)
        pot = max(0.0, float(pot_size))
        call = max(0.0, float(call_amount))
        if call == 0:
            action = "CHECK AVAILABLE"
            reason = "Kein Call-Einsatz; kein Raise wird ohne weitere Tischdaten empfohlen. Position: {}; Zufallsgegner-Equity {:.1f}% +/- {:.1f}%.".format(
                position, equity * 100, error * 100
            )
        else:
            pot_odds = call / (pot + call) if pot + call else 1.0
            margin = {"UTG": 0.04, "MP": 0.03, "CO": 0.02, "BTN": 0.0, "SB": 0.02, "BB": 0.01}.get(position, 0.02)
            action = "CALL (heuristisch)" if equity >= pot_odds + margin else "FOLD (heuristisch)"
            reason = "Pot Odds {:.1f}%; {}-Equity {:.1f}% +/- {:.1f}%; Position {} (Puffer {:.1f}%). Rake nicht enthalten.".format(
                pot_odds * 100, "Zufallsgegner", equity * 100, error * 100, position, margin * 100
            )
        return action, reason
