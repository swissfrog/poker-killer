// opponent_tracker.dart
// Verfolgt Gegner-Statistiken innerhalb einer Session
// VPIP, PFR, AF (Aggression Factor), 3bet%

class OpponentStats {
  int handsPlayed = 0;
  int vpip = 0;       // Voluntary Put money In Pot
  int pfr = 0;        // Pre-Flop Raise
  int threebet = 0;   // 3bet count
  int threebetOpp = 0; // 3bet opportunities
  int aggrActions = 0; // bets + raises
  int passiveActions = 0; // calls + checks

  // Derived stats (0.0 - 1.0)
  double get vpipPct => handsPlayed > 5 ? vpip / handsPlayed : 0.25;
  double get pfrPct => handsPlayed > 5 ? pfr / handsPlayed : 0.15;
  double get af => (aggrActions + passiveActions) > 3
      ? aggrActions / (passiveActions + 1.0)
      : 1.0; // neutral default
  double get threebetPct => threebetOpp > 3 ? threebet / threebetOpp : 0.07;

  // Spieler-Typ: 0=Nit, 0.25=TAG, 0.5=LAG, 0.75=Calling Station, 1=Maniac
  double get playerType {
    if (vpipPct < 0.15 && pfrPct < 0.12) return 0.0;  // Nit
    if (vpipPct < 0.25 && pfrPct > 0.15) return 0.25; // TAG
    if (vpipPct > 0.35 && pfrPct > 0.25) return 0.5;  // LAG
    if (vpipPct > 0.35 && pfrPct < 0.15) return 0.75; // Calling Station
    if (vpipPct > 0.5) return 1.0;                     // Maniac
    return 0.3; // Default: slight TAG
  }

  String get playerTypeName {
    final t = playerType;
    if (t <= 0.1) return 'Nit 🧊';
    if (t <= 0.3) return 'TAG 🎯';
    if (t <= 0.55) return 'LAG 🔥';
    if (t <= 0.8) return 'Station 📞';
    return 'Maniac 💣';
  }

  // Exploitative Adjustments
  // Gegen Nits: mehr Steals, weniger Calls
  // Gegen Maniacs: tighter, more trapping
  double adjustedFoldThreshold() {
    // Basis-Threshold erhöhen gegen aggressive Spieler (mehr FE)
    return 0.35 + (playerType - 0.5) * 0.1;
  }

  double adjustedRaiseThreshold() {
    // Gegen Calling Stations: mehr Value, weniger Bluffs
    if (playerType > 0.6) return 0.65; // need stronger hand vs station
    if (playerType < 0.2) return 0.55; // can bluff nits more
    return 0.60;
  }

  void recordHand({bool voluntary = false, bool raised = false}) {
    handsPlayed++;
    if (voluntary) vpip++;
    if (raised) pfr++;
  }

  void recordAction({required bool aggressive}) {
    if (aggressive) aggrActions++;
    else passiveActions++;
  }

  void record3betOpp({bool did3bet = false}) {
    threebetOpp++;
    if (did3bet) threebet++;
  }

  Map<String, dynamic> toJson() => {
    'hands': handsPlayed,
    'vpip': vpipPct,
    'pfr': pfrPct,
    'af': af,
    '3bet': threebetPct,
    'type': playerTypeName,
  };
}

class OpponentTracker {
  final Map<String, OpponentStats> _players = {};
  int _currentHand = 0;

  OpponentStats get(String playerId) {
    _players[playerId] ??= OpponentStats();
    return _players[playerId]!;
  }

  void newHand() => _currentHand++;

  // Aggregierte Stats wenn kein spezifischer Gegner bekannt
  OpponentStats get aggregated {
    if (_players.isEmpty) return OpponentStats();
    final all = _players.values.toList();
    final agg = OpponentStats();
    agg.handsPlayed = all.map((s) => s.handsPlayed).reduce((a, b) => a + b) ~/ all.length;
    agg.vpip = (all.map((s) => s.vpipPct).reduce((a, b) => a + b) / all.length * agg.handsPlayed).round();
    agg.pfr = (all.map((s) => s.pfrPct).reduce((a, b) => a + b) / all.length * agg.handsPlayed).round();
    agg.aggrActions = all.map((s) => s.aggrActions).reduce((a, b) => a + b) ~/ all.length;
    agg.passiveActions = all.map((s) => s.passiveActions).reduce((a, b) => a + b) ~/ all.length;
    return agg;
  }

  int get trackedPlayers => _players.length;
  void reset() => _players.clear();
}
