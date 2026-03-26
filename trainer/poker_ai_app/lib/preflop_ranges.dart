// preflop_ranges.dart
// GTO-approximierte Preflop Opening- und 3bet-Ranges
// Basiert auf solver-basierten Ranges für 6-max NLHE
// v2: Position-Awareness integriert (PositionAwareness.openingRangeMultiplier)

import 'position_awareness.dart';

class PreflopRanges {
  // Opening Ranges per Position (% der Hände die man öffnet)
  // UTG, MP, CO, BTN, SB, BB (BB = facing open)
  static const Map<String, double> openingFreq = {
    'UTG': 0.14, // ~14% der Hände
    'MP':  0.19,
    'CO':  0.27,
    'BTN': 0.42,
    'SB':  0.35,
    'BB':  0.30, // defending vs open
  };

  // 3bet Ranges per Position (facing open)
  static const Map<String, double> threeBetFreq = {
    'UTG': 0.04,
    'MP':  0.05,
    'CO':  0.07,
    'BTN': 0.10,
    'SB':  0.12,
    'BB':  0.10,
  };

  // Handstärke 0-1 (basiert auf Kategorie)
  // Kategorie aus r (rank) und s (suit)
  static double handStrengthPreflop(String r1, String s1, String r2, String s2) {
    const rankValues = {
      'A': 14, 'K': 13, 'Q': 12, 'J': 11, '10': 10,
      '9': 9,  '8': 8,  '7': 7,  '6': 6,  '5': 5,
      '4': 4,  '3': 3,  '2': 2,
    };

    final rv1 = rankValues[r1] ?? 7;
    final rv2 = rankValues[r2] ?? 7;
    final high = rv1 > rv2 ? rv1 : rv2;
    final low  = rv1 < rv2 ? rv1 : rv2;
    final suited = s1 == s2;
    final pair = r1 == r2;
    final gap = high - low;

    // Premium pairs
    if (pair && high >= 10) return 0.90 + (high - 10) * 0.025;
    if (pair) return 0.55 + low * 0.02;

    // Suited premium
    if (suited && high == 14 && low >= 12) return 0.85;
    if (suited && high == 14 && low >= 9)  return 0.72;
    if (suited && high == 13 && low >= 12) return 0.78;
    if (suited && gap <= 1 && high >= 10)  return 0.68;
    if (suited && gap <= 2 && high >= 9)   return 0.58;
    if (suited && high >= 10)              return 0.52;

    // Offsuit
    if (high == 14 && low >= 13) return 0.82; // AKo
    if (high == 14 && low >= 11) return 0.70; // AQo, AJo
    if (high == 14 && low >= 9)  return 0.58; // ATo, A9o
    if (high == 13 && low >= 12) return 0.65; // KQo
    if (high >= 11 && gap == 0)  return 0.60; // Broadway pairs

    // Connected
    if (gap <= 1 && high >= 9) return 0.45;
    if (gap <= 2 && high >= 8) return 0.38;

    // Rest
    return 0.20 + high * 0.01 + (suited ? 0.05 : 0.0);
  }

  // Soll man preflop öffnen?
  static bool shouldOpen(String rank1, String suit1, String rank2, String suit2, int positionIdx) {
    final positions = ['BB', 'SB', 'UTG', 'MP', 'CO', 'BTN'];
    final posName = positionIdx < positions.length ? positions[positionIdx] : 'CO';
    final threshold = 1.0 - (openingFreq[posName] ?? 0.25);
    final strength = handStrengthPreflop(rank1, suit1, rank2, suit2);
    return strength >= threshold;
  }

  // Soll man 3betten?
  static bool should3bet(String rank1, String suit1, String rank2, String suit2, int positionIdx) {
    final positions = ['BB', 'SB', 'UTG', 'MP', 'CO', 'BTN'];
    final posName = positionIdx < positions.length ? positions[positionIdx] : 'CO';
    final freq = threeBetFreq[posName] ?? 0.07;
    final strength = handStrengthPreflop(rank1, suit1, rank2, suit2);
    // 3bet value hands (top %) + some bluffs (suited connectors)
    final valueThreshold = 1.0 - (freq * 0.6);
    final suited = suit1 == suit2;
    return strength >= valueThreshold || (suited && strength >= 0.55 && strength < 0.65);
  }

  // Empfehlung als Text (original, behält Kompatibilität)
  static String preflopAdvice(
    String rank1, String suit1,
    String rank2, String suit2,
    int posIdx, double callAmount, double pot
  ) {
    return preflopAdviceWithPosition(rank1, suit1, rank2, suit2, posIdx, callAmount, pot);
  }

  // Erweiterte Empfehlung mit expliziter Position-Awareness
  static String preflopAdviceWithPosition(
    String rank1, String suit1,
    String rank2, String suit2,
    int posIdx, double callAmount, double pot
  ) {
    final strength = handStrengthPreflop(rank1, suit1, rank2, suit2);
    final potOdds = (pot + callAmount) > 0 ? callAmount / (pot + callAmount) : 0.0;
    final pokerPos = PositionAwareness.fromIndex(posIdx);

    // Positions-Multiplikator: Late Position öffnet breiter
    final multiplier = PositionAwareness.openingRangeMultiplier(pokerPos);
    final adjustedStrength = strength * multiplier;

    if (callAmount == 0) {
      // Facing no bet / we open
      final positions = ['BB', 'SB', 'UTG', 'MP', 'CO', 'BTN'];
      final posName = posIdx < positions.length ? positions[posIdx] : 'CO';
      final baseThreshold = 1.0 - (openingFreq[posName] ?? 0.25);
      // Late Position: niedrigerer Threshold (weiter öffnen)
      final adjustedThreshold = baseThreshold / multiplier;
      if (strength >= adjustedThreshold) return 'RAISE';

      // Steal aus SB/BTN wenn stark genug
      if (PositionAwareness.shouldSteal(pokerPos, strength)) return 'RAISE';

      return 'FOLD';
    } else {
      // Facing a raise
      if (should3bet(rank1, suit1, rank2, suit2, posIdx)) return 'RAISE';
      // Late Position: etwas mehr Calls mit schwächeren Händen (implied odds)
      final callThreshold = potOdds + 0.05 - PositionAwareness.equityBoost(pokerPos);
      if (strength > callThreshold) return 'CALL';
      return 'FOLD';
    }
  }
}
