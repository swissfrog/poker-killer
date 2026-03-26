import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hand_evaluator.dart';
import 'preflop_ranges.dart';
import 'opponent_tracker.dart';
import 'draw_analyzer.dart';
import 'bet_sizer.dart';
import 'stack_awareness.dart';
import 'position_awareness.dart';
import 'hand_history.dart';
import 'opponent_model.dart';
import 'pot_odds.dart';
import 'preflop_chart.dart';

// ─── Farben ───────────────────────────────────────────────────────────────────
class AC {
  static const Color P = Color(0xFF00FF88);
  static const Color BG = Color(0xFF1A1A2E);
  static const Color PN = Color(0xFF16213E);
}

// ─── Kaggle-Klassen (alphabetisch, 52 ohne Joker) ────────────────────────────
// Reihenfolge: os.listdir() auf Linux = alphabetisch
// Dataset: gpiosenka/cards-image-datasetclassification
const List<String> kKaggleLabels = [
  'ace of clubs',    'ace of diamonds',    'ace of hearts',    'ace of spades',
  'eight of clubs',  'eight of diamonds',  'eight of hearts',  'eight of spades',
  'five of clubs',   'five of diamonds',   'five of hearts',   'five of spades',
  'four of clubs',   'four of diamonds',   'four of hearts',   'four of spades',
  'jack of clubs',   'jack of diamonds',   'jack of hearts',   'jack of spades',
  'king of clubs',   'king of diamonds',   'king of hearts',   'king of spades',
  'nine of clubs',   'nine of diamonds',   'nine of hearts',   'nine of spades',
  'queen of clubs',  'queen of diamonds',  'queen of hearts',  'queen of spades',
  'seven of clubs',  'seven of diamonds',  'seven of hearts',  'seven of spades',
  'six of clubs',    'six of diamonds',    'six of hearts',    'six of spades',
  'ten of clubs',    'ten of diamonds',    'ten of hearts',    'ten of spades',
  'three of clubs',  'three of diamonds',  'three of hearts',  'three of spades',
  'two of clubs',    'two of diamonds',    'two of hearts',    'two of spades',
];

// Konvertierung Kaggle-Label → {r, s} Map für Poker-Logik
Map<String, String> labelToCard(String label) {
  const rankMap = {
    'ace': 'A', 'king': 'K', 'queen': 'Q', 'jack': 'J',
    'ten': '10', 'nine': '9', 'eight': '8', 'seven': '7',
    'six': '6', 'five': '5', 'four': '4', 'three': '3', 'two': '2',
  };
  const suitMap = {
    'spades': '♠', 'hearts': '♥', 'diamonds': '♦', 'clubs': '♣',
  };
  final parts = label.split(' of ');
  return {
    'r': rankMap[parts[0]] ?? parts[0],
    's': suitMap[parts[1]] ?? parts[1],
    'label': label,
  };
}

// ─── DL Poker Brain (Empfehlungs-Modell) ─────────────────────────────────────
class PokerBrain {
  Interpreter? _interpreter;
  bool get isLoaded => _interpreter != null;

  static const List<String> kActions = ['FOLD', 'CHECK', 'CALL', 'RAISE'];

  bool _useRlModel = false;

  Future<void> load({bool useRl = false}) async {
    _useRlModel = useRl;
    final modelPath = useRl ? 'assets/poker_brain_rl.tflite' : 'assets/poker_brain.tflite';
    _interpreter = await Interpreter.fromAsset(modelPath);
  }

  String get modelName => _useRlModel ? 'RL Model (500k steps)' : 'Imitation v4';

  /// Gibt Aktion + Confidence zurück
  /// equity: 0.0-1.0 (Gewinnchance, aus Handstärke geschätzt)
  /// position: 0=BB, 1=SB, 2=BTN, 3=CO, 4=MP, 5=EP (als Index)
  /// callAmount, pot, stack in Chips
  /// bigBlind: Größe des Big Blinds für Stack-in-BB Berechnung
  /// street: 0=preflop, 1=flop, 2=turn, 3=river
  /// boardWetness: 0=dry, 1=wet (flush/straight-heavy board)
  ({String action, double confidence, List<double> scores}) recommend({
    required double equity,
    required int position,
    required double callAmount,
    required double pot,
    required double stack,
    required int street,
    double boardWetness = 0.3,
    double bigBlind = 2.0,
  }) {
    if (_interpreter == null) return (action: '?', confidence: 0, scores: [0,0,0,0]);
    try {
      final pokerPos = PositionAwareness.fromIndex(position);
      // Position-Awareness: Equity-Boost durch Position
      final adjustedEquity = (equity + PositionAwareness.equityBoost(pokerPos)).clamp(0.0, 1.0);

      // Stack-Awareness: Stack in BB berechnen
      final stackBbRaw = StackAwareness.stackInBb(stack, bigBlind);
      final stackType = StackAwareness.classify(stackBbRaw);

      // Equity-Threshold Anpassung nach Stack-Größe
      final effectiveEquity = (adjustedEquity + StackAwareness.bluffAdjustment(stackType))
          .clamp(0.0, 1.0);

      final pos = PositionAwareness.toModelInput(pokerPos); // normalisierter Positions-Input
      final potOdds = (pot + callAmount) > 0 ? callAmount / (pot + callAmount) : 0.0;
      final spr = pot > 0 ? (stack / pot).clamp(0.0, 20.0) / 20.0 : 1.0;
      final str = street / 3.0;
      final aggression = pot > 0 ? (callAmount / (pot * 0.75 + 0.01)).clamp(0.0, 1.0) : 0.0;
      // Stack-Ratio: normalisiert auf 0–1 (200bb = max deep stack)
      final stackBb = stackBbRaw.clamp(0.0, 200.0) / 200.0;

      final input = [[effectiveEquity, pos, potOdds, spr, str, aggression, stackBb, boardWetness]
          .map((e) => e.toDouble()).toList()];
      final output = [List.filled(4, 0.0)];
      _interpreter!.run(input, output);

      final rawScores = output[0];

      // Softmax für echte Wahrscheinlichkeiten
      final maxRaw = rawScores.reduce((a, b) => a > b ? a : b);
      double expSum = 0;
      final softmaxScores = <double>[];
      for (final s in rawScores) {
        final e = math.exp((s - maxRaw).clamp(-50.0, 0.0));
        softmaxScores.add(e);
        expSum += e;
      }
      final scores = expSum > 0
          ? softmaxScores.map((e) => e / expSum).toList()
          : List.filled(rawScores.length, 1.0 / rawScores.length);

      int maxIdx = 0;
      double maxVal = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > maxVal) { maxVal = scores[i]; maxIdx = i; }
      }

      String action = kActions[maxIdx < kActions.length ? maxIdx : 0];

      // Stack-Overlay: Push/Fold Zone Override
      action = StackAwareness.applyStackOverlay(
        baseAction: action,
        stackInBb: stackBbRaw,
        equity: effectiveEquity,
        isPreflop: street == 0,
      );

      // Position-Overlay: Late Position öffnet breiter, Early Position enger
      action = PositionAwareness.applyPositionOverlay(
        baseAction: action,
        position: pokerPos,
        equity: effectiveEquity,
        isPreflop: street == 0,
        facingNoRaise: callAmount == 0,
      );

