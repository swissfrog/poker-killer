# Poker Vision Assistant

Ein KI-gestützter Poker-Assistent der durch die Kamera schaut und dir Spielempfehlungen gibt.

## Installation

```bash
pip install -r requirements.txt
```

## Verwendung

```bash
python poker_vision_assistant.py
```

## Features

- 📷 Kamerabild erfassen
- 🃏 Spielkarten erkennen
- 📊 Hand-Stärke berechnen
- 🎯 Spielempfehlungen (Fold/Call/Raise)
- 🔊 Optionale Sprachausgabe

## Steuerung

- `q` - Beenden
- `r` - Karten resetten
- `h` - Letzte Hand-History-Einträge im Terminal anzeigen

Erkannte Karten-Zustände werden nach vier stabilen Kamerabildern in `hand_history.json` gespeichert (maximal 500 Einträge). Die Datei bleibt lokal im Arbeitsverzeichnis.

## Voraussetzungen

- Python 3.8+
- Webcam
- OpenCV

## Hinweis

Dies ist ein Experiment/Educational Tool. Pokerseiten können die Nutzung von Bots verbieten!
