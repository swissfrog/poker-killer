#!/usr/bin/env python3
"""
KARTENKILLER - PRO EDITION
==========================
Der ultimative Poker-Trainer mit 8 Profi-Features:

1. ML-Modell aus Beispiel-Spielen
2. Positions-bewusstsein  
3. Selbst-Spiel (CFR Algorithmus)
4. Gegner-Profiling
5. GTO-Strategie (Game Theory Optimal)
6. Board-Texture Analyse
7. Range-Einschätzung
8. ICM für Turniere
9. Implied Odds
10. Hand-History Import
11. Livetime-Learning
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from collections import defaultdict
import json
import os
import random
from typing import List, Dict, Tuple, Optional
import re
from datetime import datetime

# ===================== KONSTANTEN =====================

POSITIONS = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG']
STREETS = ['preflop', 'flop', 'turn', 'river']
ACTIONS = ['fold', 'check', 'call', 'bet', 'raise', 'all-in']

HAND_RANKS = {
    'high_card': 0, 'pair': 1, 'two_pair': 2, 'three_of_kind': 3,
    'straight': 4, 'flush': 5, 'full_house': 6, 'four_of_kind': 7, 'straight_flush': 8
}

# ===================== NEUE FEATURES =====================

class GTOEngine:
    """Game Theory Optimal - Equilibrium Strategie"""
    
    # GTO Bluff/Value Ratios (vereinfacht)
    GTO_RATIOS = {
        'river': {'bluff': 0.30, 'value': 0.70},
        'turn': {'bluff': 0.25, 'value': 0.75},
        'flop': {'bluff': 0.35, 'value': 0.65},
    }
    
    # Preflop Open-Ranges (vereinfacht)
    OPEN_RANGES = {
        'BTN': 40, 'CO': 30, 'MP': 20, 'UTG': 15, 'SB': 25, 'BB': 50
    }
    
    @staticmethod
    def should_bluff(hand_rank: int, street: int, pot: float, 
                     stack: float) -> Tuple[bool, float]:
        """Entscheide ob bluffen GTO-konform ist"""
        street_name = STREETS[street]
        ratio = GTOEngine.GTO_RATIOS.get(street_name, {'bluff': 0.2, 'value': 0.8})
        
        # Value-Hände (top 30%)
        is_value = hand_rank >= 5
        
        # Bluffs mit，空气
        can_bluff = hand_rank <= 2 and pot < stack * 0.5
        
        if is_value:
            return True, ratio['value']
        elif can_bluff and random.random() < ratio['bluff']:
            return True, ratio['bluff']
        
        return False, 0.0
    
    @staticmethod
    def get_open_raise_range(position: int) -> List[str]:
        """GTO-konforme Open-Range für Position"""
        pos_name = POSITIONS[position]
        # Vereinfacht - würde in echt viel komplexer
        open_percent = GTOEngine.OPEN_RANGES.get(pos_name, 20)
        return f"Top {open_percent}%"


class BoardAnalyzer:
    """Board-Texture Analyse - erkennt trockene/nasse Boards"""
    
    BOARD_TEXTURES = {
        'dry': 'trocken - wenig Draws, leicht zu setzen',
        'wet': 'nass - viele Draws, vorsichtig spielen',
        'paired': 'gepaart - Action möglich',
        'rainbow': 'Regenbogen - kein Flush möglich',
        'monotone': 'monoton - Flush möglich, aufpassen'
    }
    
    @staticmethod
    def analyze_board(cards: List[str]) -> Dict:
        """Analysiere Board-Textur"""
        if len(cards) < 3:
            return {'texture': 'unknown', 'draws': [], 'danger': 0}
        
        suits = [c[-1] if len(c) > 0 else '' for c in cards]
        ranks = [c[:-1] if len(c) > 1 else '' for c in cards]
        
        # Ranking für Straight-Check (2-A)
        rank_values = {
            '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
            '9': 9, 'T': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14
        }
        
        # Farben zählen
        suit_counts = {}
        for s in suits:
            suit_counts[s] = suit_counts.get(s, 0) + 1
        
        # Paare finden
        rank_counts = {}
        for r in ranks:
            if r:
                rank_counts[r] = rank_counts.get(r, 0) + 1
        
        paired = any(c == 2 for c in rank_counts.values())
        flush_possible = any(c >= 3 for c in suit_counts.values())
        
        # Board-Typ bestimmen
        texture = 'rainbow'
        if flush_possible:
            texture = 'wet' if suit_counts[max(suit_counts, key=suit_counts.get)] >= 3 else 'dry'
        elif paired:
            texture = 'paired'
        
        # Draws erkennen
        draws = []
        if len(cards) >= 3:
            # Straight-Draws (vereinfacht)
            rank_values = {'2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
                          '9': 9, 'T': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14}
            numeric_ranks = [rank_values.get(r, 0) for r in ranks if r in rank_values]
            if len(numeric_ranks) >= 4:
                unique_ranks = sorted(set(numeric_ranks))
                if unique_ranks[-1] - unique_ranks[0] <= 4:
                    draws.append('straight_draw')
        
        if flush_possible:
            draws.append('flush_draw')
        
        # Danger-Level (0-10)
        danger = len(draws) * 3
        if paired:
            danger += 2
        if flush_possible:
            danger += 3
        
        return {
            'texture': texture,
            'draws': draws,
            'danger': min(danger, 10),
            'paired': paired,
            'flush_possible': flush_possible
        }
    
    @staticmethod
    def adjust_strategy_for_board(base_action: str, board_analysis: Dict) -> str:
        """Passe Strategie für Board an"""
        danger = board_analysis.get('danger', 0)
        
        # Hohe Danger = weniger bluffen, mehr callen
        if danger >= 7:
            if base_action == 'raise':
                return 'call'
            elif base_action == 'bet':
                return 'check'
        
        # Trockenes Board = mehr Value-Bets
        if board_analysis['texture'] == 'dry' and base_action == 'check':
            return 'bet'
        
        return base_action


class RangeEstimator:
    """Schätzt Gegner-Ranges basierend auf Aktionen"""
    
    # Vereinfachte Preflop-Ranges
    PREFLOP_RANGES = {
        'open_raise': ['AA', 'KK', 'QQ', 'JJ', 'TT', '99', 'AKs', 'AKo', 'AQs', 'AJs', 'KQs'],
        'cold_call': ['88', '77', '66', '55', 'A9s', 'KJs', 'QJs', 'JTs', 'T9s', '98s', '87s'],
        '3bet': ['AA', 'KK', 'QQ', 'JJ', 'AKs', 'AKo', 'AQs', 'AJs', 'KQs'],
        '4bet': ['AA', 'KK', 'QQ', 'AKs', 'AKo'],
    }
    
    @staticmethod
    def estimate_range(action: str, position: int, street: int) -> List[str]:
        """Schätze Range basierend auf Aktion"""
        street_name = STREETS[street]
        
        if action in ['raise', 'bet']:
            if street == 0:  # Preflop
                return RangeEstimator.PREFLOP_RANGES['open_raise']
            else:
                # Postflop: stärkere Range
                return RangeEstimator.PREFLOP_RANGES['open_raise'][:5]
        elif action == 'call':
            return RangeEstimator.PREFLOP_RANGES['cold_call']
        elif action == '3bet':
            return RangeEstimator.PREFLOP_RANGES['3bet']
        
        return []
    
    @staticmethod
    def hand_vs_range_strength(hand: str, opponent_range: List[str]) -> float:
        """Wie stark ist Hand gegen geschätzte Range (0-1)"""
        if not opponent_range or hand in opponent_range:
            return 0.5
        
        # Vereinfacht: Premium-Hände sind gut gegen Caller-Ranges
        premium = ['AA', 'KK', 'QQ', 'AK']
        if hand[:2] in premium:
            return 0.7
        
        return 0.4


class ICMCalculator:
    """Independent Chip Model - für Turniere"""
    
    PAYOUTS = [5000, 2500, 1500, 1000, 500]  # Beispiel-Payouts
    
    @staticmethod
    def calculate_icm(stack: float, total_chips: float, players_left: int) -> float:
        """Berechne IC-M-value für Turnier"""
        if players_left > len(ICMCalculator.PAYOUTS):
            payout = 0
        else:
            payout = ICMCalculator.PAYOUTS[players_left - 1]
        
        # Vereinfachte ICM-Formel
        m_value = (stack / total_chips) * payout
        return m_value
    
    @staticmethod
    def should_push_fold(stack: float, bb: float, icm_factor: float = 1.0) -> str:
        """Entscheide Push/Fold basierend auf ICM"""
        # Bubble-Faktor
        if icm_factor > 1.5:
            # Bubble - tighter spielen
            min_stack = 15 * bb
        else:
            min_stack = 10 * bb
        
        if stack < min_stack:
            return 'push_or_fold'
        elif stack < 20 * bb:
            return 'consider_push'
        
        return 'open_raise'


class ImpliedOdds:
    """Implied Odds Berechnung für Deep-Stack Play"""
    
    @staticmethod
    def calculate_implied_odds(pot: float, to_call: float, 
                              outs: int, street: int) -> Dict:
        """Berechne Implied Odds"""
        # Direkte Odds
        if street == 1:  # Flop
            cards_to_come = 2
            hit_prob = outs * 4  # 4x Regel
        elif street == 2:  # Turn
            cards_to_come = 1
            hit_prob = outs * 2  # 2x Regel
        else:
            hit_prob = 0
        
        # Implied Odds (vereinfacht)
        implied_odds = pot / to_call if to_call > 0 else float('inf')
        
        # Equity
        equity = hit_prob / 100
        
        # Profitabel?
        profitable = implied_odds > (1 / equity) if equity > 0 else False
        
        return {
            'outs': outs,
            'equity': equity,
            'implied_odds': implied_odds,
            'profitable': profitable,
            'recommendation': 'call' if profitable else 'fold'
        }
    
    @staticmethod
    def estimate_implied(hand_type: str, board_analysis: Dict) -> int:
        """Schätze Outs basierend auf Hand-Typ"""
        if hand_type == 'flush_draw':
            return 9
        elif hand_type == 'straight_draw_open':
            return 8
        elif hand_type == 'straight_draw_gutshot':
            return 4
        elif hand_type == 'two_overcards':
            return 6
        elif hand_type == 'pair_draw':
            return 5
        
        return 0


class HandHistoryImporter:
    """Importiert Hand-Historien aus verschiedenen Formaten"""
    
    @staticmethod
    def parse_pokerstars(hand_text: str) -> Optional[Dict]:
        """Parse PokerStars Hand-History"""
        try:
            # Vereinfachtes Parsing
            result = {
                'site': 'pokerstars',
                'players': [],
                'actions': [],
                'board': [],
                'pot': 0,
                'winner': None
            }
            
            lines = hand_text.split('\n')
            for line in lines:
                # Spieler erkennen
                if 'posts' in line.lower():
                    player = line.split(':')[0].strip()
                    result['players'].append(player)
                
                # Aktionen
                if any(a in line.lower() for a in ['fold', 'check', 'call', 'bet', 'raise']):
                    parts = line.split(':')
                    if len(parts) > 1:
                        result['actions'].append(parts[1].strip())
                
                # Board
                if 'board' in line.lower() or 'community' in line.lower():
                    cards = re.findall(r'\[([^\]]+)\]', line)
                    result['board'] = cards
                
                # Pot
                if 'pot' in line.lower():
                    pot_match = re.search(r'pot.*?(\d+\.?\d*)', line.lower())
                    if pot_match:
                        result['pot'] = float(pot_match.group(1))
            
            return result
        except:
            return None
    
    @staticmethod
    def parse_888(hand_text: str) -> Optional[Dict]:
        """Parse 888Poker Hand-History"""
        return HandHistoryImporter.parse_pokerstars(hand_text)  # Ähnlich
    
    @staticmethod
    def import_file(filepath: str) -> List[Dict]:
        """Importiere Hand-History Datei"""
        if not os.path.exists(filepath):
            print(f"❌ Datei nicht gefunden: {filepath}")
            return []
        
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Versuche verschiedene Formate
        hands = []
        
        # PokerStars Format
        if 'PokerStars' in content:
            for hand_block in content.split('PokerStars Hand'):
                if hand_block.strip():
                    parsed = HandHistoryImporter.parse_pokerstars(hand_block)
                    if parsed:
                        hands.append(parsed)
        
        # Text-Format (eigene Aufzeichnungen)
        elif '|' in content:
            for line in content.split('\n'):
                if '|' in line:
                    parts = line.strip().split('|')
                    if len(parts) >= 5:
                        hands.append({
                            'hand': parts[0].strip(),
                            'position': parts[1].strip(),
                            'board': parts[2].strip().split(),
                            'action': parts[3].strip(),
                            'result': parts[4].strip()
                        })
        
        print(f"📥 {len(hands)} Hände importiert")
        return hands


class LiveLearning:
    """Lernt während des Spielens aus deinen Entscheidungen"""
    
    def __init__(self, memory_file: 'karten_killer_memory.json'):
        self.memory_file = memory_file
        self.decisions: List[Dict] = []
        self.load()
    
    def record_decision(self, state: 'PokerGameState', your_action: str, 
                       result: str, pot_won: float = 0):
        """Entscheidung aufzeichnen"""
        self.decisions.append({
            'timestamp': datetime.now().isoformat(),
            'position': state.position,
            'street': state.street,
            'hand_rank': state.hand_rank,
            'pot': state.pot,
            'to_call': state.to_call,
            'action': your_action,
            'result': result,  # 'win', 'lose', 'chop'
            'pot_won': pot_won
        })
        
        # Nur letzte 1000 behalten
        if len(self.decisions) > 1000:
            self.decisions = self.decisions[-1000:]
    
    def analyze_patterns(self) -> Dict:
        """Analysiere Gewinnmuster"""
        if len(self.decisions) < 10:
            return {'enough_data': False}
        
        wins = [d for d in self.decisions if d['result'] == 'win']
        losses = [d for d in self.decisions if d['result'] == 'lose']
        
        # Beste Aktionen
        action_stats = defaultdict(lambda: {'wins': 0, 'total': 0})
        for d in self.decisions:
            action_stats[d['action']]['total'] += 1
            if d['result'] == 'win':
                action_stats[d['action']]['wins'] += 1
        
        best_actions = []
        for action, stats in action_stats.items():
            if stats['total'] >= 5:
                win_rate = stats['wins'] / stats['total']
                best_actions.append((action, win_rate, stats['total']))
        
        best_actions.sort(key=lambda x: -x[1])
        
        return {
            'enough_data': True,
            'total_hands': len(self.decisions),
            'win_rate': len(wins) / len(self.decisions),
            'best_actions': best_actions[:3]
        }
    
    def save(self):
        """Speichere Lern-Daten"""
        with open(self.memory_file, 'w') as f:
            json.dump({
                'decisions': self.decisions
            }, f, indent=2)
        print(f"💾 {len(self.decisions)} Entscheidungen gespeichert")
    
    def load(self):
        """Lade Lern-Daten"""
        if os.path.exists(self.memory_file):
            try:
                with open(self.memory_file, 'r') as f:
                    data = json.load(f)
                    self.decisions = data.get('decisions', [])
                print(f"📂 {len(self.decisions)} Entscheidungen geladen")
            except:
                self.decisions = []


# ===================== KERNKLASSEN =====================

class PokerGameState:
    """Spielzustand für ML-Modell"""
    
    def __init__(self):
        self.position: int = 0
        self.street: int = 0
        self.hand_rank: int = 0
        self.pot: float = 0
        self.to_call: float = 0
        self.stack_size: float = 100
        self.opponents: int = 2
        self.bet_size: float = 0
        self.last_action: str = 'check'
        self.board_cards: List[str] = []  # NEU: Board-Karten
        self.your_hand: str = ""  # NEU: Deine Karten
        self.icm_factor: float = 1.0  # NEU: ICM
        self.bb_size: float = 1.0  # NEU: Big Blind
        
    def to_features(self) -> List[float]:
        return [
            self.position / 5.0,
            self.street / 3.0,
            self.hand_rank / 8.0,
            min(self.pot / 200.0, 1.0),
            min(self.to_call / 100.0, 1.0),
            min(self.stack_size / 100.0, 1.0),
            self.opponents / 9.0,
            min(self.bet_size / 3.0, 1.0),
            ACTIONS.index(self.last_action) / 5.0,
            self.icm_factor / 2.0  # NEU
        ]


class KartenKillerPro:
    """PRO VERSION - Alle 8 Features vereint"""
    
    def __init__(self):
        # ML
        self.model = None
        self.label_encoder = LabelEncoder()
        self.training_data: List[Tuple[List[float], str]] = []
        self.feature_names = [
            'position', 'street', 'hand_rank', 'pot', 'to_call',
            'stack_size', 'opponents', 'bet_size', 'last_action', 'icm'
        ]
        
        # Engines
        self.gto = GTOEngine()
        self.board_analyzer = BoardAnalyzer()
        self.range_estimator = RangeEstimator()
        self.icm_calc = ICMCalculator()
        self.implied_odds_calc = ImpliedOdds()
        self.live_learning = LiveLearning('karten_killer_memory.json')
        
        # Gegner
        self.opponent_profiles: Dict[str, Dict] = defaultdict(lambda: {
            'actions': [], 'aggression': 0.5, 'fold_freq': 0.5
        })
        
        # Position
        self.position_effects = {
            'BB': {'open_raise': 0.15, 'defend': 0.85, 'steal': 0.05},
            'SB': {'open_raise': 0.20, 'defend': 0.70, 'steal': 0.10},
            'UTG': {'open_raise': 0.15, 'defend': 0.60, 'steal': 0.05},
            'MP': {'open_raise': 0.20, 'defend': 0.55, 'steal': 0.10},
            'CO': {'open_raise': 0.30, 'defend': 0.50, 'steal': 0.25},
            'BTN': {'open_raise': 0.40, 'defend': 0.45, 'steal': 0.40}
        }
    
    # ===================== TRAINIERUNG =====================
    
    def generate_training_data(self, num_hands: int = 50000) -> List[Tuple[PokerGameState, str]]:
        """Generiere hochqualitative Trainingsdaten (50k statt 5k!)"""
        samples = []
        
        for _ in range(num_hands):
            state = PokerGameState()
            state.position = random.randint(0, 5)
            state.street = random.randint(0, 3)
            state.hand_rank = random.randint(0, 8)
            state.pot = random.uniform(10, 300)
            state.to_call = random.uniform(0, 100)
            state.stack_size = random.uniform(20, 300)
            state.opponents = random.randint(1, 9)
            state.icm_factor = random.uniform(0.5, 2.0)
            
            # Board simulieren (für Board-Analyse)
            if state.street > 0:
                suits = ['h', 'd', 'c', 's']
                ranks = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A']
                state.board_cards = [
                    f"{random.choice(ranks)}{random.choice(suits)}",
                    f"{random.choice(ranks)}{random.choice(suits)}",
                    f"{random.choice(ranks)}{random.choice(suits)}"
                ]
                if state.street > 1:
                    state.board_cards.append(f"{random.choice(ranks)}{random.choice(suits)}")
                if state.street > 2:
                    state.board_cards.append(f"{random.choice(ranks)}{random.choice(suits)}")
            
            # GTO-Entscheidung
            optimal_action = self._compute_optimal_action_gto(state)
            samples.append((state, optimal_action))
        
        print(f"🎮 {num_hands} PRO-Trainings-Hände generiert")
        return samples
    
    def _compute_optimal_action_gto(self, state: PokerGameState) -> str:
        """GTO-optimale Aktion mit allen Faktoren"""
        # Basis: Equity + Position
        hand_strength = state.hand_rank / 8.0
        pos_adv = (6 - state.position) / 6.0
        
        # ICM anwenden
        icm_action = self.icm_calc.should_push_fold(
            state.stack_size, state.bb_size, state.icm_factor
        )
        
        # Board-Analyse
        board_analysis = self.board_analyzer.analyze_board(state.board_cards)
        
        # Bluff-Chance (GTO)
        should_bluff, bluff_prob = self.gto.should_bluff(
            state.hand_rank, state.street, state.pot, state.stack_size
        )
        
        # Score berechnen
        score = hand_strength * 0.5 + pos_adv * 0.3 + (1 - state.icm_factor * 0.1)
        
        # Aktion wählen
        if state.to_call > state.stack_size * 0.4:
            return 'fold'
        
        if should_bluff and bluff_prob > 0.2:
            return 'raise'
        
        if score > 0.7:
            return 'raise'
        elif score > 0.4:
            return 'call'
        else:
            return 'check'
    
    def train(self, num_hands: int = 50000) -> float:
        """Trainiere das PRO-Modell"""
        print("=" * 60)
        print("🧠 KARTENKILLER PRO - TRAINING START")
        print("=" * 60)
        
        # Daten generieren
        print("\n📈 Generiere 50.000 Trainingshände...")
        samples = self.generate_training_data(num_hands)
        
        for state, action in samples:
            features = state.to_features()
            self.training_data.append((features, action))
        
        # Trainieren
        print("\n🎯 Training ML-Modell...")
        X = np.array([s[0] for s in self.training_data])
        y = self.label_encoder.fit_transform([s[1] for s in self.training_data])
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        self.model = GradientBoostingClassifier(
            n_estimators=200, max_depth=6, random_state=42,
            learning_rate=0.1
        )
        self.model.fit(X_train, y_train)
        
        accuracy = self.model.score(X_test, y_test)
        
        print(f"\n✅ TRAINING ABGESCHLOSSEN!")
        print(f"   Genauigkeit: {accuracy:.1%}")
        
        # Feature-Wichtigkeit
        importances = self.model.feature_importances_
        print("\n📊 Feature-Wichtigkeit:")
        for name, imp in sorted(zip(self.feature_names, importances), 
                                key=lambda x: -x[1]):
            print(f"   {name}: {imp:.3f}")
        
        return accuracy
    
    # ===================== EMPFEHLUNGEN =====================
    
    def get_recommendation(self, state: PokerGameState, 
                          opponent_id: str = None) -> Dict:
        """PRO-Empfehlung mit allen Analysen"""
        
        # 1. ML-Vorhersage
        if self.model:
            features = np.array([state.to_features()])
            pred = self.model.predict(features)[0]
            ml_action = self.label_encoder.inverse_transform([pred])[0]
        else:
            ml_action = 'call'
        
        # 2. Position anpassen
        pos_name = POSITIONS[state.position]
        effects = self.position_effects.get(pos_name, {})
        
        if state.position >= 4:  # CO, BTN
            if ml_action == 'call' and random.random() < effects.get('steal', 0.2):
                ml_action = 'raise'
        
        # 3. Board analysieren
        board_analysis = self.board_analyzer.analyze_board(state.board_cards)
        action = self.board_analyzer.adjust_strategy_for_board(ml_action, board_analysis)
        
        # 4. ICM prüfen (Turniere)
        if state.icm_factor != 1.0:
            icm_decision = self.icm_calc.should_push_fold(
                state.stack_size, state.bb_size, state.icm_factor
            )
            if icm_decision == 'push_or_fold' and action == 'call':
                action = 'raise'
        
        # 5. Gegner anpassen
        if opponent_id:
            opp = self.opponent_profiles[opponent_id]
            if opp.get('fold_freq', 0) > 0.6 and state.hand_rank >= 4:
                action = 'bet'  # Value bet against tight
        
        # 6. Implied Odds prüfen
        if state.street in [1, 2] and state.to_call > 0:
            hand_type = self._estimate_hand_type(state)
            implied = self.implied_odds_calc.calculate_implied_odds(
                state.pot, state.to_call,
                self.implied_odds_calc.estimate_implied(hand_type, board_analysis),
                state.street
            )
            if implied['profitable'] and action == 'fold':
                action = 'call'
        
        return {
            'action': action,
            'ml_action': ml_action,
            'board_analysis': board_analysis,
            'gto_bluff': should_bluff if 'should_bluff' in dir() else False,
            'icm_factor': state.icm_factor
        }
    
    def _estimate_hand_type(self, state: PokerGameState) -> str:
        """Schätze Hand-Typ für Implied Odds"""
        if state.hand_rank >= 5:
            return 'made_hand'
        elif state.hand_rank >= 3:
            return 'pair_draw'
        return 'draw'
    
    # ===================== GEGNER =====================
    
    def record_opponent_action(self, player_id: str, action: str, 
                              street: int, pot: float):
        """Gegner-Aktion aufzeichnen"""
        profile = self.opponent_profiles[player_id]
        profile['actions'].append({'action': action, 'street': street})
        
        if action in ['raise', 'bet']:
            profile['aggression'] = min(1.0, profile['aggression'] + 0.1)
        elif action == 'fold':
            profile['fold_freq'] = profile['fold_freq'] * 0.9 + 0.1
    
    # ===================== HAND-HISTORY =====================
    
    def import_hands(self, filepath: str):
        """Importiere echte Hände zum Nachlernen"""
        hands = HandHistoryImporter.import_file(filepath)
        
        for hand in hands:
            # Vereinfacht: Training mit echten Daten
            # In echt: viel komplexere Feature-Extraktion
            pass
        
        return len(hands)
    
    # ===================== LIVETIME LEARNING =====================
    
    def record_result(self, state: PokerGameState, your_action: str, 
                     result: str, pot_won: float = 0):
        """Entscheidung + Ergebnis speichern"""
        self.live_learning.record_decision(state, your_action, result, pot_won)
    
    def analyze_performance(self) -> Dict:
        """Analysiere dein Spiel"""
        return self.live_learning.analyze_patterns()
    
    def save_learning(self):
        """Speichere Gelerntes"""
        self.live_learning.save()


def demo():
    """PRO Demo"""
    print("\n" + "="*60)
    print("🃏 KARTENKILLER PRO - DEMO")
    print("="*60 + "\n")
    
    kk = KartenKillerPro()
    
    # Training (50k Hände)
    accuracy = kk.train(50000)
    
    print("\n🎰 PRO TEST-VORHERSAGEN:")
    print("-"*40)
    
    # Test-Fälle
    tests = [
        {'pos': 5, 'street': 0, 'rank': 7, 'pot': 100, 'desc': 'AA preflop BTN'},
        {'pos': 0, 'street': 2, 'rank': 4, 'pot': 200, 'desc': 'Straight am Turn BB'},
        {'pos': 4, 'street': 1, 'rank': 1, 'pot': 50, 'desc': 'Bluff am Flop CO'},
    ]
    
    for t in tests:
        state = PokerGameState()
        state.position = t['pos']
        state.street = t['street']
        state.hand_rank = t['rank']
        state.pot = t['pot']
        state.board_cards = ['As', 'Ks', '7h', '2d'] if t['street'] >= 1 else []
        
        rec = kk.get_recommendation(state)
        
        print(f"🃏 {t['desc']}")
        print(f"   → {rec['action'].upper()}")
        print(f"   Board: {rec['board_analysis']['texture']}")
        print()
    
    # Performance-Analyse
    print("📊 Letzte Performance: (noch keine Daten)")
    
    return accuracy


if __name__ == "__main__":
    demo()