      return (
        action: action,
        confidence: maxVal,
        scores: List<double>.from(scores),
      );
    } catch (_) {
      return (action: '?', confidence: 0, scores: [0,0,0,0]);
    }
  }

  void dispose() => _interpreter?.close();
}

// ─── ML Kartenscanner ─────────────────────────────────────────────────────────

/// Ergebnis einer Zone-Klassifizierung
class ZoneResult {
  final String label;
  final double score;
  final String zoneName;
  ZoneResult(this.label, this.score, this.zoneName);
}

class CardClassifier {
  Interpreter? _interpreter;
  bool get isLoaded => _interpreter != null;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset('assets/64x3-cards.tflite');
  }

  /// Gibt Kaggle-Label zurück (z.B. "ace of hearts") oder null bei niedrigem Score
  String? classify(CameraImage cameraImage) {
    if (_interpreter == null) return null;
    try {
      final result = classifyBestZone(cameraImage);
      if (result == null || result.score < 0.15) return null;
      return result.label;
    } catch (_) {
      return null;
    }
  }

  /// FIX 3: Testet 5 Zonen und gibt das beste Ergebnis zurück
  ZoneResult? classifyBestZone(CameraImage cameraImage) {
    if (_interpreter == null) return null;
    try {
      final srcW = cameraImage.width;
      final srcH = cameraImage.height;

      // 5 Zonen definieren: (centerX_ratio, centerY_ratio, name)
      final zones = [
        (0.5, 0.5, 'Mitte'),
        (0.3, 0.3, 'Oben-Links'),
        (0.7, 0.3, 'Oben-Rechts'),
        (0.3, 0.7, 'Unten-Links'),
        (0.7, 0.7, 'Unten-Rechts'),
      ];

      ZoneResult? best;
      for (final zone in zones) {
        final cx = (zone.$1 * srcW).round();
        final cy = (zone.$2 * srcH).round();
        final input = _prepareInputFromRegion(cameraImage, cx, cy);
        final output = [List.filled(52, 0.0)];
        _interpreter!.run(input, output);

        final scores = output[0];
        int maxIdx = 0;
        double maxVal = scores[0];
        for (int i = 1; i < scores.length; i++) {
          if (scores[i] > maxVal) { maxVal = scores[i]; maxIdx = i; }
        }

        if (best == null || maxVal > best.score) {
          best = ZoneResult(kKaggleLabels[maxIdx], maxVal, zone.$3);
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  /// Gibt Top-3 Kandidaten mit Scores zurück (aus der besten Zone)
  List<({String label, double score, String zone})> classifyTopK(CameraImage cameraImage, {int k = 3}) {
    if (_interpreter == null) return [];
    try {
      final srcW = cameraImage.width;
      final srcH = cameraImage.height;

      final zones = [
        (0.5, 0.5, 'Mitte'),
        (0.3, 0.3, 'Oben-Links'),
        (0.7, 0.3, 'Oben-Rechts'),
        (0.3, 0.7, 'Unten-Links'),
        (0.7, 0.7, 'Unten-Rechts'),
      ];

      // Alle Zonen auswerten, beste Zone finden
      String bestZoneName = 'Mitte';
      double bestZoneScore = 0.0;
      List<double>? bestScores;

      for (final zone in zones) {
        final cx = (zone.$1 * srcW).round();
        final cy = (zone.$2 * srcH).round();
        final input = _prepareInputFromRegion(cameraImage, cx, cy);
        final output = [List.filled(52, 0.0)];
        _interpreter!.run(input, output);
        final scores = output[0];
        final maxVal = scores.reduce((a, b) => a > b ? a : b);
        if (maxVal > bestZoneScore) {
          bestZoneScore = maxVal;
          bestScores = List<double>.from(scores);
          bestZoneName = zone.$3;
        }
      }

      if (bestScores == null) return [];
      final indexed = List.generate(bestScores.length, (i) => (label: kKaggleLabels[i], score: bestScores![i], zone: bestZoneName));
      indexed.sort((a, b) => b.score.compareTo(a.score));
      return indexed.take(k).toList();
    } catch (_) {
      return [];
    }
  }

  /// Live-Confidence (höchster Score aus bester Zone, auch unter Threshold)
  double liveConfidence(CameraImage cameraImage) {
    final result = classifyBestZone(cameraImage);
    return result?.score ?? 0.0;
  }

  /// CameraImage → [1][70][70][1] float32 (aus Bildmitte, Legacy-Kompatibilität)
  List prepareInput(CameraImage cameraImage) {
    final cx = cameraImage.width ~/ 2;
    final cy = cameraImage.height ~/ 2;
    return _prepareInputFromRegion(cameraImage, cx, cy);
  }

  /// FIX 2: Bildvorverarbeitung aus einer bestimmten Region
  List _prepareInputFromRegion(CameraImage cameraImage, int centerX, int centerY) {
    final yPlane = cameraImage.planes[0].bytes;
    final srcW = cameraImage.width;
    final srcH = cameraImage.height;

    // Ausschnitt: 70% der kürzeren Seite als Quadrat um Zentrum
    final cropSize = ((srcW < srcH ? srcW : srcH) * 0.7).round();
    final halfCrop = cropSize ~/ 2;
    final x0 = (centerX - halfCrop).clamp(0, srcW - cropSize);
    final y0 = (centerY - halfCrop).clamp(0, srcH - cropSize);

    // Graustufen-Bild aus YUV Y-Kanal
    final grayImg = img.Image(width: cropSize, height: cropSize);
    for (int y = 0; y < cropSize; y++) {
      for (int x = 0; x < cropSize; x++) {
        final srcX = x0 + x;
        final srcY = y0 + y;
        if (srcX < srcW && srcY < srcH) {
          final val = yPlane[srcY * srcW + srcX];
          grayImg.setPixelRgb(x, y, val, val, val);
        }
      }
    }
    final resized = img.copyResize(grayImg, width: 70, height: 70);

    // ── FIX 2: Fortgeschrittene Bildvorverarbeitung ────────────────────
    // Schritt 1: Pixel-Werte sammeln
    final pixels = List.generate(70 * 70, (i) {
      final px = resized.getPixel(i % 70, i ~/ 70);
      return px.r / 255.0;
    });

    // Schritt 2: Histogramm-Equalization (CLAHE-ähnlich, vereinfacht)
    // Sortiere Pixel und berechne CDF für Contrast Enhancement
    final sorted = List<double>.from(pixels)..sort();
    final cdfMin = sorted.first;
    final cdfMax = sorted.last;
    final cdfRange = (cdfMax - cdfMin) > 0.01 ? (cdfMax - cdfMin) : 1.0;

    // Schritt 3: Mittlere Helligkeit für Gamma-Entscheidung
    double sum = 0.0;
    for (final v in pixels) sum += v;
    final mean = sum / pixels.length;

    // Schritt 4: Gamma-Korrektur (aggressiver bei dunklen Bildern)
    final double gamma = mean < 0.25
        ? 0.4   // sehr dunkel → stark aufhellen
        : mean < 0.35
            ? 0.6 // dunkel → deutlich aufhellen
            : mean < 0.45
                ? 0.8 // leicht dunkel → leicht aufhellen
                : 1.0; // normal

    // Schritt 5: Unsharp-Mask Simulation (3x3 Mittelwert-Differenz)
    final blurred = List<double>.filled(70 * 70, 0.0);
    for (int y = 0; y < 70; y++) {
      for (int x = 0; x < 70; x++) {
        double acc = 0.0;
        int cnt = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < 70 && ny >= 0 && ny < 70) {
              acc += pixels[ny * 70 + nx];
              cnt++;
            }
          }
        }
        blurred[y * 70 + x] = acc / cnt;
      }
    }

    // Schritt 6: Weißabgleich-Korrektur (für gelbliche/bläuliche Beleuchtung)
    // Da wir Graustufen arbeiten, simulieren wir durch Mittelwert-Verschiebung
    // Ziel-Mittelwert für weiße Karten: ~0.85 (heller Hintergrund)
    final targetMean = 0.80;
    final whiteBalanceOffset = mean > 0.3 ? (targetMean - mean) * 0.3 : 0.0;

    return [
      List.generate(
        70,
        (y) => List.generate(
          70,
          (x) {
            final idx = y * 70 + x;
            final raw = pixels[idx];
            // Histogram Equalization: Min-Max Stretch
            final heq = ((raw - cdfMin) / cdfRange).clamp(0.0, 1.0);
            // Unsharp Mask: Original + Faktor * (Original - Blur)
            final sharpened = (heq + 0.4 * (heq - blurred[idx])).clamp(0.0, 1.0);
            // Weißabgleich
            final whiteBalanced = (sharpened + whiteBalanceOffset).clamp(0.0, 1.0);
            // Gamma Korrektur
            final gammaCorrected = gamma != 1.0
                ? _gammaCorrect(whiteBalanced, gamma)
                : whiteBalanced;
            return [gammaCorrected];
          },
        ),
      )
    ];
  }

  /// Gamma-Korrektur: value^gamma (linearisiertes sRGB-ähnliches Mapping)
  double _gammaCorrect(double value, double gamma) {
    if (value <= 0.0) return 0.0;
    if (value >= 1.0) return 1.0;
    return _powApprox(value, gamma).clamp(0.0, 1.0);
  }

  double _powApprox(double base, double exp) {
    if (base <= 0) return 0.0;
    if (exp == 1.0) return base;
    if (exp == 0.5) {
      // Newton's method sqrt
      double s = base;
      for (int i = 0; i < 8; i++) s = (s + base / s) / 2.0;
      return s;
    }
    final ln = _lnApprox(base);
    return _expApprox(exp * ln);
  }

  double _lnApprox(double x) {
    int k = 0;
    double xr = x;
    while (xr > 1.5) { xr /= 2.718281828; k++; }
    while (xr < 0.5) { xr *= 2.718281828; k--; }
    final t = (xr - 1) / (xr + 1);
    double s = t, tt = t * t, term = t;
    for (int i = 1; i <= 10; i++) {
      term *= tt;
      s += term / (2 * i + 1);
    }
    return 2 * s + k;
  }

  double _expApprox(double x) {
    if (x > 20) return double.infinity;
    if (x < -20) return 0.0;
    int n = x.floor();
    double r = x - n;
    double er = 1 + r * (1 + r * (0.5 + r * (1/6.0 + r * (1/24.0 + r * (1/120.0)))));
    double en = 1.0;
    double base = n >= 0 ? 2.718281828 : 1.0 / 2.718281828;
    int absN = n.abs();
    for (int i = 0; i < absN; i++) en *= base;
    return en * er;
  }

  void dispose() => _interpreter?.close();
}

