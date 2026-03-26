// opponent_model.dart — FEATURE 1: Opponent Modeling
// VPIP / PFR tracking + player type badge
// FEATURE: Animated Fish Detector Badge + Bluff-O-Meter Gauge

import 'package:flutter/material.dart';
import 'dart:math';

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
      return handScore > 0.5 ? 0.08 : -0.05;
    case PlayerType.lag:
      return handScore > 0.7 ? 0.05 : -0.08;
    case PlayerType.nit:
      return 0.06;
    case PlayerType.reg:
      return -0.03;
  }
}

// ─── Fish Detector Badge (Animated) ──────────────────────────────────────────

class FishDetectorBadge extends StatefulWidget {
  final PlayerType playerType;

  const FishDetectorBadge({super.key, required this.playerType});

  @override
  State<FishDetectorBadge> createState() => _FishDetectorBadgeState();
}

class _FishDetectorBadgeState extends State<FishDetectorBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _waveAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _waveAnim = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFish = widget.playerType == PlayerType.fish;
    final color = widget.playerType.color;

    if (!isFish) {
      // Normal badge for non-fish
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(
          widget.playerType.label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    }

    // Animated Fish Badge
    return AnimatedBuilder(
      animation: _waveAnim,
      builder: (context, child) {
        final swimOffset = sin(_waveAnim.value) * 5.0;

        return Transform.translate(
          offset: Offset(swimOffset, 0),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0D47A1).withOpacity(0.9),
                  const Color(0xFF1565C0).withOpacity(0.85),
                  const Color(0xFF0277BD).withOpacity(0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF4FC3F7),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4FC3F7)
                      .withOpacity(0.4 + sin(_waveAnim.value) * 0.2),
                  blurRadius: 8 + sin(_waveAnim.value) * 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wackelndes Fisch-Emoji
                Transform.rotate(
                  angle: sin(_waveAnim.value) * 0.25,
                  child: const Text(
                    '🐟',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'FISH DETECTED',
                  style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Bluff-O-Meter ────────────────────────────────────────────────────────────

class BluffOMeter extends StatefulWidget {
  final bool isBluff;
  final double score;       // 0.0–1.0 hand score
  final int boardDanger;    // 0–10

  const BluffOMeter({
    super.key,
    required this.isBluff,
    required this.score,
    required this.boardDanger,
  });

  /// Bluff risk: 0.0–1.0
  static double calcBluffRisk({
    required bool isBluff,
    required double score,
    required int boardDanger,
  }) {
    double risk = 0.0;
    if (isBluff) risk += 0.45;
    // Low score = more likely bluffing
    risk += (1.0 - score.clamp(0.0, 1.0)) * 0.35;
    // Board danger contributes
    risk += (boardDanger / 10.0) * 0.20;
    return risk.clamp(0.0, 1.0);
  }

  @override
  State<BluffOMeter> createState() => _BluffOMeterState();
}

class _BluffOMeterState extends State<BluffOMeter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _needleAnim;
  double _currentRisk = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _currentRisk = BluffOMeter.calcBluffRisk(
      isBluff: widget.isBluff,
      score: widget.score,
      boardDanger: widget.boardDanger,
    );
    _needleAnim = Tween<double>(begin: _currentRisk, end: _currentRisk)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(BluffOMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newRisk = BluffOMeter.calcBluffRisk(
      isBluff: widget.isBluff,
      score: widget.score,
      boardDanger: widget.boardDanger,
    );
    if (newRisk != _currentRisk) {
      final from = _currentRisk;
      _currentRisk = newRisk;
      _needleAnim = Tween<double>(begin: from, end: newRisk)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _riskColor(double risk) {
    if (risk < 0.3) return const Color(0xFF4CAF50);
    if (risk < 0.7) return const Color(0xFFFFB300);
    return const Color(0xFFF44336);
  }

  String _riskLabel(double risk) {
    if (risk < 0.3) return 'Safe 😎';
    if (risk < 0.7) return 'Risky 🤔';
    return 'YOLO 😈';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _needleAnim,
      builder: (context, _) {
        final risk = _needleAnim.value;
        final color = _riskColor(risk);
        final label = _riskLabel(risk);
        final pct = (risk * 100).toStringAsFixed(0);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16213e),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Column(
            children: [
              const Text(
                'BLUFF-O-METER',
                style: TextStyle(
                    color: Colors.grey, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              // Tachometer
              SizedBox(
                width: 200,
                height: 110,
                child: CustomPaint(
                  painter: _GaugePainter(risk: risk),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$pct% Bluff-Risiko',
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double risk; // 0.0–1.0

  _GaugePainter({required this.risk});

  Color _colorForAngle(double fraction) {
    if (fraction < 0.3) return const Color(0xFF4CAF50);
    if (fraction < 0.7) return const Color(0xFFFFB300);
    return const Color(0xFFF44336);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height - 10;
    final radius = size.width / 2 - 10;

    // Draw arc segments: green → yellow → red
    final segmentCount = 60;
    final sweepPerSeg = pi / segmentCount;
    for (int i = 0; i < segmentCount; i++) {
      final fraction = i / segmentCount;
      final startAngle = pi + fraction * pi;
      final color = _colorForAngle(fraction);
      final paint = Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        startAngle,
        sweepPerSeg,
        false,
        paint,
      );
    }

    // Draw filled progress arc
    final progressPaint = Paint()
      ..color = _colorForAngle(risk).withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      pi,
      risk * pi,
      false,
      progressPaint,
    );

    // Draw inner track
    final trackPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius - 14),
      pi,
      pi,
      false,
      trackPaint,
    );

    // Draw needle
    final needleAngle = pi + risk * pi;
    final needleLength = radius - 18;
    final needleX = cx + needleLength * cos(needleAngle);
    final needleY = cy + needleLength * sin(needleAngle);

    final needleColor = _colorForAngle(risk);
    final needlePaint = Paint()
      ..color = needleColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), Offset(needleX, needleY), needlePaint);

    // Center dot
    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()..color = needleColor,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      3,
      Paint()..color = Colors.white,
    );

    // Labels: 0% and 100%
    final textStyle = TextStyle(
        color: Colors.grey.shade500, fontSize: 10);
    final tp0 = TextPainter(
        text: TextSpan(text: '0%', style: textStyle),
        textDirection: TextDirection.ltr)
      ..layout();
    tp0.paint(canvas, Offset(2, cy - 14));

    final tp100 = TextPainter(
        text: TextSpan(text: '100%', style: textStyle),
        textDirection: TextDirection.ltr)
      ..layout();
    tp100.paint(canvas, Offset(size.width - tp100.width - 2, cy - 14));
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.risk != risk;
}

// ─── UI Widget ────────────────────────────────────────────────────────────────

class OpponentModelWidget extends StatefulWidget {
  final ValueChanged<double> onVpipChanged;
  final ValueChanged<double> onPfrChanged;
  final double initialVpip;
  final double initialPfr;

  // For Bluff-O-Meter
  final bool isBluff;
  final double score;
  final int boardDanger;
  final int street;

  const OpponentModelWidget({
    super.key,
    required this.onVpipChanged,
    required this.onPfrChanged,
    this.initialVpip = 25,
    this.initialPfr  = 12,
    this.isBluff = false,
    this.score = 0.5,
    this.boardDanger = 0,
    this.street = 0,
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
    final showBluffOMeter = widget.street > 0 || widget.isBluff;

    return Column(
      children: [
        Container(
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
                  // Animated Fish Badge or normal badge
                  FishDetectorBadge(playerType: pt),
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
        ),

        // Bluff-O-Meter (only from Flop onwards or when isBluff = true)
        if (showBluffOMeter) ...[
          const SizedBox(height: 8),
          BluffOMeter(
            isBluff: widget.isBluff,
            score: widget.score,
            boardDanger: widget.boardDanger,
          ),
        ],
      ],
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
