/// bet_sizer.dart — GTO-inspirierte Bet-Sizing Empfehlungen
/// Gibt konkrete Beträge und Strategie zurück statt nur RAISE/FOLD

class BetSizing {
  final String category; // 'value', 'bluff', 'protection', 'probe', 'check-raise'
  final double fraction; // Anteil am Pot (z.B. 0.33, 0.66, 1.5)
  final double amount;   // Konkreter Betrag in Chips
  final String reason;   // Erklärung für den User

  const BetSizing({
    required this.category,
    required this.fraction,
    required this.amount,
    required this.reason,
  });

  String get fractionLabel {
    if (fraction <= 0.35) return '33%';
    if (fraction <= 0.5) return '50%';
    if (fraction <= 0.7) return '66%';
    if (fraction <= 1.1) return 'Pot';
    if (fraction <= 1.6) return '1.5x';
    return 'All-In';
  }

  String get display => '\$${amount.toStringAsFixed(0)} ($fractionLabel Pot)';
}

class BetSizer {
  /// Berechnet optimale Bet-Size basierend auf Spielsituation
  ///
  /// [equity] 0.0-1.0 — Gewinnchance
  /// [street] 0=preflop, 1=flop, 2=turn, 3=river
  /// [pot] aktueller Pot
  /// [stack] verbleibender Stack
  /// [handCategory] 0=highcard, 1=pair, 2=twopair, 3=set, 4=straight, 5=flush, 6=fullhouse, 7=quads, 8=sf
  /// [boardWetness] 0.0=dry, 1.0=wet
  /// [hasDraw] hat Flush Draw oder OESD
  /// [position] 0=BB, 1=SB, 2=BTN, 3=CO, 4=MP, 5=UTG
  /// [facingBet] ob wir auf einen Bet reagieren oder selbst setzen
  /// [spr] Stack-to-Pot-Ratio
  static BetSizing recommend({
    required double equity,
    required int street,
    required double pot,
    required double stack,
    required int handCategory,
    double boardWetness = 0.3,
    bool hasDraw = false,
    bool hasFlushDraw = false,
    bool hasOESD = false,
    int position = 2,
    bool facingBet = false,
    double spr = 10.0,
    bool isBluff = false,
  }) {
    // Absolute Grenzen
    final maxBet = stack;
    if (pot <= 0) return _allIn(stack, 'All-In');

    // All-In wenn Stack sehr klein
    if (stack <= pot * 0.5 || spr < 1.0) {
      return _allIn(stack, 'Stack zu kurz → All-In ist optimal');
    }

    // ─── RIVER ───────────────────────────────────────────────────────────────
    if (street == 3) {
      return _riverSizing(equity, pot, stack, handCategory, boardWetness, facingBet, maxBet);
    }

    // ─── TURN ────────────────────────────────────────────────────────────────
    if (street == 2) {
      return _turnSizing(equity, pot, stack, handCategory, boardWetness, hasDraw, facingBet, spr, maxBet);
    }

    // ─── FLOP ────────────────────────────────────────────────────────────────
    if (street == 1) {
      return _flopSizing(equity, pot, stack, handCategory, boardWetness, hasDraw, hasFlushDraw, hasOESD, position, facingBet, spr, maxBet);
    }

    // ─── PREFLOP ─────────────────────────────────────────────────────────────
    return _preflopSizing(equity, pot, stack, position, facingBet, maxBet);
  }

