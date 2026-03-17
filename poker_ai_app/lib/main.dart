import 'package:flutter/material.dart';

void main() => runApp(const PokerKillerApp());

class AppConfig {
  static const String appName = 'PokerKiller';
  static const Color primaryColor = Color(0xFF00ff88);
  static const Color bgColor = Color(0xFF1a1a2e);
  static const Color panelColor = Color(0xFF16213e);
}

class PokerKillerApp extends StatelessWidget {
  const PokerKillerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: appName, debugShowCheckedModeBanner: false, theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: bgColor, primaryColor: primaryColor), home: const MainNavigator());
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});
  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;
  List<Map<String, String>> _holeCards = [];
  List<Map<String, String>> _boardCards = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: [
        RecommenderPage(holeCards: _holeCards, boardCards: _boardCards),
        ScanPage(title: 'Meine Karten', onDetected: (c) => setState(() => _holeCards = c)),
        ScanPage(title: 'Tisch', onDetected: (c) => setState(() => _boardCards = c)),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i),
        selectedItemColor: primaryColor, backgroundColor: panelColor,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.poker_chip), label: 'Empfehlung'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Meine Karten'),
          BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'Tisch'),
        ],
      ),
    );
  }
}

class RecommenderPage extends StatefulWidget {
  final List<Map<String, String>> holeCards, boardCards;
  const RecommenderPage({super.key, required this.holeCards, required this.boardCards});
  @override
  State<RecommenderPage> createState() => _RecommenderPageState();
}

class _RecommenderPageState extends State<RecommenderPage> {
  int position = 2, handRank = 0;
  double pot = 100, toCall = 20, stackSize = 200;
  String recommendation = '';
  final positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];

  void _getRecommendation() {
    int street = widget.boardCards.isEmpty ? 0 : widget.boardCards.length < 4 ? 1 : widget.boardCards.length < 5 ? 2 : 3;
    double score = (handRank / 8.0) * 0.5 + ((6 - position) / 6.0) * 0.3 + 0.2;
    if (stackSize < 20) score -= 0.2;
    double potOdds = toCall > 0 ? toCall / (pot + toCall) : 0;
    bool profitable = potOdds < (handRank / 8.0);
    if (toCall > stackSize * 0.4) recommendation = 'FOLD';
    else if (score > 0.7) recommendation = stackSize < 40 ? 'ALL-IN' : 'RAISE';
    else if (score > 0.45) recommendation = profitable ? 'CALL' : 'CHECK';
    else recommendation = toCall == 0 ? 'CHECK' : 'FOLD';
    setState(() {});
  }

  void _updateHand() {
    if (widget.holeCards.isEmpty) return;
    List<String> ranks = widget.holeCards.map((c) => c['rank']!).toList();
    List<String> suits = widget.holeCards.map((c) => c['suit']!).toList();
    if (widget.boardCards.isNotEmpty) {
      ranks.addAll(widget.boardCards.map((c) => c['rank']!));
      suits.addAll(widget.boardCards.map((c) => c['suit']!));
    }
    Map<String, int> rc = {}, sc = {};
    for (var r in ranks) rc[r] = (rc[r] ?? 0) + 1;
    for (var s in suits) sc[s] = (sc[s] ?? 0) + 1;
    if (sc.values.any((c) => c >= 5)) handRank = 5;
    else if (rc.values.any((c) => c >= 4)) handRank = 7;
    else if (rc.values.any((c) => c == 3) && rc.values.any((c) => c >= 2)) handRank = 6;
    else if (rc.values.any((c) => c == 3)) handRank = 3;
    else handRank = rc.values.where((c) => c == 2).length >= 2 ? 2 : (rc.values.any((c) => c == 2) ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    _updateHand();
    return Scaffold(
      appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min, children: [Text('🃏 '), Text('PokerKiller', style: TextStyle(fontWeight: FontWeight.bold))]), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _cardSection('🃏 MEINE KARTEN', widget.holeCards),
          _cardSection('♠♣ TISCH', widget.boardCards),
          if (handRank > 0 || widget.holeCards.isNotEmpty) Container(
            padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.analytics, color: primaryColor), const SizedBox(width: 8), Text('Hand: ${_handName(handRank)}', style: const TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold))])),
          if (recommendation.isNotEmpty) Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: LinearGradient(colors: recommendation == 'ALL-IN' ? [Colors.red, Colors.red.shade700] : [primaryColor, primaryColor.withOpacity(0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [const Text('EMPFEHLUNG', style: TextStyle(fontSize: 14, color: Colors.black54)), Text(recommendation, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black))])),
          const SizedBox(height: 20),
          _dropdown('Position', position, positions, (v) => setState(() => position = v)),
          _slider('Pot', pot, 500, (v) => setState(() => pot = v)),
          _slider('Zu zahlen', toCall, 200, (v) => setState(() => toCall = v)),
          _slider('Stack', stackSize, 500, (v) => setState(() => stackSize = v)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _getRecommendation, style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.black, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('🎯 EMPFEHLUNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  Widget _cardSection(String title, List<Map<String, String>> cards) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(8)),
    child: Column(children: [Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 8),
      cards.isEmpty ? const Text('Keine Karten', style: TextStyle(color: Colors.grey)) : Row(mainAxisAlignment: MainAxisAlignment.center, children: cards.map((c) { bool isRed = c['suit'] == '♥' || c['suit'] == '♦'; return Container(margin: const EdgeInsets.all(4), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: isRed ? Colors.red : Colors.black, width: 2)), child: Text('${c['rank']}${c['suit']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isRed ? Colors.red : Colors.black))); }).toList())]));

  Widget _dropdown(String label, int value, List<String> items, Function(int) onChanged) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [SizedBox(width: 90, child: Text('$label:', style: const TextStyle(color: Colors.white70))), Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(8)), child: DropdownButton<int>(value: value, isExpanded: true, underline: const SizedBox(), dropdownColor: panelColor, items: List.generate(items.length, (i) => DropdownMenuItem(value: i, child: Text(items[i]))), onChanged: (v) => onChanged(v!))))]));

  Widget _slider(String label, double value, double max, Function(double) onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$label: \$${value.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 13)), SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: primaryColor, thumbColor: primaryColor, inactiveTrackColor: Colors.grey.shade800), child: Slider(value: value, min: 0, max: max, onChanged: onChanged))]);

  String _handName(int r) => ['High Card', 'Pair', 'Two Pair', 'Three of Kind', 'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'][r.clamp(0, 8)];
}

