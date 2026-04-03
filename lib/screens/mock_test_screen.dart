import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🟢 IMPORTS
import '../widgets/smart_text_renderer.dart';
import 'result_analysis_screen.dart';
import 'practice_canvas_screen.dart';
import '../services/analytics_engine.dart';

class MockTestScreen extends StatefulWidget {
  final String examTitle;
  final int durationMins;
  final String testId;

  const MockTestScreen({
    super.key,
    required this.examTitle,
    required this.durationMins,
    required this.testId,
  });

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // Animation Controller for Palette
  late AnimationController _paletteController;
  late Animation<Offset> _paletteAnimation;
  late PageController _pageController;

  // State
  bool _isLoading = true;
  String _selectedLang = 'en';
  String? _errorMessage;

  // Timer
  Timer? _timer;
  late ValueNotifier<Duration> _timeNotifier;
  late DateTime _endTime;

  // Data
  int _currentIndex = 0;
  List<Map<String, dynamic>> _questions = [];
  double _devicePixelRatio = 1.0;

  // Tracking
  List<int> _questionStatus = [];
  List<int?> _selectedAnswers = [];

  final String _baseUrl =
      "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/testmt/";

  // UI Strings
  final Map<String, Map<String, String>> _uiStrings = {
    'submit_title': {'en': 'Submit Test?', 'hi': 'क्या टेस्ट सबमिट करें?'},
    'submit_msg': {
      'en': 'Are you sure you want to finish?',
      'hi': 'क्या आप सच में टेस्ट खत्म करना चाहते हैं?'
    },
    'review_warn': {'en': 'Marked for Review:', 'hi': 'रिव्यू के लिए मार्क:'},
    'skip_warn': {'en': 'Unattempted:', 'hi': 'छोड़े गए:'},
    'yes': {'en': 'Yes, Submit', 'hi': 'हाँ, सबमिट करें'},
    'no': {'en': 'Cancel', 'hi': 'रद्द करें'},
    'save_next': {'en': 'Save & Next', 'hi': 'सेव और आगे'},
    'submit_btn': {'en': 'Submit Test', 'hi': 'टेस्ट सबमिट'},
    'mark_review': {'en': 'Mark Review', 'hi': 'रिव्यू मार्क'},
    'q_palette': {'en': 'Question Palette', 'hi': 'प्रश्न सूची'},
    'section': {'en': 'Section', 'hi': 'सेक्शन'},
  };

  String _getStr(String key) => _uiStrings[key]?[_selectedLang] ?? key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _paletteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _paletteAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _paletteController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _pageController = PageController(initialPage: 0, keepPage: true);
    _timeNotifier = ValueNotifier(Duration(minutes: widget.durationMins));

