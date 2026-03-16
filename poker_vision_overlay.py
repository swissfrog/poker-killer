#!/usr/bin/env python3
"""
Poker Vision Assistant - Overlay + Sprachausgabe
================================================

Ein Poker-Assistent mit:
- Kamera-Overlay
- Karten-Erkennung  
- Hand-Stärke Berechnung
- Sprachempfehlungen (TTS)

Author: PokerBot
"""

import cv2
import numpy as np
import threading
import time
from collections import namedtuple
from typing import List, Tuple, Optional
import sys

# Farben
COLOR_BG = (20, 20, 30)
COLOR_PRIMARY = (0, 180, 255)      # Orange
COLOR_SUCCESS = (0, 255, 100)       # Grün
COLOR_WARNING = (255, 200, 0)      # Gelb
COLOR_DANGER = (255, 50, 80)       # Rot
COLOR_TEXT = (255, 255, 255)
COLOR_CARD = (50, 50, 70)


class Card:
    """Eine Spielkarte"""
    RANKS = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2']
    SUITS = {'♥': 'herz', '♦': 'karo', '♣': 'kreuz', '♠': 'pik'}
    
    def __init__(self, rank: str, suit: str):
        self.rank = rank
        self.suit = suit
    
    def __str__(self):
        suits = {'herz': '♥', 'karo': '♦', 'kreuz': '♣', 'pik': '♠'}
        return f"{self.rank}{suits.get(self.suit, self.suit)}"
    
    @property
    def is_red(self):
        return self.suit in ['herz', 'karo']