// ─── App Entry ───────────────────────────────────────────────────────────────
late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(const OttoApp());
}

// ─── Glassmorphism Panel ──────────────────────────────────────────────────────
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  const GlassPanel({super.key, required this.child,
    this.padding = const EdgeInsets.all(16), this.borderColor});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.15), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class OttoApp extends StatelessWidget {
  const OttoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Otto',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: AC.BG,
          primaryColor: AC.P,
        ),
        home: const MN(),
      );
}

// ─── Haupt-Navigation ────────────────────────────────────────────────────────
class MN extends StatefulWidget {
  const MN({super.key});
  @override
  State<MN> createState() => _MNState();
}

class _MNState extends State<MN> {
  int _tab = 0;
  List<Map<String, String>> myCards = [];
  List<Map<String, String>> boardCards = [];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            RP(myCards, boardCards),
            SP(
              'Meine 2 Karten',
              maxCards: 2,
              onDetected: (c) => setState(() => myCards = c),
            ),
            SP(
              'Tisch (5)',
              maxCards: 5,
              onDetected: (c) => setState(() => boardCards = c),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (x) => setState(() => _tab = x),
          selectedItemColor: AC.P,
          backgroundColor: AC.PN,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.auto_awesome), label: 'Empfehlung'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person), label: 'Meine 2'),
            BottomNavigationBarItem(
                icon: Icon(Icons.table_bar), label: 'Tisch (5)'),
          ],
        ),
      );
}

// ─── Empfehlungs-Screen ───────────────────────────────────────────────────────
class RP extends StatefulWidget {
  final List<Map<String, String>> M, B;
  const RP(this.M, this.B, {super.key});
  @override
  State<RP> createState() => _RPState();
}

// Globaler Gegner-Tracker (Session-weit)
final OpponentTracker globalTracker = OpponentTracker();

