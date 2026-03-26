/// position_awareness.dart — Position-Awareness für Poker-Bot
///
/// Positionen (Late → Early):
///   BTN (Button)   — stärkste Position, am meisten Hands öffnen
///   CO  (Cutoff)   — zweitstärkste, weite Range
///   MP  (Middle)   — mittlere Range
///   EP  (Early / UTG) — engste Range
///   SB  (Small Blind) — OOP postflop, leicht tighter
///   BB  (Big Blind)   — Defending Range, gute Odds

enum PokerPosition {
  bb,  // 0 - Big Blind
  sb,  // 1 - Small Blind
  btn, // 2 - Button (späte Position)
  co,  // 3 - Cutoff
  mp,  // 4 - Middle Position
  ep,  // 5 - Early Position / UTG
}

class PositionAwareness {
  /// Positionen in Reihenfolge (für Dropdown, Index == enum index)
  static const List<String> positionNames = ['BB', 'SB', 'BTN', 'CO', 'MP', 'EP'];

  /// Ob die Position als "late" gilt (Vorteil postflop)
  static bool isLatePosition(PokerPosition pos) =>
      pos == PokerPosition.btn || pos == PokerPosition.co;

  /// Ob die Position als "early" gilt (stärkste Range nötig)
  static bool isEarlyPosition(PokerPosition pos) =>
      pos == PokerPosition.ep || pos == PokerPosition.mp;

  /// Ob man postflop in Position ist (nach BB gehandelt wird)
  static bool isInPosition(PokerPosition pos) =>
      pos == PokerPosition.btn || pos == PokerPosition.co || pos == PokerPosition.mp;

  /// Opening Range Multiplikator: Late Position öffnet breiter
  /// Gibt einen Faktor zurück, um die Opening Range anzupassen (>1 = weiter, <1 = enger)
  static double openingRangeMultiplier(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn:
        return 1.50; // BTN: sehr breit
      case PokerPosition.co:
        return 1.30; // CO: breit
      case PokerPosition.mp:
        return 1.10; // MP: leicht breiter
      case PokerPosition.ep:
        return 0.85; // EP: enger
      case PokerPosition.sb:
        return 1.15; // SB: etwas breiter (steal)
      case PokerPosition.bb:
        return 1.20; // BB: defending Range (breiter wegen pot odds)
    }
  }

  /// Equity-Boost für In-Position Spiel (implied odds, information advantage)
  static double equityBoost(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn:
        return 0.05;  // +5% effektive Equity dank Position
      case PokerPosition.co:
        return 0.03;
      case PokerPosition.mp:
        return 0.01;
      case PokerPosition.ep:
        return -0.02; // -2% weil OOP
      case PokerPosition.sb:
        return -0.03; // SB OOP postflop
      case PokerPosition.bb:
        return 0.02;  // BB hat pot odds Vorteil
    }
  }

  /// C-Bet Frequenz Anpassung nach Position
  static double cbetAdjustment(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn:
        return 0.10;  // Häufiger C-betten
      case PokerPosition.co:
        return 0.07;
      case PokerPosition.mp:
        return 0.03;
      case PokerPosition.ep:
        return -0.05; // Seltener C-betten
      case PokerPosition.sb:
        return -0.05;
      case PokerPosition.bb:
        return 0.0;
    }
  }

  /// Steal-Raise Empfehlung (SB/BTN vs Blinds)
  static bool shouldSteal(PokerPosition pos, double equity) {
    switch (pos) {
      case PokerPosition.btn:
        return equity >= 0.35; // Sehr breit stealen
      case PokerPosition.co:
        return equity >= 0.45;
      case PokerPosition.sb:
        return equity >= 0.40;
      default:
        return false;
    }
  }

  /// Finale Aktions-Anpassung basierend auf Position
  static String applyPositionOverlay({
    required String baseAction,
    required PokerPosition position,
    required double equity,
    required bool isPreflop,
    required bool facingNoRaise,
  }) {
    // Late Position: öffne breiter (Raise wenn kein Raise vor dir)
    if (isPreflop && facingNoRaise && shouldSteal(position, equity)) {
      if (baseAction == 'FOLD') return 'RAISE';
    }

    // Early Position: wenn Raise empfohlen aber Equity nur mittel → lieber Call/Fold
    if (isEarlyPosition(position) && baseAction == 'RAISE' && equity < 0.60) {
      return equity >= 0.48 ? 'CALL' : 'FOLD';
    }

    return baseAction;
  }

  /// Konvertiert den position-Index (wie im Dropdown) zu PokerPosition enum
  static PokerPosition fromIndex(int idx) {
    if (idx < 0 || idx >= PokerPosition.values.length) return PokerPosition.mp;
    return PokerPosition.values[idx];
  }

  /// Anzeige-Text für UI (mit Emoji)
  static String displayLabel(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn:
        return '🎯 BTN (Button)';
      case PokerPosition.co:
        return '🟢 CO (Cutoff)';
      case PokerPosition.mp:
        return '🟡 MP (Middle)';
      case PokerPosition.ep:
        return '🔴 EP (Early)';
      case PokerPosition.sb:
        return '🔵 SB (Small Blind)';
      case PokerPosition.bb:
        return '⚪ BB (Big Blind)';
    }
  }

  /// Kurzform für Anzeige
  static String shortLabel(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn: return 'BTN';
      case PokerPosition.co:  return 'CO';
      case PokerPosition.mp:  return 'MP';
      case PokerPosition.ep:  return 'EP';
      case PokerPosition.sb:  return 'SB';
      case PokerPosition.bb:  return 'BB';
    }
  }

  /// Strategie-Hinweis für den Spieler
  static String strategyHint(PokerPosition pos) {
    switch (pos) {
      case PokerPosition.btn:
        return 'BTN: Weiteste Range, steal oft';
      case PokerPosition.co:
        return 'CO: Breit öffnen, 3bet leicht';
      case PokerPosition.mp:
        return 'MP: Standard Range, vorsichtig';
      case PokerPosition.ep:
        return 'EP: Nur Premium Hände!';
      case PokerPosition.sb:
        return 'SB: Steal vs BB, OOP postflop';
      case PokerPosition.bb:
        return 'BB: Defend mit pot odds';
    }
  }

  /// Numerischer Wert für TFLite Input (0.0–1.0)
  static double toModelInput(PokerPosition pos) {
    return pos.index / (PokerPosition.values.length - 1).toDouble();
  }
}
