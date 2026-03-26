/// stack_awareness.dart — Stack-Size Klassifizierung und angepasste Strategie
///
/// Short Stack (<20bb):  Push/Fold Strategie, weniger Bluffs, mehr All-In
/// Mid Stack (20-50bb):  Vorsichtige Raises, keine fancy plays, Push/Fold near 15bb
/// Deep Stack (>50bb):   Volle Postflop-Strategie, Bluffs erlaubt, SPR-Spiel

enum StackType {
  shortStack,  // < 20 BB
  midStack,    // 20–50 BB
  deepStack,   // > 50 BB
}

class StackAwareness {
  /// Klassifiziert den Stack-Typ basierend auf BB-Größe
  static StackType classify(double stackInBb) {
    if (stackInBb < 20) return StackType.shortStack;
    if (stackInBb <= 50) return StackType.midStack;
    return StackType.deepStack;
  }

  /// Berechnet Stack in Big Blinds
  static double stackInBb(double stack, double bigBlind) {
    if (bigBlind <= 0) return stack;
    return stack / bigBlind;
  }

  /// Angepasster Equity-Threshold: Short Stack braucht höhere Equity für Calls
  static double adjustedEquityThreshold(StackType type, double baseThreshold) {
    switch (type) {
      case StackType.shortStack:
        // Short Stack: Push/Fold → threshold höher für Calls, aber All-In wenn gut
        return baseThreshold + 0.05;
      case StackType.midStack:
        return baseThreshold;
      case StackType.deepStack:
        // Deep Stack kann mehr Calls riskieren (implied odds)
        return baseThreshold - 0.03;
    }
  }

  /// Bluff-Frequenz Anpassung: Short Stack blufft weniger
  static double bluffAdjustment(StackType type) {
    switch (type) {
      case StackType.shortStack:
        return -0.15; // 15% weniger Bluffs
      case StackType.midStack:
        return -0.05;
      case StackType.deepStack:
        return 0.0; // volle Bluff-Frequenz
    }
  }

  /// Ob Push/Fold Strategie aktiv sein soll (statt Raise/Call/Fold)
  static bool isPushFoldZone(double stackInBb) => stackInBb < 15;

  /// Ob All-In sinnvoller ist als ein normaler Raise
  static bool shouldGoAllIn(double stackInBb) => stackInBb < 20;

  /// Stack-Awareness Overlay: Modifiziert die finale Empfehlung
  static String applyStackOverlay({
    required String baseAction,
    required double stackInBb,
    required double equity,
    required bool isPreflop,
  }) {
    final type = classify(stackInBb);

    // Push/Fold Zone: Short Stack < 15bb
    if (isPushFoldZone(stackInBb) && isPreflop) {
      if (equity >= 0.55) return 'ALL-IN';  // Push
      if (equity < 0.40) return 'FOLD';     // Fold
      // Borderline: behalte ursprüngliche Empfehlung
    }

    // Short Stack: kein Raise → direkt All-In
    if (type == StackType.shortStack && baseAction == 'RAISE') {
      return 'ALL-IN';
    }

    // Short Stack: keine Bluffs
    if (type == StackType.shortStack && baseAction == 'RAISE' && equity < 0.50) {
      return 'CHECK';
    }

    return baseAction;
  }

  /// Anzeige-Text für UI
  static String displayLabel(double stackInBb) {
    final type = classify(stackInBb);
    final bbStr = stackInBb.toStringAsFixed(1);
    switch (type) {
      case StackType.shortStack:
        return '🔴 ${bbStr}bb (Short)';
      case StackType.midStack:
        return '🟡 ${bbStr}bb (Mid)';
      case StackType.deepStack:
        return '🟢 ${bbStr}bb (Deep)';
    }
  }

  /// Farb-Code für UI (als Hex-String)
  static int displayColor(StackType type) {
    switch (type) {
      case StackType.shortStack:
        return 0xFFFF4444; // Rot
      case StackType.midStack:
        return 0xFFFFAA00; // Gelb/Orange
      case StackType.deepStack:
        return 0xFF00FF88; // Grün (AC.P)
    }
  }

  /// Strategie-Hinweis für den Spieler
  static String strategyHint(double stackInBb) {
    final type = classify(stackInBb);
    switch (type) {
      case StackType.shortStack:
        return 'Push/Fold Modus — kein Postflop';
      case StackType.midStack:
        return 'Vorsichtig — nur Premium öffnen';
      case StackType.deepStack:
        return 'Deep Stack — Implied Odds spielen';
    }
  }
}
