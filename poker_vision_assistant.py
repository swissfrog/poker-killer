#!/usr/bin/env python3
"""
Poker Vision Assistant - Ein Poker-Bot der durch die Kamera schaut
und dir Sprachempfehlungen gibt.

Verwendung:
    python poker_vision_assistant.py
"""

import cv2
import numpy as np
import threading
import time
import json
from collections import namedtuple
from typing import List, Tuple, Optional

# Farben für die Kartenerkennung (in HSV)
CARD_COLORS = {
    'red': ((0, 100, 100), (10, 255, 255)),
    'black': ((0, 0, 0), (180, 255, 50)),
    'hearts': ((0, 100, 100), (10, 255, 255)),
    'diamonds': ((0, 100, 100), (10, 255, 255)),
    'clubs': ((90, 50, 50), (130, 255, 150)),
    'spades': ((90, 50, 50), (130, 255, 150)),
}

# Kartensymbole erkennen wir über Konturanalyse
# Vereinfachte Erkennung basierend auf Farbe und Form


class Card:
    """Eine Spielkarte"""
    RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    SUITS = ['hearts', 'diamonds', 'clubs', 'spades']
    
    def __init__(self, rank: str, suit: str):
        self.rank = rank
        self.suit = suit
    
    def __str__(self):
        return f"{self.rank}{self._suit_symbol()}"
    
    def _suit_symbol(self):
        symbols = {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'}
        return symbols.get(self.suit, self.suit)
    
    def value(self) -> int:
        """Kartenwert für Vergleiche"""
        return self.RANKS.index(self.rank) + 2


class PokerLogic:
    """Poker-Logik und Odds-Berechnung"""
    
    @staticmethod
    def evaluate_hand(cards: List[Card]) -> Tuple[str, int]:
        """Bewertet eine Poker-Hand"""
        if len(cards) < 2:
            return ("Start hand", 0)
        
        ranks = [c.rank for c in cards]
        suits = [c.suit for c in cards]
        
        # Prüfe auf Paar, Two Pair, Drilling, etc.
        rank_counts = {}
        for r in ranks:
            rank_counts[r] = rank_counts.get(r, 0) + 1
        
        values = sorted([c.value() for c in cards], reverse=True)
        
        # Royal Flush, Straight Flush, etc. (vereinfacht)
        if len(cards) >= 5:
            if PokerLogic._is_flush(suits) and PokerLogic._is_straight(values):
                if values[-1] == 10:
                    return ("Royal Flush", 100)
                return ("Straight Flush", 90)
            
            if 4 in rank_counts.values():
                return ("Four of a Kind", 80)
            
            if 3 in rank_counts.values() and 2 in rank_counts.values():
                return ("Full House", 70)
            
            if PokerLogic._is_flush(suits):
                return ("Flush", 60)
            
            if PokerLogic._is_straight(values):
                return ("Straight", 50)
            
            if 3 in rank_counts.values():
                return ("Three of a Kind", 40)
            
            if list(rank_counts.values()).count(2) == 2:
                return ("Two Pair", 30)
            
            if 2 in rank_counts.values():
                return ("Pair", 20)
        
        # Beste High Card
        return ("High Card", max(values))
    
    @staticmethod
    def _is_flush(suits: List[str]) -> bool:
        return len(set(suits)) == 1
    
    @staticmethod
    def _is_straight(values: List[int]) -> bool:
        if len(values) < 5:
            return False
        unique = sorted(set(values))
        if len(unique) < 5:
            return False
        # Prüfe auf Straße
        for i in range(len(unique) - 4):
            if unique[i+4] - unique[i] == 4:
                return True
        # Wheel (A-2-3-4-5)
        if set([14, 2, 3, 4, 5]).issubset(set(values)):
            return True
        return False
    
    @staticmethod
    def get_hand_strength(cards: List[Card], community: List[Card]) -> float:
        """Berechnet die Stärke der Hand (0-1)"""
        all_cards = cards + community
        
        if len(all_cards) < 2:
            return 0.1
        
        hand_type, score = PokerLogic.evaluate_hand(all_cards)
        
        # Basis-Score umrechnen
        strength = score / 100.0
        
        # Boni für Starthand
        if len(cards) == 2:
            # Premium-Hände
            premium_ranks = ['A', 'K', 'Q', 'J', '10']
            if all(c.rank in premium_ranks for c in cards):
                strength += 0.2
            # Pocket Pairs
            if cards[0].rank == cards[1].rank:
                strength += 0.15
            # Suited connectors
            if cards[0].suit == cards[1].suit and abs(cards[0].value() - cards[1].value()) <= 2:
                strength += 0.1
        
        return min(strength, 1.0)
    
    @staticmethod
    def get_recommendation(hand_strength: float, pot_odds: float, position: str = "middle") -> str:
        """Gibt eine Empfehlung basierend auf Handstärke und Pot-Odds"""
        
        # Anpassung nach Position
        position_bonus = {"early": -0.1, "middle": 0, "late": 0.1}
        adjusted_strength = hand_strength + position_bonus.get(position, 0)
        
        if adjusted_strength > 0.8:
            return "RAISE - Starke Hand, erhöhen!"
        elif adjusted_strength > 0.6:
            if pot_odds > 0.2:
                return "CALL - Gute Odds zum callen"
            return "CHECK - Hand ist gut"
        elif adjusted_strength > 0.4:
            if pot_odds > 0.15:
                return "FOLD - Zu schwach"
            return "CHECK - Weiter"
        else:
            return "FOLD - Hand zu schwach"


class CardDetector:
    """Erkennt Spielkarten im Kamerabild"""
    
    def __init__(self):
        self.template_cards = self._load_templates()
    
    def _load_templates(self):
        """Lädt Karten-Templates (vereinfacht)"""
        # In einer echten Implementierung würde man echte Templates laden
        return {}
    
    def detect_cards(self, frame) -> List[Card]:
        """Erkennt Karten im Bild"""
        cards = []
        
        # Bild vorverarbeiten
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)
        
        # Konturen finden
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        # Filtere kleine Konturen (keine Karten)
        contours = [c for c in contours if 1000 < cv2.contourArea(c) < 50000]
        
        for contour in contours:
            # Umrandung finden
            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            
            # Ist es ein Rechteck (Karte)?
            if len(approx) == 4:
                x, y, w, h = cv2.boundingRect(contour)
                aspect_ratio = w / float(h)
                
                if 0.6 < aspect_ratio < 0.8:  # Kartenformat
                    # Farbe der Karte bestimmen
                    roi = frame[y:y+h, x:x+w]
                    avg_color = np.mean(roi, axis=(0, 1))
                    
                    # Vereinfachte Farberkennung
                    if avg_color[2] > avg_color[0] + 20:  # Rötlich
                        suit = 'hearts' if avg_color[1] > 100 else 'diamonds'
                    else:  # Schwärzlich oder
                        suit = 'spades' if avg_color[1] < 80 else 'clubs'
                    
                    # Rang basierend auf Helligkeit (vereinfacht)
                    brightness = np.mean(gray[y:y+h, x:x+w])
                    rank_idx = min(int(brightness / 20), 12)
                    rank = Card.RANKS[rank_idx]
                    
                    cards.append(Card(rank, suit)
                    
                    # Zeichne Rahmen
                    cv2.rectangle(frame, (x, y), (x+w, y+h), (0, 255, 0), 2)
        
        return cards
    
    def detect_community_cards(self, frame) -> List[Card]:
        """Erkennt Gemeinschaftskarten (Flop, Turn, River)"""
        # Similar to detect_cards but looks for cards in the center
        return self.detect_cards(frame)


class PokerVisionAssistant:
    """Hauptklasse für den Poker Vision Assistant"""
    
    def __init__(self, camera_index=0):
        self.cap = cv2.VideoCapture(camera_index)
        self.card_detector = CardDetector()
        self.poker_logic = PokerLogic()
        
        self.player_cards: List[Card] = []
        self.community_cards: List[Card] = []
        self.pot_size: float = 0
        self.current_bet: float = 0
        
        self.running = False
        self.last_recommendation = ""
        self.last_speak_time = 0
    
    def start(self):
        """Startet den Assistant"""
        self.running = True
        print("🎲 Poker Vision Assistant gestartet!")
        print("Drücke 'q' zum Beenden")
        print("Drücke 'r' um Karten zu resetten")
        
        while self.running:
            ret, frame = self.cap.read()
            if not ret:
                print("❌ Kein Kamerabild")
                break
            
            # Karten erkennen
            self.player_cards = self.card_detector.detect_cards(frame)
            
            # UI zeichnen
            self._draw_ui(frame)
            
            # Empfehlung aktualisieren
            self._update_recommendation()
            
            cv2.imshow('Poker Vision Assistant', frame)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('r'):
                self.player_cards = []
                self.community_cards = []
        
        self.stop()
    
    def _draw_ui(self, frame):
        """Zeichnet die UI auf das Bild"""
        height, width = frame.shape[:2]
        
        # Header
        cv2.rectangle(frame, (0, 0), (width, 60), (20, 20, 30), -1)
        cv2.putText(frame, "🎲 Poker Vision Assistant", (20, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        
        # Spieler-Karten anzeigen
        y_card = height - 150
        if self.player_cards:
            card_text = " ".join(str(c) for c in self.player_cards)
            cv2.putText(frame, f"Deine Karten: {card_text}", (20, y_card), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        
        # Gemeinschaftskarten
        if self.community_cards:
            comm_text = " ".join(str(c) for c in self.community_cards)
            cv2.putText(frame, f"Tisch: {comm_text}", (20, y_card + 40), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2)
        
        # Empfehlung
        if self.last_recommendation:
            # Empfehlungs-Box
            cv2.rectangle(frame, (width//4, height//2 - 40), 
                         (3*width//4, height//2 + 40), (0, 0, 0), -1)
            cv2.rectangle(frame, (width//4, height//2 - 40), 
                         (3*width//4, height//2 + 40), (0, 255, 0), 3)
            
            # Text zentrieren
            text_size = cv2.getTextSize(self.last_recommendation, 
                                        cv2.FONT_HERSHEY_SIMPLEX, 1, 2)[0]
            text_x = (width - text_size[0]) // 2
            cv2.putText(frame, self.last_recommendation, (text_x, height//2 + 10), 
                        cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        
        # Hand-Stärke
        if self.player_cards:
            strength = self.poker_logic.get_hand_strength(
                self.player_cards, self.community_cards
            )
            strength_text = f"Hand-Stärke: {strength*100:.0f}%"
            cv2.putText(frame, strength_text, (width - 250, height - 20), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
    
    def _update_recommendation(self):
        """Aktualisiert die Empfehlung"""
        if len(self.player_cards) >= 2:
            strength = self.poker_logic.get_hand_strength(
                self.player_cards, self.community_cards
            )
            
            # Pot-Odds berechnen (vereinfacht)
            pot_odds = 0.1  # Default
            
            self.last_recommendation = self.poker_logic.get_recommendation(
                strength, pot_odds
            )
    
    def add_community_card(self, card: Card):
        """Fügt eine Gemeinschaftskarte hinzu"""
        if len(self.community_cards) < 5:
            self.community_cards.append(card)
    
    def set_pot_size(self, amount: float):
        """Setzt die Pot-Größe"""
        self.pot_size = amount
    
    def stop(self):
        """Stoppt den Assistant"""
        self.running = False
        self.cap.release()
        cv2.destroyAllWindows()
        print("👋 Poker Vision Assistant beendet")


def main():
    """Hauptfunktion"""
    print("=" * 50)
    print("🎲 Poker Vision Assistant")
    print("=" * 50)
    print()
    print("Funktionen:")
    print("  • Kamerabild erfassen")
    print("  • Karten automatisch erkennen")
    print("  • Hand-Stärke berechnen")
    print("  • Spielempfehlungen anzeigen")
    print()
    
    assistant = PokerVisionAssistant(camera_index=0)
    assistant.start()


if __name__ == "__main__":
    main()
# ──────────────────────────────────────────────────────────
# Sprachausgabe-Funktionen
# ──────────────────────────────────────────────────────────

try:
    import pyttsx3
    TTS_AVAILABLE = True
except ImportError:
    TTS_AVAILABLE = False

class VoiceAssistant:
    """Sprachausgabe für Empfehlungen"""
    
    def __init__(self, enabled=True):
        self.enabled = enabled and TTS_AVAILABLE
        self.engine = None
        
        if self.enabled:
            try:
                self.engine = pyttsx3.init()
                self.engine.setProperty('rate', 150)
                self.engine.setProperty('volume', 0.9)
            except:
                self.enabled = False
    
    def speak(self, text: str):
        """Spricht einen Text"""
        if not self.enabled:
            return
        
        try:
            # Threading damit UI nicht blockiert
            thread = threading.Thread(target=self._speak_async, args=(text,))
            thread.start()
        except Exception as e:
            print(f"Speech error: {e}")
    
    def _speak_async(self, text: str):
        try:
            self.engine.say(text)
            self.engine.runAndWait()
        except:
            pass
    
    def announce_cards(self, cards: List[Card]):
        """Kündigt erkannte Karten an"""
        if not cards:
            return
        
        card_text = ", ".join(str(c) for c in cards)
        self.speak(f"Deine Karten: {card_text}")
    
    def announce_recommendation(self, recommendation: str):
        """Kündigt Empfehlung an"""
        # Kurz und prägnant
        if "RAISE" in recommendation:
            self.speak("Erhöhe!")
        elif "CALL" in recommendation:
            self.speak("Mitgehen")
        elif "CHECK" in recommendation:
            self.speak("Bleiben")
        elif "FOLD" in recommendation:
            self.speak("Passen")
    
    def announce_strength(self, strength: float):
        """Kündigt Handstärke an"""
        percent = int(strength * 100)
        self.speak("Handstärke $percent Prozent")
