import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// 🟢 IMPORTS FOR SUB-SCREENS
import 'faq_screen.dart';
import 'privacy_policy_screen.dart';
import 'dev.dart';

// 🎨 AESTHETIC THEME COLORS
const Color _bgColor = Color(0xFFF1F5F9);
const Color _accentColor = Color(0xFF6366F1);
const Color _darkText = Color(0xFF1E293B);
const Color _mutedText = Color(0xFF64748B);
const List<Color> _headerGradient = [Color(0xFF4F46E5), Color(0xFF8B5CF6)];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  bool _isHindi = false;

  // Real Data Variables
  String _name = "Aspirant";

  // Streak Data
  int _streak = 1;
  String _userRank = "Rookie";

  // Controller (Only Name needed now)
  final TextEditingController _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDataForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDataForUpdates();
    }
  }

  // 🟢 SMART DATA SYNC
  Future<void> _checkDataForUpdates() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Get Language
    bool savedLang = prefs.getBool('isHindi') ?? false;

    // 2. Fetch User Data
    if (!Hive.isBoxOpen('user_data')) await Hive.openBox('user_data');
    final userBox = Hive.box('user_data');

    final newName = userBox.get('name', defaultValue: 'Aspirant');

    // 3. Sync Streak
    int newStreak = prefs.getInt('current_streak') ?? 0;
    if (newStreak == 0) newStreak = 1;

    // 4. Calculate Rank
    String newRank = "Rookie";
    if (newStreak >= 3) newRank = "Enthusiast";
    if (newStreak >= 7) newRank = "Warrior";
    if (newStreak >= 14) newRank = "Elite";
    if (newStreak >= 30) newRank = "Titan";

    if (mounted) {
      setState(() {
        _isHindi = savedLang;
        _name = newName;
        _streak = newStreak;
        _userRank = newRank;

        _nameCtrl.text = newName;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final box = Hive.box('user_data');
    await box.put('name', _nameCtrl.text.trim());

    await _checkDataForUpdates();
    if (mounted) Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            _isHindi ? "प्रोफाइल अपडेट हो गई!" : "Profile Updated!",
            style: GoogleFonts.poppins()
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildAestheticHeader(),
            const SizedBox(height: 50),
            _buildSettingsList(),
            const SizedBox(height: 40),
            _buildFooterVersion(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 🟢 1. HEADER (SIMPLIFIED)
  Widget _buildAestheticHeader() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          height: 240, // Reduced height slightly since less content
          width: double.infinity,
          padding: const EdgeInsets.only(top: 50, left: 24, right: 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: _headerGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white,
                      child: Text(
                        _name.isNotEmpty ? _name[0].toUpperCase() : "A",
                        style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: _accentColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isHindi ? "नमस्ते," : "Hello,",
                          style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                        ),
                        Text(
                          _name,
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _showEditSheet,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 20),
                  )
                ],
              ),
            ],
          ),
        ),

        // STREAK CARD
        Positioned(
          bottom: -30,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 50, width: 50,
                  decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$_streak ${_isHindi ? 'दिन की स्ट्रीक' : 'Day Streak'}",
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText),
                      ),
                      Text(
                        _isHindi ? "ऐसे ही जोश बनाए रखें!" : "Keep the fire burning!",
                        style: GoogleFonts.inter(fontSize: 12, color: _mutedText),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    _userRank,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🟢 2. SETTINGS LIST
  Widget _buildSettingsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("ACCOUNT"),
          // Removed Notifications if you don't have push notifications implemented yet
          // Kept basic settings
          _buildMenuTile(
            title: _isHindi ? "मदद चाहिए?" : "Help Center",
            subtitle: _isHindi ? "सवाल पूछें या हमसे बात करें" : "FAQs & contact support",
            icon: Icons.headset_mic_outlined,
            color: Colors.blueAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FAQScreen())),
          ),

          _buildMenuTile(
            title: _isHindi ? "एप्प को रेट करें" : "Rate Application",
            subtitle: _isHindi ? "एप्प पसंद है? तो स्टार दें!" : "Love the app? Rate us!",
            icon: Icons.star_rate_rounded,
            color: Colors.amber,
            onTap: () async {
              final url = Uri.parse('https://play.google.com/store/apps/details?id=com.ashirwaddigital.rrbprep'); // Replace ID
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
          ),

          _buildMenuTile(
            title: _isHindi ? "सीधा डेवलपर से बात करें" : "Direct to Developer",
            subtitle: _isHindi ? "कोई शिकायत या सुझाव? सीधा बतायें" : "Complaints/Issues/Suggestions",
            icon: Icons.code_rounded,
            color: Colors.purple,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DevScreen())),
          ),

          _buildMenuTile(
            title: _isHindi ? "प्राइवेसी पॉलिसी" : "Privacy Policy",
            subtitle: _isHindi ? "आपका डेटा सेफ है या नहीं?" : "Data usage & protection",
            icon: Icons.lock_outline_rounded,
            color: Colors.teal,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _mutedText, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildMenuTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 2))]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: _darkText)),
                      Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: _mutedText)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🟢 3. EDIT BOTTOM SHEET (NAME ONLY)
  void _showEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 24, left: 24, right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Text(
                _isHindi ? "नाम बदलें" : "Edit Name",
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: _darkText)
            ),
            const SizedBox(height: 24),
            // Only ONE Text Field Now
            _buildTextField(_isHindi ? "पूरा नाम" : "Full Name", Icons.person_outline_rounded, _nameCtrl),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                    _isHindi ? "सेव करें" : "Save Changes",
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, IconData icon, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: _darkText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: _mutedText),
        prefixIcon: Icon(icon, color: _mutedText, size: 20),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _accentColor)),
      ),
    );
  }

  Widget _buildFooterVersion() {
    return Column(
      children: [
        Text(
          "NTPC & GROUP D PREP APP",
          style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
        ),
        Text(
          "Version 1.0.1",
          style: GoogleFonts.inter(fontSize: 12, color: _mutedText),
        ),
      ],
    );
  }
}