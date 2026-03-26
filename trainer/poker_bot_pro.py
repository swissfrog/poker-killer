#!/usr/bin/env python3
"""
Poker Screen Reader - Professional Edition
==========================================

Bot schaut auf deinen Bildschirm:
1. Erkennt deine Karten automatisch
2. Erkennt Tischkarten
3. Berechnet beste Entscheidung (Poker-Mathematik)
4. Zeigt + spricht Empfehlung

Autor: PokerBot
"""

import cv2
import numpy as np
import pyttsx3
import threading
import time
from typing import List, Tuple, Dict, Optional
from collections import Counter
import re

# ===================== FARBEN =====================
COLOR_BG = (18, 18, 28)
COLOR_PANEL = (30, 30, 45)
COLOR_PRIMARY = (0, 180, 255)
COLOR_SUCCESS = (0, 255, 120)
COLOR_WARNING = (255, 200, 0)
COLOR_DANGER = (255, 70, 90)
COLOR_TEXT = (255, 255, 255)
COLOR_CARD_BG = (45, 50, 70)

# ===================== POKER LOGIK =====================

# KartenKiller Integration
try:
    from karten_killer_pro import KartenKillerPro, PokerGameState, BoardAnalyzer
    KARTENKILLER_AVAILABLE = True
    kk = None  # Wird später initialisiert
except ImportError:
    KARTENKILLER_AVAILABLE = False
    kk = None

def init_karten_killer():
    """Initialisiere KartenKiller"""
    global kk
    if KARTENKILLER_AVAILABLE and kk is None:
        try:
            kk = KartenKillerPro()
            print("♠️ KartenKiller ML geladen!")
        except Exception as e:
            print(f"⚠️ KartenKiller Fehler: {e}")

class PokerMath:
    """Poker Mathematik & Berechnungen"""
    
    # Starthand-Werte (vereinfacht)
    STARTING_HANDS = {
        ('A','A'): 1.0, ('K','K'): 0.95, ('Q','Q'): 0.90, ('J','J'): 0.85,
        ('10','10'): 0.80, ('A','K'): 0.78, ('A','Q'): 0.72, ('K','Q'): 0.68,
        ('A','J'): 0.65, ('K','J'): 0.62, ('Q','J'): 0.58, ('A','10'): 0.55,
    }
    
    @staticmethod
    def evaluate_7_cards(cards: List) -> Tuple[int, str]:
        """Bewertet beste 5-Karten Hand aus 7"""
        if len(cards) < 5:
            return 0, "Incomplete"
        
        from itertools import combinations
        
        best = (0, "High Card")
        
        for combo in combinations(cards, 5):
            rank = PokerMath._rank_5(combo)
            if rank[0] > best[0]:
                best = rank
        
        return best
    
    @staticmethod
    def _rank_5(cards: List) -> Tuple[int, str]:
        """Ranked 5 cards"""
        ranks = sorted([c[1] for c in cards], reverse=True)
        suits = [c[0] for c in cards]
        
        rank_cnt = Counter(ranks)
        is_flush = len(set(suits)) == 1
        
        # Straight check
        unique = sorted(set(ranks))
        is_straight = len(unique) == 5 and unique[0] - unique[4] == 4
        if is_straight and unique[0] == 12:  # A-5 wheel
            is_straight = True
        
        # Check hands
        if is_straight and is_flush:
            if ranks[0] == 12:
                return 9, "Royal Flush"
            return 8, "Straight Flush"
        
        if 4 in rank_cnt.values():
            return 7, "Four of a Kind"
        
        if 3 in rank_cnt.values() and 2 in rank_cnt.values():
            return 6, "Full House"
        
        if is_flush:
            return 5, "Flush"
        
        if is_straight:
            return 4, "Straight"
        
        if 3 in rank_cnt.values():
            return 3, "Three of a Kind"
        
        pairs = [r for r, c in rank_cnt.items() if c == 2]
        if len(pairs) >= 2:
            return 2, "Two Pair"
        
        if len(pairs) == 1:
            return 1, "Pair"
        
        return 0, "High Card"
    
    @staticmethod
    def calculate_equity(hole: List, board: List, opponents: int = 1) -> float:
        """Berechnet Equity (Gewinnchance)"""
        if len(hole) < 2:
            return 0.0
        
        # Vereinfachte Equity-Berechnung
        base = 0.5
        
        # Hole Cards Stärke
        if len(hole) == 2:
            ranks = sorted([c[1] for c in hole], reverse=True)
            
            # Pocket Pair
            if ranks[0] == ranks[1]:
                if ranks[0] >= 12:  # AA-KK
                    base += 0.35
                elif ranks[0] >= 10:  # QQ-JJ
                    base += 0.25
                else:
                    base += 0.15
            
            # High cards
            high = max(ranks)
            suited = hole[0][0] == hole[1][0]
            
            if high >= 12:  # AK
                base += 0.20
            elif high >= 11:  # AQ-AJ, KQ
                base += 0.12
        
        # Board-Bonus
        if len(board) >= 3:
            base += 0.15
        if len(board) >= 4:
            base += 0.10
        if len(board) == 5:
            # Stage hand evaluation
            rank, name = PokerMath.evaluate_7_cards(hole + board)
            base = 0.5 + (rank * 0.12)
        
        # Position & Opponents
        base += max(0, (6 - opponents) * 0.02)
        
        return min(base, 0.98)
    
    @staticmethod
    def get_recommendation(equity: float, pot_odds: float, street: int) -> Tuple[str, str]:
        """Beste Empfehlung basierend auf Equity vs Pot-Odds"""
        
        ev = equity - pot_odds
        
        # Preflop
        if street == 0:
            if equity > 0.70:
                return "RAISE 3x", "stark"
            elif equity > 0.50:
                return "CALL", "ok"
            else:
                return "FOLD", "schwach"
        
        # Post-flop
        if equity > 0.80:
            return "ALL-IN", "monster"
        elif equity > 0.65:
            return "BET 2/3 POT", "stark"
        elif equity > 0.50:
            if pot_odds < equity:
                return "CALL", "profitabel"
            else:
                return "CHECK", "abwarten"
        elif equity > 0.35:
            if pot_odds < 0.20:
                return "CALL", "billig"
            else:
                return "CHECK/FOLD", "scheck"
        else:
            return "FOLD", "schwach"


