import 'package:flutter/material.dart';

void main() => runApp(const OttoApp());

class AC { static const Color P = Color(0xFF00FF88), BG = Color(0xFF1A1A2E), PN = Color(0xFF16213E); }

class OttoApp extends StatelessWidget {
  const OttoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Otto Poker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AC.BG, primaryColor: AC.P),
    home: const MN(),
  );
}

class MN extends StatefulWidget {
  const MN({super.key});
  @override
  State<MN> createState() => _MNState();
}

class _MNState extends State<MN> {
  int i = 0;
  List myCards = [];
  List boardCards = [];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: i,
      children: [
        RecScr(myCards: myCards, boardCards: boardCards),
        ManScr(title: 'Meine 2', max: 2, onSave: (c) => setState(() => myCards = c)),
        ManScr(title: 'Tisch', max: 5, onSave: (c) => setState(() => boardCards = c)),
      ],
    ),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: i,
      onTap: (x) => setState(() => i = x),
      selectedItemColor: AC.P,
      backgroundColor: AC.PN,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.casino), label: 'Empfehlung'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Meine 2'),
        BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'Tisch'),
      ],
    ),
  );
}

class RecScr extends StatefulWidget {
  final List myCards, boardCards;
  const RecScr({super.key, required this.myCards, required this.boardCards});
  @override
  State<RecScr> createState() => _RecScrState();
}

class _RecScrState extends State<RecScr> {
  int pos = 2, hr = 0;
  double pot = 100, toCall = 20, stack = 200;
  String rec = '';
  final poss = ['BB', 'SB', 'BTN', 'CO', 'MP', 'UTG'];

  void calc() {
    double s = (hr / 8) * 0.5 + ((6 - pos) / 6) * 0.3 + 0.2;
    if (stack < 20) s -= 0.2;
    double o = toCall > 0 ? toCall / (pot + toCall) : 0;
    bool fb = o < (hr / 8);
    if (toCall > stack * 0.4) rec = 'FOLD';
    else if (s > 0.7) rec = stack < 40 ? 'ALL-IN' : 'ERHOHEN';
    else if (s > 0.45) rec = fb ? 'MITGEHEN' : 'CHECK';
    else rec = toCall == 0 ? 'CHECK' : 'FOLD';
    setState(() {});
  }

  void ev() {
    if (widget.myCards.isEmpty) { hr = 0; return; }
    List rs = [...widget.myCards.map((c) => c['r']), ...widget.boardCards.map((c) => c['r'])];
    List ss = [...widget.myCards.map((c) => c['s']), ...widget.boardCards.map((c) => c['s'])];
    Map rc = {}, sc = {};
    for (var r in rs) rc[r] = (rc[r] ?? 0) + 1;
    for (var s in ss) sc[s] = (sc[s] ?? 0) + 1;
    if (sc.values.any((c) => c >= 5)) hr = 5;
    else if (rc.values.any((c) => c >= 4)) hr = 7;
    else if (rc.values.any((c) => c == 3) && rc.values.any((c) => c >= 2)) hr = 6;
    else if (rc.values.any((c) => c == 3)) hr = 3;
    else hr = rc.values.where((c) => c == 2).length >= 2 ? 2 : (rc.values.any((c) => c == 2) ? 1 : 0);
  }

  String hn(int h) => ['High Card', 'Paar', 'Two Pair', 'Drilling', 'Strasse', 'Flush', 'Full House', 'Vierling', 'Strasse Flush'][h.clamp(0, 8)];

  @override
  Widget build(BuildContext context) {
    ev();
    String st = widget.boardCards.isEmpty ? 'Preflop' : widget.boardCards.length == 3 ? 'Flop' : widget.boardCards.length == 4 ? 'Turn' : 'River';
    return Scaffold(
      appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Otto '), Text('Poker', style: TextStyle(fontWeight: FontWeight.bold))]), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Text('MEINE 2 KARTEN', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.myCards.isEmpty 
                  ? [const Text('-', style: TextStyle(fontSize: 40, color: Colors.grey))]
                  : widget.myCards.map<Widget>((x) => VisCard(rank: x['r'], suit: x['s'])).toList(),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text('TISCH (${widget.boardCards.length})', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.boardCards.isEmpty 
                  ? [const Text('-', style: TextStyle(fontSize: 40, color: Colors.grey))]
                  : widget.boardCards.map<Widget>((x) => VisCard(rank: x['r'], suit: x['s'])).toList(),
              ),
            ]),
          ),
          if (hr > 0 || widget.myCards.isNotEmpty) Container(
            padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(color: AC.P.withAlpha(51), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.analytics, color: AC.P), const SizedBox(width: 8),
              Text('Hand: ' + hn(hr) + ' | ' + st, style: const TextStyle(color: AC.P, fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
          ),
          if (rec.isNotEmpty) Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: rec == 'ALL-IN' ? [Colors.red, Colors.red.shade700] : [AC.P, AC.P.withAlpha(179)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Text('EMPFEHLUNG', style: TextStyle(fontSize: 14, color: Colors.black54)),
              Text(rec, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black)),
            ]),
          ),
          const SizedBox(height: 20),
          dd('Position', pos, poss, (x) => setState(() => pos = x)),
          sl('Pot', pot, 500, (x) => setState(() => pot = x)),
          sl('Zu zahlen', toCall, 200, (x) => setState(() => toCall = x)),
          sl('Stack', stack, 500, (x) => setState(() => stack = x)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: calc, style: ElevatedButton.styleFrom(backgroundColor: AC.P, foregroundColor: Colors.black, padding: const EdgeInsets.all(16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('EMPFEHLUNG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  Widget dd(String l, int v, List I, Function f) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 90, child: Text(l + ':', style: const TextStyle(color: Colors.white70))),
      Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(8)),
        child: DropdownButton<int>(value: v, isExpanded: true, underline: const SizedBox(), dropdownColor: AC.PN,
          items: List.generate(I.length, (x) => DropdownMenuItem(value: x, child: Text(I[x]))), onChanged: (y) => f(y))))]),
  );

  Widget sl(String l, double v, double m, Function f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(l + ': ' + v.toStringAsFixed(0) + ' Euro', style: const TextStyle(color: Colors.white70, fontSize: 13)),
    SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: AC.P, thumbColor: AC.P, inactiveTrackColor: Colors.grey.shade800),
      child: Slider(value: v, min: 0, max: m, onChanged: (x) => f(x))),
  ]);
}

