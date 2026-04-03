import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../widgets/smart_text_renderer.dart';

class PracticeCanvasScreen extends StatefulWidget {
  final String paperId;
  final int questionIndex;
  final String questionText;
  final double devicePixelRatio;

  const PracticeCanvasScreen({
    super.key,
    required this.paperId,
    required this.questionIndex,
    required this.questionText,
    required this.devicePixelRatio,
  });

  @override
  State<PracticeCanvasScreen> createState() => _PracticeCanvasScreenState();
}

class _PracticeCanvasScreenState extends State<PracticeCanvasScreen> {
  List<DrawingStroke> _strokes = [];
  DrawingStroke? _currentStroke;

  Color _selectedColor = Colors.black;
  bool _isEraser = false;
  bool _isPanMode = false;
  bool _showQuestionOverlay = true;

  // 🟢 Reduced size to prevent GPU rendering issues on low-end devices
  final double _canvasSize = 10000.0;
  late final TransformationController _transformController;
  Box? _drawingBox;

  String get _hiveKey => "${widget.paperId}_q${widget.questionIndex}";

  @override
  void initState() {
    super.initState();
    // Center the canvas initially
    _transformController = TransformationController(
        Matrix4.identity()..translate(-_canvasSize / 2, -_canvasSize / 2)
    );
    _initHiveAndLoad();
  }

