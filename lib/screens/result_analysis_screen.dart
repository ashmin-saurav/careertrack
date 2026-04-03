import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🟢 ADDED: AdMob & Review Imports
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_review/in_app_review.dart';

// 🟢 ADDED: FIREBASE IMPORTS FOR SILENT SYNC
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🟢 IMPORTS
import '../widgets/smart_text_renderer.dart';
import '../widgets/ad_banner.dart';
import 'test_instruction_screen.dart';
import 'package:rrb_ssc_examprep/screens/practice_canvas_screen.dart';

// ⚡ VIEW MODEL - Optimized for memory efficiency
class QuestionViewModel {
  final int index;
  final String questionText;
  final List<String> options;
  final String explanation;
  final int correctIndex;
  final int? userIndex;
  final bool isWrong;
  final bool isSkipped;
  final bool isCorrect;
  final bool isComplexQuestion;
  final List<bool> isComplexOptions;
  final bool isComplexExplanation;

  QuestionViewModel({
    required this.index,
    required this.questionText,
    required this.options,
    required this.explanation,
    required this.correctIndex,
    required this.userIndex,
    required this.isWrong,
    required this.isSkipped,
    required this.isCorrect,
    required this.isComplexQuestion,
    required this.isComplexOptions,
    required this.isComplexExplanation,
  });
}

class ViewModelGenerationParams {
  final List<Map<String, dynamic>> questions;
  final List<int?> userAnswers;
  final bool isHindi;
  ViewModelGenerationParams(this.questions, this.userAnswers, this.isHindi);
}

List<QuestionViewModel> _generateViewModelsInBackground(ViewModelGenerationParams params) {
  final questions = params.questions;
  final userAnswers = params.userAnswers;
  final isHindi = params.isHindi;

  String extractText(dynamic data, String engKey, String hinKey) {
    if (data is! Map) return data?.toString() ?? "";
    if (isHindi && data.containsKey(hinKey) && data[hinKey] != null) return data[hinKey];
    if (data.containsKey(engKey)) return data[engKey] ?? "";
    if (data.containsKey('question')) return data['question'] ?? "";
    if (data.containsKey('e')) return data['e'] ?? "";
    return "";
  }

  List<String> extractOpts(Map<String, dynamic> data) {
    List<dynamic> raw = [];
    if (isHindi && data.containsKey('ho') && data['ho'] != null) raw = data['ho'];
    else if (data.containsKey('o')) raw = data['o'];
    else if (data.containsKey('opts')) raw = data['opts'];
    else if (data.containsKey('options')) raw = data['options'];
    return raw.map((e) => e.toString()).toList();
  }

  return List.generate(questions.length, (i) {
    final data = questions[i];
    final userAns = (i < userAnswers.length) ? userAnswers[i] : null;
    var rawAns = data['a'] ?? data['ans'];
    int correctIndex = (rawAns is int) ? rawAns : (int.tryParse(rawAns.toString()) ?? 0);

    String qText = extractText(data, 'q', 'hq');
    List<String> opts = extractOpts(data);
    String exp = extractText(data, 'exp', 'he');

    bool qComplex = qText.contains(r'$') || qText.contains('<');
    List<bool> oComplex = opts.map((o) => o.contains(r'$') || o.contains('<')).toList();
    bool eComplex = exp.contains(r'$') || exp.contains('<');

    return QuestionViewModel(
      index: i,
      questionText: qText,
      options: opts,
      explanation: exp,
      correctIndex: correctIndex,
      userIndex: userAns,
      isWrong: userAns != null && userAns != correctIndex,
      isSkipped: userAns == null,
      isCorrect: userAns == correctIndex,
      isComplexQuestion: qComplex,
      isComplexOptions: oComplex,
      isComplexExplanation: eComplex,
    );
  });
}

class ResultAnalysisScreen extends StatefulWidget {
  final String examTitle;
  final String testId;
  final int duration;
  final bool showRetakeButton;
  final bool isNewAttempt;

  const ResultAnalysisScreen({
    super.key,
    required this.examTitle,
    required this.testId,
    required this.duration,
    this.showRetakeButton = false,
    this.isNewAttempt = false,
  });

  @override
  State<ResultAnalysisScreen> createState() => _ResultAnalysisScreenState();
}

class _ResultAnalysisScreenState extends State<ResultAnalysisScreen> {
  late ScrollController _scrollController;

  bool _isLoading = true;
  bool _hasError = false;
  int _filterIndex = 0;
  bool _isHindi = false;

  bool _isPopping = false;

  bool _areExplanationsUnlocked = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  final String _adUnitId = 'ca-app-pub-3116634693177302/2037004651';


  List<Map<String, dynamic>> _questions = [];
  List<int?> _userAnswers = [];
  List<QuestionViewModel> _allViewModels = [];
  List<QuestionViewModel> _visibleViewModels = [];

  double? _previousScore;
  double _scoreDiff = 0.0;
  bool _showTrendBadge = false;

  String _selectedZone = "Chandigarh";
  String _selectedCategory = "UR";
  double _currentCutoff = 82.3;

  int _correct = 0;
  int _wrong = 0;
  int _skipped = 0;
  double _score = 0.0;
  double _rawScore = 0.0;
  double _totalMarks = 100.0;
  bool _isQualified = false;
  bool _isFullMock = true;

