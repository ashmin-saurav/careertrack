import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // 🟢 REQUIRED IMPORT

// 🟢 EXTERNAL WIDGETS
import '../widgets/smart_text_renderer.dart';
import 'practice_canvas_screen.dart';
import 'quiz_screen.dart';

class SavedQuestionsScreen extends StatefulWidget {
  const SavedQuestionsScreen({super.key});

  @override
  State<SavedQuestionsScreen> createState() => _SavedQuestionsScreenState();
}

class _SavedQuestionsScreenState extends State<SavedQuestionsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const String _savedBoxName = "saved_questions";

  late Future<Box> _boxFuture;
  double _devicePixelRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _boxFuture = Hive.openBox(_savedBoxName);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate-100
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          "My Collections",
          style: GoogleFonts.poppins(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w500,
            fontSize: 24,
            letterSpacing: -0.5,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
          indicatorColor: const Color(0xFF2563EB),
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 4,
          indicatorPadding: const EdgeInsets.only(bottom: 6),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: "Mock Tests"),
            Tab(text: "PYQ Papers"),
          ],
        ),
      ),
      body: FutureBuilder<Box>(
        future: _boxFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB), strokeWidth: 2));
          }
          if (snapshot.hasError) {
            return Center(child: Text("Database Error", style: GoogleFonts.inter(color: Colors.red)));
          }

          final box = snapshot.data!;

          return ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, Box box, _) {
              final allItems = box.values.toList();

              final pyqList = allItems.where((i) => (i['category'] ?? 'PYQ') == 'PYQ').toList();
              final mockList = allItems.where((i) => i['category'] == 'MOCK').toList();

              return TabBarView(
                controller: _tabController,
                children: [
                  _ModernList(items: mockList, box: box, devicePixelRatio: _devicePixelRatio),
                  _ModernList(items: pyqList, box: box, devicePixelRatio: _devicePixelRatio),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ModernList extends StatelessWidget {
  final List<dynamic> items;
  final Box box;
  final double devicePixelRatio;

  const _ModernList({
    required this.items,
    required this.box,
    required this.devicePixelRatio,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
              child: Icon(Icons.bookmarks_outlined, size: 40, color: Colors.blue.shade200),
            ),
            const SizedBox(height: 16),
            Text("No questions saved yet", style: GoogleFonts.inter(color: Colors.blueGrey, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final data = items[items.length - 1 - index];
        return RepaintBoundary(
          child: _ModernSavedCard(
            data: data,
            box: box,
            devicePixelRatio: devicePixelRatio,
          ),
        );
      },
    );
  }
}

class _ModernSavedCard extends StatelessWidget {
  final Map<dynamic, dynamic> data;
  final Box box;
  final double devicePixelRatio;

  const _ModernSavedCard({
    required this.data,
    required this.box,
    required this.devicePixelRatio,
  });

  // 🟢 ChatGPT Logic
  Future<void> _launchChatGPT() async {
    final Map<String, dynamic> qData = Map<String, dynamic>.from(data['questionData'] ?? {});
    final String questionText = qData['q'] ?? "";
    final List<dynamic> options = qData['o'] ?? [];
    final int correctAns = qData['a'] ?? qData['ans'] ?? -1;

    // 1. Get User Name
    final userBox = await Hive.openBox('user_data');
    final String userName = userBox.get('name', defaultValue: 'me');

    // 2. Clean Question
    final String cleanQuestion = questionText.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '').trim();

    // 3. Format Options
    String optionsText = "";
    for (int i = 0; i < options.length; i++) {
      optionsText += "${String.fromCharCode(65 + i)}) ${options[i]}\n";
    }

    // 4. Format Answer
    String answerText = (correctAns >= 0 && correctAns < options.length)
        ? "Correct Answer: Option ${String.fromCharCode(65 + correctAns)}"
        : "Correct Answer: Unknown";

    // 5. Construct Prompt
    String fullPrompt =
        "Explain this multiple choice question step by step for $userName.\n\n"
        "Question: $cleanQuestion\n\n"
        "Options:\n$optionsText\n"
        "$answerText\n\n"
        "Please provide a clear and concise explanation.";

    final Uri url = Uri.parse("https://chatgpt.com/?q=${Uri.encodeComponent(fullPrompt)}");

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint("Could not launch ChatGPT");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> qData = Map<String, dynamic>.from(data['questionData'] ?? {});
    final String questionText = qData['q'] ?? "Question Text Missing";
    final List<dynamic> options = qData['o'] ?? [];
    final int correctAns = qData['a'] ?? qData['ans'] ?? -1;
    final String location = data['examName'] ?? "Unknown Source";
    final String uniqueKey = data['id'];

    final String paperId = data['paperId'] ?? "";
    final String category = data['category'] ?? "PYQ";
    final int qIndex = data['index'] ?? 0;

    void _handleNavigation() {
      if (category == 'MOCK') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mock tests cannot be reopened.")));
        return;
      }
      if (paperId.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => QuizScreen(
              paperId: paperId,
              examName: location,
              initialIndex: qIndex,
            )
        ));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF64748B).withOpacity(0.06), blurRadius: 15, offset: const Offset(0, 8)),
          BoxShadow(color: const Color(0xFF64748B).withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // 1. HEADER
          InkWell(
            onTap: _handleNavigation,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "Q.${qIndex + 1}",
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1D4ED8)
                      ),
                    ),
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155),
                            letterSpacing: 0.3, height: 1.4,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. CONTENT
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SmartTextRenderer(
                  text: questionText,
                  textColor: Colors.black,
                  devicePixelRatio: devicePixelRatio,
                ),
                const SizedBox(height: 16),

                ...List.generate(options.length, (index) {
                  final isCorrect = index == correctAns;
                  if (!isCorrect) return const SizedBox.shrink();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF34D399).withOpacity(0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${String.fromCharCode(65 + index)}.",
                          style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF059669)
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SmartTextRenderer(
                            text: options[index].toString(),
                            textColor: const Color(0xFF047857),
                            devicePixelRatio: devicePixelRatio,
                          ),
                        ),
                        const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981))
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          // 3. FOOTER
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SingleChildScrollView( // Added for safety on small screens
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 🟢 ASK AI BUTTON
                  _PillButton(
                    assetPath: 'assets/chatgpt.webp', // Pass asset path
                    label: "Ask AI",
                    color: const Color(0xFF7E22CE), // Purple
                    bgColor: const Color(0xFFF3E8FF),
                    onTap: _launchChatGPT,
                  ),
                  const SizedBox(width: 10),

                  // SCRIBBLE BUTTON
                  _PillButton(
                    icon: Icons.draw_rounded,
                    label: "Scribble",
                    color: const Color(0xFF6366F1),
                    bgColor: const Color(0xFFEEF2FF),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PracticeCanvasScreen(
                          paperId: paperId,
                          questionIndex: qIndex,
                          questionText: questionText,
                          devicePixelRatio: devicePixelRatio,
                        ),
                      ));
                    },
                  ),
                  const SizedBox(width: 10),

                  // DELETE BUTTON
                  _PillButton(
                    icon: Icons.delete_rounded,
                    label: "Delete",
                    color: const Color(0xFFEF4444),
                    bgColor: const Color(0xFFFEF2F2),
                    onTap: () {
                      showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Colors.white,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text("Delete Question?"),
                            content: const Text("This action cannot be undone."),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text("Cancel", style: TextStyle(color: Colors.grey[600])),
                              ),
                              TextButton(
                                onPressed: () {
                                  box.delete(uniqueKey);
                                  Navigator.pop(ctx);
                                },
                                child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              )
                            ],
                          )
                      );
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData? icon;
  final String? assetPath; // 🟢 Added Asset Path
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _PillButton({
    this.icon,
    this.assetPath,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🟢 Render Icon OR Asset
              if (assetPath != null)
                Image.asset(assetPath!, width: 16, height: 16)
              else if (icon != null)
                Icon(icon, size: 16, color: color),

              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}