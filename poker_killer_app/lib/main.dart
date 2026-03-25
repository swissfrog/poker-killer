import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'opponent_model.dart';
import 'pot_odds.dart';
import 'hand_history.dart';
import 'preflop_chart.dart';

void main() {
  runApp(const PokerKillerApp());
}

// ===================== APP CONFIG =====================

class AppConfig {
  static const String appName = 'KartenKiller';
  static const String version = '1.0.0';
  static const Color primaryColor = Color(0xFF00ff88);
  static const Color bgColor = Color(0xFF1a1a2e);
  static const Color panelColor = Color(0xFF1E2A3A);

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

// ===================== CARD MODEL =====================

/// Represents a single playing card (rank + suit).
class CardModel {
  final String rank; // '2'-'9', 'T', 'J', 'Q', 'K', 'A'
  final String suit; // '♠', '♥', '♦', '♣'

  const CardModel({required this.rank, required this.suit});

  String get display => '$rank$suit';

  Color get suitColor =>
      (suit == '♥' || suit == '♦') ? Colors.red : Colors.black;

  /// Numeric rank value for straight detection (2=2 … A=14)
  int get rankValue {
    const map = {
      '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7,
      '8': 8, '9': 9, 'T': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
    };
    return map[rank] ?? 2;
  }

  @override
  bool operator ==(Object other) =>
      other is CardModel && other.rank == rank && other.suit == suit;

  @override
  int get hashCode => rank.hashCode ^ suit.hashCode;
}

// ===================== BOARD TEXTURE ANALYSIS =====================

class BoardAnalysis {
  final String texture;     // 'dry', 'wet', 'paired'
  final bool flushDraw;     // 2+ same suit
  final bool straightDraw;  // 3+ consecutive ranks
  final bool paired;        // any rank appears 2+
  final int dangerScore;    // 0-10
  final String label;       // emoji + text

  const BoardAnalysis({
    required this.texture,
    required this.flushDraw,
    required this.straightDraw,
    required this.paired,
    required this.dangerScore,
    required this.label,
  });
}

BoardAnalysis analyzeBoardTexture(List<CardModel> board) {
  if (board.isEmpty) {
    return const BoardAnalysis(
      texture: 'unknown',
      flushDraw: false,
      straightDraw: false,
      paired: false,
      dangerScore: 0,
      label: '—',
    );
  }

  // Flush draw: 2+ cards of same suit
  final suitCounts = <String, int>{};
  for (final c in board) {
    suitCounts[c.suit] = (suitCounts[c.suit] ?? 0) + 1;
  }
  final flushDraw = suitCounts.values.any((v) => v >= 2);

  // Paired board: any rank appears 2+
  final rankCounts = <String, int>{};
  for (final c in board) {
    rankCounts[c.rank] = (rankCounts[c.rank] ?? 0) + 1;
  }
  final paired = rankCounts.values.any((v) => v >= 2);

  // Straight draw: 3+ ranks that span a window of ≤5 (connectedness)
  final ranks = board.map((c) => c.rankValue).toSet().toList()..sort();
  bool straightDraw = false;
  if (ranks.length >= 3) {
    for (int i = 0; i <= ranks.length - 3; i++) {
      final window = ranks.sublist(i, i + 3);
      if (window.last - window.first <= 4) {
        straightDraw = true;
        break;
      }
    }
  }

  // Texture classification
  final String texture;
  final String label;
  int danger = 0;

  if (paired) {
    texture = 'paired';
    label = '🔄 Paired Board';
    danger = 5;
  } else if (flushDraw && straightDraw) {
    texture = 'wet';
    label = '🌊 Wet Board';
    danger = 8;
  } else if (flushDraw || straightDraw) {
    texture = 'wet';
    label = '💧 Semi-Wet Board';
    danger = 5;
  } else {
    texture = 'dry';
    label = '🏜️ Dry Board';
    danger = 2;
  }

  return BoardAnalysis(
    texture: texture,
    flushDraw: flushDraw,
    straightDraw: straightDraw,
    paired: paired,
    dangerScore: danger,
    label: label,
  );
}

// ===================== HAND vs BOARD DRAW DETECTION =====================

class DrawInfo {
  final String label;
  final bool isMade;

