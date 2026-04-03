import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

// 🟢 IMPORTS
import 'mock_test_screen.dart';

class TestInstructionScreen extends StatefulWidget {
  final String title;
  final int duration;
  final String testId;

  const TestInstructionScreen({
    super.key,
    required this.title,
    required this.duration,
    required this.testId,
  });

  @override
  State<TestInstructionScreen> createState() => _TestInstructionScreenState();
}

class _TestInstructionScreenState extends State<TestInstructionScreen> with SingleTickerProviderStateMixin {
  bool _isHindi = false;
  bool _isDownloading = false;
  bool _isReady = false;
  String _statusMessage = "";
  Color _statusColor = const Color(0xFF4F46E5);
  double _downloadProgress = 0.0;

  // 🟢 ANIMATION CONTROLLERS RESTORED
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // 🟢 1. FIXED LINK (GitHub Pages)
  final String _baseUrl = "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/testmt/";

  @override
  void initState() {
    super.initState();

    // 🟢 ANIMATION SETUP
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _animationController.forward();
    _loadLanguage();
    _checkDataAvailability();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isHindi = prefs.getBool('isHindi') ?? false;
      });
    }
  }

  Future<void> _checkDataAvailability() async {
    try {
      if (!Hive.isBoxOpen('app_cache')) {
        await Hive.openLazyBox('app_cache');
      }

      var box = Hive.lazyBox('app_cache');

      if (await box.containsKey(widget.testId)) {
        if (mounted) {
          setState(() {
            _isReady = true;
            _statusMessage = _isHindi ? "टेस्ट तैयार है" : "Test ready";
            _statusColor = const Color(0xFF10B981);
          });
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        _downloadTestContent();
      }
    } catch (e) {
      _downloadTestContent();
    }
  }

  Future<void> _downloadTestContent() async {
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _isReady = false;
        _downloadProgress = 0.0;
        _statusColor = const Color(0xFF4F46E5);
        _statusMessage = _isHindi ? "प्रश्नपत्र डाउनलोड हो रहा है..." : "Downloading resources...";
      });
    }

    final urlString = "$_baseUrl${widget.testId}.json";

    try {
      final response = await http.get(Uri.parse(urlString)).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException("Connection timed out");
        },
      );

      if (response.statusCode == 200) {
        // Simulate progress for smooth UI
        for (double i = 0; i <= 1.0; i += 0.1) {
          if (!mounted) break;
          setState(() {
            _downloadProgress = i;
          });
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final data = jsonDecode(response.body);

        if (!Hive.isBoxOpen('app_cache')) await Hive.openLazyBox('app_cache');
        var box = Hive.lazyBox('app_cache');
        await box.put(widget.testId, data);

        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isReady = true;
            _downloadProgress = 1.0;
            _statusMessage = _isHindi ? "डाउनलोड पूर्ण हुआ" : "Download complete";
            _statusColor = const Color(0xFF10B981);
          });
        }
      } else {
        throw const HttpException("Server Error");
      }
    } on SocketException {
      _setErrorState(_isHindi ? "इंटरनेट कनेक्शन नहीं है" : "No internet connection");
    } on TimeoutException {
      _setErrorState(_isHindi ? "कनेक्शन टाइमआउट हुआ" : "Connection timed out");
    } catch (e) {
      _setErrorState(_isHindi ? "डाउनलोड विफल" : "Download failed");
    }
  }

  void _setErrorState(String message) {
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _isReady = false;
        _downloadProgress = 0.0;
        _statusMessage = message;
        _statusColor = const Color(0xFFEF4444);
      });
    }
  }

  // 🟢 ORIGINAL FULL TRANSLATIONS
  Map<String, String> get t => _isHindi
      ? {
    'app_bar': 'परीक्षा निर्देश',
    'header_gen': 'सामान्य निर्देश',
    'time_msg_1': 'परीक्षा की कुल अवधि ',
    'time_msg_2': ' मिनट है।',
    'clock_msg': 'सर्वर घड़ी सेट की गई है। ऊपरी दाएं कोने में टाइमर शेष समय दिखाएगा।',
    'palette_header': 'प्रश्न पैलेट',
    'palette_msg': 'दाईं ओर दिखने वाला प्रश्न पैलेट प्रत्येक प्रश्न की स्थिति दर्शाता है:',
    'st_white': 'अभी तक नहीं देखा गया',
    'st_red': 'उत्तर नहीं दिया गया',
    'st_green': 'उत्तर दिया गया',
    'st_purple': 'समीक्षा के लिए चिह्नित',
    'nav_header': 'नेविगेशन',
    'nav_1': 'किसी प्रश्न पर सीधे जाने के लिए पैलेट में उसकी संख्या पर क्लिक करें',
    'nav_2': 'वर्तमान उत्तर सहेजने और अगले प्रश्न पर जाने के लिए "Save & Next" दबाएं',
    'ans_header': 'उत्तर देने की विधि',
    'ans_1': 'उत्तर चुनने के लिए विकल्प के बटन पर क्लिक करें',
    'ans_2': 'उत्तर सहेजने के लिए "Save & Next" बटन अवश्य दबाएं',
    'ans_3': 'उत्तर बदलने के लिए दूसरे विकल्प पर क्लिक करें',
    'btn_start': 'प्रारंभ करें',
    'retry': 'पुनः डाउनलोड करें',
    'mins': 'मिनट',
    'qs': 'प्रश्न',
    'best_luck': 'शुभकामनाएँ!',
    'status': 'स्थिति',
    'test_info': 'टेस्ट जानकारी',
  }
      : {
    'app_bar': 'Exam Instructions',
    'header_gen': 'General Instructions',
    'time_msg_1': 'Total exam duration is ',
    'time_msg_2': ' minutes.',
    'clock_msg': 'Server clock is set. Timer at top-right will show remaining time.',
    'palette_header': 'Question Palette',
    'palette_msg': 'The question palette on right shows status using symbols:',
    'st_white': 'Not yet visited',
    'st_red': 'Not answered',
    'st_green': 'Answered',
    'st_purple': 'Marked for review',
    'nav_header': 'Navigation',
    'nav_1': 'Click question number in palette to go directly',
    'nav_2': 'Click Save & Next to save current answer and move next',
    'ans_header': 'Answering Questions',
    'ans_1': 'Click option button to select your answer',
    'ans_2': 'You MUST click Save & Next to save your answer',
    'ans_3': 'Click another option to change your answer',
    'btn_start': 'START TEST',
    'retry': 'RETRY DOWNLOAD',
    'mins': 'minutes',
    'qs': 'questions',
    'best_luck': 'Best of Luck!',
    'status': 'Status',
    'test_info': 'Test Information',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // 🟢 ORIGINAL APP BAR
            _buildAppBar(),

            // 🟢 SCROLLABLE CONTENT (Expanded ensures it fits in remaining space)
            Expanded(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: _buildContent(),
              ),
            ),

            // 🟢 BOTTOM ACTION SECTION (Original Look)
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['app_bar']!,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    widget.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🟢 ORIGINAL TEST INFO CARD (Gradient)
          _buildTestInfoCard(),
          const SizedBox(height: 24),

          // 🟢 STATUS CARD
          _buildStatusCard(),
          const SizedBox(height: 24),

          // 🟢 INSTRUCTIONS
          _buildInstructions(),
        ],
      ),
    );
  }

  Widget _buildTestInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.assignment_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['test_info']!,
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // 🟢 RESPONSIVE FIX: Wrap to prevent overflow
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      Icons.timer_outlined,
                      "${widget.duration} ${t['mins']}",
                    ),
                    _buildInfoChip(
                      Icons.question_answer_outlined,
                      "100 ${t['qs']}",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          // 🟢 FITTED BOX prevents text from overflowing chip
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isDownloading ? Icons.downloading :
                _isReady ? Icons.check_circle : Icons.error_outline,
                color: _statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                t['status']!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isDownloading)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: const Color(0xFFF1F5F9),
                  color: _statusColor,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 8),
              ],
            ),

          Text(
            _statusMessage,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _statusColor,
            ),
          ),

          if (_isReady)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: const Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isHindi ? "टेस्ट शुरू करने के लिए तैयार" : "Ready to start test",
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF065F46),
                        fontWeight: FontWeight.w500,
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

  Widget _buildInstructions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(t['header_gen']!),
        _buildInstructionPoint(
          Icons.access_time,
          "${t['time_msg_1']!}${widget.duration}${t['time_msg_2']!}",
        ),
        _buildInstructionPoint(
          Icons.timer_outlined,
          t['clock_msg']!,
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(t['palette_header']!),
        _buildInstructionPoint(
          Icons.info_outline,
          t['palette_msg']!,
        ),
        const SizedBox(height: 12),

        _buildLegendItem(
          Colors.white,
          const Color(0xFF94A3B8),
          t['st_white']!,
        ),
        _buildLegendItem(
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626),
          t['st_red']!,
        ),
        _buildLegendItem(
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A),
          t['st_green']!,
        ),
        _buildLegendItem(
          const Color(0xFFF3E8FF),
          const Color(0xFF9333EA),
          t['st_purple']!,
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(t['nav_header']!),
        _buildInstructionPoint(
          Icons.navigate_next,
          t['nav_1']!,
        ),
        _buildInstructionPoint(
          Icons.save,
          t['nav_2']!,
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(t['ans_header']!),
        _buildInstructionPoint(
          Icons.radio_button_checked,
          t['ans_1']!,
        ),
        _buildInstructionPoint(
          Icons.check_circle_outline,
          t['ans_2']!,
        ),
        _buildInstructionPoint(
          Icons.change_circle_outlined,
          t['ans_3']!,
        ),

        // 🟢 BEST WISHES SECTION (Original Style)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 32),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF4F46E5).withOpacity(0.1),
                const Color(0xFF7C3AED).withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.emoji_events_outlined,
                  color: const Color(0xFF4F46E5),
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  t['best_luck']!,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F172A),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildInstructionPoint(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 16,
              color: const Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(width: 12),
          // 🟢 RESPONSIVE FIX: Expanded wrapping
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color bgColor, Color borderColor, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                "1",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: borderColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 🟢 RESPONSIVE FIX: Expanded
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: _isReady
                ? ElevatedButton(
              onPressed: () {
                // 🟢 RESTORED FADE TRANSITION
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => MockTestScreen(
                      examTitle: widget.title,
                      durationMins: widget.duration,
                      testId: widget.testId,
                    ),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    t['btn_start']!,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            )
                : ElevatedButton(
              onPressed: _isDownloading ? null : _downloadTestContent,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9),
                foregroundColor: const Color(0xFF475569),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                elevation: 0,
              ),
              child: _isDownloading
                  ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isHindi ? "डाउनलोड हो रहा है..." : "Downloading...",
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.refresh_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    t['retry']!,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_isReady && !_isDownloading)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _isHindi
                    ? "टेस्ट शुरू करने के लिए डाउनलोड करें"
                    : "Download test to begin",
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }
}