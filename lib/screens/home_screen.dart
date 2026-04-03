import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:url_launcher/url_launcher.dart';

// 🟢 FIREBASE GHOST SYNC IMPORTS
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 🟢 YOUR IMPORTS
import 'pyq_screen.dart';
import 'mock_list_screen.dart';
import 'syllabus.dart';
import 'saved_questions_screen.dart';
import 'cloud_screen.dart';
import 'analytics_screen.dart';
import 'profile_screen.dart';
import 'dev.dart';

// ============================================================================
// THEME & CONSTANTS
// ============================================================================
class AppTheme {
  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color primaryPurple = Color(0xFF6366F1);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color background = Color(0xFFF5F7FA);

  static const List<Color> heroGradient = [Color(0xFF6366F1), Color(0xFF8B5CF6)];

  static const List<Color> morningGradient = [Color(0xFF4facfe), Color(0xFF00f2fe)];
  static const List<Color> noonGradient = [Color(0xFF4364F7), Color(0xFF6FB1FC)];
  static const List<Color> eveningGradient = [Color(0xFF667eea), Color(0xFF764ba2)];
  static const List<Color> nightGradient = [Color(0xFF0f2027), Color(0xFF2c5364)];

  static const List<Color> studyGradient = [Color(0xFF4F46E5), Color(0xFF4338CA)];

  static const Color menuPurple = Color(0xFF8B5CF6);
  static const Color menuOrange = Color(0xFFF59E0B);
  static const Color menuGreen = Color(0xFF10B981);
  static const Color menuRed = Color(0xFFEF4444);

  static const double cardRadius = 22.0;
  static const double buttonRadius = 14.0;
}

// ============================================================================
// MAIN HOME SCREEN (PARENT)
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool isHindi = false;
  late final PageController _pageController;

  // 🟢 OPTIMIZED TIMER STATE
  final ValueNotifier<int> _timeSpentNotifier = ValueNotifier<int>(1);
  Timer? _uiTimer;
  DateTime? _sessionStartTime;
  int _savedSecondsToday = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    _pageController = PageController(initialPage: 0);
    _loadLang();

    // 🟢 START THE ACCURATE TIME TRACKER
    _initTimeTracker();
  }

  // --------------------------------------------------------------------------
  // 🟢 SILENT BACKGROUND GHOST SYNC (Zero Lag, Offline Handled)
  // --------------------------------------------------------------------------
  Future<void> _syncGhostProfile(int completedTestsCount) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final String? lastSyncDate = prefs.getString('last_cloud_sync');

      // 1. GET THE LANGUAGE PREFERENCE
      final bool isHindiUser = prefs.getBool('isHindi') ?? false;

      // 2. SUBSCRIBE TO THE CORRECT LANGUAGE TOPIC
      if (isHindiUser) {
        await FirebaseMessaging.instance.subscribeToTopic('lang_hi');
        await FirebaseMessaging.instance.unsubscribeFromTopic('lang_en');
      } else {
        await FirebaseMessaging.instance.subscribeToTopic('lang_en');
        await FirebaseMessaging.instance.unsubscribeFromTopic('lang_hi');
      }

      if (lastSyncDate == todayString) {
        return; // Already synced today (Full sync)
      }

      UserCredential userCred = await FirebaseAuth.instance.signInAnonymously();
      String uid = userCred.user!.uid;
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      // GRAB THE NAME FROM HIVE
      if (!Hive.isBoxOpen('user_data')) await Hive.openBox('user_data');
      final String userName = Hive.box('user_data').get('name', defaultValue: "Aspirant");

      // GRAB HISTORICAL TEST IDs
      if (!Hive.isBoxOpen('exam_history')) await Hive.openBox('exam_history');
      final List<String> completedTestIds = Hive.box('exam_history').keys.map((k) => k.toString()).toList();

      // 🟢 GRAB CURRENT STREAK FOR DAILY SYNC
      final int currentStreak = prefs.getInt('current_streak') ?? 1;

      if (fcmToken != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'user_id': uid,
          'fcm_token': fcmToken,
          'tests_completed': completedTestsCount,
          'completed_test_ids': completedTestIds,
          'current_streak': currentStreak,
          'last_login': todayString,
          'language': isHindiUser ? 'hi' : 'en',
          'name': userName,
        }, SetOptions(merge: true));

        await prefs.setString('last_cloud_sync', todayString);
      }
    } catch (e) {
      // Silently catch errors so the app never crashes
      debugPrint("Ghost Sync Error: $e");
    }
  }
  // --------------------------------------------------------------------------

  Future<void> _initTimeTracker() async {
    if (!Hive.isBoxOpen('usage_stats')) await Hive.openBox('usage_stats');
    final box = Hive.box('usage_stats');
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Strictly treat all data as seconds
    _savedSecondsToday = box.get(todayKey, defaultValue: 0) as int;

    _timeSpentNotifier.value = _savedSecondsToday ~/ 60;

    _sessionStartTime = DateTime.now();
    _startUiTimer();
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateDisplayTime();
    });
  }

  void _updateDisplayTime() {
    if (_sessionStartTime == null) return;
    final int sessionSeconds = DateTime.now().difference(_sessionStartTime!).inSeconds;
    final int totalSeconds = _savedSecondsToday + sessionSeconds;

    _timeSpentNotifier.value = totalSeconds ~/ 60;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveSession();
      _uiTimer?.cancel();
      _sessionStartTime = null;
    } else if (state == AppLifecycleState.resumed) {
      _sessionStartTime = DateTime.now();
      _startUiTimer();
      _updateDisplayTime();
    }
  }

  void _handleLanguageChange(bool newValue) {
    setState(() {
      isHindi = newValue;
    });
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => isHindi = prefs.getBool('isHindi') ?? false);
  }

  Future<void> _saveSession() async {
    if (_sessionStartTime == null) return;

    final int sessionSeconds = DateTime.now().difference(_sessionStartTime!).inSeconds;
    _savedSecondsToday += sessionSeconds;
    _sessionStartTime = DateTime.now();

    try {
      if (!Hive.isBoxOpen('usage_stats')) await Hive.openBox('usage_stats');
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await Hive.box('usage_stats').put(todayKey, _savedSecondsToday);
    } catch (e) {
      debugPrint('Session save error: $e');
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    HapticFeedback.lightImpact();
    _saveSession();

    final int previousIndex = _selectedIndex;
    setState(() => _selectedIndex = index);

    if ((index - previousIndex).abs() > 1) {
      _pageController.jumpToPage(index > previousIndex ? index - 1 : index + 1);
    }

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutQuart,
    );
  }

  @override
  void dispose() {
    _saveSession();
    _uiTimer?.cancel();
    _timeSpentNotifier.dispose();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          HomeTab(
            onLanguageChanged: _handleLanguageChange,
            onForceSaveSession: _saveSession,
            timeSpentNotifier: _timeSpentNotifier,
            onGhostSyncTrigger: _syncGhostProfile,
          ),
          const AnalyticsScreen(),
          const SavedQuestionsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: FloatingIOSNavBar(
        selectedIndex: _selectedIndex,
        onTap: _onItemTapped,
        isHindi: isHindi,
      ),
    );
  }
}

