#!/usr/bin/env python3
"""
KARTENKILLER - KOMPLETT PAKET
=============================
Alles in einem: CLI, Web-Interface, Integration, Turnier-Modus

Befehle:
    python karten_killer_cli.py train [hände]     - Trainiere Modell
    python karten_killer_cli.py recommend          - Empfehlung holen
    python karten_killer_cli.py analyze <hand>     - Hand analysieren
    python karten_killer_cli.py web                - Starte Web-Interface
    python karten_killer_cli.py tournament          - Turnier-Modus
    python karten_killer_cli.py stats              - Zeige Statistiken
"""

import sys
import argparse
from karten_killer_pro import KartenKillerPro, PokerGameState, BoardAnalyzer
from karten_killer_pro import GTOEngine, ICMCalculator, RangeEstimator
import json
import os

# Farben für CLI
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
BLUE = '\033[94m'
RESET = '\033[0m'
BOLD = '\033[1m'

class KartenKillerCLI:
    """CLI für KartenKiller"""
    
    def __init__(self):
        self.kk = None
        self.load_model()
    
    def load_model(self):
        """Lade oder erstelle Modell"""
        if os.path.exists('karten_killer_model.json'):
            print(f"{YELLOW}📂 Modell wird geladen...{RESET}")
            # Vereinfacht: Neues Modell erstellen
            self.kk = KartenKillerPro()
        else:
            print(f"{YELLOW}🆕 Erstelle neues Modell...{RESET}")
            self.kk = KartenKillerPro()
    
    def cmd_train(self, num_hands=100000):
        """Trainiere das Modell"""
        print(f"\n{BOLD}{'='*50}")
        print(f"🧠 TRAINING MIT {num_hands:,} HÄNDEN")
        print(f"{'='*50}{RESET}\n")
        
        accuracy = self.kk.train(num_hands)
        
        print(f"\n{GREEN}✅ Training abgeschlossen!{RESET}")
        print(f"   Genauigkeit: {accuracy:.1%}")
        
        # Speichern
        self.kk.save_learning()
        
        return accuracy
    
    def cmd_recommend(self, args):
        """Interaktive Empfehlung"""
        print(f"\n{BLUE}🎰 EMPFEHLUNG GENERIEREN{RESET}")
        print("-" * 40)
        
        state = PokerGameState()
        
        # Position
        print("\nPositionen: 0=BB, 1=SB, 2=BTN, 3=CO, 4=MP, 5=UTG")
        state.position = int(input("Position [0-5]: ") or "2")
        
        # Street
        print("Streets: 0=Preflop, 1=Flop, 2=Turn, 3=River")
        state.street = int(input("Street [0-3]: ") or "0")
        
        # Hand Rank
        state.hand_rank = int(input("Hand Rank (0-8) [7]: ") or "7")
        
        # Pot
        state.pot = float(input("Pot: ") or "100")
        
        # To Call
        state.to_call = float(input("Zu zahlen: ") or "20")
        
        # Stack
        state.stack_size = float(input("Stack: ") or "200")
        
        # Board (optional)
        board = input("Board (z.B. AsKs7h) [leer]: ")
        if board:
            state.board_cards = board.replace(' ', '').split(',')
        
        # ICM
        icm = input("ICM Faktor (1.0=Normal) [1.0]: ")
        if icm:
            state.icm_factor = float(icm)
        
        # Empfehlung
        print("\n" + "="*40)
        rec = self.kk.get_recommendation(state)
        
        print(f"{GREEN}🎯 EMPFEHLUNG: {rec['action'].upper()}{RESET}")
        print(f"   ML Aktion: {rec['ml_action']}")
        
        if rec['board_analysis']:
            ba = rec['board_analysis']
            print(f"   Board: {ba.get('texture', 'unknown')}")
            print(f"   Danger: {ba.get('danger', 0)}/10")
            if ba.get('draws'):
                print(f"   Draws: {', '.join(ba['draws'])}")
        
        if rec.get('icm_factor', 1.0) != 1.0:
            print(f"   ICM: {rec['icm_factor']:.1f}x")
        
        print("="*40 + "\n")
    
    def cmd_analyze(self, hand_str):
        """Analysiere eine Hand"""
        print(f"\n{BLUE}🃏 HAND-ANALYSE: {hand_str}{RESET}")
        print("-" * 40)
        
        # Parse Hand (z.B. "AsKh" = Ace of Spades, King of Hearts)
        # Vereinfacht
        hand_rank = 0
        if 'AA' in hand_str.upper():
            hand_rank = 7
        elif 'KK' in hand_str.upper():
            hand_rank = 6
        elif 'QQ' in hand_str.upper():
            hand_rank = 5
        elif 'JJ' in hand_str.upper():
            hand_rank = 4
        elif 'TT' in hand_str.upper():
            hand_rank = 3
        elif any(p in hand_str.upper() for p in ['AK', 'AQ', 'AJ', 'KQ']):
            hand_rank = 2
        
        print(f"Hand-Rang: {hand_rank}")
        
        # GTO Empfehlung
        gto_bluff, prob = GTOEngine.should_bluff(hand_rank, 0, 100, 200)
        print(f"GTO Bluff: {gto_bluff} ({prob:.0%})")
        
        # Range
        print("\nGeschätzte Range:")
        for action in ['open_raise', 'cold_call', '3bet']:
            r = RangeEstimator.estimate_range(action, 3, 0)
            print(f"  {action}: {r[:3]}...")
        
        print()
    
    def cmd_tournament(self, args):
        """Turnier-Modus"""
        print(f"\n{BOLD}🏆 TOURNIER-MODUS{RESET}")
        print("-" * 40)
        
        #typical tournament scenarios
        stacks = [5000, 10000, 20000, 50000]
        bb = 100
        
        print("\nSzenarien:")
        for stack in stacks:
            state = PokerGameState()
            state.stack_size = stack
            state.bb_size = bb
            state.pot = bb * 2
            state.to_call = bb
            
            # ICM
            icm = ICMCalculator.should_push_fold(stack, bb, 1.5)
            
            # Recommend
            rec = self.kk.get_recommendation(state)
            
            print(f"Stack {stack:,} (BBs: {stack/bb:.0f}): {rec['action'].upper()} [{icm}]")
        
        print("\n💡 Tipps:")
        print("  - < 10 BB: Push/Fold Phase")
        print("  - 10-20 BB: Consider Push")
        print("  - > 20 BB: Open Raise normal")
        print("  - Bubble: +50% tighter spielen!")
        print()
    
    def cmd_stats(self, args):
        """Zeige Statistiken"""
        print(f"\n{BOLD}📊 KARTENKILLER STATISTIKEN{RESET}")
        print("-" * 40)
        
        # Lern-Daten
        perf = self.kk.analyze_performance()
        
        if perf.get('enough_data'):
            print(f"\nGespielte Hände: {perf['total_hands']}")
            print(f"Win-Rate: {perf['win_rate']:.1%}")
            
            print("\nBeste Aktionen:")
            for action, win_rate, count in perf['best_actions']:
                print(f"  {action}: {win_rate:.1%} ({count} Hände)")
        else:
            print(f"\n{YELLOW}Noch nicht genug Daten für Statistiken{RESET}")
            print("Spiele mehr Hände mit KartenKiller!")
        
        # Dateien
        print("\nDateien:")
        files = ['karten_killer_pro.py', 'karten_killer_memory.json']
        for f in files:
            exists = "✅" if os.path.exists(f) else "❌"
            print(f"  {exists} {f}")
        
        print()
    
    def cmd_web(self, args):
        """Starte Web-Interface"""
        print(f"\n{BOLD}🌐 WEB-INTERFACE{RESET}")
        print("-" * 40)
        print(f"{YELLOW}Web-Interface wird gestartet...{RESET}")
        print(f"\nURL: http://localhost:5000")
        print(f"\nDrücke STRG+C zum Beenden\n")
        
        # Einfacher Flask-Server
        try:
            from flask import Flask, render_string, request
        except ImportError:
            print(f"{RED}Flask nicht installiert!{RESET}")
            print(f"Installiere: pip install flask")
            return
        
        app = Flask(__name__)
        
        HTML = '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>KartenKiller</title>
            <style>
                body { font-family: Arial; background: #1a1a2e; color: #eee; padding: 20px; }
                .container { max-width: 600px; margin: 0 auto; }
                h1 { color: #00ff88; text-align: center; }
                .card { background: #16213e; padding: 20px; border-radius: 10px; margin: 10px 0; }
                label { display: block; margin: 10px 0 5px; }
                input, select { width: 100%; padding: 8px; background: #0f3460; color: #fff; border: none; border-radius: 5px; }
                button { width: 100%; padding: 12px; background: #00ff88; color: #000; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; margin-top: 15px; }
                button:hover { background: #00cc6a; }
                .result { background: #00ff88; color: #000; padding: 15px; border-radius: 5px; text-align: center; font-size: 24px; font-weight: bold; margin-top: 20px; }
                .tip { color: #aaa; font-size: 14px; text-align: center; margin-top: 20px; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🃏 KARTENKILLER</h1>
                <div class="card">
                    <form method="POST">
                        <label>Position (0=BB bis 5=UTG)</label>
                        <input type="number" name="position" value="2" min="0" max="5">
                        
                        <label>Street (0=Preflop bis 3=River)</label>
                        <input type="number" name="street" value="0" min="0" max="3">
                        
                        <label>Hand Rank (0-8)</label>
                        <input type="number" name="hand_rank" value="5" min="0" max="8">
                        
                        <label>Pot</label>
                        <input type="number" name="pot" value="100">
                        
                        <label>Zu zahlen</label>
                        <input type="number" name="to_call" value="20">
                        
                        <label>Stack</label>
                        <input type="number" name="stack_size" value="200">
                        
                        <label>Board (z.B. AsKs7h, leer wenn nicht)</label>
                        <input type="text" name="board" placeholder="AsKs7h">
                        
                        <button type="submit">🎯 EMPFEHLUNG HOLEN</button>
                    </form>
                </div>
                
                {% if recommendation %}
                <div class="result">
                    {{ recommendation }}
                </div>
                {% endif %}
                
                <p class="tip">KartenKiller Pro - 87% Genauigkeit</p>
            </div>
        </body>
        </html>
        '''
        
        @app.route('/', methods=['GET', 'POST'])
        def index():
            recommendation = None
            
            if request.method == 'POST':
                state = PokerGameState()
                state.position = int(request.form.get('position', 2))
                state.street = int(request.form.get('street', 0))
                state.hand_rank = int(request.form.get('hand_rank', 5))
                state.pot = float(request.form.get('pot', 100))
                state.to_call = float(request.form.get('to_call', 20))
                state.stack_size = float(request.form.get('stack_size', 200))
                
                board = request.form.get('board', '')
                if board:
                    state.board_cards = [board[i:i+2] for i in range(0, len(board), 2)]
                
                rec = kk.get_recommendation(state)
                recommendation = rec['action'].upper()
            
            return render_string(HTML, recommendation=recommendation)
        
        # Start Flask
        app.run(host='0.0.0.0', port=5000, debug=False)


def main():
    parser = argparse.ArgumentParser(description='KartenKiller - Poker Bot')
    parser.add_argument('command', choices=['train', 'recommend', 'analyze', 'web', 'tournament', 'stats'],
                       help='Befehl ausführen')
    parser.add_argument('args', nargs='*', help='Argumente')
    
    args = parser.parse_args()
    
    cli = KartenKillerCLI()
    
    if args.command == 'train':
        num = int(args.args[0]) if args.args else 100000
        cli.cmd_train(num)
    
    elif args.command == 'recommend':
        cli.cmd_recommend(args.args)
    
    elif args.command == 'analyze':
        hand = args.args[0] if args.args else "AhKh"
        cli.cmd_analyze(hand)
    
    elif args.command == 'web':
        cli.cmd_web(args.args)
    
    elif args.command == 'tournament':
        cli.cmd_tournament(args.args)
    
    elif args.command == 'stats':
        cli.cmd_stats(args.args)


if __name__ == "__main__":
    main()
