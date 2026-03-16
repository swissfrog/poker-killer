#!/usr/bin/env python3
"""
Texas Hold'em Poker Vision Assistant
====================================

Ein Poker-Assistent für Texas Hold'em mit:
- Kamera-Overlay
- Texas Hold'em spezifische Logik
- Hand-Rang Berechnung
- Sprachempfehlungen (TTS)

Autor: PokerBot
"""

import cv2
import numpy as np
import threading
import time
from typing import List, Tuple, Optional, Dict
from collections import Counter

# Farben
COLOR_BG = (20, 20, 30)
COLOR_PRIMARY = (0, 180, 255)      # Blau
COLOR_SUCCESS = (0, 255, 100)       # Grün
COLOR_WARNING = (255, 200, 0)      # Gelb
COLOR_DANGER = (255, 50, 80)       # Rot
COLOR_TEXT = (255, 255, 255)


class Card:
    """Eine Spielkarte für Texas Hold'em"""
    RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    RANK_VALUES = {r: v for v, r in enumerate(RANKS)}
    
    def __init__(self, rank: str, suit: str):
        self.rank = rank
        self.suit = suit  # hearts, diamonds, clubs, spades
    
    def __str__(self):
        suit_symbols = {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'}
        return f"{self.rank}{suit_symbols.get(self.suit, '?')}"
    
    def __repr__(self):
        return self.__str__()
    
    @property
    def value(self) -> int:
        return self.RANK_VALUES[self.rank]
    
    @property
    def is_red(self) -> bool:
        return self.suit in ['hearts', 'diamonds']


class TexasHoldemHand:
    """Texas Hold'em Hand-Bewertung"""
    
    HAND_RANGS = [
        "High Card", "Pair", "Two Pair", "Three of a Kind",
        "Straight", "Flush", "Full House", "Four of a Kind",
        "Straight Flush", "Royal Flush"
    ]
    
    @staticmethod
    def evaluate(cards: List[Card]) -> Tuple[int, str, List[int]]:
        """
        Bewertet die beste 5-Karten Hand aus 7 Karten (2 hole + 5 community)
        Returns: (rank_index, hand_name, tie_breakers)
        """
        if len(cards) < 2:
            return (0, "Start Hand", [])
        
        # Brauche mindestens 5 Karten für eine vollständige Hand
        if len(cards) < 5:
            return (0, f"({len(cards)} Karten)", [])
        
        # Alle 5-Karten Kombinationen durchgehen
        best_hand = (0, "High Card", [])
        
        from itertools import combinations
        
        for combo in combinations(cards, 5):
            combo_list = list(combo)
            rank, name, tie = TexasHoldemHand._evaluate_5_cards(combo_list)
            
            if rank > best_hand[0]:
                best_hand = (rank, name, tie)
        
        return best_hand
    
    @staticmethod
    def _evaluate_5_cards(cards: List[Card]) -> Tuple[int, str, List[int]]:
        """Bewertet 5 spezifische Karten"""
        ranks = [c.value for c in cards]
        suits = [c.suit for c in cards]
        
        rank_counts = Counter(ranks)
        suit_counts = Counter(suits)
        
        is_flush = len(suit_counts) == 1
        
        # Check for straight
        unique_ranks = sorted(set(ranks))
        is_straight = False
        if len(unique_ranks) == 5:
            # Normal straight
            if unique_ranks[4] - unique_ranks[0] == 4:
                is_straight = True
            # Wheel (A-2-3-4-5)
            elif set([12, 0, 1, 2, 3]).issubset(set(ranks)):
                is_straight = True
                unique_ranks = [3, 2, 1, 0, 12]  # 5-4-3-2-A
        
        # Royal Flush
        if is_flush and is_straight and min(unique_ranks) >= 8:
            return (9, "Royal Flush", [max(ranks)])
        
        # Straight Flush
        if is_flush and is_straight:
            return (8, "Straight Flush", [max(unique_ranks)])
        
        # Four of a Kind
        if 4 in rank_counts.values():
            quad_rank = [r for r, c in rank_counts.items() if c == 4][0]
            kicker = max([r for r in ranks if r != quad_rank])
            return (7, "Four of a Kind", [quad_rank, kicker])
        
        # Full House
        if 3 in rank_counts.values() and 2 in rank_counts.values():
            trips_rank = [r for r, c in rank_counts.items() if c == 3][0]
            pair_rank = [r for r, c in rank_counts.items() if c == 2][0]
            return (6, "Full House", [trips_rank, pair_rank])
        
        # Flush
        if is_flush:
            return (5, "Flush", sorted(ranks, reverse=True))
        
        # Straight
        if is_straight:
            return (4, "Straight", [max(unique_ranks)])
        
        # Three of a Kind
        if 3 in rank_counts.values():
            trips_rank = [r for r, c in rank_counts.items() if c == 3][0]
            kickers = sorted([r for r in ranks if r != trips_rank], reverse=True)
            return (3, "Three of a Kind", [trips_rank] + kickers[:2])
        
        # Two Pair
        pairs = sorted([r for r, c in rank_counts.items() if c == 2], reverse=True)
        if len(pairs) >= 2:
            kicker = max([r for r in ranks if r not in pairs])
            return (2, "Two Pair", [pairs[0], pairs[1], kicker])
        
        # Pair
        if 2 in rank_counts.values():
            pair_rank = [r for r, c in rank_counts.items() if c == 2][0]
            kickers = sorted([r for r in ranks if r != pair_rank], reverse=True)
            return (1, "Pair", [pair_rank] + kickers[:3])
        
        # High Card
        return (0, "High Card", sorted(ranks, reverse=True))
    
    @staticmethod
    def get_starter_hand_strength(cards: List[Card]) -> float:
        """Bewertet Starthand-Stärke (Pre-Flop)"""
        if len(cards) != 2:
            return 0.0
        
        v1, v2 = cards[0].value, cards[1].value
        suited = cards[0].suit == cards[1].suit
        
        # Pocket Pairs
        if v1 == v2:
            if v1 >= 10:  # JJ-AA
                return 0.95
            elif v1 >= 8:  # TT
                return 0.85
            else:
                return 0.70 + (v1 * 0.02)
        
        # High cards
        high = max(v1, v2)
        low = min(v1, v2)
        
        # Suited connectors
        if suited:
            if high >= 10:
                return 0.75
            elif high >= 8:
                return 0.60
            else:
                return 0.45
        
        # Offsuit
        if high >= 11:  # AK, AQ, AJ
            return 0.65
        elif high >= 10:
            return 0.55
        else:
            return 0.35


class PokerAssistant:
    """Texas Hold'em Poker Assistant"""
    
    def __init__(self):
        # Kamera
        self.cap = cv2.VideoCapture(0)
        if not self.cap.isOpened():
            print("❌ Keine Kamera gefunden!")
            import sys
            sys.exit(1)
        
        # Texas Hold'em State
        self.hole_cards: List[Card] = []      # Die 2 Karten des Spielers
        self.community_cards: List[Card] = []  # Die 5 Tischkarten
        self.current_street = "preflop"  # preflop, flop, turn, river
        
        # Bewertung
        self.hand_rank = 0
        self.hand_name = ""
        self.hand_strength = 0.0
        self.recommendation = ""
        
        # TTS
        self.tts_enabled = True
        self.last_speak_time = 0
        
        # Demo
        self.demo_cards = self._create_demo_deck()
        self.demo_index = 0
        
        # Initialisiere TTS
        self._init_tts()
        
        self.running = True
    
    def _create_demo_deck(self) -> List[Card]:
        """Erstellt ein Demo-Deck"""
        suits = ['hearts', 'diamonds', 'clubs', 'spades']
        ranks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6']
        deck = []
        for s in suits:
            for r in ranks:
                deck.append(Card(r, s))
        return deck
    
    def _init_tts(self):
        """Initialisiert Sprachausgabe"""
        self.tts_engine = None
        try:
            import pyttsx3
            self.tts_engine = pyttsx3.init()
            self.tts_engine.setProperty('rate', 160)
            self.tts_engine.setProperty('volume', 0.9)
            print("✅ TTS aktiviert")
        except Exception as e:
            print(f"⚠️ TTS nicht verfügbar: {e}")
            self.tts_enabled = False
    
    def _speak(self, text: str):
        """Spricht Text"""
        if not self.tts_enabled or not self.tts_engine:
            return
        
        now = time.time()
        if now - self.last_speak_time < 4:
            return
        
        self.last_speak_time = now
        
        def speak_async():
            try:
                self.tts_engine.say(text)
                self.tts_engine.runAndWait()
            except:
                pass
        
        thread = threading.Thread(target=speak_async, daemon=True)
        thread.start()
    
    def _update_hand_evaluation(self):
        """Aktualisiert die Hand-Bewertung"""
        all_cards = self.hole_cards + self.community_cards
        
        if len(self.hole_cards) < 2:
            self.hand_name = "Warte auf Karten"
            self.hand_rank = -1
            self.hand_strength = TexasHoldemHand.get_starter_hand_strength(self.hole_cards)
            self.recommendation = "WARTE"
            return
        
        # Pre-Flop: Nur Starthand
        if len(self.community_cards) == 0:
            self.hand_name = "Pre-Flop"
            self.hand_rank = -1
            self.hand_strength = TexasHoldemHand.get_starter_hand_strength(self.hole_cards)
        
        # Post-Flop: Volle Bewertung
        else:
            self.hand_rank, self.hand_name, _ = TexasHoldemHand.evaluate(all_cards)
            self.hand_strength = 0.5 + (self.hand_rank * 0.1)
            if len(self.community_cards) >= 3:
                self.hand_strength += 0.1
        
        # Empfehlung basierend auf Hand
        self._update_recommendation()
    
    def _update_recommendation(self):
        """Aktualisiert die Spielempfehlung"""
        s = self.hand_strength
        
        if len(self.hole_cards) < 2:
            self.recommendation = "WARTE"
            return
        
        # Street-spezifisch
        street = len(self.community_cards)
        
        if street == 0:  # Pre-Flop
            if s > 0.75:
                self.recommendation = "RAISE"
                self._speak("Erhöhe")
            elif s > 0.50:
                self.recommendation = "CALL"
                self._speak("Mitgehen")
            else:
                self.recommendation = "FOLD"
                self._speak("Passen")
        
        elif street < 5:  # Flop/Turn
            if self.hand_rank >= 6:  # Full House+
                self.recommendation = "RAISE"
                self._speak("Erhöhe stark")
            elif self.hand_rank >= 3:  # Trips+
                self.recommendation = "BET"
                self._speak("Setze")
            elif s > 0.6:
                self.recommendation = "CALL"
                self._speak("Mitgehen")
            elif s > 0.4:
                self.recommendation = "CHECK"
                self._speak("Bleiben")
            else:
                self.recommendation = "FOLD"
                self._speak("Passen")
        
        else:  # River
            if self.hand_rank >= 4:
                self.recommendation = "VALUE BET"
                self._speak("Setze auf Wert")
            elif s > 0.5:
                self.recommendation = "CALL"
                self._speak("Mitgehen")
            else:
                self.recommendation = "FOLD"
                self._speak("Passen")
    
    def _add_demo_card(self):
        """Fügt Demo-Karte hinzu"""
        if len(self.hole_cards) < 2:
            card = self.demo_cards[self.demo_index]
            self.hole_cards.append(card)
            self._speak("Karte ${card.rank}")
        
        elif len(self.community_cards) < 5:
            card = self.demo_cards[self.demo_index + 2]
            self.community_cards.append(card)
            street_names = {0: "Flop", 3: "Turn", 4: "River"}
            self._speak(street_names.get(len(self.community_cards), "Karte"))
        
        else:
            # Reset
            self.hole_cards = []
            self.community_cards = []
            self.demo_index = (self.demo_index + 7) % len(self.demo_cards)
            self._speak("Neue Hand")
        
        self.demo_index = (self.demo_index + 1) % len(self.demo_cards)
        self._update_hand_evaluation()
    
    def _reset(self):
        """Setzt alles zurück"""
        self.hole_cards = []
        self.community_cards = []
        self.hand_rank = 0
        self.hand_name = ""
        self.hand_strength = 0.0
        self.recommendation = ""
        self._speak("Zurückgesetzt")
    
    def _draw_card(self, frame, x, y, card: Card):
        """Zeichnet eine Karte"""
        cw, ch = 55, 80
        
        # Hintergrund
        color = (180, 50, 50) if card.is_red else (40, 55, 80)
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), color, -1)
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), COLOR_TEXT, 1)
        
        # Rank
        cv2.putText(frame, card.rank, (x + 12, y + 20), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 2)
        
        # Suit
        suit_symbols = {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'}
        suit_char = suit_symbols.get(card.suit, '?')
        cv2.putText(frame, suit_char, (x + 22, y + 55), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_TEXT, 2)
    
    def _draw_overlay(self, frame):
        """Zeichnet das Overlay"""
        h, w = frame.shape[:2]
        
        # ====== HEADER ======
        cv2.rectangle(frame, (0, 0), (w, 60), COLOR_BG, -1)
        cv2.putText(frame, "♠️ TEXAS HOLD'EM", (20, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, COLOR_PRIMARY, 2)
        
        # Street Anzeige
        street_names = {0: "PRE-FLOP", 3: "FLOP", 4: "TURN", 5: "RIVER"}
        street = street_names.get(len(self.community_cards), "??")
        cv2.putText(frame, f"  {street}", (w - 180, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_WARNING, 2)
        
        # ====== HOLE CARDS (Spieler) ======
        card_y = h - 180
        
        if self.hole_cards:
            cv2.rectangle(frame, (20, card_y - 30), (200, h - 50), COLOR_BG, -1)
            cv2.putText(frame, "YOUR HAND", (30, card_y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
            
            for i, card in enumerate(self.hole_cards):
                self._draw_card(frame, 40 + i * 70, card_y + 15, card)
        else:
            cv2.rectangle(frame, (20, card_y - 30), (200, h - 50), COLOR_BG, -1)
            cv2.putText(frame, "YOUR HAND", (30, card_y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
            cv2.putText(frame, "Drücke [D]", (50, card_y + 50), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (100, 100, 100), 1)
        
        # ====== COMMUNITY CARDS (Tisch) ======
        if self.community_cards:
            comm_y = h - 300
            cv2.rectangle(frame, (20, comm_y - 30), (w - 20, comm_y + 70), COLOR_BG, -1)
            cv2.putText(frame, "COMMUNITY", (30, comm_y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
            
            # Zeige bis zu 5 Karten
            for i, card in enumerate(self.community_cards[:5]):
                x = 150 + i * 80
                self._draw_card(frame, x, comm_y + 15, card)
        
        # ====== HAND RANK ======
        if self.hand_name and self.hand_name != "Pre-Flop":
            rank_y = h - 340
            cv2.rectangle(frame, (20, rank_y - 25), (350, rank_y + 5), COLOR_BG, -1)
            cv2.putText(frame, f"HAND: {self.hand_name.upper()}", (30, rank_y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_SUCCESS, 1)
        
        # ====== EMPFEHLUNG ======
        box_w, box_h = 350, 100
        box_x = (w - box_w) // 2
        box_y = h // 2 - 50
        
        # Farbe
        if "RAISE" in self.recommendation or "BET" in self.recommendation:
            rec_color = COLOR_SUCCESS
        elif "CALL" in self.recommendation:
            rec_color = COLOR_PRIMARY
        elif "CHECK" in self.recommendation:
            rec_color = COLOR_WARNING
        elif "FOLD" in self.recommendation:
            rec_color = COLOR_DANGER
        else:
            rec_color = (80, 80, 80)
        
        cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), COLOR_BG, -1)
        cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), rec_color, 3)
        
        # Text
        text_size = cv2.getTextSize(self.recommendation, cv2.FONT_HERSHEY_SIMPLEX, 1.3, 3)[0]
        text_x = (w - text_size[0]) // 2
        cv2.putText(frame, self.recommendation, (text_x, box_y + 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 1.3, rec_color, 3)
        
        # Stärke
        strength_text = f"Stärke: {self.hand_strength*100:.0f}%"
        cv2.putText(frame, strength_text, (box_x + 20, box_y + 75), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        
        # ====== STATS ======
        stats_x = w - 220
        stats_y = 80
        stats = [
            f"Hole: {len(self.hole_cards)}/2",
            f"Tisch: {len(self.community_cards)}/5",
            f"TTS: {'AN' if self.tts_enabled else 'AUS'}",
        ]
        for i, stat in enumerate(stats):
            cv2.putText(frame, stat, (stats_x, stats_y + i*22), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150, 150, 150), 1)
        
        # ====== HINTS ======
        cv2.putText(frame, "[D] Karte | [R] Reset | [T] TTS | [Q] Beenden", 
                    (20, h - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (100, 100, 100), 1)
    
    def run(self):
        """Hauptschleife"""
        print("♠️ =====================================♠️")
        print("   TEXAS HOLD'EM POKER ASSISTANT")
        print("♠️ =====================================♠️")
        print("Steuerung:")
        print("  [D] - Demo: Karte hinzufügen")
        print("  [R] - Reset")
        print("  [T] - TTS an/aus")
        print("  [Q] - Beenden")
        print("======================================")
        
        while self.running:
            ret, frame = self.cap.read()
            if not ret:
                break
            
            frame = cv2.flip(frame, 1)
            self._draw_overlay(frame)
            
            cv2.imshow('♠️ Texas Hold\'em', frame)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                self.running = False
            elif key == ord('d'):
                self._add_demo_card()
            elif key == ord('r'):
                self._reset()
            elif key == ord('t'):
                self.tts_enabled = not self.tts_enabled
                self._speak("Sprache an" if self.tts_enabled else "Sprache aus")
        
        self._cleanup()
    
    def _cleanup(self):
        self.cap.release()
        cv2.destroyAllWindows()
        print("\n👋 Texas Hold'em beendet!")


def main():
    assistant = PokerAssistant()
    assistant.run()


if __name__ == "__main__":
    main()
