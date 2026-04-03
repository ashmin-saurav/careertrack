import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

// 🟢 Ensure this import points to your actual engine file
import '../services/analytics_engine.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final String _usageBoxName = 'usage_stats';
  final String _historyBoxName = 'question_history';

  @override
  void initState() {
    super.initState();
    _openBoxes();
  }

  Future<void> _openBoxes() async {
    if (!Hive.isBoxOpen(_usageBoxName)) await Hive.openBox(_usageBoxName);
    if (!Hive.isBoxOpen(_historyBoxName)) await Hive.openBox(_historyBoxName);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          "My Progress",
          style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
      ),
      body: FutureBuilder(
        future: Future.wait([
          Hive.isBoxOpen(_usageBoxName) ? Future.value(null) : Hive.openBox(_usageBoxName),
          Hive.isBoxOpen(_historyBoxName) ? Future.value(null) : Hive.openBox(_historyBoxName),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildScrollableContent();
        },
      ),
    );
  }

  Widget _buildScrollableContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRealTimeUsageSection(),
          const SizedBox(height: 24),
          _buildPerformanceSection(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🟢 1. TIME USAGE SECTION (Smart Scaling)
  // ---------------------------------------------------------------------------
  Widget _buildRealTimeUsageSection() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(_usageBoxName).listenable(),
      builder: (context, box, _) {
        final now = DateTime.now();
        List<double> weeklyData = [];
        List<String> weekLabels = [];
        double maxMinutes = 0;
        int todayMinutes = 0;

        // 1. Get raw data
        // 1. Get raw data
        for (int i = 6; i >= 0; i--) {
          DateTime d = now.subtract(Duration(days: i));
          String key = DateFormat('yyyy-MM-dd').format(d);

          // 🔴 OLD CODE:
          // int mins = box.get(key, defaultValue: 0);

          // 🟢 NEW CODE: Convert seconds to minutes!
          int rawSeconds = box.get(key, defaultValue: 0);
          int mins = rawSeconds ~/ 60;

          if (i == 0) todayMinutes = mins;
          weeklyData.add(mins.toDouble());
          weekLabels.add(DateFormat('E').format(d).substring(0, 1));

          if (mins > maxMinutes) maxMinutes = mins.toDouble();
        }

        // 🟢 2. SMART SCALING LOGIC
        // If max is 3h 15m (195m), round UP to 4h (240m) so the graph looks clean.
        // If max is < 1h, default to 1h.
        if (maxMinutes <= 60) {
          maxMinutes = 60;
        } else {
          // Calculate hours and round up to next hour
          double hours = maxMinutes / 60;
          maxMinutes = (hours.ceil()) * 60.0;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Time Spent This Week", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_formatDurationBig(todayMinutes), style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.2)),
                  const SizedBox(width: 8),
                  Text("Today", style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 24),

              LayoutBuilder(
                  builder: (context, constraints) {
                    return RepaintBoundary(
                      child: SizedBox(
                        height: 150,
                        width: constraints.maxWidth,
                        child: CustomPaint(
                          painter: WeeklyChartPainter(
                              data: weeklyData,
                              labels: weekLabels,
                              maxVal: maxMinutes,
                              colors: [
                                Colors.blue.shade300, Colors.purple.shade200, Colors.orange.shade300,
                                Colors.teal.shade200, Colors.red.shade300, Colors.indigo.shade200,
                                Colors.green.shade400,
                              ]
                          ),
                        ),
                      ),
                    );
                  }
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🟢 2. PERFORMANCE SECTION
  // ---------------------------------------------------------------------------
  Widget _buildPerformanceSection() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box(_historyBoxName).listenable(),
      builder: (context, box, _) {
        return FutureBuilder<Map<String, dynamic>>(
          future: AnalyticsEngine.getReport(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return _buildEmptyExamState();
            }

            final report = snapshot.data!;

            int tQ = 0, tC = 0, tW = 0, tS = 0;
            String best = '-';
            String worst = '-';
            double highestAcc = -1;
            double lowestAcc = 101;

            report.forEach((subject, data) {
              int subTotal = (data['total'] as int? ?? 0);
              tQ += subTotal;
              tC += (data['correct'] as int? ?? 0);
              tW += (data['wrong'] as int? ?? 0);
              tS += (data['skipped'] as int? ?? 0);

              double acc = (data['accuracy'] as double? ?? 0.0);

              if (acc > highestAcc && subTotal >= 3) {
                highestAcc = acc;
                best = subject;
              }
              if (acc < lowestAcc && subTotal >= 3) {
                lowestAcc = acc;
                worst = subject;
              }
            });

            double overallAcc = tQ > 0 ? (tC / tQ) * 100 : 0.0;
            String bestSubject = best == '-' ? report.keys.first : best;
            String weakestSubject = worst == '-' ? "None" : worst;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScoreCard(overallAcc, tQ, tC, tW, tS),
                const SizedBox(height: 20),
                _buildInsightsGrid(bestSubject, weakestSubject),
                const SizedBox(height: 24),
                Text("Subject Breakdown", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text("Tap on a subject to see details", style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 12),
                _buildSubjectList(report),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🟢 WIDGET COMPONENTS
  // ---------------------------------------------------------------------------

  Widget _buildScoreCard(double accuracy, int total, int correct, int wrong, int skipped) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Exam Performance", style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text("${accuracy.toStringAsFixed(0)}%", style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(width: 6),
                        Text("Accuracy", style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text("$total Total Questions", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                    ),
                  ],
                ),
              ),
              RepaintBoundary(
                child: SizedBox(
                  height: 90, width: 90,
                  child: CustomPaint(painter: PerformanceChartPainter(correct: correct, wrong: wrong, skipped: skipped, total: total)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(Colors.green, "Correct", correct),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.redAccent, "Wrong", wrong),
                const SizedBox(width: 16),
                _buildLegendItem(Colors.orangeAccent, "Skipped", skipped),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, int value) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text("$value", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _buildInsightsGrid(String best, String worst) {
    return Row(
      children: [
        Expanded(child: _buildInsightCard("Strongest Subject", best, Icons.emoji_events_rounded, Colors.amber)),
        const SizedBox(width: 12),
        Expanded(child: _buildInsightCard("Weakest Subject", worst, Icons.warning_rounded, Colors.orange)),
      ],
    );
  }

  Widget _buildInsightCard(String title, String subject, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(title, style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            subject, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyExamState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text("No Exam Data Yet", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              "Take a mock test or quiz to see your performance analysis here.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectList(Map<String, dynamic> report) {
    final entries = report.entries.toList()..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));
    return Column(children: entries.map((entry) => _buildSubjectTile(entry.key, entry.value)).toList());
  }

  Widget _buildSubjectTile(String subject, Map<dynamic, dynamic> data) {
    final double accuracy = data['accuracy'] ?? 0.0;
    final int total = data['total'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showTopicDetails(subject, data),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: _getAccuracyColor(accuracy).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: Text(
                      subject.isNotEmpty ? subject[0].toUpperCase() : '?',
                      style: GoogleFonts.poppins(color: _getAccuracyColor(accuracy), fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subject, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text("$total questions attempted", style: GoogleFonts.inter(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                  child: Text("${accuracy.toInt()}%", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTopicDetails(String subject, Map<dynamic, dynamic> data) {
    final Map<String, dynamic> topics = Map<String, dynamic>.from(data['topics'] ?? {});
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8, minChildSize: 0.5, maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                      child: Icon(Icons.auto_stories_outlined, color: Colors.blue.shade700, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text("Topic-wise Analysis", style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEFF2F5)),
              Expanded(
                child: topics.isEmpty
                    ? Center(child: Text("No topic data available.", style: GoogleFonts.inter(color: Colors.grey)))
                    : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: topics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, index) {
                    String key = topics.keys.elementAt(index);
                    Map<String, dynamic> tData = Map<String, dynamic>.from(topics[key] ?? {});
                    return _buildModernTopicCard(key, tData);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernTopicCard(String name, Map<String, dynamic> data) {
    int attempts = data['att'] ?? 0;
    int correct = data['cor'] ?? 0;
    int wrong = data['wrg'] ?? 0;
    int skipped = data['skp'] ?? 0;
    double accuracy = data['accuracy'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: _getAccuracyColor(accuracy).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text("${accuracy.toInt()}%", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: _getAccuracyColor(accuracy))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (correct > 0) Flexible(flex: correct, child: Container(color: Colors.green)),
                  if (wrong > 0) Flexible(flex: wrong, child: Container(color: Colors.redAccent)),
                  if (skipped > 0) Flexible(flex: skipped, child: Container(color: Colors.orangeAccent)),
                  if (attempts == 0) Expanded(child: Container(color: Colors.grey.shade200)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDurationBig(int minutes) {
    if (minutes == 0) return "0 min";
    if (minutes < 60) return "$minutes min";
    int h = minutes ~/ 60;
    int m = minutes % 60;
    if (m == 0) return "$h hr";
    return "$h hr, $m min";
  }

  Color _getAccuracyColor(double acc) {
    if (acc >= 80) return Colors.green.shade600;
    if (acc >= 50) return Colors.blue.shade600;
    return Colors.orange.shade600;
  }
}

// ---------------------------------------------------------------------------
// 🟢 FIXED PAINTER (Responsive + Smart Scaling)
// ---------------------------------------------------------------------------

class WeeklyChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final double maxVal;
  final List<Color> colors;

  WeeklyChartPainter({required this.data, required this.labels, required this.maxVal, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    // 🟢 SAFE LAYOUT LOGIC
    const double bottomLabelReservedHeight = 24.0;
    const double rightAxisReservedWidth = 32.0;

    final double chartH = size.height - bottomLabelReservedHeight;
    final double chartW = size.width - rightAxisReservedWidth;

    final linePaint = Paint()..color = Colors.grey.shade100..strokeWidth = 1;
    final barPaint = Paint()..style = PaintingStyle.fill;

    canvas.drawLine(Offset(0, chartH), Offset(chartW, chartH), linePaint);
    canvas.drawLine(Offset(0, chartH / 2), Offset(chartW, chartH / 2), linePaint);
    canvas.drawLine(Offset(0, 0), Offset(chartW, 0), linePaint);

    // Y-Axis Labels (Smart Rounding makes these clean: 1h, 2h, etc)
    final axisStyle = GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w500);
    _drawText(canvas, "0", Offset(chartW + 6, chartH - 6), axisStyle);
    _drawText(canvas, _formatMinutesForAxis(maxVal / 2), Offset(chartW + 6, (chartH / 2) - 6), axisStyle);
    _drawText(canvas, _formatMinutesForAxis(maxVal), Offset(chartW + 6, -6), axisStyle);

    // Bars
    final double slotWidth = chartW / 7;
    final double barWidth = slotWidth * 0.5;

    for (int i = 0; i < 7; i++) {
      double left = (i * slotWidth) + (slotWidth - barWidth) / 2;
      double barHeight = (data[i] / maxVal) * chartH;

      if (data[i] > 0 && barHeight < 4) barHeight = 4;
      if (barHeight > chartH) barHeight = chartH;

      Rect barRect = Rect.fromLTWH(left, chartH - barHeight, barWidth, barHeight);
      barPaint.color = colors[i];
      canvas.drawRRect(RRect.fromRectAndCorners(barRect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), barPaint);

      bool isToday = (i == 6);
      final labelStyle = GoogleFonts.inter(
          color: isToday ? Colors.blue.shade700 : Colors.grey.shade500,
          fontSize: 11,
          fontWeight: isToday ? FontWeight.bold : FontWeight.w500
      );

      _drawTextCentered(canvas, labels[i], Offset(left + barWidth / 2, chartH + 12), labelStyle);
    }
  }

  String _formatMinutesForAxis(double minutes) {
    if (minutes <= 0) return "0";
    if (minutes < 60) return "${minutes.toInt()}m";
    int hours = minutes ~/ 60;
    return "${hours}h";
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final textPainter = TextPainter(text: TextSpan(text: text, style: style), textDirection: ui.TextDirection.ltr)..layout();
    textPainter.paint(canvas, pos);
  }

  void _drawTextCentered(Canvas canvas, String text, Offset centerPos, TextStyle style) {
    final textPainter = TextPainter(text: TextSpan(text: text, style: style), textDirection: ui.TextDirection.ltr)..layout();
    textPainter.paint(canvas, Offset(centerPos.dx - (textPainter.width / 2), centerPos.dy - (textPainter.height / 2)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PerformanceChartPainter extends CustomPainter {
  final int correct, wrong, skipped, total;

  PerformanceChartPainter({required this.correct, required this.wrong, required this.skipped, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.height / 2;
    const strokeWidth = 8.0;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round;

    if (total == 0) {
      paint.color = Colors.grey.shade200;
      canvas.drawCircle(center, radius - strokeWidth / 2, paint);
      return;
    }
    double startAngle = -pi / 2;
    void drawSegment(int value, Color color) {
      if (value > 0) {
        double sweep = (value / total) * 2 * pi;
        paint.color = color;
        canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweep, false, paint);
        startAngle += sweep;
      }
    }
    drawSegment(correct, Colors.green);
    drawSegment(wrong, Colors.redAccent);
    drawSegment(skipped, Colors.orangeAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}