  static BetSizing _preflopSizing(double equity, double pot, double stack, int position, bool facingBet, double maxBet) {
    if (facingBet) {
      // 3bet sizing
      if (equity > 0.72) {
        // Premium: 3x raise (linear sizing)
        final size = (pot * 3.0).clamp(0.0, maxBet);
        return BetSizing(
          category: 'value',
          fraction: 3.0,
          amount: size,
          reason: 'Premium Hand → 3bet für Value (3x)',
        );
      } else if (equity > 0.60) {
        // Gute Hand: 2.5x
        final size = (pot * 2.5).clamp(0.0, maxBet);
        return BetSizing(
          category: 'value',
          fraction: 2.5,
          amount: size,
          reason: 'Starke Hand → 3bet (2.5x)',
        );
      } else {
        // Bluff-3bet mit Position: klein
        final size = (pot * 2.2).clamp(0.0, maxBet);
        return BetSizing(
          category: 'bluff',
          fraction: 2.2,
          amount: size,
          reason: 'Bluff-3bet mit Equity/Position (2.2x)',
        );
      }
    } else {
      // Open-Raise sizing: 2.5x aus Position, 3x OOP
      final isInPosition = position >= 2; // BTN/CO/MP
      final mult = isInPosition ? 2.5 : 3.0;
      final size = (pot * mult).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: mult,
        amount: size,
        reason: isInPosition
            ? 'Open-Raise in Position (2.5x BB)'
            : 'Open-Raise OOP (3x BB)',
      );
    }
  }

  static BetSizing _flopSizing(double equity, double pot, double stack,
      int handCategory, double boardWetness, bool hasDraw, bool hasFlushDraw,
      bool hasOESD, int position, bool facingBet, double spr, double maxBet) {

    // Wet Board: größere Bets (Draws teuer machen)
    // Dry Board: kleinere Bets (weniger Draws, mehr value)

    if (equity > 0.75 || handCategory >= 5) {
      // Monster Hand (Flush+, Full House, Quads)
      if (boardWetness > 0.6) {
        // Wet board: bet groß für Schutz + Value
        final size = (pot * 0.75).clamp(0.0, maxBet);
        return BetSizing(
          category: 'value',
          fraction: 0.75,
          amount: size,
          reason: 'Monster auf nassem Board → 75% für Value + Schutz',
        );
      } else {
        // Dry board: bet klein (slowplay oder thin value)
        final size = (pot * 0.33).clamp(0.0, maxBet);
        return BetSizing(
          category: 'value',
          fraction: 0.33,
          amount: size,
          reason: 'Monster auf trockenem Board → 33% (thin value, keine Folds)',
        );
      }
    }

    if (equity > 0.60 || handCategory >= 3) {
      // Starke Hand (Set, Two Pair, Straight)
      final fraction = boardWetness > 0.5 ? 0.66 : 0.50;
      final size = (pot * fraction).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: fraction,
        amount: size,
        reason: boardWetness > 0.5
            ? 'Starke Hand auf nassem Board → 66% für Schutz'
            : 'Starke Hand → 50% Pot für Value',
      );
    }

    if (hasDraw) {
      // Draw: semi-bluff sizing
      if (hasFlushDraw && boardWetness > 0.5) {
        // Flush Draw auf Wet Board: bet groß als Semi-Bluff
        final size = (pot * 0.66).clamp(0.0, maxBet);
        return BetSizing(
          category: 'bluff',
          fraction: 0.66,
          amount: size,
          reason: 'Flush Draw Semi-Bluff → 66% (Fold-Equity + Outs)',
        );
      } else if (hasOESD) {
        final size = (pot * 0.50).clamp(0.0, maxBet);
        return BetSizing(
          category: 'bluff',
          fraction: 0.50,
          amount: size,
          reason: 'OESD Semi-Bluff → 50% Pot (8 Outs)',
        );
      } else {
        // Gutshot oder schwacher Draw: klein oder check
        final size = (pot * 0.33).clamp(0.0, maxBet);
        return BetSizing(
          category: 'probe',
          fraction: 0.33,
          amount: size,
          reason: 'Schwacher Draw → 33% als Probe-Bet',
        );
      }
    }

    if (equity > 0.45) {
      // Middle Hand (Pair): C-Bet auf trockenen Boards
      if (boardWetness < 0.4) {
        final size = (pot * 0.33).clamp(0.0, maxBet);
        return BetSizing(
          category: 'protection',
          fraction: 0.33,
          amount: size,
          reason: 'Pair auf trockenem Board → kleines C-Bet (33%)',
        );
      } else {
        // Auf nassem Board: Vorsicht, meist Check
        return BetSizing(
          category: 'probe',
          fraction: 0.0,
          amount: 0.0,
          reason: 'Pair auf nassem Board → Check (schütze Hand, kein Over-Commit)',
        );
      }
    }

    // Schwache Hand: Bluff oder Check
    if (position >= 2 && boardWetness < 0.4) {
      // In Position, trockenes Board: kleiner Bluff
      final size = (pot * 0.33).clamp(0.0, maxBet);
      return BetSizing(
        category: 'bluff',
        fraction: 0.33,
        amount: size,
        reason: 'Position C-Bet (33%) auf trockenem Board',
      );
    }

    return BetSizing(
      category: 'probe',
      fraction: 0.0,
      amount: 0.0,
      reason: 'Check → keine starke Hand oder Draw',
    );
  }

  static BetSizing _turnSizing(double equity, double pot, double stack,
      int handCategory, double boardWetness, bool hasDraw,
      bool facingBet, double spr, double maxBet) {

    // Turn: Pots größer, Draws teurer machen, Value maximieren
    if (equity > 0.75 || handCategory >= 5) {
      // Sehr starke Hand: polarisiert groß
      final fraction = spr < 3 ? 1.0 : 0.75;
      final size = (pot * fraction).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: fraction,
        amount: size,
        reason: spr < 3
            ? 'Monster Turn → Pot-Bet (SPR niedrig, committen)'
            : 'Monster Turn → 75% für maximalen Value',
      );
    }

    if (equity > 0.60 || handCategory >= 3) {
      // Gute Hand: 66% Standard
      final size = (pot * 0.66).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: 0.66,
        amount: size,
        reason: 'Starke Hand Turn → 66% Pot',
      );
    }

    if (hasDraw) {
      // Draw auf Turn: semi-bluff, Draws brauchen hohen Preis
      final size = (pot * 0.66).clamp(0.0, maxBet);
      return BetSizing(
        category: 'bluff',
        fraction: 0.66,
        amount: size,
        reason: 'Semi-Bluff Turn → 66% (teuer für Gegner-Draws)',
      );
    }

    // Probe/Bluff
    if (equity > 0.45) {
      final size = (pot * 0.50).clamp(0.0, maxBet);
      return BetSizing(
        category: 'protection',
        fraction: 0.50,
        amount: size,
        reason: 'Mittelstarke Hand Turn → 50% Probe',
      );
    }

    return BetSizing(
      category: 'probe',
      fraction: 0.0,
      amount: 0.0,
      reason: 'Check/Fold → schwache Hand auf Turn',
    );
  }

  static BetSizing _riverSizing(double equity, double pot, double stack,
      int handCategory, double boardWetness, bool facingBet, double maxBet) {

    // River: Kein Draw mehr. Entweder Value oder Bluff (polarisiert)
    if (equity > 0.80 || handCategory >= 6) {
      // Sehr starke Hand: bet groß (value maximieren)
      final size = (pot * 1.0).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: 1.0,
        amount: size,
        reason: 'Nuthouse River → Pot-Bet für maximalen Value',
      );
    }

    if (equity > 0.65 || handCategory >= 4) {
      // Gute Hand: 75%
      final size = (pot * 0.75).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: 0.75,
        amount: size,
        reason: 'Starke Hand River → 75% Value-Bet',
      );
    }

    if (equity > 0.50) {
      // Pair/Two Pair: thin value
      final size = (pot * 0.33).clamp(0.0, maxBet);
      return BetSizing(
        category: 'value',
        fraction: 0.33,
        amount: size,
        reason: 'Thin Value River → 33% (Calls von schlechteren Händen)',
      );
    }

    if (equity < 0.30 && !facingBet) {
      // Bluff mit schwacher Hand: polarisiert groß
      final size = (pot * 0.75).clamp(0.0, maxBet);
      return BetSizing(
        category: 'bluff',
        fraction: 0.75,
        amount: size,
        reason: 'Bluff River → 75% (polarisiert, keine Value)',
      );
    }

    // Showdown-Value aber unklar: Check
    return BetSizing(
      category: 'probe',
      fraction: 0.0,
      amount: 0.0,
      reason: 'Check für Showdown (keine klare Value oder Bluff-Situation)',
    );
  }

  static BetSizing _allIn(double stack, String reason) => BetSizing(
    category: 'value',
    fraction: 99.0,
    amount: stack,
    reason: reason,
  );
}