class VisCard extends StatelessWidget {
  final String rank;
  final String suit;
  const VisCard({super.key, required this.rank, required this.suit});
  
  @override
  Widget build(BuildContext context) {
    bool red = suit == 'HEARTS' || suit == 'DIAMONDS';
    Color bg = red ? Colors.white : Colors.black;
    Color fg = red ? Colors.red : Colors.white;
    String icon = suit == 'SPADES' ? '♠' : suit == 'HEARTS' ? '♥' : suit == 'DIAMONDS' ? '♦' : '♣';
    
    return Container(
      width: 60,
      height: 84,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: red ? Colors.red : Colors.white, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(77), blurRadius: 4, offset: const Offset(2, 2))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(rank, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: fg)),
        Text(icon, style: TextStyle(fontSize: 24, color: fg)),
      ]),
    );
  }
}

class ManScr extends StatefulWidget {
  final String title;
  final int max;
  final Function(List) onSave;
  const ManScr({super.key, required this.title, required this.max, required this.onSave});
  @override
  State<ManScr> createState() => _ManScrState();
}

class _ManScrState extends State<ManScr> {
  List cards = [];
  final rks = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];
  final sts = ['SPADES', 'HEARTS', 'DIAMONDS', 'CLUBS'];
  final simg = {'SPADES': '♠', 'HEARTS': '♥', 'DIAMONDS': '♦', 'CLUBS': '♣'};
  final scol = {'SPADES': Colors.black, 'HEARTS': Colors.red, 'DIAMONDS': Colors.red, 'CLUBS': Colors.black};

  void add(String r, String s) {
    if (cards.length >= widget.max) return;
    if (!cards.any((c) => c['r'] == r && c['s'] == s)) setState(() => cards.add({'r': r, 's': s}));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(children: [
      if (cards.isNotEmpty) Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AC.PN, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: cards.map<Widget>((x) => VisCard(rank: x['r'], suit: x['s'])).toList(),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Wert wahlen:', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: rks.map((r) => GestureDetector(
              onTap: () => _pick(r),
              child: Container(
                width: 50, height: 70,
                decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)),
                child: Center(child: Text(r, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold))),
              ),
            )).toList()),
            const SizedBox(height: 24),
            if (cards.isNotEmpty) ...[
              const Text('Ausgewahlt:', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: cards.asMap().entries.map((e) => GestureDetector(
                onTap: () => setState(() => cards.removeAt(e.key)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.red.shade800, borderRadius: BorderRadius.circular(8)),
                  child: Text(e.value['r'] + simg[e.value['s']], style: const TextStyle(fontSize: 18, color: Colors.white)),
                ),
              )).toList()),
              const SizedBox(height: 16),
            ],
            ElevatedButton(onPressed: () => widget.onSave(cards), style: ElevatedButton.styleFrom(backgroundColor: AC.P, foregroundColor: Colors.black, padding: const EdgeInsets.all(16)),
              child: Text('SPEICHERN (' + cards.length.toString() + '/' + widget.max.toString() + ')', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ]),
        ),
      ),
    ]),
  );

  void _pick(String r) {
    showModalBottomSheet(context: context, backgroundColor: AC.PN,
      builder: (ctx) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Farbe wahlen:', style: TextStyle(fontSize: 18, color: Colors.white)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: sts.map((s) => GestureDetector(
          onTap: () { add(r, s); Navigator.pop(ctx); },
          child: Container(
            width: 60, height: 80,
            decoration: BoxDecoration(color: s == 'HEARTS' || s == 'DIAMONDS' ? Colors.red : Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 2)),
            child: Center(child: Text(simg[s]!, style: const TextStyle(fontSize: 36, color: Colors.white))),
          ),
        )).toList()),
        const SizedBox(height: 20),
      ])),
    );
  }
}