// ============================================================================
// 🧠 HYBRID NAV BAR
// ============================================================================
class FloatingIOSNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;
  final bool isHindi;

  const FloatingIOSNavBar({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.isHindi,
  });

  @override
  Widget build(BuildContext context) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final bool hasButtons = bottomPadding > 40.0;

    if (hasButtons) {
      return _buildStickyBar(bottomPadding);
    } else {
      return _buildFloatingPill();
    }
  }

  Widget _buildStickyBar(double bottomPadding) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _buildNavItems(isSolid: true),
            ),
          ),
          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }

  Widget _buildFloatingPill() {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _buildNavItems(isSolid: false),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavItems({required bool isSolid}) {
    return [
      _NavItem(Icons.home_rounded, isHindi ? "होम" : "Home", 0, isSolid),
      _NavItem(Icons.bar_chart_rounded, isHindi ? "विश्लेषण" : "Analysis", 1, isSolid),
      _NavItem(Icons.bookmark_rounded, isHindi ? "सेव्ड" : "Saved", 2, isSolid),
      _NavItem(Icons.person_rounded, isHindi ? "प्रोफाइल" : "Profile", 3, isSolid),
    ];
  }

  Widget _NavItem(IconData icon, String label, int index, bool isSolid) {
    final bool isActive = selectedIndex == index;
    final Color color = isActive ? AppTheme.primaryBlue : const Color(0xFF94A3B8);
    final double scale = (isActive && !isSolid) ? 1.15 : 1.0;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap(index);
          },
          borderRadius: isSolid ? null : BorderRadius.circular(20),
          child: Container(
            height: double.infinity,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: scale,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(icon, color: color, size: 26),
                ),
                if (isActive) ...[
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HOME TAB (WITH NEW BACKGROUND OBSERVER)
// ============================================================================
class HomeTab extends StatefulWidget {
  final Function(bool) onLanguageChanged;
  final Future<void> Function() onForceSaveSession;
  final ValueNotifier<int> timeSpentNotifier;
  final Function(int) onGhostSyncTrigger;

  const HomeTab({
    super.key,
    required this.onLanguageChanged,
    required this.onForceSaveSession,
    required this.timeSpentNotifier,
    required this.onGhostSyncTrigger,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late AnimationController _entryController;

  bool isHindi = false;
  String _userName = "Aspirant";
  bool _isFirstTimeUser = true;

  bool _isLocalLoading = true;
  bool _isConfigLoading = true;

  int _completedTests = 0;
  int _streakCount = 1;

  // 🟢 VARIABLE FOR RED DOT
  bool _hasUnreadDevReply = false;

  final ValueNotifier<int> _quoteIndex = ValueNotifier<int>(0);
  Timer? _quoteTimer;
  Timer? _langDebounceTimer;

  String? _examName;
  String? _daysLeftText;

  final ScrollController _scrollController = ScrollController();

  static const List<String> _quotesEn = [
    "Success is a few practices away 🚀",
    "Make yourself proud today ✨",
    "Consistency is the key 🗝️",
    "One step closer to victory 🏆",
    "Focus on progress, not perfection 📈",
    "Believe you can and you're halfway there 🌟",
    "Don't watch the clock; keep going 🕰️",
    "The future depends on what you do today 📅",
    "It always seems impossible until it's done ✅",
    "Great things never come from comfort zones 🚧",
    "Dream bigger. Do bigger 🌌",
    "Wake up with determination. Sleep with satisfaction 🛌",
    "Do something today that your future self will thank you for 🙏",
    "Little things make big days 🌈",
    "Don't stop when you're tired. Stop when you're done 🛑",
    "Success doesn't just find you. You have to get it 🏃‍♂️",
    "Your limitation—it's only your imagination 🧠",
    "Push yourself, because no one else will 💪",
    "Hard work betrays none 🤝",
    "Stay hungry, stay foolish 🍎",
  ];

  static const List<String> _quotesHi = [
    "सफलता बस कुछ अभ्यास दूर है 🚀",
    "आज खुद को गर्व महसूस कराएं ✨",
    "निरंतरता ही सफलता की कुंजी है 🗝️",
    "जीत की ओर एक और कदम 🏆",
    "प्रगति पर ध्यान दें, पूर्णता पर नहीं 📈",
    "विश्वास रखें कि आप कर सकते हैं 🌟",
    "घड़ी को मत देखो, बस चलते रहो 🕰️",
    "भविष्य आज की मेहनत पर निर्भर है 📅",
    "जब तक हो न जाए, असंभव लगता है ✅",
    "महान चीजें कभी भी आराम क्षेत्र से नहीं आतीं 🚧",
    "बड़ा सोचो। बड़ा करो 🌌",
    "दृढ़ संकल्प के साथ जागें। संतुष्टि के साथ सोएं 🛌",
    "आज कुछ ऐसा करें कि कल खुद को शुक्रिया कहें 🙏",
    "छोटी कोशिशें बड़ी कामयाबी लाती हैं 🌈",
    "थक कर न रुकें, काम पूरा करके ही रुकें 🛑",
    "सफलता खुद चलकर नहीं आती, उसे पाना पड़ता है 🏃‍♂️",
    "आपकी सीमा केवल आपकी कल्पना है 🧠",
    "खुद को आगे बढ़ाएं, कोई और नहीं आएगा 💪",
    "कड़ी मेहनत कभी धोखा नहीं देती 🤝",
    "सीखने की भूख कभी खत्म न होने दें 🍎",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _initData();
    _setupRemoteConfig();
    _startTimers();

    // 🟢 CALL SMART POLLING WHEN APP OPENS
    _checkPendingDevReplies();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(mounted) _entryController.forward();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entryController.dispose();
    _quoteTimer?.cancel();
    _langDebounceTimer?.cancel();
    _scrollController.dispose();
    _quoteIndex.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 🟢 SMART POLLING FOR DEV REPLIES
  // --------------------------------------------------------------------------
  Future<void> _checkPendingDevReplies() async {
    try {
      if (!Hive.isBoxOpen('support_cache')) return;
      final cacheBox = Hive.box('support_cache');
      final cachedData = cacheBox.get('messages', defaultValue: []);

      if (cachedData.isEmpty) return;

      List<String> pendingDocIds = [];
      for (var msg in cachedData) {
        if (msg['admin_reply'] == null || msg['admin_reply'].toString().trim().isEmpty) {
          if (msg['id'] != null) pendingDocIds.add(msg['id']);
        }
      }

      if (pendingDocIds.isEmpty) return; // ZERO DB HITS!

      String targetDocId = pendingDocIds.first;
      final doc = await FirebaseFirestore.instance
          .collection('support_messages')
          .doc(targetDocId)
          .get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['admin_reply'] != null && data['admin_reply'].toString().trim().isNotEmpty) {
          if (mounted) {
            setState(() {
              _hasUnreadDevReply = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Silent Dev Reply Check Error: $e");
    }
  }

  // --------------------------------------------------------------------------
  // 🟢 NEW: THE PIGGYBACK BACKGROUND SYNC
  // --------------------------------------------------------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _silentPiggybackSync();
    } else if (state == AppLifecycleState.resumed) {
      // 🟢 TRIGGER SMART POLLING WHEN THEY RESUME THE APP
      _checkPendingDevReplies();
    }
  }

  DateTime? _lastPiggybackSync;

  Future<void> _silentPiggybackSync() async {
    if (_lastPiggybackSync != null && DateTime.now().difference(_lastPiggybackSync!).inSeconds < 60) {
      debugPrint("⏭️ Piggyback Skipped: Cooldown active.");
      return;
    }

    _lastPiggybackSync = DateTime.now();

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'time_spent_mins': widget.timeSpentNotifier.value,
        'tests_completed': _completedTests,
        'last_active_timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint("✅ Admin Dashboard Synced Silently in Background!");
    } catch (e) {
      debugPrint("Background Sync Error: $e");
    }
  }
  // --------------------------------------------------------------------------

  void _startTimers() {
    _quoteTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) _quoteIndex.value++;
    });
  }

  String _getTimeBasedGreeting() {
    var hour = DateTime.now().hour;
    if (isHindi) {
      if (hour < 5) return 'शुभ रात्रि';
      if (hour < 12) return 'सुप्रभात';
      if (hour < 17) return 'शुभ दोपहर';
      return 'शुभ संध्या';
    } else {
      if (hour < 5) return 'Up Late?';
      if (hour < 12) return 'Good Morning';
      if (hour < 17) return 'Good Afternoon';
      return 'Good Evening';
    }
  }

  String _formatTime(int minutes) {
    if (minutes < 1) return "1m";
    if (minutes < 60) return "${minutes}m";
    final int h = (minutes / 60).floor();
    final int m = minutes % 60;
    if (m == 0) return "${h}h";
    return "${h}h ${m}m";
  }

  Future<void> _initData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => isHindi = prefs.getBool('isHindi') ?? false);
      final userBox = await Hive.openBox('user_data');
      final name = userBox.get('name', defaultValue: "Aspirant");
      final hasVisited = prefs.getBool('has_visited_before') ?? false;

      final now = DateTime.now();
      final String todayString = DateFormat('yyyy-MM-dd').format(now);
      String? lastDateString = prefs.getString('last_streak_date');
      int currentStreak = prefs.getInt('current_streak') ?? 1;

      if (lastDateString == null) {
        currentStreak = 1;
        await prefs.setString('last_streak_date', todayString);
        await prefs.setInt('current_streak', currentStreak);
      } else if (todayString != lastDateString) {
        DateTime todayDate = DateTime.parse(todayString);
        DateTime lastDate = DateTime.parse(lastDateString);
        int difference = todayDate.difference(lastDate).inDays;

        if (difference == 1) {
          currentStreak++;
        } else if (difference > 1) {
          int missedDays = difference - 1;
          currentStreak -= missedDays;
          if (currentStreak < 1) currentStreak = 1;
        }
        await prefs.setString('last_streak_date', todayString);
        await prefs.setInt('current_streak', currentStreak);
      }

      final historyBox = await Hive.openBox('exam_history');
      int completed = historyBox.length;

      widget.onGhostSyncTrigger(completed);

      if (mounted) {
        setState(() {
          _userName = name;
          _isFirstTimeUser = !hasVisited;
          _completedTests = completed;
          _streakCount = currentStreak;
          _isLocalLoading = false;
        });
        if (!hasVisited) await prefs.setBool('has_visited_before', true);
      }
    } catch (e) {
      if (mounted) setState(() => _isLocalLoading = false);
    }
  }

  Future<void> _setupRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setDefaults({
        "exam_name": "Exam Prep",
        "exam_date": "2026-01-01",
        "test_data_version": 0,
      });
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await remoteConfig.fetchAndActivate();

      if (!Hive.isBoxOpen('app_metadata')) await Hive.openBox('app_metadata');
      final metaBox = Hive.box('app_metadata');

      int cloudVersion = remoteConfig.getInt('test_data_version');
      int localVersion = metaBox.get('local_test_version', defaultValue: 0);

      if (cloudVersion > localVersion) {
        debugPrint("🔥 NEW TEST DATA DETECTED! Breaking the 1-hour shield.");
        await metaBox.put('last_check_ts', 0);
        await metaBox.put('local_test_version', cloudVersion);
      }

      if (mounted) _processExamData(remoteConfig.getString('exam_name'), remoteConfig.getString('exam_date'));

      remoteConfig.onConfigUpdated.listen((event) async {
        await remoteConfig.activate();

        int updatedCloudVersion = remoteConfig.getInt('test_data_version');
        int currentLocalVersion = metaBox.get('local_test_version', defaultValue: 0);

        if (updatedCloudVersion > currentLocalVersion) {
          debugPrint("🔥 LIVE UPDATE DETECTED! Breaking shield.");
          await metaBox.put('last_check_ts', 0);
          await metaBox.put('local_test_version', updatedCloudVersion);
        }

        if (mounted) _processExamData(remoteConfig.getString('exam_name'), remoteConfig.getString('exam_date'));
      });
    } catch (e) {
      if (mounted) _processExamData("Exam Prep", "2026-01-01");
    } finally {
      if (mounted) setState(() => _isConfigLoading = false);
    }
  }

  void _processExamData(String name, String dateString) {
    if (dateString.isEmpty) return;
    try {
      DateTime startDate;
      DateTime endDate;

      if (dateString.contains(" to ")) {
        final parts = dateString.split(" to ");
        startDate = DateTime.parse(parts[0].trim());
        endDate = DateTime.parse(parts[1].trim());
      } else {
        startDate = DateTime.parse(dateString.trim());
        endDate = startDate;
      }

      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);
      DateTime start = DateTime(startDate.year, startDate.month, startDate.day);
      DateTime end = DateTime(endDate.year, endDate.month, endDate.day);

      String displayText;

      if (today.isAfter(end)) {
        displayText = "Exam Over";
      } else if (today.isBefore(start)) {
        int diff = start.difference(today).inDays;

        if (diff == 1) {
          displayText = "Tomorrow ⏳";
        } else if (diff < 30) {
          displayText = "$diff Days Left 🔥";
        } else {
          int months = (start.year - today.year) * 12 + start.month - today.month;
          if (months <= 0) months = 1;
          displayText = "In $months Months 🗓️";
        }
      } else {
        if (start.isAtSameMomentAs(end)) {
          displayText = "Today! 🎯";
        } else {
          displayText = "Ongoing 🔥";
        }
      }

      setState(() {
        _examName = name;
        _daysLeftText = displayText;
      });
    } catch (e) {
      debugPrint('Date Parse Error: $e');
    }
  }

  Future<void> _toggleLang() async {
    final prefs = await SharedPreferences.getInstance();
    bool newState = !isHindi;

    setState(() => isHindi = newState);
    widget.onLanguageChanged(newState);
    HapticFeedback.selectionClick();
    await prefs.setBool('isHindi', newState);

    _langDebounceTimer?.cancel();

    _langDebounceTimer = Timer(const Duration(seconds: 2), () async {
      try {
        if (newState) {
          await FirebaseMessaging.instance.subscribeToTopic('lang_hi');
          await FirebaseMessaging.instance.unsubscribeFromTopic('lang_en');
        } else {
          await FirebaseMessaging.instance.subscribeToTopic('lang_en');
          await FirebaseMessaging.instance.unsubscribeFromTopic('lang_hi');
        }

        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
            'language': newState ? 'hi' : 'en',
          }, SetOptions(merge: true));
        }
        debugPrint("✅ Firebase Language Preferences Synced Safely!");
      } catch (e) {
        debugPrint("Ghost Sync Error: $e");
      }
    });
  }

  void _navigate(Widget page, {bool fromLeft = false}) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const curve = Curves.easeOutQuart;
          var tween = Tween(begin: Offset(fromLeft ? -0.2 : 0.2, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: curve));
          return SlideTransition(position: animation.drive(tween), child: FadeTransition(opacity: animation, child: child));
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  Map<String, String> get t => isHindi
      ? {
    'pyq': 'पिछले प्रश्न',
    'saved_qs': 'सेव्ड प्रश्न',
    'mocks': 'मॉक टेस्ट',
    'syllabus': 'पाठ्यक्रम',
    'challenge_title': 'ग्रुप स्टडी',
    'battle_title': 'दोस्तों के साथ पढ़ें',
    'battle_sub': 'लाइव रूम में जुड़ें',
  }
      : {
    'pyq': 'PYQ Papers',
    'saved_qs': 'Saved Qs',
    'mocks': 'Mock Tests',
    'syllabus': 'Syllabus',
    'challenge_title': 'Group Study',
    'battle_title': 'Study with Friends',
    'battle_sub': 'Join Live Rooms',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    String greeting = _getTimeBasedGreeting();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            setState(() => _isConfigLoading = true);
            await widget.onForceSaveSession();
            await Future.wait([_initData(), _setupRemoteConfig()]);
          },
          color: AppTheme.primaryPurple,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                EntryAnimation(
                  controller: _entryController,
                  delay: 0,
                  child: RepaintBoundary(
                    child: HeroCard(
                      isLocalLoading: _isLocalLoading,
                      isConfigLoading: _isConfigLoading,
                      isFirstTime: _isFirstTimeUser,
                      completedTests: _completedTests,
                      userName: _userName,
                      isHindi: isHindi,
                      greeting: greeting,
                      streakCount: _streakCount,
                      timeSpentNotifier: widget.timeSpentNotifier,
                      examName: _examName,
                      daysLeft: _daysLeftText,
                      quoteIndexNotifier: _quoteIndex,
                      quotesEn: _quotesEn,
                      quotesHi: _quotesHi,
                      onTap: () => _navigate(const MockListScreen()),
                      formatTime: _formatTime,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                EntryAnimation(
                  controller: _entryController,
                  delay: 1,
                  child: Text(
                      isHindi ? "त्वरित पहुंच" : "Quick Access",
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary
                      )
                  ),
                ),

                const SizedBox(height: 15),

                EntryAnimation(
                  controller: _entryController,
                  delay: 2,
                  child: RepaintBoundary(child: _buildMenuGrid()),
                ),

                const SizedBox(height: 15),

                EntryAnimation(
                  controller: _entryController,
                  delay: 3,
                  child: RepaintBoundary(child: _buildCompactHelpRow()),
                ),

                const SizedBox(height: 25),

                EntryAnimation(
                  controller: _entryController,
                  delay: 4,
                  child: Text(
                      t['challenge_title']!,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary
                      )
                  ),
                ),

                const SizedBox(height: 15),

                EntryAnimation(
                  controller: _entryController,
                  delay: 5,
                  child: RepaintBoundary(child: _buildGroupStudyCard()),
                ),

                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      leading: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/icon.webp',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                isHindi ? "नमस्ते, $_userName 👋" : "Welcome, $_userName 👋",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary
                )
            ),
            Text(
                isHindi ? "चलो RRB फोड़ते हैं! 🔥" : "Let's crack the RRB! 🎯",
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500
                )
            )
          ]
      ),
      actions: [
        IconButton(
            onPressed: _toggleLang,
            icon: const Icon(Icons.g_translate_rounded, color: AppTheme.primaryBlue, size: 24)
        ),
        const SizedBox(width: 16)
      ],
    );
  }

  Widget _buildMenuGrid() {
    return Row(
        children: [
          Expanded(
              child: Column(
                  children: [
                    _buildMenuItem(t['pyq']!, Icons.history_edu_rounded, AppTheme.menuPurple, () => _navigate(const PyqScreen(), fromLeft: true)),
                    const SizedBox(height: 15),
                    _buildMenuItem(t['saved_qs']!, Icons.bookmark_added_rounded, AppTheme.menuOrange, () => _navigate(const SavedQuestionsScreen(), fromLeft: true))
                  ]
              )
          ),
          const SizedBox(width: 15),
          Expanded(
              child: Column(
                  children: [
                    _buildMenuItem(t['mocks']!, Icons.assignment_rounded, AppTheme.menuGreen, () => _navigate(const MockListScreen(), fromLeft: false)),
                    const SizedBox(height: 15),
                    _buildMenuItem(t['syllabus']!, Icons.menu_book_rounded, AppTheme.menuRed, () => _navigate(const SyllabusScreen(), fromLeft: false))
                  ]
              )
          )
        ]
    );
  }

  Widget _buildMenuItem(String title, IconData icon, Color color, VoidCallback onTap) {
    return AspectRatio(
        aspectRatio: 1.5,
        child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    splashColor: color.withOpacity(0.08),
                    highlightColor: Colors.transparent,
                    onTap: () { HapticFeedback.lightImpact(); onTap(); },
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                                  child: Icon(icon, color: color, size: 24)
                              ),
                              Flexible(
                                  child: Text(
                                      title,
                                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary, height: 1.2),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis
                                  )
                              )
                            ]
                        )
                    )
                )
            )
        )
    );
  }

  // 🟢 COMPACT HELP ROW WIRED UP WITH RED DOT
  Widget _buildCompactHelpRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMiniActionBtn(
            Icons.support_agent_rounded,
            isHindi ? "मैसेज करें" : "Message Us",
            AppTheme.primaryBlue,
                () {
              // Turn off red dot when tapped
              if (_hasUnreadDevReply) {
                setState(() => _hasUnreadDevReply = false);
              }
              _navigate(const DevScreen(), fromLeft: false);
            },
            hasBadge: _hasUnreadDevReply,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildMiniActionBtn(
              Icons.star_rate_rounded,
              isHindi ? "रेट करें" : "Rate App",
              Colors.amber.shade900,
                  () async {
                HapticFeedback.selectionClick();
                final String packageName = "com.ashirwaddigital.rrbprep";
                final Uri playStoreUri = Uri.parse("market://details?id=$packageName");
                final Uri webUri = Uri.parse("https://play.google.com/store/apps/details?id=$packageName");

                try {
                  if (!await launchUrl(playStoreUri, mode: LaunchMode.externalApplication)) {
                    await launchUrl(webUri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  await launchUrl(webUri, mode: LaunchMode.externalApplication);
                }
              }
          ),
        ),
      ],
    );
  }

  // 🟢 MINI ACTION BTN WITH RED DOT STACK
  // 🟢 MINI ACTION BTN WITH RED DOT STACK & AUTO-SHRINK TEXT
  Widget _buildMiniActionBtn(IconData icon, String title, Color color, VoidCallback onTap, {bool hasBadge = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        // Reduced padding slightly from 12 to 8 to give the text maximum breathing room
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 16),
                if (hasBadge)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4), // Tightened the gap slightly
            Flexible(
              child: FittedBox( // 🔥 THE MAGIC FIX: Shrinks text instead of clipping it!
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildGroupStudyCard() {
    return Container(
        width: double.infinity,
        decoration: BoxDecoration(
            gradient: const LinearGradient(colors: AppTheme.studyGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: AppTheme.primaryPurple.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]
        ),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
                borderRadius: BorderRadius.circular(24),
                splashColor: Colors.white.withOpacity(0.15),
                highlightColor: Colors.transparent,
                onTap: () { HapticFeedback.mediumImpact(); _navigate(const CloudScreen(), fromLeft: false); },
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                        children: [
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                              child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28)
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t['battle_title']!, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                    const SizedBox(height: 4),
                                    Text(t['battle_sub']!, style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.8)))
                                  ]
                              )
                          ),
                          Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                              child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16)
                          )
                        ]
                    )
                )
            )
        )
    );
  }
}

