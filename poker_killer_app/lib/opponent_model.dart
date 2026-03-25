// opponent_model.dart — FEATURE 1: Opponent Modeling
// VPIP / PFR tracking + player type badge

import 'package:flutter/material.dart';

// ─── Data Model ───────────────────────────────────────────────────────────────

enum PlayerType { fish, reg, nit, lag }

extension PlayerTypeExtension on PlayerType {
  String get label {
    switch (this) {
      case PlayerType.fish: return 'Fish 🐟';
      case PlayerType.reg:  return 'Reg 🎯';
      case PlayerType.nit:  return 'Nit 🪨';
      case PlayerType.lag:  return 'LAG 🔥';
    }
  }

  Color get color {
    switch (this) {
      case PlayerType.fish: return const Color(0xFF4FC3F7);
      case PlayerType.reg:  return const Color(0xFF00FF88);
      case PlayerType.nit:  return const Color(0xFFBDBDBD);
      case PlayerType.lag:  return const Color(0xFFFF5722);
    }
  }

  String get advice {
    switch (this) {
      case PlayerType.fish:
        return 'Mehr Value-Bets 💰, weniger Bluffs';
      case PlayerType.reg:
        return 'Standard GTO-Strategie';
      case PlayerType.nit:
        return 'Weniger bluff-raisen, mehr folden gegen Bets';
      case PlayerType.lag:
        return 'Mehr Traps spielen, Check-Raise nutzen';
    }
  }
}

/// Klassifiziert einen Gegner anhand von VPIP und PFR.
PlayerType classifyOpponent(double vpip, double pfr) {
  final bool loose  = vpip > 35;
  final bool tight  = vpip < 20;
  final bool aggro  = pfr > 15;
  // final bool passiv = pfr < 8;  // für spätere Nutzung

  if (loose && !aggro) return PlayerType.fish;
  if (loose && aggro)  return PlayerType.lag;
  if (tight && aggro)  return PlayerType.reg;
  return PlayerType.nit; // tight + passiv
}

/// Gibt einen Strategie-Score-Modifier zurück (positiv = aggressiver spielen).
double opponentScoreModifier({
  required double vpip,
  required double pfr,
  required double handScore,
}) {
  final type = classifyOpponent(vpip, pfr);
  switch (type) {
    case PlayerType.fish:
      // Loose-passive: mehr Value, kein Bluff nötig
      return handScore > 0.5 ? 0.08 : -0.05;
    case PlayerType.lag:
      // Loose-aggressive: Traps, weniger bluff-raises
      return handScore > 0.7 ? 0.05 : -0.08;
    case PlayerType.nit:
      // Tight-passive: c-bets profitabler, Bluffs funktionieren besser
      return 0.06;
    case PlayerType.reg:
      // Tight-aggressive: standard, leicht defensiver
      return -0.03;
  }
}

// ─── UI Widget ────────────────────────────────────────────────────────────────

class OpponentModelWidget extends StatefulWidget {
  final ValueChanged<double> onVpipChanged;
  final ValueChanged<double> onPfrChanged;
  final double initialVpip;
  final double initialPfr;

  const OpponentModelWidget({
    super.key,
    required this.onVpipChanged,
    required this.onPfrChanged,
    this.initialVpip = 25,
    this.initialPfr  = 12,
  });

  @override
  State<OpponentModelWidget> createState() => _OpponentModelWidgetState();
}

class _OpponentModelWidgetState extends State<OpponentModelWidget> {
  late double _vpip;
  late double _pfr;

  static const Color _primary = Color(0xFF00ff88);
  static const Color _panel   = Color(0xFF16213e);

  @override
  void initState() {
    super.initState();
    _vpip = widget.initialVpip;
    _pfr  = widget.initialPfr;
  }

  PlayerType get _playerType => classifyOpponent(_vpip, _pfr);

  @override
  Widget build(BuildContext context) {
    final pt    = _playerType;
    final color = pt.color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GEGNER PROFIL',
                style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Text(
                  pt.label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // VPIP Slider
          _buildSlider(
            label: 'VPIP',
            value: _vpip,
            hint: '${_vpip.toStringAsFixed(0)}%',
            color: _primary,
            onChanged: (v) {
              setState(() => _vpip = v);
              // Ensure PFR never exceeds VPIP
              if (_pfr > _vpip) {
                setState(() => _pfr = _vpip);
                widget.onPfrChanged(_pfr);
              }
              widget.onVpipChanged(v);
            },
          ),

          // PFR Slider
          _buildSlider(
            label: 'PFR',
            value: _pfr,
            hint: '${_pfr.toStringAsFixed(0)}%',
            color: Colors.orangeAccent,
            max: _vpip,
            onChanged: (v) {
              setState(() => _pfr = v);
              widget.onPfrChanged(v);
            },
          ),

          const SizedBox(height: 10),

          // Advice
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.tips_and_updates, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pt.advice,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required String hint,
    required Color color,
    double max = 100,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(hint, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: Colors.grey.shade800,
            overlayColor: color.withOpacity(0.2),
          ),
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            divisions: max.toInt(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
