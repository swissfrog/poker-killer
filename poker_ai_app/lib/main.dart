import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

// ===================== KARTENKILLER ML ENGINE =====================

class KartenKillerEngine {
  // Position effects (from poker theory)
  static final Map<String, Map<String, double>> POSITION_EFFECTS = {
    'BB': {'open_raise': 0.15, 'defend': 0.85, 'steal': 0.05},
    'SB': {'open_raise': 0.20, 'defend': 0.70, 'steal': 0.10},
    'UTG': {'open_raise': 0.15, 'defend': 0.60, 'steal': 0.05},
    'MP': {'open_raise': 0.20, 'defend': 0.55, 'steal': 0.10},
    'CO': {'open_raise': 0.30, 'defend': 0.50, 'steal': 0.25},
    'BTN': {'open_raise': 0.40, 'defend': 0.45, 'steal': 0.40},
  };

  // GTO Bluff ratios
  static final Map<String, Map<String, double>> GTO_RATIOS = {
    'river': {'bluff': 0.30, 'value': 0.70},
    'turn': {'bluff': 0.25, 'value': 0.75},
    'flop': {'bluff': 0.35, 'value': 0.65},
  };

  static Map<String, dynamic> getRecommendation({
    required int position,
    required int street,
    required int handRank,
    required double pot,
    required double toCall,
    required double stackSize,
    double icmFactor = 1.0,
    double bbSize = 1.0,
  }) {
    final positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
    final streets = ['preflop', 'flop', 'turn', 'river'];
    
    String posName = positions[position];
    String streetName = streets[street];
    Map<String, double> posEffects = POSITION_EFFECTS[posName]!;
    
    // Calculate base equity
    double handStrength = handRank / 8.0;
    double positionAdvantage = (6 - position) / 6.0;
    
    // ICM adjustment
    double icmPenalty = 0.0;
    if (icmFactor > 1.5) {
      // Bubble - play tighter
      icmPenalty = 0.15;
    }
    
    // Stack pressure
    double stackPressure = 0.0;
    if (stackSize < 20) {
      stackPressure = -0.25; // Short stack
    } else if (stackSize < 50) {
      stackPressure = -0.1;
    } else if (stackSize > 150) {
      stackPressure = 0.1; // Deep stack
    }
    
    // Calculate overall score
    double score = (handStrength * 0.45) + 
                   (positionAdvantage * 0.25) + 
                   stackPressure - 
                   icmPenalty +
                   0.1;
    
    // Board texture effect (if postflop)
    double boardPenalty = 0.0;
    if (street > 0) {
      // Wet boards (dangerous) reduce value
      if (street == 1) boardPenalty = -0.05; // Flop
      if (street == 2) boardPenalty = -0.08; // Turn
      if (street == 3) boardPenalty = -0.10; // River
    }
    score += boardPenalty;
    
    // Pot odds consideration
    double potOdds = (toCall > 0 && pot > 0) ? toCall / (pot + toCall) : 0;
    bool potOddsGood = potOdds < handStrength;
    
    // GTO Bluff calculation
    bool canBluff = handRank <= 2;
    bool shouldBluff = false;
    if (canBluff && street > 0) {
      double bluffProb = GTO_RATIOS[streetName]!['bluff']!;
      shouldBluff = Random().nextDouble() < bluffProb;
    }
    
    // Determine action
    String action = 'CHECK';
    String reason = 'Abwarten';
    
    // Too expensive to continue
    if (toCall > stackSize * 0.5) {
      action = 'FOLD';
      reason = 'Zu teuer';
    }
    // All-in or major decisions
    else if (toCall > stackSize * 0.3) {
      if (handStrength > 0.6 && potOddsGood) {
        action = stackSize < 40 ? 'ALL-IN' : 'RAISE';
        reason = 'Stark mit Odds';
      } else if (handStrength < 0.3) {
        action = 'FOLD';
        reason = 'Zu schwach';
      } else {
        action = potOddsGood ? 'CALL' : 'FOLD';
        reason = potOddsGood ? 'Odds stimmen' : 'Zu teuer';
      }
    }
    // Normal decisions
    else {
      if (score > 0.75) {
        action = stackSize < 50 ? 'ALL-IN' : 'RAISE';
        if (shouldBluff) {
          reason = '🤖 GTO Bluff';
        } else {
          reason = '🤖 Sehr stark';
        }
      } else if (score > 0.55) {
        action = 'RAISE';
        reason = '🤖 Wertraise';
      } else if (score > 0.40) {
        if (potOddsGood) {
          action = 'CALL';
          reason = '🤖 Profitable';
        } else {
          action = 'CHECK';
          reason = '🤖 Check behind';
        }
      } else if (score > 0.25) {
        if (toCall < pot * 0.15) {
          action = 'CALL';
          reason = '🤖 Billig';
        } else {
          action = 'CHECK';
          reason = '🤖 Zu teuer für value';
        }
      } else {
        action = toCall == 0 ? 'CHECK' : 'FOLD';
        reason = score > 0.15 ? '🤖 Marginal' : '🤖 Schwach';
      }
    }
    
    // Position adjustments
    if (position >= 4 && action == 'CALL') {
      // Button/CO can raise sometimes
      if (Random().nextDouble() < posEffects['steal']!) {
        action = 'RAISE';
        reason = '🤖 Position steal';
      }
    }
    if (position <= 1 && action == 'RAISE') {
      // Early position - be more careful
      if (handStrength < 0.5) {
        action = 'CALL';
        reason = '🤖 Aus Position';
      }
    }
    
    // Street and board info
    String boardTexture = 'unknown';
    int boardDanger = 0;
    if (street > 0) {
      boardDanger = street * 2 + 3;
      if (street % 3 == 0) boardTexture = 'dry';
      else if (street % 3 == 1) boardTexture = 'wet';
      else boardTexture = 'paired';
    }
    
    return {
      'action': action,
      'reason': reason,
      'score': score,
      'boardTexture': boardTexture,
      'boardDanger': boardDanger,
      'isBluff': shouldBluff,
      'equity': handStrength,
      'potOdds': potOdds,
    };
  }
  
