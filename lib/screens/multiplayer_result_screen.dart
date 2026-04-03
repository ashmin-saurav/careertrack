import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:confetti/confetti.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/ad_banner.dart';

// ------------------------------------------------------------------
// 1. DATA MODELS & CONSTANTS
// ------------------------------------------------------------------

class ResultAvatarData {
  static const List<Map<String, dynamic>> list = [
    {'id': 0, 'emoji': '👻', 'color': Color(0xFF9CA3AF)},
    {'id': 1, 'emoji': '🤖', 'color': Color(0xFF3B82F6)},
    {'id': 2, 'emoji': '👽', 'color': Color(0xFF10B981)},
    {'id': 3, 'emoji': '🦁', 'color': Color(0xFFF59E0B)},
    {'id': 4, 'emoji': '🦄', 'color': Color(0xFFEC4899)},
    {'id': 5, 'emoji': '🦊', 'color': Color(0xFFF97316)},
    {'id': 6, 'emoji': '🐼', 'color': Color(0xFF1F2937)},
    {'id': 7, 'emoji': '🦖', 'color': Color(0xFF0D9488)},
  ];

  static Map<String, dynamic> get(int id) {
    try {
      return list.firstWhere((e) => e['id'] == id, orElse: () => list[0]);
    } catch (e) {
      return list[0];
    }
  }
}

class RankedPlayer {
  final String name;
  final int score;
  final int avatarId;
  final int rank;
  final bool isMe;

  RankedPlayer({
    required this.name,
    required this.score,
    required this.avatarId,
    required this.rank,
    required this.isMe,
  });
}

// ------------------------------------------------------------------
// 2. MAIN SCREEN
// ------------------------------------------------------------------

class MultiplayerResultScreen extends StatefulWidget {
  final List<dynamic> scores;
  final int totalQuestions;
  final String roomCode;
  final String userName;

  const MultiplayerResultScreen({
    super.key,
    required this.scores,
    required this.totalQuestions,
    required this.roomCode,
    required this.userName,
  });

  @override
  State<MultiplayerResultScreen> createState() =>
      _MultiplayerResultScreenState();
}

