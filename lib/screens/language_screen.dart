import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_screen.dart'; // Ensure this file exists

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final PageController _pageController = PageController();

  // 🎨 Design Tokens
  static const Color primaryColor = Color(0xFF2563EB);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);

  bool _isHindi = false;
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onLanguageSelected(bool isHindi) {
    setState(() {
      _isHindi = isHindi;
      _currentPage = 1;
    });

    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _goBack() {
    if (_currentPage == 1) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      setState(() {
        _currentPage = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 Status Bar Control
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _Page1Language(onLanguageSelected: _onLanguageSelected),
              _Page2TrustList(
                isHindi: _isHindi,
                onBack: _goBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================
// 📄 PAGE 1: LANGUAGE SELECTION
// =========================================================
// =========================================================
// 📄 PAGE 1: LANGUAGE SELECTION (Updated)
// =========================================================
class _Page1Language extends StatelessWidget {
  final Function(bool) onLanguageSelected;

  const _Page1Language({required this.onLanguageSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // 🟢 PREMIUM WELCOME CARD
            Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. MAIN CARD BACKGROUND
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)], // Rich Blue
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 2. ICON WITH GLOW RINGS
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                          ),
                          Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                            ),
                            child: const Icon(Icons.school_rounded, size: 32, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // 3. TEXT CONTENT
                      const Text(
                        "Welcome to the Family\nपरिवार में स्वागत है",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.3,
                          letterSpacing: 0.5,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        "Your journey to success begins here.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 4. "TRUST" BADGE (Fixed for New App Launch)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Changed icon to 'Verified' to match the text
                            const Icon(Icons.verified_outlined, color: Color(0xFFFFD700), size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "Based on Latest Exam Pattern", // Honest & High Value
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                // 5. DECORATIVE CIRCLES
                Positioned(
                  top: -20, right: -20,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -30, left: -10,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // 🟢 HEADER
            Center(
              child: Text(
                "Choose your language / भाषा चुनें",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B).withOpacity(0.8),
                  letterSpacing: 0.5,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 🟢 ENGLISH OPTION
            _LanguageOption(
              title: "English",
              subtitle: "Continue in English",
              icon: "Aa",
              color: const Color(0xFF2563EB),
              onTap: () => onLanguageSelected(false),
            ),

            const SizedBox(height: 16),

            // 🟢 HINDI OPTION
            _LanguageOption(
              title: "हिंदी",
              subtitle: "हिंदी में तैयारी करें",
              icon: "अ",
              color: const Color(0xFFEA580C),
              onTap: () => onLanguageSelected(true),
            ),
          ],
        ),
      ),
    );
  }
}
// =========================================================
// 📄 PAGE 2: TRUST LIST & NAME INPUT
// =========================================================
class _Page2TrustList extends StatefulWidget {
  final bool isHindi;
  final VoidCallback onBack;

  const _Page2TrustList({
    required this.isHindi,
    required this.onBack,
  });

  @override
  State<_Page2TrustList> createState() => _Page2TrustListState();
}

class _Page2TrustListState extends State<_Page2TrustList> {
  final TextEditingController _nameController = TextEditingController();
  bool _animationsComplete = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _animationsComplete = true;
          });
        }
      });
    });
  }

  Future<void> _finishSetup() async {
    final String enteredName = _nameController.text.trim();

    if (enteredName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isHindi ? "कृपया अपना नाम लिखें" : "Please enter your name"),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isHindi', widget.isHindi);
    await prefs.setBool('isFirstTime', false);

    var box = await Hive.openBox('user_data');
    await box.put('name', enteredName);
    await box.put('target_exam', "RRB NTPC");

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.black54, size: 20),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            widget.isHindi ? "बस एक कदम और! 🚀" : "One Step Closer! 🚀",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _LanguageScreenState.textDark),
          ),

          const SizedBox(height: 20),

          // 1. SMART AI
          _AnimatedListItem(
            animate: _animationsComplete, delay: 0,
            icon: Icons.auto_awesome, color: const Color(0xFF8B5CF6), // Purple
            title: widget.isHindi ? "स्मार्ट एआई विश्लेषण" : "Smart AI Analysis",
            subtitle: widget.isHindi
                ? "आपकी कमजोरियों को अपने आप पहचानता है।"
                : "Finds your weak areas automatically.",
          ),

          const SizedBox(height: 10),

          // 2. EXPERT CONTENT
          _AnimatedListItem(
            animate: _animationsComplete, delay: 100,
            icon: Icons.verified, color: const Color(0xFF10B981), // Green
            title: widget.isHindi ? "विशेषज्ञ सत्यापित सामग्री" : "Expert Verified Content",
            subtitle: widget.isHindi
                ? "100% सटीक प्रश्न और समाधान।"
                : "100% accurate questions & solutions.",
          ),

          const SizedBox(height: 10),

          // 3. DAILY UPDATES
          _AnimatedListItem(
            animate: _animationsComplete, delay: 200,
            icon: Icons.update, color: const Color(0xFFF59E0B), // Orange
            title: widget.isHindi ? "रोज़ाना नए टेस्ट" : "Daily New Tests",
            subtitle: widget.isHindi
                ? "हर सुबह नई सामग्री जोड़ी जाती है।"
                : "Fresh content added every morning.",
          ),

          const SizedBox(height: 10),

          // 4. SOURCE / STANDARDS (The new one)
          // 4. SOURCE / STANDARDS (Expert + Public Source)
          _AnimatedListItem(
            animate: _animationsComplete, delay: 300,
            icon: Icons.history_edu_rounded, color: const Color(0xFFEC4899), // Pink

            title: widget.isHindi
                ? "वास्तविक परीक्षा स्तर"
                : "Real Exam Standards",

            subtitle: widget.isHindi
                ? "विशेषज्ञों द्वारा तैयार और सार्वजनिक रुझानों पर आधारित।"
                : "Crafted by experts using trusted public sources.",
          ),

          const SizedBox(height: 28),

          Text(
            widget.isHindi ? "आपका नाम?" : "What's your name?",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _LanguageScreenState.textDark),
          ),

          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(fontWeight: FontWeight.w600, color: _LanguageScreenState.textDark),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
                hintText: widget.isHindi ? "अपना नाम लिखें" : "Enter full name",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: Icon(Icons.person_outline, color: Colors.grey.shade400, size: 20),
              ),
            ),
          ),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _finishSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _LanguageScreenState.primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.isHindi ? "शुरू करें" : "Start Learning",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // 🟢 SUBTLE FOOTER DISCLAIMER
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text(
                    widget.isHindi ? "महत्वपूर्ण जानकारी" : "Important Note",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  widget.isHindi
                      ? "यह ऐप केवल परीक्षा तैयारी में सहायता के उद्देश्य से बनाया गया है। यह भारत सरकार या भारतीय रेलवे का आधिकारिक ऐप नहीं है। हमारा उद्देश्य छात्रों को प्रभावी तैयारी के लिए विश्वसनीय शैक्षणिक सामग्री और मॉक टेस्ट प्रदान करना है।"
                      : "This app is designed solely for exam preparation assistance. It is not an official app of the Government of India or Indian Railways. Our mission is to provide reliable educational content and mock tests to help students prepare effectively.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: Colors.grey.shade400, height: 1.4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// =========================================================
// 🧩 REUSABLE COMPONENTS
// =========================================================

class _LanguageOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final String icon;
  final Color color;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          overlayColor: MaterialStateProperty.all(color.withOpacity(0.05)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 50, height: 50, alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Text(icon, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), letterSpacing: -0.3)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: color.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedListItem extends StatelessWidget {
  final bool animate;
  final int delay;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _AnimatedListItem({
    required this.animate,
    required this.delay,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 300 + delay),
      opacity: animate ? 1.0 : 0.0,
      curve: Curves.easeOut,
      child: AnimatedPadding(
        duration: Duration(milliseconds: 300 + delay),
        padding: animate ? EdgeInsets.zero : const EdgeInsets.only(top: 10),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _LanguageScreenState.textDark)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: _LanguageScreenState.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}