  // ICM for tournaments
  static String getICMDecision(double stack, double bb, {double icmFactor = 1.0}) {
    double bbs = stack / bb;
    
    if (bbs < 10) {
      return 'push_or_fold';
    } else if (bbs < 20) {
      return 'consider_push';
    } else if (bbs < 35) {
      // Bubble factor
      if (icmFactor > 1.5) {
        return 'open_minraise';
      }
      return 'open_raise';
    }
    return 'standard';
  }
}

// ===================== FLUTTER APP =====================

void main() {
  runApp(const PokerKillerApp());
}

class AppConfig {
  static const String appName = 'KartenKiller';
  static const String version = '1.0.0';
  static const Color primaryColor = Color(0xFF00ff88);
  static const Color bgColor = Color(0xFF1a1a2e);
  static const Color panelColor = Color(0xFF16213e);
  
  static String currentLang = 'DE';
  
  static final Map<String, Map<String, String>> translations = {
    'DE': {
      'recommendation': 'Empfehlung', 'training': 'Training', 'stats': 'Statistiken',
      'camera': 'Kamera', 'settings': 'Einstellungen',
      'fold': 'Fold', 'check': 'Check', 'call': 'Call', 'bet': 'Bet', 'raise': 'Raise', 'allin': 'All-In',
      'position': 'Position', 'street': 'Street', 'hand': 'Hand', 'pot': 'Pot', 'stack': 'Stack',
      'board': 'Board', 'danger': 'Danger', 'equity': 'Equity', 'potOdds': 'Pot Odds',
    },
    'EN': {
      'recommendation': 'Recommendation', 'training': 'Training', 'stats': 'Statistics',
      'camera': 'Camera', 'settings': 'Settings',
      'fold': 'Fold', 'check': 'Check', 'call': 'Call', 'bet': 'Bet', 'raise': 'Raise', 'allin': 'All-In',
      'position': 'Position', 'street': 'Street', 'hand': 'Hand', 'pot': 'Pot', 'stack': 'Stack',
      'board': 'Board', 'danger': 'Danger', 'equity': 'Equity', 'potOdds': 'Pot Odds',
    },
  };
  