  const DrawInfo({required this.label, required this.isMade});
}

/// Detects draws or made hands when hole cards are known against the board.
/// Returns a list of detections (empty if no hole cards or nothing notable).
List<DrawInfo> detectDraws(List<CardModel> holeCards, List<CardModel> board) {
  if (holeCards.isEmpty || board.isEmpty) return [];

  final combined = [...holeCards, ...board];
  final results = <DrawInfo>[];

  // ── Flush / Flush Draw ────────────────────────────────────────────────
  final suitMap = <String, List<CardModel>>{};
  for (final c in combined) {
    suitMap.putIfAbsent(c.suit, () => []).add(c);
  }
  for (final entry in suitMap.entries) {
    if (entry.value.length >= 5) {
      results.add(const DrawInfo(label: 'Made Hand: Flush ♦♥♠♣', isMade: true));
    } else if (entry.value.length == 4) {
      results.add(const DrawInfo(label: 'Draw Detected: Flush Draw 🎨', isMade: false));
    }
  }

  // ── Straight / Straight Draw ──────────────────────────────────────────
  final rankVals = combined.map((c) => c.rankValue).toSet().toList()..sort();
  // Include low ace (A=1)
  if (rankVals.contains(14)) rankVals.insert(0, 1);
  bool foundStraight = false;
  int consecutiveMax = 0;
  for (int i = 0; i < rankVals.length; i++) {
    int streak = 1;
    for (int j = i + 1; j < rankVals.length; j++) {
      if (rankVals[j] == rankVals[j - 1] + 1) {
        streak++;
      } else {
        break;
      }
    }
    if (streak > consecutiveMax) consecutiveMax = streak;
    if (streak >= 5 && !foundStraight) {
      foundStraight = true;
      results.add(const DrawInfo(label: 'Made Hand: Straight ✅', isMade: true));
    }
  }
  if (!foundStraight && consecutiveMax == 4) {
    results.add(const DrawInfo(label: 'Draw Detected: Open-Ended Straight Draw 📏', isMade: false));
  } else if (!foundStraight && consecutiveMax == 3) {
    results.add(const DrawInfo(label: 'Draw Detected: Gutshot 🎯', isMade: false));
  }

  // ── Pairs, Trips, Full House ──────────────────────────────────────────
  final rankCount = <String, int>{};
  for (final c in combined) {
    rankCount[c.rank] = (rankCount[c.rank] ?? 0) + 1;
  }
  final pairs = rankCount.values.where((v) => v == 2).length;
  final trips = rankCount.values.where((v) => v == 3).length;
  final quads = rankCount.values.where((v) => v >= 4).length;

  if (quads > 0) {
    results.add(const DrawInfo(label: 'Made Hand: Four of a Kind 🎰', isMade: true));
  } else if (trips > 0 && pairs > 0) {
    results.add(const DrawInfo(label: 'Made Hand: Full House 🏠', isMade: true));
  } else if (trips > 0) {
    results.add(const DrawInfo(label: 'Made Hand: Three of a Kind ✅', isMade: true));
  } else if (pairs >= 2) {
    results.add(const DrawInfo(label: 'Made Hand: Two Pair ✅', isMade: true));
  } else if (pairs == 1) {
    // Check if the pair is from hole cards (pocket pair) and board is paired → Full House draw
    final holeRanks = holeCards.map((c) => c.rank).toList();
    final boardRankCount = <String, int>{};
    for (final c in board) {
      boardRankCount[c.rank] = (boardRankCount[c.rank] ?? 0) + 1;
    }
    final boardPaired = boardRankCount.values.any((v) => v >= 2);
    final holePaired = holeRanks.length == 2 && holeRanks[0] == holeRanks[1];
    if (holePaired && boardPaired) {
      results.add(const DrawInfo(
          label: 'Draw Detected: Full House Draw (Pocket Pair + Paired Board) 🏠', isMade: false));
    } else {
      results.add(const DrawInfo(label: 'Made Hand: One Pair ✅', isMade: true));
    }
  }

  return results;
}

// ===================== COMMUNITY CARDS WIDGET =====================

class CommunityCardsWidget extends StatefulWidget {
  final List<CardModel> cards;
  final int street; // 0=Preflop, 1=Flop, 2=Turn, 3=River
  final ValueChanged<List<CardModel>> onChanged;

  const CommunityCardsWidget({
    super.key,
    required this.cards,
    required this.street,
    required this.onChanged,
  });

  @override
  State<CommunityCardsWidget> createState() => _CommunityCardsWidgetState();
}

class _CommunityCardsWidgetState extends State<CommunityCardsWidget> {
  static const List<String> ranks = [
    '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'
  ];
  static const List<String> suits = ['♠', '♥', '♦', '♣'];

  /// Max cards allowed per street
  int get _maxCards {
    switch (widget.street) {
      case 1: return 3; // Flop
      case 2: return 4; // Turn
      case 3: return 5; // River
      default: return 0; // Preflop → no board
    }
  }

  void _addCard() async {
    if (widget.cards.length >= _maxCards) return;
    final card = await showModalBottomSheet<CardModel>(
      context: context,
      backgroundColor: AppConfig.panelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CardPickerSheet(
        existingCards: widget.cards,
        ranks: ranks,
        suits: suits,
      ),
    );
    if (card != null) {
      widget.onChanged([...widget.cards, card]);
    }
  }

  void _removeCard(int index) {
    final updated = List<CardModel>.from(widget.cards)..removeAt(index);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.street == 0) return const SizedBox.shrink();

