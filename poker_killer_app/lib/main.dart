import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

void main() {
  runApp(const PokerKillerApp());
}

// ===================== APP CONFIG =====================

class AppConfig {
  static const String appName = 'KartenKiller';
  static const String version = '1.0.0';
  static const Color primaryColor = Color(0xFF00ff88);
  static const Color bgColor = Color(0xFF1a1a2e);
  static const Color panelColor = Color(0xFF16213e);
  
  static const List<String> languages = ['DE', 'EN'];
  static String currentLang = 'DE';
  
  static final Map<String, Map<String, String>> translations = {
    'DE': {
      'recommendation': 'Empfehlung',
      'training': 'Training',
      'stats': 'Statistiken',
      'camera': 'Kamera',
      'settings': 'Einstellungen',
      'fold': 'Fold',
      'check': 'Check',
      'call': 'Call',
      'bet': 'Bet',
      'raise': 'Raise',
      'allin': 'All-In',
      'position': 'Position',
      'street': 'Street',
      'hand': 'Hand',
      'pot': 'Pot',
      'stack': 'Stack',
      'board': 'Board',
      'danger': 'Danger',
      'bluff': 'Bluff',
      'value': 'Value',
      'winrate': 'Win-Rate',
      'hands': 'Hände',
      'tournament': 'Turnier',
      'language': 'Sprache',
      'tts': 'Sprachausgabe',
      'opponent': 'Gegner',
      'tracking': 'Tracking',
    },
    'EN': {
      'recommendation': 'Recommendation',
      'training': 'Training',
      'stats': 'Statistics',
      'camera': 'Camera',
      'settings': 'Settings',
      'fold': 'Fold',
      'check': 'Check',
      'call': 'Call',
      'bet': 'Bet',
      'raise': 'Raise',
      'allin': 'All-In',
      'position': 'Position',
      'street': 'Street',
      'hand': 'Hand',
      'pot': 'Pot',
      'stack': 'Stack',
      'board': 'Board',
      'danger': 'Danger',
      'bluff': 'Bluff',
      'value': 'Value',
      'winrate': 'Win-Rate',
      'hands': 'Hands',
      'tournament': 'Tournament',
      'language': 'Language',
      'tts': 'Voice Output',
      'opponent': 'Opponent',
      'tracking': 'Tracking',
    },
  };
  
  static String t(String key) {
    return translations[currentLang]?[key] ?? key;
  }
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
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: AppConfig.primaryColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppConfig.panelColor,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppConfig.panelColor,
          selectedItemColor: AppConfig.primaryColor,
          unselectedItemColor: Colors.grey,
        ),
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
  
  static final List<Widget> _pages = [
    const RecommenderPage(),
    const CameraPage(),
    const TournamentPage(),
    const StatsPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.poker_chip), label: AppConfig.t('recommendation')),
          BottomNavigationBarItem(icon: const Icon(Icons.camera_alt), label: AppConfig.t('camera')),
          BottomNavigationBarItem(icon: const Icon(Icons.emoji_events), label: AppConfig.t('tournament')),
          BottomNavigationBarItem(icon: const Icon(Icons.bar_chart), label: AppConfig.t('stats')),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: AppConfig.t('settings')),
        ],
      ),
    );
  }
}

// ===================== EMPFEHLUNGS-SEITE =====================

class RecommenderPage extends StatefulWidget {
  const RecommenderPage({super.key});

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
  String reason = '';
  String boardTexture = 'unknown';
  int boardDanger = 0;
  bool isBluff = false;
  bool ttsEnabled = true;

  final List<String> positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
  final List<String> streets = ['Preflop', 'Flop', 'Turn', 'River'];
  final List<String> handNames = [
    'High Card', 'Pair', 'Two Pair', 'Three of Kind',
    'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
  ];

