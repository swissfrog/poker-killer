import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(PokerVisionApp(cameras: cameras));
}

class PokerVisionApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const PokerVisionApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Poker Vision',
      theme: ThemeData.dark(),
      home: PokerVisionScreen(cameras: cameras),
    );
  }
}

class PokerVisionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const PokerVisionScreen({super.key, required this.cameras});

  @override
  State<PokerVisionScreen> createState() => _PokerVisionScreenState();
}

class _PokerVisionScreenState extends State<PokerVisionScreen> {
  CameraController? _controller;
  List<String> _playerCards = [];
  List<String> _communityCards = [];
  String _recommendation = "Warte auf Karten...";
  double _handStrength = 0.0;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;
    
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.medium,
    );
    
    await _controller!.initialize();
    if (mounted) setState(() {});
    
    // Starte kontinuierliche Analyse
    _startAnalysis();
  }

  void _startAnalysis() async {
    while (mounted && _controller!.value.isInitialized) {
      try {
        final image = await _controller!.takePicture();
        // Hier würde die Karten-Erkennung laufen
        // Vereinfachte Simulation für Demo
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          setState(() {
            _isAnalyzing = !_isAnalyzing;
          });
        }
      } catch (e) {
        break;
      }
    }
  }

  void _simulateCardDetection() {
    // Demo: Füge Karten hinzu für Test
    setState(() {
      if (_playerCards.length < 2) {
        final ranks = ['A', 'K', 'Q', 'J', '10', '9', '8'];
        final suits = ['♠', '♥', '♦', '♣'];
        final rank = ranks[DateTime.now().second % ranks.length];
        final suit = suits[DateTime.now().second % suits.length];
        _playerCards.add('$rank$suit');
      }
      _calculateRecommendation();
    });
  }

  void _calculateRecommendation() {
    if (_playerCards.length < 2) {
      _recommendation = "Warte auf 2 Karten";
      _handStrength = 0;
      return;
    }
    
    // Vereinfachte Berechnung
    _handStrength = 0.5 + (DateTime.now().millisecond / 2000);
    _handStrength = _handStrength.clamp(0.0, 1.0);
    
    if (_handStrength > 0.75) {
      _recommendation = "RAISE - Starke Hand!";
    } else if (_handStrength > 0.5) {
      _recommendation = "CALL - Gute Hand";
    } else if (_handStrength > 0.3) {
      _recommendation = "CHECK - Mittel";
    } else {
      _recommendation = "FOLD - Zu schwach";
    }
  }

  void _resetCards() {
    setState(() {
      _playerCards = [];
      _communityCards = [];
      _recommendation = "Warte auf Karten...";
      _handStrength = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🎲 Poker Vision'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetCards,
          ),
        ],
      ),
      body: Column(
        children: [
          // Kamera-Vorschau
          Expanded(
            flex: 3,
            child: _controller != null && _controller!.value.isInitialized
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CameraPreview(_controller!),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          
          // Analyse-Status
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isAnalyzing ? Icons.radar : Icons.radar_outlined,
                  color: _isAnalyzing ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isAnalyzing ? "Analysiere..." : "Bereit",
                  style: TextStyle(
                    color: _isAnalyzing ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          
          // Hand-Anzeige
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  "Deine Karten",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _playerCards.isEmpty
                      ? [const Text("-", style: TextStyle(fontSize: 32))]
                      : _playerCards.map((card) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            card,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )).toList(),
                ),
              ],
            ),
          ),
          
          // Empfehlung
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getRecommendationColor(),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _recommendation,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Hand-Stärke: ${(_handStrength * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _simulateCardDetection,
                    icon: const Icon(Icons.style),
                    label: const Text("Test Karte"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRecommendationColor() {
    if (_recommendation.contains("RAISE")) return Colors.green;
    if (_recommendation.contains("CALL")) return Colors.blue;
    if (_recommendation.contains("CHECK")) return Colors.orange;
    if (_recommendation.contains("FOLD")) return Colors.red;
    return Colors.grey;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
