// hand_history.dart — FEATURE 3: Hand History
// Speichert Empfehlungen lokal via SharedPreferences (JSON)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class HandRecord {
  final String id;
  final DateTime date;
  final String hand;         // z.B. "AK"
  final String position;     // z.B. "BTN"
  final double stack;
  final String recommendation; // FOLD / CALL / RAISE / ALL-IN
  final String? action;      // was der User tatsächlich getan hat
  final String? result;      // optional: "Win" / "Loss" / "+$150"

  const HandRecord({
    required this.id,
    required this.date,
    required this.hand,
    required this.position,
    required this.stack,
    required this.recommendation,
    this.action,
    this.result,
  });

  Map<String, dynamic> toJson() => {
    'id':             id,
    'date':           date.toIso8601String(),
    'hand':           hand,
    'position':       position,
    'stack':          stack,
    'recommendation': recommendation,
    'action':         action,
    'result':         result,
  };

  factory HandRecord.fromJson(Map<String, dynamic> json) => HandRecord(
    id:             json['id'] as String,
    date:           DateTime.parse(json['date'] as String),
    hand:           json['hand'] as String,
    position:       json['position'] as String,
    stack:          (json['stack'] as num).toDouble(),
    recommendation: json['recommendation'] as String,
    action:         json['action'] as String?,
    result:         json['result'] as String?,
  );
}

// ─── Service ──────────────────────────────────────────────────────────────────

class HandHistoryService {
  static const String _key = 'hand_history_v1';
  static const int    _maxRecords = 20;

  static Future<List<HandRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_key);
    if (raw == null) return [];
    final list  = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HandRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(List<HandRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final data  = jsonEncode(records.map((r) => r.toJson()).toList());
    await prefs.setString(_key, data);
  }

  static Future<void> addRecord(HandRecord record) async {
    final records = await load();
    records.insert(0, record);
    if (records.length > _maxRecords) records.removeLast();
    await save(records);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// ─── Statistics Helper ────────────────────────────────────────────────────────

class HandStats {
  final int total;
  final int folds;
  final int calls;
  final int raises;

  const HandStats({
    required this.total,
    required this.folds,
    required this.calls,
    required this.raises,
  });

  double get foldPct  => total > 0 ? folds  / total * 100 : 0;
  double get callPct  => total > 0 ? calls  / total * 100 : 0;
  double get raisePct => total > 0 ? raises / total * 100 : 0;

  static HandStats fromRecords(List<HandRecord> records) {
    int folds   = 0;
    int calls   = 0;
    int raises  = 0;
    for (final r in records) {
      final action = (r.action ?? r.recommendation).toUpperCase();
      if (action.contains('FOLD'))                     folds++;
      else if (action.contains('CALL') || action.contains('CHECK')) calls++;
      else                                             raises++;
    }
    return HandStats(total: records.length, folds: folds, calls: calls, raises: raises);
  }
}

// ─── UI Screen ────────────────────────────────────────────────────────────────

class HandHistoryScreen extends StatefulWidget {
  const HandHistoryScreen({super.key});

  @override
  State<HandHistoryScreen> createState() => _HandHistoryScreenState();
}

class _HandHistoryScreenState extends State<HandHistoryScreen> {
  static const Color _primary = Color(0xFF00ff88);
  static const Color _panel   = Color(0xFF16213e);
  static const Color _bg      = Color(0xFF1a1a2e);

  List<HandRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await HandHistoryService.load();
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('History löschen?'),
        content: const Text('Alle gespeicherten Hände werden gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await HandHistoryService.clearAll();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = HandStats.fromRecords(_records);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('📋 Hand History'),
        backgroundColor: _panel,
        actions: [
          if (_records.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildStatsCard(stats),
                    const SizedBox(height: 16),
                    const Text(
                      'LETZTE 20 HÄNDE',
                      style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    ..._records.map(_buildHandTile),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Noch keine Hände gespeichert',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Empfehlungen werden automatisch gespeichert.',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatsCard(HandStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: _primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'STATISTIKEN (${stats.total} Hände)',
                style: const TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatBar('FOLD',  stats.foldPct,  Colors.red.shade600),
          _buildStatBar('CALL',  stats.callPct,  Colors.green.shade500),
          _buildStatBar('RAISE', stats.raisePct, Colors.blue.shade400),
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${pct.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandTile(HandRecord r) {
    final recColor = _recColor(r.recommendation);
    final dateStr  = '${r.date.day.toString().padLeft(2,'0')}.'
                     '${r.date.month.toString().padLeft(2,'0')}. '
                     '${r.date.hour.toString().padLeft(2,'0')}:'
                     '${r.date.minute.toString().padLeft(2,'0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: recColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Empfehlungs-Badge
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: recColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: recColor),
            ),
            child: Text(
              r.recommendation.length > 5 ? r.recommendation.substring(0, 5) : r.recommendation,
              textAlign: TextAlign.center,
              style: TextStyle(color: recColor, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.hand,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(r.position,
                          style: const TextStyle(color: Colors.grey, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Stack: \$${r.stack.toStringAsFixed(0)}'
                  '${r.result != null ? " · ${r.result}" : ""}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }

  Color _recColor(String rec) {
    switch (rec.toUpperCase()) {
      case 'FOLD':    return Colors.red.shade400;
      case 'CALL':
      case 'CHECK':   return Colors.green.shade400;
      case 'RAISE':   return Colors.blue.shade400;
      case 'ALL-IN':  return Colors.deepOrange;
      default:        return Colors.grey;
    }
  }
}