  // Data Source: RRB NTPC CBT-1 Official Cutoffs (Normalized)
  final Map<String, Map<String, double>> _zoneCutoffs = {
    // --- North Zone ---
    "Chandigarh":        {"UR": 82.27, "OBC": 71.47, "SC": 71.83, "ST": 65.90, "EWS": 70.70},
    "Ajmer":             {"UR": 77.39, "OBC": 70.93, "SC": 63.37, "ST": 60.62, "EWS": 65.00},
    "Allahabad":         {"UR": 77.49, "OBC": 70.47, "SC": 62.92, "ST": 50.12, "EWS": 66.80},
    "Jammu":             {"UR": 68.72, "OBC": 50.80, "SC": 52.20, "ST": 38.00, "EWS": 45.00},
    "Gorakhpur":         {"UR": 77.43, "OBC": 69.00, "SC": 56.63, "ST": 47.67, "EWS": 62.00},

    // --- East Zone ---
    "Kolkata":           {"UR": 79.50, "OBC": 71.53, "SC": 67.00, "ST": 52.90, "EWS": 68.00},
    "Patna":             {"UR": 80.30, "OBC": 72.50, "SC": 61.64, "ST": 58.20, "EWS": 65.00},
    "Malda":             {"UR": 61.87, "OBC": 48.40, "SC": 43.10, "ST": 31.80, "EWS": 50.00},
    "Ranchi":            {"UR": 63.75, "OBC": 57.29, "SC": 45.40, "ST": 48.58, "EWS": 49.00},
    "Bhubaneswar":       {"UR": 71.91, "OBC": 65.76, "SC": 53.09, "ST": 48.79, "EWS": 56.00},
    "Guwahati":          {"UR": 66.44, "OBC": 57.11, "SC": 52.53, "ST": 52.90, "EWS": 49.00},
    "Muzaffarpur":       {"UR": 57.97, "OBC": 45.57, "SC": 30.06, "ST": 25.00, "EWS": 40.00},
    "Siliguri":          {"UR": 67.52, "OBC": 45.90, "SC": 54.30, "ST": 45.90, "EWS": 42.00},

    // --- West Zone ---
    "Mumbai":            {"UR": 77.05, "OBC": 70.21, "SC": 63.60, "ST": 54.95, "EWS": 65.00},
    "Ahmedabad":         {"UR": 71.86, "OBC": 66.43, "SC": 60.09, "ST": 57.23, "EWS": 58.00},
    "Bhopal":            {"UR": 72.90, "OBC": 66.31, "SC": 58.61, "ST": 51.16, "EWS": 55.00},

    // --- South Zone ---
    "Bangalore":         {"UR": 71.00, "OBC": 65.00, "SC": 55.00, "ST": 51.00, "EWS": 60.00},
    "Chennai":           {"UR": 72.14, "OBC": 69.11, "SC": 57.67, "ST": 46.84, "EWS": 58.00},
    "Secunderabad":      {"UR": 77.72, "OBC": 72.80, "SC": 63.70, "ST": 59.10, "EWS": 64.00},
    "Thiruvananthapuram":{"UR": 79.75, "OBC": 75.10, "SC": 56.10, "ST": 36.40, "EWS": 55.00},

    // --- Central Zone ---
    "Bilaspur":          {"UR": 68.79, "OBC": 66.00, "SC": 51.40, "ST": 50.00, "EWS": 52.00},
  };

  final List<String> _categories = ["UR", "OBC", "SC", "ST", "EWS"];
  final String _testBaseUrl = "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/mt/";

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadAllData();
    _loadRewardedAdAsync();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 🟢 NEW: SILENT FIREBASE SYNC FOR NEW ATTEMPTS (MINIMALIST)
  // --------------------------------------------------------------------------
  Future<void> _silentTestResultSync() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('test_attempts')
          .doc(widget.testId)
          .set({
        'test_id': widget.testId,
        'score': _score,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint("✅ Silent Test Sync Complete (Minimal Data)!");
    } catch (e) {
      // Fails silently, no lag for user
      debugPrint("Silent Sync Error: $e");
    }
  }
  // --------------------------------------------------------------------------
  // --------------------------------------------------------------------------

