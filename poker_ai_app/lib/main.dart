import 'package:flutter/material.dart';
import 'dart:math';

void main() {
  runApp(const PokerKillerApp());
}

// ===================== POKER KILLER ML ENGINE =====================

class PokerKillerEngine {
  static String getRecommendation({
    required int position,
    required int street,
    required int handRank,
    required double pot,
    required double toCall,
    required double stackSize,
  }) {
    double score = (handRank / 8.0) * 0.5 + ((6 - position) / 6.0) * 0.3 + 0.2;
    if (stackSize < 20) score -= 0.2;
    if (stackSize > 150) score += 0.1;
    double potOdds = (toCall > 0) ? toCall / (pot + toCall) : 0;
    bool profitable = potOdds < (handRank / 8.0);
    if (toCall > stackSize * 0.4) return 'FOLD';
    if (score > 0.7) return stackSize < 40 ? 'ALL-IN' : 'RAISE';
    if (score > 0.45) return profitable ? 'CALL' : 'CHECK';
    if (toCall < pot * 0.15 && score > 0.25) return 'CALL';
    return toCall == 0 ? 'CHECK' : 'FOLD';
  }
}

// ===================== CARD RECOGNITION =====================

class CardRecognizer {
  static List<Map<String, String>> simulateDetection() {
    // Simulate card detection - in real app, this would analyze camera feed
    List<String> ranks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];
    List<String> suits = ['♠', '♥', '♦', '♣'];
    Random rand = Random();
    
    return [
      {'rank': ranks[rand.nextInt(ranks.length)], 'suit': suits[rand.nextInt(suits.length)]},
      {'rank': ranks[rand.nextInt(ranks.length)], 'suit': suits[rand.nextInt(suits.length)]},
    ];
  }
  
  static int evaluateHand(List<Map<String, String>> cards) {
    if (cards.length < 2) return 0;
    
    String r1 = cards[0]['rank']!;
    String r2 = cards[1]['rank']!;
    
    if (r1 == r2) {
      if (r1 == 'A') return 7;
      if (r1 == 'K') return 6;
      if (r1 == 'Q') return 5;
      return 4;
    }
    
    List<String> high = ['A', 'K', 'Q', 'J'];
    if (high.contains(r1) || high.contains(r2)) return 3;
    
    return 2;
  }
}

// ===================== APP =====================

class AppConfig {
  static const String appName = 'PokerKiller';
  static const Color primaryColor = Color(0xFF00ff88);
  static const Color bgColor = Color(0xFF1a1a2e);
  static const Color panelColor = Color(0xFF16213e);
}

class PokerKillerApp extends StatelessWidget {
  const PokerKillerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppConfig.bgColor,
        primaryColor: AppConfig.primaryColor,
      ),
      home: const MainNavigator(),
    );
  }
}

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;
  List<Map<String, String>> _detectedCards = [];
  
  static final List<Widget> _pages = [];

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      RecommenderPage(detectedCards: _detectedCards, onCardsDetected: _updateCards),
      CameraPage(onCardsDetected: _updateCards),
    ]);
  }
  
  void _updateCards(List<Map<String, String>> cards) {
    setState(() {
      _detectedCards = cards;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: AppConfig.primaryColor,
        unselectedItemColor: Colors.grey,
        backgroundColor: AppConfig.panelColor,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.poker_chip), label: 'Empfehlung'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Kamera'),
        ],
      ),
    );
  }
}

// ===================== RECOMMENDER PAGE =====================

class RecommenderPage extends StatefulWidget {
  final List<Map<String, String>> detectedCards;
  final Function(List<Map<String, String>>) onCardsDetected;
  
  const RecommenderPage({super.key, required this.detectedCards, required this.onCardsDetected});

  @override
  State<RecommenderPage> createState() => _RecommenderPageState();
}

class _RecommenderPageState extends State<RecommenderPage> {
  int position = 2;
  int street = 0;
  int handRank = 5;
  double pot = 100;
  double toCall = 20;
  double stackSize = 200;
  
  String recommendation = '';

  final List<String> positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
  final List<String> streets = ['Preflop', 'Flop', 'Turn', 'River'];
  final List<String> handNames = ['High Card', 'Pair', 'Two Pair', 'Three of Kind', 'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'];

