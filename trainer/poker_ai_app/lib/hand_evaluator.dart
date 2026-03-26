// hand_evaluator.dart
// Schnelle Poker-Hand-Evaluierung in Dart
// Basiert auf Lookup-Table-Ansatz (vereinfacht aber korrekt)

class HandEvaluator {
  // Hand-Kategorien (höher = besser)
  static const int HIGH_CARD = 0;
  static const int ONE_PAIR = 1;
  static const int TWO_PAIR = 2;
  static const int THREE_OF_KIND = 3;
  static const int STRAIGHT = 4;
  static const int FLUSH = 5;
  static const int FULL_HOUSE = 6;
  static const int FOUR_OF_KIND = 7;
  static const int STRAIGHT_FLUSH = 8;

  static const Map<String, int> rankValue = {
    '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8,
    '9': 9, '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
  };

  /// Evaluiert die beste 5-Karten-Hand aus gegebenen Karten
  /// cards: Liste von {'r': rank, 's': suit}
  /// Gibt [kategorie, tiebreaker1, tiebreaker2] zurück
  static List<int> evaluate(List<Map<String, String>> cards) {
    if (cards.length < 2) return [HIGH_CARD, 0, 0];

    final ranks = cards.map((c) => rankValue[c['r']] ?? 7).toList()..sort((a, b) => b.compareTo(a));
    final suits = cards.map((c) => c['s'] ?? '♠').toList();

    // Suit-Counts für Flush
    final suitCounts = <String, int>{};
    for (var s in suits) suitCounts[s] = (suitCounts[s] ?? 0) + 1;
    final hasFlush = suitCounts.values.any((c) => c >= 5);

    // Rank-Counts für Pairs etc.
    final rankCounts = <int, int>{};
    for (var r in ranks) rankCounts[r] = (rankCounts[r] ?? 0) + 1;

    final counts = rankCounts.values.toList()..sort((a, b) => b.compareTo(a));
    final ranksByCount = <int, List<int>>{};
    for (var entry in rankCounts.entries) {
      ranksByCount[entry.value] ??= [];
      ranksByCount[entry.value]!.add(entry.key);
    }
    ranksByCount.forEach((k, v) => v.sort((a, b) => b.compareTo(a)));

    // Straight check
    final uniqueRanks = ranks.toSet().toList()..sort((a, b) => b.compareTo(a));
    bool hasStraight = false;
    int straightHigh = 0;
    // Wheel (A-2-3-4-5)
    if (uniqueRanks.contains(14) && uniqueRanks.contains(2) &&
        uniqueRanks.contains(3) && uniqueRanks.contains(4) && uniqueRanks.contains(5)) {
      hasStraight = true;
      straightHigh = 5;
    }
    for (int i = 0; i <= uniqueRanks.length - 5; i++) {
      if (uniqueRanks[i] - uniqueRanks[i + 4] == 4) {
        hasStraight = true;
        straightHigh = uniqueRanks[i];
        break;
      }
    }

    final fours = ranksByCount[4] ?? [];
    final threes = ranksByCount[3] ?? [];
    final pairs = ranksByCount[2] ?? [];

    // Kategorien von oben nach unten
    if (hasFlush && hasStraight) return [STRAIGHT_FLUSH, straightHigh, 0];
    if (fours.isNotEmpty) return [FOUR_OF_KIND, fours[0], ranks.firstWhere((r) => r != fours[0], orElse: () => 0)];
    if (threes.isNotEmpty && pairs.isNotEmpty) return [FULL_HOUSE, threes[0], pairs[0]];
    if (hasFlush) return [FLUSH, ranks[0], ranks[1]];
    if (hasStraight) return [STRAIGHT, straightHigh, 0];
    if (threes.isNotEmpty) return [THREE_OF_KIND, threes[0], ranks.firstWhere((r) => r != threes[0], orElse: () => 0)];
    if (pairs.length >= 2) return [TWO_PAIR, pairs[0], pairs[1]];
    if (pairs.length == 1) return [ONE_PAIR, pairs[0], ranks.firstWhere((r) => r != pairs[0], orElse: () => 0)];
    return [HIGH_CARD, ranks[0], ranks.length > 1 ? ranks[1] : 0];
  }

  /// Schnelle Monte-Carlo Equity-Schätzung
  /// holecards: meine 2 Karten
  /// board: 0-5 Gemeinschaftskarten
  /// Gibt Equity 0.0-1.0 zurück
  static double monteCarloEquity(
    List<Map<String, String>> holecards,
    List<Map<String, String>> board, {
    int simulations = 200,
  }) {
    if (holecards.length < 2) return 0.5;

    final usedCards = {...holecards, ...board};
    final deck = _buildDeck(exclude: usedCards.toList());

    if (deck.length < 2) return 0.5;

    int wins = 0;
    int total = 0;
    final need = 5 - board.length;

    final rng = _SimpleRng();

    for (int i = 0; i < simulations; i++) {
      if (deck.length < need + 2) break;

      // Random sample
      final sample = _randomSample(deck, need + 2, rng);
      final runout = [...board, ...sample.sublist(0, need)];
      final oppHole = sample.sublist(need, need + 2);

      final myCards = [...holecards, ...runout];
      final oppCards = [...oppHole, ...runout];

      final myScore = evaluate(myCards);
      final oppScore = evaluate(oppCards);

      final cmp = _compareHands(myScore, oppScore);
      if (cmp > 0) wins += 2;
      else if (cmp == 0) wins += 1;
      total += 2;
    }

    return total > 0 ? wins / total : 0.5;
  }

  static int _compareHands(List<int> a, List<int> b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] > b[i]) return 1;
      if (a[i] < b[i]) return -1;
    }
    return 0;
  }

  static List<Map<String, String>> _buildDeck({List<Map<String, String>> exclude = const []}) {
    const ranks = ['2','3','4','5','6','7','8','9','10','J','Q','K','A'];
    const suits = ['♠','♥','♦','♣'];
    final deck = <Map<String, String>>[];
    final excludeSet = exclude.map((c) => '${c['r']}${c['s']}').toSet();

    for (var r in ranks) {
      for (var s in suits) {
        final key = '$r$s';
        if (!excludeSet.contains(key)) {
          deck.add({'r': r, 's': s});
        }
      }
    }
    return deck;
  }

  static List<Map<String, String>> _randomSample(
    List<Map<String, String>> deck, int n, _SimpleRng rng
  ) {
    final copy = List<Map<String, String>>.from(deck);
    final result = <Map<String, String>>[];
    for (int i = 0; i < n && copy.isNotEmpty; i++) {
      final idx = rng.nextInt(copy.length);
      result.add(copy[idx]);
      copy.removeAt(idx);
    }
    return result;
  }

  static String categoryName(int cat) => [
    'High Card', 'Pair', 'Two Pair', 'Three of Kind',
    'Straight', 'Flush', 'Full House', 'Four of Kind', 'Straight Flush'
  ][cat.clamp(0, 8)];
}

// Einfacher PRNG (schneller als dart:math Random für viele Iterationen)
class _SimpleRng {
  int _state;
  _SimpleRng() : _state = DateTime.now().microsecondsSinceEpoch;

  int nextInt(int max) {
    _state = (_state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF;
    return _state % max;
  }
}
