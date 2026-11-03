# Poker Vision Assistant

Experimentelle OpenCV-Anwendung zur Erfassung von Spielkarten und Darstellung von Poker-Hilfsfunktionen.

## Installation

```bash
pip install -r requirements.txt
```

## Start

```bash
python poker_vision_assistant.py
```

## Tastatursteuerung

| Taste | Funktion |
|---|---|
| `q` | Beenden |
| `r` | Kartenansicht zurücksetzen |
| `h` | Letzte Einträge der Hand-History im Terminal anzeigen |
| `p` | Eigenes Preflop-Range-Raster öffnen/schließen |
| `n` | Push/Fold-Tabellenansicht öffnen/schließen |
| `b` | Bet-Sizing-Fenster öffnen/schließen |
| `t` | Dark/Light-Kopfzeile umschalten |
| `m` | Shake-to-Reset umschalten |
| `1`–`6` | Position UTG, MP, CO, BTN, SB, BB wählen |
| `[` / `]` | Push/Fold-Stacktiefe verringern/erhöhen |

## Funktionen

- Hand-History speichert nach vier stabilen Kamerabildern erkannte Karten-Zustände lokal in `hand_history.json` (maximal 500 Einträge).
- Das Range-Raster erlaubt eigene Kombinationen je Position und speichert sie in `preflop_ranges.json`.
- VPIP, PFR und die Bluff-Einschätzung sind manuelle Regler im Fenster „Gegnerprofil“.
- Das Fish-Profil-Badge pulsiert bei einem manuell eingestellten losen/passiven Profil.
- Bet-Sizing bietet Pot-Regler und Presets für 1/3, 1/2, 2/3 und Pot.
- Neue erkannte Karten erhalten eine Flip-Animation.
- Shake-to-Reset reagiert auf erkannte schnelle Richtungswechsel der Kamera. Mit `m` kann die Erkennung abgeschaltet werden.

## Push/Fold-Daten

Die Tabellenansicht liest `push_fold_tables.json`. Eine Vorlage liegt in `push_fold_tables.example.json`. Das Format enthält Position, effektive Stacktiefe in Big Blinds sowie Push- und Call-Kombinationen. Es sind bewusst keine Nash-Ranges vorinstalliert: Ohne Solver-Ausgabe und Spielannahmen (Auszahlungsstruktur, Blinds, Antes und Gegner) wären solche Werte nicht belastbar. Die Ansicht zeigt nur die bereitgestellten Daten.

## Voraussetzungen und Grenzen

- Python 3.8+, Webcam, OpenCV und NumPy
- Die Kartenerkennung ist ein vereinfachter Prototyp und kann Karten falsch erkennen.
- Das Gegnerprofil und der Bluff-Meter sind manuelle Schätzungen, keine statistische Analyse oder berechnete Wahrscheinlichkeiten.
- Range- und Push/Fold-Daten müssen vom Nutzer gepflegt werden. Die App berechnet keine Nash-Gleichgewichte.
- Die App ist ein Lernexperiment. Pokerseiten können die Nutzung automatisierter Hilfsmittel untersagen.