  Future<void> _handleBack() async {
    if (_isPopping) return;
    _isPopping = true;

    bool shouldShowReview = await _shouldShowRatingPrompt();

    if (mounted) {
      Navigator.of(context).pop();
    }

    if (shouldShowReview) {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        inAppReview.requestReview();
      }
    }
  }

  Future<bool> _shouldShowRatingPrompt() async {
    try {
      const bool isTesting = false;
      final prefs = await SharedPreferences.getInstance();

      if (!Hive.isBoxOpen('exam_history')) await Hive.openBox('exam_history');
      final historyBox = Hive.box('exam_history');

      int totalTestsCompleted = historyBox.length;
      bool hasMinimumExperience = totalTestsCompleted >= 5;

      double percentage = (_totalMarks > 0) ? (_score / _totalMarks) * 100 : 0;
      bool isGoodMood = percentage >= 60.0 || _isQualified;

      int lastPromptTestCount = prefs.getInt('last_rating_prompt_test_count') ?? -100;
      bool cooldownPassed = (totalTestsCompleted - lastPromptTestCount) >= 10;

      if (isTesting || (hasMinimumExperience && isGoodMood && cooldownPassed)) {
        await prefs.setInt('last_rating_prompt_test_count', totalTestsCompleted);
        return true;
      }
    } catch (e) {
      debugPrint("Rating logic error: $e");
    }
    return false;
  }

  void _loadRewardedAdAsync() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    if (_isAdLoading || _rewardedAd != null) return;
    _isAdLoading = true;

    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _rewardedAd = ad;
            _isAdLoading = false;
          });
        },
        onAdFailedToLoad: (err) {
          if (!mounted) return;
          setState(() {
            _isAdLoading = false;
            _rewardedAd = null;
          });
        },
      ),
    );
  }

  void _showUnlockDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_open_rounded, color: Colors.amber[700], size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Unlock Solutions?",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          )
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade50, Colors.orange.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.stars_rounded, color: Colors.amber[700], size: 48),
                  const SizedBox(height: 12),
                  Text(
                    "Watch one short ad to unlock detailed explanations forever!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 15, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Master your mistakes and ace your exam! 🎯",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Maybe Later", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _playAdAndUnlock();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            icon: const Icon(Icons.play_circle_fill, size: 20),
            label: const Text("Watch & Unlock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          )
        ],
      ),
    );
  }

  void _playAdAndUnlock() {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _loadRewardedAd();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Ad failed to load. Please try again."),
                backgroundColor: Colors.orange[700],
              ),
            );
          }
        },
      );

      _rewardedAd!.show(onUserEarnedReward: (ad, reward) async {
        setState(() {
          _areExplanationsUnlocked = true;
        });
        final box = await Hive.openBox('unlocked_tests');
        await box.put(widget.testId, true);

        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text("🎉 Solutions Unlocked Forever!", style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                ],
              ),
              backgroundColor: Colors.green[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      });
      _rewardedAd = null;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Ad is loading... Please wait a moment."),
          backgroundColor: Colors.blue[700],
        ),
      );
      _loadRewardedAd();
    }
  }

  Future<void> _loadAllData() async {
    try {
      if (!mounted) return;
      setState(() { _isLoading = true; _hasError = false; });

      final unlockedBox = await Hive.openBox('unlocked_tests');
      _areExplanationsUnlocked = unlockedBox.get(widget.testId, defaultValue: false);

      if (!Hive.isBoxOpen('exam_history')) await Hive.openBox('exam_history');
      final historyBox = Hive.box('exam_history');
      final rawHistory = historyBox.get(widget.testId);
      List<int?> uAns = [];
      if (rawHistory != null && rawHistory is List) {
        uAns = rawHistory.map((e) => e as int?).toList();
      }

      if (!Hive.isBoxOpen('app_cache')) await Hive.openLazyBox('app_cache');
      final appCacheBox = Hive.lazyBox('app_cache');
      var rawQuestionsData = await appCacheBox.get(widget.testId);

      if (rawQuestionsData == null) {
        final response = await http.get(Uri.parse("$_testBaseUrl${widget.testId}.json"));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await appCacheBox.put(widget.testId, data);
          rawQuestionsData = data;
        }
      }

      List<Map<String, dynamic>> parsedQuestions = [];
      if (rawQuestionsData != null) {
        final qData = rawQuestionsData is String ? jsonDecode(rawQuestionsData) : jsonDecode(jsonEncode(rawQuestionsData));
        if (qData is Map) {
          if (qData['data'] != null) parsedQuestions = List<Map<String, dynamic>>.from(qData['data']);
          else if (qData['q'] != null) parsedQuestions = List<Map<String, dynamic>>.from(qData['q']);
          else if (qData['questions'] != null) parsedQuestions = List<Map<String, dynamic>>.from(qData['questions']);
        } else if (qData is List) {
          parsedQuestions = List<Map<String, dynamic>>.from(qData);
        }
      }

      if (parsedQuestions.isEmpty) throw Exception("No questions found");

      final prefs = await SharedPreferences.getInstance();
      _isHindi = (prefs.getString('exam_lang') ?? 'en') == 'hi';
      _selectedZone = prefs.getString('prefZone') ?? "Chandigarh";
      _selectedCategory = prefs.getString('prefCategory') ?? "UR";

      final viewModels = await compute(
          _generateViewModelsInBackground,
          ViewModelGenerationParams(parsedQuestions, uAns, _isHindi)
      );

      if (mounted) {
        setState(() {
          _questions = parsedQuestions;
          _userAnswers = uAns;
          _allViewModels = viewModels;
          _isLoading = false;
        });
        _calculateStats();
        _updateCutoffReference();
        _filterList();

        if (widget.isNewAttempt) {
          String key = 'last_score_${widget.testId}';
          double? lastScore = prefs.getDouble(key);
          if (lastScore != null) {
            _previousScore = lastScore;
            _scoreDiff = _score - lastScore;
            _showTrendBadge = true;
          }
          prefs.setDouble(key, _score);

          // 🟢 FIRE SILENT SYNC ON NEW ATTEMPT
          _silentTestResultSync();
        }
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  Future<void> _startViewModelGeneration() async {
    setState(() => _isLoading = true);
    final viewModels = await compute(
        _generateViewModelsInBackground,
        ViewModelGenerationParams(_questions, _userAnswers, _isHindi)
    );
    if (mounted) {
      setState(() {
        _allViewModels = viewModels;
        _isLoading = false;
      });
      _filterList();
    }
  }

  void _filterList() {
    if (_filterIndex == 0) _visibleViewModels = List.from(_allViewModels);
    else if (_filterIndex == 1) _visibleViewModels = _allViewModels.where((vm) => vm.isWrong).toList();
    else _visibleViewModels = _allViewModels.where((vm) => vm.isSkipped).toList();
    if (mounted) setState(() {});
  }

  void _calculateStats() {
    _correct = 0; _wrong = 0; _skipped = 0;
    for (int i = 0; i < _questions.length; i++) {
      int? userAns = (i < _userAnswers.length) ? _userAnswers[i] : null;
      var rawAns = _questions[i]['a'] ?? _questions[i]['ans'];
      int correctIndex = (rawAns is int) ? rawAns : (int.tryParse(rawAns.toString()) ?? 0);

      if (userAns == null) _skipped++;
      else if (userAns == correctIndex) _correct++;
      else _wrong++;
    }
    _rawScore = (_correct * 1.0) - (_wrong * 0.33);
    if (_rawScore < 0) _rawScore = 0;
    _score = _rawScore;

    _totalMarks = _questions.length.toDouble();
    // 🟢 UPDATED: Only show Zone Analysis for 100+ questions
    _isFullMock = _totalMarks >= 100.0;
  }

  Future<void> _saveCutoffPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('prefZone', _selectedZone);
    await prefs.setString('prefCategory', _selectedCategory);
    await prefs.setString('exam_lang', _isHindi ? 'hi' : 'en');
    _updateCutoffReference();
  }

  void _updateCutoffReference() {
    _currentCutoff = _zoneCutoffs[_selectedZone]?[_selectedCategory] ?? 75.0;
    _isQualified = _score >= _currentCutoff;
    if (mounted) setState(() {});
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
            : _hasError
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 56),
          const SizedBox(height: 20),
          Text("Failed to load results", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh),
            label: const Text("Retry"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ]))
            : Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 5,
                radius: const Radius.circular(10),
                interactive: true,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  cacheExtent: 500,
                  slivers: [
                    _buildAppBar(),

                    if (_isFullMock) SliverToBoxAdapter(child: _buildCutoffSelector()),

                    SliverToBoxAdapter(child: _buildCompactScoreCard()),

                    if (_isFullMock) SliverToBoxAdapter(child: _buildZoneAnalysisCard()),

                    SliverToBoxAdapter(child: _buildDisclaimer()),
                    SliverToBoxAdapter(child: _buildStatsGrid()),

                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyFilterDelegate(child: _buildFilterBar()),
                    ),

                    if (_visibleViewModels.isEmpty)
                      SliverFillRemaining(child: _buildEmptyState())
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              return _QuestionAnalysisCard(
                                key: ValueKey(_visibleViewModels[index].index),
                                data: _visibleViewModels[index],
                                testId: widget.testId,
                                isHindi: _isHindi,
                                isUnlocked: _areExplanationsUnlocked,
                                onUnlockPressed: _showUnlockDialog,
                              );
                            },
                            childCount: _visibleViewModels.length,
                          ),
                        ),
                      ),

                    SliverToBoxAdapter(child: _buildFooter()),
                    const SliverToBoxAdapter(child: SizedBox(height: 30)),
                  ],
                ),
              ),
            ),
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: AdBanner(size: AdSize.banner),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- COMPACT & RESPONSIVE SCORE CARD ---
  Widget _buildCompactScoreCard() {
    double percentage = (_score / _totalMarks) * 100;

    // Define motivational data based on score ranges
    String statusTitle, statusMessage, motivationQuote;
    Color primaryColor, secondaryColor;
    IconData statusIcon;
    List<Color> gradientColors;

    // -----------------------------------------------------------
    // LOGIC START: Determines Status, Color, and Quote
    // -----------------------------------------------------------

    if (_isFullMock) {
      double diff = _score - _currentCutoff;

      if (diff >= 10) {
        // Tier 1: Super Safe Zone
        statusTitle = _isHindi ? "शानदार! 🏆" : "Exceptional! 🏆";
        statusMessage = _isHindi ? "कटऑफ से बहुत आगे" : "Far above cutoff";
        motivationQuote = _isHindi ? "आप टॉपर की राह पर हैं!" : "You're on the path to excellence!";
        primaryColor = const Color(0xFF10B981);
        secondaryColor = const Color(0xFF059669);
        statusIcon = Icons.emoji_events_rounded;
        gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
      } else if (diff >= 5) {
        // Tier 2: Safe Zone
        statusTitle = _isHindi ? "बेहतरीन! 🎉" : "Outstanding! 🎉";
        statusMessage = _isHindi ? "कटऑफ से काफी आगे" : "Well above cutoff";
        motivationQuote = _isHindi ? "बस यूं ही करते रहो!" : "Keep up this amazing work!";
        primaryColor = const Color(0xFF10B981);
        secondaryColor = const Color(0xFF059669);
        statusIcon = Icons.verified_rounded;
        gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
      } else if (diff >= 0) {
        // Tier 3: Cleared
        statusTitle = _isHindi ? "बढ़िया! ✨" : "Great! ✨";
        statusMessage = _isHindi ? "कटऑफ क्लियर" : "Cutoff cleared";
        motivationQuote = _isHindi ? "अब फोकस रखो और सुधरते जाओ!" : "Stay focused and keep improving!";
        primaryColor = const Color(0xFF8B5CF6);
        secondaryColor = const Color(0xFF7C3AED);
        statusIcon = Icons.check_circle_rounded;
        gradientColors = [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
      } else if (diff >= -5) {
        // Tier 4: Almost There (0 to -5)
        statusTitle = _isHindi ? "बस पास! 💪" : "Almost There! 💪";
        statusMessage = _isHindi ? "कटऑफ के करीब" : "Missed by a whisker";
        motivationQuote = _isHindi ? "एक और धक्का और मंजिल मिल जाएगी!" : "One more push and the seat is yours!";
        primaryColor = const Color(0xFFF59E0B);
        secondaryColor = const Color(0xFFD97706);
        statusIcon = Icons.trending_up_rounded;
        gradientColors = [const Color(0xFFF59E0B), const Color(0xFFD97706)];
      } else if (diff >= -15) {
        // Tier 5: Fighting Distance (-5 to -15)
        statusTitle = _isHindi ? "हार मत मानो! ⚔️" : "Don't Give Up! ⚔️";
        statusMessage = _isHindi ? "लक्ष्य की रेंज में" : "Within striking distance";
        motivationQuote = _isHindi ? "सिली मिस्टेक्स सुधारो, जीत पक्की है।" : "Fix your silly mistakes and you will fly.";
        primaryColor = const Color(0xFFEA580C);
        secondaryColor = const Color(0xFFC2410C);
        statusIcon = Icons.bolt_rounded;
        gradientColors = [const Color(0xFFFB923C), const Color(0xFFEA580C)];
      } else if (diff >= -30) {
        // Tier 6: Needs Analysis (-15 to -30)
        statusTitle = _isHindi ? "विश्लेषण जरूरी 📈" : "Needs Analysis 📈";
        statusMessage = _isHindi ? "कॉन्सेप्ट्स कमजोर" : "Concepts need work";
        motivationQuote = _isHindi ? "टेस्ट रोको, विश्लेषण करो। कॉन्सेप्ट क्लियर करो।" : "Stop testing, start analysing. You need clarity.";
        primaryColor = const Color(0xFFEF4444);
        secondaryColor = const Color(0xFFB91C1C);
        statusIcon = Icons.analytics_rounded;
        gradientColors = [const Color(0xFFF87171), const Color(0xFFDC2626)];
      } else if (diff >= -50) {
        // Tier 7: Foundation Building (-30 to -50)
        statusTitle = _isHindi ? "नींव मजबूत करें 🧱" : "Time to Rebuild 🧱";
        statusMessage = _isHindi ? "कॉन्सेप्ट्स पर ध्यान दें" : "Focus on concepts";
        motivationQuote = _isHindi ? "धीमी शुरुआत भी शुरुआत है। रुकना मना है।" : "Slow progress is still progress. Don't stop.";
        primaryColor = const Color(0xFFBF6F14);
        secondaryColor = const Color(0xFF92400E);
        statusIcon = Icons.construction_rounded;
        gradientColors = [const Color(0xFFFBBF24), const Color(0xFFD97706)];
      } else {
        // Tier 8: Fresh Start (<-50)
        statusTitle = _isHindi ? "नई शुरुआत 🌱" : "New Journey 🌱";
        statusMessage = _isHindi ? "सीखने का समय" : "Learning phase";
        motivationQuote = _isHindi ? "हर एक्सपर्ट कभी बिगिनर था। चलते रहो।" : "Every expert started as a beginner. Keep going.";
        primaryColor = const Color(0xFF3B82F6);
        secondaryColor = const Color(0xFF1D4ED8);
        statusIcon = Icons.school_rounded;
        gradientColors = [const Color(0xFF60A5FA), const Color(0xFF2563EB)];
      }
    } else {
      // -------------------------------------------------------
      // PRACTICE TESTS (Percentage Based) - Unchanged
      // -------------------------------------------------------
      if (percentage >= 85) {
        statusTitle = _isHindi ? "परफेक्ट! 🌟" : "Perfect! 🌟";
        statusMessage = _isHindi ? "शानदार परफॉर्मेंस" : "Excellent performance";
        motivationQuote = _isHindi ? "आप मास्टर बनते जा रहे हो!" : "You're mastering this!";
        primaryColor = const Color(0xFF10B981);
        secondaryColor = const Color(0xFF059669);
        statusIcon = Icons.stars_rounded;
        gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
      } else if (percentage >= 80) {
        statusTitle = _isHindi ? "बहुत बढ़िया! 🎯" : "Excellent! 🎯";
        statusMessage = _isHindi ? "टॉप परफॉर्मेंस" : "Top performance";
        motivationQuote = _isHindi ? "आपकी मेहनत रंग ला रही है!" : "Your hard work is paying off!";
        primaryColor = const Color(0xFF10B981);
        secondaryColor = const Color(0xFF059669);
        statusIcon = Icons.workspace_premium_rounded;
        gradientColors = [const Color(0xFF10B981), const Color(0xFF059669)];
      } else if (percentage >= 75) {
        statusTitle = _isHindi ? "अच्छा! 👏" : "Very Good! 👏";
        statusMessage = _isHindi ? "मजबूत समझ" : "Strong understanding";
        motivationQuote = _isHindi ? "थोड़ा और पुश करो, टॉप पर पहुंच जाओगे!" : "Push a bit more, you'll reach the top!";
        primaryColor = const Color(0xFF8B5CF6);
        secondaryColor = const Color(0xFF7C3AED);
        statusIcon = Icons.thumb_up_rounded;
        gradientColors = [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
      } else if (percentage >= 60) {
        statusTitle = _isHindi ? "ठीक है! 👍" : "Good! 👍";
        statusMessage = _isHindi ? "अच्छी प्रोग्रेस" : "Good progress";
        motivationQuote = _isHindi ? "सही दिशा में जा रहे हो!" : "You're on the right track!";
        primaryColor = const Color(0xFF8B5CF6);
        secondaryColor = const Color(0xFF7C3AED);
        statusIcon = Icons.trending_up_rounded;
        gradientColors = [const Color(0xFF8B5CF6), const Color(0xFF7C3AED)];
      } else if (percentage >= 40) {
        statusTitle = _isHindi ? "कोशिश जारी! 💡" : "Keep Trying! 💡";
        statusMessage = _isHindi ? "और रिवीज़न चाहिए" : "Needs more revision";
        motivationQuote = _isHindi ? "रोज़ थोड़ा प्रैक्टिस करो, फर्क दिखेगा!" : "Daily practice makes a difference!";
        primaryColor = const Color(0xFFEA580C);
        secondaryColor = const Color(0xFFC2410C);
        statusIcon = Icons.lightbulb_rounded;
        gradientColors = [const Color(0xFFF59E0B), const Color(0xFFD97706)];
      } else if (percentage >= 20) {
        statusTitle = _isHindi ? "शुरुआत! 🎯" : "Starting Out! 🎯";
        statusMessage = _isHindi ? "बेसिक्स पर फोकस करो" : "Focus on basics";
        motivationQuote = _isHindi ? "हर छोटा कदम तुम्हें आगे ले जाता है!" : "Every small step takes you forward!";
        primaryColor = const Color(0xFF3B82F6);
        secondaryColor = const Color(0xFF2563EB);
        statusIcon = Icons.school_rounded;
        gradientColors = [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
      } else {
        statusTitle = _isHindi ? "शुरुआत! 🌱" : "Just Starting! 🌱";
        statusMessage = _isHindi ? "बहुत सीखना बाकी है" : "Lots to learn";
        motivationQuote = _isHindi ? "डरो मत, रोज़ प्रैक्टिस करो, आगे बढ़ते जाओगे!" : "Don't worry, practice daily and you'll grow!";
        primaryColor = const Color(0xFF3B82F6);
        secondaryColor = const Color(0xFF2563EB);
        statusIcon = Icons.rocket_launch_rounded;
        gradientColors = [const Color(0xFF3B82F6), const Color(0xFF2563EB)];
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles (smaller)
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -15,
            left: -15,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                // Header with edit button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isHindi ? "आपका स्कोर" : "YOUR SCORE",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Compact Score Display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _score.toStringAsFixed(1),
                      style: GoogleFonts.outfit(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 6),
                      child: Text(
                        "/ ${_totalMarks.toInt()}",
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Percentage badge (smaller)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "${percentage.toStringAsFixed(1)}%",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Compact Status Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(statusIcon, color: primaryColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  statusTitle,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  statusMessage,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.85),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.format_quote_rounded, color: Colors.white.withOpacity(0.5), size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                motivationQuote,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- OTHER WIDGETS ---
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "No questions found",
            style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFFF8FAFC),
      elevation: 0,
      pinned: true,
      toolbarHeight: 64,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.close_rounded, color: Color(0xFF1E293B), size: 20),
        ),
        onPressed: () => _handleBack(),
      ),
      centerTitle: true,
      title: Column(
        children: [
          Text(
            _isHindi ? "रिजल्ट एनालिसिस" : "Result Analysis",
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
          Text(
            widget.examTitle,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _langBtn("EN", !_isHindi),
              const SizedBox(width: 8),
              _langBtn("HI", _isHindi),
            ],
          ),
        )
      ],
    );
  }

  Widget _langBtn(String text, bool active) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isHindi = (text == "HI");
          _startViewModelGeneration();
        });
        _saveCutoffPrefs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? Colors.transparent : Colors.grey.shade300),
          boxShadow: active ? [
            BoxShadow(
              color: const Color(0xFF1E293B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : [],
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildCutoffSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _dropdownColumn(
              _isHindi ? "लक्ष्य जोन" : "Target Zone",
              _selectedZone,
              _zoneCutoffs.keys.toList(),
                  (val) {
                if (val != null) {
                  setState(() {
                    _selectedZone = val;
                    _saveCutoffPrefs();
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 2,
            child: _dropdownColumn(
              _isHindi ? "श्रेणी" : "Category",
              _selectedCategory,
              _categories,
                  (val) {
                if (val != null) {
                  setState(() {
                    _selectedCategory = val;
                    _saveCutoffPrefs();
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownColumn(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        DropdownButton<String>(
          value: value,
          isDense: true,
          underline: const SizedBox(),
          isExpanded: true,
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildZoneAnalysisCard() {
    List<String> highChance = [];
    List<String> borderline = [];

    _zoneCutoffs.forEach((zone, cutoffs) {
      if (zone == _selectedZone) return;
      double cutoff = cutoffs[_selectedCategory] ?? 75.0;
      if (_score >= cutoff + 2) highChance.add(zone);
      else if (_score >= cutoff - 3) borderline.add(zone);
    });

    if (!_isQualified && highChance.isEmpty) {
      double gap = _currentCutoff - _score;
      return _buildMotivationCard(
        title: _isHindi ? "आगे बढ़ते रहें! 💪" : "Keep Pushing! 💪",
        body: _isHindi
            ? "आप लक्ष्य से सिर्फ ${gap.toStringAsFixed(1)} अंक दूर हैं। नियमित प्रैक्टिस से ये गैप आसानी से पूरा हो जाएगा।"
            : "You are just ${gap.toStringAsFixed(1)} marks away. Regular practice will bridge this gap easily.",
        color: const Color(0xFFF59E0B),
        icon: Icons.trending_up_rounded,
        items: [],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
              Icon(Icons.location_on_rounded, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                _isHindi ? "जोन विश्लेषण" : "Zone Analysis",
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (highChance.isNotEmpty) ...[
            _probabilityRow(_isHindi ? "बहुत अच्छी संभावना:" : "Strong Chances:", highChance.take(5).toList(), const Color(0xFF10B981)),
            const SizedBox(height: 12),
          ],
          if (borderline.isNotEmpty)
            _probabilityRow(_isHindi ? "पहुंच में:" : "Within Reach:", borderline.take(5).toList(), const Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  Widget _probabilityRow(String label, List<String> zones, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: zones.map((z) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              z,
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildMotivationCard({
    required String title,
    required String body,
    required Color color,
    required IconData icon,
    required List<String> items,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: color, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
          ),
          child: ExpansionTile(
            shape: Border.all(color: Colors.transparent),
            collapsedShape: Border.all(color: Colors.transparent),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Icon(Icons.shield_rounded, color: Colors.green[700], size: 22),
            title: Text(
              _isHindi ? "सफलता का मंत्र" : "Your Path to Success",
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[900]),
            ),
            children: [
              Text(
                _isHindi
                    ? "यह विश्लेषण पिछले वर्षों के डेटा और सामान्य ट्रेंड्स पर आधारित है।\n\nयह वास्तविक परीक्षा से पूरी तरह मेल खा भी सकता है और नहीं भी। आपकी सफलता आपकी मेहनत, निरंतर अभ्यास और परीक्षा के दिन के आत्मविश्वास पर निर्भर करती है।\n\nहर मॉक टेस्ट आपको बेहतर बनाता है। गलतियाँ सीखने का हिस्सा हैं, हार नहीं।\n\nखुद पर विश्वास रखें, खुद को साबित करें, और अपने माता-पिता को आप पर गर्व करने का मौका दें।"
                    : "This analysis is based on previous years' data and general trends.\n\nIt may not exactly match the real exam. Your success depends on your effort, consistency, and confidence on exam day.\n\nEvery mock test helps you grow. Mistakes are lessons, not failures.\n\nKeep believing in yourself, prove your worth, and make yourself and your parents proud of you.",
                style: GoogleFonts.inter(fontSize: 12, color: Colors.green[800], height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem("$_correct", _isHindi ? "सही" : "Correct", const Color(0xFF10B981)),
          _verticalDivider(),
          _statItem("$_wrong", _isHindi ? "गलत" : "Wrong", const Color(0xFFEF4444)),
          _verticalDivider(),
          _statItem("$_skipped", _isHindi ? "छोड़े" : "Skipped", const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _verticalDivider() => Container(height: 30, width: 1, color: Colors.grey.shade200);

  Widget _statItem(String val, String label, Color color) {
    return Column(
      children: [
        Text(
          val,
          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: const Color(0xFFF8FAFC),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterChip(0, _isHindi ? "सभी" : "All", Icons.list_alt_rounded),
          const SizedBox(width: 10),
          _filterChip(1, _isHindi ? "गलत" : "Wrong", Icons.cancel_rounded),
          const SizedBox(width: 10),
          _filterChip(2, _isHindi ? "छोड़े" : "Skipped", Icons.skip_next_rounded),
        ],
      ),
    );
  }

  Widget _filterChip(int index, String label, IconData icon) {
    bool isActive = _filterIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterIndex = index;
          _filterList();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isActive ? Colors.transparent : Colors.grey.shade300),
          boxShadow: isActive ? [
            BoxShadow(
              color: const Color(0xFF1E293B).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? Colors.white : Colors.grey[700],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (!widget.showRetakeButton) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ElevatedButton.icon(
        onPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TestInstructionScreen(
              title: widget.examTitle,
              duration: widget.duration,
              testId: widget.testId,
            ),
          ),
        ),
        icon: const Icon(Icons.refresh_rounded, color: Colors.white),
        label: Text(
          _isHindi ? "फिर से टेस्ट दें" : "RETAKE TEST",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: 0.8, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
      ),
    );
  }
}

class _StickyFilterDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _StickyFilterDelegate({required this.child});

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: const Color(0xFFF8FAFC), child: child);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

class _QuestionAnalysisCard extends StatefulWidget {
  final QuestionViewModel data;
  final String testId;
  final bool isHindi;
  final bool isUnlocked;
  final VoidCallback onUnlockPressed;

  const _QuestionAnalysisCard({
    super.key,
    required this.data,
    required this.testId,
    required this.isHindi,
    required this.isUnlocked,
    required this.onUnlockPressed,
  });

  @override
  State<_QuestionAnalysisCard> createState() => _QuestionAnalysisCardState();
}

class _QuestionAnalysisCardState extends State<_QuestionAnalysisCard> {
  bool _showSolution = false;
  bool _hasScribble = false;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _checkScribble();
    _checkIfSaved();
  }

  Future<void> _checkScribble() async {
    final key = "${widget.testId}_q${widget.data.index}";
    if (!Hive.isBoxOpen('drawings')) await Hive.openBox('drawings');
    final box = Hive.box('drawings');
    if (mounted && box.containsKey(key)) {
      setState(() {
        _hasScribble = true;
      });
    }
  }

  Future<void> _checkIfSaved() async {
    final box = await Hive.openBox('saved_questions');
    final key = "${widget.testId}_${widget.data.index}";
    if (mounted) setState(() => _isSaved = box.containsKey(key));
  }

  Future<void> _toggleSave() async {
    final box = await Hive.openBox('saved_questions');
    final key = "${widget.testId}_${widget.data.index}";

    if (box.containsKey(key)) {
      await box.delete(key);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Removed from saved questions"), duration: Duration(seconds: 1)));
    } else {
      await box.put(key, {
        "id": key,
        "paperId": widget.testId,
        "examName": "Mock Test",
        "category": "MOCK",
        "index": widget.data.index,
        "savedAt": DateTime.now().toIso8601String(),
        "questionData": {
          "q": widget.data.questionText,
          "o": widget.data.options,
          "a": widget.data.correctIndex,
          "exp": widget.data.explanation
        }
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Question Saved!"), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
    }
    _checkIfSaved();
  }

  Future<void> _launchGPT() async {
    var box = await Hive.openBox('user_data');
    final name = box.get('name', defaultValue: 'Aspirant');

    final cleanQ = widget.data.questionText.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '').trim();

    String formattedOptions = "";
    for (int i = 0; i < widget.data.options.length; i++) {
      formattedOptions += "\n${String.fromCharCode(65 + i)}) ${widget.data.options[i]}";
    }

    final fullPrompt = "Explain to $name:\nQuestion: $cleanQ\n\nOptions:$formattedOptions";
    final url = Uri.parse("https://chatgpt.com/?q=${Uri.encodeComponent(fullPrompt)}");

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch ChatGPT");
    }
  }

  Widget _buildStyledText(String text) {
    List<String> parts = text.split('**');
    List<TextSpan> spans = [];
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        spans.add(TextSpan(
          text: parts[i],
          style: GoogleFonts.inter(color: const Color(0xFF334155), fontSize: 14, height: 1.6),
        ));
      } else {
        spans.add(TextSpan(
          text: parts[i],
          style: GoogleFonts.inter(
            color: const Color(0xFF1E293B),
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.circle_outlined;
    String statusText = widget.isHindi ? "छोड़ा" : "Skipped";
    Color cardBorderColor = Colors.grey.shade200;

    if (d.isCorrect) {
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
      statusText = widget.isHindi ? "सही (+1.0)" : "Correct (+1.0)";
      cardBorderColor = const Color(0xFFD1FAE5);
    } else if (d.isWrong) {
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.cancel_rounded;
      statusText = widget.isHindi ? "गलत (-0.33)" : "Wrong (-0.33)";
      cardBorderColor = const Color(0xFFFECDD3);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      "Q.${d.index + 1}",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFF1E293B), fontSize: 16),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          await _toggleSave();
                        },
                        borderRadius: BorderRadius.circular(50),
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Icon(
                            _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                            color: _isSaved ? const Color(0xFF2563EB) : Colors.grey.shade400,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_hasScribble)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PracticeCanvasScreen(
                                paperId: widget.testId,
                                questionIndex: d.index,
                                questionText: d.questionText,
                                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                              ),
                            ));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Icon(Icons.draw_rounded, size: 16, color: Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, color: statusColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: d.isComplexQuestion
                ? SmartTextRenderer(
              text: d.questionText,
              textColor: const Color(0xFF1E293B),
              devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
            )
                : Text(
              d.questionText,
              style: GoogleFonts.inter(
                fontSize: 16,
                height: 1.6,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              children: List.generate(d.options.length, (i) {
                bool isOptionCorrect = (i == d.correctIndex);
                bool isOptionWrongSelected = (i == d.userIndex && d.isWrong);

                Color bg = Colors.white;
                Color border = Colors.grey.shade200;
                Color text = const Color(0xFF475569);
                FontWeight weight = FontWeight.normal;

                if (isOptionCorrect) {
                  bg = const Color(0xFFD1FAE5);
                  border = const Color(0xFF10B981);
                  text = const Color(0xFF065F46);
                  weight = FontWeight.w600;
                } else if (isOptionWrongSelected) {
                  bg = const Color(0xFFFECDD3);
                  border = const Color(0xFFEF4444);
                  text = const Color(0xFF7F1D1D);
                  weight = FontWeight.w600;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: border, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isOptionCorrect || isOptionWrongSelected ? border.withOpacity(0.2) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: border.withOpacity(0.5)),
                        ),
                        child: Text(
                          String.fromCharCode(65 + i),
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: text, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: d.isComplexOptions[i]
                            ? SmartTextRenderer(text: d.options[i], textColor: text, devicePixelRatio: 1.0)
                            : Text(
                          d.options[i],
                          style: GoogleFonts.inter(color: text, fontWeight: weight, fontSize: 14, height: 1.5),
                        ),
                      ),
                      if (isOptionCorrect)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle_rounded, color: const Color(0xFF10B981), size: 20),
                        ),
                      if (isOptionWrongSelected)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.cancel_rounded, color: const Color(0xFFEF4444), size: 20),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
          if (d.explanation.isNotEmpty)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                color: _showSolution ? const Color(0xFFFFFBEB) : Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onTap: () {
                        if (widget.isUnlocked) {
                          setState(() => _showSolution = !_showSolution);
                        } else {
                          widget.onUnlockPressed();
                        }
                      },
                      borderRadius: _showSolution
                          ? BorderRadius.zero
                          : const BorderRadius.vertical(bottom: Radius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: widget.isUnlocked
                                    ? (_showSolution ? Colors.amber.shade100 : Colors.grey.shade100)
                                    : Colors.red.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.isUnlocked ? Icons.lightbulb_rounded : Icons.lock_outline_rounded,
                                size: 18,
                                color: widget.isUnlocked
                                    ? (_showSolution ? Colors.amber[700] : Colors.grey[500])
                                    : Colors.red[400],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.isUnlocked
                                    ? (widget.isHindi ? "समाधान देखें" : "View Solution")
                                    : (widget.isHindi ? "समाधान अनलॉक करें" : "Unlock Solution"),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: widget.isUnlocked
                                      ? (_showSolution ? Colors.amber[800] : const Color(0xFF64748B))
                                      : Colors.red[600],
                                ),
                              ),
                            ),
                            if (widget.isUnlocked)
                              AnimatedRotation(
                                turns: _showSolution ? 0.5 : 0,
                                duration: const Duration(milliseconds: 300),
                                child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey[500]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showSolution && widget.isUnlocked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            d.isComplexExplanation
                                ? LayoutBuilder(
                              builder: (context, constraints) {
                                return SizedBox(
                                  width: constraints.maxWidth,
                                  child: SmartTextRenderer(
                                    text: d.explanation,
                                    textColor: const Color(0xFF78350F),
                                    devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
                                  ),
                                );
                              },
                            )
                                : _buildStyledText(d.explanation),

                            const SizedBox(height: 12),
                            const Divider(color: Color(0xFFFDE68A)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _launchGPT,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset('assets/chatgpt.webp', width: 20, height: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Ask AI for more details",
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF92400E)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.arrow_outward_rounded, size: 14, color: Color(0xFF92400E))
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5FF),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _launchGPT,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFD8B4FE)),
                          ),
                          child: Image.asset('assets/chatgpt.webp', width: 18, height: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Ask AI for more details",
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF7E22CE),
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF7E22CE)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}