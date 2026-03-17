import 'package:flutter/material.dart';

void main() => runApp(const OttoApp());

class AC { 
  static const Color P = Color(0xFF00FF88); 
  static const Color BG = Color(0xFF1A1A2E); 
  static const Color PN = Color(0xFF16213E); 
}

class OttoApp extends StatelessWidget {
  const OttoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Otto Poker',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: AC.BG),
    home: const MN()
  );
}

class MN extends StatefulWidget {
  const MN({super.key});
  @override
  State<MN> createState() => _MNState();
}

class _MNState extends State<MN> {
  int seite = 0;
  List meineKarten = [];
  List tischKarten = [];
  
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min, children: [Text('🦦 Otto'), Text(' Poker', style: TextStyle(fontWeight: FontWeight.bold))]), centerTitle: true, backgroundColor: AC.PN),
    body: IndexedStack(index: seite, children: [
      Empfehlung(meineKarten: meineKarten, tischKarten: tischKarten),
      KartenEingabe(titel: 'Meine 2 Karten', max: 2, Karten: meineKarten, onSave: (k) => setState(() => meineKarten = k)),
      KartenEingabe(titel: 'Tisch (5 Karten)', max: 5, Karten: tischKarten, onSave: (k) => setState(() => tischKarten = k)),
    ]),
    bottomNavigationBar: BottomNavigationBar(currentIndex: seite, onTap: (s) => setState(() => seite = s), selectedItemColor: AC.P, backgroundColor: AC.PN, items: const [
      BottomNavigationBarItem(icon: Icon(Icons.calculate), label: 'Empfehlung'),
      BottomNavigationBarItem(icon: Icon(Icons.credit_card), label: 'Meine Karten'),
      BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'Tisch'),
    ]),
  );
}

class Empfehlung extends StatefulWidget {
  final List meineKarten, tischKarten;
  const Empfehlung({super.key, required this.meineKarten, required this.tischKarten});
  @override
  State<Empfehlung> createState() => _EmpfehlungState();
}

class _EmpfehlungState extends State<Empfehlung> {
  int position = 2, handRang = 0;
  double pot = 100, zuZahlen = 20, stack = 200;
  String empfehlung = '';
  final positionen = ['Big Blind', 'Small Blind', 'Button', 'Cutoff', 'MP', 'UTG'];

  void berechne() {
    double staerke = (handRang / 8) * 0.5 + ((6 - position) / 6) * 0.3 + 0.2;
    if (stack < 20) staerke -= 0.2;
    double potOdds = zuZahlen > 0 ? zuZahlen / (pot + zuZahlen) : 0;
    bool einsatz = potOdds < (handRang / 8);
    if (zuZahlen > stack * 0.4) empfehlung = 'PASSEN';
    else if (staerke > 0.7) empfehlung = stack < 40 ? 'ALL-IN' : 'ERHOHEN';
    else if (staerke > 0.45) empfehlung = einsatz ? 'MITGEHEN' : 'CHECK';
    else empfehlung = zuZahlen == 0 ? 'CHECK' : 'PASSEN';
    setState(() {});
  }

  void bewerteHand() {
    if (widget.meineKarten.isEmpty) { handRang = 0; return; }
    List werte = [...widget.meineKarten.map((k) => k['r']), ...widget.tischKarten.map((k) => k['r'])];
    List farben = [...widget.meineKarten.map((k) => k['s']), ...widget.tischKarten.map((k) => k['s'])];
    Map zaehlerW = {};
    Map zaehlerF = {};
    for (var w in werte) zaehlerW[w] = (zaehlerW[w] ?? 0) + 1;
    for (var f in farben) zaehlerF[f] = (zaehlerF[f] ?? 0) + 1;
    if (zaehlerF.values.any((z) => z >= 5)) handRang = 5;
    else if (zaehlerW.values.any((z) => z >= 4)) handRang = 7;
    else if (zaehlerW.values.any((z) => z == 3) && zaehlerW.values.any((z) => z >= 2)) handRang = 6;
    else if (zaehlerW.values.any((z) => z == 3)) handRang = 3;
    else handRang = zaehlerW.values.where((z) => z == 2).length >= 2 ? 2 : (zaehlerW.values.any((z) => z == 2) ? 1 : 0);
  }

