// draw_analyzer.dart
// Erkennt Draws, zählt Outs, berechnet Wahrscheinlichkeiten
// Board-Texture-Analyse

class DrawInfo {
  final String name;
  final int outs;
  final double probTurn;  // Wahrscheinlichkeit auf Turn zu treffen
  final double probRiver; // auf River
  final double probTurnOrRiver; // mind. einmal treffen
  final String emoji;

  const DrawInfo({
    required this.name,
    required this.outs,
    required this.probTurn,
    required this.probRiver,
    required this.probTurnOrRiver,
    required this.emoji,
  });
}

class BoardTexture {
  final bool isPaired;
  final bool isDoublePaired;
  final bool isTripped;
  final bool isMonotone;      // 3+ same suit
  final bool isTwoTone;       // exactly 2 same suit
  final bool isRainbow;       // all different suits
  final bool isConnected;     // sequence of 3+ ranks
  final bool isDisconnected;
  final double wetness;       // 0=dry, 1=very wet
  final String description;

  const BoardTexture({
    required this.isPaired,
    required this.isDoublePaired,
    required this.isTripped,
    required this.isMonotone,
    required this.isTwoTone,
    required this.isRainbow,
    required this.isConnected,
    required this.isDisconnected,
    required this.wetness,
    required this.description,
  });
}

class DrawAnalyzer {
  static const Map<String, int> rankValue = {
    '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
    '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
  };