class _MultiplayerResultScreenState extends State<MultiplayerResultScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // UI Controllers
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late ConfettiController _confettiController;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();

  // Logic State
  MqttServerClient? _client;
  final List<Map<String, String>> _messages = [];
  int _selectedTab = 0;
  bool _hasUnreadMessages = false;
  late List<RankedPlayer> _rankedPlayers;

  // My Performance State
  int _myRank = 0;
  int _myScore = 0;
  bool _isTopThree = false;

  // Language State
  bool _isHindi = false;

  // Ad State
  final String _interstitialId = 'ca-app-pub-3116634693177302/8035427055';

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoaded = false;

  // Session Tracking
  final DateTime _enterTime = DateTime.now();
  final String _mySessionId =
      "u_${Random().nextInt(9999999)}_${DateTime.now().millisecondsSinceEpoch}";
  String get _updateTopic => "room/${widget.roomCode}/update";

  // Keyboard State
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLanguage();
    _processScoresWithProperRanking();

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 2500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _slideController.forward();
      _fadeController.forward();
      _triggerCelebrationIfEligible();
      _connectForChat();
      _loadInterstitialAd();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    if (mounted) {
      setState(() {
        _keyboardVisible = bottomInset > 0;
      });

      // Scroll to bottom when keyboard opens
      if (_keyboardVisible && _selectedTab == 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
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

  // ------------------------------------------------------------------
  // 3. PROPER RANKING LOGIC (Same score = Same rank)
  // ------------------------------------------------------------------

  void _processScoresWithProperRanking() {
    List<dynamic> sorted = List.from(widget.scores);
    sorted.sort((a, b) => (b['score'] ?? 0).compareTo(a['score'] ?? 0));

    _rankedPlayers = [];
    int currentRank = 1;
    int previousScore = -1;
    int skipCount = 0;

    for (int i = 0; i < sorted.length; i++) {
      final player = sorted[i];
      final score = player['score'] ?? 0;

      if (score != previousScore) {
        currentRank = i + 1;
      }

      final isMe = player['name'] == widget.userName;
      _rankedPlayers.add(RankedPlayer(
        name: player['name'],
        score: score,
        avatarId: player['avatar'] ?? 0,
        rank: currentRank,
        isMe: isMe,
      ));

      if (isMe) {
        _myRank = currentRank;
        _myScore = score;
      }

      previousScore = score;
    }

    _isTopThree = _myRank <= 3 && _myScore > 0;
  }

  void _triggerCelebrationIfEligible() {
    if (_isTopThree) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _confettiController.play();
          HapticFeedback.mediumImpact();
        }
      });
    }
  }

  String _getMotivationMessage() {
    if (_isHindi) {
      if (_myRank == 1) return "🏆 शानदार! आप विजेता हैं!";
      if (_myRank <= 3) return "🥈 बहुत बढ़िया! टॉप 3 में आए!";
      if (_myRank <= 5) return "🔥 अच्छा खेले! लगे रहो!";
      if (_myScore == 0) return "💪 कोई बात नहीं! अगली बार बेहतर करो!";
      return "📈 अच्छी कोशिश! प्रैक्टिस से सब आएगा!";
    } else {
      if (_myRank == 1) return "🏆 Outstanding! You're the Champion!";
      if (_myRank <= 3) return "🥈 Excellent! You made it to Top 3!";
      if (_myRank <= 5) return "🔥 Great Job! Keep it up!";
      if (_myScore == 0) return "💪 No worries! You'll do better next time!";
      return "📈 Good effort! Practice makes perfect!";
    }
  }

  // ------------------------------------------------------------------
  // 4. INTERSTITIAL AD LOGIC
  // ------------------------------------------------------------------

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoaded = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _exitScreen();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _exitScreen();
            },
          );
        },
        onAdFailedToLoad: (err) => _isInterstitialLoaded = false,
      ),
    );
  }

  void _handleExitClick() {
    final int secondsOnScreen =
        DateTime.now().difference(_enterTime).inSeconds;

    final int maxPossible = widget.totalQuestions * 10;
    final double percentage =
    maxPossible > 0 ? (_myScore / maxPossible) : 0.0;
    final bool isLowScore = percentage < 0.15;

    // Safety: Instant Exit (< 2s)
    if (secondsOnScreen < 2) {
      _exitScreen();
      return;
    }

    // Mercy: Low Score
    if (isLowScore) {
      _exitScreen();
      return;
    }

    // Show Ad
    if (_isInterstitialLoaded && _interstitialAd != null) {
      _interstitialAd!.show();
    } else {
      _exitScreen();
    }
  }

  void _exitScreen() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ------------------------------------------------------------------
  // 5. CHAT INFRASTRUCTURE
  // ------------------------------------------------------------------

  Future<void> _connectForChat() async {
    try {
      final clientId = "chat_${Random().nextInt(999999)}";
      _client = MqttServerClient('test.mosquitto.org', clientId);
      _client!.port = 1883;
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.onConnected = () {
        _client!.subscribe(_updateTopic, MqttQos.atLeastOnce);
      };
      _client!.connect();

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> c) {
        final recMess = c[0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message);
        try {
          final data = jsonDecode(pt);
          if (data['type'] == 'chat') _addMessage(data);
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _addMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    bool isMe = data['id'] == _mySessionId;
    setState(() {
      _messages.add({
        'sender': data['sender'],
        'msg': data['msg'],
        'isMe': '$isMe'
      });
      if (_selectedTab != 1 && !isMe) _hasUnreadMessages = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final t = _chatController.text.trim();
    if (t.isEmpty || _client == null) return;
    final p = jsonEncode({
      "type": "chat",
      "sender": widget.userName,
      "id": _mySessionId,
      "msg": t
    });
    final builder = MqttClientPayloadBuilder();
    builder.addString(p);
    _client!.publishMessage(
        _updateTopic, MqttQos.atLeastOnce, builder.payload!);
    _chatController.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client?.disconnect();
    _chatController.dispose();
    _chatFocusNode.dispose();
    _scrollController.dispose();
    _slideController.dispose();
    _fadeController.dispose();
    _confettiController.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 6. BUILD UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 1. FIX: FORCE STATUS BAR TEXT TO WHITE
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Android: White icons
      statusBarBrightness: Brightness.dark,      // iOS: White text
    ));

    final size = MediaQuery.of(context).size;
    final bool isLandscape = size.width > size.height;

    // 2. Get keyboard height manually
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = bottomInset > 0;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleExitClick();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),

        // CRITICAL FIX: Disable auto-resize to prevent AdView crash
        resizeToAvoidBottomInset: false,

        body: Stack(
          children: [
            // GRADIENT BACKGROUND
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F172A),
                      const Color(0xFF1E293B),
                      const Color(0xFF0F172A),
                    ],
                  ),
                ),
              ),
            ),

            // MAIN CONTENT
            Positioned.fill(
              child: Column(
                children: [
                  // Header & Content
                  if (isLandscape)
                    _buildLandscapeContent(isKeyboardOpen)
                  else
                    _buildPortraitContent(isKeyboardOpen),

                  // BOTTOM SECTION (Chat Input + Ad)
                  // We keep this rigid to prevent focus loss
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. The Chat Input Bar
                      // We wrap it in a container that moves up/down
                      _buildChatInputBar(),

                      // 2. The Keyboard Spacer
                      // When keyboard opens, this grows and pushes Input up
                      SizedBox(height: bottomInset),

                      // 3. The Ad & Exit Button
                      // We use Offstage to HIDE them without KILLING them.
                      Offstage(
                        offstage: isKeyboardOpen,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildExitButton(),
                            const AdBanner(),
                          ],
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),

            // CONFETTI LAYER
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirection: pi / 2,
                maxBlastForce: 8,
                minBlastForce: 3,
                emissionFrequency: 0.03,
                numberOfParticles: 12,
                gravity: 0.15,
                colors: const [
                  Color(0xFF10B981),
                  Color(0xFF3B82F6),
                  Color(0xFFF59E0B),
                  Color(0xFFEC4899),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to keep the build method clean
  Widget _buildPortraitContent(bool isKeyboardOpen) {
    return Expanded(
      child: Column(
        children: [
          SafeArea(child: _buildModernHeader()),
          _buildModernTabBar(),
          if (!isKeyboardOpen) _buildMotivationBanner(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _selectedTab == 0
                  ? _buildLeaderboardTab()
                  : _buildChatList(), // Renamed to separate list from input
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeContent(bool isKeyboardOpen) {
    return Expanded(
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _buildModernHeader(compact: true),
                  if (!isKeyboardOpen) _buildMotivationBanner(),
                  Expanded(child: _buildLeaderboardTab()),
                ],
              ),
            ),
            Container(width: 1, color: Colors.white.withOpacity(0.1)),
            Expanded(
              flex: 5,
              child: _buildChatList(),
            ),
          ],
        ),
      ),
    );
  }

  // Extracted Chat List (WITHOUT INPUT)
  Widget _buildChatList() {
    return _messages.isEmpty
        ? Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            _isHindi ? 'सबको हैलो बोलो! 👋' : 'Say hello! 👋',
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.3),
              fontSize: 16,
            ),
          ),
        ],
      ),
    )
        : ListView.builder(
      controller: _scrollController,
      // Add this line:
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          // Add extra padding at the bottom equal to keyboard height + input bar height
          bottom: MediaQuery.of(context).viewInsets.bottom + 80
      ),
      itemCount: _messages.length,
      itemBuilder: (c, i) {
        final m = _messages[i];
        final bool me = m['isMe'] == 'true';
        return _buildChatBubble(
          sender: m['sender']!,
          message: m['msg']!,
          isMe: me,
        );
      },
    );
  }

  // Extracted Input Bar
  Widget _buildChatInputBar() {
    // Only show input bar if Chat tab is selected
    if (_selectedTab != 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocusNode,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: _isHindi ? 'मैसेज लिखो...' : 'Type a message...',
                  hintStyle: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                onTap: () {
                  // Ensure we scroll to bottom when keyboard opens
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ------------------------------------------------------------------
  // 7. MODERN UI COMPONENTS
  // ------------------------------------------------------------------

  Widget _buildModernHeader({bool compact = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isHindi ? 'क्विज़ का रिजल्ट' : 'Quiz Results',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (!compact) const SizedBox(height: 4),
          if (!compact)
            Text(
              _isHindi
                  ? 'रूम: ${widget.roomCode}'
                  : 'Room: ${widget.roomCode}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModernTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _buildTabButton(
                index: 0,
                icon: Icons.leaderboard_rounded,
                label: _isHindi ? 'रैंकिंग' : 'Rankings',
              ),
            ),
            Expanded(
              child: _buildTabButton(
                index: 1,
                icon: Icons.chat_bubble_rounded,
                label: _isHindi ? 'चैट' : 'Chat',
                hasNotification: _hasUnreadMessages,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
    bool hasNotification = false,
  }) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
          if (index == 1) _hasUnreadMessages = false;
        });
        HapticFeedback.lightImpact();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color:
                isSelected ? Colors.white : Colors.white.withOpacity(0.5),
              ),
            ),
            if (hasNotification) ...[
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMotivationBanner() {
    return FadeTransition(
      opacity: _fadeController,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isTopThree
                ? [const Color(0xFF10B981), const Color(0xFF059669)]
                : [const Color(0xFF475569), const Color(0xFF334155)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (_isTopThree
                  ? const Color(0xFF10B981)
                  : const Color(0xFF475569))
                  .withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          _getMotivationMessage(),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_rankedPlayers.isEmpty) {
      return Center(
        child: Text(
          _isHindi ? 'कोई स्कोर नहीं' : 'No scores',
          style: GoogleFonts.inter(
            color: Colors.white.withOpacity(0.3),
            fontSize: 16,
          ),
        ),
      );
    }

    final topThree = _rankedPlayers.where((p) => p.rank <= 3).toList();
    final others = _rankedPlayers.where((p) => p.rank > 3).toList();

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOut,
      )),
      child: FadeTransition(
        opacity: _fadeController,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (topThree.isNotEmpty) ...[
              _buildPodium(topThree),
              const SizedBox(height: 24),
            ],
            if (others.isNotEmpty) ...[
              Text(
                _isHindi ? 'अन्य खिलाड़ी' : 'Other Players',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 12),
              ...others.asMap().entries.map((entry) {
                return _buildPlayerCard(entry.value, entry.key);
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPodium(List<RankedPlayer> topThree) {
    // Arrange podium: 2nd, 1st, 3rd
    RankedPlayer? first = topThree.firstWhere((p) => p.rank == 1,
        orElse: () => topThree[0]);
    RankedPlayer? second =
    topThree.firstWhere((p) => p.rank == 2, orElse: () => topThree[0]);
    RankedPlayer? third =
    topThree.firstWhere((p) => p.rank == 3, orElse: () => topThree[0]);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (topThree.length >= 2 && second.rank == 2)
          _buildPodiumPlace(second, 2, 110),
        if (topThree.isNotEmpty) _buildPodiumPlace(first, 1, 140),
        if (topThree.length >= 3 && third.rank == 3)
          _buildPodiumPlace(third, 3, 90),
      ],
    );
  }

  Widget _buildPodiumPlace(RankedPlayer player, int rank, double height) {
    final avatar = ResultAvatarData.get(player.avatarId);
    final colors = {
      1: [const Color(0xFFFCD34D), const Color(0xFFF59E0B)],
      2: [const Color(0xFFD1D5DB), const Color(0xFF9CA3AF)],
      3: [const Color(0xFFFBBF24), const Color(0xFFD97706)],
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors[rank]!,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors[rank]![0].withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 3,
              ),
            ),
            child: Text(
              avatar['emoji'],
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            player.name,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: player.isMe ? const Color(0xFF10B981) : Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            width: 70,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors[rank]![0].withOpacity(0.8),
                  colors[rank]![1].withOpacity(0.6),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '#$rank',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${player.score}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(RankedPlayer player, int index) {
    final avatar = ResultAvatarData.get(player.avatarId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: player.isMe
            ? const Color(0xFF10B981).withOpacity(0.15)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: player.isMe
              ? const Color(0xFF10B981).withOpacity(0.4)
              : Colors.white.withOpacity(0.05),
          width: player.isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (avatar['color'] as Color).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (avatar['color'] as Color).withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                avatar['emoji'],
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: player.isMe
                        ? const Color(0xFF10B981)
                        : Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${player.score} ${_isHindi ? 'अंक' : 'pts'}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '#${player.rank}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Messages area - expands to fill available space
        Expanded(
          child: _messages.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 64,
                  color: Colors.white.withOpacity(0.1),
                ),
                const SizedBox(height: 16),
                Text(
                  _isHindi ? 'सबको हैलो बोलो! 👋' : 'Say hello! 👋',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (c, i) {
              final m = _messages[i];
              final bool me = m['isMe'] == 'true';
              return _buildChatBubble(
                sender: m['sender']!,
                message: m['msg']!,
                isMe: me,
              );
            },
          ),
        ),
        // Chat input field - THIS WILL MOVE UP WITH KEYBOARD
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _chatController,
                    focusNode: _chatFocusNode,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: _isHindi ? 'मैसेज लिखो...' : 'Type a message...',
                      hintStyle: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    textInputAction: TextInputAction.send,
                    onTap: () {
                      // Scroll to bottom when input field is tapped
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble({
    required String sender,
    required String message,
    required bool isMe,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(
                  sender,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                )
                    : null,
                color: isMe ? null : const Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(isMe ? 0 : 0.1),
                  width: 1,
                ),
              ),
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExitButton() {
    return Container(
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: 10, // Reduced bottom padding since ad banner is separate
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _handleExitClick,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_rounded, size: 20),
              const SizedBox(width: 10),
              Text(
                _isHindi ? 'होम पर जाएँ' : 'Exit to Home',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}