    final streetLabel = ['', 'Flop', 'Turn', 'River'][widget.street];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🃏 ', style: TextStyle(fontSize: 16)),
              Text(
                'Community Cards — $streetLabel',
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12, letterSpacing: 0.5),
              ),
              const Spacer(),
              if (widget.cards.isNotEmpty)
                GestureDetector(
                  onTap: () => widget.onChanged([]),
                  child: const Text('Reset',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Existing cards as chips
              ...widget.cards.asMap().entries.map((entry) {
                final i = entry.key;
                final card = entry.value;
                return GestureDetector(
                  onLongPress: () => _removeCard(i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      card.display,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: card.suitColor,
                      ),
                    ),
                  ),
                );
              }),
              // Add button (only if slots remain)
              if (widget.cards.length < _maxCards)
                GestureDetector(
                  onTap: _addCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppConfig.primaryColor.withOpacity(0.6),
                          style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+ Karte (${widget.cards.length}/$_maxCards)',
                      style: const TextStyle(
                          color: AppConfig.primaryColor, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Long-press to remove a card',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _CardPickerSheet extends StatefulWidget {
  final List<CardModel> existingCards;
  final List<String> ranks;
  final List<String> suits;

  const _CardPickerSheet({
    required this.existingCards,
    required this.ranks,
    required this.suits,
  });

  @override
  State<_CardPickerSheet> createState() => _CardPickerSheetState();
}

class _CardPickerSheetState extends State<_CardPickerSheet> {
  String _selectedRank = 'A';
  String _selectedSuit = '♠';

  bool get _isDuplicate => widget.existingCards
      .any((c) => c.rank == _selectedRank && c.suit == _selectedSuit);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Karte auswählen',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          // Rank picker
          const Text('Rang', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: widget.ranks.map((r) {
              final sel = r == _selectedRank;
              return GestureDetector(
                onTap: () => setState(() => _selectedRank = r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppConfig.primaryColor
                        : AppConfig.bgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: sel
                            ? AppConfig.primaryColor
                            : Colors.grey.shade700),
                  ),
                  child: Text(r,
                      style: TextStyle(
                          color: sel ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Suit picker
          const Text('Farbe', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: widget.suits.map((s) {
              final sel = s == _selectedSuit;
              final suitColor = (s == '♥' || s == '♦') ? Colors.red : Colors.white;
              return GestureDetector(
                onTap: () => setState(() => _selectedSuit = s),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: sel ? suitColor.withOpacity(0.15) : AppConfig.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel ? suitColor : Colors.grey.shade700,
                        width: sel ? 2 : 1),
                  ),
                  child: Text(s,
                      style: TextStyle(
                          fontSize: 26,
                          color: suitColor,
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_selectedRank$_selectedSuit',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: (_selectedSuit == '♥' || _selectedSuit == '♦')
                    ? Colors.red
                    : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isDuplicate)
            const Text('⚠️ Diese Karte wurde bereits gewählt',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isDuplicate
                      ? null
                      : () => Navigator.pop(
                          context,
                          CardModel(
                              rank: _selectedRank, suit: _selectedSuit)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Hinzufügen'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ===================== HOLE CARDS PICKER WIDGET =====================

class HoleCardsWidget extends StatefulWidget {
  final List<CardModel> cards;
  final ValueChanged<List<CardModel>> onChanged;

  const HoleCardsWidget({
    super.key,
    required this.cards,
    required this.onChanged,
  });

  @override
  State<HoleCardsWidget> createState() => _HoleCardsWidgetState();
}

class _HoleCardsWidgetState extends State<HoleCardsWidget> {
  static const List<String> ranks = [
    '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'
  ];
  static const List<String> suits = ['♠', '♥', '♦', '♣'];

  void _addCard() async {
    if (widget.cards.length >= 2) return;
    final card = await showModalBottomSheet<CardModel>(
      context: context,
      backgroundColor: AppConfig.panelColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CardPickerSheet(
        existingCards: widget.cards,
        ranks: ranks,
        suits: suits,
      ),
    );
    if (card != null) {
      widget.onChanged([...widget.cards, card]);
    }
  }

  void _removeCard(int index) {
    final updated = List<CardModel>.from(widget.cards)..removeAt(index);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤚 ', style: TextStyle(fontSize: 16)),
              const Text('Meine Handkarten (optional)',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const Spacer(),
              if (widget.cards.isNotEmpty)
                GestureDetector(
                  onTap: () => widget.onChanged([]),
                  child: const Text('Reset',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ...widget.cards.asMap().entries.map((entry) {
                final card = entry.value;
                return GestureDetector(
                  onLongPress: () => _removeCard(entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      card.display,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: card.suitColor,
                      ),
                    ),
                  ),
                );
              }),
              if (widget.cards.length < 2)
                GestureDetector(
                  onTap: _addCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.blue.shade400.withOpacity(0.6)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+ Karte (${widget.cards.length}/2)',
                      style: TextStyle(
                          color: Colors.blue.shade300, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Long-press to remove',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 10)),
        ],
      ),
    );
  }
}

// ===================== NASH PUSH/FOLD RESULT =====================

class _NashResult {
  final String action;
  final String reason;
  const _NashResult({required this.action, required this.reason});
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

  // Community Cards (board)
  List<CardModel> communityCards = [];

  // Hole Cards (optional, for draw detection)
  List<CardModel> holeCards = [];

  // Opponent Modeling
  double _vpip = 25;
  double _pfr  = 18;

  // Last Hand (Feature 6)
  int? _lastPosition; int? _lastStreet; int? _lastHandRank;
  double? _lastPot; double? _lastToCall; double? _lastStackSize;

  // Bet Size Button selection (Feature 7)
  int _selectedBetBtn = -1;

  String recommendation = '';
  String reason = '';
  BoardAnalysis _boardAnalysis = const BoardAnalysis(
    texture: 'unknown',
    flushDraw: false,
    straightDraw: false,
    paired: false,
    dangerScore: 0,
    label: '—',
  );
  List<DrawInfo> _draws = [];
  bool isBluff = false;
  bool ttsEnabled = true;

  // Action-Wahrscheinlichkeiten (0.0–1.0)
  double _foldPct = 0;
  double _callPct = 0;
  double _raisePct = 0;
  // Bet-Sizing
  String _betDisplay = '';
  String _betReason = '';

  final List<String> positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
  final List<String> streets = ['Preflop', 'Flop', 'Turn', 'River'];
  final List<String> handNames = [
    'High Card', 'Pair', 'Two Pair', 'Three of Kind',
    'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
  ];

  // ── Stack-Awareness Helper ──────────────────────────────────────────────
  String _positionHint(int pos, double stackBb) {
    const posNames = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
    final posStr = pos < posNames.length ? posNames[pos] : 'MP';
    String stackLabel;
    if (stackBb < 20) {
      stackLabel = '🔴 ${stackBb.toStringAsFixed(1)}bb (Short)';
    } else if (stackBb <= 50) {
      stackLabel = '🟡 ${stackBb.toStringAsFixed(1)}bb (Mid)';
    } else {
      stackLabel = '🟢 ${stackBb.toStringAsFixed(1)}bb (Deep)';
    }
    return '$posStr | $stackLabel';
  }

  static const double _bigBlindSize = 2.0;

  _NashResult? _nashPushFoldCheck(double stackBb, int rank) {
    if (street != 0) return null;

    if (stackBb < 8) {
      if (rank >= 1) {
        return _NashResult(action: 'ALL-IN', reason: '🎯 Nash Push <8bb: ${_rankName(rank)} → Push!');
      }
      return _NashResult(action: 'ALL-IN', reason: '🎯 Nash Push <8bb: Breiteste Range → Push!');
    } else if (stackBb < 13) {
      if (rank >= 1) {
        return _NashResult(action: 'ALL-IN', reason: '🎯 Nash Push 8-13bb: ${_rankName(rank)} → Push!');
      }
      if (toCall > 0 && rank < 3) {
        return _NashResult(action: 'FOLD', reason: '🎯 Nash Fold vs Push: Brauchst Top 15% zum Callen');
      }
      return null;
    } else if (stackBb < 20) {
      if (rank >= 3) {
        return _NashResult(action: 'ALL-IN', reason: '🎯 Nash Push 13-20bb: ${_rankName(rank)} → Push!');
      }
      if (toCall > 0 && rank < 3) {
        return _NashResult(action: 'FOLD', reason: '🎯 Nash Fold vs Push: Brauchst Top 15% zum Callen');
      }
      return null;
    }
    return null;
  }

  String _rankName(int rank) {
    const names = [
      'High Card', 'Pair', 'Two Pair', 'Three of Kind',
      'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
    ];
    return rank < names.length ? names[rank] : 'Unknown';
  }

  void _getRecommendation() {
    final stackBb = stackSize / _bigBlindSize;

    // Opponent Modeling: Score-Modifier
    final oppMod = opponentScoreModifier(vpip: _vpip, pfr: _pfr, handScore: handRank / 8.0);

    // Position-Awareness
    final positionBonus = position <= 3 ? (3 - position) * 0.05 : 0.0;
    final positionPenalty = position >= 4 ? (position - 3) * 0.04 : 0.0;

    double score = (handRank / 8.0) * 0.6
        + ((6 - position) / 6.0) * 0.3
        + positionBonus
        - positionPenalty
        + oppMod
        + 0.1;

    // Stack-Awareness
    if (stackBb < 10) {
      score -= 0.15;
    } else if (stackBb < 20) {
      score -= 0.10;
    }

    // ── Board Texture Analysis (replaces random boardDanger) ──────────────
    final board = analyzeBoardTexture(communityCards);
    setState(() => _boardAnalysis = board);

    if (street > 0) {
      // Real board danger from analysis
      final danger = board.dangerScore;

      // Adjust score based on board texture + hand strength
      if (board.texture == 'wet') {
        if (handRank <= 2) {
          // Wet board + weak hand → fold more
          score -= 0.20;
        } else if (handRank >= 5) {
          // Wet board + strong hand → value
          score += 0.05;
        } else {
          score -= 0.08;
        }
      } else if (board.texture == 'paired') {
        // Paired board: trips/boat possible → evaluate carefully
        if (handRank >= 5) {
          score += 0.08; // Likely best hand
        } else if (handRank <= 1) {
          score -= 0.15; // Dangerous
        }
      } else {
        // Dry board: value bet more freely
        if (handRank >= 3) score += 0.05;
      }

      if (danger > 6) score -= 0.15;
    }

    // Draw detection
    final draws = detectDraws(holeCards, communityCards);
    setState(() => _draws = draws);

    // Adjust score based on detected draws
    for (final d in draws) {
      if (d.isMade) {
        score += 0.05; // Known made hand confirms strength
      } else {
        // Drawing hands get a small boost (implied odds)
        score += 0.03;
      }
    }

    // Bluff detection (GTO)
    isBluff = handRank <= 2 && stackBb > 20 && Random().nextDouble() < 0.25;

    final posHint = _positionHint(position, stackBb);

    // ── Implied Odds at Deep Stack ────────────────────────────────────────
    String impliedOddsReason = '';
    if (stackBb > 50 && (street == 0 || street == 1)) {
      final impliedBonus = (stackBb / 100) * 0.08;
      score += impliedBonus;
      impliedOddsReason = 'Deep Stack Implied Odds +';
      if (handRank >= 3 && handRank <= 5) {
        score += 0.05;
        impliedOddsReason = 'Deep Stack Implied Odds + (implied odds boost)';
      }
    }

    // ── Nash Push/Fold Check ──────────────────────────────────────────────
    final nashResult = _nashPushFoldCheck(stackBb, handRank);

    // ── Pot Odds ──────────────────────────────────────────────────────────
    String potOddsReason = '';
    String? potOddsOverride;
    if (toCall > 0 && pot + toCall > 0) {
      final handEquity = handRank / 8.0;
      final requiredEquity = toCall / (pot + toCall);
      final requiredPct = (requiredEquity * 100).toStringAsFixed(0);
      final hasPct = (handEquity * 100).toStringAsFixed(0);

      if (handEquity < requiredEquity - 0.05) {
        potOddsOverride = 'FOLD';
        potOddsReason = 'Pot Odds Override: FOLD (brauchst $requiredPct%, hast $hasPct%)';
      } else if (handEquity > requiredEquity + 0.10) {
        potOddsReason = 'Pot Odds: Call profitable ($hasPct% > $requiredPct%)';
      }
    }

    // ── Aktion bestimmen ─────────────────────────────────────────────────
    String newRec;
    String newReason;

    if (nashResult != null) {
      newRec = nashResult.action;
      newReason = nashResult.reason;
    } else if (potOddsOverride != null) {
      newRec = potOddsOverride;
      newReason = potOddsReason;
    } else if (toCall > stackSize * 0.4) {
      newRec = 'Passen';
      newReason = 'Zu teuer | $posHint';
    } else if (score > 0.75) {
      newRec = stackBb < 20 ? 'All-In' : 'Erh�hen';
      newReason = isBluff ? '🤖 GTO Bluff' : '🤖 Starke Hand | $posHint';
    } else if (score > 0.5) {
      newRec = toCall > pot * 0.3 ? 'FOLD' : 'CALL';
      newReason = '🤖 Value | $posHint';
    } else if (score > 0.3) {
      newRec = toCall < pot * 0.15 ? 'CALL' : 'CHECK';
      newReason = '🤖 Optional | $posHint';
    } else {
      newRec = 'Checken';
      newReason = '🤖 Schwach | $posHint';
    }

    // Board texture label in reason for post-flop
    if (street > 0 && communityCards.isNotEmpty) {
      newReason = '${board.label} | $newReason';
    }

    if (potOddsReason.isNotEmpty && potOddsOverride == null) {
      newReason = '$newReason | $potOddsReason';
    }
    if (impliedOddsReason.isNotEmpty) {
      newReason = '$newReason | $impliedOddsReason';
    }

    // ── GTO Wahrscheinlichkeiten ──────────────────────────────────────────
    final double rawFold  = (1.0 - score).clamp(0.0, 1.0);
    final double rawRaise = score.clamp(0.0, 1.0);
    final double rawCall  = (1.0 - (score - 0.5).abs() * 2).clamp(0.0, 1.0);
    final double total = rawFold + rawCall + rawRaise;
    final double nFold  = total > 0 ? rawFold  / total : 0.33;
    final double nCall  = total > 0 ? rawCall  / total : 0.34;
    final double nRaise = total > 0 ? rawRaise / total : 0.33;

    // ── Bet-Sizing ────────────────────────────────────────────────────────
    String betDisplay = '';
    String betReason  = '';
    if (newRec == 'RAISE' || newRec == 'ALL-IN') {
      double fraction;
      String fracLabel;
      String sizingReason;

      if (newRec == 'ALL-IN') {
        fraction = stackSize;
        fracLabel = 'All-In';
        sizingReason = 'Push/Fold Zone → All-In';
      } else if (street == 0) {
        final isPosition = position >= 2;
        fraction = isPosition ? pot * 2.5 : pot * 3.0;
        fracLabel = isPosition ? '2.5x' : '3x';
        sizingReason = isPosition ? 'Open-Raise in Position (2.5x)' : 'Open-Raise OOP (3x)';
      } else if (score > 0.80) {
        fraction = pot * 0.75;
        fracLabel = '75% Pot';
        sizingReason = 'Starke Hand → 75% für Value';
      } else if (score > 0.65) {
        fraction = pot * 0.66;
        fracLabel = '66% Pot';
        sizingReason = 'Gute Hand → 66% Pot';
      } else if (score > 0.50) {
        fraction = pot * 0.50;
        fracLabel = '50% Pot';
        sizingReason = 'Standard Bet → 50% Pot';
      } else {
        fraction = pot * 0.33;
        fracLabel = '33% Pot';
        sizingReason = 'C-Bet / Probe → 33% Pot';
      }
      final betAmt = (newRec == 'ALL-IN') ? stackSize : fraction.clamp(0.0, stackSize);
      final betBb  = betAmt / _bigBlindSize;
      betDisplay   = '\$${betAmt.toStringAsFixed(0)}  (${betBb.toStringAsFixed(1)} BB · $fracLabel)';
      betReason    = sizingReason;
    }

    // Save last hand (Feature 6)
    _lastPosition = position; _lastStreet = street; _lastHandRank = handRank;
    _lastPot = pot; _lastToCall = toCall; _lastStackSize = stackSize;

    setState(() {
      recommendation = newRec;
      reason = newReason;
      _foldPct  = nFold;
      _callPct  = nCall;
      _raisePct = nRaise;
      _betDisplay = betDisplay;
      _betReason  = betReason;
    });

    // Hand History
    final posNames = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
    final posStr = position < posNames.length ? posNames[position] : 'MP';
    HandHistoryService.addRecord(HandRecord(
      id:             DateTime.now().millisecondsSinceEpoch.toString(),
      date:           DateTime.now(),
      hand:           handNames[handRank],
      position:       posStr,
      stack:          stackSize / _bigBlindSize,
      recommendation: newRec,
    ));

    if (ttsEnabled && recommendation.isNotEmpty) {
      _speak(recommendation);
    }
  }

  // Feature 6: Restore last hand
  void _restoreLastHand() {
    if (_lastPosition == null) return;
    setState(() {
      position = _lastPosition!; street = _lastStreet!; handRank = _lastHandRank!;
      pot = _lastPot!; toCall = _lastToCall!; stackSize = _lastStackSize!;
    });
    _getRecommendation();
  }

  // Feature 7: Bet size buttons
  Widget _buildBetSizeButtons() {
    final sizes = [
      ('1/3 Pot', pot / 3),
      ('1/2 Pot', pot / 2),
      ('2/3 Pot', pot * 2 / 3),
      ('Pot', pot),
      ('All-In', stackSize),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Zu zahlen:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: sizes.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value.$1;
              final val = entry.value.$2;
              final selected = _selectedBetBtn == i;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedBetBtn = i;
                  toCall = val.clamp(0, stackSize);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppConfig.primaryColor.withOpacity(0.3) : AppConfig.panelColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? AppConfig.primaryColor : Colors.grey.shade700),
                  ),
                  child: Text(
                    '$label\n\$${val.toStringAsFixed(0)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? AppConfig.primaryColor : Colors.white70,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _speak(String text) {
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
            icon: const Icon(Icons.style),
            tooltip: 'Preflop Range Chart',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: AppConfig.panelColor,
                child: PreflopChartScreen(initialPosition: position),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Hand History',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HandHistoryScreen()),
            ),
          ),
          IconButton(
            icon: Icon(ttsEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () => setState(() => ttsEnabled = !ttsEnabled),
          ),
        ],
      ),
      floatingActionButton: _lastPosition != null
          ? FloatingActionButton.small(
              onPressed: _restoreLastHand,
              backgroundColor: AppConfig.panelColor,
              tooltip: 'Letzte Hand',
              child: const Icon(Icons.replay, color: AppConfig.primaryColor),
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Empfehlung Haupt-Box ─────────────────────────────────────
            if (recommendation.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: recommendation == 'All-In'
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
                        style: const TextStyle(
                            fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isBluff) const Text('🎭 ', style: TextStyle(fontSize: 20)),
                        Flexible(
                          child: Text(reason,
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Action Probabilities ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppConfig.panelColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('WAHRSCHEINLICHKEITEN',
                        style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    _buildActionBar('FOLD',         _foldPct,  Colors.red.shade600),
                    _buildActionBar('CHECK / CALL', _callPct,  Colors.green.shade600),
                    _buildActionBar('RAISE',        _raisePct, Colors.blue.shade500),
                  ],
                ),
              ),

              // ── Bet-Sizing ────────────────────────────────────────────
              if (_betDisplay.isNotEmpty) ...[
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
                        Flexible(
                          child: Text(
                            _betDisplay,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(_betReason,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                        textAlign: TextAlign.center),
                  ]),
                ),
              ],

              // ── Board Texture Info (post-flop only) ───────────────────
              if (street > 0 && communityCards.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildBoardTextureCard(),
              ],

              // ── Draw Detections ───────────────────────────────────────
              if (_draws.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDrawsCard(),
              ],
            ],

            const SizedBox(height: 16),

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

            // Stack & Position Badge
            _buildStackPositionBadge(),
            const SizedBox(height: 8),

            _buildDropdown('Position', position, positions, (v) => setState(() => position = v)),
            _buildDropdown('Street', street, streets, (v) {
              setState(() {
                street = v;
                // Clear community cards if switching to preflop
                if (v == 0) communityCards = [];
              });
            }),
            _buildDropdown('Hand', handRank, handNames, (v) => setState(() => handRank = v)),
            _buildSlider('Pot', pot, 500, (v) => setState(() => pot = v)),
            // Bet Size Buttons (Feature 7)
            _buildBetSizeButtons(),
            _buildSlider('Stack', stackSize, 500, (v) => setState(() => stackSize = v)),

            const SizedBox(height: 12),

            // ── Community Cards Input ─────────────────────────────────────
            if (street > 0) ...[
              CommunityCardsWidget(
                cards: communityCards,
                street: street,
                onChanged: (cards) => setState(() => communityCards = cards),
              ),
              const SizedBox(height: 8),
            ],

            // ── Hole Cards Input (optional) ───────────────────────────────
            HoleCardsWidget(
              cards: holeCards,
              onChanged: (cards) => setState(() => holeCards = cards),
            ),

            const SizedBox(height: 12),

            // Board Info (old chip row) — show only if no community cards entered
            if (street > 0 && communityCards.isEmpty)
              _buildBoardInfo(),

            const SizedBox(height: 12),

            // Opponent Modeling
            OpponentModelWidget(
              initialVpip: _vpip,
              initialPfr:  _pfr,
              onVpipChanged: (v) => setState(() => _vpip = v),
              onPfrChanged:  (p) => setState(() => _pfr  = p),
            ),

            const SizedBox(height: 8),

            // Pot Odds
            PotOddsWidget(
              handEquityPercent: (handRank / 8.0) * 100,
            ),

            const SizedBox(height: 20),

            // CTA Button
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
                  const Text('86.9%',
                      style: TextStyle(
                          color: AppConfig.primaryColor,
                          fontWeight: FontWeight.bold)),
                  const Text(' | 100k Hände', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Board Texture Card ────────────────────────────────────────────────────
  Widget _buildBoardTextureCard() {
    final Color textureColor;
    switch (_boardAnalysis.texture) {
      case 'wet':
        textureColor = Colors.blue.shade400;
        break;
      case 'paired':
        textureColor = Colors.orange.shade400;
        break;
      default:
        textureColor = Colors.amber.shade600;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: textureColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textureColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('BOARD TEXTURE',
                  style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
              const Spacer(),
              Text(
                'Danger ${_boardAnalysis.dangerScore}/10',
                style: TextStyle(color: textureColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _boardAnalysis.label,
            style: TextStyle(
                color: textureColor,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              if (_boardAnalysis.flushDraw)
                _boardTag('Flush Draw ♦', Colors.blue.shade300),
              if (_boardAnalysis.straightDraw)
                _boardTag('Straight Draw 📏', Colors.green.shade300),
              if (_boardAnalysis.paired)
                _boardTag('Paired Board 🔄', Colors.orange.shade300),
              if (!_boardAnalysis.flushDraw &&
                  !_boardAnalysis.straightDraw &&
                  !_boardAnalysis.paired)
                _boardTag('No Draws', Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boardTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  // ── Draw Detections Card ──────────────────────────────────────────────────
  Widget _buildDrawsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HAND vs BOARD',
              style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          ..._draws.map((d) {
            final color = d.isMade ? Colors.green.shade400 : Colors.amber.shade400;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    d.isMade ? Icons.check_circle : Icons.arrow_circle_right,
                    color: color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(d.label, style: TextStyle(color: color, fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Action Bar ────────────────────────────────────────────────────────────
  Widget _buildActionBar(String label, double value, Color color) {
    final pct = (value * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            Text('$pct%',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colors.grey.shade800,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ]),
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

  Widget _buildStackPositionBadge() {
    final stackBb = stackSize / _bigBlindSize;
    final posNames = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
    final posStr = position < posNames.length ? posNames[position] : 'MP';

    final Color stackColor;
    final String stackLabel;
    final String stackHint;
    if (stackBb < 20) {
      stackColor = const Color(0xFFFF4444);
      stackLabel = '🔴 ${stackBb.toStringAsFixed(1)}bb';
      stackHint = 'Short Stack → Push/Fold';
    } else if (stackBb <= 50) {
      stackColor = const Color(0xFFFFAA00);
      stackLabel = '🟡 ${stackBb.toStringAsFixed(1)}bb';
      stackHint = 'Mid Stack → Vorsichtig';
    } else {
      stackColor = AppConfig.primaryColor;
      stackLabel = '🟢 ${stackBb.toStringAsFixed(1)}bb';
      stackHint = 'Deep Stack → Implied Odds';
    }

    final String posHint;
    switch (posStr) {
      case 'BTN': posHint = 'Weiteste Range, steal'; break;
      case 'CO':  posHint = 'Breit öffnen'; break;
      case 'MP':  posHint = 'Standard Range'; break;
      case 'UTG': posHint = 'Nur Premium!'; break;
      case 'SB':  posHint = 'Steal vs BB, OOP'; break;
      case 'BB':  posHint = 'Defend mit Odds'; break;
      default:    posHint = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('POSITION', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 2),
            Text('🎯 $posStr',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            Text(posHint, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ]),
          Container(width: 1, height: 40, color: Colors.grey.shade800),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('STACK', style: TextStyle(color: Colors.grey, fontSize: 10)),
            const SizedBox(height: 2),
            Text(stackLabel,
                style: TextStyle(
                    color: stackColor, fontSize: 14, fontWeight: FontWeight.bold)),
            Text(stackHint, style: const TextStyle(color: Colors.grey, fontSize: 10)),
          ]),
        ],
      ),
    );
  }

  Widget _buildDropdown(
      String label, int value, List<String> items, Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text('$label:', style: const TextStyle(color: Colors.white70))),
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
                items: List.generate(items.length,
                    (i) => DropdownMenuItem(value: i, child: Text(items[i]))),
                onChanged: (v) => onChanged(v!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(
      String label, double value, double max, Function(double) onChanged) {
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
    // Fallback board info when no community cards entered
    final texture = street > 0 ? ['', 'Dry', 'Wet', 'Paired'][street % 4 == 0 ? 3 : street] : '—';
    final danger = street * 2 + 3;
    Color dangerColor =
        danger > 6 ? Colors.red : (danger > 3 ? Colors.orange : AppConfig.primaryColor);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoChip('Board', texture.toUpperCase(), AppConfig.primaryColor),
          _buildInfoChip('Danger', '$danger/10', dangerColor),
          _buildInfoChip('Bluff', isBluff ? 'YES 🎭' : 'No',
              isBluff ? Colors.purple : Colors.grey),
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
                          const Icon(Icons.camera_alt,
                              size: 64, color: AppConfig.primaryColor),
                          const SizedBox(height: 16),
                          const Text('Kamera aktiv',
                              style: TextStyle(color: AppConfig.primaryColor)),
                          const SizedBox(height: 8),
                          const Text('Karten werden erkannt...',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppConfig.panelColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: demoCards
                                  .take(2)
                                  .map((c) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(c,
                                            style: const TextStyle(fontSize: 24)),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('Kamera aus',
                              style: TextStyle(color: Colors.grey)),
                          Text('Tippe auf Play zum Starten',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
              ),
            ),
          ),
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
                  children: demoCards
                      .take(2)
                      .map((c) => Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(c,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                )),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('TISCH',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: demoTable
                      .map((c) => Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(c,
                                style: const TextStyle(
                                    fontSize: 18, color: Colors.black)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
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
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
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
            child: const Column(
              children: [
                Text('ICM STATUS',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 8),
                Text('Normal',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                SizedBox(height: 4),
                Text('Kein Bubble',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('TURNIER SZENARIEN',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          _buildScenario(50, 'Push/Fold', '10-15 BB', Colors.red),
          _buildScenario(100, 'Open Raise', '15-20 BB', Colors.orange),
          _buildScenario(200, 'Standard', '20+ BB', AppConfig.primaryColor),
          _buildScenario(500, 'Deep Stack', '50+ BB', Colors.blue),
          const SizedBox(height: 16),
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
                    Text('Bubble Tipps',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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

  static Widget _buildScenario(
      int bbs, String action, String range, Color color) {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            child: Text('$bbs BB',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color)),
                Text(range,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: color, size: 16),
        ],
      ),
    );
  }

  static Widget _buildTip(String emoji, String text) {
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

  static Widget _buildPayout(String place, String percent, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 30,
              child: Text(place,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold))),
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppConfig.primaryColor.withOpacity(0.8),
                  AppConfig.primaryColor.withOpacity(0.4)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Text('GESAMT PERFORMANCE',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
                SizedBox(height: 8),
                Text('0',
                    style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                Text('Hände gespielt',
                    style: TextStyle(color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _buildStatCard('Win-Rate', '0%', Colors.grey)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildStatCard('Avg Profit', '\$0', Colors.grey)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.people, color: AppConfig.primaryColor),
                    SizedBox(width: 8),
                    Text('GEGNER TRACKING',
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
                    backgroundColor:
                        AppConfig.primaryColor.withOpacity(0.2),
                    foregroundColor: AppConfig.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppConfig.panelColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history, color: AppConfig.primaryColor),
                    SizedBox(width: 8),
                    Text('HAND HISTORY',
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
                    backgroundColor:
                        AppConfig.primaryColor.withOpacity(0.2),
                    foregroundColor: AppConfig.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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

  static Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.panelColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  static Widget _buildActionStat(
      String action, int count, double winRate) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 60,
              child: Text(action,
                  style: const TextStyle(color: Colors.white70))),
          Expanded(
            child: LinearProgressIndicator(
              value: winRate / 100,
              backgroundColor: Colors.grey.shade800,
              valueColor:
                  AlwaysStoppedAnimation(AppConfig.primaryColor),
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
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Version ${AppConfig.version}',
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('ML Genauigkeit: 86.9%',
                    style: TextStyle(color: AppConfig.primaryColor)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSection('SPRACHE', [
            _buildLangOption('DE', 'Deutsch', true),
            _buildLangOption('EN', 'English', false),
          ]),
          _buildSection('AUDIO & FEEDBACK', [
            _buildSwitch('Sprachausgabe (TTS)', ttsEnabled,
                (v) => setState(() => ttsEnabled = v)),
            _buildSwitch('Haptic Feedback', hapticEnabled,
                (v) => setState(() => hapticEnabled = v)),
          ]),
          _buildSection('AUFNAHME', [
            _buildSwitch('Auto-Record Hände', autoRecord,
                (v) => setState(() => autoRecord = v)),
          ]),
          _buildSection('MACHINE LEARNING', [
            _buildInfo('Trainingsdaten', '100.000 Hände'),
            _buildInfo('Modell', 'Gradient Boosting'),
            _buildInfo('Genauigkeit', '86.9%'),
            _buildButton('Neu Trainieren', () {}),
          ]),
          _buildSection('DATEN', [
            _buildButton('Exportieren', () {}),
            _buildButton('Importieren', () {}),
            _buildButton('Reset', () {}, isDestructive: true),
          ]),
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
      title: Text(label,
          style: const TextStyle(color: Colors.white70)),
      trailing: Text(value,
          style: const TextStyle(color: AppConfig.primaryColor)),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed,
      {bool isDestructive = false}) {
    return ListTile(
      title: Text(label,
          style:
              TextStyle(color: isDestructive ? Colors.red : Colors.white)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onPressed,
    );
  }

  Widget _buildLink(String label, VoidCallback onPressed) {
    return ListTile(
      title: Text(label,
          style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onPressed,
    );
  }
}
