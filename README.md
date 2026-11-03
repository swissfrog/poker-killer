# Poker Vision Assistant

Experimentelle OpenCV-Anwendung zur Kartenerfassung und Darstellung von Poker-Hilfsfunktionen.

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
| `c` | Karten manuell prüfen, ändern oder eingeben |
| `v` | Automatische Kameraerkennung wieder aufnehmen |
| `h` | Letzte Einträge der Hand-History im Terminal anzeigen |
| `p` | Eigenes Preflop-Range-Raster öffnen/schließen |
| `n` | Push/Fold-Tabellenansicht öffnen/schließen |
| `b` | Pot, Call-Betrag und Bet-Sizing öffnen |
| `t` | Dark/Light-Kopfzeile umschalten |
| `m` | Shake-to-Reset umschalten |
| `1`–`6` | Position UTG, MP, CO, BTN, SB, BB wählen |
| `[` / `]` | Push/Fold-Stacktiefe ändern |

## Kartenprüfung und Empfehlungen

Mit `c` wird die automatische Erkennung angehalten und ein Editor geöffnet. Dort lassen sich Hole Cards und Board per Reglern setzen oder korrigieren. Doppelte Karten werden abgelehnt. Empfehlungen erscheinen erst, wenn genau zwei Hole Cards und ein gültiges Board (0 oder 3–5 Karten) bestätigt wurden. Mit `v` wird die unbestätigte Kameraerkennung wieder aktiviert.

Der Hand-Evaluator prüft die beste Fünf-Karten-Hand aus zwei bis sieben unterschiedlichen Karten. Die Equity-Anzeige in der Entscheidungsbegründung ist eine reproduzierbare Monte-Carlo-Schätzung gegen eine zufällige gegnerische Hand (600 Durchläufe), keine Solver-Ausgabe. Pot Odds stammen aus Pot- und Call-Eingabe. Die ausgewählte Position und ihr heuristischer Sicherheitspuffer werden in der Begründung gezeigt. Bet-Presets werden getrennt vom Call-Betrag angezeigt. Ohne Call-Betrag gibt die App keine Raise-Empfehlung aus.

## Weitere Funktionen

- Hand-History speichert nach vier stabilen Kamerabildern erkannte Karten-Zustände lokal in `hand_history.json` (maximal 500 Einträge).
- Das Range-Raster erlaubt eigene Kombinationen je Position und speichert sie in `preflop_ranges.json`.
- VPIP, PFR und die Bluff-Einschätzung sind manuelle Regler im Fenster „Gegnerprofil“.
- Das Fish-Profil-Badge pulsiert bei einem manuell eingestellten losen/passiven Profil.
- Neue erkannte Karten erhalten eine Flip-Animation.
- Shake-to-Reset reagiert auf schnelle Richtungswechsel der Kamera. Mit `m` kann es abgeschaltet werden.

## Push/Fold-Daten

Die Tabellenansicht liest `push_fold_tables.json`. Eine Vorlage liegt in `push_fold_tables.example.json`. Das Format enthält Position, Stacktiefe in Big Blinds sowie Push- und Call-Kombinationen. Es sind bewusst keine Nash-Ranges vorinstalliert: Ohne Solver-Ausgabe und Spielannahmen (Auszahlungsstruktur, Blinds, Antes und Gegner) wären solche Werte nicht belastbar. Die Ansicht zeigt nur bereitgestellte Daten.

## Voraussetzungen und Grenzen

- Python 3.8+, Webcam, OpenCV und NumPy
- Die automatische Kartenerkennung ist ein vereinfachter Prototyp und kann Karten falsch erkennen. Ihre Ergebnisse gelten bis zur manuellen Bestätigung als unsicher.
- Die Equity-Schätzung nimmt einen zufälligen Gegner an, ignoriert Rake und ersetzt keine Spieler- oder Gegner-Range.
- Der Positionspuffer ist eine Heuristik, keine validierte Pokerstrategie.
- Gegnerprofil und Bluff-Schätzung sind manuelle Schätzungen.
- Die App berechnet keine Nash-Gleichgewichte. Pokerseiten können automatisierte Hilfsmittel untersagen.