class _RPState extends State<RP> with TickerProviderStateMixin {
  int p = 2, hr = 0;
  double pt = 100, tc = 20, ss = 200;
  double bb = 2; // Big Blind Größe
  String r = '';
  double _confidence = 0;
  List<double> _scores = [0, 0, 0, 0];
  double _equity = 0;
  String _handName = '';
  String _oppType = '';
  BetSizing? _betSizing;
  // Position-Namen: Index 0=BB, 1=SB, 2=BTN, 3=CO, 4=MP, 5=EP
  final ps = PositionAwareness.positionNames;
  final PokerBrain _brain = PokerBrain();
  bool _brainReady = false;
  bool _calcEquity = false;
  final FlutterTts _tts = FlutterTts();
  List<Map<String, String>> _manualBoard = [];
  late AnimationController _glowController;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _brain.load().then((_) => setState(() => _brainReady = true));
    _tts.setLanguage('de-DE');
    _tts.setSpeechRate(0.9);
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_glowController);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Color _actionColor() {
    switch (r) {
      case 'RAISE': case 'ALL-IN': return const Color(0xFF00FF88);
      case 'FOLD': return Colors.red.shade400;
      case 'CALL': return Colors.blue.shade300;
      default: return Colors.orange.shade300;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _brain.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _board => widget.B.isNotEmpty ? widget.B : _manualBoard;
  int get _street => _board.isEmpty ? 0 : _board.length == 3 ? 1 : _board.length == 4 ? 2 : 3;

  // Echte Monte-Carlo Equity aus Dart-Evaluator
  Future<double> _calcRealEquity() async {
    if (widget.M.isEmpty) return 0.5;
    return HandEvaluator.monteCarloEquity(
      widget.M.cast<Map<String, String>>(),
      _board.cast<Map<String, String>>(),
      simulations: 300,
    );
  }

  double _boardWetness() {
    if (_board.isEmpty) return 0.3;
    final suits = _board.map((c) => c['s'] ?? '').toList();
    final suitCounts = <String, int>{};
    for (var s in suits) suitCounts[s] = (suitCounts[s] ?? 0) + 1;
    final maxSuit = suitCounts.values.fold(0, (a, b) => a > b ? a : b);
    return maxSuit >= 3 ? 0.8 : maxSuit == 2 ? 0.5 : 0.2;
  }

  // Preflop-Empfehlung aus Range-Tabellen (position-aware)
  String? _preflopAdvice() {
    if (_street != 0 || widget.M.length < 2) return null;
    final c1 = widget.M[0];
    final c2 = widget.M[1];
    return PreflopRanges.preflopAdviceWithPosition(
      c1['r'] ?? 'A', c1['s'] ?? '♠',
      c2['r'] ?? 'K', c2['s'] ?? '♦',
      p, tc, pt,
    );
  }

  void _rec() async {
    if (!_brainReady) return;
    _ev();

    // Preflop: Range-Tabellen nutzen
    final pfAdvice = _preflopAdvice();

    // Equity berechnen
    setState(() => _calcEquity = true);
    final equity = await _calcRealEquity();
    setState(() {
      _equity = equity;
      _calcEquity = false;
    });

    // Gegner-Stats
    final oppStats = globalTracker.aggregated;
    _oppType = oppStats.handsPlayed > 3 ? oppStats.playerTypeName : '';

    // DL Brain Empfehlung (mit Stack- und Position-Awareness)
    final result = _brain.recommend(
      equity: equity,
      position: p,
      callAmount: tc,
      pot: pt,
      stack: ss,
      street: _street,
      boardWetness: _boardWetness(),
      bigBlind: bb,
    );

    // Preflop: Range-Tabelle hat Vorrang
    String action = pfAdvice ?? result.action;

    // Exploitative Anpassung bei bekanntem Gegner-Typ
    if (oppStats.handsPlayed > 10) {
      // Gegen Calling Station: raise threshold senken (mehr Value)
      if (oppStats.playerType > 0.6 && action == 'CHECK' && equity > 0.55) {
        action = 'RAISE';
      }
      // Gegen Nit: fold threshold erhöhen (respektiere ihre Bets)
      if (oppStats.playerType < 0.15 && action == 'CALL' && equity < 0.45) {
        action = 'FOLD';
      }
    }

    // Stack-Awareness: Short Stack geht All-In statt Raise
    final stackBbs = StackAwareness.stackInBb(ss, bb);
    if (action == 'RAISE' && StackAwareness.shouldGoAllIn(stackBbs)) action = 'ALL-IN';

    // Hand-Name anzeigen
    _handName = _street > 0 && widget.M.isNotEmpty
        ? HandEvaluator.categoryName(hr)
        : '';

    // Bet-Sizing berechnen
    final draws = DrawAnalyzer.findDraws(
      widget.M.cast<Map<String, String>>(),
      _board.cast<Map<String, String>>(),
    );
    final hasFlushDraw = draws.any((d) => d.name.toLowerCase().contains('flush'));
    final hasOESD = draws.any((d) => d.name.toLowerCase().contains('oesd') || d.name.toLowerCase().contains('open-ended'));
    final hasDraw = draws.isNotEmpty;

    final sizing = BetSizer.recommend(
      equity: equity,
      street: _street,
      pot: pt,
      stack: ss,
      handCategory: hr,
      boardWetness: _boardWetness(),
      hasDraw: hasDraw,
      hasFlushDraw: hasFlushDraw,
      hasOESD: hasOESD,
      position: p,
      facingBet: tc > 0,
      spr: pt > 0 ? ss / pt : 10.0,
    );

    setState(() {
      r = action;
      _confidence = pfAdvice != null ? 1.0 : result.confidence;
      _scores = result.scores;
      _betSizing = (action == 'RAISE' || action == 'ALL-IN') ? sizing : null;
    });

    // TTS Ausgabe
    final actionDe = {
      'FOLD': 'Passen', 'CHECK': 'Checken', 'CALL': 'Mitgehen',
      'RAISE': 'Erhöhen', 'ALL-IN': 'All In',
    }[action] ?? action;
    final eqStr = '${(_equity * 100).toStringAsFixed(0)} Prozent Equity';
    _speak('$actionDe. $eqStr.');
  }

  // Kartenfarben & Werte für Card-Picker
  static const _suits = ['♠', '♥', '♦', '♣'];
  static const _ranks = ['A','K','Q','J','10','9','8','7','6','5','4','3','2'];

  void _showCardPicker(int slot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AC.PN,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Karte wählen', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final suit in _suits)
              Wrap(
                children: _ranks.map((rank) {
                  final isRed = suit == '♥' || suit == '♦';
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        if (slot < _manualBoard.length) {
                          _manualBoard[slot] = {'r': rank, 's': suit};
                        } else {
                          _manualBoard.add({'r': rank, 's': suit});
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AC.BG,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Text('$rank$suit',
                          style: TextStyle(color: isRed ? Colors.red : Colors.white, fontSize: 13)),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _manualBoardWidget() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AC.PN,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('FLOP / TURN / RIVER', style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
            const Spacer(),
            if (_manualBoard.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _manualBoard = []),
                child: const Icon(Icons.clear, color: Colors.grey, size: 18),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (int i = 0; i < 5; i++)
              GestureDetector(
                onTap: () => _showCardPicker(i),
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  width: 52, height: 72,
                  decoration: BoxDecoration(
                    color: i < _manualBoard.length ? Colors.white : AC.BG,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i < _manualBoard.length ? AC.P : Colors.grey.shade600,
                      width: i < _manualBoard.length ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: i < _manualBoard.length
                        ? Text(
                            '${_manualBoard[i]['r']}${_manualBoard[i]['s']}',
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold,
                              color: (_manualBoard[i]['s'] == '♥' || _manualBoard[i]['s'] == '♦')
                                  ? Colors.red : Colors.black,
                            ),
                          )
                        : Text(
                            ['F', 'F', 'F', 'T', 'R'][i],
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                  ),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  void _ev() {
    if (widget.M.isEmpty) { hr = 0; return; }
    final ranks = [...widget.M.map((c) => c['r']), ..._board.map((c) => c['r'])];
    final suits = [...widget.M.map((c) => c['s']), ..._board.map((c) => c['s'])];
    Map<String?, int> rc = {}, sc = {};
    for (var x in ranks) rc[x] = (rc[x] ?? 0) + 1;
    for (var x in suits) sc[x] = (sc[x] ?? 0) + 1;
    if (sc.values.any((c) => c >= 5)) {
      hr = 5;
    } else if (rc.values.any((c) => c >= 4)) {
      hr = 7;
    } else if (rc.values.any((c) => c == 3) && rc.values.any((c) => c >= 2)) {
      hr = 6;
    } else if (rc.values.any((c) => c == 3)) {
      hr = 3;
    } else {
      hr = rc.values.where((c) => c == 2).length >= 2
          ? 2
          : (rc.values.any((c) => c == 2) ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ev();
    String sn = _board.isEmpty
        ? 'Preflop'
        : _board.length == 3 ? 'Flop'
        : _board.length == 4 ? 'Turn' : 'River';
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🦦 '), Text('Otto', style: TextStyle(fontWeight: FontWeight.bold))
        ]),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardRow('🦦 MEINE 2 KARTEN', widget.M),
          _cardRow('♠♣ TISCH: ${_board.length} Karten', _board),
          // Manuelle Community Cards Eingabe (wenn kein Scanner-Board)
          if (widget.B.isEmpty) _manualBoardWidget(),
          if (hr > 0 || widget.M.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AC.P.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.analytics, color: AC.P),
                  const SizedBox(width: 8),
                  Text('${_handName.isNotEmpty ? _handName : _handNameStr(hr)} | $sn',
                      style: const TextStyle(
                          color: AC.P, fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                if (_equity > 0) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Equity: ${(_equity * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: AC.P, fontSize: 13)),
                    if (_calcEquity) ...[
                      const SizedBox(width: 8),
                      const SizedBox(width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AC.P)),
                    ],
                    if (_oppType.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text('Gegner: $_oppType',
                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ]),
                ],
              ]),
            ),
          if (r.isNotEmpty) ...[
            // ── Empfehlung Haupt-Box ──────────────────────────────────────
            AnimatedBuilder(
              animation: _glowAnim,
              builder: (context, child) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: _actionColor().withValues(alpha: _glowAnim.value * 0.6),
                    blurRadius: 28, spreadRadius: 2,
                  )],
                ),
                child: GlassPanel(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  borderColor: _actionColor().withValues(alpha: 0.7),
                  child: Column(children: [
                    const Text('EMPFEHLUNG',
                        style: TextStyle(fontSize: 14, color: Colors.white54)),
                    Text(r, style: TextStyle(
                        fontSize: 42, fontWeight: FontWeight.bold,
                        color: _actionColor())),
                    const SizedBox(height: 2),
                    Text('${(_confidence * 100).toStringAsFixed(0)}% Konfidenz',
                        style: const TextStyle(fontSize: 12, color: Colors.white38)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // ── Action-Wahrscheinlichkeiten als farbige Balken ────────────
            if (_scores.isNotEmpty && _scores.any((s) => s > 0))
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AC.PN,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('WAHRSCHEINLICHKEITEN',
                        style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    ..._buildActionBars(),
                  ],
                ),
              ),
            // ── Empfohlener Bet-Betrag ────────────────────────────────────
            if (_betSizing != null && _betSizing!.amount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade700),
                ),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.attach_money, color: Colors.white, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        _betDisplayWithBB(),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _betSizing!.reason,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 20),
          // ── Stack & Position Info Badge ─────────────────────────────────
          _stackPositionBadge(),
          const SizedBox(height: 12),
          _dropdown('Position', p, ps, (x) => setState(() => p = x)),
          _slider('Pot', pt, 500, (x) => setState(() => pt = x)),
          _slider('Zu zahlen', tc, 200, (x) => setState(() => tc = x)),
          _slider('Stack', ss, 500, (x) => setState(() => ss = x)),
          _slider('Big Blind', bb, 50, (x) => setState(() => bb = x < 1 ? 1 : x), unit: '\$'),
          const SizedBox(height: 20),
          // Draw-Anzeige
          if (widget.M.isNotEmpty && _board.isNotEmpty) ...[
            _drawsWidget(),
            const SizedBox(height: 8),
          ],
          ElevatedButton(
            onPressed: _brainReady ? _rec : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AC.P, foregroundColor: Colors.black,
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _brainReady ? '🧠 DL EMPFEHLUNG' : 'Lade DL...',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Stack & Position Info Badge ──────────────────────────────────────────
  Widget _stackPositionBadge() {
    final pokerPos = PositionAwareness.fromIndex(p);
    final stackBbs = StackAwareness.stackInBb(ss, bb);
    final stackType = StackAwareness.classify(stackBbs);
    final stackColor = Color(StackAwareness.displayColor(stackType));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AC.PN,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Position Anzeige
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('POSITION', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              PositionAwareness.displayLabel(pokerPos),
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              PositionAwareness.strategyHint(pokerPos),
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ]),
          // Divider
          Container(width: 1, height: 40, color: Colors.grey.shade700),
          // Stack Anzeige
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('STACK', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              StackAwareness.displayLabel(stackBbs),
              style: TextStyle(
                  color: stackColor, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              StackAwareness.strategyHint(stackBbs),
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Hilfsmethode: Bet-Betrag mit BB-Angabe ──────────────────────────────
  String _betDisplayWithBB() {
    if (_betSizing == null) return '';
    final amount = _betSizing!.amount;
    final bbVal = bb > 0 ? amount / bb : 0.0;
    return '\$${amount.toStringAsFixed(0)} (${bbVal.toStringAsFixed(1)} BB) · ${_betSizing!.fractionLabel}';
  }

  // ── Hilfsmethode: Farbige Action-Balken ─────────────────────────────────
  List<Widget> _buildActionBars() {
    final labels = ['FOLD', 'CHECK/CALL', 'RAISE'];
    // Scores: [0]=FOLD, [1]=CHECK, [2]=CALL, [3]=RAISE
    // Merge CHECK+CALL zu einem Balken
    final foldPct = _scores.isNotEmpty ? _scores[0] : 0.0;
    final callPct = _scores.length >= 3 ? (_scores[1] + _scores[2]) / 2.0 : 0.0;
    final raisePct = _scores.length >= 4 ? _scores[3] : 0.0;
    // Normalisieren
    final total = foldPct + callPct + raisePct;
    final norm = total > 0 ? 1.0 / total : 1.0;
    final values = [foldPct * norm, callPct * norm, raisePct * norm];
    final colors = [Colors.red.shade600, Colors.green.shade600, Colors.blue.shade600];

    return List.generate(3, (i) {
      final pct = (values[i] * 100).toStringAsFixed(0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(labels[i],
                  style: TextStyle(color: colors[i], fontSize: 12, fontWeight: FontWeight.bold)),
              Text('$pct%',
                  style: TextStyle(color: colors[i], fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: values[i].clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(colors[i]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _cardRow(String title, List<Map<String, String>> cards) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          cards.isEmpty
              ? const Text('Keine', style: TextStyle(color: Colors.grey))
              : Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8, runSpacing: 8,
                  children: cards.map((x) {
                    bool red = x['s'] == '♥' || x['s'] == '♦';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: red ? Colors.red : Colors.black, width: 2),
                      ),
                      child: Text('${x['r']}${x['s']}',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold,
                              color: red ? Colors.red : Colors.black)),
                    );
                  }).toList()),
        ]),
      );

  Widget _dropdown(String l, int v, List<String> items, Function f) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 90,
              child: Text('$l:', style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: AC.PN, borderRadius: BorderRadius.circular(8)),
              child: DropdownButton<int>(
                value: v, isExpanded: true, underline: const SizedBox(),
                dropdownColor: AC.PN,
                items: List.generate(items.length,
                    (x) => DropdownMenuItem(value: x, child: Text(items[x]))),
                onChanged: (y) => f(y),
              ),
            ),
          ),
        ]),
      );

  Widget _slider(String l, double v, double m, Function f, {String? unit}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$l: ${unit ?? '\$'}${v.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AC.P, thumbColor: AC.P,
              inactiveTrackColor: Colors.grey.shade800,
            ),
            child: Slider(value: v, min: unit != null ? 1 : 0, max: m, onChanged: (x) => f(x)),
          ),
        ],
      );

  String _handNameStr(int r) => [
        'High Card', 'Pair', 'Two Pair', 'Three of Kind',
        'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
      ][r.clamp(0, 8)];

  Widget _drawsWidget() {
    final draws = DrawAnalyzer.findDraws(
      widget.M.cast<Map<String, String>>(),
      _board.cast<Map<String, String>>(),
    );
    final texture = DrawAnalyzer.analyzeBoard(_board.cast<Map<String, String>>());
    final totalOuts = DrawAnalyzer.totalOuts(draws);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AC.PN,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Board Texture
        Row(children: [
          const Icon(Icons.dashboard, color: Colors.grey, size: 14),
          const SizedBox(width: 6),
          Text('Board: ${texture.description}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Color.lerp(Colors.green, Colors.red, texture.wetness),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              texture.wetness > 0.6 ? 'WET' : texture.wetness > 0.3 ? 'SEMI' : 'DRY',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ]),
        if (draws.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Draws:', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: draws.map((d) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(d.emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text('${d.name} (${d.outs} outs · ${(d.probTurnOrRiver * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ]),
          )).toList()),
          if (totalOuts > 0) ...[
            const SizedBox(height: 6),
            Text('Total ~$totalOuts Outs → ${(totalOuts * 4).clamp(0, 99)}% (Rule of 4)',
                style: TextStyle(
                    color: totalOuts >= 8 ? AC.P : Colors.orange,
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Keine Draws', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
      ]),
    );
  }
}

// ─── Manuelle Karten-Eingabe ──────────────────────────────────────────────────
class CardPicker extends StatefulWidget {
  final int maxCards;
  final List<Map<String, String>> selected;
  final Function(List<Map<String, String>>) onChanged;
  const CardPicker({required this.maxCards, required this.selected, required this.onChanged, super.key});
  @override
  State<CardPicker> createState() => _CardPickerState();
}

class _CardPickerState extends State<CardPicker> {
  static const ranks = ['A','K','Q','J','10','9','8','7','6','5','4','3','2'];
  static const suits = ['♠','♥','♦','♣'];
  String _selRank = 'A';
  String _selSuit = '♠';

  bool _isSelected(String r, String s) =>
      widget.selected.any((c) => c['r'] == r && c['s'] == s);

  void _addCard() {
    if (widget.selected.length >= widget.maxCards) return;
    if (_isSelected(_selRank, _selSuit)) return;
    final newList = List<Map<String, String>>.from(widget.selected)
      ..add({'r': _selRank, 's': _selSuit, 'label': '$_selRank $_selSuit'});
    widget.onChanged(newList);
  }

  void _removeCard(int i) {
    final newList = List<Map<String, String>>.from(widget.selected)..removeAt(i);
    widget.onChanged(newList);
  }

  @override
  Widget build(BuildContext context) {
    final isRed = _selSuit == '♥' || _selSuit == '♦';
    final alreadySelected = _isSelected(_selRank, _selSuit);
    final isFull = widget.selected.length >= widget.maxCards;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Gewählte Karten
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text('KARTEN: ${widget.selected.length}/${widget.maxCards}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            widget.selected.isEmpty
                ? const Text('Noch keine Karten', style: TextStyle(color: Colors.grey))
                : Wrap(
                    spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
                    children: widget.selected.asMap().entries.map((e) {
                      final red = e.value['s'] == '♥' || e.value['s'] == '♦';
                      return GestureDetector(
                        onTap: () => _removeCard(e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: red ? Colors.red : Colors.black, width: 2),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('${e.value['r']}${e.value['s']}',
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                                    color: red ? Colors.red : Colors.black)),
                            const SizedBox(width: 4),
                            const Icon(Icons.close, size: 14, color: Colors.grey),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
          ]),
        ),
        const SizedBox(height: 16),

        // Rank Auswahl
        const Text('RANG', style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6, runSpacing: 6, alignment: WrapAlignment.center,
          children: ranks.map((r) {
            final sel = r == _selRank;
            return GestureDetector(
              onTap: () => setState(() => _selRank = r),
              child: Container(
                width: 44, height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? AC.P : AC.PN,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? AC.P : Colors.grey.shade700),
                ),
                child: Text(r, style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold,
                    color: sel ? Colors.black : Colors.white)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // Suit Auswahl
        const Text('FARBE', style: TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: suits.map((s) {
            final sel = s == _selSuit;
            final red = s == '♥' || s == '♦';
            return GestureDetector(
              onTap: () => setState(() => _selSuit = s),
              child: Container(
                width: 64, height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? (red ? Colors.red.shade700 : Colors.grey.shade800) : AC.PN,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel ? (red ? Colors.red : Colors.white) : Colors.grey.shade700,
                      width: sel ? 2 : 1),
                ),
                child: Text(s, style: TextStyle(
                    fontSize: 28, color: red ? Colors.red : Colors.white)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Preview + Add Button
        Row(children: [
          // Preview
          Container(
            width: 70, height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isRed ? Colors.red : Colors.black, width: 2),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Text('$_selRank$_selSuit',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                    color: isRed ? Colors.red : Colors.black)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 90,
              child: ElevatedButton(
                onPressed: (!isFull && !alreadySelected) ? _addCard : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AC.P,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isFull ? 'Voll' : alreadySelected ? 'Bereits gewählt' : '+ KARTE HINZUFÜGEN',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ]),
        if (widget.selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => widget.onChanged([]),
            icon: const Icon(Icons.refresh, color: Colors.grey),
            label: const Text('Alle löschen', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ]),
    );
  }
}

// ─── Scanner Screen (Kamera + ML) ────────────────────────────────────────────
class SP extends StatefulWidget {
  final String t;
  final int maxCards;
  final Function(List<Map<String, String>>) onDetected;
  const SP(this.t, {required this.maxCards, required this.onDetected, super.key});
  @override
  State<SP> createState() => _SPState();
}

class _SPState extends State<SP> with WidgetsBindingObserver {
  CameraController? _cam;
  final CardClassifier _ml = CardClassifier();
  bool _scanning = false;
  bool _camReady = false;
  bool _manualMode = false;
  String _status = 'Bereit';
  List<Map<String, String>> _detected = [];
  String? _lastLabel;
  int _confirmCount = 0;
  double _zoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  static const int kConfirmFrames = 4;

  // FIX 1: Top-3 Kandidaten (mit Zone-Info)
  List<({String label, double score, String zone})> _topCandidates = [];

  // FIX 3: Auto-Zoom Counter + erkannte Zone
  int _noDetectFrames = 0;
  String _detectedZone = '';
  static const int kAutoZoomFrames = 10;

  // FIX 4: Live-Confidence
  double _liveConfidence = 0.0;
  bool _cardDetected = false;

  // FIX 1 (Kamera): Torch-Status
  bool _torchOn = false;
  static const int kTorchFrames = 5; // Nach 5 Frames ohne Erkennung → Torch

  // FIX 5: Edge-Detection Fallback
  Map<String, String>? _edgeCard;
  bool _showEdgeConfirm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _status = 'Kamera-Zugriff verweigert');
      return;
    }
    await _ml.load();
    if (_cameras.isEmpty) {
      setState(() => _status = 'Keine Kamera gefunden');
      return;
    }
    _cam = CameraController(
      _cameras.first,
      ResolutionPreset.high, // FIX 1: Höhere Auflösung für bessere Erkennung
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cam!.initialize();

    // FIX 1: Kamera-Einstellungen für weiße Karten optimieren
    try {
      await _cam!.setExposureMode(ExposureMode.auto);
      await _cam!.setFocusMode(FocusMode.auto);
      // Belichtung leicht anheben für weiße Karten auf dunklem Tisch
      final minExposure = await _cam!.getMinExposureOffset();
      final maxExposure = await _cam!.getMaxExposureOffset();
      if (maxExposure > 0) {
        await _cam!.setExposureOffset((maxExposure * 0.2).clamp(minExposure, maxExposure));
      }
    } catch (_) {
      // Kamera unterstützt diese Einstellungen nicht → ignorieren
    }

    _minZoom = await _cam!.getMinZoomLevel();
    _maxZoom = await _cam!.getMaxZoomLevel();
    _zoom = _minZoom;
    if (mounted) setState(() => _camReady = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    _ml.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) _cam?.dispose();
    else if (state == AppLifecycleState.resumed) _init();
  }

  void _startScan() {
    if (!_camReady || _scanning) return;
    setState(() {
      _scanning = true;
      _status = 'Halte Karte in die Mitte...';
      _detected = [];
      _lastLabel = null;
      _confirmCount = 0;
      _topCandidates = [];
      _noDetectFrames = 0;
      _liveConfidence = 0.0;
      _cardDetected = false;
      _detectedZone = '';
      _edgeCard = null;
      _showEdgeConfirm = false;
    });
    // FIX 1: Torch ausschalten zu Beginn
    _setTorch(false);
    _cam!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage image) {
    if (!_scanning) return;
    if (_detected.length >= widget.maxCards) { _stopScan(); return; }

    // FIX 3: Beste Zone klassifizieren
    final zoneResult = _ml.classifyBestZone(image);
    final rawConfidence = zoneResult?.score ?? 0.0;

    // FIX 5: Edge-Detection Fallback bei sehr niedrigem Confidence
    if (rawConfidence < 0.30) {
      _noDetectFrames++;

      // FIX 1: Torch nach kTorchFrames einschalten
      if (_noDetectFrames >= kTorchFrames && !_torchOn) {
        _setTorch(true);
      }

      // FIX 3: Auto-Zoom nach kAutoZoomFrames
      if (_noDetectFrames >= kAutoZoomFrames && _zoom < _maxZoom) {
        final newZoom = (_zoom + 0.2).clamp(_minZoom, _maxZoom);
        if (newZoom != _zoom) {
          _zoom = newZoom;
          _cam?.setZoomLevel(_zoom);
        }
        _noDetectFrames = 0;
      }

      // Top-K für manuelles Bestätigen
      final topK = _ml.classifyTopK(image, k: 3);

      // FIX 4: Tipp generieren
      final tip = _scanTip(rawConfidence);

      if (mounted) setState(() {
        _liveConfidence = rawConfidence;
        _cardDetected = false;
        _status = tip;
        _topCandidates = topK;
        _detectedZone = zoneResult?.zoneName ?? '';
      });
      _lastLabel = null;
      _confirmCount = 0;
      return;
    }

    // Confidence >= 30% → Karte erkannt
    final label = zoneResult!.label;
    _noDetectFrames = 0;

    // FIX 1: Torch wieder ausschalten wenn gut erkannt
    if (_torchOn && rawConfidence > 0.5) {
      _setTorch(false);
    }

    if (mounted) {
      setState(() {
        _liveConfidence = rawConfidence;
        _cardDetected = rawConfidence >= 0.60;
        _detectedZone = zoneResult.zoneName;
        _topCandidates = rawConfidence < 0.60 ? _ml.classifyTopK(image, k: 3) : [];
      });
    }

    if (label == _lastLabel) {
      _confirmCount++;
    } else {
      _lastLabel = label;
      _confirmCount = 1;
    }

    if (_confirmCount >= kConfirmFrames) {
      final card = labelToCard(label);
      final already = _detected.any((c) => c['r'] == card['r'] && c['s'] == card['s']);
      if (!already) {
        _detected.add(card);
        widget.onDetected(List.from(_detected));
        // Zoom zurücksetzen nach erfolgreicher Erkennung
        if (_zoom > _minZoom) {
          _zoom = _minZoom;
          _cam?.setZoomLevel(_zoom);
        }
        _setTorch(false);
        if (mounted) setState(() {
          _status = _detected.length < widget.maxCards ? 'Nächste Karte...' : 'Fertig!';
          _liveConfidence = 0.0;
          _cardDetected = false;
          _detectedZone = '';
        });
      }
      _lastLabel = null;
      _confirmCount = 0;
    } else {
      final card = labelToCard(label);
      if (mounted) setState(() =>
          _status = '${card['r']}${card['s']} – Zone: $_detectedZone ($_confirmCount/$kConfirmFrames)');
    }
  }

  /// FIX 4: Scan-Tipp basierend auf Confidence
  String _scanTip(double confidence) {
    if (confidence < 0.05) return '💡 Mehr Licht – kaum was erkannt';
    if (confidence < 0.15) return '📏 Karte näher halten';
    if (confidence < 0.25) return '🎯 Karte zentrieren';
    return '⏳ Karte stabilisieren...';
  }

  /// FIX 1 (Kamera): Torch an/aus
  Future<void> _setTorch(bool on) async {
    if (_torchOn == on) return;
    try {
      await _cam?.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = on);
    } catch (_) {}
  }

  /// Top-K Kandidaten manuell bestätigen
  void _confirmCandidate(String label) {
    _setTorch(false);
    final card = labelToCard(label);
    final already = _detected.any((c) => c['r'] == card['r'] && c['s'] == card['s']);
    if (!already && _detected.length < widget.maxCards) {
      _detected.add(card);
      widget.onDetected(List.from(_detected));
    }
    setState(() {
      _topCandidates = [];
      _liveConfidence = 0.0;
      _cardDetected = false;
      _status = _detected.length < widget.maxCards ? 'Nächste Karte...' : 'Fertig!';
    });
  }

  /// FIX 5: Edge-Detection Bestätigung (manuelle Rang/Farbe Auswahl)
  void _confirmEdgeCard(String rank, String suit) {
    final card = {'r': rank, 's': suit, 'label': '$rank $suit'};
    final already = _detected.any((c) => c['r'] == rank && c['s'] == suit);
    if (!already && _detected.length < widget.maxCards) {
      _detected.add(card);
      widget.onDetected(List.from(_detected));
    }
    setState(() {
      _showEdgeConfirm = false;
      _edgeCard = null;
      _status = _detected.length < widget.maxCards ? 'Nächste Karte...' : 'Fertig!';
    });
  }

  void _stopScan() {
    _cam?.stopImageStream();
    _setTorch(false);
    if (mounted) setState(() {
      _scanning = false;
      _liveConfidence = 0.0;
      _cardDetected = false;
      _status = _detected.isNotEmpty ? 'Fertig!' : 'Gestoppt';
    });
  }

  void _reset() {
    if (_scanning) _stopScan();
    _setTorch(false);
    setState(() {
      _detected = [];
      _status = 'Bereit';
      _topCandidates = [];
      _noDetectFrames = 0;
      _liveConfidence = 0.0;
      _cardDetected = false;
      _detectedZone = '';
      _edgeCard = null;
      _showEdgeConfirm = false;
    });
    widget.onDetected([]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.t),
          actions: [
            // FIX 1: Manueller Torch-Toggle
            if (_camReady && _scanning)
              IconButton(
                icon: Icon(_torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                    color: _torchOn ? Colors.yellow : Colors.grey),
                tooltip: _torchOn ? 'Taschenlampe aus' : 'Taschenlampe an',
                onPressed: () => _setTorch(!_torchOn),
              ),
            IconButton(
              icon: Icon(_manualMode ? Icons.camera_alt : Icons.edit),
              tooltip: _manualMode ? 'Kamera' : 'Manuell',
              onPressed: () {
                if (_scanning) _stopScan();
                setState(() => _manualMode = !_manualMode);
              },
            ),
            if (_detected.isNotEmpty)
              IconButton(icon: const Icon(Icons.refresh), onPressed: _reset),
          ],
        ),
        body: _manualMode
            ? CardPicker(
                maxCards: widget.maxCards,
                selected: _detected,
                onChanged: (cards) {
                  setState(() => _detected = cards);
                  widget.onDetected(cards);
                },
              )
            : Column(children: [
          // ── Kamerabereich ───────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                // FIX 4: Grüner Rahmen wenn erkannt, roter wenn nicht
                border: Border.all(
                  color: !_scanning
                      ? Colors.grey
                      : _cardDetected
                          ? Colors.green
                          : (_liveConfidence > 0.10 ? Colors.orange : Colors.red),
                  width: _scanning ? 3 : 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _camReady
                    ? Stack(alignment: Alignment.center, children: [
                        CameraPreview(_cam!),
                        // Karten-Rahmen (grün/rot je nach Erkennung)
                        Container(
                          width: 110,
                          height: 155,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: !_scanning
                                  ? Colors.white38
                                  : _cardDetected
                                      ? Colors.green
                                      : (_liveConfidence > 0.10 ? Colors.orange : Colors.white38),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        // FIX 3: Zone-Anzeige
                        if (_detectedZone.isNotEmpty && _scanning)
                          Positioned(
                            top: 8,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('📍 $_detectedZone',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            ),
                          ),
                        // Torch-Indikator
                        if (_torchOn)
                          const Positioned(
                            top: 8,
                            left: 10,
                            child: Icon(Icons.flashlight_on, color: Colors.yellow, size: 20),
                          ),
                        // FIX 5: Edge-Detection Bestätigungs-Overlay
                        if (_showEdgeConfirm && _scanning)
                          Positioned.fill(
                            child: _buildEdgeConfirmOverlay(),
                          ),
                        // Top-K Kandidaten Overlay (wenn unter Threshold)
                        if (_topCandidates.isNotEmpty && _scanning && !_showEdgeConfirm)
                          Positioned(
                            top: 12,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.80),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade700, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Kandidaten – antippen zum Bestätigen:',
                                      style: TextStyle(color: Colors.orange, fontSize: 10)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: _topCandidates.map((c) {
                                      final card = labelToCard(c.label);
                                      final isRed = card['s'] == '♥' || card['s'] == '♦';
                                      final pct = (c.score * 100).toStringAsFixed(0);
                                      return GestureDetector(
                                        onTap: () => _confirmCandidate(c.label),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.92),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                                color: isRed ? Colors.red : Colors.black87,
                                                width: 1.5),
                                          ),
                                          child: Text(
                                            '${card['r']}${card['s']} $pct%',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: isRed ? Colors.red : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  // FIX 5: Button für manuelle Eingabe
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () => setState(() => _showEdgeConfirm = true),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade800,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('✏️ Manuell Rang+Farbe eingeben',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Status-Label unten
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(_status,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: _cardDetected
                                        ? Colors.green
                                        : (_scanning ? AC.P : Colors.white70),
                                    fontSize: 12)),
                          ),
                        ),
                      ])
                    : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const CircularProgressIndicator(color: AC.P),
                        const SizedBox(height: 12),
                        Text(_status, style: const TextStyle(color: Colors.grey)),
                      ])),
              ),
            ),
          ),
          // ── FIX 4: Live-Confidence Fortschrittsbalken ───────────────────
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Erkennungs-Confidence',
                        style: TextStyle(
                          color: _cardDetected ? Colors.green : Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${(_liveConfidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: _cardDetected
                              ? Colors.green
                              : _liveConfidence > 0.30
                                  ? Colors.orange
                                  : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _liveConfidence.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade800,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _cardDetected
                            ? Colors.green
                            : _liveConfidence > 0.30
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ── Erkannte Karten ─────────────────────────────────────────────
          if (_detected.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text('ERKANNTE KARTEN: ${_detected.length}/${widget.maxCards}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8, runSpacing: 8,
                  children: _detected.map((x) {
                    bool red = x['s'] == '♥' || x['s'] == '♦';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: red ? Colors.red : Colors.black, width: 2),
                      ),
                      child: Text('${x['r']}${x['s']}',
                          style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold,
                              color: red ? Colors.red : Colors.black)),
                    );
                  }).toList(),
                ),
              ]),
            ),
          // ── Zoom Slider ─────────────────────────────────────────────────
          if (_camReady && _maxZoom > _minZoom)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.zoom_out, color: Colors.grey, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AC.P, thumbColor: AC.P,
                      inactiveTrackColor: Colors.grey.shade800,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _zoom,
                      min: _minZoom,
                      max: _maxZoom,
                      onChanged: (v) async {
                        setState(() => _zoom = v);
                        await _cam?.setZoomLevel(v);
                      },
                    ),
                  ),
                ),
                const Icon(Icons.zoom_in, color: AC.P, size: 18),
                const SizedBox(width: 4),
                Text('${_zoom.toStringAsFixed(1)}x',
                    style: const TextStyle(color: AC.P, fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 8),
          // ── Scan / Stop Buttons ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _scanning ? _stopScan : (_camReady ? _startScan : null),
                  icon: Icon(_scanning ? Icons.stop : Icons.camera_alt),
                  label: Text(_scanning ? 'STOP' : 'SCANNEN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _scanning ? Colors.red : AC.P,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_detected.isNotEmpty) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _reset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
        ]),  // Column Ende
      );    // Scaffold Ende

  /// FIX 5: Edge-Detection Fallback Overlay (manuelle Rang+Farbe Bestätigung)
  Widget _buildEdgeConfirmOverlay() {
    const ranks = ['A','K','Q','J','10','9','8','7','6','5','4','3','2'];
    const suits = ['♠','♥','♦','♣'];
    String selRank = _edgeCard?['r'] ?? 'A';
    String selSuit = _edgeCard?['s'] ?? '♠';

    return StatefulBuilder(
      builder: (ctx, setLocal) => Container(
        color: Colors.black.withOpacity(0.92),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('KARTE MANUELL BESTÄTIGEN',
                style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // Rang-Auswahl
            const Text('RANG', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4, runSpacing: 4, alignment: WrapAlignment.center,
              children: ranks.map((r) {
                final sel = r == selRank;
                return GestureDetector(
                  onTap: () => setLocal(() { selRank = r; _edgeCard = {'r': r, 's': selSuit}; }),
                  child: Container(
                    width: 36, height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? AC.P : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(r, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold,
                        color: sel ? Colors.black : Colors.white)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // Farbe-Auswahl
            const Text('FARBE', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: suits.map((s) {
                final sel = s == selSuit;
                final red = s == '♥' || s == '♦';
                return GestureDetector(
                  onTap: () => setLocal(() { selSuit = s; _edgeCard = {'r': selRank, 's': s}; }),
                  child: Container(
                    width: 52, height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? (red ? Colors.red.shade700 : Colors.grey.shade700) : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? Colors.white : Colors.grey.shade700, width: sel ? 2 : 1),
                    ),
                    child: Text(s, style: TextStyle(fontSize: 24, color: red ? Colors.red : Colors.white)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _confirmEdgeCard(selRank, selSuit),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('✓ $selRank$selSuit bestätigen',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => setState(() { _showEdgeConfirm = false; _edgeCard = null; }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