  Future<void> _initHiveAndLoad() async {
    if (!Hive.isBoxOpen('drawings')) {
      _drawingBox = await Hive.openBox('drawings');
    } else {
      _drawingBox = Hive.box('drawings');
    }

    final savedData = _drawingBox!.get(_hiveKey);
    if (savedData != null && mounted) {
      setState(() {
        _strokes = (savedData as List)
            .map((e) => DrawingStroke.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // 🟢 Auto-save on every stroke to prevent data loss
  void _saveToHive() {
    if (_drawingBox != null) {
      final dataToSave = _strokes.map((s) => s.toJson()).toList();
      _drawingBox!.put(_hiveKey, dataToSave);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: Stack(
        children: [
          // --------------------------------------------------------
          // 1. INFINITE CANVAS
          // --------------------------------------------------------
          InteractiveViewer(
            transformationController: _transformController,
            panEnabled: _isPanMode,
            scaleEnabled: _isPanMode,
            minScale: 0.1,
            maxScale: 5.0,
            // 🟢 Aligned boundary with new canvas size
            boundaryMargin: const EdgeInsets.all(5000),
            constrained: false,
            child: GestureDetector(
              onPanStart: _isPanMode ? null : _onPanStart,
              onPanUpdate: _isPanMode ? null : _onPanUpdate,
              onPanEnd: _isPanMode ? null : _onPanEnd,
              child: RepaintBoundary(
                child: SizedBox(
                  width: _canvasSize,
                  height: _canvasSize,
                  child: Stack(
                    children: [
                      // Layer 1: White Background
                      Container(color: Colors.white),

                      // Layer 2: Grid (Won't get erased now!)
                      RepaintBoundary(
                          child: CustomPaint(
                              size: Size(_canvasSize, _canvasSize),
                              painter: const GridPainter()
                          )
                      ),

                      // Layer 3: Drawing History (Transparent Layer)
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(_canvasSize, _canvasSize),
                          isComplex: true,
                          willChange: false, // Optimized
                          painter: HistoryPainter(strokes: _strokes), // Pass list reference
                        ),
                      ),

                      // Layer 4: Active Stroke
                      CustomPaint(
                        size: Size(_canvasSize, _canvasSize),
                        painter: ActiveStrokePainter(currentStroke: _currentStroke),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --------------------------------------------------------
          // 2. QUESTION OVERLAY
          // --------------------------------------------------------
          if (_showQuestionOverlay)
            Positioned(
              top: 80, left: 20, right: 20,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Question Reference", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() => _showQuestionOverlay = false)
                            )
                          ],
                        ),
                        const Divider(),
                        SmartTextRenderer(
                            text: widget.questionText,
                            textColor: Colors.black87,
                            devicePixelRatio: widget.devicePixelRatio
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // --------------------------------------------------------
          // 3. TOP BUTTONS
          // --------------------------------------------------------
          Positioned(
            top: 40, left: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                    heroTag: "b",
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context)
                ),
                const SizedBox(height: 12),
                if (!_showQuestionOverlay)
                  FloatingActionButton.small(
                      heroTag: "q",
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.help_outline, color: Colors.black),
                      onPressed: () => setState(() => _showQuestionOverlay = true)
                  ),
              ],
            ),
          ),

          // --------------------------------------------------------
          // 4. TOOLBAR
          // --------------------------------------------------------
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: Center(child: _buildToolbar()),
          ),

          Positioned(
            top: 20, left: 0, right: 0,
            child: Center(child: _buildStatusChip()),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS ---
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))]
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildModeBtn(),
            const SizedBox(width: 16),

            if (!_isPanMode) ...[
              IconButton(
                  icon: Icon(Icons.cleaning_services_outlined, color: _isEraser ? Colors.orange : Colors.white),
                  onPressed: () => setState(() => _isEraser = !_isEraser)
              ),
              const SizedBox(width: 4),
            ],

            IconButton(
                icon: const Icon(Icons.undo, color: Colors.white),
                onPressed: _strokes.isEmpty ? null : () {
                  setState(() => _strokes.removeLast());
                  _saveToHive(); // Save on undo
                }
            ),

            if (!_isPanMode) ...[
              const SizedBox(width: 8),
              Container(height: 24, width: 1, color: Colors.grey),
              const SizedBox(width: 8),
              _buildColorDot(Colors.black),
              _buildColorDot(const Color(0xFFD32F2F)),
              _buildColorDot(const Color(0xFF1976D2)),
            ],

            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () {
                  setState(() { _strokes.clear(); _currentStroke = null; });
                  _saveToHive(); // Save on clear
                }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBtn() {
    return GestureDetector(
      onTap: () => setState(() => _isPanMode = !_isPanMode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: _isPanMode ? Colors.blue : Colors.green, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Icon(_isPanMode ? Icons.pan_tool : Icons.edit, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(_isPanMode ? "MOVE" : "DRAW", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _buildColorDot(Color c) {
    bool isSelected = _selectedColor == c && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() { _selectedColor = c; _isEraser = false; }),
      child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), width: 24, height: 24, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.white, width: 2) : null)),
    );
  }

  Widget _buildStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: _isPanMode ? Colors.blue.withOpacity(0.9) : Colors.green.withOpacity(0.9), borderRadius: BorderRadius.circular(20)),
      child: Text(_isPanMode ? "👆 Move & Pinch to Zoom" : "✏️ Draw Mode", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  // --- LOGIC ---
  void _onPanStart(DragStartDetails d) {
    setState(() {
      _currentStroke = DrawingStroke(
        color: _isEraser ? Colors.transparent : _selectedColor,
        width: _isEraser ? 40.0 : 3.0,
        points: [d.localPosition],
        isEraser: _isEraser, // 🟢 Mark as eraser
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_currentStroke == null) return;
    if ((d.localPosition - _currentStroke!.points.last).distance > 1.0) {
      setState(() => _currentStroke!.points.add(d.localPosition));
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_currentStroke != null) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
      });
      _saveToHive(); // 🟢 Save immediately
    }
  }
}

// --- PAINTERS & MODELS ---

class DrawingStroke {
  final Color color;
  final double width;
  final List<Offset> points;
  final bool isEraser; // 🟢 Added property

  DrawingStroke({
    required this.color,
    required this.width,
    required this.points,
    this.isEraser = false,
  });

  Map<String, dynamic> toJson() => {
    'c': color.value,
    'w': width,
    'e': isEraser, // Save eraser state
    'p': points.map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}').toList()
  };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
      color: Color(json['c']),
      width: (json['w'] as num).toDouble(),
      isEraser: json['e'] ?? false, // Load eraser state
      points: (json['p'] as List).map((s) {
        var p = (s as String).split(',');
        return Offset(double.parse(p[0]), double.parse(p[1]));
      }).toList()
  );
}

class GridPainter extends CustomPainter {
  const GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.grey.withOpacity(0.2)..strokeWidth = 1; // Made slightly darker for visibility
    for (double i = 0; i < size.width; i += 50) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 50) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class HistoryPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  HistoryPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    // 🟢 Creating a save layer is crucial for blend modes to work correctly on some devices
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    for (var s in strokes) {
      final p = Paint()
        ..color = s.isEraser ? Colors.transparent : s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
      // 🟢 THE FIX: Clear pixels if eraser, otherwise draw normal
        ..blendMode = s.isEraser ? BlendMode.clear : BlendMode.srcOver;

      if (s.points.length > 1) {
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (int i = 1; i < s.points.length; i++) path.lineTo(s.points[i].dx, s.points[i].dy);
        canvas.drawPath(path, p);
      } else if (s.points.isNotEmpty) {
        canvas.drawCircle(s.points.first, s.width/2, p..style = PaintingStyle.fill);
      }
    }

    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant HistoryPainter old) => true;
}

class ActiveStrokePainter extends CustomPainter {
  final DrawingStroke? currentStroke;
  ActiveStrokePainter({required this.currentStroke});
  @override
  void paint(Canvas canvas, Size size) {
    if (currentStroke == null || currentStroke!.points.isEmpty) return;
    final s = currentStroke!;

    // Same logic for active stroke
    final p = Paint()
      ..color = s.isEraser ? Colors.transparent : s.color
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = s.isEraser ? BlendMode.clear : BlendMode.srcOver;

    // Use saveLayer for the active stroke too if it's an eraser
    if (s.isEraser) canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    if (s.points.length > 1) {
      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, p);
    } else {
      canvas.drawCircle(s.points.first, s.width/2, p..style = PaintingStyle.fill);
    }

    if (s.isEraser) canvas.restore();
  }
  @override
  bool shouldRepaint(covariant ActiveStrokePainter old) => true;
}