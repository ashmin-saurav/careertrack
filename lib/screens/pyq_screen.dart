import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🟢 MAKE SURE THESE IMPORTS EXIST IN YOUR PROJECT
import 'quiz_screen.dart';
import '../widgets/ad_banner.dart';

// ---------------------------------------------------------------------------
// 🟢 ISOLATE PARSER (Runs in Background)
// ---------------------------------------------------------------------------
List<Map<String, dynamic>> _parseAndCleanInBackground(String responseBody) {
  try {
    // 🧹 1. CLEANING
    String cleanBody = responseBody
        .replaceAll(String.fromCharCode(160), ' ')
        .replaceAll(RegExp(r'[\u00A0\u200B\u200C\u200D\uFEFF]'), ' ')
        .trim();

    final dynamic decoded = jsonDecode(cleanBody);
    final List<dynamic> rawList = decoded is List ? decoded : [];

    if (rawList.isEmpty) return [];

    final List<Map<String, dynamic>> result = [];

    for (var rawItem in rawList) {
      String rawTitle = rawItem['title'] ?? "Unknown Paper";
      String id = rawItem['id']?.toString() ?? "";
      final String upperTitle = rawTitle.toUpperCase();

      if (!upperTitle.contains("NTPC")) continue;

      String levelBadge = "GRADUATE";
      if (id.contains("_ug_") || id.contains("_12th_") || upperTitle.contains("UNDER GRADUATE") || upperTitle.contains("12TH")) {
        levelBadge = "UNDER GRADUATE";
      } else if (id.contains("_g_") || upperTitle.contains("GRADUATE")) {
        levelBadge = "GRADUATE";
      }

      String examBadge = "NTPC";
      String yearBadge = "";
      final yearMatch = RegExp(r"20[1-2][0-9]").firstMatch(rawTitle);
      if (yearMatch != null) yearBadge = yearMatch.group(0)!;

      String stageBadge = "";
      final stageMatch = RegExp(r'\b(CBT|TIER)\s*[-]?\s*[12]\b', caseSensitive: false).firstMatch(rawTitle);
      if (stageMatch != null) {
        stageBadge = stageMatch.group(0)!.toUpperCase().replaceAll("-", " ");
      }

      String langBadge = "ENGLISH";
      if (upperTitle.contains("HINDI") || rawTitle.contains("हिन्दी") || id.contains("_hi_")) {
        langBadge = "HINDI";
      } else if (upperTitle.contains("BENGALI")) {
        langBadge = "BENGALI";
      }

      String displayTitle = rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();

      result.add({
        "id": id,
        "rawTitle": rawTitle,
        "displayTitle": displayTitle,
        "questions": rawItem['questions'] ?? 0,
        "ts": rawItem['ts'] ?? 0,
        "examBadge": examBadge,
        "yearBadge": yearBadge,
        "stageBadge": stageBadge,
        "langBadge": langBadge,
        "levelBadge": levelBadge,
      });
    }
    return result;
  } catch (e) {
    debugPrint("❌ CRITICAL PARSING ERROR: $e");
    return [];
  }
}

// ---------------------------------------------------------------------------
// 🟢 MAIN SCREEN
// ---------------------------------------------------------------------------
class PyqScreen extends StatefulWidget {
  const PyqScreen({super.key});

  @override
  State<PyqScreen> createState() => _PyqScreenState();
}

class _PyqScreenState extends State<PyqScreen> {
  // 🟢 CONFIGURATION
  static const String _baseUrl = "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/";
  static const String _indexFileName = "py/index.json";
  static const String _boxName = "pyq_master_cache";
  static const String _prefsBox = "user_prefs";
  static const int _cacheDurationHours = 3;

  // 🧠 RAM CACHE
  static List<Map<String, dynamic>>? _ramCache;

  // 🎨 PALETTE
  static const Color _bg = Color(0xFFF0F4F8);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _cardBg = Colors.white;
  static const Color _textDark = Color(0xFF1E293B);
  static const Color _textLight = Color(0xFF64748B);
  static const Color _orangeBadge = Color(0xFFD97706);
  static const Color _orangeBg = Color(0xFFFFF7ED);
  static const Color _tealBadge = Color(0xFF0D9488);

  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _masterIndex = [];
  List<Map<String, dynamic>> _gradPapers = [];
  List<Map<String, dynamic>> _ugPapers = [];
  int _totalFilteredCount = 0;

  bool _isGradOpen = true;
  bool _isUgOpen = true;

  int _ribbonIndex = 0;
  final List<String> _ribbonFilters = ["Hindi Papers", "English Papers"];
  final Set<String> _advStages = {};
  final Set<String> _advYears = {};