// ============================================================================
// ANIMATION HELPERS & WIDGETS
// ============================================================================
class EntryAnimation extends StatelessWidget {
  final AnimationController controller;
  final int delay;
  final Widget child;

  const EntryAnimation({super.key, required this.controller, required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    final double start = (delay * 0.1).clamp(0.0, 1.0);
    final double end = (start + 0.4).clamp(0.0, 1.0);
    final animation = Tween<Offset>(begin: const Offset(0.0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: controller, curve: Interval(start, end, curve: Curves.easeOutCubic)));
    final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: controller, curve: Interval(start, end, curve: Curves.easeOut)));
    return FadeTransition(opacity: fadeAnimation, child: SlideTransition(position: animation, child: child));
  }
}

class PulsingTimerIcon extends StatefulWidget {
  const PulsingTimerIcon({super.key});
  @override
  State<PulsingTimerIcon> createState() => _PulsingTimerIconState();
}

class _PulsingTimerIconState extends State<PulsingTimerIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: const Icon(Icons.timer_rounded, color: Colors.white, size: 14));
  }
}

class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const AutoScrollText({super.key, required this.text, required this.style});
  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  late ScrollController _scrollController;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }
  void _checkOverflow() {
    if (_scrollController.hasClients && _scrollController.position.maxScrollExtent > 0) _startScrolling();
  }
  void _startScrolling() async {
    if (!mounted) return;
    while (mounted && _scrollController.hasClients) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_scrollController.hasClients) break;
      await _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(seconds: 3), curve: Curves.linear);
      if (!mounted || !_scrollController.hasClients) break;
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_scrollController.hasClients) break;
      await _scrollController.animateTo(0.0, duration: const Duration(seconds: 1), curve: Curves.easeOut);
    }
  }
  @override
  void dispose() { _scrollController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style),
    );
  }
}

