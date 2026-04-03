import 'dart:async'; // Added for TimeoutException
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'live_room_screen.dart';

class CloudScreen extends StatefulWidget {
  const CloudScreen({super.key});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  int _viewState = 0;
  List<dynamic> _availableTests = [];
  bool _isLoadingTests = true;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // 🟢 ADMOB
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  final String _adUnitId = 'ca-app-pub-3116634693177302/2037004651'; // Test ID

  final String _rawBaseUrl = "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/mt/index";

  @override
  void initState() {
    super.initState();
    _preloadUserName();
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    _isAdLoading = true;
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (mounted) setState(() { _rewardedAd = ad; _isAdLoading = false; });
        },
        onAdFailedToLoad: (err) {
          if (mounted) setState(() { _isAdLoading = false; });
        },
      ),
    );
  }

  Future<void> _preloadUserName() async {
    final box = await Hive.openBox('user_data');
    final String savedName = box.get('name', defaultValue: '');
    if (mounted && savedName.isNotEmpty) {
      setState(() => _nameController.text = savedName);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  // 🟢 OPTIMIZED LOADER
// 🟢 OPTIMIZED LOADER (LazyBox Compatible)
  Future<void> _loadCachedTests() async {
    setState(() => _isLoadingTests = true);

    // 🟢 FIX 1: Open as LazyBox
    final LazyBox box = await Hive.openLazyBox('test_data_cache');
    final metaBox = await Hive.openBox('app_metadata');

    if (!box.containsKey('index_0')) {
      try {
        final response = await http.get(Uri.parse("${_rawBaseUrl}0.json"));
        if (response.statusCode == 200) {
          await box.put('index_0', response.body);
          await metaBox.put('max_index', 0);
        }
      } catch (_) {}
    }

    await _performGlobalUpdateCheck(box, metaBox);

    final int maxIndex = metaBox.get('max_index', defaultValue: 0);
    List<dynamic> allTests = [];

    for (int i = 0; i <= maxIndex; i++) {
      // 🟢 FIX 2: Add 'await' because LazyBox reads from disk
      final String? jsonStr = await box.get('index_$i');

      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr);
          List<dynamic> batch = [];
          if (decoded is List) batch = decoded;
          else if (decoded is Map && decoded.containsKey('tests')) batch = decoded['tests'];

          allTests.addAll(batch.where((t) => t['s'] != false));
        } catch (_) {}
      }
    }

    allTests.sort((a, b) {
      final int dateA = int.tryParse(a['dr']?.toString() ?? "0") ?? 0;
      final int dateB = int.tryParse(b['dr']?.toString() ?? "0") ?? 0;
      return dateB.compareTo(dateA);
    });

    if (mounted) {
      setState(() {
        _availableTests = allTests;
        _isLoadingTests = false;
      });
    }
  }

  // 🟢 FIX 3: Change parameter type to LazyBox
  Future<void> _performGlobalUpdateCheck(LazyBox box, Box metaBox) async {
    final int lastCheck = metaBox.get('last_check_ts', defaultValue: 0);
    final DateTime now = DateTime.now();

    if (now.difference(DateTime.fromMillisecondsSinceEpoch(lastCheck)).inHours < 24) return;

    int currentMax = metaBox.get('max_index', defaultValue: 0);
    int safetyCounter = 0;

    while (safetyCounter < 10) {
      int nextIndex = currentMax + 1;
      try {
        final response = await http.get(Uri.parse("${_rawBaseUrl}$nextIndex.json"));
        if (response.statusCode == 200) {
          // .put is async for both Box and LazyBox, so this line is fine
          await box.put('index_$nextIndex', response.body);
          currentMax = nextIndex;
          await metaBox.put('max_index', currentMax);
        } else {
          break;
        }
      } catch (_) {
        break;
      }
      safetyCounter++;
    }
    await metaBox.put('last_check_ts', now.millisecondsSinceEpoch);
  }

  bool _isPremium(Map test) {
    int type = 0;
    try {
      dynamic rawT = test['t'];
      if (rawT is int) type = rawT;
      else if (rawT is String && (rawT == 'm' || rawT == 'mt')) type = 10;
    } catch (_) {}
    return (type == 1 || type == 11);
  }

  void _onHostClicked(Map test) {
    if (_isPremium(test)) {
      _showUnlockDialog(test);
    } else {
      _generateRoomAndHost(test);
    }
  }

  void _showUnlockDialog(Map test) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 28),
          const SizedBox(width: 8),
          Text("Premium Test", style: GoogleFonts.poppins(fontWeight: FontWeight.bold))
        ]),
        content: Text(
          "Watch a short ad to host this premium room for free.",
          style: GoogleFonts.inter(color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showAdAndHost(test);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF384F2C)),
            icon: const Icon(Icons.play_circle_fill, color: Colors.white, size: 18),
            label: const Text("Watch Ad", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showAdAndHost(Map test) {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _loadRewardedAd();
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            _loadRewardedAd();
            _generateRoomAndHost(test);
          }
      );
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) => _generateRoomAndHost(test));
      _rewardedAd = null;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ad loading... please wait.")));
      _loadRewardedAd();
    }
  }

  Future<void> _generateRoomAndHost(Map testData) async {
    final String roomCode = (Random().nextInt(900000) + 100000).toString();
    String hostName = _nameController.text;
    if (hostName.isEmpty) {
      final userBox = await Hive.openBox('user_data');
      hostName = userBox.get('name', defaultValue: 'Host');
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomScreen(
      isHost: true,
      roomCode: roomCode,
      examData: testData,
      userName: hostName,
    )));
  }

  void _joinRoom() async {
    if (_codeController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Code"), backgroundColor: Colors.red));
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter Name"), backgroundColor: Colors.red));
      return;
    }
    await Hive.openBox('user_data').then((box) => box.put('name', _nameController.text.trim()));
    if (!mounted) return;

    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomScreen(
        isHost: false,
        roomCode: _codeController.text,
        examData: null,
        userName: _nameController.text.trim()
    )));

    if (result == 'room_full') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⛔ Room Full!"), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleScan() async {
    final String? scannedCode = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SimpleScannerPage()));
    if (scannedCode != null && mounted) {
      setState(() => _codeController.text = scannedCode);
      if (_nameController.text.trim().isNotEmpty) _joinRoom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () {
            if (_viewState == 0) Navigator.pop(context);
            else setState(() => _viewState = 0);
          },
        ),
        title: Text(
          _viewState == 0 ? "Group Study" : (_viewState == 1 ? "Select Exam" : "Join Room"),
          style: GoogleFonts.poppins(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildCurrentView(),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_viewState) {
      case 1: return _buildHostExamList();
      case 2: return _buildJoinForm();
      default: return _buildSelectionMenu();
    }
  }

  Widget _buildSelectionMenu() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildBigOptionCard("Host a Quiz", "Invite friends to compete live.", Icons.podcasts_rounded, const Color(0xFF6366F1), () {
            _loadCachedTests();
            setState(() => _viewState = 1);
          }),
          const SizedBox(height: 20),
          _buildBigOptionCard("Join a Room", "Enter code or scan QR.", Icons.sensors_rounded, const Color(0xFF10B981), () => setState(() => _viewState = 2)),
        ],
      ),
    );
  }

  Widget _buildBigOptionCard(String title, String desc, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 32)),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))), const SizedBox(height: 4), Text(desc, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), height: 1.4))])),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  // 🟢 OPTIMIZED LIST (0 LAG + VISUAL DISTINCTION)
  Widget _buildHostExamList() {
    if (_isLoadingTests) return const Center(child: CircularProgressIndicator());
    if (_availableTests.isEmpty) return Center(child: Text("No live tests available.", style: GoogleFonts.inter(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _availableTests.length,
      // 🟢 Cache items off-screen for smoothness
      cacheExtent: 1000,
      itemBuilder: (context, index) {
        final test = _availableTests[index];
        // 🟢 RepaintBoundary stops the whole list from lagging
        return RepaintBoundary(
          child: _CloudTestCard(
            test: test,
            onHost: () => _onHostClicked(test),
            isPremium: _isPremium(test),
          ),
        );
      },
    );
  }

  Widget _buildJoinForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Text("Enter Room Code", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Ask host for 6-digit code", style: GoogleFonts.inter(color: Colors.grey)),
          const SizedBox(height: 32),
          TextField(controller: _codeController, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: GoogleFonts.notoSans(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold), decoration: InputDecoration(counterText: "", hintText: "000000", filled: true, fillColor: Colors.white, suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF10B981)), onPressed: _handleScan), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
          const SizedBox(height: 20),
          TextField(controller: _nameController, textAlign: TextAlign.center, decoration: InputDecoration(hintText: "Enter Your Name", filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _joinRoom, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text("Join Room", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)))),
        ],
      ),
    );
  }
}