  void _getRecommendation() {
    double score = (handRank / 8.0) * 0.6 + ((6 - position) / 6.0) * 0.3 + 0.1;
    
    // ICM Anpassung
    if (stackSize < 20) score -= 0.2;
    if (stackSize > 100) score += 0.1;
    
    // Board Danger
    if (street > 0) {
      boardTexture = ['dry', 'wet', 'paired'][street % 3];
      boardDanger = street * 2 + 3;
      if (boardDanger > 7) score -= 0.15;
    }
    
    // Bluff Erkennung (GTO)
    isBluff = handRank <= 2 && Random().nextDouble() < 0.25;
    
    setState(() {
      if (toCall > stackSize * 0.4) {
        recommendation = 'FOLD';
        reason = 'Zu teuer';
      } else if (score > 0.75) {
        recommendation = stackSize < 30 ? 'ALL-IN' : 'RAISE';
        reason = isBluff ? '🤖 GTO Bluff' : '🤖 Starke Hand';
      } else if (score > 0.5) {
        recommendation = toCall > pot * 0.3 ? 'FOLD' : 'CALL';
        reason = '🤖 Value';
      } else if (score > 0.3) {
        recommendation = toCall < pot * 0.15 ? 'CALL' : 'CHECK';
        reason = '🤖 Optional';
      } else {
        recommendation = 'CHECK';
        reason = '🤖 Schwach';
      }
    });
    
    // TTS
    if (ttsEnabled && recommendation.isNotEmpty) {
      _speak(recommendation);
    }
  }

  void _speak(String text) {
    // Placeholder für TTS - in echt: flutter_tts package
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🃏 ', style: TextStyle(fontSize: 24)),
            Text(AppConfig.appName, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(ttsEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => ttsEnabled = !ttsEnabled),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Empfehlung
            if (recommendation.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: recommendation == 'ALL-IN' 
                      ? [Colors.red, Colors.red.shade700]
                      : [AppConfig.primaryColor, AppConfig.primaryColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppConfig.primaryColor.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(AppConfig.t('recommendation').toUpperCase(),
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    Text(recommendation,
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isBluff) const Text('🎭 ', style: TextStyle(fontSize: 20)),
                        Text(reason,
                          style: const TextStyle(fontSize: 14, color: Colors.black87)),
                      ],
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Quick Actions
            if (recommendation.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQuickAction('FOLD', Colors.red),
                  _buildQuickAction('CALL', Colors.orange),
                  _buildQuickAction('RAISE', AppConfig.primaryColor),
                ],
              ),
            
            const SizedBox(height: 16),
            
            // Sliders & Dropdowns
            _buildDropdown('Position', position, positions, (v) => setState(() => position = v)),
            _buildDropdown('Street', street, streets, (v) => setState(() => street = v)),
            _buildDropdown('Hand', handRank, handNames, (v) => setState(() => handRank = v)),
            _buildSlider('Pot', pot, 500, (v) => setState(() => pot = v)),
            _buildSlider('Zu zahlen', toCall, 200, (v) => setState(() => toCall = v)),
            _buildSlider('Stack', stackSize, 500, (v) => setState(() => stackSize = v)),
            
            const SizedBox(height: 12),
            
            // Board Info
            if (street > 0)
              _buildBoardInfo(),
            
            const SizedBox(height: 20),
            
            // Button
            ElevatedButton(
              onPressed: _getRecommendation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('🎯 ${AppConfig.t('recommendation').toUpperCase()}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            
            const SizedBox(height: 12),
            
            // ML Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConfig.panelColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.psychology, color: AppConfig.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  const Text('ML: ', style: TextStyle(color: Colors.grey)),
                  Text('86.9%', style: const TextStyle(color: AppConfig.primaryColor, fontWeight: FontWeight.bold)),
                  const Text(' | 100k Hände', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(String action, Color color) {
    return ElevatedButton(
      onPressed: () => setState(() => recommendation = action),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        side: BorderSide(color: color),
      ),
      child: Text(action),
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
              decoration: BoxDecoration(
                color: AppConfig.panelColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<int>(
                value: value,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: AppConfig.panelColor,
                items: List.generate(items.length, (i) =>
                  DropdownMenuItem(value: i, child: Text(items[i]))),
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
        Text('$label: \$${value.toStringAsFixed(0)}',
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
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

  Widget _buildBoardInfo() {
    Color dangerColor = boardDanger > 6 ? Colors.red : (boardDanger > 3 ? Colors.orange : AppConfig.primaryColor);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoChip('Board', boardTexture.toUpperCase(), AppConfig.primaryColor),
          _buildInfoChip('Danger', '$boardDanger/10', dangerColor),
          _buildInfoChip('Bluff', isBluff ? 'YES 🎭' : 'No', isBluff ? Colors.purple : Colors.grey),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ===================== KAMERA-SEITE =====================

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  bool cameraActive = false;
  String detectedCards = 'Keine';
  String tableCards = '';
  
  // Simulierte Kartenerkennung
  final List<String> demoCards = ['A♠', 'K♥', 'Q♣', 'J♦', '10♠', '7♥', '2♣'];
  final List<String> demoTable = ['K♠', 'Q♥', '7♦'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📷 ${AppConfig.t("camera")}'),
        actions: [
          IconButton(
            icon: Icon(cameraActive ? Icons.stop : Icons.play_arrow),
            onPressed: () => setState(() => cameraActive = !cameraActive),
          ),
        ],
      ),
      body: Column(
        children: [
          // Kamera Vorschau (Placeholder)
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cameraActive ? AppConfig.primaryColor : Colors.grey,
                  width: 2,
                ),
              ),
              child: Center(
                child: cameraActive
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt, size: 64, color: AppConfig.primaryColor),
                        const SizedBox(height: 16),
                        const Text('Kamera aktiv',
                          style: TextStyle(color: AppConfig.primaryColor)),
                        const SizedBox(height: 8),
                        const Text('Karten werden erkannt...',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 16),
                        // Demo Erkennung
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppConfig.panelColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: demoCards.take(2).map((c) => 
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(c, style: const TextStyle(fontSize: 24)),
                              ),
                            ).toList(),
                          ),
                        ),
                      ],
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Kamera aus',
                          style: TextStyle(color: Colors.grey)),
                        Text('Tippe auf Play zum Starten',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
              ),
            ),
          ),
          
          // Erkannte Karten
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text('DEINE HAND',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: demoCards.take(2).map((c) => 
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(c, style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black,
                      )),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 16),
                const Text('TISCH',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: demoTable.map((c) => 
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(c, style: const TextStyle(fontSize: 18, color: Colors.black)),
                    ),
                  ).toList(),
                ),
              ],
            ),
          ),
          