// ============================================================================
// HERO CARD
// ============================================================================
class HeroCard extends StatelessWidget {
  final bool isLocalLoading;
  final bool isConfigLoading;
  final bool isFirstTime;
  final int completedTests;
  final String userName;
  final bool isHindi;
  final String greeting;
  final int streakCount;
  final String? examName;
  final String? daysLeft;
  final List<String> quotesEn;
  final List<String> quotesHi;
  final VoidCallback onTap;
  final Function(int) formatTime;

  final ValueNotifier<int> quoteIndexNotifier;
  final ValueNotifier<int> timeSpentNotifier;

  const HeroCard({
    super.key,
    required this.isLocalLoading,
    required this.isConfigLoading,
    required this.isFirstTime,
    required this.completedTests,
    required this.userName,
    required this.isHindi,
    required this.greeting,
    required this.streakCount,
    required this.timeSpentNotifier,
    this.examName,
    this.daysLeft,
    required this.quoteIndexNotifier,
    required this.quotesEn,
    required this.quotesHi,
    required this.onTap,
    required this.formatTime,
  });

  List<Color> _getTimeBasedGradient() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return AppTheme.morningGradient;
    if (hour >= 11 && hour < 16) return AppTheme.noonGradient;
    if (hour >= 16 && hour < 18) return AppTheme.eveningGradient;
    return AppTheme.nightGradient;
  }

  Color _getCircleColor() {
    final hour = DateTime.now().hour;
    if (hour >= 18 || hour < 5) return Colors.white.withOpacity(0.05);
    return Colors.white.withOpacity(0.1);
  }

  @override
  Widget build(BuildContext context) {
    String title;
    String btnText;

    if (isFirstTime) {
      title = isHindi ? "आपका स्वागत है!" : "Welcome Aboard!";
      btnText = isHindi ? "शुरू करें" : "Start Journey";
    } else if (completedTests == 0) {
      title = "$greeting!";
      btnText = isHindi ? "पहला टेस्ट लें" : "Take First Test";
    } else {
      title = "$greeting!";
      btnText = isHindi ? "अभ्यास करें" : "Continue Practice";
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(seconds: 1),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _getTimeBasedGradient(),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _getTimeBasedGradient().first.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(color: _getCircleColor(), shape: BoxShape.circle),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFirstTime && !isLocalLoading)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text("NEW", style: GoogleFonts.inter(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),

                  isLocalLoading
                      ? _buildShimmerLine(200, 28)
                      : Text(title, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2)),

                  const SizedBox(height: 6),

                  isLocalLoading
                      ? _buildShimmerLine(250, 14, topMargin: 8)
                      : ValueListenableBuilder<int>(
                    valueListenable: quoteIndexNotifier,
                    builder: (context, quoteIndex, child) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        child: Text(
                          isFirstTime
                              ? (isHindi ? "सफलता की यात्रा शुरू करें" : "Your journey to success starts here.")
                              : (isHindi ? quotesHi[quoteIndex % quotesHi.length] : quotesEn[quoteIndex % quotesEn.length]),
                          key: ValueKey<int>(quoteIndex),
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withOpacity(0.9), height: 1.4),
                        ),
                      );
                    },
                  ),

                  if (!isFirstTime && !isLocalLoading) _buildStatsWidget(),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: isConfigLoading
                        ? _buildExamShimmer()
                        : (daysLeft != null && examName != null ? _buildExamDateWidget() : const SizedBox.shrink()),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: isLocalLoading
                        ? _buildShimmerLine(double.infinity, 50)
                        : ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        onTap();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _getTimeBasedGradient().last,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(btnText, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.1),
      highlightColor: Colors.white.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
            child: Container(height: 12, width: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          ),
          Container(height: 36, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10))),
        ],
      ),
    );
  }

  Widget _buildStatsWidget() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          if (completedTests > 0) ...[
            Expanded(child: _buildMiniStat(isHindi ? "प्रयास" : "Tests", "$completedTests")),
            Container(height: 20, width: 1, color: Colors.white.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 10)),
          ],

          Expanded(
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const PulsingTimerIcon(), const SizedBox(width: 6),

                  ValueListenableBuilder<int>(
                    valueListenable: timeSpentNotifier,
                    builder: (context, timeSpent, child) {
                      return Text(formatTime(timeSpent), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white));
                    },
                  ),
                ]),
              ),
              Text(isHindi ? "समय" : "Time", style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500)),
            ]),
          ),

          Container(height: 20, width: 1, color: Colors.white.withOpacity(0.3), margin: const EdgeInsets.symmetric(horizontal: 10)),

          Expanded(child: _buildMiniStat(isHindi ? "स्ट्रेक" : "Streak", "$streakCount Days")),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white))),
      Text(label, style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500))
    ]);
  }

  Widget _buildExamDateWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
          child: Text(isHindi ? "आगामी परीक्षा" : "UPCOMING EXAM", style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7), letterSpacing: 0.5)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.event_note_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 20, child: AutoScrollText(text: examName!, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text(daysLeft!, style: GoogleFonts.poppins(color: _getTimeBasedGradient().first, fontSize: 11, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerLine(double width, double height, {double topMargin = 0}) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.1),
      highlightColor: Colors.white.withOpacity(0.3),
      child: Container(margin: EdgeInsets.only(top: topMargin), height: height, width: width, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
    );
  }
}