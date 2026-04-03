import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

// 🟢 YOUR CUSTOM WIDGETS (Ensure these exist)
import '../widgets/ad_banner.dart';
import '../widgets/smart_text_renderer.dart';
import 'practice_canvas_screen.dart';

class QuizScreen extends StatefulWidget {
  final String paperId;
  final String examName;
  final int initialIndex;

  const QuizScreen({
    super.key,
    required this.paperId,
    required this.examName,
    this.initialIndex = 0,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late DateTime _adsAllowedTime;

  // --- STATE ---
  List<dynamic> _questions = [];
  bool _isLoading = true;
  String _errorMessage = '';
  double _devicePixelRatio = 1.0;

  ScrollController? _scrollController;
  double _initialScrollOffset = 0.0;

  static const String _cdnBaseUrl = "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/py";
  static const String _boxName = "paper_cache";       // ⚠️ HEAVY DATA -> USE LAZY BOX
  static const String _progressBox = "quiz_progress"; // ✅ LIGHT DATA -> USE NORMAL BOX
  static const String _metadataBox = "cache_metadata";// ✅ LIGHT DATA -> USE NORMAL BOX
  static const int _maxCachedPapers = 20;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  void initState() {
    super.initState();
    // Allow ads to show after 1 minute to avoid accidental clicks
    _adsAllowedTime = DateTime.now().add(const Duration(minutes: 1));
    _initializeAndLoad();
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoad() async {
    final progressBox = await Hive.openBox(_progressBox);

    if (widget.initialIndex > 0) {
      _initialScrollOffset = widget.initialIndex * 400.0;
    } else {
      _initialScrollOffset = progressBox.get(widget.paperId, defaultValue: 0.0);
    }

    _scrollController = ScrollController(initialScrollOffset: _initialScrollOffset);
    await _loadPaperStrategy();
  }

  Future<void> _saveProgress() async {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    final double currentOffset = _scrollController!.offset;
    final box = await Hive.openBox(_progressBox);
    await box.put(widget.paperId, currentOffset);
  }

  // ------------------------------------------------------------------------
  // 🟢 LAZY CACHE MANAGEMENT (Safe for Low-End Devices)
  // ------------------------------------------------------------------------
  Future<void> _manageCacheLimit() async {
    try {
      final LazyBox cacheBox = await Hive.openLazyBox(_boxName);
      final metaBox = await Hive.openBox(_metadataBox);

      final int currentCount = cacheBox.length;

      if (currentCount > _maxCachedPapers) {
        Map<String, int> paperTimestamps = {};

        for (var key in cacheBox.keys) {
          final timestamp = metaBox.get(key, defaultValue: 0);
          paperTimestamps[key] = timestamp;
        }

        var sortedPapers = paperTimestamps.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        int papersToDelete = currentCount - _maxCachedPapers;
        for (int i = 0; i < papersToDelete && i < sortedPapers.length; i++) {
          final paperIdToDelete = sortedPapers[i].key;

          await cacheBox.delete(paperIdToDelete);
          await metaBox.delete(paperIdToDelete);

          final progressBox = await Hive.openBox(_progressBox);
          await progressBox.delete(paperIdToDelete);
        }
      }
      await metaBox.put(widget.paperId, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("⚠️ Cache management error: $e");
    }
  }

  Future<void> _loadPaperStrategy({bool forceRefresh = false}) async {
    try {
      final LazyBox box = await Hive.openLazyBox(_boxName);
      List<dynamic>? parsedData;

      if (!forceRefresh) {
        final String? cachedString = await box.get(widget.paperId);

        if (cachedString != null) {
          parsedData = await compute(_parseJsonIsolate, cachedString);
          final metaBox = await Hive.openBox(_metadataBox);
          await metaBox.put(widget.paperId, DateTime.now().millisecondsSinceEpoch);
        }
      }

      if (parsedData == null) {
        final String cleanId = widget.paperId.replaceAll('(', '%28').replaceAll(')', '%29');
        final response = await http.get(
            Uri.parse("$_cdnBaseUrl/$cleanId.json")
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final String utf8Body = utf8.decode(response.bodyBytes);
          parsedData = await compute(_parseJsonIsolate, utf8Body);

          await box.put(widget.paperId, utf8Body);

          final metaBox = await Hive.openBox(_metadataBox);
          await metaBox.put(widget.paperId, DateTime.now().millisecondsSinceEpoch);

          await _manageCacheLimit();
        } else {
          throw Exception("HTTP ${response.statusCode}");
        }
      }

      if (mounted) {
        setState(() {
          _questions = parsedData!;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_questions.isEmpty) _errorMessage = "Unable to load paper.";
        });
      }
    }
  }

  static List<dynamic> _parseJsonIsolate(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded['q'] ?? decoded['questions'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ------------------------------------------------------------------------
  // 🎨 UI BUILD
  // ------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.notoSansTextTheme(Theme.of(context).textTheme);

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: textTheme,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: GoogleFonts.notoSans(
              color: const Color(0xFF0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w600
          ),
          iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        ),
      ),
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
        // 🟢 BOTTOM BANNER AD (Pinned/Sticky)
        // 🟢 BOTTOM BANNER (Professional Look)
        bottomNavigationBar: Container(
          color: Colors.white, // Background extends behind system nav bar
          child: SafeArea(
            top: false,
            child: Container(
              height: 60,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: const Center(
                child: AdBanner(size: AdSize.banner),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFFE2E8F0), height: 1),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.examName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!_isLoading)
            Text(
              "${_questions.length} Questions • View Only",
              style: GoogleFonts.notoSans(
                  fontSize: 12,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w500
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage.isNotEmpty) return _buildErrorView();
    if (_isLoading && _questions.isEmpty) {
      return const _QuizShimmerList();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) _saveProgress();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => await _loadPaperStrategy(forceRefresh: true),
        color: const Color(0xFF2563EB),
        backgroundColor: Colors.white,
        child: ListView.separated(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          cacheExtent: 200,
          itemCount: _questions.length,

          // 🟢 INLINE ADS (Every 20th item)
          separatorBuilder: (context, index) {
            if ((index + 1) % 20 == 0 && index != _questions.length - 1) {
              return Column(
                children: [
                  const SizedBox(height: 24),
                  RepaintBoundary(
                    child: AdBanner(
                      size: AdSize.mediumRectangle,
                      showAfter: _adsAllowedTime,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }
            return const SizedBox(height: 24);
          },
          itemBuilder: (context, index) {
            return QuestionCard(
              key: ValueKey(index),
              paperId: widget.paperId,
              examName: widget.examName,
              index: index,
              questionData: _questions[index],
              devicePixelRatio: _devicePixelRatio,
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_errorMessage, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => _loadPaperStrategy(forceRefresh: true),
              child: const Text("Retry")
          )
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------
// 🧩 QUESTION CARD
// ------------------------------------------------------------------------
class QuestionCard extends StatelessWidget {
  final String paperId;
  final String examName;
  final int index;
  final Map<String, dynamic> questionData;
  final double devicePixelRatio;

  const QuestionCard({
    super.key,
    required this.paperId,
    required this.examName,
    required this.index,
    required this.questionData,
    required this.devicePixelRatio,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- TOOLBAR ---
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Q.${index + 1}",
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _SaveButton(
                          paperId: paperId,
                          examName: examName,
                          index: index,
                          questionData: questionData
                      ),
                      const SizedBox(width: 4),
                      _ScribbleButton(
                          paperId: paperId,
                          index: index,
                          text: questionData['q']?.toString() ?? "",
                          ratio: devicePixelRatio
                      ),
                      const SizedBox(width: 4),
                      _ChatGPTButton(
                          question: questionData['q']?.toString() ?? "",
                          options: questionData['o'] is List ? questionData['o'] : [],
                          answerIndex: questionData['a'] ?? -1
                      ),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

            // --- QUESTION TEXT ---
            Padding(
              padding: const EdgeInsets.all(20),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64),
                  child: SmartTextRenderer(
                    text: questionData['q']?.toString() ?? "",
                    textColor: const Color(0xFF0F172A),
                    devicePixelRatio: devicePixelRatio,
                  ),
                ),
              ),
            ),

            // --- OPTIONS ---
            if (questionData['o'] is List && (questionData['o'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: List.generate(
                      (questionData['o'] as List).length,
                          (i) => _MinimalOptionTile(
                        index: i,
                        text: questionData['o'][i].toString(),
                        isCorrect: i == (questionData['a'] ?? -1),
                        devicePixelRatio: devicePixelRatio,
                      )
                  ),
                ),
              ),

            // --- EXPLANATION ---
            if (questionData['exp'] != null &&
                questionData['exp'].toString() != "null" &&
                questionData['exp'].toString().isNotEmpty)
              _CleanExplanation(
                  text: questionData['exp'].toString(),
                  devicePixelRatio: devicePixelRatio
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------
// 📝 OPTION TILE
// ------------------------------------------------------------------------
class _MinimalOptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool isCorrect;
  final double devicePixelRatio;

  const _MinimalOptionTile({
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.devicePixelRatio
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCorrect ? const Color(0xFFF0FDF4) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isCorrect ? const Color(0xFF22C55E) : const Color(0xFFE2E8F0)
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              String.fromCharCode(65 + index),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isCorrect ? const Color(0xFF15803D) : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 120),
                  child: SmartTextRenderer(
                    text: text,
                    textColor: const Color(0xFF334155),
                    devicePixelRatio: devicePixelRatio,
                  ),
                ),
              ),
            ),
            if (isCorrect)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 18),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------
// 🔘 ACTION BUTTONS
// ------------------------------------------------------------------------

class _ActionButtonFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color bgColor;

  const _ActionButtonFrame({
    required this.child,
    required this.onTap,
    required this.bgColor
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ChatGPTButton extends StatelessWidget {
  final String question;
  final List<dynamic> options;
  final int answerIndex;

  const _ChatGPTButton({
    required this.question,
    required this.options,
    required this.answerIndex
  });

  Future<void> _launchGPT() async {
    final box = await Hive.openBox('user_data');
    final name = box.get('name', defaultValue: 'Aspirant');

    final cleanQ = question.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '').trim();

    String formattedOptions = "";
    if (options.isNotEmpty) {
      for (int i = 0; i < options.length; i++) {
        formattedOptions += "\n${String.fromCharCode(65 + i)}) ${options[i]}";
      }
    }

    final fullPrompt = "Explain to $name:\nQuestion: $cleanQ\n\nOptions:$formattedOptions";
    final url = Uri.parse("https://chatgpt.com/?q=${Uri.encodeComponent(fullPrompt)}");

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Err");
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ActionButtonFrame(
      onTap: _launchGPT,
      bgColor: const Color(0xFFF3E8FF),
      child: Image.asset('assets/chatgpt.webp', width: 20, height: 20),
    );
  }
}

class _ScribbleButton extends StatelessWidget {
  final String paperId;
  final int index;
  final String text;
  final double ratio;

  const _ScribbleButton({
    required this.paperId,
    required this.index,
    required this.text,
    required this.ratio
  });

  @override
  Widget build(BuildContext context) {
    return _ActionButtonFrame(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PracticeCanvasScreen(
                paperId: paperId,
                questionIndex: index,
                questionText: text,
                devicePixelRatio: ratio
            ),
          )
      ),
      bgColor: const Color(0xFFE0F2FE),
      child: const Icon(Icons.draw_rounded, color: Color(0xFF0284C7), size: 20),
    );
  }
}

class _SaveButton extends StatefulWidget {
  final String paperId;
  final String examName;
  final int index;
  final Map<String, dynamic> questionData;

  const _SaveButton({
    required this.paperId,
    required this.examName,
    required this.index,
    required this.questionData
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _isSaved = false;
  late String _key;

  @override
  void initState() {
    super.initState();
    _key = "${widget.paperId}_${widget.index}";
    _check();
  }

  Future<void> _check() async {
    final box = await Hive.openBox("saved_questions");
    if (mounted) setState(() => _isSaved = box.containsKey(_key));
  }

  Future<void> _toggle() async {
    final box = await Hive.openBox("saved_questions");
    if (_isSaved) {
      await box.delete(_key);
    } else {
      await box.put(_key, {
        "id": _key,
        "paperId": widget.paperId,
        "examName": widget.examName,
        "index": widget.index,
        "questionData": widget.questionData,
        "savedAt": DateTime.now().toIso8601String(),
      });
    }
    if (mounted) setState(() => _isSaved = !_isSaved);
  }

  @override
  Widget build(BuildContext context) {
    return _ActionButtonFrame(
      onTap: _toggle,
      bgColor: _isSaved ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
      child: Icon(
        _isSaved ? Icons.bookmark : Icons.bookmark_border,
        color: _isSaved ? const Color(0xFF16A34A) : const Color(0xFF64748B),
        size: 20,
      ),
    );
  }
}

class _CleanExplanation extends StatefulWidget {
  final String text;
  final double devicePixelRatio;

  const _CleanExplanation({
    required this.text,
    required this.devicePixelRatio
  });

  @override
  State<_CleanExplanation> createState() => _CleanExplanationState();
}

class _CleanExplanationState extends State<_CleanExplanation> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
        color: Color(0xFFFAFAFA),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_rounded, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(
                    "Explanation",
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.amber[800]
                    ),
                  ),
                  const Spacer(),
                  Icon(
                      _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey[400],
                      size: 20
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SmartTextRenderer(
                text: widget.text,
                textColor: const Color(0xFF475569),
                devicePixelRatio: widget.devicePixelRatio,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuizShimmerList extends StatelessWidget {
  const _QuizShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 4,
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade200,
            highlightColor: Colors.white,
            period: const Duration(milliseconds: 1500),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12)
              ),
            ),
          ),
        );
      },
    );
  }
}