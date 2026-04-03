import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ Import this

// 🎨 Theme Colors (Consistent with Profile)
const Color _bgColor = Color(0xFFF8FAFC);
const Color _accentColor = Color(0xFF6366F1);
const Color _darkText = Color(0xFF1E293B);
const Color _mutedText = Color(0xFF64748B);

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> with SingleTickerProviderStateMixin {
  bool _isHindi = false; // Will be updated in initState
  late AnimationController _controller;

  // 📝 FAQ DATA
  final List<Map<String, dynamic>> _faqs = [
    {
      'icon': Icons.monetization_on_outlined,
      'q_en': 'Are Premium Tests paid?',
      'a_en': 'No! You don\'t need to pay money. You can unlock any Premium Test instantly by simply watching a short video ad.',
      'q_hi': 'क्या प्रीमियम टेस्ट के लिए पैसे देने होंगे?',
      'a_hi': 'नहीं! आपको पैसे देने की जरूरत नहीं है। आप बस एक छोटा विज्ञापन (Ad) देखकर किसी भी प्रीमियम टेस्ट को मुफ्त में अनलॉक कर सकते हैं।'
    },
    {
      'icon': Icons.lock_open_rounded,
      'q_en': 'How long does a test stay unlocked?',
      'a_en': 'Once unlocked via an ad, the test remains open for the entire duration of your session. You can attempt it freely.',
      'q_hi': 'टेस्ट कब तक अनलॉक रहता है?',
      'a_hi': 'एक बार विज्ञापन देखकर अनलॉक करने पर, टेस्ट आपके पूरे सत्र (session) के लिए खुला रहता है। आप इसे आसानी से दे सकते हैं।'
    },
    {
      'icon': Icons.remove_circle_outline_rounded,
      'q_en': 'Is there negative marking?',
      'a_en': 'Yes. As per the official NTPC pattern, 1/3rd marks will be deducted for every wrong answer to simulate real exams.',
      'q_hi': 'क्या परीक्षा में नेगेटिव मार्किंग है?',
      'a_hi': 'हाँ। आधिकारिक NTPC पैटर्न के अनुसार, असली परीक्षा का अनुभव देने के लिए प्रत्येक गलत उत्तर के लिए 1/3 अंक काटे जाएंगे।'
    },
    {
      'icon': Icons.wifi_off_rounded,
      'q_en': 'Can I attempt tests offline?',
      'a_en': 'Yes! Once a test is opened, questions are saved locally. You can finish and submit the test even if the internet goes off.',
      'q_hi': 'क्या मैं बिना इंटरनेट के टेस्ट दे सकता हूँ?',
      'a_hi': 'हाँ! एक बार टेस्ट खुलने के बाद प्रश्न सेव हो जाते हैं। अगर इंटरनेट चला भी जाए, तो भी आप टेस्ट पूरा करके जमा कर सकते हैं।'
    },
    {
      'icon': Icons.military_tech_rounded,
      'q_en': 'How do I increase my Rank?',
      'a_en': 'Ranks (Rookie → Titan) are based on your Daily Streak. Practice every day without a break to reach the top level!',
      'q_hi': 'मैं अपनी रैंक कैसे बढ़ा सकता हूँ?',
      'a_hi': 'रैंक (रकी से टाइटन) आपकी "डेली स्ट्रीक" पर निर्भर करती है। टॉप लेवल पर पहुँचने के लिए बिना रुके हर दिन अभ्यास करें!'
    },
  ];

  @override
  void initState() {
    super.initState();
    // 🟢 1. Check Saved Language
    _loadLanguage();

    // 🟢 2. Setup Animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _controller.forward();
  }

  // ✅ Helper to load saved preference
  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final bool savedLang = prefs.getBool('isHindi') ?? false;

    if (mounted) {
      setState(() {
        _isHindi = savedLang;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded, color: _darkText, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isHindi ? "सहायता केंद्र" : "Help Center",
          style: GoogleFonts.poppins(color: _darkText, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => setState(() => _isHindi = !_isHindi),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _isHindi ? Colors.orange.withOpacity(0.1) : _accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isHindi ? Colors.orange.withOpacity(0.3) : _accentColor.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _isHindi ? "हिंदी" : "English",
                  style: GoogleFonts.poppins(
                    color: _isHindi ? Colors.orange[800] : _accentColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        itemCount: _faqs.length,
        separatorBuilder: (ctx, i) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _faqs[index];

          // Staggered Animation Logic
          // Calculates a delay based on the index
          final double startInterval = (index / _faqs.length) * 0.5;
          final double endInterval = startInterval + 0.5;

          final Animation<double> animation = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(
                  startInterval.clamp(0.0, 1.0),
                  endInterval.clamp(0.0, 1.0),
                  curve: Curves.easeOut
              ),
            ),
          );

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
              child: _buildFAQCard(item),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFAQCard(Map<String, dynamic> item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withOpacity(0.06),
            offset: const Offset(0, 4),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          // 🟢 Modern Leading Icon
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item['icon'], color: _accentColor, size: 22),
          ),
          title: Text(
            _isHindi ? item['q_hi']! : item['q_en']!,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: _darkText,
              fontSize: 14,
            ),
          ),
          iconColor: _accentColor,
          collapsedIconColor: Colors.grey.shade400,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isHindi ? item['a_hi']! : item['a_en']!,
                style: GoogleFonts.inter(
                  color: _mutedText,
                  fontSize: 13,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}