  @override
  void didUpdateWidget(RecommenderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detectedCards.isNotEmpty) {
      handRank = CardRecognizer.evaluateHand(widget.detectedCards);
    }
  }
  
  void _getRecommendation() {
    setState(() {
      recommendation = PokerKillerEngine.getRecommendation(
        position: position,
        street: street,
        handRank: handRank,
        pot: pot,
        toCall: toCall,
        stackSize: stackSize,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🃏 ', style: TextStyle(fontSize: 24)),
            Text('PokerKiller', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.detectedCards.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConfig.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppConfig.primaryColor),
                ),
                child: Column(
                  children: [
                    const Text('📷 ERKANnte KARTEN', style: TextStyle(color: AppConfig.primaryColor)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: widget.detectedCards.map((c) {
                        bool isRed = c['suit'] == '♥' || c['suit'] == '♦';
                        return Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${c['rank']}${c['suit']}', 
                            style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold,
                              color: isRed ? Colors.red : Colors.black,
                            )),
                        );
                      }).toList(),
                    ),
                    Text('Hand: ${handNames[handRank]}', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            if (recommendation.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: recommendation == 'ALL-IN' 
                      ? [Colors.red, Colors.red.shade700]
                      : [AppConfig.primaryColor, AppConfig.primaryColor.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text('EMPFEHLUNG', style: TextStyle(fontSize: 14, color: Colors.black54)),
                    Text(recommendation, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black)),
                  ],
                ),
              ),
            
            const SizedBox(height: 20),
            _buildDropdown('Position', position, positions, (v) => setState(() => position = v)),
            _buildDropdown('Street', street, streets, (v) => setState(() => street = v)),
            _buildDropdown('Hand', handRank, handNames, (v) => setState(() => handRank = v)),
            _buildSlider('Pot', pot, 500, (v) => setState(() => pot = v)),
            _buildSlider('Zu zahlen', toCall, 200, (v) => setState(() => toCall = v)),
            _buildSlider('Stack', stackSize, 500, (v) => setState(() => stackSize = v)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _getRecommendation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('🎯 EMPFEHLUNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, int value, List<String> items, Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text('$label:', style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(8)),
              child: DropdownButton<int>(
                value: value,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: AppConfig.panelColor,
                items: List.generate(items.length, (i) => DropdownMenuItem(value: i, child: Text(items[i]))),
                onChanged: (v) => onChanged(v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double max, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: \$${value.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppConfig.primaryColor,
            thumbColor: AppConfig.primaryColor,
            inactiveTrackColor: Colors.grey.shade800,
          ),
          child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

// ===================== CAMERA PAGE =====================

class CameraPage extends StatefulWidget {
  final Function(List<Map<String, String>>) onCardsDetected;
  
  const CameraPage({super.key, required this.onCardsDetected});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  bool _isScanning = false;
  List<Map<String, String>> _detectedCards = [];
  
  void _scanCards() {
    setState(() {
      _isScanning = true;
    });
    
    // Simulate card recognition
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        List<Map<String, String>> cards = CardRecognizer.simulateDetection();
        
        setState(() {
          _detectedCards = cards;
          _isScanning = false;
        });
        
        // Send to recommender
        widget.onCardsDetected(cards);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📷 Karten-Erkennung'),
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isScanning ? AppConfig.primaryColor : Colors.grey,
                  width: 2,
                ),
              ),
              child: Center(
                child: _isScanning
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: AppConfig.primaryColor),
                        const SizedBox(height: 16),
                        const Text('Scanne Karten...', style: TextStyle(color: AppConfig.primaryColor, fontSize: 18)),
                        const SizedBox(height: 8),
                        const Text('Halte Karten vor die Kamera', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Bereit zum Scannen', style: TextStyle(color: Colors.grey, fontSize: 18)),
                        const SizedBox(height: 8),
                        const Text('Tippe unten auf Scan', style: TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
              ),
            ),
          ),
          
          // Detected cards display
          if (_detectedCards.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConfig.panelColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text('ERKANnte KARTEN', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _detectedCards.map((card) {
                      bool isRed = card['suit'] == '♥' || card['suit'] == '♦';
                      return Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isRed ? Colors.red : Colors.black, width: 2),
                        ),
                        child: Text(
                          '${card['rank']}${card['suit']}',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isRed ? Colors.red : Colors.black),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hand: ${_getHandName(CardRecognizer.evaluateHand(_detectedCards))}',
                    style: const TextStyle(color: AppConfig.primaryColor, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Scan button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanCards,
              icon: Icon(_isScanning ? Icons.hourglass_top : Icons.camera_alt),
              label: Text(_isScanning ? 'Scanne...' : 'KARTEN SCANNEN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          const Text('Tippe auf Scan um Karten zu erkennen', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
  
  String _getHandName(int rank) {
    List<String> names = ['High Card', 'Pair', 'Two Pair', 'Three of Kind', 'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'];
    return rank < names.length ? names[rank] : 'Unknown';
  }
}
