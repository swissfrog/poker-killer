import 'package:flutter/material.dart';

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
    // Simple scoring
    double score = (handRank / 8.0) * 0.5 + ((6 - position) / 6.0) * 0.3 + 0.2;
    
    // Stack pressure
    if (stackSize < 20) score -= 0.2;
    if (stackSize > 150) score += 0.1;
    
    // Pot odds
    double potOdds = (toCall > 0) ? toCall / (pot + toCall) : 0;
    bool profitable = potOdds < (handRank / 8.0);
    
    if (toCall > stackSize * 0.4) return 'FOLD';
    if (score > 0.7) return stackSize < 40 ? 'ALL-IN' : 'RAISE';
    if (score > 0.45) return profitable ? 'CALL' : 'CHECK';
    if (toCall < pot * 0.15 && score > 0.25) return 'CALL';
    return toCall == 0 ? 'CHECK' : 'FOLD';
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
                    const Text('🤖 ML Engine', style: TextStyle(fontSize: 14, color: Colors.black87)),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(8)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology, color: AppConfig.primaryColor, size: 20),
                  SizedBox(width: 8),
                  Text('PokerKiller ML Engine', style: TextStyle(color: AppConfig.primaryColor, fontWeight: FontWeight.bold)),
                ],
              ),
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
