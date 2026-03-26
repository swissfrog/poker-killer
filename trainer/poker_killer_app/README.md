# 🃏 KartenKiller - Poker Bot Pro

**ML-gestützter Poker-Assistent mit 86.9% Genauigkeit**

## Features

### 🎯 Empfehlungs-System
- Position, Street, Hand-Rang, Pot, Stack
- Board-Analyse (Dry/Wet/Danger)
- GTO Bluff-Erkennung
- ICM für Turniere

### 📷 Kamera-Scan
- Karten-Erkennung (Demo)
- Tisch-Karten Anzeige
- Echtzeit Empfehlungen

### 🏆 Turnier-Modus
- ICM Status
- Push/Fold Charts
- Bubble Tipps
- Payout Struktur

### 📊 Statistiken
- Win-Rate Tracking
- Gegner-Profiling
- Hand-History Import
- Aktions-Analyse

### ⚙️ Einstellungen
- 🇩🇪 🇬🇧 Mehrsprachig
- 🔊 TTS Sprachausgabe
- 📳 Haptic Feedback
- 🔄 Auto-Record

## Installation & Build

### Voraussetzungen
- Flutter SDK 3.0+
- Android SDK

### Build

```bash
# 1. In den Ordner
cd poker_killer_app

# 2. Dependencies holen
flutter pub get

# 3. Debug APK bauen
flutter build apk --debug

# 4. APK finden unter:
# build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK

```bash
flutter build apk --release
```

## ML Hintergrund

- **Training:** 100.000+ simulierte Pokersituationen
- **Algorithmus:** Gradient Boosting Classifier
- **Features:** Position, Street, Hand-Rang, Pot, Stack, ICM
- **Genauigkeit:** 86.9%

## Dateien

```
poker_bot/
├── poker_killer_app/
│   ├── lib/main.dart      # Flutter App
│   ├── pubspec.yaml       # Flutter Config
│   └── README.md          # Diese Datei
├── karten_killer_pro.py   # ML Modell (Python)
└── poker_bot_pro.py       # Screen-Reader
```

## Lizenz

MIT License - Nur für Bildungszwecke!

⚠️ **Hinweis:** Dies ist ein Experiment/Tool zur Analyse. 
Poker-Seiten können die Nutzung von Bots verbieten!
