// pot_odds.dart — FEATURE 2: Pot Odds Anzeige
// Berechnet Pot Odds und zeigt +EV / -EV

import 'package:flutter/material.dart';

// ─── Logic ────────────────────────────────────────────────────────────────────

class PotOddsResult {
  final double potOddsPercent;    // z.B. 25.0  → Call kostet 25% des neuen Pots
  final double requiredEquity;    // break-even equity (gleich wie pot odds bei einfachem Call)
  final bool   isPositiveEv;
  final double callAmount;
  final double totalPot;

  const PotOddsResult({
    required this.potOddsPercent,
    required this.requiredEquity,
    required this.isPositiveEv,
    required this.callAmount,
    required this.totalPot,
  });
}

/// [currentEquityPercent] = aktuelle Hand-Stärke als Prozentzahl (0–100)
PotOddsResult calculatePotOdds({
  required double potSize,
  required double betSize,
  required double currentEquityPercent,
}) {
  if (betSize <= 0) {
    return PotOddsResult(
      potOddsPercent: 0,
      requiredEquity: 0,
      isPositiveEv: true,
      callAmount: 0,
      totalPot: potSize,
    );
  }

  final totalPot       = potSize + betSize;
  // Pot Odds = call / (pot + call) → Anteil den du ins Verhältnis zum Gesamtpot gibst
  final potOddsPercent = (betSize / totalPot) * 100;
  // Break-even Equity = pot odds percent (mathematisch identisch für einfachen Call)
  final requiredEquity = potOddsPercent;
  final isPositiveEv   = currentEquityPercent >= requiredEquity;

  return PotOddsResult(
    potOddsPercent: potOddsPercent,
    requiredEquity: requiredEquity,
    isPositiveEv: isPositiveEv,
    callAmount: betSize,
    totalPot: totalPot,
  );
}

// ─── UI Widget ────────────────────────────────────────────────────────────────

class PotOddsWidget extends StatefulWidget {
  /// Aktuelle Hand-Equity in % (0–100) — z.B. aus Hand-Rank abgeleitet
  final double handEquityPercent;

  const PotOddsWidget({super.key, required this.handEquityPercent});

  @override
  State<PotOddsWidget> createState() => _PotOddsWidgetState();
}

class _PotOddsWidgetState extends State<PotOddsWidget> {
  double _potSize = 100;
  double _betSize = 30;

  static const Color _panel   = Color(0xFF16213e);
  static const Color _primary = Color(0xFF00ff88);

  @override
  Widget build(BuildContext context) {
    final result = calculatePotOdds(
      potSize: _potSize,
      betSize: _betSize,
      currentEquityPercent: widget.handEquityPercent,
    );

    final evColor = result.isPositiveEv ? Colors.green.shade400 : Colors.red.shade400;
    final evLabel = result.isPositiveEv ? '+EV ✅' : '-EV ❌';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: evColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'POT ODDS RECHNER',
            style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
          ),
          const SizedBox(height: 12),

          // Input Sliders
          _buildSlider(
            label: 'Pot-Größe',
            value: _potSize,
            max: 1000,
            onChanged: (v) => setState(() => _potSize = v),
            color: _primary,
          ),
          _buildSlider(
            label: 'Gegner Bet',
            value: _betSize,
            max: 500,
            onChanged: (v) => setState(() => _betSize = v),
            color: Colors.orangeAccent,
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.grey),
          const SizedBox(height: 8),

          // Results
          _buildResultRow(
            'Pot Odds',
            '${result.potOddsPercent.toStringAsFixed(1)}%',
            Colors.white,
          ),
          const SizedBox(height: 6),
          _buildResultRow(
            'Benötigte Equity',
            '${result.requiredEquity.toStringAsFixed(1)}%',
            Colors.white70,
          ),
          const SizedBox(height: 6),
          _buildResultRow(
            'Deine Equity',
            '${widget.handEquityPercent.toStringAsFixed(1)}%',
            _primary,
          ),

          const SizedBox(height: 12),

          // EV Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: evColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: evColor),
            ),
            child: Column(
              children: [
                Text(
                  'Call \$${result.callAmount.toStringAsFixed(0)} → '
                  'benötigst ${result.requiredEquity.toStringAsFixed(1)}% Equity',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  evLabel,
                  style: TextStyle(
                    color: evColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
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
    required double max,
    required ValueChanged<double> onChanged,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(
              '\$${value.toStringAsFixed(0)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: Colors.grey.shade800,
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildResultRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