class PokerAssistant:
    """Hauptklasse für den Poker Assistant"""
    
    def __init__(self):
        # Kamera
        self.cap = cv2.VideoCapture(0)
        if not self.cap.isOpened():
            print("❌ Keine Kamera gefunden!")
            sys.exit(1)
        
        # State
        self.player_cards: List[Card] = []
        self.community_cards: List[Card] = []
        self.hand_strength: float = 0.0
        self.recommendation: str = ""
        self.running = True
        
        # Overlay-Einstellungen
        self.overlay_opacity = 0.85
        
        # TTS
        self.tts_enabled = True
        self.last_speak_time = 0
        self.speak_interval = 5  # Sekunden zwischen Ansagen
        
        # Demo-Modus (simuliert Karten)
        self.demo_mode = True
        self.demo_cards = [
            Card('A', 'pik'), Card('K', 'herz'),
            Card('Q', 'karo'), Card('J', 'kreuz'),
            Card('10', 'pik'), Card('9', 'herz'), Card('8', 'karo'),
        ]
        self.demo_index = 0
        
        # Initialisiere TTS
        self._init_tts()
    
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
        """Spricht Text ( threaded )"""
        if not self.tts_enabled or not self.tts_engine:
            return
        
        # Nur alle X Sekunden sprechen
        now = time.time()
        if now - self.last_speak_time < self.speak_interval:
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
    
    def _calculate_hand_strength(self):
        """Berechnet Hand-Stärke (vereinfacht)"""
        all_cards = self.player_cards + self.community_cards
        
        if len(self.player_cards) < 2:
            self.hand_strength = 0.0
            self.recommendation = "Warte auf Karten"
            return
        
        # Vereinfachte Bewertung
        strength = 0.5
        
        # Premium-Paare
        premium = ['A', 'K', 'Q', 'J']
        if self.player_cards[0].rank in premium and self.player_cards[1].rank in premium:
            strength += 0.3
        
        # Pocket Pair
        if self.player_cards[0].rank == self.player_cards[1].rank:
            strength += 0.25
        
        # Suited
        if self.player_cards[0].suit == self.player_cards[1].suit:
            strength += 0.1
        
        # Position incommunity cards
        community_str = len(self.community_cards)
        if community_str >= 3:  # Flop
            strength += 0.1
        if community_str >= 4:  # Turn
            strength += 0.05
        if community_str >= 5:  # River
            strength += 0.05
        
        self.hand_strength = min(strength, 1.0)
        
        # Empfehlung
        if self.hand_strength > 0.75:
            self.recommendation = "RAISE"
            self._speak("Erhöhe!")
        elif self.hand_strength > 0.55:
            self.recommendation = "CALL"
            self._speak("Mitgehen")
        elif self.hand_strength > 0.35:
            self.recommendation = "CHECK"
            self._speak("Bleiben")
        else:
            self.recommendation = "FOLD"
            self._speak("Passen")
    
    def _add_demo_card(self):
        """Fügt Demo-Karte hinzu"""
        if not self.demo_mode:
            return
        
        # Zyklus durch Demo-Karten
        card = self.demo_cards[self.demo_index % len(self.demo_cards)]
        self.demo_index += 1
        
        if len(self.player_cards) < 2:
            self.player_cards.append(card)
        elif len(self.community_cards) < 5:
            self.community_cards.append(card)
        else:
            # Reset
            self.player_cards = []
            self.community_cards = [card]
        
        # Karten angesagen
        if len(self.player_cards) == 2:
            self._speak("Zwei Karten erkannt")
    
    def _draw_overlay(self, frame):
        """Zeichnet das Overlay auf das Bild"""
        h, w = frame.shape[:2]
        
        # ====== HEADER ======
        # Obere Leiste
        cv2.rectangle(frame, (0, 0), (w, 60), COLOR_BG, -1)
        cv2.putText(frame, "🎲 POKER VISION", (20, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, COLOR_PRIMARY, 2)
        
        # Status-Indikator
        status = "● LIVE" if self.running else "○ STOPPED"
        color = COLOR_SUCCESS if self.running else COLOR_DANGER
        cv2.putText(frame, status, (w - 120, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
        
        # ====== SPIELER-KARTEN ======
        # Box für Spieler-Karten
        card_y = h - 200
        cv2.rectangle(frame, (20, card_y), (300, h - 80), COLOR_BG, -1)
        cv2.rectangle(frame, (20, card_y), (300, h - 80), COLOR_PRIMARY, 2)
        
        cv2.putText(frame, "DEINE KARTEN", (30, card_y + 25), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        
        # Karten anzeigen
        if self.player_cards:
            for i, card in enumerate(self.player_cards):
                x = 40 + i * 70
                self._draw_card(frame, x, card_y + 45, card)
        else:
            cv2.putText(frame, "Warte...", (50, card_y + 80), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (100, 100, 100), 2)
        
        # ====== GEMEINSCHAFTSKARTEN ======
        if self.community_cards:
            comm_y = h - 320
            cv2.rectangle(frame, (20, comm_y), (w - 20, comm_y + 70), COLOR_BG, -1)
            cv2.putText(frame, "TISCH", (30, comm_y + 20), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
            
            for i, card in enumerate(self.community_cards):
                x = 100 + i * 70
                self._draw_card(frame, x, comm_y + 35, card)
        
        # ====== EMPFEHLUNG ======
        # Große Empfehlungs-Box in der Mitte
        box_w, box_h = 400, 120
        box_x = (w - box_w) // 2
        box_y = h // 2 - 60
        
        # Farbe basierend auf Empfehlung
        if "RAISE" in self.recommendation:
            rec_color = COLOR_SUCCESS
        elif "CALL" in self.recommendation:
            rec_color = COLOR_PRIMARY
        elif "CHECK" in self.recommendation:
            rec_color = COLOR_WARNING
        elif "FOLD" in self.recommendation:
            rec_color = COLOR_DANGER
        else:
            rec_color = (80, 80, 80)
        
        # Box zeichnen
        cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), COLOR_BG, -1)
        cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), rec_color, 3)
        
        # Empfehlungs-Text
        text_size = cv2.getTextSize(self.recommendation, cv2.FONT_HERSHEY_SIMPLEX, 1.5, 3)[0]
        text_x = (w - text_size[0]) // 2
        cv2.putText(frame, self.recommendation, (text_x, box_y + 50), 
                    cv2.FONT_HERSHEY_SIMPLEX, 1.5, rec_color, 3)
        
        # Hand-Stärke
        strength_text = f"Stärke: {self.hand_strength*100:.0f}%"
        strength_size = cv2.getTextSize(strength_text, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)[0]
        strength_x = (w - strength_size[0]) // 2
        cv2.putText(frame, strength_text, (strength_x, box_y + 90), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, COLOR_TEXT, 2)
        
        # ====== STATS ======
        # Statistiken links
        stats_x = w - 200
        stats_y = 80
        cv2.putText(frame, "STATISTIK", (stats_x, stats_y), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        
        stats = [
            f"Player: {len(self.player_cards)}",
            f"Tisch: {len(self.community_cards)}",
            f"TTS: {'AN' if self.tts_enabled else 'AUS'}",
        ]
        for i, stat in enumerate(stats):
            cv2.putText(frame, stat, (stats_x, stats_y + 25 + i*20), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150, 150, 150), 1)
        
        # ====== STEUERUNG-HINTS ======
        # Unten
        cv2.putText(frame, "[D] Karte | [R] Reset | [T] TTS | [Q] Beenden", 
                    (20, h - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (100, 100, 100), 1)
    
    def _draw_card(self, frame, x, y, card: Card):
        """Zeichnet eine einzelne Karte"""
        card_w, card_h = 60, 84
        
        # Karte Hintergrund
        color = (180, 50, 50) if card.is_red else (50, 50, 80)
        cv2.rectangle(frame, (x, y), (x + card_w, y + card_h), color, -1)
        cv2.rectangle(frame, (x, y), (x + card_w, y + card_h), COLOR_TEXT, 1)
        
        # Rank
        cv2.putText(frame, card.rank, (x + 15, y + 25), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_TEXT, 2)
        
        # Suit
        suits = {'herz': '♥', 'karo': '♦', 'kreuz': '♣', 'pik': '♠'}
        suit_char = suits.get(card.suit, '?')
        cv2.putText(frame, suit_char, (x + 25, y + 60), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, COLOR_TEXT, 2)
    
    def run(self):
        """Hauptschleife"""
        print("=" * 50)
        print("🎲 POKER VISION ASSISTANT")
        print("=" * 50)
        print("Steuerung:")
        print("  [D] - Demo: Karte hinzufügen")
        print("  [R] - Reset: Alles zurücksetzen")
        print("  [T] - TTS: Sprachausgabe an/aus")
        print("  [Q] - Quit: Beenden")
        print("=" * 50)
        
        while self.running:
            # Frame von Kamera
            ret, frame = self.cap.read()
            if not ret:
                break
            
            # Spiegeln (Selfie-Modus)
            frame = cv2.flip(frame, 1)
            
            # Overlay zeichnen
            self._draw_overlay(frame)
            
            # Berechne Hand-Stärke
            self._calculate_hand_strength()
            
            # Anzeigen
            cv2.imshow('🎲 Poker Vision', frame)
            
            # Tastatur-Eingabe
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                self.running = False
            elif key == ord('d'):
                self._add_demo_card()
            elif key == ord('r'):
                self.player_cards = []
                self.community_cards = []
                self.hand_strength = 0.0
                self.recommendation = ""
                self._speak("Zurückgesetzt")
            elif key == ord('t'):
                self.tts_enabled = not self.tts_enabled
                status = "an" if self.tts_enabled else "aus"
                self._speak(f"Sprache {status}")
        
        self._cleanup()
    
    def _cleanup(self):
        """Aufräumen"""
        self.cap.release()
        cv2.destroyAllWindows()
        print("\n👋 Poker Vision beendet!")


def main():
    assistant = PokerAssistant()
    assistant.run()


if __name__ == "__main__":
    main()