// 🟢 NEW: SEPARATE WIDGET FOR CARD (PERFORMANCE + STYLING)
class _CloudTestCard extends StatelessWidget {
  final Map test;
  final VoidCallback onHost;
  final bool isPremium;

  const _CloudTestCard({
    required this.test,
    required this.onHost,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    int type = 0;
    try {
      dynamic rawT = test['t'];
      if (rawT is int) type = rawT;
      else if (rawT is String && (rawT == 'm' || rawT == 'mt')) type = 10;
    } catch (_) {}

    final bool isFullMock = (type == 10 || type == 11);
    final int duration = test['d'] ?? test['duration'] ?? ((test['q'] ?? 30) * 1);

    // 🎨 DISTINCT STYLING
    Color bgCol = Colors.white;
    Color borderCol = Colors.grey.shade200;

    if (isPremium) {
      bgCol = const Color(0xFF384F2C); // Premium Green
      borderCol = Colors.amber.withOpacity(0.5);
    } else if (isFullMock) {
      bgCol = const Color(0xFFEFF6FF); // Light Blue for Mocks
      borderCol = const Color(0xFFBFDBFE);
    }

    final Color titleCol = isPremium ? Colors.white : Colors.black87;
    final Color subCol = isPremium ? Colors.white70 : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isFullMock ? 0.05 : 0.02),
            blurRadius: isFullMock ? 8 : 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onHost,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isFullMock && !isPremium)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text("FULL MOCK", style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),

                      Text(
                        test['ti'] ?? "Unknown Test",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: titleCol,
                            height: 1.2
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (isPremium) ...[
                            const Icon(Icons.workspace_premium, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            "${test['q'] ?? 0} Qs • $duration Mins",
                            style: GoogleFonts.inter(fontSize: 12, color: subCol),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPremium ? Colors.amber[700] : (isFullMock ? const Color(0xFF2563EB) : const Color(0xFF6366F1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isPremium
                      ? const Icon(Icons.lock_open_rounded, color: Colors.black, size: 18)
                      : const Text("Select", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SimpleScannerPage extends StatefulWidget {
  const SimpleScannerPage({super.key});

  @override
  State<SimpleScannerPage> createState() => _SimpleScannerPageState();
}

class _SimpleScannerPageState extends State<SimpleScannerPage> {
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Scan Room QR"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.noDuplicates,
              returnImage: false,
            ),
            onDetect: (capture) {
              if (_isScanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _isScanned = true;
                  HapticFeedback.lightImpact();
                  Navigator.pop(context, barcode.rawValue);
                  break;
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF10B981), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const Positioned(
            bottom: 50, left: 0, right: 0,
            child: Text(
              "Point camera at the QR Code",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          )
        ],
      ),
    );
  }
}