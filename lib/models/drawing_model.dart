import 'dart:ui';

class DrawingStroke {
  final Color color;
  final double width;
  final List<Offset> points;

  DrawingStroke({required this.color, required this.width, required this.points});

  // Convert to JSON for Hive
  Map<String, dynamic> toJson() => {
    'c': color.value,
    'w': width,
    'p': points.map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}').toList(),
  };

  // Create from JSON
  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    return DrawingStroke(
      color: Color(json['c']),
      width: (json['w'] as num).toDouble(),
      points: (json['p'] as List).map((pointStr) {
        final parts = (pointStr as String).split(',');
        return Offset(double.parse(parts[0]), double.parse(parts[1]));
      }).toList(),
    );
  }
}