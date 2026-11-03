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
import math
from collections import namedtuple
from typing import List, Tuple, Optional
from hand_history import HandHistory
from opponent_model import OpponentModel
from preflop_range_chart import PreflopRangeChart
from push_fold_table import PushFoldTable
from bet_sizing import BetSizingControls
from card_flip_animation import CardFlipAnimation
from shake_reset import ShakeResetDetector
from card_correction import CardCorrectionUI
from poker_logic import PokerLogic

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
                    
                    cards.append(Card(rank, suit))
                    
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
        self.card_editor = CardCorrectionUI(Card)
        self.manual_card_mode = False
        self.last_recommendation_reason = ""
        self._recommendation_key = None
        self.history = HandHistory()
        self.opponent_model = OpponentModel()
        self.range_chart = PreflopRangeChart()
        self.push_fold_table = PushFoldTable()
        self.bet_sizing = BetSizingControls()
        self.card_animation = CardFlipAnimation()
        self.shake_detector = ShakeResetDetector()
        self.shake_reset_enabled = True
        self.detection_paused_until = 0.0
        self.light_mode = False
        
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
        print("Drücke 'h' für History, 'p' für Ranges, 'n' für Push/Fold, 'b' für Bet-Sizing")
        print("Drücke 't' für Theme, 'm' schaltet Shake-Reset um; Position im Chart: 1-6")
        print("Drücke 'c' für Kartenkorrektur, 'v' für automatische Kameraerkennung")
        
        while self.running:
            ret, frame = self.cap.read()
            if not ret:
                print("❌ Kein Kamerabild")
                break
            
            # Kamera-Schütteln als Reset-Geste; die Historie bleibt erhalten.
            if self.shake_reset_enabled and self.shake_detector.update(frame):
                self.player_cards = []
                self.community_cards = []
                self.last_recommendation = ""
                self.last_recommendation_reason = ""
                self.detection_paused_until = time.monotonic() + 1.5
                if self.manual_card_mode:
                    self.card_editor.load_cards([], [])
                print("Shake-Reset erkannt; Kartenansicht zurückgesetzt")

            # Karten erkennen oder bestaetigte manuelle Eingaben verwenden
            if self.manual_card_mode:
                self.player_cards, self.community_cards = self.card_editor.cards()
            elif time.monotonic() >= self.detection_paused_until:
                self.player_cards = self._unique_cards(self.card_detector.detect_cards(frame))
            else:
                self.player_cards = []
            
            # Einsatzwerte zuerst lesen, damit Empfehlung und Verlauf denselben Zustand nutzen.
            self.pot_size, self.current_bet = self.bet_sizing.values()
            self._update_recommendation()
            self.history.observe(
                self.player_cards,
                self.community_cards,
                self.pot_size,
                self.current_bet,
                self.last_recommendation,
            )

            # UI zeichnen
            self._draw_ui(frame)
            
            cv2.imshow('Poker Vision Assistant', frame)
            if self.range_chart.is_open:
                cv2.imshow(self.range_chart.WINDOW_NAME, self.range_chart.render(self.player_cards))
            if self.push_fold_table.is_open:
                cv2.imshow(self.push_fold_table.WINDOW_NAME, self.push_fold_table.render(self.player_cards))
            if self.bet_sizing.is_open:
                self.bet_sizing.render()
            if self.card_editor.is_open:
                self.card_editor.show()
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('r'):
                self.player_cards = []
                self.community_cards = []
                self.last_recommendation = ""
                self.last_recommendation_reason = ""
                if self.manual_card_mode:
                    self.card_editor.load_cards([], [])
                self.detection_paused_until = time.monotonic() + 1.5
            elif key == ord('h'):
                self.history.print_recent()
            elif key == ord('c'):
                if not self.card_editor.is_open:
                    if not self.manual_card_mode:
                        self.card_editor.open(self.player_cards, self.community_cards)
                        self.manual_card_mode = True
                    else:
                        self.card_editor.open()
                else:
                    self.card_editor.close()
            elif key == ord('v'):
                self.manual_card_mode = False
                self.card_editor.close()
                self.community_cards = []
                self.last_recommendation = ""
                self.last_recommendation_reason = ""
            elif key == ord('p'):
                self.range_chart.toggle_window()
            elif key == ord('n'):
                self.push_fold_table.toggle_window()
            elif key == ord('b'):
                self.bet_sizing.toggle_window()
            elif key == ord('t'):
                self.light_mode = not self.light_mode
            elif key == ord('m'):
                self.shake_reset_enabled = not self.shake_reset_enabled
                print("Shake-Reset {}".format("aktiv" if self.shake_reset_enabled else "aus"))
            elif key in [ord(str(i)) for i in range(1, 7)]:
                position_index = key - ord('1')
                self.range_chart.set_position_index(position_index)
                self.push_fold_table.set_position_index(position_index)
            elif key == ord('['):
                self.push_fold_table.cycle_stack(-1)
            elif key == ord(']'):
                self.push_fold_table.cycle_stack(1)
        
        self.stop()
    
    def _draw_ui(self, frame):
        """Zeichnet die UI auf das Bild"""
        height, width = frame.shape[:2]
        
        # Theme und Kopfbereich
        header_color = (225, 225, 225) if self.light_mode else (20, 20, 30)
        foreground = (30, 30, 30) if self.light_mode else (245, 245, 245)
        cv2.rectangle(frame, (0, 0), (width, 60), header_color, -1)
        cv2.putText(frame, "Poker Vision Assistant | {} mode".format("Light" if self.light_mode else "Dark"), (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, foreground, 2)
        
        cv2.putText(frame, "History: {} | h: Verlauf | p: Range | n: Push/Fold | b: Bet".format(len(self.history.entries)),
                    (20, 85), cv2.FONT_HERSHEY_SIMPLEX, 0.45, foreground, 1)
        cv2.putText(frame, self.opponent_model.summary(), (20, 108),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, foreground, 1)
        pot_size, current_bet = self.bet_sizing.values()
        self.pot_size, self.current_bet = pot_size, current_bet
        cv2.putText(frame, "Kartenmodus: {} | c: Korrektur | v: Kamera".format(
            "manuell" if self.manual_card_mode else "Kamera (unbestaetigt)"),
            (20, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.43, foreground, 1)
        cv2.putText(frame, "Pot {:.0f} | Einsatz {:.0f} | m: Shake-Reset {}".format(
            pot_size, current_bet, "AN" if self.shake_reset_enabled else "AUS"),
            (20, 130), cv2.FONT_HERSHEY_SIMPLEX, 0.45, foreground, 1)
        self._draw_bluff_meter(frame, foreground)
        self.card_animation.draw(frame, self.player_cards, 20, 175)
        vpip, pfr = self.opponent_model.values()
        if vpip >= 35 and vpip > 0 and pfr / float(vpip) <= 0.35:
            pulse = 110 + int(100 * (0.5 + 0.5 * math.sin(time.monotonic() * 6)))
            cv2.rectangle(frame, (width - 205, 12), (width - 18, 48), (20, pulse, 30), -1)
            cv2.putText(frame, "Fish profile? (manuell)", (width - 198, 36),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)

        # Spieler-Karten anzeigen
        y_card = height - 150
        if self.player_cards:
            card_text = " ".join(str(c) for c in self.player_cards)
            cv2.putText(frame, f"Hole Cards: {card_text}", (20, y_card),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 130, 30), 2)
        
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
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
            if self.last_recommendation_reason:
                cv2.putText(frame, self.last_recommendation_reason[:100], (max(10, width//8), height//2 + 42),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.42, foreground, 1)
        
        # Einen Hand-Rang nur fuer bestaetigte, vollstaendige manuelle Karten anzeigen.
        if self.manual_card_mode and self.card_editor.confirmed:
            known_cards = self.player_cards + self.community_cards
            if 2 <= len(known_cards) <= 7:
                try:
                    hand_name, _category = self.poker_logic.evaluate_hand(known_cards)
                except ValueError:
                    hand_name = "ungueltige Karten"
                strength_text = "Hand-Rang: {}".format(hand_name)
                cv2.putText(frame, strength_text, (width - 250, height - 20),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)
    
    def _draw_bluff_meter(self, frame, foreground):
        """Zeigt eine manuelle Schätzung, keine berechnete Bluff-Wahrscheinlichkeit."""
        height, width = frame.shape[:2]
        value = self.opponent_model.bluff_estimate()
        center = (width - 100, height - 80)
        cv2.ellipse(frame, center, (70, 42), 0, 180, 360, (130, 130, 130), 5)
        angle = math.pi - (value / 100.0) * math.pi
        endpoint = (int(center[0] + 62 * math.cos(angle)), int(center[1] - 36 * math.sin(angle)))
        cv2.line(frame, center, endpoint, (0, 160, 255), 3)
        cv2.putText(frame, "Bluff (manuell) {}%".format(value),
                    (width - 210, height - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.45, foreground, 1)

    @staticmethod
    def _unique_cards(cards):
        unique = []
        seen = set()
        for card in cards:
            key = (card.rank, card.suit)
            if key not in seen:
                seen.add(key)
                unique.append(card)
        return unique

    def _update_recommendation(self):
        """Gibt nur fuer bestaetigte manuelle Karten eine begruendete Entscheidung aus."""
        if not self.manual_card_mode or not self.card_editor.confirmed:
            self._recommendation_key = None
            self.last_recommendation = "Karten pruefen und in der Korrektur bestaetigen"
            self.last_recommendation_reason = ""
            return
        if len(self.player_cards) != 2:
            self._recommendation_key = None
            self.last_recommendation = "Keine Empfehlung: genau zwei Hole Cards benoetigt"
            self.last_recommendation_reason = ""
            return
        cache_key = (
            tuple((card.rank, card.suit) for card in self.player_cards),
            tuple((card.rank, card.suit) for card in self.community_cards),
            self.pot_size,
            self.current_bet,
            self.range_chart.position,
        )
        if cache_key == self._recommendation_key:
            return
        self._recommendation_key = cache_key
        self.last_recommendation = ""
        self.last_recommendation_reason = ""
        try:
            action, reason = self.poker_logic.recommend(
                self.player_cards,
                self.community_cards,
                self.pot_size,
                self.current_bet,
                self.range_chart.position,
            )
        except ValueError as exc:
            self.last_recommendation = "Keine Empfehlung: ungueltige Karten"
            self.last_recommendation_reason = str(exc)
            return
        self.last_recommendation = action
        self.last_recommendation_reason = reason
    
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