    _loadUserLanguage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        });
      }
    });

    _initializeAndFetch();
  }

  void _togglePalette() {
    if (_paletteController.isDismissed) {
      _paletteController.forward();
    } else {
      _paletteController.reverse();
    }
  }

  Future<void> _loadUserLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedLang = prefs.getString('exam_lang') ?? 'en';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncTimer();
  }

  Future<void> _initializeAndFetch() async {
    if (!Hive.isBoxOpen('app_cache')) {
      await Hive.openLazyBox('app_cache');
    }

    await _loadFromCache();

    if (_questions.isEmpty) {
      await _fetchFromNetwork();
    } else {
      _startTimerSession();
    }
  }

  Future<void> _loadFromCache() async {
    try {
      var box = Hive.lazyBox('app_cache');
      var cachedData = await box.get(widget.testId);

      if (cachedData != null) {
        Map<String, dynamic> data = (cachedData is String)
            ? jsonDecode(cachedData)
            : (cachedData is Map)
            ? Map<String, dynamic>.from(cachedData)
            : jsonDecode(jsonEncode(cachedData));

        await _processData(data);
      }
    } catch (e) {
      debugPrint("Cache Load Error: $e");
    }
  }

  Future<void> _fetchFromNetwork() async {
    try {
      final url = Uri.parse("$_baseUrl${widget.testId}.json");
      debugPrint("Fetching from URL: $url"); // ADD THIS

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      debugPrint("Status Code: ${response.statusCode}"); // ADD THIS

      if (response.statusCode == 200) {
        debugPrint("Raw Response Body: ${response.body}"); // ADD THIS (Shows the exact JSON string)

        final data = jsonDecode(response.body);
        debugPrint("Decoded Data Type: ${data.runtimeType}"); // ADD THIS (Usually shows _Map<String, dynamic>)

        var box = Hive.lazyBox('app_cache');
        await box.put(widget.testId, data);

        await _processData(data);
        _startTimerSession();
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Network Fetch Error Caught: $e"); // ADD THIS to see exact failure reason
      if (_questions.isEmpty && mounted) {
        setState(() {
          _errorMessage = "Connection Failed & No Offline Data.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _processData(Map<String, dynamic> data) async {
    List<dynamic> rawQuestions = [];
    if (data.containsKey('data')) {
      rawQuestions = data['data'];
    } else if (data.containsKey('q')) {
      rawQuestions = data['q'];
    } else if (data.containsKey('questions')) {
      rawQuestions = data['questions'];
    }

    debugPrint("Found ${rawQuestions.length} questions. Data Type of list: ${rawQuestions.runtimeType}"); // ADD THIS
    if(rawQuestions.isNotEmpty) {
      debugPrint("Sample first question data: ${rawQuestions.first}"); // ADD THIS
    }

    final parsedQuestions = await compute(_parseQuestions, rawQuestions);

    if (mounted) {
      setState(() {
        _questions = parsedQuestions;
        _questionStatus = List.filled(_questions.length, 0);
        _selectedAnswers = List.filled(_questions.length, null);
        if (_questions.isNotEmpty) _questionStatus[0] = 2;
        _isLoading = false;
      });
    }
  }

  static List<Map<String, dynamic>> _parseQuestions(List<dynamic> rawList) {
    return rawList.map((q) => Map<String, dynamic>.from(q)).toList();
  }

  void _startTimerSession() {
    if (_timer != null && _timer!.isActive) return;

    _endTime = DateTime.now().add(Duration(minutes: widget.durationMins));
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _syncTimer());
  }

  void _syncTimer() {
    final now = DateTime.now();
    if (now.isAfter(_endTime)) {
      _timer?.cancel();
      _finalizeAndGo(timeUp: true);
    } else {
      _timeNotifier.value = _endTime.difference(now);
    }
  }

  Future<void> _finalizeAndGo({bool timeUp = false}) async {
    _timer?.cancel();

    try {
      if (!Hive.isBoxOpen('exam_history')) await Hive.openBox('exam_history');
      var box = Hive.box('exam_history');
      await box.put(widget.testId, _selectedAnswers);
    } catch (e) {
      debugPrint("Save error: $e");
    }

    try {
      await AnalyticsEngine.recordSession(_questions, _selectedAnswers);
    } catch (e) {
      debugPrint("Analytics error: $e");
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultAnalysisScreen(
          examTitle: widget.examTitle,
          testId: widget.testId,
          duration: widget.durationMins,
          showRetakeButton: false,
          isNewAttempt: true,
        ),
      ),
    );
  }

  void _trySubmit() {
    if (_paletteController.isCompleted) _paletteController.reverse();

    int reviewCount = _questionStatus.where((s) => s == 3).length;
    int unattemptedCount = _selectedAnswers.where((a) => a == null).length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _getStr('submit_title'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getStr('submit_msg'),
              style: GoogleFonts.inter(fontSize: 14),
            ),
            const SizedBox(height: 16),
            if (reviewCount > 0)
              _warningRow(
                Icons.flag_rounded,
                Colors.purple,
                "${_getStr('review_warn')} $reviewCount",
              ),
            if (unattemptedCount > 0)
              _warningRow(
                Icons.warning_amber_rounded,
                Colors.orange,
                "${_getStr('skip_warn')} $unattemptedCount",
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _getStr('no'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _finalizeAndGo();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(_getStr('yes')),
          )
        ],
      ),
    );
  }

  Widget _warningRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _getCurrentQuestionText(int index) {
    if (_questions.isEmpty || index >= _questions.length) return "";
    final qData = _questions[index];
    if (_selectedLang == 'hi' && qData['hq'] != null) return qData['hq'];
    return qData['q'] ?? "";
  }

  List<String> _getCurrentOptions(int index) {
    if (_questions.isEmpty || index >= _questions.length) return [];
    final qData = _questions[index];
    if (_selectedLang == 'hi' && qData['ho'] != null) {
      return List<String>.from(qData['ho']);
    }
    return List<String>.from(qData['o'] ?? []);
  }

  String _getSectionName(int index) {
    if (_questions.isEmpty || index >= _questions.length) return "";
    return _questions[index]['s'] ?? "General";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildShimmerLoading();

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.inter(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_paletteController.isCompleted || _paletteController.isAnimating) {
          _togglePalette();
          return;
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              "Exit Exam?",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "Your progress will be lost.",
              style: GoogleFonts.inter(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text(
                  "Exit",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Stack(
            children: [
              // Main Content
              Column(
                children: [
                  _buildCompactHeader(),
                  const _ProgressIndicator(),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const ClampingScrollPhysics(),
                      onPageChanged: (index) {
                        if (mounted) {
                          setState(() {
                            _currentIndex = index;
                            if (_questionStatus[index] == 0) {
                              _questionStatus[index] = 2;
                            }
                          });
                        }
                      },
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        return _buildSingleQuestionPage(index);
                      },
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),

              // Dim Barrier
              AnimatedBuilder(
                animation: _paletteController,
                builder: (context, child) {
                  if (_paletteController.value == 0) {
                    return const SizedBox.shrink();
                  }
                  return GestureDetector(
                    onTap: _togglePalette,
                    child: Container(
                      color: Colors.black.withOpacity(
                        _paletteController.value * 0.4,
                      ),
                    ),
                  );
                },
              ),

              // Sliding Palette
              SlideTransition(
                position: _paletteAnimation,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: RepaintBoundary(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.85,
                      height: double.infinity,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            offset: Offset(-4, 0),
                          )
                        ],
                      ),
                      child: _buildQuestionPalette(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.examTitle,
                  style: GoogleFonts.notoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePalette,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: Color(0xFF475569),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LanguageSelector(
                selectedLang: _selectedLang,
                onChanged: (val) async {
                  if (val != null) {
                    setState(() {
                      _selectedLang = val;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('exam_lang', val);
                  }
                },
              ),
              _IsolatedTimerWidget(timeNotifier: _timeNotifier),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSingleQuestionPage(int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          key: ValueKey<int>(index),
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _getSectionName(index).toUpperCase(),
                            style: GoogleFonts.notoSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Text(
                          "+1.0 / -0.33",
                          style: GoogleFonts.notoSans(
                            color: const Color(0xFF166534),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Q.${index + 1}",
                        style: GoogleFonts.notoSans(
                          color: const Color(0xFF1E293B),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      _ScribbleButton(
                        testId: widget.testId,
                        index: index,
                        text: _getCurrentQuestionText(index),
                        ratio: _devicePixelRatio,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    child: SmartTextRenderer(
                      text: _getCurrentQuestionText(index),
                      textColor: const Color(0xFF334155),
                      devicePixelRatio: _devicePixelRatio,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildOptionsList(index),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionsList(int qIndex) {
    final options = _getCurrentOptions(qIndex);
    return Column(
      children: List.generate(options.length, (optIndex) {
        bool isSelected = _selectedAnswers[qIndex] == optIndex;
        return RepaintBoundary(
          child: _OptionItem(
            key: ValueKey('option_${qIndex}_$optIndex'),
            optionText: options[optIndex],
            isSelected: isSelected,
            onTap: () {
              setState(() {
                if (_selectedAnswers[qIndex] == optIndex) {
                  _selectedAnswers[qIndex] = null;
                  if (_questionStatus[qIndex] != 3) {
                    _questionStatus[qIndex] = 2;
                  }
                } else {
                  _selectedAnswers[qIndex] = optIndex;
                  if (_questionStatus[qIndex] != 3) {
                    _questionStatus[qIndex] = 1;
                  }
                }
              });
            },
            letter: String.fromCharCode(65 + optIndex),
            devicePixelRatio: _devicePixelRatio,
          ),
        );
      }),
    );
  }

  Widget _buildBottomBar() {
    bool isLast = _currentIndex == _questions.length - 1;
    bool isReview = _questionStatus[_currentIndex] == 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Material(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _currentIndex > 0
                    ? () {
                  _pageController.jumpToPage(_currentIndex - 1);
                }
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: _currentIndex > 0
                        ? const Color(0xFF334155)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    if (_questionStatus[_currentIndex] == 3) {
                      _questionStatus[_currentIndex] =
                      _selectedAnswers[_currentIndex] != null ? 1 : 2;
                    } else {
                      _questionStatus[_currentIndex] = 3;
                    }
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(
                    color: isReview
                        ? const Color(0xFF9333EA)
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                  backgroundColor: isReview
                      ? const Color(0xFFFAF5FF)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    isReview ? "Unmark" : _getStr('mark_review'),
                    style: GoogleFonts.notoSans(
                      color: isReview
                          ? const Color(0xFF9333EA)
                          : const Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _trySubmit();
                  } else {
                    _pageController.jumpToPage(_currentIndex + 1);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    isLast ? _getStr('submit_btn') : _getStr('save_next'),
                    style: GoogleFonts.notoSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionPalette() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getStr('q_palette'),
                style: GoogleFonts.notoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePalette,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              )
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              _LegendItem(color: Color(0xFF10B981), text: "Ans"),
              _LegendItem(color: Color(0xFFEF4444), text: "Skip"),
              _LegendItem(color: Color(0xFF8B5CF6), text: "Rev"),
              _LegendItem(color: Color(0xFFE2E8F0), text: "Left", isBorder: true),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              return _PaletteItem(
                index: index,
                status: _questionStatus[index],
                isCurrentQuestion: index == _currentIndex,
                onTap: () {
                  _togglePalette();
                  _pageController.jumpToPage(index);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerLoading() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 24,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 30),
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 30),
              Column(
                children: List.generate(
                  4,
                      (index) => Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    height: 60,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _paletteController.dispose();
    _pageController.dispose();
    _timeNotifier.dispose();
    super.dispose();
  }
}

// ============================================================================
// PROGRESS INDICATOR
// ============================================================================
class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_MockTestScreenState>();
    if (state == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      tween: Tween<double>(
        begin: 0,
        end: (state._currentIndex + 1) / state._questions.length,
      ),
      builder: (context, value, child) {
        return LinearProgressIndicator(
          value: value,
          backgroundColor: const Color(0xFFE2E8F0),
          valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
          minHeight: 3,
        );
      },
    );
  }
}

// ============================================================================
// LANGUAGE SELECTOR
// ============================================================================
class _LanguageSelector extends StatelessWidget {
  final String selectedLang;
  final ValueChanged<String?> onChanged;

  const _LanguageSelector({
    required this.selectedLang,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedLang,
          icon: const Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
          style: GoogleFonts.notoSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
          isDense: true,
          items: const [
            DropdownMenuItem(value: 'en', child: Text("🇺🇸 English")),
            DropdownMenuItem(value: 'hi', child: Text("🇮🇳 Hindi")),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED OPTION ITEM - Fully Tappable
// ============================================================================
class _OptionItem extends StatelessWidget {
  final String optionText;
  final bool isSelected;
  final VoidCallback onTap;
  final String letter;
  final double devicePixelRatio;

  const _OptionItem({
    required Key key,
    required this.optionText,
    required this.isSelected,
    required this.onTap,
    required this.letter,
    required this.devicePixelRatio,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
              const BoxShadow(
                color: Color(0x103B82F6),
                blurRadius: 8,
                offset: Offset(0, 2),
              )
            ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFFF8FAFC),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: GoogleFonts.notoSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RepaintBoundary(
                  child: SmartTextRenderer(
                    text: optionText,
                    textColor: isSelected
                        ? const Color(0xFF1E3A8A)
                        : const Color(0xFF475569),
                    devicePixelRatio: devicePixelRatio,
                    selectable: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OPTIMIZED TIMER WIDGET
// ============================================================================
class _IsolatedTimerWidget extends StatelessWidget {
  final ValueNotifier<Duration> timeNotifier;

  const _IsolatedTimerWidget({required this.timeNotifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: timeNotifier,
      builder: (context, duration, child) {
        final bool isLow = duration.inMinutes < 5;
        final String text =
            "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}";

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isLow ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isLow ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: isLow ? const Color(0xFFDC2626) : const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 5),
              Text(
                text,
                style: GoogleFonts.notoSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLow ? const Color(0xFFDC2626) : const Color(0xFF1D4ED8),
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// SCRIBBLE BUTTON
// ============================================================================
class _ScribbleButton extends StatelessWidget {
  final String testId;
  final int index;
  final String text;
  final double ratio;

  const _ScribbleButton({
    required this.testId,
    required this.index,
    required this.text,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PracticeCanvasScreen(
              paperId: testId,
              questionIndex: index,
              questionText: text,
              devicePixelRatio: ratio,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.draw_rounded,
            color: Color(0xFF0EA5E9),
            size: 18,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PALETTE ITEM
// ============================================================================
class _PaletteItem extends StatelessWidget {
  final int index;
  final int status;
  final bool isCurrentQuestion;
  final VoidCallback onTap;

  const _PaletteItem({
    required this.index,
    required this.status,
    required this.isCurrentQuestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.white;
    Color txt = const Color(0xFF64748B);
    Border? border = Border.all(color: const Color(0xFFE2E8F0));

    switch (status) {
      case 1:
        bg = const Color(0xFF10B981);
        txt = Colors.white;
        border = null;
        break;
      case 2:
        bg = const Color(0xFFEF4444);
        txt = Colors.white;
        border = null;
        break;
      case 3:
        bg = const Color(0xFF8B5CF6);
        txt = Colors.white;
        border = null;
        break;
    }

    if (isCurrentQuestion) {
      border = Border.all(color: const Color(0xFF1E293B), width: 2.5);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          alignment: Alignment.center,
          child: FittedBox(
            child: Text(
              "${index + 1}",
              style: GoogleFonts.notoSans(
                color: txt,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LEGEND ITEM
// ============================================================================
class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;
  final bool isBorder;

  const _LegendItem({
    required this.color,
    required this.text,
    this.isBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isBorder ? Colors.white : color,
            shape: BoxShape.circle,
            border: isBorder
                ? Border.all(color: const Color(0xFFCBD5E1), width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.notoSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}


