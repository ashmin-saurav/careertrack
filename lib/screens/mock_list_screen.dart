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
// 🟢 ADDED: AdMob Import
import 'package:google_mobile_ads/google_mobile_ads.dart';
// 🟢 ADDED: Remote Config Import
import 'package:firebase_remote_config/firebase_remote_config.dart';

// 🟢 IMPORTS
import 'test_instruction_screen.dart';
import 'result_analysis_screen.dart';
import 'cloud_screen.dart';

// 🟢 GLOBAL DESIGN TOKENS
const Color _bgCol = Color(0xFFF5F7FA);
const Color _primaryCol = Color(0xFF1565C0);
const Color _textPrimary = Color(0xFF1E293B);
const Color _textSecondary = Color(0xFF64748B);
const Color _premiumCol = Color(0xFF384F2C);
const Color _goldCol = Color(0xFFFFD700);

// 🟢 COLORS FOR SUBJECT CHIPS (Pre-defined for zero lag)
const List<Color> _chipBgs = [Color(0xFFE0F2FE), Color(0xFFFEF9C3), Color(0xFFFCE7F3), Color(0xFFDCFCE7), Color(0xFFF3E8FF)];
const List<Color> _chipTexts = [Color(0xFF0284C7), Color(0xFFCA8A04), Color(0xFFDB2777), Color(0xFF16A34A), Color(0xFF7E22CE)];

// 🟢 HELPER: SUPER SAFE DURATION CALCULATOR
int _calculateDuration(Map test) {
  try {
    if (test['d'] != null) return int.parse(test['d'].toString());
    dynamic rawT = test['t'];
    int type = 0;
    if (rawT is int)
      type = rawT;
    else if (rawT is String) {
      if (rawT == 'm' || rawT == 'mt') type = 10;
    } else if (rawT is double) {
      type = rawT.toInt();
    }
    return (type >= 10) ? 90 : 30;
  } catch (e) {
    return 30;
  }
}

// ✅ FIX 1: SECONDARY SORT by `id` descending when dates are equal.
// This keeps all tests belonging to the same week grouped together,
// preventing repeated section headers like "WEEK 4 / WEEK 3 / WEEK 4".
// 🟢 FIXED ISOLATE PARSER WITH WEEK EXTRACTION & DEBUG LOGS
List<dynamic> _parseAndSortBackground(List<String> jsonStrings) {
  List<dynamic> combinedTests = [];
  for (String jsonStr in jsonStrings) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        combinedTests.addAll(decoded);
      } else if (decoded is Map && decoded.containsKey('tests')) {
        combinedTests.addAll(decoded['tests']);
      }
    } catch (_) {}
  }

  print("==== STARTING SORT LOGIC ====");

  combinedTests.sort((a, b) {
    try {
      String idA = a['id']?.toString() ?? "";
      String idB = b['id']?.toString() ?? "";

      final int dateA = int.tryParse(a['dr']?.toString() ?? "0") ?? 0;
      final int dateB = int.tryParse(b['dr']?.toString() ?? "0") ?? 0;

      // 1. PRIMARY SORT: By Date (Descending)
      int dateCmp = dateB.compareTo(dateA);
      if (dateCmp != 0) {
        return dateCmp;
      }

      // 2. SECONDARY SORT: Extract Week Number if dates are equal (March tests)
      int weekA = 0;
      int weekB = 0;

      // Use Regex to find "-w1", "-w2", etc., at the end of the ID
      final wMatchA = RegExp(r'-w(\d+)$').firstMatch(idA);
      if (wMatchA != null) weekA = int.parse(wMatchA.group(1)!);

      final wMatchB = RegExp(r'-w(\d+)$').firstMatch(idB);
      if (wMatchB != null) weekB = int.parse(wMatchB.group(1)!);

      // Compare the extracted week numbers (Descending: 4, then 3, then 2...)
      if (weekA != weekB) {
        return weekB.compareTo(weekA);
      }

      // 3. TERTIARY SORT: If Date AND Week are the same, sort alphabetically by Subject
      return idA.compareTo(idB);

    } catch (e) {
      return 0;
    }
  });

  // 🟢 DEBUG PRINT: Show the final list order in the console!
  print("==== FINAL SORTED TEST LIST ====");
  for (int i = 0; i < combinedTests.length; i++) {
    final t = combinedTests[i];
    print("Pos $i | ID: ${t['id']} | Date: ${t['dr']}");
  }
  print("================================");

  return combinedTests;
}