  String handName(int r) => ['Höchste Karte', 'Ein Paar', 'Two Pair', 'Drilling', 'Straße', 'Flush', 'Full House', 'Vierling', 'Straße Flush'][r.clamp(0, 8)];

  @override
  Widget build(BuildContext context) {
    bewerteHand();
    String strasse = widget.tischKarten.isEmpty ? 'Pre-Flop' : widget.tischKarten.length == 3 ? 'Flop' : widget.tischKarten.length == 4 ? 'Turn' : 'River';
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(16)), child: Column(children: [
        const Text('🃏 MEINE KARTEN', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: widget.meineKarten.isEmpty ? [const Text('Noch keine', style: TextStyle(fontSize: 24, color: Colors.grey))] : widget.meineKarten.map<Widget>((k) => Spielkarte(rang: k['r'], farbe: k['s'])).toList()),
      ])),
      const SizedBox(height: 16),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(16)), child: Column(children: [
        Text('🃏 TISCH (${widget.tischKarten.length})', style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: widget.tischKarten.isEmpty ? [const Text('Noch keine', style: TextStyle(fontSize: 24, color: Colors.grey))] : widget.tischKarten.map<Widget>((k) => Spielkarte(rang: k['r'], farbe: k['s'])).toList()),
      ])),
      const SizedBox(height: 20),
      if (widget.meineKarten.isNotEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AC.P.withAlpha(26), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text('🎯 Deine Hand: ' + handName(handRang), style: const TextStyle(color: AC.P, fontSize: 18, fontWeight: FontWeight.bold)), Text('Straße: ' + strasse, style: const TextStyle(color: Colors.grey, fontSize: 14))])),
      const SizedBox(height: 20),
      if (empfehlung.isNotEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: LinearGradient(colors: empfehlung == 'ALL-IN' ? [Colors.red, Colors.red.shade700] : [AC.P, AC.P.withAlpha(179)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)), child: Column(children: [const Text('👉 EMPFEHLUNG', style: TextStyle(fontSize: 14, color: Colors.black54)), const SizedBox(height: 8), Text(empfehlung, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.black))])),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(12)), child: Column(children: [
        Row(children: [const SizedBox(width: 100, child: Text('📍 Position:', style: TextStyle(color: Colors.white70))), Expanded(child: DropdownButton<int>(value: position, isExpanded: true, underline: const SizedBox(), dropdownColor: AC.PN, items: List.generate(positionen.length, (i) => DropdownMenuItem(value: i, child: Text(positionen[i]))), onChanged: (v) => setState(() => position = v ?? 2)))]),
        const SizedBox(height: 12),
        Row(children: [SizedBox(width: 100, child: Text('💰 Pot: ${pot.toInt()}€', style: const TextStyle(color: Colors.white70))), Expanded(child: Slider(value: pot, min: 0, max: 500, activeColor: AC.P, onChanged: (v) => setState(() => pot = v)))]),
        Row(children: [SizedBox(width: 100, child: Text('💵 Zu zahlen: ${zuZahlen.toInt()}€', style: const TextStyle(color: Colors.white70))), Expanded(child: Slider(value: zuZahlen, min: 0, max: 200, activeColor: AC.P, onChanged: (v) => setState(() => zuZahlen = v)))]),
        Row(children: [SizedBox(width: 100, child: Text('🎒 Stack: ${stack.toInt()}€', style: const TextStyle(color: Colors.white70))), Expanded(child: Slider(value: stack, min: 0, max: 500, activeColor: AC.P, onChanged: (v) => setState(() => stack = v)))]),
      ])),
      const SizedBox(height: 16),
      SizedBox(height: 60, child: ElevatedButton(onPressed: berechne, style: ElevatedButton.styleFrom(backgroundColor: AC.P, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calculate, size: 28), SizedBox(width: 12), Text('EMPFEHLUNG BERECHNEN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))),
    ]));
  }
}