  /// Analysiert alle Draws aus Hole + Board
  static List<DrawInfo> findDraws(
    List<Map<String, String>> hole,
    List<Map<String, String>> board,
  ) {
    if (hole.length < 2 || board.isEmpty) return [];

    final all = [...hole, ...board];
    final draws = <DrawInfo>[];
    final cardsLeft = 52 - all.length;
    final streetsLeft = board.length < 4 ? (board.length < 3 ? 2 : 2) : 1;

    // Bereits eine Hand? Dann weniger relevant
    final ranks = all.map((c) => rankValue[c['r']] ?? 7).toList();
    final suits = all.map((c) => c['s'] ?? '♠').toList();

    final rankCounts = <int, int>{};
    for (var r in ranks) rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    if (rankCounts.values.any((c) => c >= 2)) {
      // Schon ein Pair — Draws weniger wichtig aber noch relevant
    }

    // ─── Flush Draw ───────────────────────────────────────────────────────
    final suitCounts = <String, int>{};
    for (var s in suits) suitCounts[s] = (suitCounts[s] ?? 0) + 1;

    for (var entry in suitCounts.entries) {
      if (entry.value == 4) {
        final outs = 9; // 13 - 4 = 9 remaining suited cards
        draws.add(DrawInfo(
          name: 'Flush Draw',
          outs: outs,
          probTurn: _outsToProb(outs, cardsLeft),
          probRiver: board.length == 4 ? _outsToProb(outs, cardsLeft) : 0,
          probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(outs, cardsLeft) : _outsToProb(outs, cardsLeft),
          emoji: '♥',
        ));
      } else if (entry.value == 3 && hole.where((c) => c['s'] == entry.key).length == 2) {
        // Backdoor flush draw (beide Hole cards passend)
        draws.add(DrawInfo(
          name: 'Backdoor Flush',
          outs: 3,
          probTurn: _outsToProb(3, cardsLeft),
          probRiver: 0,
          probTurnOrRiver: 0.045, // ~4.5% backdoor
          emoji: '🔙',
        ));
      }
    }

    // ─── Straight Draw ────────────────────────────────────────────────────
    final uniqueRanks = ranks.toSet().toList()..sort();
    // Ace can be low (1) or high (14)
    final ranksWithLowAce = uniqueRanks.contains(14)
        ? [1, ...uniqueRanks]
        : uniqueRanks;

    // OESD (Open-Ended Straight Draw) — 8 outs
    for (int i = 0; i <= ranksWithLowAce.length - 4; i++) {
      final window = ranksWithLowAce.sublist(i, i + 4);
      if (window.last - window.first == 3 && window.toSet().length == 4) {
        // Check if we need ONE end or TWO ends
        final canHitLow = window.first > 2;
        final canHitHigh = window.last < 14;
        if (canHitLow && canHitHigh) {
          draws.add(DrawInfo(
            name: 'OESD',
            outs: 8,
            probTurn: _outsToProb(8, cardsLeft),
            probRiver: board.length == 4 ? _outsToProb(8, cardsLeft) : 0,
            probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(8, cardsLeft) : _outsToProb(8, cardsLeft),
            emoji: '↔️',
          ));
          break;
        }
      }
    }

    // Gutshot (inside straight) — 4 outs
    for (int i = 0; i <= ranksWithLowAce.length - 4; i++) {
      final window = ranksWithLowAce.sublist(i, i + 4);
      if (window.last - window.first == 4 && window.toSet().length == 4) {
        // Gap of 5 with 4 cards = gutshot
        draws.add(DrawInfo(
          name: 'Gutshot',
          outs: 4,
          probTurn: _outsToProb(4, cardsLeft),
          probRiver: board.length == 4 ? _outsToProb(4, cardsLeft) : 0,
          probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(4, cardsLeft) : _outsToProb(4, cardsLeft),
          emoji: '🎯',
        ));
        break;
      }
    }

    // ─── Pair → Set (Pocket Pair hat Trips Draw) ──────────────────────────
    if (hole.length == 2 && hole[0]['r'] == hole[1]['r']) {
      final pairRank = rankValue[hole[0]['r']] ?? 7;
      if (!board.any((c) => rankValue[c['r']] == pairRank)) {
        // Pocket pair, kein Trip auf dem Board
        draws.add(DrawInfo(
          name: 'Set Draw',
          outs: 2,
          probTurn: _outsToProb(2, cardsLeft),
          probRiver: board.length == 4 ? _outsToProb(2, cardsLeft) : 0,
          probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(2, cardsLeft) : _outsToProb(2, cardsLeft),
          emoji: '🎲',
        ));
      }
    }

    // ─── Overcards (2 Overcards zum Board) ────────────────────────────────
    if (board.isNotEmpty) {
      final boardMax = board.map((c) => rankValue[c['r']] ?? 0).reduce((a, b) => a > b ? a : b);
      final holeRanks = hole.map((c) => rankValue[c['r']] ?? 0).toList();
      final overcards = holeRanks.where((r) => r > boardMax).length;
      if (overcards == 2) {
        draws.add(DrawInfo(
          name: '2 Overcards',
          outs: 6,
          probTurn: _outsToProb(6, cardsLeft),
          probRiver: board.length == 4 ? _outsToProb(6, cardsLeft) : 0,
          probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(6, cardsLeft) : _outsToProb(6, cardsLeft),
          emoji: '👑',
        ));
      } else if (overcards == 1) {
        draws.add(DrawInfo(
          name: '1 Overcard',
          outs: 3,
          probTurn: _outsToProb(3, cardsLeft),
          probRiver: board.length == 4 ? _outsToProb(3, cardsLeft) : 0,
          probTurnOrRiver: board.length < 4 ? _outsToProbTwoStreets(3, cardsLeft) : _outsToProb(3, cardsLeft),
          emoji: '⬆️',
        ));
      }
    }

    return draws;
  }