  static String t(String key) => translations[currentLang]?[key] ?? key;
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
        selectedItemColor: AppConfig.primaryColor,
        unselectedItemColor: Colors.grey,
        backgroundColor: AppConfig.panelColor,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.poker_chip), label: AppConfig.t('recommendation')),
          BottomNavigationBarItem(icon: const Icon(Icons.camera_alt), label: AppConfig.t('camera')),
          BottomNavigationBarItem(icon: const Icon(Icons.emoji_events), label: AppConfig.t('training')),
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
  double equity = 0;
  double potOdds = 0;
  bool isBluff = false;
  bool ttsEnabled = true;
  double score = 0;

  final List<String> positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
  final List<String> streets = ['Preflop', 'Flop', 'Turn', 'River'];
  final List<String> handNames = [
    'High Card', 'Pair', 'Two Pair', 'Three of Kind',
    'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
  ];

  void _getRecommendation() {
    // Use the ML Engine
    Map<String, dynamic> result = KartenKillerEngine.getRecommendation(
      position: position,
      street: street,
      handRank: handRank,
      pot: pot,
      toCall: toCall,
      stackSize: stackSize,
    );
    
    setState(() {
      recommendation = result['action'];
      reason = result['reason'];
      boardTexture = result['boardTexture'];
      boardDanger = result['boardDanger'];
      isBluff = result['isBluff'];
      equity = result['equity'];
      potOdds = result['potOdds'];
      score = result['score'];
    });
    
    if (ttsEnabled) {
      HapticFeedback.mediumImpact();
    }
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
            if (recommendation.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: recommendation == 'ALL-IN' 
                      ? [Colors.red, Colors.red.shade700]
                      : recommendation == 'FOLD'
                        ? [Colors.orange.shade700, Colors.orange.shade900]
                        : [AppConfig.primaryColor, AppConfig.primaryColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                        Flexible(child: Text(reason,
                          style: const TextStyle(fontSize: 14, color: Colors.black87), textAlign: TextAlign.center)),
                      ],
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Stats display
            if (recommendation.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConfig.panelColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatChip('Equity', '${(equity * 100).toStringAsFixed(0)}%', 
                      equity > 0.5 ? AppConfig.primaryColor : Colors.orange),
                    _buildStatChip('Odds', '${(potOdds * 100).toStringAsFixed(0)}%', Colors.blue),
                    _buildStatChip('Score', score.toStringAsFixed(2), 
                      score > 0.5 ? AppConfig.primaryColor : Colors.grey),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Input controls
            _buildDropdown('Position', position, positions, (v) => setState(() => position = v));
            _buildDropdown('Street', street, streets, (v) => setState(() => street = v));
            _buildDropdown('Hand', handRank, handNames, (v) => setState(() => handRank = v));
            _buildSlider('Pot', pot, 500, (v) => setState(() => pot = v));
            _buildSlider('Zu zahlen', toCall, 200, (v) => setState(() => toCall = v));
            _buildSlider('Stack', stackSize, 500, (v) => setState(() => stackSize = v)),
            
            const SizedBox(height: 12),
            
            if (street > 0) _buildBoardInfo(),
            
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _getRecommendation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConfig.primaryColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('🎯 EMPFEHLUNG',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            
            const SizedBox(height: 12),
            
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
                  Text('KartenKiller Engine', style: const TextStyle(color: AppConfig.primaryColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
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

  Widget _buildBoardInfo() {
    Color dangerColor = boardDanger > 6 ? Colors.red : (boardDanger > 3 ? Colors.orange : AppConfig.primaryColor);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(8)),
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

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('📷 ${AppConfig.t("camera")}')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 200, height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppConfig.primaryColor, width: 2),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 64, color: AppConfig.primaryColor),
                    SizedBox(height: 16),
                    Text('Kamera', style: TextStyle(color: Colors.white)),
                    Text('Demo Mode', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Deine Hand: A♠ K♥', style: TextStyle(fontSize: 24, color: AppConfig.primaryColor)),
            const Text('Tisch: K♠ Q♥ 7♦', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppConfig.primaryColor),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🤖 Empfehlung: ', style: TextStyle(fontSize: 16)),
                  Text('RAISE 3x', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppConfig.primaryColor)),
                ],
              ),
            ),
          ],
        ),
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
      appBar: AppBar(title: Text('🏆 ${AppConfig.t("training")}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.purple.shade800, Colors.purple.shade600]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Text('ICM STATUS', style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 8),
                Text('Normal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Kein Bubble', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('TURNIER SZENARIEN', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          _buildScenario(10, 'Push/Fold', '<10 BB', Colors.red),
          _buildScenario(20, 'Min-Raise', '10-20 BB', Colors.orange),
          _buildScenario(50, 'Open Raise', '20-50 BB', AppConfig.primaryColor),
          _buildScenario(100, 'Standard', '50+ BB', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildScenario(int bbs, String action, String range, Color color) {
    String icmDecision = KartenKillerEngine.getICMDecision(bbs.toDouble(), 1.0);
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
                Text('$range → $icmDecision', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
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
      appBar: AppBar(title: Text('📊 ${AppConfig.t("stats")}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppConfig.primaryColor.withOpacity(0.8), AppConfig.primaryColor.withOpacity(0.4)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Text('GESAMT PERFORMANCE', style: TextStyle(color: Colors.black54, fontSize: 12)),
                SizedBox(height: 8),
                Text('0', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.black)),
                Text('Hände gespielt', style: TextStyle(color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('Win-Rate', '0%', Colors.grey)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('Avg Profit', '\$0', Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('⚙️ ${AppConfig.t("settings")}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                const Text('🃏', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text(AppConfig.appName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Version ${AppConfig.version}', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('ML Engine: KartenKiller', style: TextStyle(color: AppConfig.primaryColor)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection('SPRACHE', [
            ListTile(
              title: const Text('Deutsch'),
              trailing: AppConfig.currentLang == 'DE' ? const Icon(Icons.check, color: AppConfig.primaryColor) : null,
              onTap: () => setState(() => AppConfig.currentLang = 'DE'),
            ),
            ListTile(
              title: const Text('English'),
              trailing: AppConfig.currentLang == 'EN' ? const Icon(Icons.check, color: AppConfig.primaryColor) : null,
              onTap: () => setState(() => AppConfig.currentLang = 'EN'),
            ),
          ]),
          _buildSection('AUDIO', [
            SwitchListTile(
              title: const Text('Sprachausgabe (TTS)'),
              value: ttsEnabled,
              onChanged: (v) => setState(() => ttsEnabled = v),
              activeColor: AppConfig.primaryColor,
            ),
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
          decoration: BoxDecoration(color: AppConfig.panelColor, borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        ),
      ],
    );
  }
}