class Spielkarte extends StatelessWidget {
  final String rang, farbe;
  const Spielkarte({super.key, required this.rang, required this.farbe});
  @override
  Widget build(BuildContext context) {
    bool rot = farbe == 'HEARTS' || farbe == 'DIAMONDS';
    String symbol = farbe == 'SPADES' ? '♠' : farbe == 'HEARTS' ? '♥' : farbe == 'DIAMONDS' ? '♦' : '♣';
    return Container(width: 70, height: 100, margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: rot ? Colors.white : Colors.black, borderRadius: BorderRadius.circular(10), border: Border.all(color: rot ? Colors.red : Colors.white, width: 3)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(rang, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: rot ? Colors.red : Colors.white)), Text(symbol, style: TextStyle(fontSize: 32, color: rot ? Colors.red : Colors.white))]));
  }
}

class KartenEingabe extends StatefulWidget {
  final String titel;
  final int max;
  final List Karten;
  final Function(List) onSave;
  const KartenEingabe({super.key, required this.titel, required this.max, required this.Karten, required this.onSave});
  @override
  State<KartenEingabe> createState() => _KartenEingabeState();
}

class _KartenEingabeState extends State<KartenEingabe> {
  List karten = [];
  final rangWerte = ['A', 'K', 'Q', 'J', '10', '9', '8', '7', '6', '5', '4', '3', '2'];
  final farbenMap = {'SPADES': '♠', 'HEARTS': '♥', 'DIAMONDS': '♦', 'CLUBS': '♣'};
  final farbFarbe = {'SPADES': Colors.black, 'HEARTS': Colors.red, 'DIAMONDS': Colors.red, 'CLUBS': Colors.black};

  @override
  void initState() { super.initState(); karten = List.from(widget.Karten); }
  
  void addKarte(String r, String f) {
    if (karten.length < widget.max && !karten.any((k) => k['r'] == r && k['s'] == f)) {
      setState(() => karten.add({'r': r, 's': f}));
    }
  }

  void farbeWaehlen(BuildContext ctx, String rang) {
    showModalBottomSheet(context: ctx, backgroundColor: AC.PN, builder: (c) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("Wähle die Farbe:", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: farbenMap.entries.map((e) => GestureDetector(
        onTap: () { addKarte(rang, e.key); Navigator.pop(c); },
        child: Container(width: 60, height: 80, decoration: BoxDecoration(color: farbFarbe[e.key], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text(e.value, style: const TextStyle(fontSize: 40, color: Colors.white))))
      )).toList())
    ])));
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> rangButtons = [];
    for (var r in rangWerte) {
      rangButtons.add(GestureDetector(
        onTap: () => farbeWaehlen(context, r),
        child: Container(width: 55, height: 75, decoration: BoxDecoration(color: AC.PN, borderRadius: BorderRadius.circular(10), border: Border.all(color: AC.P, width: 2)), child: Center(child: Text(r, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold))))
      ));
    }
    
    List<Widget> ausgewaehlt = [];
    for (var i = 0; i < karten.length; i++) {
      ausgewaehlt.add(GestureDetector(
        onTap: () => setState(() => karten.removeAt(i)),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: farbFarbe[karten[i]['s']], borderRadius: BorderRadius.circular(8)), child: Text(karten[i]['r'] + farbenMap[karten[i]['s']]!, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)))
      ));
    }

    return Column(children: [
      if (karten.isNotEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: AC.PN, borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))), child: Column(children: [
        Text('Ausgewählt: ${karten.length}/${widget.max}', style: const TextStyle(color: AC.P, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 12, children: karten.map<Widget>((k) => GestureDetector(onTap: () => setState(() => karten.remove(k)), child: Spielkarte(rang: k['r'], farbe: k['s']))).toList()),
      ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('🎴 Wähle die Kartenwerte:', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: rangButtons),
        const SizedBox(height: 24),
        if (karten.isNotEmpty) ...[const Text('✖️ Tippe auf eine Karte zum Entfernen:', style: TextStyle(color: Colors.white70)), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: ausgewaehlt), const SizedBox(height: 16)],
        SizedBox(height: 60, child: ElevatedButton(onPressed: () { widget.onSave(karten); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: AC.P, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.save, size: 24), SizedBox(width: 12), Text('SPEICHERN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]))),
      ]))),
    ]);
  }
}
