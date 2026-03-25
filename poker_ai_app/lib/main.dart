import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'hand_evaluator.dart';
import 'preflop_ranges.dart';
import 'opponent_tracker.dart';
import 'draw_analyzer.dart';
import 'bet_sizer.dart';
import 'stack_awareness.dart';
import 'position_awareness.dart';

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

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset('assets/poker_brain.tflite');
  }

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

      final scores = output[0];
      int maxIdx = 0;
      double maxVal = scores[0];
      for (int i = 1; i < 4; i++) {
        if (scores[i] > maxVal) { maxVal = scores[i]; maxIdx = i; }
      }

      String action = kActions[maxIdx];

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
      // YUV420 → Graustufen 70x70 float32 [0,1]
      final input = _prepareInput(cameraImage);

      final output = [List.filled(52, 0.0)];
      _interpreter!.run(input, output);

      final scores = output[0];
      int maxIdx = 0;
      double maxVal = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > maxVal) {
          maxVal = scores[i];
          maxIdx = i;
        }
      }

      // Mindest-Confidence 15% (gesenkt f�r bessere Erkennung)
      if (maxVal < 0.15) return null;
      return kKaggleLabels[maxIdx];
    } catch (_) {
      return null;
    }
  }

  /// CameraImage → [1][70][70][1] float32
  List prepareInput(CameraImage cameraImage) => _prepareInput(cameraImage);

  List _prepareInput(CameraImage cameraImage) {
    final yPlane = cameraImage.planes[0].bytes;
    final srcW = cameraImage.width;
    final srcH = cameraImage.height;

    // Y-Kanal (Graustufen) direkt aus YUV420
    final grayImg = img.Image(width: srcW, height: srcH);
    for (int y = 0; y < srcH; y++) {
      for (int x = 0; x < srcW; x++) {
        final val = yPlane[y * srcW + x];
        grayImg.setPixelRgb(x, y, val, val, val);
      }
    }
    final resized = img.copyResize(grayImg, width: 70, height: 70);

    return [
      List.generate(
        70,
        (y) => List.generate(
          70,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r / 255.0];
          },
        ),
      )
    ];
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

class _RPState extends State<RP> {
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

  @override
  void initState() {
    super.initState();
    _brain.load().then((_) => setState(() => _brainReady = true));
  }

  @override
  void dispose() {
    _brain.dispose();
    super.dispose();
  }

  int get _street => widget.B.isEmpty ? 0 : widget.B.length == 3 ? 1 : widget.B.length == 4 ? 2 : 3;

  // Echte Monte-Carlo Equity aus Dart-Evaluator
  Future<double> _calcRealEquity() async {
    if (widget.M.isEmpty) return 0.5;
    return HandEvaluator.monteCarloEquity(
      widget.M.cast<Map<String, String>>(),
      widget.B.cast<Map<String, String>>(),
      simulations: 300,
    );
  }

  double _boardWetness() {
    if (widget.B.isEmpty) return 0.3;
    final suits = widget.B.map((c) => c['s'] ?? '').toList();
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
      widget.B.cast<Map<String, String>>(),
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
  }

  void _ev() {
    if (widget.M.isEmpty) { hr = 0; return; }
    final ranks = [...widget.M.map((c) => c['r']), ...widget.B.map((c) => c['r'])];
    final suits = [...widget.M.map((c) => c['s']), ...widget.B.map((c) => c['s'])];
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
    String sn = widget.B.isEmpty
        ? 'Preflop'
        : widget.B.length == 3 ? 'Flop'
        : widget.B.length == 4 ? 'Turn' : 'River';
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
          _cardRow('♠♣ TISCH: ${widget.B.length} Karten', widget.B),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: r == 'ALL-IN'
                      ? [Colors.red, Colors.red.shade700]
                      : [AC.P, AC.P.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                const Text('EMPFEHLUNG',
                    style: TextStyle(fontSize: 14, color: Colors.black54)),
                Text(r,
                    style: const TextStyle(
                        fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black)),
                const SizedBox(height: 2),
                Text('${(_confidence * 100).toStringAsFixed(0)}% Konfidenz',
                    style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ]),
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
          if (widget.M.isNotEmpty && widget.B.isNotEmpty) ...[
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
      widget.B.cast<Map<String, String>>(),
    );
    final texture = DrawAnalyzer.analyzeBoard(widget.B.cast<Map<String, String>>());
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
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _cam!.initialize();
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
    });
    _cam!.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage image) {
    if (!_scanning) return;
    if (_detected.length >= widget.maxCards) { _stopScan(); return; }

    final label = _ml.classify(image);
    if (label == null) {
      if (mounted) setState(() => _status = 'Karte nicht erkannt - bessere Beleuchtung?');
      _lastLabel = null;
      _confirmCount = 0;
      return;
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
        if (mounted) setState(() {
          _status = _detected.length < widget.maxCards ? 'Nächste Karte...' : 'Fertig!';
        });
      }
      _lastLabel = null;
      _confirmCount = 0;
    } else {
      final card = labelToCard(label);
      if (mounted) setState(() =>
          _status = '${card['r']}${card['s']} erkannt ($_confirmCount/$kConfirmFrames)');
    }
  }

  void _stopScan() {
    _cam?.stopImageStream();
    if (mounted) setState(() {
      _scanning = false;
      _status = _detected.isNotEmpty ? 'Fertig!' : 'Gestoppt';
    });
  }

  void _reset() {
    if (_scanning) _stopScan();
    setState(() { _detected = []; _status = 'Bereit'; });
    widget.onDetected([]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.t),
          actions: [
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
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _scanning ? AC.P : Colors.grey, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _camReady
                    ? Stack(alignment: Alignment.center, children: [
                        CameraPreview(_cam!),
                        // Rahmen für Karte
                        Container(
                          width: 110,
                          height: 155,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _scanning ? AC.P : Colors.white38, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(_status,
                                style: TextStyle(
                                    color: _scanning ? AC.P : Colors.white70,
                                    fontSize: 13)),
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
          // Zoom Slider
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
}