class MockListScreen extends StatefulWidget {
  // 🟢 ADDED: Flag to know if we came from a push notification
  final bool forceRefreshFromPush;

  const MockListScreen({
    super.key,
    this.forceRefreshFromPush = false, // Defaults to false for normal navigation
  });

  @override
  State<MockListScreen> createState() => _MockListScreenState();
}

class _MockListScreenState extends State<MockListScreen>
    with AutomaticKeepAliveClientMixin {
  // 🟢 ADMOB CONFIGURATION
  final String _premiumAdUnitId = 'ca-app-pub-3116634693177302/2037004651';

  List<dynamic> _allTests = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isRepairing = false;

  // 🟢 FILTERS
  int _topTab = 0; // 0 = Live, 1 = Completed
  int _subFilter = 0; // 0 = All, 1 = Mocks, 2 = Practice
  final Set<String> _selectedTopicFilters = {};
  List<String> _availableTopics = [];

  late LazyBox _cacheBox;
  late Box _metaBox;
  late Box _historyBox;
  late Box _unlockedBox;
  Box? _userBox;
  bool _isHindi = false;

  // 🟢 UPCOMING TEST STATE
  String? _upcomingDateStr;

// 🟢 MOVED OUTSIDE: Compile regex exactly once to prevent scroll lag
  static final RegExp _weekRegex = RegExp(
      r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s*Week\s*(\d+)",
      caseSensitive: false);
  // 🟢 YOUR R2 URL
  final String _rawBaseUrl =
      "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/testmt/index";

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      _cacheBox = await Hive.openLazyBox('test_data_cache');
      _metaBox = await Hive.openBox('app_metadata');
      _historyBox = await Hive.openBox('exam_history');
      _unlockedBox = await Hive.openBox('unlocked_premium_tests');

      // We don't need the userBox for language anymore,
      // but keep it if you need it for other things.

      // 🟢 ADD AWAIT HERE
      await _loadLanguage();

      await _performCacheCleanup();
      _fetchUpcomingDate();

      if (!mounted) return;

      await _loadFromCache();
      _checkForNewContent();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // 🟢 FIREBASE FETCH FOR UPCOMING BANNER
  // 🟢 FIREBASE FETCH FOR UPCOMING BANNER & SHIELD BREAKER
  Future<void> _fetchUpcomingDate() async {
    try {
      final rc = FirebaseRemoteConfig.instance;

      // 🟢 CRITICAL: Set minimumFetchInterval to ZERO here!
      // This ensures that when a user taps a notification, the app actually
      // talks to Firebase instead of using a 1-hour old cached Remote Config value.
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ));

      await rc.fetchAndActivate();

      // 1. UPDATE THE BANNER DATE
      final dateStr = rc.getString('upcoming_test_date');
      if (dateStr.isNotEmpty) {
        final DateTime targetDate = DateTime.parse(dateStr);
        if (targetDate.isAfter(DateTime.now())) {
          if (mounted) {
            setState(() {
              _upcomingDateStr = dateStr;
            });
          }
        }
      }

      // 2. 🛡️ THE SHIELD BREAKER 🛡️
      // If we opened this screen directly from a notification,
      // this will catch the new version and destroy the throttle!
      int cloudVersion = rc.getInt('test_data_version');
      int localVersion = _metaBox.get('local_test_version', defaultValue: 0);

      if (cloudVersion > localVersion) {
        print("🔥 DIRECT NOTIFICATION SHIELD BREAKER ACTIVATED!");

        // Destroy the 1-hour throttle
        await _metaBox.put('last_check_ts', 0);
        // Save the new version so we don't break it twice
        await _metaBox.put('local_test_version', cloudVersion);

        // Force the app to fetch the new test right now!
        _checkForNewContent();
      }

    } catch (e) {
      print("Remote Config Fetch Error: $e");
    }
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isHindi = prefs.getBool('isHindi') ?? false;
      });
    }
  }

  Future<void> _performCacheCleanup() async {
    try {
      final box = Hive.lazyBox('app_cache');
      if (box.length > 20) {
        final int itemsToDelete = box.length - 20;
        final keysToDelete = box.keys.take(itemsToDelete).toList();
        await box.deleteAll(keysToDelete);
      }
    } catch (_) {}
  }

  Future<void> _performAutoRepair() async {
    if (_isRepairing) return;
    _isRepairing = true;
    try {
      await _cacheBox.clear();
      await _metaBox.put('max_index', 0);
      setState(() {
        _allTests = [];
        _isLoading = true;
        _hasError = false;
      });
      await _fetchSpecificIndex(0, forceRefresh: true);
      await _loadFromCache();
    } catch (e) {
    } finally {
      if (mounted)
        setState(() {
          _isRepairing = false;
        });
    }
  }

  Future<void> _loadFromCache() async {
    final int maxIndex = _metaBox.get('max_index', defaultValue: 0);
    List<String> cachedJsons = [];

    for (int i = 0; i <= maxIndex; i++) {
      final String? jsonStr = await _cacheBox.get('index_$i');
      if (jsonStr != null) cachedJsons.add(jsonStr);
    }

    if (cachedJsons.isEmpty) {
      await _fetchSpecificIndex(0, forceRefresh: false);
      return;
    }
    final sortedData = await compute(_parseAndSortBackground, cachedJsons);
    if (mounted) _updateUiData(sortedData);
  }

  Future<void> _checkForNewContent() async {
    final int lastCheck = _metaBox.get('last_check_ts', defaultValue: 0);
    final DateTime now = DateTime.now();

    // 🟢 NEW THROTTLE: Only automatically check once per hour.
    if (now.difference(DateTime.fromMillisecondsSinceEpoch(lastCheck)).inHours < 1 &&
        _allTests.isNotEmpty) {
      print("==== AUTO-FETCH SKIPPED (Checked less than 1 hour ago) ====");
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    int currentMax = _metaBox.get('max_index', defaultValue: 0);
    bool foundNewData = false;

    // 1. FIRST: Check existing files (index0.json) for 304 updates
    for (int i = 0; i <= currentMax; i++) {
      await _fetchSpecificIndex(i, forceRefresh: false);
    }

    // 2. SECOND: Check if you uploaded a brand new file (index1.json, etc)
    int safetyCounter = 0;
    while (safetyCounter < 10) {
      int nextIndex = currentMax + 1;
      bool success = await _fetchSpecificIndex(nextIndex, forceRefresh: true);
      if (success) {
        currentMax = nextIndex;
        foundNewData = true;
        await _metaBox.put('max_index', currentMax);
      } else {
        break; // 404 hit, no new index files.
      }
      safetyCounter++;
    }

    // 🟢 SAVE TIMESTAMP: Record exactly when we just checked.
    await _metaBox.put('last_check_ts', now.millisecondsSinceEpoch);

    // 3. Always reload cache after checking, to ensure UI is fresh
    await _loadFromCache();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasError = false;
      });
    }
  }

  Future<bool> _fetchSpecificIndex(int index,
      {required bool forceRefresh}) async {
    try {
      final String url = "$_rawBaseUrl$index.json";
      final String metaKey = 'last_modified_$index';

      print("==== FETCH TRIGGERED ====");
      print("URL: $url");
      print("Force Refresh (Pull-to-Refresh): $forceRefresh");

      Map<String, String> headers = {};

      // Retrieve the saved timestamp
      final String? savedLastModified = _metaBox.get(metaKey);
      print("Saved Last-Modified in Hive: $savedLastModified");

      if (forceRefresh) {
        // First-ever fetch or manual pull: bypass any intermediary cache
        headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
        headers['Pragma'] = 'no-cache';
        headers['Expires'] = '0';
        print("Headers applied: Force No-Cache");
      } else if (savedLastModified != null && savedLastModified.isNotEmpty) {
        // Attach If-Modified-Since if we have a saved timestamp
        headers['If-Modified-Since'] = savedLastModified;
        print("Headers applied: If-Modified-Since = $savedLastModified");
      } else {
        print("Headers applied: None (No saved timestamp and not a force refresh)");
      }

      print("Sending HTTP GET request...");
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 25));
      print("Response Status Code: ${response.statusCode}");

      if (response.statusCode == 200) {
        print("RESULT: 200 OK - Downloading full JSON body.");
        // Full download — save content and record the Last-Modified timestamp
        await _cacheBox.put('index_$index', response.body);

        final String? lastModified = response.headers['last-modified'];
        if (lastModified != null && lastModified.isNotEmpty) {
          print("New Last-Modified received from server: $lastModified");
          await _metaBox.put(metaKey, lastModified);
        } else {
          print("Warning: Server did not return a last-modified header.");
        }

        if (index == 0 && _allTests.isEmpty) {
          final sortedData =
          await compute(_parseAndSortBackground, [response.body]);
          if (mounted) _updateUiData(sortedData);
        }
        print("==== FETCH COMPLETE (200) ====");
        return true;
      }

      // ✅ HTTP 304: Server confirmed nothing changed — use existing Hive cache.
      // No bandwidth consumed, no Cloudflare cost, UI stays up-to-date.
      if (response.statusCode == 304) {
        print("RESULT: 304 Not Modified — Server says our cache is still the latest.");
        print("Zero data downloaded! Using Hive cache.");
        final String? cached = await _cacheBox.get('index_$index');
        print("==== FETCH COMPLETE (304) ====");
        return cached != null; // treat as success if we have local data
      }

      print("RESULT: Unknown or Error status code - ${response.statusCode}");
      print("==== FETCH COMPLETE (ERROR) ====");

    } catch (e) {
      print("==== FETCH CRASHED ====");
      print("Error details: $e");
    }

    if (_allTests.isEmpty && mounted && index == 0)
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    return false;
  }

  void _updateUiData(List<dynamic> data) {
    if (!mounted) return;
    final Set<String> tags = {};
    for (var test in data) {
      if (test['su'] != null) {
        for (var tag in test['su']) {
          if (tag != null) tags.add(tag.toString());
        }
      }
    }
    setState(() {
      _allTests = data;
      _availableTopics = tags.toList()..sort();
      _isLoading = false;
      _hasError = false;
    });
  }

  // 🟢 SAFELY MODIFIED FILTER LOGIC
  List<dynamic> _getSafeFilteredList(Box historyBox) {
    try {
      final DateTime now = DateTime.now();
      final String formattedNowStr =
          "${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
      final int currentDateInt = int.parse(formattedNowStr);

      List<dynamic> liveUnattempted = [];
      List<dynamic> liveAttempted = [];
      List<dynamic> completedTests = [];

      for (var t in _allTests) {
        try {
          if (t['dr'] != null) {
            final int testDate = int.parse(t['dr'].toString());
            if (testDate > currentDateInt) continue;
          }
          dynamic rawT = t['t'];
          int type = 0;
          if (rawT is int)
            type = rawT;
          else if (rawT is String) {
            if (rawT == 'm' || rawT == 'mt') type = 10;
          } else if (rawT is double) {
            type = rawT.toInt();
          }
          final bool isMock = (type == 10 || type == 11);
          final bool isAttempted = historyBox.containsKey(t['id']);

          if (_subFilter == 1) {
            if (!isMock) continue;
          } else if (_subFilter == 2) {
            if (isMock) continue;
          }

          if (_selectedTopicFilters.isNotEmpty) {
            final List subjects = t['su'] ?? [];
            if (!_selectedTopicFilters
                .any((selected) => subjects.contains(selected))) continue;
          }

          if (_topTab == 0) {
            if (isAttempted) {
              liveAttempted.add(t);
            } else {
              liveUnattempted.add(t);
            }
          } else {
            if (isAttempted) {
              completedTests.add(t);
            }
          }
        } catch (e) {
          continue;
        }
      }

      if (_topTab == 0) return [...liveUnattempted, ...liveAttempted];
      return completedTests;

    } catch (e) {
      throw Exception("Data Corrupt");
    }
  }

  void _onRetakeTap(Map test, bool isPremium) {
    final bool isAlreadyUnlocked = _unlockedBox.containsKey(test['id']);
    if (isPremium && !isAlreadyUnlocked) {
      _showUnlockDialog(test, isRetake: true);
    } else {
      _handleCardTap(test, false); // Retake forces it to act unattempted
    }
  }

  void _onAnalysisTap(Map test) {
    _handleCardTap(test, true); // True forces it to open analysis
  }

  void _onCardTap(Map test, bool isAttempted, bool isPremium) {
    final bool isAlreadyUnlocked = _unlockedBox.containsKey(test['id']);
    if (isPremium && !isAttempted && !isAlreadyUnlocked) {
      _showUnlockDialog(test, isRetake: false);
    } else {
      _handleCardTap(test, isAttempted);
    }
  }

  void _loadAndShowAd(Map test, {required bool isRetake}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_goldCol))),
    );

    RewardedAd.load(
      adUnitId: _premiumAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (mounted) Navigator.pop(context);
          ad.show(
              onUserEarnedReward:
                  (AdWithoutView ad, RewardItem reward) async {
                await _unlockedBox.put(test['id'], true);
                _handleCardTap(test, isRetake ? false : false);
              });
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (mounted) Navigator.pop(context);
          debugPrint('Ad failed to load: $error');
          _handleCardTap(test, isRetake ? false : false);
        },
      ),
    );
  }

  void _showUnlockDialog(Map test, {required bool isRetake}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.workspace_premium_rounded,
              color: Colors.amber, size: 28),
          const SizedBox(width: 8),
          Text(_isHindi ? "प्रीमियम टेस्ट" : "Premium Test",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold))
        ]),
        content: Text(
          _isHindi
              ? "इस टेस्ट को अनलॉक करने के लिए एक छोटा विज्ञापन देखें।"
              : "Watch a short ad to unlock this premium test.",
          style: GoogleFonts.inter(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isHindi ? "रद्द करें" : "Cancel",
                style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadAndShowAd(test, isRetake: isRetake);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: _premiumCol,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text(_isHindi ? "अनलॉक (विज्ञापन)" : "Unlock (Watch Ad)",
                style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _handleCardTap(Map test, bool isAttempted) async {
    HapticFeedback.lightImpact();
    final String testId = test['id'];
    final String title = test['ti'] ?? "Result";
    final int duration = _calculateDuration(test);

    if (isAttempted) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ResultAnalysisScreen(
                examTitle: title,
                testId: testId,
                duration: duration,
                showRetakeButton: true,
              )));
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TestInstructionScreen(
                  title: title, duration: duration, testId: testId)));
    }
  }

  Future<void> _onRefresh() async {
    await _fetchSpecificIndex(0, forceRefresh: true);
    await _loadFromCache();
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 24),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            _isHindi ? 'विषय फ़िल्टर' : 'Filter by Topic',
                            style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary)),
                        GestureDetector(
                            onTap: () => setModalState(() {
                              _selectedTopicFilters.clear();
                            }),
                            child: Text(_isHindi ? 'रीसेट' : 'Reset',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w600)))
                      ]),
                  const SizedBox(height: 20),
                  Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableTopics.map((topic) {
                        return GestureDetector(
                          onTap: () => setModalState(() {
                            _selectedTopicFilters.contains(topic)
                                ? _selectedTopicFilters.remove(topic)
                                : _selectedTopicFilters.add(topic);
                          }),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                  color: _selectedTopicFilters.contains(topic)
                                      ? _primaryCol
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(topic.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                      color:
                                      _selectedTopicFilters.contains(topic)
                                          ? Colors.white
                                          : Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12))),
                        );
                      }).toList()),
                  const SizedBox(height: 32),
                  SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                          onPressed: () {
                            setState(() {});
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryCol,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: Text(
                              _isHindi ? "लागू करें" : "Apply Filters",
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600))))
                ]),
          );
        },
      ),
    );
  }

  // 🟢 SAFELY MODIFIED GET SECTION TITLE
  String _getSectionTitle(Map test, bool isAttempted) {
    if (_topTab == 0 && isAttempted) return _isHindi ? "पूर्ण किए गए टेस्ट" : "ATTEMPTED MOCKS";

    try {
      final String title = test['ti'] ?? "";
      final match = _weekRegex.firstMatch(title);
      if (match != null)
        return "${match.group(1)!.toUpperCase()} • WEEK ${match.group(2)!}";

      if (test['dr'] != null) {
        String dr = test['dr'].toString();
        int month = int.parse(dr.substring(2, 4));
        final DateTime date = DateTime(2000, month, 1);
        final String monthName = DateFormat('MMMM').format(date).toUpperCase();
        return "$monthName • RECENT";
      }
    } catch (_) {}
    return _isHindi ? "हाल के टेस्ट" : "RECENT TESTS";
  }

  // 🟢 FORMAT UPCOMING DATE
  String _formatUpcomingDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = DateTime(date.year, date.month, date.day).difference(DateTime(now.year, now.month, now.day)).inDays;
      final timeForm = DateFormat('h:mm a').format(date);

      if (diff == 0) return _isHindi ? "आज, $timeForm" : "Today, $timeForm";
      if (diff == 1) return _isHindi ? "कल, $timeForm" : "Tomorrow, $timeForm";
      return DateFormat('MMM dd, h:mm a').format(date);
    } catch (_) { return ""; }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading && _allTests.isEmpty) {
      return const Scaffold(
          backgroundColor: _bgCol,
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _bgCol,
      body: ValueListenableBuilder(
        valueListenable: _historyBox.listenable(),
        builder: (context, Box box, _) {
          List filteredTests = [];
          try {
            filteredTests = _getSafeFilteredList(box);
          } catch (e) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _performAutoRepair());
            return const Center(child: CircularProgressIndicator(color: _primaryCol));
          }

          if (_hasError && filteredTests.isEmpty) {
            return const Center(child: Text("Error"));
          }
          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: _primaryCol,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              slivers: [
                SliverAppBar(
                  expandedHeight: 70.0,
                  pinned: true,
                  floating: false,
                  backgroundColor: _bgCol,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  leading: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ]),
                      child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: _textPrimary, size: 20),
                          onPressed: () => Navigator.pop(context))),
                  centerTitle: true,
                  title: Text(_isHindi ? "मॉक टेस्ट" : "Mock Tests",
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary)),
                  actions: [
                    Container(
                        width: 40,
                        margin: const EdgeInsets.only(
                            right: 12, top: 8, bottom: 8),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.groups_2_rounded,
                                color: _primaryCol, size: 22),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const CloudScreen())))),
                    Container(
                        width: 40,
                        margin: const EdgeInsets.only(
                            right: 16, top: 8, bottom: 8),
                        decoration: BoxDecoration(
                            color: _selectedTopicFilters.isNotEmpty
                                ? _primaryCol
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(Icons.tune_rounded,
                                color: _selectedTopicFilters.isNotEmpty
                                    ? Colors.white
                                    : _textPrimary,
                                size: 20),
                            onPressed: _showFilterSheet)),
                  ],
                ),
                SliverPersistentHeader(
                    delegate: _StickyTabDelegate(child: _buildTopTabs()),
                    pinned: true),

                // 🟢 UPCOMING BANNER
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutQuart,
                    child: (_topTab == 0 && _upcomingDateStr != null)
                        ? Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_isHindi ? "नया मॉक टेस्ट" : "New Mock Test", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 2),
                                Text(_formatUpcomingDate(_upcomingDateStr!), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9))),
                              ],
                            ),
                          )
                        ],
                      ),
                    )
                        : const SizedBox.shrink(),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        _buildSubFilterChip(
                            _isHindi ? "सभी" : "All", 0),
                        const SizedBox(width: 8),
                        _buildSubFilterChip(
                            _isHindi ? "मॉक टेस्ट" : "Mock Tests", 1),
                        const SizedBox(width: 8),
                        _buildSubFilterChip(
                            _isHindi ? "प्रैक्टिस" : "Practice", 2),
                      ],
                    ),
                  ),
                ),
                if (!_isLoading && filteredTests.isEmpty)
                  SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded,
                                  size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                  _isHindi
                                      ? "कोई टेस्ट नहीं मिला"
                                      : "No Tests Found",
                                  style: GoogleFonts.poppins(
                                      color: _textSecondary))
                            ],
                          )))
                else
                  SliverPadding(
                    padding:
                    const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final test = filteredTests[index];
                              final bool isAttempted =
                              box.containsKey(test['id']);

                              int type = 0;
                              try {
                                dynamic rawT = test['t'];
                                if (rawT is int)
                                  type = rawT;
                                else if (rawT is String &&
                                    (rawT == 'm' || rawT == 'mt'))
                                  type = 10;
                              } catch (_) {}

                              final bool isPremium = (type == 1 || type == 11);
                              final bool isMock = (type == 10 || type == 11);

                              final String currentSection =
                              _getSectionTitle(test as Map, isAttempted);
                              final String prevSection = (index > 0)
                                  ? _getSectionTitle(
                                  filteredTests[index - 1] as Map, box.containsKey(filteredTests[index - 1]['id']))
                                  : "";
                              final bool showHeader =
                                  currentSection != prevSection;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showHeader)
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            top: 20, bottom: 12, left: 4),
                                        child: Text(currentSection,
                                            style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.grey[500],
                                                letterSpacing: 1.0))),
                                  TestCard(
                                    test: test,
                                    isAttempted: isAttempted,
                                    isLiveTab: _topTab == 0,
                                    isHindi: _isHindi,
                                    isPremium: isPremium,
                                    isMock: isMock,
                                    onCardTap: () => _onCardTap(
                                        test, isAttempted, isPremium),
                                    onRetake: () => _onRetakeTap(test, isPremium),
                                    onAnalysis: () => _onAnalysisTap(test),
                                  ),
                                ],
                              );
                            }, childCount: filteredTests.length)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
        color: _bgCol,
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                  child: _buildTopTabItem(
                      _isHindi ? "लाइव टेस्ट" : "Live Tests", 0)),
              Expanded(
                  child: _buildTopTabItem(
                      _isHindi ? "पूर्ण" : "Completed", 1)),
            ])));
  }

  Widget _buildTopTabItem(String title, int index) {
    final bool isSelected = _topTab == index;
    return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _topTab = index);
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: isSelected ? _primaryCol : Colors.transparent,
                borderRadius: BorderRadius.circular(10)),
            child: Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                    isSelected ? Colors.white : _textSecondary))));
  }

  Widget _buildSubFilterChip(String title, int index) {
    final bool isSelected = _subFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _subFilter = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: isSelected ? _primaryCol : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSelected
                      ? _primaryCol
                      : Colors.grey.shade300),
              boxShadow: isSelected
                  ? [
                BoxShadow(
                    color: _primaryCol.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ]
                  : []),
          child: Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color:
                  isSelected ? Colors.white : _textSecondary)),
        ),
      ),
    );
  }
}