          // Empfehlung
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppConfig.primaryColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🤖 Empfehlung: ', style: TextStyle(fontSize: 16)),
                Text('RAISE 3x',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: AppConfig.primaryColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== TURNIER-SEITE =====================

class TournamentPage extends StatelessWidget {
  const TournamentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🏆 ${AppConfig.t("tournament")}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ICM Status
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade800, Colors.purple.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('ICM STATUS',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                const Text('Normal',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Kein Bubble',
                  style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Szenarien
          const Text('TURNIER SZENARIEN',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          
          _buildScenario(50, 'Push/Fold', '10-15 BB', Colors.red),
          _buildScenario(100, 'Open Raise', '15-20 BB', Colors.orange),
          _buildScenario(200, 'Standard', '20+ BB', AppConfig.primaryColor),
          _buildScenario(500, 'Deep Stack', '50+ BB', Colors.blue),
          
          const SizedBox(height: 16),
          
          // Bubble Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Bubble Tipps', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTip('🔒', 'Tighter Open-Raises'),
                _buildTip('💰', 'Mehr Value-Bets'),
                _buildTip('🎯', 'Weniger Bluffs'),
                _buildTip('🛡️', 'Premium Hände spielen'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Payout Structure
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PAYOUT STRUKTUR',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                _buildPayout('1.', '50%', Colors.amber),
                _buildPayout('2.', '25%', Colors.grey.shade400),
                _buildPayout('3.', '15%', Colors.brown.shade300),
                _buildPayout('4.', '10%', Colors.grey.shade600),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScenario(int bbs, String action, String range, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: Text('$bbs BB', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(range, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: color, size: 16),
        ],
      ),
    );
  }

  Widget _buildTip(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(emoji),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildPayout(String place, String percent, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(place, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          Text(percent, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

// ===================== STATS-SEITE =====================

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('📊 ${AppConfig.t("stats")}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Gesamt Stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppConfig.primaryColor.withOpacity(0.8), AppConfig.primaryColor.withOpacity(0.4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('GESAMT PERFORMANCE',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 8),
                const Text('0',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.black)),
                const Text('Hände gespielt',
                  style: TextStyle(color: Colors.black87)),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Quick Stats
          Row(
            children: [
              Expanded(child: _buildStatCard('Win-Rate', '0%', Colors.grey)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('Avg Profit', '\$0', Colors.grey)),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Gegner Tracking
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people, color: AppConfig.primaryColor),
                    const SizedBox(width: 8),
                    const Text('GEGNER TRACKING',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Keine Gegner getrackt',
                  style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Gegner hinzufügen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor.withOpacity(0.2),
                    foregroundColor: AppConfig.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Hand History
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history, color: AppConfig.primaryColor),
                    const SizedBox(width: 8),
                    const Text('HAND HISTORY',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Importiere deine Hände',
                  style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Importieren'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor.withOpacity(0.2),
                    foregroundColor: AppConfig.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Beste Hände
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BESTE AKTIONEN',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                _buildActionStat('Raise', 0, 0),
                _buildActionStat('Call', 0, 0),
                _buildActionStat('Fold', 0, 0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActionStat(String action, int count, double winRate) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(action, style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: LinearProgressIndicator(
              value: winRate / 100,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation(AppConfig.primaryColor),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ===================== EINSTELLUNGEN-SEITE =====================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool ttsEnabled = true;
  bool hapticEnabled = true;
  bool autoRecord = false;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('⚙️ ${AppConfig.t("settings")}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // App Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text('🃏', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text(AppConfig.appName,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Version ${AppConfig.version}',
                  style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('ML Genauigkeit: 86.9%',
                  style: TextStyle(color: AppConfig.primaryColor)),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sprache
          _buildSection('SPRACHE', [
            _buildLangOption('DE', 'Deutsch', true),
            _buildLangOption('EN', 'English', false),
          ]),
          
          // Audio
          _buildSection('AUDIO & FEEDBACK', [
            _buildSwitch('Sprachausgabe (TTS)', ttsEnabled, (v) => setState(() => ttsEnabled = v)),
            _buildSwitch('Haptic Feedback', hapticEnabled, (v) => setState(() => hapticEnabled = v)),
          ]),
          
          // Recording
          _buildSection('AUFNAHME', [
            _buildSwitch('Auto-Record Hände', autoRecord, (v) => setState(() => autoRecord = v)),
          ]),
          
          // ML
          _buildSection('MACHINE LEARNING', [
            _buildInfo('Trainingsdaten', '100.000 Hände'),
            _buildInfo('Modell', 'Gradient Boosting'),
            _buildInfo('Genauigkeit', '86.9%'),
            _buildButton('Neu Trainieren', () {}),
          ]),
          
          // Data
          _buildSection('DATEN', [
            _buildButton('Exportieren', () {}),
            _buildButton('Importieren', () {}),
            _buildButton('Reset', () {}, isDestructive: true),
          ]),
          
          // About
          _buildSection('ÜBER', [
            _buildLink('Datenschutz', () {}),
            _buildLink('Nutzungsbedingungen', () {}),
            _buildLink('Version', () {}),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppConfig.panelColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildLangOption(String code, String name, bool selected) {
    return ListTile(
      title: Text(name),
      trailing: selected 
        ? const Icon(Icons.check, color: AppConfig.primaryColor)
        : null,
      onTap: () => setState(() => AppConfig.currentLang = code),
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      activeColor: AppConfig.primaryColor,
    );
  }

  Widget _buildInfo(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      trailing: Text(value, style: const TextStyle(color: AppConfig.primaryColor)),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed, {bool isDestructive = false}) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: isDestructive ? Colors.red : Colors.white),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onPressed,
    );
  }

  Widget _buildLink(String label, VoidCallback onPressed) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onPressed,
    );
  }
}
