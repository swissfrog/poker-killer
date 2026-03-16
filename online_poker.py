#!/usr/bin/env python3
"""
Online Poker Vision Assistant
============================

Für Online-Poker optimiert:
- Kamera auf Bildschirm/Handy gerichtet
- Karten erkennen (auch bei verschiedenen Poker-Plattformen)
- Pot-Odds berechnen
- Position berücksichtigen
- Sprachausgabe für Heads-Up Play

Unterstützte Plattformen:
- PokerStars
- Partypoker
- GG Poker
- 888 Poker
- usw.

Autor: PokerBot
"""

import cv2
import numpy as np
import threading
import time
from typing import List, Tuple, Dict, Optional
from collections import Counter

# Farben für Overlay
COLOR_BG = (15, 15, 25)
COLOR_PRIMARY = (100, 180, 255)   # Blau
COLOR_SUCCESS = (50, 255, 120)   # Grün
COLOR_WARNING = (255, 200, 50)   # Gelb
COLOR_DANGER = (255, 80, 100)     # Rot
COLOR_TEXT = (240, 240, 240)


class OnlinePokerAssistant:
    """Online Poker Assistant - Optimiert für Bildschirm-Aufnahme"""
    
    def __init__(self):
        # Kamera
        print("📷 Initialisiere Kamera...")
        self.cap = cv2.VideoCapture(0)
        if not self.cap.isOpened():
            print("❌ Keine Kamera gefunden!")
            import sys
            sys.exit(1)
        
        # Konfiguriere Kamera für Screen-Aufnahme
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        
        # Poker State
        self.hero_cards: List = []      # Deine Karten
        self.board_cards: List = []      # Tischkarten
        self.pot_size: float = 0        # Pot-Größe
        self.current_bet: float = 0      # Dein Einsatz
        self.position: str = "UTG"       # Position am Tisch
        self.opponents: int = 6           # Anzahl Gegner
        
        # Berechnungen
        self.hand_strength: float = 0
        self.pot_odds: float = 0
        self.recommendation: str = ""
        self.ev: float = 0               # Erwartungswert
        
        # Street
        self.street: str = "preflop"      # preflop, flop, turn, river
        
        # TTS
        self.tts_enabled = True
        self.last_announce = 0
        
        # Demo
        self.demo_mode = True
        self.running = True
        
        # Init TTS
        self._init_tts()
        
        # Screen-Capture Einstellungen
        self.capture_mode = "screen"  # screen, phone
    
    def _init_tts(self):
        """Initialisiert Sprachausgabe"""
        self.tts = None
        try:
            import pyttsx3
            self.tts = pyttsx3.init()
            self.tts.setProperty('rate', 170)
            self.tts.setProperty('volume', 0.9)
            print("✅ TTS bereit")
        except:
            print("⚠️ TTS nicht verfügbar")
    
    def _speak(self, text: str, force: bool = False):
        """Spricht Text mit Cooldown"""
        if not self.tts_enabled or not self.tts:
            return
        
        now = time.time()
        if not force and now - self.last_announce < 5:
            return
        
        self.last_announce = now
        
        def talk():
            try:
                self.tts.say(text)
                self.tts.runAndWait()
            except:
                pass
        
        threading.Thread(target=talk, daemon=True).start()
    
    def _detect_cards_from_screen(self, frame) -> Tuple[List, List]:
        """
        Erkennt Karten vom Bildschirm
        Vereinfachte Version - in echt bräuchte man ML-Modell
        """
        # Für Demo: simuliere Erkennung
        return self.hero_cards, self.board_cards
    
    def _calculate_pot_odds(self) -> float:
        """Berechnet Pot-Odds"""
        if self.pot_size == 0:
            return 0
        
        if self.current_bet == 0:
            return 1.0  # Check
        
        return self.current_bet / (self.pot_size + self.current_bet)
    
    def _calculate_equity(self) -> float:
        """Berechnet Equity (Gewinnwahrscheinlichkeit)"""
        # Vereinfachte Berechnung
        base = 0.5
        
        # Karten-Stärke
        if len(self.hero_cards) == 2:
            # Premium-Hände
            ranks = [c[0] for c in self.hero_cards]
            if ranks[0] == ranks[1]:  # Pocket Pair
                if ranks[0] in ['A', 'K', 'Q', 'J']:
                    base += 0.35
                else:
                    base += 0.20
            
            # High Cards
            high = max([self._rank_value(r) for r in ranks])
            if high >= 12:  # AK
                base += 0.15
            elif high >= 11:  # AQ, AJ, KQ
                base += 0.10
        
        # Board-Bonus
        if len(self.board_cards) >= 3:
            base += 0.15
        if len(self.board_cards) >= 4:
            base += 0.10
        if len(self.board_cards) == 5:
            base += 0.05
        
        # Position-Bonus
        if self.position in ["BTN", "SB"]:
            base += 0.05
        
        # Gegner-Bonus (weniger Gegner = mehr Equity)
        base += (6 - self.opponents) * 0.02
        
        return min(base, 0.98)
    
    def _rank_value(self, rank: str) -> int:
        """Kartenwert"""
        values = {'2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
                 '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14}
        return values.get(rank, 0)
    
    def _make_recommendation(self):
        """Erstellt Spielempfehlung"""
        if len(self.hero_cards) < 2:
            self.recommendation = "WARTE"
            return
        
        equity = self._calculate_equity()
        pot_odds = self._calculate_pot_odds()
        self.hand_strength = equity
        self.pot_odds = pot_odds
        
        # Berechne Erwartungswert
        self.ev = equity - pot_odds
        
        street = len(self.board_cards)
        
        # Empfehlung basierend auf Equity vs Pot-Odds
        if self.ev > 0.15:
            if street == 0:
                self.recommendation = "RAISE 3x"
            else:
                self.recommendation = "BET POT"
            self._speak("Erhöhe")
        
        elif self.ev > 0:
            if street == 0:
                self.recommendation = "CALL"
            else:
                self.recommendation = "CHECK/CALL"
            self._speak("Mitgehen")
        
        elif equity > pot_odds + 0.1:
            self.recommendation = "CALL"
            self._speak("Call, Odds stimmen")
        
        elif equity < 0.25:
            self.recommendation = "FOLD"
            self._speak("Passen")
        
        elif street == 0:
            self.recommendation = "FOLD"
            self._speak("Zu schwach")
        
        else:
            self.recommendation = "CHECK"
            self._speak("Bleiben")
    
    def _add_demo_card(self):
        """Demo: Fügt Karten hinzu"""
        import random
        
        ranks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6']
        suits = ['h', 'd', 'c', 's']
        
        def rand_card():
            return random.choice(ranks) + random.choice(suits)
        
        if len(self.hero_cards) < 2:
            c1, c2 = rand_card(), rand_card()
            self.hero_cards = [c1, c2]
            self._speak("Zwei Karten")
        
        elif len(self.board_cards) < 5:
            c = rand_card()
            self.board_cards.append(c)
            names = {0: "Flop", 3: "Turn", 4: "River"}
            self._speak(names.get(len(self.board_cards), "Karte"))
        
        else:
            # Neue Hand
            self.hero_cards = []
            self.board_cards = []
            self._speak("Neue Hand")
    
    def _reset(self):
        """Reset"""
        self.hero_cards = []
        self.board_cards = []
        self.hand_strength = 0
        self.recommendation = ""
        self._speak("Zurückgesetzt")
    
    def _draw_card(self, frame, x, y, card_str: str):
        """Zeichnet eine Karte"""
        if len(card_str) < 2:
            return
            
        rank = card_str[:-1]
        suit = card_str[-1]
        
        cw, ch = 50, 70
        
        # Farbe
        if suit in ['h', 'd']:
            bg = (60, 40, 40)
            fg = (150, 80, 80)
        else:
            bg = (40, 45, 65)
            fg = (180, 180, 200)
        
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), bg, -1)
        cv2.rectangle(frame, (x, y), (x + cw, y + ch), fg, 1)
        
        # Rank
        cv2.putText(frame, rank, (x + 8, y + 20), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, fg, 2)
        
        # Suit
        suit_sym = {'h': '♥', 'd': '♦', 'c': '♣', 's': '♠'}
        cv2.putText(frame, suit_sym.get(suit, '?'), (x + 18, y + 50), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, fg, 2)
    
    def _draw_overlay(self, frame):
        """Zeichnet Overlay"""
        h, w = frame.shape[:2]
        
        # ====== HEADER ======
        cv2.rectangle(frame, (0, 0), (w, 55), COLOR_BG, -1)
        cv2.putText(frame, "🖥️ ONLINE POKER", (15, 38), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, COLOR_PRIMARY, 2)
        
        # Street
        street_names = {0: "PRE-FLOP", 3: "FLOP", 4: "TURN", 5: "RIVER"}
        street_txt = street_names.get(len(self.board_cards), "??")
        cv2.putText(frame, f" {street_txt}", (w - 160, 38), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_WARNING, 2)
        
        # ====== POT & POSITION ======
        # Obere Info-Leiste
        info_y = 70
        cv2.rectangle(frame, (10, info_y), (350, info_y + 50), COLOR_BG, -1)
        cv2.putText(frame, f"Pot: ${self.pot_size:.0f}", (20, info_y + 18), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        cv2.putText(frame, f"Bet: ${self.current_bet:.0f}", (20, info_y + 38), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180, 180, 180), 1)
        
        cv2.rectangle(frame, (360, info_y), (500, info_y + 50), COLOR_BG, -1)
        cv2.putText(frame, f"Pos: {self.position}", (370, info_y + 35), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_PRIMARY, 1)
        
        # ====== HERO CARDS ======
        card_y = h - 160
        cv2.rectangle(frame, (10, card_y - 25), (180, h - 40), COLOR_BG, -1)
        cv2.putText(frame, "YOUR HAND", (20, card_y), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
        
        if self.hero_cards:
            for i, card in enumerate(self.hero_cards):
                self._draw_card(frame, 30 + i * 60, card_y + 10, card)
        else:
            cv2.putText(frame, "Drücke [D]", (40, card_y + 50), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (100, 100, 100), 1)
        
        # ====== BOARD CARDS ======
        if self.board_cards:
            board_y = h - 280
            cv2.rectangle(frame, (10, board_y - 25), (w - 10, board_y + 60), COLOR_BG, -1)
            cv2.putText(frame, "BOARD", (20, board_y), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
            
            for i, card in enumerate(self.board_cards):
                x = 100 + i * 65
                self._draw_card(frame, x, board_y + 10, card)
        
        # ====== RECOMMENDATION ======
        if self.recommendation:
            # Box
            box_w, box_h = 320, 110
            box_x = (w - box_w) // 2
            box_y = h // 2 - 30
            
            # Farbe
            if "RAISE" in self.recommendation or "BET" in self.recommendation:
                rc = COLOR_SUCCESS
            elif "CALL" in self.recommendation:
                rc = COLOR_PRIMARY
            elif "CHECK" in self.recommendation:
                rc = COLOR_WARNING
            else:
                rc = COLOR_DANGER
            
            cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), COLOR_BG, -1)
            cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), rc, 3)
            
            # Text
            ts = cv2.getTextSize(self.recommendation, cv2.FONT_HERSHEY_SIMPLEX, 1.2, 3)[0]
            tx = (w - ts[0]) // 2
            cv2.putText(frame, self.recommendation, (tx, box_y + 40), 
                        cv2.FONT_HERSHEY_SIMPLEX, 1.2, rc, 3)
            
            # Stats
            cv2.putText(frame, f"Equity: {self.hand_strength*100:.0f}%  |  Odds: {self.pot_odds*100:.0f}%  |  EV: {self.ev:+.2f}", 
                        (box_x + 15, box_y + 75), cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
        
        # ====== POT ODDS BAR ======
        if self.current_bet > 0 and self.pot_size > 0:
            odds_y = h - 340
            cv2.rectangle(frame, (10, odds_y), (200, odds_y + 35), COLOR_BG, -1)
            cv2.putText(frame, "Pot Odds:", (15, odds_y + 12), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_TEXT, 1)
            
            # Balken
            bar_w = int(180 * min(self.pot_odds, 1.0))
            bar_col = COLOR_SUCCESS if self.pot_odds < self.hand_strength else COLOR_DANGER
            cv2.rectangle(frame, (15, odds_y + 18), (15 + bar_w, odds_y + 28), bar_col, -1)
        
        # ====== CONTROLS HINT ======
        cv2.putText(frame, "[D] Karte [P] Position [O] Odds [R] Reset [T] TTS [Q] Beenden", 
                    (10, h - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (80, 80, 80), 1)
    
    def run(self):
        """Hauptschleife"""
        print("🖥️ =====================================🖥️")
        print("   ONLINE POKER ASSISTANT")
        print("🖥️ =====================================🖥️")
        print("Kamera auf Bildschirm/Handy richten!")
        print()
        print("Steuerung:")
        print("  [D] - Demo: Karte")
        print("  [P] - Position ändern")
        print("  [O] - Odds eingeben")
        print("  [R] - Reset")
        print("  [T] - TTS")
        print("  [Q] - Beenden")
        print("======================================")
        
        while self.running:
            ret, frame = self.cap.read()
            if not ret:
                break
            
            # Spiegeln
            frame = cv2.flip(frame, 1)
            
            # Overlay
            self._draw_overlay(frame)
            
            # Empfehlung
            self._make_recommendation()
            
            cv2.imshow('🖥️ Online Poker', frame)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                self.running = False
            elif key == ord('d'):
                self._add_demo_card()
            elif key == ord('r'):
                self._reset()
            elif key == ord('t'):
                self.tts_enabled = not self.tts_enabled
            elif key == ord('p'):
                # Zyklus Position
                positions = ["UTG", "UTG+1", "MP", "CO", "BTN", "SB", "BB"]
                try:
                    idx = positions.index(self.position)
                    self.position = positions[(idx + 1) % len(positions)]
                except:
                    self.position = "BTN"
                self._speak(self.position)
            elif key == ord('o'):
                # Demo Odds
                self.pot_size = 100
                self.current_bet = 20
        
        self._cleanup()
    
    def _cleanup(self):
        self.cap.release()
        cv2.destroyAllWindows()
        print("\n👋 Online Poker Assistant beendet!")


def main():
    OnlinePokerAssistant().run()


if __name__ == "__main__":
    main()