  /// Board-Texture analysieren
  static BoardTexture analyzeBoard(List<Map<String, String>> board) {
    if (board.isEmpty) {
      return const BoardTexture(
        isPaired: false, isDoublePaired: false, isTripped: false,
        isMonotone: false, isTwoTone: false, isRainbow: true,
        isConnected: false, isDisconnected: true,
        wetness: 0.2,
        description: 'Preflop',
      );
    }

    final ranks = board.map((c) => rankValue[c['r']] ?? 7).toList()..sort();
    final suits = board.map((c) => c['s'] ?? '♠').toList();

    // Rank counts
    final rankCounts = <int, int>{};
    for (var r in ranks) rankCounts[r] = (rankCounts[r] ?? 0) + 1;
    final isPaired = rankCounts.values.any((c) => c == 2);
    final isDoublePaired = rankCounts.values.where((c) => c == 2).length >= 2;
    final isTripped = rankCounts.values.any((c) => c >= 3);

    // Suit counts
    final suitCounts = <String, int>{};
    for (var s in suits) suitCounts[s] = (suitCounts[s] ?? 0) + 1;
    final maxSuit = suitCounts.values.fold(0, (a, b) => a > b ? a : b);
    final isMonotone = maxSuit >= 3;
    final isTwoTone = maxSuit == 2 && board.length >= 3;
    final isRainbow = maxSuit == 1;

    // Connectedness
    final uniqueRanks = ranks.toSet().toList()..sort();
    bool isConnected = false;
    if (uniqueRanks.length >= 3) {
      for (int i = 0; i <= uniqueRanks.length - 3; i++) {
        if (uniqueRanks[i + 2] - uniqueRanks[i] <= 4) {
          isConnected = true;
          break;
        }
      }
    }
    final isDisconnected = !isConnected && (uniqueRanks.isEmpty || (uniqueRanks.last - uniqueRanks.first > 6));

    // Wetness
    double wetness = 0.0;
    if (isMonotone) wetness += 0.4;
    else if (isTwoTone) wetness += 0.2;
    if (isConnected) wetness += 0.3;
    if (!isPaired && !isTripped) wetness += 0.1;
    wetness = wetness.clamp(0.0, 1.0);

    // Description
    final parts = <String>[];
    if (isTripped) parts.add('Trips');
    else if (isDoublePaired) parts.add('Double-Paired');
    else if (isPaired) parts.add('Paired');
    if (isMonotone) parts.add('Monotone');
    else if (isTwoTone) parts.add('Two-tone');
    else if (isRainbow) parts.add('Rainbow');
    if (isConnected) parts.add('Connected');
    else if (isDisconnected) parts.add('Dry');

    return BoardTexture(
      isPaired: isPaired,
      isDoublePaired: isDoublePaired,
      isTripped: isTripped,
      isMonotone: isMonotone,
      isTwoTone: isTwoTone,
      isRainbow: isRainbow,
      isConnected: isConnected,
      isDisconnected: isDisconnected,
      wetness: wetness,
      description: parts.join(' · '),
    );
  }

  /// C-Bet Empfehlung basierend auf Board-Texture
  static String cbetAdvice(BoardTexture texture, double equity) {
    if (texture.isMonotone && equity < 0.6) return 'Small C-Bet (25-33%)';
    if (texture.isPaired && equity > 0.65) return 'C-Bet (50-66%)';
    if (texture.isDisconnected && equity > 0.55) return 'C-Bet (66-75%)';
    if (texture.isConnected && equity > 0.7) return 'C-Bet (50%)';
    if (equity < 0.4) return 'Check (keine Equity)';
    return 'Check-Call';
  }

  // Rule of 2 and 4
  static double _outsToProb(int outs, int cardsLeft) {
    if (cardsLeft <= 0) return 0;
    return outs / cardsLeft;
  }

  static double _outsToProbTwoStreets(int outs, int cardsLeft) {
    // Rule of 4 approximation
    return (outs * 4 / 100).clamp(0.0, 0.99);
  }

  /// Totale Outs (dedupliziert)
  static int totalOuts(List<DrawInfo> draws) {
    if (draws.isEmpty) return 0;
    // Nimm den größten Draw als Basis, addiere nicht-überlappende
    final sorted = [...draws]..sort((a, b) => b.outs.compareTo(a.outs));
    int total = sorted[0].outs;
    // Weitere Draws: halbe Outs addieren wegen Overlap
    for (int i = 1; i < sorted.length; i++) {
      total += (sorted[i].outs * 0.5).round();
    }
    return total.clamp(0, 20);
  }
}