class CardRecognizer:
    """Erkennt Karten vom Bildschirm"""
    
    # Bekannte Poker-Plattformen (vereinfacht)
    RANK_TEMPLATES = {
        'A': ['A', 'ACE', 'As'],
        'K': ['K', 'KING', 'Ks'],
        'Q': ['Q', 'QUEEN', 'Qs'],
        'J': ['J', 'JACK', 'Js'],
        '10': ['10', 'TEN', 'Ts'],
        '9': ['9', '9s'],
        '8': ['8', '8s'],
    }
    
    SUIT_SYMBOLS = {
        '♥': 'hearts', '♦': 'diamonds', 
        '♣': 'clubs', '♠': 'spades',
        'h': 'hearts', 'd': 'diamonds',
        'c': 'clubs', 's': 'spades'
    }
    
    @staticmethod
    def detect_cards(frame) -> Tuple[List, List]:
        """
        Erkennt Karten im Frame
        Returns: (hero_cards, board_cards)
        
        In echter Version: ML-Modell für OCR
        """
        # Hier würde echte OCR/ML-Erkennung laufen
        # Für Demo: returning mock data
        return [], []


class ScreenPokerAssistant:
    """Hauptklasse - Poker Bot für Bildschirm"""
    
    def __init__(self):
        # Kamera
        print("📷 Initialisiere...")
        self.cap = cv2.VideoCapture(0)
        if not self.cap.isOpened():
            print("❌ Keine Kamera!")
            exit(1)
        
        # Optimal für Screen-Reading
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1920)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 1080)
        self.cap.set(cv2.CAP_PROP_FPS, 30)
        
        # State
        self.hero: List[Tuple] = []    # (suit, rank)
        self.board: List[Tuple] = []   # (suit, rank)
        self.pot: float = 0
        self.to_call: float = 0
        self.position: str = "BTN"
        self.opponents: int = 6
        
        # Berechnungen
        self.equity: float = 0
        self.pot_odds: float = 0
        self.hand_name: str = ""
        self.hand_rank: int = 0
        self.recommendation: str = ""
        self.reason: str = ""
        
        # KartenKiller
        self.board_texture: str = "unknown"
        self.board_danger: int = 0
        
        # TTS
        self.tts = self._init_tts()
        self.last_speak = 0
        
        # Demo
        self.demo_cards = self._create_demo_deck()
        self.demo_idx = 0
        
        self.running = True
        print("✅ Poker Bot bereit!\n")
    
    def _init_tts(self):
        try:
            engine = pyttsx3.init()
            engine.setProperty('rate', 165)
            engine.setProperty('volume', 0.9)
            print("🔊 TTS: AN\n")
            return engine
        except:
            print("⚠️ TTS: AUS\n")
            return None
    
    def _create_demo_deck(self):
        suits = ['h', 'd', 'c', 's']
        ranks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6']
        return [(s, r) for s in suits for r in ranks]
    
    def _speak(self, text: str, force: bool = False):
        if not self.tts:
            return
        now = time.time()
        if not force and now - self.last_speak < 5:
            return
        self.last_speak = now
        
        def talk():
            try:
                self.tts.say(text)
                self.tts.runAndWait()
            except:
                pass
        threading.Thread(target=talk, daemon=True).start()
    
    def _add_card(self):
        """Fügt Karte hinzu (Demo)"""
        if len(self.hero) < 2:
            self.hero.append(self.demo_cards[self.demo_idx])
            self._speak("Karte")
        elif len(self.board) < 5:
            self.board.append(self.demo_cards[self.demo_idx + 2])
            names = {3: "Flop", 4: "Turn", 5: "River"}
            self._speak(names.get(len(self.board), "Karte"))
        else:
            self.hero = []
            self.board = []
            self._speak("Neue Hand")
        
        self.demo_idx = (self.demo_idx + 1) % len(self.demo_cards)
        self._recalculate()
    
    def _recalculate(self):
        """Berechnet alles neu"""
        street = len(self.board)
        
        # Equity
        self.equity = PokerMath.calculate_equity(self.hero, self.board, self.opponents)
        
        # Pot Odds
        if self.to_call > 0 and self.pot > 0:
            self.pot_odds = self.to_call / (self.pot + self.to_call)
        else:
            self.pot_odds = 0
        
        # Hand Name
        if len(self.hero + self.board) >= 5:
            self.hand_rank, self.hand_name = PokerMath.evaluate_7_cards(self.hero + self.board)
        else:
            self.hand_name = f"({len(self.hero)} Karten)"
        
        # === KARTENKILLER ML EMPFEHLUNG ===
        kk_action = None
        if kk is not None and len(self.hero) >= 2:
            try:
                # Erstelle KartenKiller State
                kk_state = PokerGameState()
                kk_state.position = 2  # BTN als Default
                kk_state.street = street
                kk_state.hand_rank = self.hand_rank if self.hand_rank else 0
                kk_state.pot = self.pot
                kk_state.to_call = self.to_call
                kk_state.stack_size = 200  # Default Stack
                kk_state.opponents = self.opponents
                
                # Board Karten
                if self.board:
                    suits = {'hearts': 'h', 'diamonds': 'd', 'clubs': 'c', 'spades': 's'}
                    kk_state.board_cards = []
                    for card in self.board:
                        if len(card) >= 2:
                            s, r = card
                            kk_state.board_cards.append(f"{r}{suits.get(s, 's')}")
                
                # Hole KartenKiller Empfehlung
                kk_rec = kk.get_recommendation(kk_state)
                kk_action = kk_rec.get('action', '').upper()
                
                # Board Analyse für UI
                if kk_rec.get('board_analysis'):
                    self.board_texture = kk_rec['board_analysis'].get('texture', 'unknown')
                    self.board_danger = kk_rec['board_analysis'].get('danger', 0)
                else:
                    self.board_texture = 'unknown'
                    self.board_danger = 0
                    
            except Exception as e:
                print(f"KartenKiller Fehler: {e}")
        
        # === FALLBACK: Klassische Empfehlung ===
        math_recommendation, math_reason = PokerMath.get_recommendation(
            self.equity, self.pot_odds, street
        )
        
        # === HYBRID: Kombiniere beide (KartenKiller hat Vorrang wenn verfügbar) ===
        if kk_action and kk_action not in ['CALL', 'CHECK']:
            # KartenKiller sagt RAISE/BET/ALL-IN - nimm das
            self.recommendation = kk_action
            self.reason = "🤖 KartenKiller AI"
        elif kk_action == 'CALL':
            # Bei CALL nimm die stärkere von beiden
            if 'RAISE' in math_recommendation or 'ALL-IN' in math_recommendation:
                self.recommendation = math_recommendation
                self.reason = math_reason
            else:
                self.recommendation = kk_action
                self.reason = "🤖 KartenKiller AI"
        else:
            # Fallback zu klassisch
            self.recommendation = math_recommendation
            self.reason = math_reason
        
        # Markiere KartenKiller Empfehlungen
        if "KartenKiller" in self.reason:
            self.recommendation = f"🤖{self.recommendation}"
        
        # Auto-speak bei wichtigen Entscheidungen
        if "ALL-IN" in self.recommendation or "FOLD" in self.recommendation:
            self._speak(self.recommendation.replace("🤖", ""))
    
    def _set_pot(self, pot: float, to_call: float):
        """Setzt Pot-Daten"""
        self.pot = pot
        self.to_call = to_call
        self._recalculate()
    
    def _draw_card(self, f, x, y, card: Tuple, small: bool = False):
        if not card:
            return
        suit, rank = card
        cw, ch = (35, 50) if small else (50, 70)
        
        # Farbe
        is_red = suit in ['h', 'd']
        bg = (70, 45, 45) if is_red else (40, 45, 75)
        fg = (255, 200, 200) if is_red else (200, 220, 255)
        
        # Zeichnen
        cv2.rectangle(f, (x, y), (x + cw, y + ch), bg, -1)
        cv2.rectangle(f, (x, y), (x + cw, y + ch), fg, 1)
        
        # Rank
        cv2.putText(f, rank, (x + 5, y + 18), cv2.FONT_HERSHEY_SIMPLEX, 
                   0.4 if small else 0.5, fg, 2)
        
        # Suit
        sym = {'h': '♥', 'd': '♦', 'c': '♣', 's': '♠'}
        cv2.putText(f, sym.get(suit, '?'), (x + 12, y + 35 if small else 48), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5 if small else 0.6, fg, 2)
    
    def _draw_ui(self, frame):
        h, w = frame.shape[:2]
        
        # Header
        cv2.rectangle(frame, (0, 0), (w, 60), COLOR_BG, -1)
        cv2.putText(frame, "♠️ POKER BOT PRO", (20, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.85, COLOR_PRIMARY, 2)
        
        # Street
        streets = {0: "PRE-FLOP", 3: "FLOP", 4: "TURN", 5: "RIVER"}
        st = streets.get(len(self.board), "?")
        cv2.putText(frame, f"  {st}", (w - 180, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, COLOR_WARNING, 2)
        
        # ==================== HERO CARDS ====================
        y_card = h - 170
        cv2.rectangle(frame, (15, y_card - 30), (200, h - 50), COLOR_PANEL, -1)
        cv2.rectangle(frame, (15, y_card - 30), (200, h - 50), COLOR_PRIMARY, 2)
        cv2.putText(frame, "DEINE HAND", (25, y_card), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
        
        if self.hero:
            for i, c in enumerate(self.hero):
                self._draw_card(frame, 35 + i * 65, y_card + 15, c)
        else:
            cv2.putText(frame, "Warte auf Karten...", (40, y_card + 50), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (120, 120, 120), 1)
        
        # ==================== BOARD ====================
        if self.board:
            y_board = h - 290
            cv2.rectangle(frame, (15, y_board - 30), (w - 15, y_board + 55), COLOR_PANEL, -1)
            cv2.putText(frame, "TISCH", (25, y_board), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, COLOR_TEXT, 1)
            
            start_x = 120
            for i, c in enumerate(self.board):
                self._draw_card(frame, start_x + i * 70, y_board + 15, c)
        
        # ==================== HAND RANK ====================
        if self.hand_name and "Incomplete" not in self.hand_name:
            y_rank = h - 360
            cv2.rectangle(frame, (15, y_rank - 25), (400, y_rank + 5), COLOR_PANEL, -1)
            cv2.putText(frame, f"HAND: {self.hand_name.upper()}", (25, y_rank), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_SUCCESS, 2)
        
        # ==================== RECOMMENDATION ====================
        if self.recommendation:
            box_w, box_h = 380, 130
            box_x = (w - box_w) // 2
            box_y = h // 2 - 40
            
            # Farbe
            if "ALL-IN" in self.recommendation:
                rc = (255, 0, 255)  # Purple
            elif "RAISE" in self.recommendation or "BET" in self.recommendation:
                rc = COLOR_SUCCESS
            elif "CALL" in self.recommendation:
                rc = COLOR_PRIMARY
            elif "CHECK" in self.recommendation:
                rc = COLOR_WARNING
            else:
                rc = COLOR_DANGER
            
            # Box
            cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), COLOR_PANEL, -1)
            cv2.rectangle(frame, (box_x, box_y), (box_x + box_w, box_y + box_h), rc, 4)
            
            # Empfehlung
            ts = cv2.getTextSize(self.recommendation, cv2.FONT_HERSHEY_SIMPLEX, 1.4, 3)[0]
            tx = (w - ts[0]) // 2
            cv2.putText(frame, self.recommendation, (tx, box_y + 45), 
                        cv2.FONT_HERSHEY_SIMPLEX, 1.4, rc, 3)
            
            # Stats
            eq_txt = f"Equity: {self.equity*100:.0f}% | Odds: {self.pot_odds*100:.0f}%"
            ts2 = cv2.getTextSize(eq_txt, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)[0]
            tx2 = (w - ts2[0]) // 2
            cv2.putText(frame, eq_txt, (tx2, box_y + 80), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, COLOR_TEXT, 1)
            
            # Reason
            cv2.putText(frame, f"→ {self.reason}", (box_x + 20, box_y + 110), 
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (180, 180, 180), 1)
        
        # ==================== POT INFO ====================
        # Info Panel rechts
        px = w - 250
        py = 75
        cv2.rectangle(frame, (px, py), (px + 230, py + 100), COLOR_PANEL, -1)
        
        cv2.putText(frame, f"Pot: ${self.pot:.0f}", (px + 15, py + 25), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        cv2.putText(frame, f"Call: ${self.to_call:.0f}", (px + 15, py + 50), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, COLOR_TEXT, 1)
        cv2.putText(frame, f"Pos: {self.position} | Gegner: {self.opponents}", (px + 15, py + 80), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (150, 150, 150), 1)
        
        # ==================== EQUITY BAR ====================
        bar_y = h - 395
        bar_w = 300
        cv2.rectangle(frame, (15, bar_y), (15 + bar_w, bar_y + 25), COLOR_PANEL, -1)
        cv2.putText(frame, "EQUITY", (20, bar_y + 18), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, COLOR_TEXT, 1)
        
        # Balken
        eq_w = int(bar_w * self.equity)
        eq_col = COLOR_SUCCESS if self.equity > 0.5 else COLOR_WARNING if self.equity > 0.3 else COLOR_DANGER
        cv2.rectangle(frame, (80, bar_y + 5), (80 + eq_w, bar_y + 20), eq_col, -1)
        cv2.putText(frame, f"{self.equity*100:.0f}%", (80 + eq_w + 10, bar_y + 18), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, eq_col, 1)
        
        # ==================== CONTROLS ====================
        cv2.putText(frame, "[D] Karte [P] Position [O] Pot [R] Reset [T] TTS [Q] Quit", 
                    (20, h - 15), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (80, 80, 80), 1)
    
    def run(self):
        print("=" * 50)
        print("♠️ POKER BOT PRO - BILDschirm LESER")
        print("=" * 50)
        print("Richte Kamera auf deinen Poker-Bildschirm!")
        print()
        print("Steuerung:")
        print("  [D] = Demo Karte hinzufügen")
        print("  [P] = Position zyklieren")
        print("  [O] = Pot setzen (Demo: 100/20)")
        print("  [R] = Reset")
        print("  [T] = TTS an/aus")
        print("  [Q] = Beenden")
        print("=" * 50 + "\n")
        
        # Demo Pot
        self._set_pot(100, 20)
        
        while self.running:
            ret, frame = self.cap.read()
            if not ret:
                break
            
            # Spiegeln
            frame = cv2.flip(frame, 1)
            
            # UI
            self._draw_ui(frame)
            
            # Show
            cv2.imshow('♠️ POKER BOT PRO', frame)
            
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                self.running = False
            elif key == ord('d'):
                self._add_card()
            elif key == ord('r'):
                self.hero = []
                self.board = []
                self._recalculate()
                self._speak("Reset")
            elif key == ord('p'):
                pos = ["UTG", "UTG+1", "MP", "CO", "BTN", "SB", "BB"]
                try:
                    i = pos.index(self.position)
                    self.position = pos[(i + 1) % len(pos)]
                except:
                    self.position = "BTN"
                self._recalculate()
            elif key == ord('o'):
                self._set_pot(100, 20)
            elif key == ord('t'):
                if self.tts:
                    self.tts = None
                    print("🔇 TTS: AUS")
                else:
                    self.tts = self._init_tts()
        
        self._cleanup()
    
    def _cleanup(self):
        self.cap.release()
        cv2.destroyAllWindows()
        print("\n👋 Bot beendet!")


# ===================== MAIN =====================
if __name__ == "__main__":
    # KartenKiller ML initialisieren
    init_karten_killer()
    
    # Starte Poker Bot
    ScreenPokerAssistant().run()
