import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(PokerAIApp(cameras: cameras));
}

class PokerAIApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const PokerAIApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker AI',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12141C),
      ),
      home: PokerAIScreen(cameras: cameras),
    );
  }
}

class PokerAIScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const PokerAIScreen({super.key, required this.cameras});

  @override
  State<PokerAIScreen> createState() => _PokerAIScreenState();
}

class _PokerAIScreenState extends State<PokerAIScreen> {
  CameraController? _controller;
  List<String> heroCards = [];
  List<String> boardCards = [];
  double equity = 0;
  String recommendation = "";
  String reason = "";
  final List<String> demoDeck = [];
  int demoIdx = 0;
  String position = "BTN";

  @override
  void initState() {
    super.initState();
    initDeck();
    initCamera();
  }

  void initDeck() {
    final suits = ['h', 'd', 'c', 's'];
    final ranks = ['A', 'K', 'Q', 'J', 'T', '9', '8', '7', '6', '5'];
    for (var s in suits) {
      for (var r in ranks) {
        demoDeck.add('$r$s');
      }
    }
    demoDeck.shuffle();
  }

  Future<void> initCamera() async {
    if (widget.cameras.isEmpty) return;
    _controller = CameraController(widget.cameras.first, ResolutionPreset.high);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  void addCard() {
    setState(() {
      if (heroCards.length < 2) {
        heroCards.add(demoDeck[demoIdx]);
      } else if (boardCards.length < 5) {
        boardCards.add(demoDeck[demoIdx + 2]);
      } else {
        heroCards = [];
        boardCards = [];
        heroCards.add(demoDeck[demoIdx]);
      }
      demoIdx = (demoIdx + 1) % demoDeck.length;
      calculate();
    });
  }

  void calculate() {
    if (heroCards.length < 2) {
      equity = 0;
      recommendation = "WARTE";
      reason = "Brauche 2 Karten";
      return;
    }

    equity = 0.5;
    final ranks = heroCards.map((c) => c[0]).toList();
    if (ranks[0] == ranks[1]) equity += 0.30;
    if (heroCards[0][1] == heroCards[1][1]) equity += 0.10;
    final highCards = ranks.where((r) => 'AKQJT'.contains(r)).length;
    equity += highCards * 0.08;
    equity += boardCards.length * 0.05;
    if (position == "BTN" || position == "CO") equity += 0.03;
    equity = equity.clamp(0.0, 0.98);

    if (equity > 0.75) {
      recommendation = "RAISE";
      reason = "Starke Hand";
    } else if (equity > 0.50) {
      recommendation = "CALL";
      reason = "OK";
    } else if (equity > 0.35) {
      recommendation = "CHECK";
      reason = "Abwarten";
    } else {
      recommendation = "FOLD";
      reason = "Zu schwach";
    }
  }

  void reset() {
    setState(() {
      heroCards = [];
      boardCards = [];
      recommendation = "";
      equity = 0;
    });
  }

  void cyclePos() {
    final pos = ["UTG", "MP", "CO", "BTN", "SB", "BB"];
    final i = pos.indexOf(position);
    setState(() {
      position = pos[(i + 1) % pos.length];
      calculate();
    });
  }

  Color getRecColor() {
    if (recommendation == "RAISE") return const Color(0xFF00FF88);
    if (recommendation == "CALL") return const Color(0xFF00AAFF);
    if (recommendation == "CHECK") return const Color(0xFFFFCC00);
    return const Color(0xFFFF4466);
  }

  Widget cardWidget(String card, bool small) {
    if (card.isEmpty) return const SizedBox();
    final rank = card[0];
    final suit = card[1];
    final isRed = suit == 'h' || suit == 'd';
    final suitSymbol = {'h': '♥', 'd': '♦', 'c': '♣', 's': '♠'}[suit] ?? '?';
    final color = isRed ? const Color(0xFFFF6666) : const Color(0xFF6699FF);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: small ? 4 : 8),
      width: small ? 45 : 60,
      height: small ? 65 : 90,
      decoration: BoxDecoration(
        color: isRed ? const Color(0xFF3A2222) : const Color(0xFF22223A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(rank, style: TextStyle(fontSize: small ? 18 : 24, fontWeight: FontWeight.bold, color: color)),
          Text(suitSymbol, style: TextStyle(fontSize: small ? 18 : 28, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(_controller!)),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("POKER AI", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00AAFF))),
                      Text(position, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),
                const Spacer(),
                if (boardCards.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF1A1D2A).withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: boardCards.map((c) => cardWidget(c, true)).toList(),
                    ),
                  ),
                if (recommendation.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFF1A1D2A), borderRadius: BorderRadius.circular(20), border: Border.all(color: getRecColor(), width: 3)),
                    child: Column(
                      children: [
                        Text(recommendation, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: getRecColor())),
                        Text(reason, style: const TextStyle(color: Colors.grey)),
                        Text("Equity: ${(equity * 100).toStringAsFixed(0)}%", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF1A1D2A), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: heroCards.isEmpty 
                      ? [const Text("-", style: TextStyle(fontSize: 32))] 
                      : heroCards.map((c) => cardWidget(c, false)).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(child: ElevatedButton.icon(onPressed: addCard, icon: const Icon(Icons.add), label: const Text("Karte"), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00AAFF), padding: const EdgeInsets.symmetric(vertical: 14)))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton.icon(onPressed: cyclePos, icon: const Icon(Icons.place), label: Text(position), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2D3A), padding: const EdgeInsets.symmetric(vertical: 14)))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton.icon(onPressed: reset, icon: const Icon(Icons.refresh), label: const Text("Reset"), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2D3A), padding: const EdgeInsets.symmetric(vertical: 14)))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