class _StickyTabDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _StickyTabDelegate({required this.child});
  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: _bgCol, child: Center(child: child));
  @override
  bool shouldRebuild(_StickyTabDelegate oldDelegate) => true;
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _controller,
        child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Colors.red, shape: BoxShape.circle)));
  }
}

class TestCard extends StatelessWidget {
  final Map test;
  final bool isAttempted;
  final bool isLiveTab;
  final bool isHindi;
  final bool isPremium;
  final bool isMock;
  final VoidCallback onCardTap;
  final VoidCallback onRetake;
  final VoidCallback onAnalysis;

  const TestCard(
      {super.key,
        required this.test,
        required this.isAttempted,
        required this.isLiveTab,
        required this.isHindi,
        required this.isPremium,
        required this.isMock,
        required this.onCardTap,
        required this.onRetake,
        required this.onAnalysis});

  @override
  Widget build(BuildContext context) {
    final String title = test['ti'] ?? "Test";
    int questions = 0;
    try {
      questions = int.parse(test['q'].toString());
    } catch (_) {}

    final int duration = _calculateDuration(test);
    final String? specialMessage = test['mes'] ?? test['me'];
    final List subjects = test['su'] ?? [];

    final List langs = test['l'] ?? ['en'];
    String langText = "English";
    if (langs.contains('hi') && langs.contains('en'))
      langText = isHindi ? "हिंदी और अंग्रेजी" : "Hindi & English";
    else if (langs.contains('hi')) langText = isHindi ? "हिंदी" : "Hindi";

    bool isNew = false;
    try {
      if (test['dr'] != null) {
        final String dr = test['dr'].toString();
        final DateTime testDate = DateTime(
            2000 + int.parse(dr.substring(0, 2)),
            int.parse(dr.substring(2, 4)),
            int.parse(dr.substring(4, 6)));
        isNew = DateTime.now().difference(testDate).inDays <= 4;
      }
    } catch (_) {}

    final bool isHot = !isNew && !isAttempted;

    Color cardBg = Colors.white;
    BoxBorder? cardBorder;

    if (isPremium) {
      cardBg = _premiumCol;
      cardBorder = Border.all(color: _goldCol.withOpacity(0.3), width: 1);
    } else if (isMock) {
      cardBg = const Color(0xFFFFFBE6);
      cardBorder = Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3), width: 1);
    }

    final Color mainTextCol = isPremium ? Colors.white : _textPrimary;
    final Color subTextCol = isPremium ? Colors.white70 : _textSecondary;
    final Color iconCol = isPremium ? Colors.white60 : Colors.grey[400]!;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: cardBorder,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8))
            ]),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onCardTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: Row(children: [
                              if (isPremium) ...[
                                const Icon(Icons.workspace_premium_rounded,
                                    color: _goldCol, size: 20),
                                const SizedBox(width: 8)
                              ] else if (isMock) ...[
                                const Icon(Icons.star_rounded,
                                    color: Color(0xFFD4AF37), size: 20),
                                const SizedBox(width: 8)
                              ],
                              if (specialMessage != null) ...[
                                _Badge(
                                    text: specialMessage.toUpperCase(),
                                    bg: isPremium
                                        ? Colors.white24
                                        : const Color(0xFFF3E8FF),
                                    textCol: isPremium
                                        ? Colors.white
                                        : const Color(0xFF7E22CE)),
                                const SizedBox(width: 8)
                              ],
                              if (isNew && !isAttempted)
                                const _Badge(
                                    text: "NEW",
                                    bg: Color(0xFFFEF2F2),
                                    textCol: Color(0xFFEF4444))
                              else if (isHot)
                                const _Badge(
                                    text: "HOT 🔥",
                                    bg: Color(0xFFFFF7ED),
                                    textCol: Color(0xFFC2410C)),
                            ])),
                      ]),
                  const SizedBox(height: 12),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: mainTextCol,
                          height: 1.3)),
                  const SizedBox(height: 8),

                  // 🟢 OPTIMIZED SUBJECT CHIPS
                  if (subjects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: subjects.map((s) {
                            final String str = s.toString();
                            final int idx = str.hashCode.abs() % _chipBgs.length;
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: isPremium ? Colors.white.withOpacity(0.15) : _chipBgs[idx], borderRadius: BorderRadius.circular(6)),
                              child: Text(str.toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: isPremium ? Colors.white : _chipTexts[idx])),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                  Row(children: [
                    Icon(Icons.translate_rounded,
                        size: 14,
                        color: subTextCol.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(langText,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: subTextCol))
                  ]),

                  const SizedBox(height: 12),
                  Divider(
                      color: isPremium
                          ? Colors.white24
                          : Colors.grey.withOpacity(0.1),
                      height: 1),
                  const SizedBox(height: 12),

                  // 🟢 FIXED: Time and Qs always visible!
                  Row(children: [
                    Icon(Icons.timer_outlined, size: 16, color: iconCol),
                    const SizedBox(width: 6),
                    Text("$duration ${isHindi ? 'मिनट' : 'Mins'}",
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: subTextCol)),
                    const SizedBox(width: 20),
                    Icon(Icons.format_list_numbered_rounded,
                        size: 16, color: iconCol),
                    const SizedBox(width: 6),
                    Text("$questions ${isHindi ? 'प्रश्न' : 'Qs'}",
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: subTextCol)),
                    const Spacer(),

                    // 🟢 Status Badge: LIVE vs DONE
                    if (!isAttempted) ...[
                      const RepaintBoundary(child: _LiveDot()),
                      const SizedBox(width: 6),
                      Text(isHindi ? "लाइव" : "LIVE",
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isPremium ? _goldCol : Colors.red)),
                    ] else ...[
                      Icon(Icons.check_circle_rounded,
                          size: 16,
                          color: isPremium ? _goldCol : Colors.green),
                      const SizedBox(width: 4),
                      Text(isHindi ? "पूर्ण" : "DONE",
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isPremium ? _goldCol : Colors.green)),
                    ]
                  ]),

                  // 🟢 FIXED: Buttons sit UNDERNEATH the stats
                  if (isAttempted) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: OutlinedButton(
                              onPressed: onRetake,
                              style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                  isPremium ? Colors.white : _primaryCol,
                                  side: BorderSide(
                                      color: isPremium
                                          ? Colors.white30
                                          : _primaryCol.withOpacity(0.3)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10)),
                              child: Text(isHindi ? "पुनः प्रयास" : "RETAKE",
                                  style: GoogleFonts.inter(
                                      fontSize: 12, fontWeight: FontWeight.bold)),
                            )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: ElevatedButton(
                              onPressed: onAnalysis,
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  isPremium ? _goldCol : _primaryCol,
                                  foregroundColor:
                                  isPremium ? _premiumCol : Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 10)),
                              child: Text(isHindi ? "विश्लेषण" : "ANALYSIS",
                                  style: GoogleFonts.inter(
                                      fontSize: 12, fontWeight: FontWeight.bold)),
                            )),
                      ],
                    )
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color textCol;
  const _Badge(
      {required this.text, required this.bg, required this.textCol});
  @override
  Widget build(BuildContext context) {
    return Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: textCol)));
  }
}