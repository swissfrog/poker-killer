// preflop_chart.dart — FEATURE 5: Preflop Range Chart
// 6x6 Tabelle der stärksten Starthände mit positionsabhängiger Färbung

import 'package:flutter/material.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

enum HandStatus { play, marginal, fold }

extension HandStatusExtension on HandStatus {
  Color get color {
    switch (this) {
      case HandStatus.play:     return const Color(0xFF00C853); // Grün
      case HandStatus.marginal: return const Color(0xFFFFAB00); // Gelb
      case HandStatus.fold:     return const Color(0xFFD50000); // Rot
    }
  }

  String get label {
    switch (this) {
      case HandStatus.play:     return 'Play';
      case HandStatus.marginal: return 'Mar.';
      case HandStatus.fold:     return 'Fold';
    }
  }
}

/// Vereinfachte 6x6 Matrix: Reihen = Suit combo (ss, os), Spalten = Rang-Paar
/// Wir verwenden die 36 stärksten Preflop-Hände als NxM-Grid dargestellt.
///
/// Positionen: 0=BB, 1=SB, 2=BTN, 3=CO, 4=MP, 5=UTG
/// Je enger die Position, desto weniger Hände werden gespielt.

// Karten-Kürzel für 6x6 Grid (Reihe x Spalte)
// Format: [suited/offsuit marker + Karten], z.B. "AKs", "QJo"
const List<String> _gridLabels = [
  'AA',  'KK',  'QQ',  'JJ',  'TT',  '99',
  'AKs', 'AQs', 'AJs', 'ATs', 'KQs', 'KJs',
  'AKo', 'AQo', 'AJo', 'KQo', 'QJs', 'JTs',
  'TT+', '99',  '88',  '77',  'T9s', '98s',
  'A9s', 'A8s', 'KTs', 'QTs', 'JTo', 'T9o',
  'A5s', 'A4s', 'K9s', 'Q9s', 'J9s', '87s',
];

/// Gibt den Status einer Hand je nach Position zurück.
HandStatus getHandStatus(String hand, int position) {
  // Premium Hände: immer spielbar
  const always = {'AA', 'KK', 'QQ', 'JJ', 'AKs', 'AKo'};
  // Starke Hände: ab MP (position <= 4)
  const strong = {'TT', 'AQs', 'AQo', 'KQs'};
  // Gute Hände: ab CO (position <= 3)
  const good   = {'99', 'AJs', 'AJo', 'KJs', 'QJs', 'JTs', 'TT+'};
  // Breite Hände: nur BTN/SB (position <= 1 oder == 2)
  const wide   = {'88', '77', 'A9s', 'A8s', 'KTs', 'QTs', 'T9s', '98s'};
  // Stealing Hände: nur BTN (position == 2) / SB (position == 1)
  const steal  = {'A5s', 'A4s', 'K9s', 'Q9s', 'J9s', '87s',
                  'JTo', 'T9o', 'KQo'};

  if (always.contains(hand)) return HandStatus.play;

  if (strong.contains(hand)) {
    if (position <= 4) return HandStatus.play;
    return HandStatus.marginal; // UTG = marginal
  }

  if (good.contains(hand)) {
    if (position <= 3) return HandStatus.play;
    if (position == 4) return HandStatus.marginal;
    return HandStatus.fold;
  }

  if (wide.contains(hand)) {
    if (position <= 2) return HandStatus.play;
    if (position <= 3) return HandStatus.marginal;
    return HandStatus.fold;
  }

  if (steal.contains(hand)) {
    if (position <= 1) return HandStatus.play;    // BTN, SB
    if (position == 2) return HandStatus.marginal; // CO
    return HandStatus.fold;
  }

  return HandStatus.fold;
}

// ─── UI Widget ────────────────────────────────────────────────────────────────

class PreflopChartScreen extends StatefulWidget {
  final int initialPosition;
  const PreflopChartScreen({super.key, this.initialPosition = 2});

  @override
  State<PreflopChartScreen> createState() => _PreflopChartScreenState();
}

class _PreflopChartScreenState extends State<PreflopChartScreen> {
  static const Color _bg    = Color(0xFF1a1a2e);
  static const Color _panel = Color(0xFF16213e);

  final List<String> _positions = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];
  late int _position;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('🃏 Preflop Range Chart'),
        backgroundColor: _panel,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Position Selector
            _buildPositionSelector(),
            const SizedBox(height: 16),

            // Legend
            _buildLegend(),
            const SizedBox(height: 12),

            // 6x6 Grid
            Expanded(
              child: _buildGrid(),
            ),

            const SizedBox(height: 12),
            _buildSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(_positions.length, (i) {
          final selected = _position == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _position = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF00ff88) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _positions[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: HandStatus.values.map((s) {
        return Row(
          children: [
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(s.label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      itemCount: _gridLabels.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (ctx, i) {
        final hand   = _gridLabels[i];
        final status = getHandStatus(hand, _position);
        final color  = status.color;

        return Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Text(
              hand,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary() {
    final playCount     = _gridLabels.where((h) => getHandStatus(h, _position) == HandStatus.play).length;
    final marginalCount = _gridLabels.where((h) => getHandStatus(h, _position) == HandStatus.marginal).length;
    final foldCount     = _gridLabels.where((h) => getHandStatus(h, _position) == HandStatus.fold).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSummaryChip('Play',     playCount.toString(),     Colors.green.shade400),
          _buildSummaryChip('Marginal', marginalCount.toString(), Colors.amber),
          _buildSummaryChip('Fold',     foldCount.toString(),     Colors.red.shade400),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String count, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
