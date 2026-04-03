import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🎨 Theme Colors
const Color _bgColor = Color(0xFFF1F5F9);
const Color _accentColor = Color(0xFF6366F1);
const Color _darkText = Color(0xFF1E293B);
const Color _mutedText = Color(0xFF64748B);
const Color _warningColor = Color(0xFFEF4444); // Red for warning

class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  bool _isHindi = false;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final bool savedLang = prefs.getBool('isHindi') ?? false;
    if (mounted) setState(() => _isHindi = savedLang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _darkText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isHindi ? "प्राइवेसी पॉलिसी" : "Privacy Policy",
          style: GoogleFonts.poppins(color: _darkText, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: InkWell(
                onTap: () => setState(() => _isHindi = !_isHindi),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    _isHindi ? "English" : "हिंदी",
                    style: GoogleFonts.poppins(color: _accentColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLastUpdated(),
            const SizedBox(height: 24),

            // SECTION 1: NO COLLECTION
            _buildSection(
              _isHindi ? "1. हम कोई डेटा नहीं लेते" : "1. Zero Data Collection",
              _isHindi
                  ? "हम आपका कोई भी डेटा (नाम, ईमेल, या प्रोग्रेस) अपने सर्वर पर सेव नहीं करते। आपका डेटा 100% आपके ही फोन में रहता है।"
                  : "We do not collect or store any of your personal data on our servers. Your name, progress, and scores stay 100% locally on your device.",
              icon: Icons.verified_user_outlined,
            ),

            // SECTION 2: DELETE WARNING (Important!)
            _buildSection(
              _isHindi ? "2. अगर ऐप डिलीट किया तो?" : "2. Data Loss Warning",
              _isHindi
                  ? "सावधान! क्योंकि सब कुछ आपके फोन में सेव है, अगर आपने ऐप डिलीट (Uninstall) किया तो आपकी सारी मेहनत और स्कोर उड़ जाएगा। हम उसे वापस नहीं ला पाएंगे।"
                  : "Warning! Since data is stored locally, if you uninstall the app or clear storage, your progress will be permanently lost. We cannot recover it.",
              icon: Icons.warning_amber_rounded,
              isWarning: true,
            ),

            // SECTION 3: INTERNET
            _buildSection(
              _isHindi ? "3. इंटरनेट क्यों चाहिए?" : "3. Internet Usage",
              _isHindi
                  ? "इंटरनेट सिर्फ नए सवाल लोड करने और विज्ञापन (Ads) दिखाने के लिए चाहिए। आपकी पर्सनल जानकारी कहीं नहीं भेजी जाती।"
                  : "Internet access is required only to load new questions and display ads. No personal information is transmitted externally.",
              icon: Icons.wifi_rounded,
            ),

            const SizedBox(height: 30),
            Center(
              child: Column(
                children: [
                  Text(
                    "Ashirwad Digital",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                        fontSize: 16
                    ),
                  ),
                  Text(
                    "Transparent & Safe",
                    style: GoogleFonts.inter(
                        color: _mutedText,
                        fontSize: 12
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Text(
            _isHindi ? "आखिरी अपडेट: 26 जनवरी 2026" : "Last Updated: Jan 26, 2026",
            style: GoogleFonts.inter(
                color: const Color(0xFF1E40AF),
                fontWeight: FontWeight.w600,
                fontSize: 13
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content, {required IconData icon, bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isWarning ? _warningColor.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isWarning ? _warningColor.withOpacity(0.3) : Colors.grey.shade200
              ),
            ),
            child: Icon(
                icon,
                color: isWarning ? _warningColor : _accentColor,
                size: 24
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isWarning ? _warningColor : _darkText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _mutedText,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}