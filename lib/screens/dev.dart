import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

// ─── Premium Design Tokens ───────────────────────────────────────────────────
const Color _bg         = Color(0xFFF5F6FA);
const Color _surface    = Color(0xFFFFFFFF);
const Color _accent     = Color(0xFF4F46E5);   // Indigo 600
const Color _accentSoft = Color(0xFFEEF2FF);   // Indigo 50
const Color _ink        = Color(0xFF0F172A);   // Slate 900
const Color _subInk     = Color(0xFF64748B);   // Slate 500
const Color _border     = Color(0xFFE8EBF0);
const Color _success    = Color(0xFF059669);
const Color _warning    = Color(0xFFF59E0B);
// ───────────────────────────────────────────────────────────────────────────────

class DevScreen extends StatefulWidget {
  const DevScreen({super.key});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> with SingleTickerProviderStateMixin {
  bool _isHindi       = false;
  bool _isSubmitting  = false;

  bool _isLoading     = false;
  bool _isBackgroundSyncing = false;
  bool _hasCheckedServerOnce = false; // 🟢 ADD THIS LINE

  final TextEditingController _msgController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _myMessages = [];

  // 🛡️ SPAM PROTECTION
  DateTime? _lastRefreshTime;

  // 🎬 ANIMATIONS
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _focusNode.addListener(() => setState(() {}));

    // 🟢 THE FIX: Wait for the slide transition to finish BEFORE loading heavy data
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        _initScreen();
      }
    });
  }

  @override
  void dispose() {
    _msgController.dispose();
    _focusNode.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── 0. The Magic "Zero-Lag" & "Zero-Waste" Init ───────────────────────────
  Future<void> _initScreen() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _isHindi = prefs.getBool('isHindi') ?? false);

    await _loadFromCacheFirst();

    bool hasPendingTickets = _myMessages.any((msg) =>
    msg['admin_reply'] == null || msg['admin_reply'].toString().trim().isEmpty
    );

    // 🟢 NOW WE CHECK THE NEW FLAG INSTEAD OF .isEmpty
    if (!_hasCheckedServerOnce) {
      debugPrint("📡 SMART FETCH: Truly the first time on this device. Checking Firebase...");
      _fetchFromFirebase(isManualRefresh: false);
    } else if (hasPendingTickets) {
      debugPrint("📡 SMART FETCH: User has pending tickets. Checking Firebase for replies...");
      _fetchFromFirebase(isManualRefresh: false);
    } else {
      debugPrint("🛑 SMART FETCH: 0 Tickets or All Resolved. 0 Database hits!");
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // ── 1. Load Instant Cache ─────────────────────────────────────────────────
  Future<void> _loadFromCacheFirst() async {
    try {
      if (!Hive.isBoxOpen('support_cache')) await Hive.openBox('support_cache');
      final cacheBox = Hive.box('support_cache');

      // 🟢 CHECK IF WE HAVE EVER SYNCED WITH THE SERVER BEFORE
      _hasCheckedServerOnce = cacheBox.containsKey('messages');

      final cachedData = cacheBox.get('messages', defaultValue: []);

      if (cachedData.isNotEmpty) {
        if (mounted) {
          setState(() {
            _myMessages = List<Map<String, dynamic>>.from(
                cachedData.map((e) => Map<String, dynamic>.from(e))
            );
          });
          _fadeCtrl.forward();
        }
      } else {
        // 🟢 IF EMPTY BUT WE ALREADY CHECKED BEFORE, JUST SHOW EMPTY UI
        if (_hasCheckedServerOnce) {
          _fadeCtrl.forward();
        } else {
          if (mounted) setState(() => _isLoading = true);
        }
      }
    } catch (e) {
      debugPrint("Cache Error: $e");
    }
  }

  // ── 2. Fetch Latest from Firebase ─────────────────────────────────────────
  Future<void> _fetchFromFirebase({required bool isManualRefresh}) async {
    if (isManualRefresh && _lastRefreshTime != null) {
      final diff = DateTime.now().difference(_lastRefreshTime!);
      if (diff.inSeconds < 30) {
        _showSnack(
          _isHindi ? "भाई, थोड़ा रुक कर रिफ्रेश करें ⏳" : "Please wait a moment before refreshing.",
          icon: Icons.hourglass_top_rounded,
          color: _warning,
        );
        return;
      }
    }

    if (mounted) setState(() => _isBackgroundSyncing = true);
    if (isManualRefresh) _lastRefreshTime = DateTime.now();

    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      final uid = user!.uid;

      final snapshot = await FirebaseFirestore.instance
          .collection('support_messages')
          .where('uid', isEqualTo: uid)
          .orderBy('timestamp', descending: true)
          .get(const GetOptions(source: Source.serverAndCache));

      final messages = snapshot.docs.map((doc) {
        final d = doc.data();
        return {
          'id':          doc.id,
          'message':     d['message']     ?? '',
          'admin_reply': d['admin_reply'],
          'name':        d['name']        ?? 'Aspirant',
          'timestamp_str': d['timestamp'] != null
              ? (d['timestamp'] as Timestamp).toDate().toIso8601String()
              : DateTime.now().toIso8601String(),
        };
      }).toList();

      if (!Hive.isBoxOpen('support_cache')) await Hive.openBox('support_cache');
      await Hive.box('support_cache').put('messages', messages);

      if (mounted) {
        setState(() {
          _myMessages = messages;
          _isLoading = false;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted && isManualRefresh) {
        _showSnack(_isHindi ? "इंटरनेट कनेक्शन जांचें।" : "Failed to refresh. Check connection.", icon: Icons.wifi_off_rounded, color: Colors.redAccent);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isBackgroundSyncing = false;
        });
      }
    }
  }

  // ── 3. Send Message ───────────────────────────────────────────────────────
  Future<void> _submitMessage() async {
    final message = _msgController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSubmitting = true);
    FocusScope.of(context).unfocus();

    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      final uid = user!.uid;

      if (!Hive.isBoxOpen('user_data')) await Hive.openBox('user_data');
      final String userName = Hive.box('user_data').get('name', defaultValue: "Aspirant");

      await FirebaseFirestore.instance.collection('support_messages').add({
        'uid':         uid,
        'name':        userName,
        'message':     message,
        'admin_reply': null,
        'timestamp':   FieldValue.serverTimestamp(),
      });

      _msgController.clear();

      await _fetchFromFirebase(isManualRefresh: false);

      if (mounted) {
        _showSnack(
          _isHindi ? "मैसेज भेज दिया गया! 🚀" : "Message Sent Successfully! 🚀",
          icon: Icons.check_circle_outline_rounded,
          color: _success,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          _isHindi ? "कुछ गड़बड़ हो गई। फिर से ट्राई करें।" : "Something went wrong. Please try again.",
          icon: Icons.error_outline_rounded,
          color: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {required IconData icon, required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return _isHindi ? "अभी-अभी" : "Just Now";
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('MMM dd  •  hh:mm a').format(date);
    } catch (e) {
      return "";
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 🟢 Unfocus keyboard when tapping anywhere outside the input box
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        // 🟢 Replaced rigid Column with fluid CustomScrollView to fix Overflow
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildInputCard()),
            SliverToBoxAdapter(child: _buildSectionHeader()),

            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: _accent, strokeWidth: 2.5),
                ),
              )
            else if (_myMessages.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                sliver: SliverFadeTransition(
                  opacity: _fadeAnim,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _buildMessageTile(_myMessages[i]),
                      childCount: _myMessages.length,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 18, color: _ink),
        onPressed: () => Navigator.pop(context),
        splashRadius: 20,
      ),
      title: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.support_agent_rounded, size: 18, color: _accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isHindi ? "डेवलपर से बात करें" : "Chat with Developer",
                  style: GoogleFonts.poppins(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _isHindi ? "हम 24 घंटे में पक्का रिप्लाई करेंगे ✌️" : "We usually reply within 24 hours ✌️",
                  style: GoogleFonts.dmSans(color: _subInk, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _isBackgroundSyncing
              ? const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          )
              : IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _accent, size: 22),
            onPressed: () => _fetchFromFirebase(isManualRefresh: true),
            tooltip: "Refresh",
            splashRadius: 20,
          ),
        ),
      ],
    );
  }

  // ── Input Card ──────────────────────────────────────────────────────────────
  Widget _buildInputCard() {
    final isFocused = _focusNode.hasFocus;
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 16, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isHindi ? "हमें मैसेज करें" : "Message the Developer",
                  style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: _ink, letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              _isHindi
                  ? "नया टेस्ट चाहिए? कोई सुझाव है? या कोई बग मिला? हमें बेझिझक बताएं!"
                  : "Request a test, share feedback, or report a bug.",
              style: GoogleFonts.dmSans(fontSize: 12, color: _subInk),
            ),
          ),
          const SizedBox(height: 14),

          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isFocused ? _accent.withOpacity(0.55) : _border,
                width: isFocused ? 1.5 : 1.0,
              ),
              boxShadow: isFocused
                  ? [BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))]
                  : [],
            ),
            child: TextField(
              controller: _msgController,
              focusNode: _focusNode,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.5),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _isHindi
                    ? "अपने आइडिया या समस्या यहाँ लिखें..."
                    : "Drop your ideas, test requests, or issues here...",
                hintStyle: GoogleFonts.dmSans(fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _isSubmitting || _msgController.text.trim().isEmpty
                  ? null
                  : _submitMessage,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _border,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _isHindi ? "मैसेज भेजें" : "Send Message",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Header ──────────────────────────────────────────────────────────
  Widget _buildSectionHeader() {
    return Container(
      color: _bg,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Text(
            _isHindi ? "आपकी बातचीत" : "Your Conversations",
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w700, color: _ink,
            ),
          ),
          const SizedBox(width: 8),
          if (_myMessages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "${_myMessages.length}",
                style: GoogleFonts.dmSans(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 32, color: _accent),
          ),
          const SizedBox(height: 18),
          Text(
            _isHindi ? "अभी तक कोई बातचीत नहीं" : "No Messages Yet",
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: _ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _isHindi
                ? "ऐप को बेहतर बनाने का कोई आईडिया है? या कोई नया मॉक टेस्ट चाहिए?\nऊपर दिए गए फॉर्म से हमें बताएं!"
                : "Have a brilliant idea for the app? Want a specific mock test?\nOr found a bug? Drop us a message above!",
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 13, color: _subInk, height: 1.55),
          ),
        ],
      ),
    );
  }

  // ── Message Tile ────────────────────────────────────────────────────────────
  Widget _buildMessageTile(Map<String, dynamic> msg) {
    final hasReply = msg['admin_reply'] != null &&
        msg['admin_reply'].toString().trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top: Label + Date ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: _StatusChip(
                    label: _isHindi ? "आपका मैसेज" : "Your Message",
                    icon: Icons.person_outline_rounded,
                    bgColor: _bg,
                    textColor: _subInk,
                    borderColor: _border,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDate(msg['timestamp_str']),
                  style: GoogleFonts.dmSans(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          // ── User's Message Body ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(
              msg['message'],
              style: GoogleFonts.dmSans(fontSize: 14, color: _ink, height: 1.55),
            ),
          ),

          // ── Divider ──
          Container(height: 1, color: _border),

          // ── Reply Section ──
          if (hasReply)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.support_agent_rounded, size: 13, color: _success),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Developer Reply",
                          style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w700, color: _success,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Text(
                      msg['admin_reply'],
                      style: GoogleFonts.dmSans(
                        fontSize: 14, color: _ink, height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
          // ── Pending State ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 13),
              child: Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: _warning,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: _warning.withOpacity(0.45), blurRadius: 5),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isHindi
                          ? "डेवलपर के रिप्लाई का इंतज़ार है..."
                          : "Awaiting Developer Reply...",
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: _warning,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
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

// ─── Reusable Status Chip ─────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bgColor;
  final Color textColor;
  final Color borderColor;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.textColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w600, color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}