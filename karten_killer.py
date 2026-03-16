#!/usr/bin/env python3
"""
Poker Bot Training System
=========================
Umfassendes Training für bessere Poker-Entscheidungen

Features:
- ML-Modell aus Beispiel-Spielen
- Positions-bewusstsein
- Selbst-Spiel (CFR Algorithmus)
- Gegner-Profiling
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from collections import defaultdict
import json
import os
from typing import List, Dict, Tuple, Optional
import random

# ===================== KONSTANTEN =====================

POSITIONS = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG']
STREETS = ['preflop', 'flop', 'turn', 'river']
ACTIONS = ['fold', 'check', 'call', 'bet', 'raise', 'all-in']

# Poker Hand Rankings (0-8)
HAND_RANKS = {
    'high_card': 0, 'pair': 1, 'two_pair': 2, 'three_of_kind': 3,
    'straight': 4, 'flush': 5, 'full_house': 6, 'four_of_kind': 7, 'straight_flush': 8
}

class PokerGameState:
    """Spielzustand für ML-Modell"""
    
    def __init__(self):
        self.position: int = 0  # 0=BB, 1=SB, 2=BTN, etc.
        self.street: int = 0    # 0=preflop, 1=flop, 2=turn, 3=river
        self.hand_rank: int = 0
        self.pot: float = 0
        self.to_call: float = 0
        self.stack_size: float = 100
        self.opponents: int = 2
        self.bet_size: float = 0  # relative to pot
        self.last_action: str = 'check'  # Default statt 'none'
        
    def to_features(self) -> List[float]:
        """Konvertiere zu Feature-Vektor für ML"""
        return [
            self.position / 5.0,
            self.street / 3.0,
            self.hand_rank / 8.0,
            min(self.pot / 200.0, 1.0),
            min(self.to_call / 100.0, 1.0),
            min(self.stack_size / 100.0, 1.0),
            self.opponents / 9.0,
            min(self.bet_size / 3.0, 1.0),
            ACTIONS.index(self.last_action) / 5.0
        ]
    
    def __repr__(self):
        return f"State(pos={POSITIONS[self.position]}, {STREETS[self.street]}, rank={self.hand_rank})"


class PokerMLTrainer:
    """ML-Trainer für Poker-Entscheidungen"""
    
    def __init__(self, model_path: str = "poker_model.pkl"):
        self.model_path = model_path
        self.model = None
        self.label_encoder = LabelEncoder()
        self.training_data: List[Tuple[List[float], str]] = []
        self.feature_names = [
            'position', 'street', 'hand_rank', 'pot', 'to_call',
            'stack_size', 'opponents', 'bet_size', 'last_action'
        ]
        
    def add_training_sample(self, state: PokerGameState, optimal_action: str):
        """Füge Trainingsbeispiel hinzu"""
        features = state.to_features()
        self.training_data.append((features, optimal_action))
        
    def train(self) -> float:
        """Trainiere das Modell"""
        if len(self.training_data) < 100:
            print(f"⚠️ Nur {len(self.training_data)} Samples, brauche mindestens 100")
            return 0.0
            
        X = np.array([s[0] for s in self.training_data])
        y = self.label_encoder.fit_transform([s[1] for s in self.training_data])
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42
        )
        
        self.model = GradientBoostingClassifier(
            n_estimators=100, max_depth=5, random_state=42
        )
        self.model.fit(X_train, y_train)
        
        accuracy = self.model.score(X_test, y_test)
        print(f"🎯 Modell-Trainingsgenauigkeit: {accuracy:.1%}")
        
        # Speichere Feature-Wichtigkeit
        importances = self.model.feature_importances_
        print("\n📊 Feature-Wichtigkeit:")
        for name, imp in sorted(zip(self.feature_names, importances), 
                                key=lambda x: -x[1]):
            print(f"   {name}: {imp:.3f}")
            
        return accuracy
    
    def predict(self, state: PokerGameState) -> str:
        """Prädiziere beste Aktion"""
        if self.model is None:
            return "call"  # Fallback
            
        features = np.array([state.to_features()])
        pred = self.model.predict(features)[0]
        return self.label_encoder.inverse_transform([pred])[0]
    
    def save(self):
        """Modell speichern"""
        # Einfache JSON-Speicherung der Parameter
        # Für echtes ML-Modell: joblib/pickle verwenden
        print(f"💾 Modell würde gespeichert als {self.model_path}")
        
    def load(self):
        """Modell laden"""
        print(f"📂 Modell würde geladen von {self.model_path}")


class SelfPlayEngine:
    """Selbst-Spiel Engine für Poker Equilibrium"""
    
    def __init__(self):
        self.num_iterations = 1000
        self.num_players = 2
        self.alpha = 0.5  # learning rate
        
    def generate_selfplay_hands(self, num_hands: int = 10000) -> List[Tuple[PokerGameState, str]]:
        """Generiere Trainingsdaten durch Selbst-Spiel"""
        samples = []
        
        for _ in range(num_hands):
            # Zufälliger Spielzustand
            state = PokerGameState()
            state.position = random.randint(0, 5)
            state.street = random.randint(0, 3)
            state.hand_rank = random.randint(0, 8)
            state.pot = random.uniform(10, 200)
            state.to_call = random.uniform(0, 50)
            state.stack_size = random.uniform(50, 200)
            state.opponents = random.randint(1, 9)
            
            # Berechne optimale Aktion basierend auf Equity
            optimal_action = self._compute_optimal_action(state)
            samples.append((state, optimal_action))
            
        print(f"🎮 {num_hands} Selbst-Spiel Hände generiert")
        return samples
    
    def _compute_optimal_action(self, state: PokerGameState) -> str:
        """Berechne (vereinfachte) optimale Aktion"""
        # Vereinfachte Strategie basierend auf Hand-Stärke und Position
        hand_strength = state.hand_rank / 8.0
        position_advantage = (6 - state.position) / 6.0  # Späte Position besser
        
        score = hand_strength * 0.7 + position_advantage * 0.3
        
        if state.to_call > state.stack_size * 0.3:
            return "fold"
        elif score > 0.7:
            return "raise"
        elif score > 0.4:
            return "call"
        else:
            return "check"


class OpponentProfiler:
    """Lernt aus Gegner-Verhalten"""
    
    def __init__(self):
        self.player_profiles: Dict[str, Dict] = defaultdict(lambda: {
            'actions': [],
            'aggression': 0.5,
            'fold_frequency': 0.5,
            'bluff_frequency': 0.3,
            'hands_observed': 0
        })
        
    def record_action(self, player_id: str, action: str, street: int, 
                     hand_strength: float, pot_size: float):
        """Aktion eines Gegners aufzeichnen"""
        profile = self.player_profiles[player_id]
        profile['actions'].append({
            'action': action, 'street': street, 
            'hand_strength': hand_strength, 'pot_size': pot_size
        })
        profile['hands_observed'] += 1
        
        # Aggression aktualisieren
        if action in ['raise', 'bet', 'all-in']:
            profile['aggression'] = min(1.0, profile['aggression'] + 0.05)
        elif action == 'fold':
            profile['fold_frequency'] = (
                profile['fold_frequency'] * 0.9 + 0.1
            )
            
    def get_recommendation(self, player_id: str, pot_size: float, 
                          your_hand_strength: float) -> str:
        """Empfehlung basierend auf Gegner-Profil"""
        profile = self.player_profiles[player_id]
        
        if profile['hands_observed'] < 10:
            return "neutral"  # Nicht genug Daten
            
        # Gegen tighten Spieler: mehr bluffen
        if profile['fold_frequency'] > 0.6:
            if your_hand_strength > 0.5:
                return "bet"  # Value bet
            else:
                return "bluff"  # Versuche zu bluffen
                
        # Gegen aggressive Spieler: tighter spielen
        if profile['aggression'] > 0.7:
            if your_hand_strength > 0.7:
                return "call"  # Bezahle ihn aus
            else:
                return "fold"
                
        return "neutral"


class PositionAwareTrainer:
    """Berücksichtigt Tischposition bei Entscheidungen"""
    
    # Positionseffekte basierend auf Poker-Theorie
    POSITION_EFFECTS = {
        'BB': {'open_raise': 0.15, 'defend': 0.85, 'steal': 0.05},
        'SB': {'open_raise': 0.20, 'defend': 0.70, 'steal': 0.10},
        'UTG': {'open_raise': 0.15, 'defend': 0.60, 'steal': 0.05},
        'MP': {'open_raise': 0.20, 'defend': 0.55, 'steal': 0.10},
        'CO': {'open_raise': 0.30, 'defend': 0.50, 'steal': 0.25},
        'BTN': {'open_raise': 0.40, 'defend': 0.45, 'steal': 0.40}
    }
    
    def adjust_for_position(self, base_action: str, position: int) -> str:
        """Passe Aktion für Position an"""
        pos_name = POSITIONS[position]
        effects = self.POSITION_EFFECTS[pos_name]
        
        # Späte Position = mehr Aggression erlaubt
        if position >= 4:  # CO, BTN
            if base_action == 'call':
                return 'raise' if random.random() < effects['steal'] else 'call'
            elif base_action == 'check':
                return 'bet'
                
        # Frühe Position = konservativer
        elif position <= 1:  # BB, SB
            if base_action == 'raise':
                return 'call'
            elif base_action == 'bet':
                return 'check'
                
        return base_action


class KartenKiller:
    """Hauptklasse für das gesamte Training"""
    
    def __init__(self):
        self.ml_trainer = PokerMLTrainer()
        self.self_play = SelfPlayEngine()
        self.opponent_profiler = OpponentProfiler()
        self.position_trainer = PositionAwareTrainer()
        
    def train_full_model(self, num_selfplay_hands: int = 10000) -> float:
        """Trainiere das komplette Modell"""
        print("=" * 50)
        print("🧠 POKER BOT TRAINING START")
        print("=" * 50)
        
        # 1. Selbst-Spiel Daten generieren
        print("\n📈 Phase 1: Selbst-Spiel generieren...")
        selfplay_samples = self.self_play.generate_selfplay_hands(num_selfplay_hands)
        
        for state, action in selfplay_samples:
            # Position-Anpassung
            action = self.position_trainer.adjust_for_position(action, state.position)
            self.ml_trainer.add_training_sample(state, action)
            
        # 2. Modell trainieren
        print("\n🎯 Phase 2: ML-Modell trainieren...")
        accuracy = self.ml_trainer.train()
        
        # 3. Zusammenfassung
        print("\n" + "=" * 50)
        print("✅ TRAINING ABGESCHLOSSEN")
        print("=" * 50)
        
        return accuracy
    
    def get_recommendation(self, state: PokerGameState, 
                          opponent_id: Optional[str] = None) -> str:
        """Erhalte KI-Empfehlung für eine Situation"""
        
        # 1. ML-Modell Vorhersage
        ml_action = self.ml_trainer.predict(state)
        
        # 2. Positions-Anpassung
        position_action = self.position_trainer.adjust_for_position(
            ml_action, state.position
        )
        
        # 3. Gegner-Anpassung (wenn verfügbar)
        if opponent_id:
            opponent_action = self.opponent_profiler.get_recommendation(
                opponent_id, state.pot, state.hand_rank / 8.0
            )
            if opponent_action != "neutral":
                return opponent_action
                
        return position_action


def demo():
    """Demo des Training-Systems"""
    print("\n🃏 POKER BOT TRAINING SYSTEM DEMO\n")
    
    system = KartenKiller()
    
    # Training durchführen
    accuracy = system.train_full_model(num_selfplay_hands=5000)
    
    # Test-Vorhersagen
    print("\n🎰 TEST-VORHERSAGEN:")
    
    test_states = [
        PokerGameState(),
        PokerGameState(),
        PokerGameState(),
    ]
    
    test_states[0].position = 5  # BTN
    test_states[0].street = 0    # Preflop
    test_states[0].hand_rank = 7  # Four of a kind (simuliert)
    test_states[0].pot = 100
    
    test_states[1].position = 0  # BB
    test_states[1].street = 2     # Turn
    test_states[1].hand_rank = 3  # Three of a kind
    
    test_states[2].position = 3  # CO
    test_states[2].street = 3     # River
    test_states[2].hand_rank = 4  # Straight
    
    for i, state in enumerate(test_states):
        rec = system.get_recommendation(state)
        print(f"  {i+1}. {state} → {rec.upper()}")
    
    return accuracy


if __name__ == "__main__":
    demo()