  String? _lastOpenedId;
  final int _batchSize = 20;
  int _currentMax = 0;

  // 🟢 STATE VARIABLES
  bool _isLoading = true;
  bool _hasError = false;

  final ValueNotifier<bool> _showFiltersNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _initializeData();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _showFiltersNotifier.dispose();
    super.dispose();
  }

  // 🟢 RESPONSIVE FONT HELPER
  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) {
      return baseSize - 2; // Shrink text for very small phones
    }
    return baseSize; // Normal size for everyone else
  }

  Future<void> _initializeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isHindi = prefs.getBool('isHindi') ?? false;
      if (mounted) setState(() => _ribbonIndex = isHindi ? 0 : 1);
    } catch (e) { /* Ignore */ }

    _loadLastOpened();

    if (_ramCache != null && _ramCache!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _masterIndex = _ramCache!;
          _isLoading = false;
          _hasError = false;
        });
        _applyFilters();
      }
      _silentUpdateCheck();
    } else {
      _loadCachedData();
    }
  }

  void _handleScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      _loadMorePagination();
    }
  }

  // 🟢 PREFS
  Future<void> _loadLastOpened() async {
    try {
      final box = await Hive.openBox(_prefsBox);
      final lastId = box.get('last_opened_paper_id');
      if (mounted && lastId != null) setState(() => _lastOpenedId = lastId);
    } catch (_) {}
  }

  Future<void> _saveLastOpened(String id) async {
    try {
      final box = await Hive.openBox(_prefsBox);
      await box.put('last_opened_paper_id', id);
      if (mounted) setState(() => _lastOpenedId = id);
    } catch (_) {}
  }

  // 🟢 LOAD CACHE
  Future<void> _loadCachedData() async {
    try {
      final LazyBox box = await Hive.openLazyBox(_boxName);
      final String? cachedJson = await box.get('index_data');

      if (cachedJson != null && cachedJson.isNotEmpty) {
        final data = await compute(_parseAndCleanInBackground, cachedJson);
        _ramCache = data;

        if (mounted) {
          setState(() {
            _masterIndex = data;
            _isLoading = false;
            _hasError = false;
          });
          _applyFilters();
        }
        _checkForUpdate(box);
      } else {
        await _fetchFromNetwork();
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _hasError = true; });
    }
  }

  // 🟢 UPDATE CHECK
  Future<void> _silentUpdateCheck() async {
    try {
      final box = await Hive.openLazyBox(_boxName);
      await _checkForUpdate(box);
    } catch (_) {}
  }

  Future<void> _checkForUpdate(LazyBox box) async {
    final int? lastTs = await box.get('last_ts');
    if (lastTs == null) { await _fetchFromNetwork(); return; }
    if (DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastTs)).inHours >= _cacheDurationHours) {
      await _fetchFromNetwork();
    }
  }

  // 🟢 NETWORK FETCH
  Future<void> _fetchFromNetwork({bool isRefresh = false}) async {
    if (!isRefresh && mounted) setState(() => _isLoading = true);
    if (mounted) setState(() => _hasError = false);

    try {
      final url = Uri.parse("$_baseUrl$_indexFileName");
      final response = await http.get(
        url,
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final String rawJson = utf8.decode(response.bodyBytes);
        final data = await compute(_parseAndCleanInBackground, rawJson);
        _ramCache = data;

        if (mounted) {
          setState(() {
            _masterIndex = data;
            _hasError = false;
          });
          _applyFilters();
        }

        final LazyBox box = await Hive.openLazyBox(_boxName);
        await box.putAll({
          'index_data': rawJson,
          'last_ts': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> filtered = List<Map<String, dynamic>>.from(_masterIndex);

    if (_ribbonIndex == 0) {
      filtered.removeWhere((item) => item['langBadge'] != "HINDI");
    } else {
      filtered.removeWhere((item) => item['langBadge'] == "HINDI");
    }

    if (_advStages.isNotEmpty) filtered.removeWhere((item) => !_advStages.contains(item['stageBadge']));
    if (_advYears.isNotEmpty) filtered.removeWhere((item) => !_advYears.contains(item['yearBadge']));

    filtered.sort((a, b) => (b['ts'] ?? 0).compareTo(a['ts'] ?? 0));

    final gradList = filtered.where((item) => item['levelBadge'] == "GRADUATE").toList();
    final ugList = filtered.where((item) => item['levelBadge'] == "UNDER GRADUATE").toList();

    setState(() {
      _gradPapers = gradList;
      _ugPapers = ugList;
      _totalFilteredCount = filtered.length;
      _currentMax = (_batchSize > _totalFilteredCount) ? _totalFilteredCount : _batchSize;
    });
  }

  void _loadMorePagination() {
    if (_currentMax < _totalFilteredCount) {
      setState(() {
        _currentMax = (_currentMax + _batchSize).clamp(0, _totalFilteredCount);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI COMPONENTS
  // ---------------------------------------------------------------------------

  Widget _buildInteractiveSectionHeader({
    required String title,
    required IconData icon,
    required Color color,
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    return SliverToBoxAdapter(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700, color: _textDark, letterSpacing: 0.5,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isOpen ? 0 : -0.25,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  child: Icon(Icons.expand_more_rounded, color: Colors.grey[400], size: 24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar() {
    return AppBar(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NTPC Archive', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: _textDark)),
          Text('Solved Previous Papers', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: _textLight)),
        ],
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: _showFiltersNotifier,
          builder: (context, hasFilters, child) {
            return Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: hasFilters ? _primary : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
              ),
              child: IconButton(
                onPressed: _showFilterSheet,
                icon: Icon(Icons.tune_rounded, color: hasFilters ? Colors.white : _textDark, size: 22),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPremiumToggle() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                alignment: _ribbonIndex == 0 ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: width * 0.5,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_primary, Color(0xFF3B82F6)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
              Row(
                children: List.generate(2, (index) {
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _ribbonIndex = index);
                        _applyFilters();
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: _ribbonIndex == index ? Colors.white : _textLight,
                          ),
                          child: Text(_ribbonFilters[index]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildWithYearHeader(Map<String, dynamic> item, Map<String, dynamic>? previousItem) {
    bool showHeader = false;
    String year = item['yearBadge'];

    if (previousItem == null) {
      if (year.isNotEmpty) showHeader = true;
    } else {
      if (year != previousItem['yearBadge'] && year.isNotEmpty) showHeader = true;
    }

    if (!showHeader) return _buildPremiumCard(item);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, (previousItem == null) ? 4.0 : 24.0, 20, 8),
          child: Row(
            children: [
              Text("Year $year", style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[500], letterSpacing: 1.0)),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: Colors.grey[200])),
            ],
          ),
        ),
        _buildPremiumCard(item),
      ],
    );
  }

  Widget _buildPremiumCard(Map<String, dynamic> item) {
    final isLastOpened = item['id'] == _lastOpenedId;
    final isUG = item['levelBadge'] == "UNDER GRADUATE";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF64748B).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
        border: isLastOpened ? Border.all(color: _primary, width: 2) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPaper(item),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 48, width: 48,
                      decoration: BoxDecoration(
                        color: isLastOpened ? _primary.withOpacity(0.1) : (isUG ? const Color(0xFFCCFBF1) : const Color(0xFFEFF6FF)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isLastOpened ? Icons.history_edu_rounded : (isUG ? Icons.school_outlined : Icons.description_outlined),
                        color: isLastOpened ? _primary : (isUG ? _tealBadge : _primary),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item['displayTitle'] ?? 'NTPC Paper',
                        style: GoogleFonts.poppins(
                            fontSize: _getResponsiveFontSize(context, 16),
                            fontWeight: FontWeight.w600,
                            color: _textDark,
                            height: 1.3
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (item['yearBadge'].isNotEmpty) ...[
                      _ColorfulBadge(text: item['yearBadge'], bg: _orangeBg, textCol: _orangeBadge),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          Icon(Icons.list_alt_rounded, size: 14, color: _textLight),
                          const SizedBox(width: 4),
                          Text("${item['questions']} Qs", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _textLight)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (isLastOpened)
                      Text("Resume", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _primary))
                    else
                      Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.grey[300]),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPaper(Map<String, dynamic> item) {
    final safeId = item['id']?.toString() ?? '';
    if (safeId.isNotEmpty) {
      _saveLastOpened(safeId);
      Navigator.push(context, MaterialPageRoute(builder: (c) => QuizScreen(paperId: safeId, examName: item['rawTitle'] ?? 'Solved Paper')));
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filter Papers', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: _textDark)),
                    GestureDetector(
                      onTap: () => setModalState(() { _advStages.clear(); _advYears.clear(); }),
                      child: Text('Reset', style: GoogleFonts.poppins(fontSize: 14, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                    )
                  ],
                ),
                const SizedBox(height: 20),
                _buildFilterGroup('Exam Stage', ['CBT 1', 'CBT 2'], _advStages, setModalState),
                const SizedBox(height: 24),
                _buildFilterGroup('Year', ['2025', '2022', '2021', '2020', '2016'], _advYears, setModalState),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      _applyFilters();
                      _showFiltersNotifier.value = _advStages.isNotEmpty || _advYears.isNotEmpty;
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      elevation: 4,
                      shadowColor: _primary.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text("Apply Filters", style: GoogleFonts.poppins(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterGroup(String title, List<String> opts, Set<String> selection, StateSetter setState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: _textLight)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12, runSpacing: 12,
          children: opts.map((opt) {
            final isSelected = selection.contains(opt);
            return GestureDetector(
              onTap: () => setState(() => isSelected ? selection.remove(opt) : selection.add(opt)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _primary : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSelected ? _primary : Colors.grey.shade300),
                  boxShadow: isSelected ? [BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))] : [],
                ),
                child: Text(opt, style: GoogleFonts.poppins(color: isSelected ? Colors.white : _textDark, fontWeight: FontWeight.w500, fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int itemsToShow = _currentMax;
    final int gradCount = _gradPapers.length;
    final int ugCount = _ugPapers.length;

    List<Map<String, dynamic>> visibleGrad = [];
    List<Map<String, dynamic>> visibleUG = [];

    if (itemsToShow > 0) {
      if (itemsToShow <= gradCount) {
        visibleGrad = _gradPapers.sublist(0, itemsToShow);
      } else {
        visibleGrad = List.from(_gradPapers);
        int remaining = itemsToShow - gradCount;
        if (remaining > ugCount) remaining = ugCount;
        visibleUG = _ugPapers.sublist(0, remaining);
      }
    }

    final bool isEmpty = _totalFilteredCount == 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildPremiumAppBar(),

      // 🟢 OPTIMIZED: Dynamic Bottom Ad Bar
      bottomNavigationBar: Container(
        color: _bg, // Seamless integration with background
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min, // ⚡ Collapses to 0 height if ad is missing
            children: const [
              AdBanner(size: AdSize.banner),
            ],
          ),
        ),
      ),

      body: RefreshIndicator(
        color: _primary,
        backgroundColor: Colors.white,
        onRefresh: () async => await _fetchFromNetwork(isRefresh: true),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            _buildPremiumToggle(),

            if (_isLoading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: _primary)))
            else if (_hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: _textLight),
                      const SizedBox(height: 16),
                      Text("Connection Error", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: _textDark)),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => _fetchFromNetwork(isRefresh: true), child: const Text("Tap to Retry"))
                    ],
                  ),
                ),
              )
            else if (isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text("No Results Found", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: _textLight)),
                      ],
                    ),
                  ),
                )
              else ...[
                  if (visibleGrad.isNotEmpty)
                    _buildInteractiveSectionHeader(
                      title: "Graduate Level",
                      icon: Icons.workspace_premium_rounded,
                      color: _primary,
                      isOpen: _isGradOpen,
                      onTap: () => setState(() => _isGradOpen = !_isGradOpen),
                    ),

                  if (_isGradOpen)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final item = visibleGrad[index];
                          final prevItem = index > 0 ? visibleGrad[index - 1] : null;
                          return _buildWithYearHeader(item, prevItem);
                        },
                        childCount: visibleGrad.length,
                      ),
                    ),

                  // 🟢 OPTIMIZED: Gapless Middle Ad
                  if (_isGradOpen && visibleGrad.length > 2)
                    const SliverToBoxAdapter(
                      child: AdBanner(
                        size: AdSize.mediumRectangle,
                        margin: EdgeInsets.symmetric(vertical: 20), // ⚡ Margin applied only if ad loads
                      ),
                    ),


                  if (visibleUG.isNotEmpty)
                    _buildInteractiveSectionHeader(
                      title: "Under Graduate Level",
                      icon: Icons.school_outlined,
                      color: _tealBadge,
                      isOpen: _isUgOpen,
                      onTap: () => setState(() => _isUgOpen = !_isUgOpen),
                    ),

                  if (_isUgOpen)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final item = visibleUG[index];
                          final prevItem = index > 0 ? visibleUG[index - 1] : null;
                          return _buildWithYearHeader(item, prevItem);
                        },
                        childCount: visibleUG.length,
                      ),
                    ),

                  if ((_isGradOpen || _isUgOpen) && _currentMax < _totalFilteredCount)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _primary)),
                      ),
                    ),

                  // 🟢 SAFETY PADDING: Ensures content isn't hidden behind the bottom ad
                  // Even if the ad loads, this extra space allows comfortable scrolling.
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
          ],
        ),
      ),
    );
  }
}

class _ColorfulBadge extends StatelessWidget {
  final String text;
  final Color bg;
  final Color textCol;

  const _ColorfulBadge({required this.text, required this.bg, required this.textCol});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: textCol)),
    );
  }
}