class ScanPage extends StatefulWidget {
  final String title;
  final Function(List<Map<String, String>>) onDetected;
  const ScanPage({super.key, required this.title, required this.onDetected});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _isScanning = false;
  List<Map<String, String>> _cards = [];

  void _scan() {
    setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 2), () {
      // Demo: Generate random cards (in real app: use camera + ML Kit OCR)
      List<String> rs = ['A','K','Q','J','10','9','8','7','6','5','4','3','2'];
      List<String> ss = ['♠','♥','♦','♣'];
      _cards = [{'rank': rs[DateTime.now().millisecond % 13], 'su': ss[DateTime.now().second % 4]}, {'rank': rs[DateTime.now().second % 13], 'su': ss[DateTime.now().millisecond % 4]}];
      widget.onDetected(_cards);
      setState(() => _isScanning = false);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(children: [
      Expanded(child: Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: _isScanning ? primaryColor : Colors.grey, width: 2)),
        child: Center(child: _isScanning ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(color: primaryColor), const SizedBox(height: 16), const Text('Scanne...', style: TextStyle(color: primaryColor, fontSize: 18)), const Text('Halte Karten vor die Kamera', style: TextStyle(color: Colors.grey, fontSize: 14))]) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt, size: 64, color: Colors.grey), const SizedBox(height: 16), const Text('Bereit zum Scannen', style: TextStyle(color: Colors.grey, fontSize: 18))])))),
      if (_cards.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [const Text('ERKANNTE KARTEN', style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.center, children: _cards.map((c) { bool isRed = c['su'] == '♥' || c['su'] == '♦'; return Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isRed ? Colors.red : Colors.black, width: 2)), child: Text('${c['rank']}${c['su']}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isRed ? Colors.red : Colors.black))); }).toList())])),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.all(16), child: ElevatedButton.icon(onPressed: _isScanning ? null : _scan, icon: Icon(_isScanning ? Icons.hourglass_top : Icons.camera_alt), label: Text(_isScanning ? 'Scanne...' : 'KARTEN SCANNEN'), style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.black, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
      const Text('Halte die Karten vor die Kamera', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
    ]),
  );
}
