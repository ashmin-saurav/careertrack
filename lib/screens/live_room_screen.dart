import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:share_plus/share_plus.dart';
import 'package:collection/collection.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../widgets/ad_banner.dart';
import 'multiplayer_quiz_screen.dart';

class AvatarData {
  static final List<Map<String, dynamic>> list = [
    {'id': 0, 'emoji': '👻', 'color': Color(0xFF9CA3AF)},
    {'id': 1, 'emoji': '🤖', 'color': Color(0xFF3B82F6)},
    {'id': 2, 'emoji': '👽', 'color': Color(0xFF10B981)},
    {'id': 3, 'emoji': '🦁', 'color': Color(0xFFF59E0B)},
    {'id': 4, 'emoji': '🦄', 'color': Color(0xFFEC4899)},
    {'id': 5, 'emoji': '🦊', 'color': Color(0xFFF97316)},
    {'id': 6, 'emoji': '🐼', 'color': Color(0xFF1F2937)},
    {'id': 7, 'emoji': '🦖', 'color': Color(0xFF0D9488)},
  ];

  static Map<String, dynamic> get(int id) =>
      list.firstWhere((e) => e['id'] == id, orElse: () => list[0]);
}

class LiveRoomScreen extends StatefulWidget {
  final bool isHost;
  final String roomCode;
  final String userName;
  final Map? examData;

  const LiveRoomScreen({
    super.key,
    required this.isHost,
    required this.roomCode,
    required this.userName,
    this.examData,
  });

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _r2BaseUrl =
      "https://pub-3d5caab4747a4f75b496f1d250515ff5.r2.dev/mt/";

  // MQTT Configuration
  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isExiting = false;
  bool _isRoomClosed = false;
  String _statusText = "Connecting...";
  int _missedHeartbeats = 0;

  // Connection management
  Timer? _joinRetryTimer;
  bool _isInLobbyList = false;
  int _connectionRetryCount = 0;
  static const int _maxConnectionRetries = 3;
  bool _isStartingGame = false;

  // Capacity system - PERSISTENT until used
  int _maxSlots = 3;
  int _currentSlotLevel = 0; // 0=3, 1=6, 2=8, 3=10
  // Add this near your other variables
  String? _roomTestId;

  // Ads
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  bool _isWatchingAd = false;
 final String _rewardedAdUnitId = 'ca-app-pub-3116634693177302/2037004651';

  // User identification
  late int _myAvatarId;
  final String _mySessionId =
      "u_${Random().nextInt(999999)}_${DateTime.now().millisecondsSinceEpoch}";

  // Timers
  Timer? _heartbeatTimer;
  Timer? _reaperTimer;
  Timer? _broadcastDebounceTimer;
  Timer? _adTimeoutTimer;
  Timer? _capacitySyncTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  Timer? _inactivityCheckTimer;

  // Player management
  final Map<String, Map<String, dynamic>> _playerMap = {};
  final Set<String> _pendingJoins = {};
  final Map<String, int> _lastJoinRequestTime = {};
  final Map<String, int> _playerLastHeartbeat = {};
  final Map<String, int> _playerLastActivity = {};

  // Download tracking
  final Map<String, DownloadStatus> _playerDownloadStatus = {};
  final Map<String, CancelableDownload> _activeDownloads = {};

  // Download progress for UI
  final Map<String, double> _playerDownloadProgress = {};

  // MQTT subscription
  StreamSubscription? _mqttSubscription;

  // Chat system
  final int _chatLimit = 50;
  final int _zombieTimeout = 30000;
  final int _inactiveTimeout = 120000;
  final List<Map<String, String>> _messages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;
  bool _hasUnreadMessages = false;

  // Quiz data
  List<dynamic>? _cachedQuestions;
  DownloadStatus _myDownloadStatus = DownloadStatus.notStarted;
  double _myDownloadProgress = 0.0;
  CancelableDownload? _myActiveDownload;
  bool _shouldCancelMyDownload = false;

  // Topics
  String get _hostTopic => "room/${widget.roomCode}/host";
  String get _updateTopic => "room/${widget.roomCode}/update";

  // Network tracking
  int _totalDisconnections = 0;
  int _lastStableConnectionTime = 0;
  bool _isNetworkStable = true;

  // Performance optimizations
  int _lastBroadcastTime = 0;
  int _lastUiUpdate = 0;
  final Map<String, dynamic> _lastLobbyState = {};

  // Responsive helpers
  double get _screenWidth => MediaQuery.of(context).size.width;
  double get _screenHeight => MediaQuery.of(context).size.height;
  double get _responsiveScale => min(_screenWidth, 400) / 400;
  double get _adaptiveFontSize => _screenWidth < 360 ? 0.85 : 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _myAvatarId = Random().nextInt(AvatarData.list.length);
    _tabController = TabController(length: 2, vsync: this);
    _lastStableConnectionTime = DateTime.now().millisecondsSinceEpoch;
    _roomTestId = widget.examData?['id'];

    _tabController.addListener(() {
      if (_tabController.index == 1 && mounted) {
        setState(() => _hasUnreadMessages = false);
      }
    });

    // Load persistent premium level
    _loadPersistentPremiumLevel();

    if (widget.isHost) {
      _statusText = "Creating Room...";
      _isInLobbyList = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      _playerMap[_mySessionId] = {
        'id': _mySessionId,
        'name': widget.userName,
        'avatar': _myAvatarId,
        'isHost': true,
        'lastSeen': now,
        'isInactive': false,
      };
      _playerLastActivity[_mySessionId] = now;

      // Host starts downloading immediately
      _myDownloadStatus = DownloadStatus.inProgress;
      _startQuizDownload();

      _loadRewardedAd();

      // Cleanup zombies every 10 seconds
      _reaperTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _pruneZombiePlayers());

      // Check for inactive players every 5 seconds
      _inactivityCheckTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _checkInactivePlayers());

      // Broadcast lobby state every 5 seconds
      _capacitySyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_isConnected && widget.isHost && !_isExiting) {
          _broadcastLobbyState();
        }
      });
    }

    // Start connection
    _connectToRoom();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (!_isConnected && mounted && !_isExiting) {
        _showBeautifulToast("Still connecting...", color: Colors.amber);
      }
    });
  }

  Future<void> _loadPersistentPremiumLevel() async {
    try {
      final box = await Hive.openBox('premium_storage');
      final int level = box.get('premium_level', defaultValue: 0);

      if (mounted) {
        setState(() {
          _currentSlotLevel = level;
          _updateCapacityFromLevel();
        });
      }
    } catch (e) {
      print("Error loading persistent premium level: $e");
    }
  }

  Future<void> _savePersistentPremiumLevel() async {
    try {
      final box = await Hive.openBox('premium_storage');
      await box.put('premium_level', _currentSlotLevel);
    } catch (e) {
      print("Error saving persistent premium level: $e");
    }
  }

  Future<void> _markUpgradeAsUsed() async {
    try {
      final box = await Hive.openBox('premium_storage');
      await box.put('premium_level', 0);
    } catch (e) {
      print("Error marking upgrade as used: $e");
    }
  }

  void _updateCapacityFromLevel() {
    switch (_currentSlotLevel) {
      case 0:
        _maxSlots = 3;
        break;
      case 1:
        _maxSlots = 6;
        break;
      case 2:
        _maxSlots = 8;
        break;
      case 3:
        _maxSlots = 10;
        break;
      default:
        _maxSlots = 3;
    }
    if (_isConnected) {
      _broadcastLobbyState(force: true);
    }
  }

  // Download system
  Future<void> _startQuizDownload() async {
    if (_cachedQuestions != null) {
      _myDownloadStatus = DownloadStatus.completed;
      _myDownloadProgress = 1.0;
      _broadcastDownloadStatus();
      return;
    }

    if (_myActiveDownload != null && !_myActiveDownload!.isCancelled) {
      _myActiveDownload!.cancel();
    }

    final testId = _roomTestId;

    if (testId == null) {
      print("⏳ Waiting for Test ID from host...");
      return;
    }

    _myActiveDownload = CancelableDownload();
    _shouldCancelMyDownload = false;

    if (mounted) {
      setState(() {
        _myDownloadStatus = DownloadStatus.inProgress;
        _myDownloadProgress = 0.0;
      });
    }

    _broadcastDownloadStatus();

    try {
      final box = await Hive.openLazyBox('app_cache');
      final cachedData = await box.get(testId);

      if (cachedData != null) {
        if (_shouldCancelMyDownload || _myActiveDownload!.isCancelled) {
          _cleanupCancelledDownload();
          return;
        }

        _processQuizData(cachedData);
        if (mounted) {
          setState(() {
            _myDownloadStatus = DownloadStatus.completed;
            _myDownloadProgress = 1.0;
          });
        }
        _broadcastDownloadStatus();
        return;
      }

      final client = http.Client();

      final downloadFuture = _myActiveDownload!.execute(() async {
        final response = await client
            .get(
          Uri.parse("$_r2BaseUrl$testId.json"),
          headers: {'Cache-Control': 'no-cache'},
        )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          throw Exception('Failed to load quiz: ${response.statusCode}');
        }

        final data = jsonDecode(response.body);
        await box.put(testId, data);
        return data;
      });

      _updateDownloadProgressSimulation();

      final data = await downloadFuture;

      if (_shouldCancelMyDownload || _myActiveDownload!.isCancelled) {
        _cleanupCancelledDownload();
        return;
      }

      _processQuizData(data);

      if (mounted) {
        setState(() {
          _myDownloadStatus = DownloadStatus.completed;
          _myDownloadProgress = 1.0;
        });
      }
      _broadcastDownloadStatus();
    } catch (e) {
      if (_shouldCancelMyDownload || _myActiveDownload!.isCancelled) {
        _cleanupCancelledDownload();
      } else {
        print("Quiz download error: $e");
        if (mounted) {
          setState(() {
            _myDownloadStatus = DownloadStatus.failed;
          });
          _showBeautifulToast("Download failed: ${e.toString()}",
              color: Colors.red);
        }
        _broadcastDownloadStatus();
      }
    }
  }

  void _updateDownloadProgressSimulation() async {
    for (int i = 0; i <= 100; i += 10) {
      if (_shouldCancelMyDownload ||
          _myActiveDownload?.isCancelled == true ||
          _myDownloadStatus != DownloadStatus.inProgress) {
        break;
      }

      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted && _myDownloadStatus == DownloadStatus.inProgress) {
        setState(() {
          _myDownloadProgress = i / 100.0;
        });
        _broadcastDownloadStatus();
      }
    }
  }

  void _broadcastDownloadStatus() {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final payload = {
      "type": "download_status",
      "id": _mySessionId,
      "status": _myDownloadStatus.index,
      "progress": _myDownloadProgress,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _client!.publishMessage(
          _updateTopic, MqttQos.atLeastOnce, builder.payload!);
    } catch (_) {}
  }

  void _cleanupCancelledDownload() {
    _myActiveDownload?.cancel();
    _myActiveDownload = null;
    _cachedQuestions = null;

    if (mounted) {
      setState(() {
        _myDownloadStatus = DownloadStatus.cancelled;
        _myDownloadProgress = 0.0;
      });
    }
  }

  void _cancelAllDownloads() {
    _shouldCancelMyDownload = true;
    _myActiveDownload?.cancel();

    for (final download in _activeDownloads.values) {
      download.cancel();
    }
    _activeDownloads.clear();
  }

  // Check if all players are ready
  bool get _allPlayersReady {
    if (_playerMap.isEmpty) return false;

    for (final player in _playerMap.values) {
      final String pid = player['id'];

      // CHECK ME (HOST)
      if (pid == _mySessionId) {
        if (_myDownloadStatus != DownloadStatus.completed) {
          return false;
        }
      }
      // CHECK OTHERS (CLIENTS)
      else {
        final status = _playerDownloadStatus[pid] ?? DownloadStatus.notStarted;
        if (status != DownloadStatus.completed) {
          return false;
        }
      }
    }
    return true;
  }

  // Check if anyone (Me or Others) is currently downloading or not started
  bool get _isAnyoneBusy {
    if (_playerMap.isEmpty) return true;

    for (final player in _playerMap.values) {
      final String pid = player['id'];

      // CHECK ME (HOST/SELF)
      if (pid == _mySessionId) {
        if (_myDownloadStatus == DownloadStatus.inProgress ||
            _myDownloadStatus == DownloadStatus.notStarted) {
          return true;
        }
      }
      // CHECK OTHERS
      else {
        final status = _playerDownloadStatus[pid] ?? DownloadStatus.notStarted;

        if (status == DownloadStatus.inProgress ||
            status == DownloadStatus.notStarted) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (widget.isHost && _isWatchingAd) {
      if (state == AppLifecycleState.paused) {
        _broadcastSystemMessage("🎬 Host is watching an ad to upgrade room...");
      } else if (state == AppLifecycleState.resumed) {
        if (mounted) {
          setState(() => _isWatchingAd = false);
        }
        _broadcastSystemMessage("✅ Host is back!");
        _broadcastLobbyState();
      }
    }

    if (state == AppLifecycleState.paused) {
      _sendHeartbeatImmediately();
    } else if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
          _reconnect();
        } else {
          _sendHeartbeatImmediately();
        }
      });
    }
  }

  void _sendHeartbeatImmediately() {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      "type": "heartbeat",
      "id": _mySessionId,
      "timestamp": DateTime.now().millisecondsSinceEpoch
    }));

    try {
      _client!.publishMessage(
          _hostTopic, MqttQos.atLeastOnce, builder.payload!);
    } catch (_) {}
  }

  void _loadRewardedAd() {
    if (_isAdLoading) return;
    _isAdLoading = true;

    final adUnitId = _rewardedAdUnitId;

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _rewardedAd = ad;
              _isAdLoading = false;
            });
          }
        },
        onAdFailedToLoad: (err) {
          if (mounted) {
            setState(() {
              _isAdLoading = false;
              _rewardedAd = null;
            });
          }
        },
      ),
    );
  }

  void _showAdForSlots() {
    if (_rewardedAd == null) {
      _showBeautifulToast("Loading ad...", color: Colors.amber);
      _loadRewardedAd();
      return;
    }

    if (mounted) {
      setState(() => _isWatchingAd = true);
    }
    _broadcastSystemMessage("🎬 Host is watching an ad for upgrade...");

    _adTimeoutTimer?.cancel();
    _adTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isWatchingAd) {
        setState(() => _isWatchingAd = false);
        _broadcastSystemMessage("✅ Host is back!");
        _broadcastLobbyState();
      }
    });

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _adTimeoutTimer?.cancel();
        ad.dispose();
        _loadRewardedAd();
        if (mounted) {
          setState(() => _isWatchingAd = false);
        }
        _broadcastSystemMessage("✅ Host is back!");
        _broadcastLobbyState();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        _adTimeoutTimer?.cancel();
        ad.dispose();
        _loadRewardedAd();
        if (mounted) {
          setState(() => _isWatchingAd = false);
          _showBeautifulToast("Ad failed: $err", color: Colors.red);
        }
      },
    );

    _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {
      _adTimeoutTimer?.cancel();

      if (mounted) {
        setState(() {
          if (_currentSlotLevel < 3) {
            _currentSlotLevel++;
            _updateCapacityFromLevel();
            _savePersistentPremiumLevel();

            String message;
            switch (_currentSlotLevel) {
              case 1:
                message = "✅ Upgraded to 6 slots! (Persistent until used)";
                break;
              case 2:
                message = "✅ Upgraded to 8 slots! (Persistent until used)";
                break;
              case 3:
                message = "✅ MAX! 10 slots unlocked! (Persistent until used)";
                break;
              default:
                message = "✅ Upgrade complete!";
            }
            _showBeautifulToast(message, color: Colors.green);
          }
        });
      }

      _broadcastLobbyState(force: true);
    });
    _rewardedAd = null;
  }

  void _showBeautifulToast(String message,
      {Color color = const Color(0xFF10B981)}) {
    if (!mounted) return;

    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13 * _adaptiveFontSize,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 2), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  void _broadcastSystemMessage(String message) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final payload = {
      "type": "chat",
      "sender": "System",
      "id": "system",
      "msg": message,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _client!.publishMessage(
          _updateTopic, MqttQos.atLeastOnce, builder.payload!);
    } catch (_) {}
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ExitConfirmationDialog(
        isHost: widget.isHost,
        playerCount: _playerMap.length - 1,
      ),
    );

    if (result == true) {
      await _handleDeliberateExit();
      return true;
    }
    return false;
  }

// inside _handleDeliberateExit()

  Future<void> _handleDeliberateExit() async {
    if (_isExiting) return;
    _isExiting = true;

    print("🚪 Deliberate exit initiated by ${widget.isHost ? 'HOST' : 'CLIENT'}");

    // Cancel all downloads first
    _cancelAllDownloads();

    if (widget.isHost) {
      // 👇 THIS IS CRITICAL. This sends the "room_closed" message manually.
      // Since we changed LWT to "host_lost", this manual message is the
      // ONLY thing that will close the room now.
      await _sendRoomClosedMessage();
    } else {
      await _sendLeaveMessage();
    }

    // Disconnect and navigate
    try {
      _client?.disconnect();
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _sendRoomClosedMessage() async {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final msg = {
      "type": "room_closed",
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "reason": "Host closed the room",
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(msg));

    print("📤 Sending room_closed message (5 times for reliability)");

    try {
      for (int i = 0; i < 5; i++) {
        _client!.publishMessage(
            _updateTopic, MqttQos.atLeastOnce, builder.payload!);
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("❌ Error sending room closed: $e");
    }
  }

  Future<void> _sendLeaveMessage() async {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final msg = {
      "type": "leave",
      "id": _mySessionId,
      "name": widget.userName,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "deliberate": true,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(msg));

    print("📤 Sending leave message (5 times for reliability)");

    try {
      for (int i = 0; i < 5; i++) {
        _client!.publishMessage(
            _hostTopic, MqttQos.atLeastOnce, builder.payload!);
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      print("❌ Error sending leave message: $e");
    }
  }

  void _checkInactivePlayers() {
    if (!widget.isHost) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    bool stateChanged = false;

    for (final entry in _playerMap.entries) {
      if (entry.value['isHost'] == true) continue;

      final lastSeen = entry.value['lastSeen'] as int? ?? 0;
      final timeSinceLastSeen = now - lastSeen;

      if (timeSinceLastSeen > _inactiveTimeout) {
        if (entry.value['isInactive'] != true) {
          entry.value['isInactive'] = true;
          stateChanged = true;
          print("⚠️ Player ${entry.value['name']} marked as inactive");
        }
      } else {
        if (entry.value['isInactive'] == true) {
          entry.value['isInactive'] = false;
          stateChanged = true;
          print("✅ Player ${entry.value['name']} is active again");
        }
      }
    }

    if (stateChanged && mounted) {
      setState(() {});
      _broadcastLobbyState(force: true);
    }
  }

  Future<void> _onStartClicked() async {
    if (_isStartingGame || _isWatchingAd) return;
    _isStartingGame = true;

    _pruneZombiePlayers();

    if (_playerMap.length < 2) {
      _showBeautifulToast("Need at least 1 other player!", color: Colors.orange);
      _isStartingGame = false;
      return;
    }

    if (!_allPlayersReady) {
      _showBeautifulToast("Waiting for players to download...",
          color: Colors.orange);
      _isStartingGame = false;
      return;
    }

    if (_cachedQuestions == null || _cachedQuestions!.isEmpty) {
      _showBeautifulToast("Quiz not loaded!", color: Colors.red);
      _isStartingGame = false;
      return;
    }

    int totalMinutes =
        widget.examData?['d'] ?? widget.examData?['duration'] ?? 15;
    int totalQuestions = _cachedQuestions!.length;
    if (totalQuestions == 0) totalQuestions = 1;
    int secPerQ = (totalMinutes * 60) ~/ totalQuestions;
    secPerQ = secPerQ.clamp(10, 300);

    await Future.delayed(const Duration(milliseconds: 300));

    final payload = {
      "type": "start_game",
      "testId": widget.examData?['id'],
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "duration": secPerQ,
      "questionCount": _cachedQuestions!.length,
      "capacity": _maxSlots,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _client!.publishMessage(
          _updateTopic, MqttQos.atLeastOnce, builder.payload!);
      await Future.delayed(const Duration(milliseconds: 300));

      if (widget.isHost && _currentSlotLevel > 0) {
        await _markUpgradeAsUsed();
      }

      _goToGame(_cachedQuestions!, secPerQ);
    } catch (e) {
      _showBeautifulToast("Failed to start: ${e.toString()}",
          color: Colors.red);
      _isStartingGame = false;
    }
  }

  void _pruneZombiePlayers() {
    if (!widget.isHost) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<String> toRemove = [];

    for (final entry in _playerMap.entries) {
      if (entry.value['isHost'] == true) continue;

      final lastSeen = entry.value['lastSeen'] as int? ?? 0;
      if (now - lastSeen > _zombieTimeout) {
        toRemove.add(entry.key);
      }
    }

    if (toRemove.isNotEmpty) {
      setState(() {
        for (final key in toRemove) {
          final name = _playerMap[key]?['name'] ?? 'Unknown';
          _playerMap.remove(key);
          _playerLastHeartbeat.remove(key);
          _playerLastActivity.remove(key);
          _playerDownloadStatus.remove(key);
          _playerDownloadProgress.remove(key);
          print("🧟 Removed zombie player: $name");
          _broadcastSystemMessage("👋 $name timed out");
        }
      });

      _broadcastLobbyState(force: true);
    }
  }

  @override
  void dispose() {
    _isExiting = true;
    WidgetsBinding.instance.removeObserver(this);

    _heartbeatTimer?.cancel();
    _reaperTimer?.cancel();
    _broadcastDebounceTimer?.cancel();
    _joinRetryTimer?.cancel();
    _adTimeoutTimer?.cancel();
    _capacitySyncTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _inactivityCheckTimer?.cancel();

    _mqttSubscription?.cancel();

    _chatController.dispose();
    _scrollController.dispose();
    _tabController.dispose();

    // Cancel all downloads
    _cancelAllDownloads();

    try {
      if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
        _client?.disconnect();
      }
    } catch (_) {}

    _rewardedAd?.dispose();

    super.dispose();
  }

  void _processQuizData(dynamic data, {bool autoStart = false}) {
    List<dynamic> qList = [];
    if (data is List) {
      qList = data;
    } else if (data is Map) {
      qList = data['data'] ?? data['questions'] ?? data['q'] ?? [];
    }

    if (mounted && qList.isNotEmpty) {
      setState(() => _cachedQuestions = qList);
      if (autoStart) {
        final duration = data is Map ? (data['duration'] ?? 60) : 60;
        _goToGame(qList, duration);
      }
    }
  }

  void _goToGame(List<dynamic> questions, int secondsPerQuestion) {
    if (!mounted || _isExiting) return;
    _isExiting = true;

    // Cancel all timers
    _heartbeatTimer?.cancel();
    _reaperTimer?.cancel();
    _joinRetryTimer?.cancel();
    _capacitySyncTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _inactivityCheckTimer?.cancel();

    try {
      _client?.updates?.drain();
      _client?.disconnect();
    } catch (_) {}

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MultiplayerQuizScreen(
          isHost: widget.isHost,
          roomCode: widget.roomCode,
          userName: widget.userName,
          initialPlayers: _playerMap.values.toList(),
          questions: questions,
          secondsPerQuestion: secondsPerQuestion,
          myId: _mySessionId,
        ),
      ),
    );
  }

  Future<void> _connectToRoom() async {
    if (_isExiting || _isRoomClosed) return;

    if (_connectionRetryCount >= _maxConnectionRetries) {
      if (mounted) {
        setState(() => _statusText = "Connection failed");
        _showBeautifulToast("Cannot connect. Please try again.",
            color: Colors.red);
      }
      return;
    }

    _connectionRetryCount++;

    if (mounted) {
      setState(() => _statusText = "Connecting...");
    }

    final String clientId =
        "user_${Random().nextInt(999999)}_${DateTime.now().millisecondsSinceEpoch}";
    _client = MqttServerClient('test.mosquitto.org', clientId);

    _client!.port = 1883;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 25;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.setProtocolV311();

    // Last Will and Testament
    String lwtTopic = widget.isHost ? _updateTopic : _hostTopic;
    String lwtMessage = widget.isHost
        ? jsonEncode({
      "type": "host_lost",
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "reason": "Host connection weak...",
    })
        : jsonEncode({
      "type": "leave",
      "id": _mySessionId,
      "name": widget.userName,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
      "deliberate": false,
    });

    _client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic(lwtTopic)
        .withWillMessage(lwtMessage)
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();

    try {
      await _client!.connect().timeout(const Duration(seconds: 8));
    } catch (e) {
      print("Connection error: $e");
      if (mounted && !_isExiting) {
        setState(() => _statusText = "Reconnecting...");
      }

      final delay = Duration(seconds: min(_connectionRetryCount, 5));

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () {
        if (!_isExiting && mounted && !_isRoomClosed) {
          _connectToRoom();
        }
      });
      return;
    }
  }

  void _onConnected() {
    if (_isExiting || !mounted) return;

    _connectionRetryCount = 0;
    _totalDisconnections = 0;
    _lastStableConnectionTime = DateTime.now().millisecondsSinceEpoch;

    if (mounted) {
      setState(() {
        _isConnected = true;
        _statusText = "Connected!";
        _isNetworkStable = true;
      });
    }

    _setupListeners();
    _startHeartbeat();

    if (!widget.isHost) {
      _startJoinRetryLoop();
    } else {
      Future.delayed(const Duration(milliseconds: 500),
              () => _broadcastLobbyState(force: true));
    }
  }

  void _onSubscribed(String topic) {
    if (mounted && _isConnected) {
      setState(() => _statusText = "Ready");
    }
  }

  void _onDisconnected() {
    if (_isExiting || !mounted) return;

    _totalDisconnections++;

    // Cancel downloads on disconnect
    if (!widget.isHost) {
      _shouldCancelMyDownload = true;
      _myActiveDownload?.cancel();
    }

    if (mounted) {
      setState(() {
        _isConnected = false;
        _statusText = "Reconnecting...";
        _isNetworkStable = false;
      });
    }

    _heartbeatTimer?.cancel();

    final delay = Duration(seconds: min(_totalDisconnections, 10));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isExiting && mounted && !_isRoomClosed) {
        _connectToRoom();
      }
    });
  }

  void _reconnect() {
    if (_isExiting || _isRoomClosed) return;

    try {
      if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
        _client?.disconnect();
      }
    } catch (_) {}

    _connectToRoom();
  }

  void _startJoinRetryLoop() {
    _joinRetryTimer?.cancel();
    _sendJoinRequest();

    _joinRetryTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isExiting || _isInLobbyList || _isRoomClosed) {
        timer.cancel();
        return;
      }
      _sendJoinRequest();
    });
  }

  void _sendJoinRequest() {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastRequest = _lastJoinRequestTime[_mySessionId] ?? 0;
    if (now - lastRequest < 1000) return;
    _lastJoinRequestTime[_mySessionId] = now;

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode({
      "type": "join",
      "name": widget.userName,
      "avatar": _myAvatarId,
      "id": _mySessionId,
      "timestamp": now,
    }));

    try {
      _client!.publishMessage(
          _hostTopic, MqttQos.atLeastOnce, builder.payload!);
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
        _missedHeartbeats++;

        if (_missedHeartbeats > 2 && mounted && !_isExiting) {
          setState(() {
            _statusText = "Connection weak...";
            _isNetworkStable = false;
          });
        }

        if (_missedHeartbeats > 4) {
          _onDisconnected();
          return;
        }
      } else {
        if (_missedHeartbeats > 0) {
          _missedHeartbeats = 0;
          _lastStableConnectionTime = DateTime.now().millisecondsSinceEpoch;
          if (mounted) {
            setState(() => _isNetworkStable = true);
          }
        }

        _sendHeartbeatImmediately();
      }
    });
  }

  bool _shouldWarnAboutConnection() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - _lastStableConnectionTime) > 30000;
  }

  void _setupListeners() {
    _client!.subscribe(_updateTopic, MqttQos.atLeastOnce);

    if (widget.isHost) {
      _client!.subscribe(_hostTopic, MqttQos.atLeastOnce);
    }

    _mqttSubscription =
        _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> c) {
          if (c.isEmpty) return;

          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          try {
            if (!_isExiting && mounted) {
              final decoded = jsonDecode(pt);
              if (decoded is Map) {
                _handleMessage(c[0].topic, decoded);
              }
            }
          } catch (e) {
            // Silent parse error
          }
        }, onError: (error) {
          print("MQTT error: $error");
        });
  }

  void _handleMessage(String topic, Map data) {
    if (_isExiting || !mounted) return;

    final int? msgTime = data['timestamp'];
    if (msgTime != null) {
      if (DateTime.now().millisecondsSinceEpoch - msgTime > 30000) return;
    }

    if (data['type'] == 'chat') {
      _handleChatMessage(data);
      return;
    }

    if (data['type'] == 'download_status') {
      _handleDownloadStatus(data);
      return;
    }

    if (topic == _hostTopic && widget.isHost) {
      final String? playerId = data['id'];
      if (playerId == null) return;

      switch (data['type']) {
        case 'join':
          _handleJoinRequest(data, playerId);
          break;
        case 'heartbeat':
          _handleHeartbeat(playerId);
          break;
        case 'leave':
          _handleLeaveImmediate(
              playerId, data['name'], data['deliberate'] == true);
          break;
      }
    }

    if (topic == _updateTopic) {
      switch (data['type']) {
        case 'reject':
          if (data['targetId'] == _mySessionId) {
            _cleanupAndExit("Room is full", isFull: true);
          }
          break;

        case 'lobby_update':
          _handleLobbyUpdate(data);
          break;

        case 'host_lost':
        // Just show a toast, DO NOT kick the user out
          _showBeautifulToast("⚠️ Host connection weak... waiting...", color: Colors.orange);
          break;

        case 'start_game':
          if (!widget.isHost && !_isExiting && !_isRoomClosed) {
            final testId = data['testId'];
            if (testId != null && _myDownloadStatus == DownloadStatus.completed) {
              _goToGame(_cachedQuestions!, data['duration'] ?? 60);
            }
          }
          break;

        case 'room_closed':
          _handleRoomClosedImmediate(data);
          break;
      }
    }
  }

  void _handleDownloadStatus(Map data) {
    final String playerId = data['id'];
    final int statusIndex = data['status'];
    final double progress = (data['progress'] ?? 0.0).toDouble();

    if (mounted) {
      setState(() {
        _playerDownloadStatus[playerId] = DownloadStatus.values[statusIndex];
        _playerDownloadProgress[playerId] = progress;
      });
    }
  }

  void _handleRoomClosedImmediate(Map data) {
    if (_isExiting || !mounted || widget.isHost) return;

    print("🚨 ROOM CLOSED received - immediate shutdown");

    _isRoomClosed = true;
    _isExiting = true;

    // Cancel downloads
    _shouldCancelMyDownload = true;
    _myActiveDownload?.cancel();

    final reason = data['reason'] ?? "Host closed the room";

    // Cancel all timers
    _heartbeatTimer?.cancel();
    _reaperTimer?.cancel();
    _joinRetryTimer?.cancel();
    _capacitySyncTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _inactivityCheckTimer?.cancel();

    // Disconnect MQTT
    try {
      _client?.disconnect();
    } catch (_) {}

    if (mounted) {
      _showBeautifulToast(reason, color: Colors.red);

      // Navigate back immediately
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _handleLeaveImmediate(
      String playerId, String? playerName, bool isDeliberate) {
    if (!widget.isHost || !_playerMap.containsKey(playerId)) return;

    final name = playerName ?? _playerMap[playerId]!['name'] ?? 'Player';

    print(
        "👋 Player $name left ${isDeliberate ? '(DELIBERATE)' : '(timeout/disconnect)'}");

    if (mounted) {
      setState(() {
        _playerMap.remove(playerId);
        _playerLastHeartbeat.remove(playerId);
        _playerLastActivity.remove(playerId);
        _playerDownloadStatus.remove(playerId);
        _playerDownloadProgress.remove(playerId);
      });
    }

    _broadcastLobbyState(force: true);
    _broadcastSystemMessage("👋 $name left");

    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_isExiting && _isConnected) {
        _broadcastLobbyState(force: true);
      }
    });
  }

  void _handleChatMessage(Map data) {
    if (mounted) {
      final bool isMe = data['id'] == _mySessionId;
      _messages.add({
        'sender': data['sender'],
        'msg': data['msg'],
        'isMe': isMe.toString(),
      });

      if (_messages.length > _chatLimit) {
        _messages.removeAt(0);
      }

      if (_tabController.index != 1) {
        _hasUnreadMessages = true;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastUiUpdate > 100) {
        setState(() {
          _lastUiUpdate = now;
        });
      }
    }
  }

  void _handleJoinRequest(Map data, String playerId) {
    // 1. Anti-Spam (Same as before)
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastRequest = _lastJoinRequestTime[playerId] ?? 0;
    if (now - lastRequest < 1000) return;
    _lastJoinRequestTime[playerId] = now;

    if (_playerMap.containsKey(playerId)) return;

    // 2. Capacity Check (Same as before)
    if (_playerMap.length >= _maxSlots) {
      if (widget.isHost) _sendRejection(playerId, "Room is full");
      return;
    }

    // 3. Add Player Locally (Same as before)
    if (mounted) {
      setState(() {
        _playerMap[playerId] = {
          'id': playerId,
          'name': data['name'] ?? 'Player',
          'avatar': data['avatar'] ?? 0,
          'isHost': false,
          'lastSeen': now,
          'isInactive': false,
        };
        _playerLastHeartbeat[playerId] = now;
        _playerLastActivity[playerId] = now;
        _playerDownloadStatus[playerId] = DownloadStatus.notStarted;
      });
    }

    // 4. THE SMART STABILITY LOGIC 🧠

    // A. Get sorted list of IDs
    final List<String> allIds = _playerMap.keys.toList()..sort();
    int myIndex = allIds.indexOf(_mySessionId);
    if (myIndex == -1) return;

    // B. Base Delay (Seniority)
    // Host=0ms, P2=800ms, P3=1600ms
    int delay = myIndex * 800;

    // C. THE STABILITY PENALTY (New!)
    // If I have missed heartbeats or my connection flag is false,
    // I am "unstable". I should step back and let others handle it.
    if (!_isNetworkStable || _missedHeartbeats > 0) {
      // Add 3 seconds to my timer.
      // This pushes me to the back of the line, giving stable players a chance to act first.
      delay += 3000;
    }

    // D. The Timer
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted || !_isConnected) return;

      final timeSinceLastBroadcast = DateTime.now().millisecondsSinceEpoch - _lastBroadcastTime;

      // If someone faster (more stable) broadcasted in the last 700ms, I stay silent.
      if (timeSinceLastBroadcast > 700) {
        // print("⚡ I am the most stable one right now! Taking control.");

        _broadcastLobbyState(force: true);

        if (widget.isHost) {
          _broadcastSystemMessage("🎉 ${data['name']} joined!");
        }
      }
    });
  }
  void _handleHeartbeat(String playerId) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_playerMap.containsKey(playerId)) {
      _playerMap[playerId]!['lastSeen'] = now;
      _playerLastHeartbeat[playerId] = now;
      _playerLastActivity[playerId] = now;

      if (_playerMap[playerId]!['isInactive'] == true) {
        _playerMap[playerId]!['isInactive'] = false;
        if (mounted) {
          setState(() {});
        }
        _broadcastLobbyState(force: true);
      }
    }
  }

  void _handleLobbyUpdate(Map data) {
    _lastBroadcastTime = DateTime.now().millisecondsSinceEpoch;
    final List<dynamic> incomingList = data['players'];
    final int capacity = data['capacity'] ?? 3;

    if (!widget.isHost) {
      final me = incomingList.firstWhereOrNull((p) => p['id'] == _mySessionId);
      if (me != null && !_isInLobbyList) {
        _isInLobbyList = true;
        _joinRetryTimer?.cancel();
      }
    }

    final String newState =
        "$capacity${incomingList.map((p) => p['id']).join(',')}";
    final String oldState =
        "${_lastLobbyState['capacity']}${_lastLobbyState['players']?.map((p) => p['id']).join(',')}";

    if (newState != oldState) {
      _lastLobbyState['capacity'] = capacity;
      _lastLobbyState['players'] = incomingList;

      if (mounted) {
        setState(() {
          _playerMap.clear();
          for (var p in incomingList) {
            if (p['id'] != null) {
              _playerMap[p['id']] = p;
            }
          }

          if (!widget.isHost) {
            _maxSlots = capacity;
          }
        });
      }
    }

    if (!widget.isHost) {
      final String? incomingId = data['testId'];

      if (incomingId != null && incomingId != _roomTestId) {
        print("Received new Test ID: $incomingId");
        setState(() {
          _roomTestId = incomingId;
          _myDownloadStatus = DownloadStatus.notStarted;
        });

        _startQuizDownload();
      }
    }
  }

  void _sendRejection(String playerId, String reason) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final payload = {
      "type": "reject",
      "targetId": playerId,
      "reason": reason,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    try {
      _client!.publishMessage(
          _updateTopic, MqttQos.atLeastOnce, builder.payload!);
    } catch (_) {}
  }

  void _sendChatMessage() {
    if (_chatController.text.trim().isEmpty) return;

    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      _showBeautifulToast("Not connected", color: Colors.red);
      return;
    }

    final msg = _chatController.text.trim();
    if (msg.length > 200) {
      _showBeautifulToast("Max 200 characters", color: Colors.orange);
      return;
    }

    final payload = {
      "type": "chat",
      "sender": widget.userName,
      "id": _mySessionId,
      "msg": msg,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    _client!.publishMessage(
        _updateTopic, MqttQos.atLeastOnce, builder.payload!);
    _chatController.clear();
  }

  void _broadcastLobbyState({bool force = false}) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force && now - _lastBroadcastTime < 1000) {
      return;
    }
    _lastBroadcastTime = now;

    _broadcastDebounceTimer?.cancel();
    _broadcastDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (_client?.connectionStatus?.state != MqttConnectionState.connected) return;

      final builder = MqttClientPayloadBuilder();
      final data = {
        "type": "lobby_update",
        "players": _playerMap.values.toList(),
        "capacity": _maxSlots,
        "testId": widget.examData?['id'],
        "timestamp": now,
      };

      builder.addString(jsonEncode(data));

      try {
        _client!.publishMessage(
            _updateTopic, MqttQos.atLeastOnce, builder.payload!);
      } catch (_) {}
    });
  }

  void _cleanupAndExit(String reason, {bool isFull = false}) {
    if (!mounted || _isExiting) return;
    _isExiting = true;

    // Cancel downloads
    _shouldCancelMyDownload = true;
    _myActiveDownload?.cancel();

    if (isFull) {
      if (mounted) {
        Navigator.pop(context, "room_full");
      }
    } else {
      _showBeautifulToast(reason, color: Colors.red);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.roomCode));
    _showBeautifulToast("Code Copied!", color: Colors.blueAccent);
  }

  void _shareCode() {
    // Your App Link
    const String appLink = 'https://play.google.com/store/apps/details?id=com.ashirwaddigital.rrbprep';

    final String message =
        '🔥 *RRB NTPC Quiz Challenge!*\n\n'
        'I am waiting for you in the arena! ⚔️\n'
        '🔑 Room Code: *${widget.roomCode}*\n\n'
        '📍 *Steps to Join:*\n'
        '1️⃣ Open App\n'
        '2️⃣ Tap *Group Battle*\n'
        '3️⃣ Select *Join Room* & enter code\n\n'
        '👇 *Download Now:*\n'
        '$appLink';

    Share.share(message);
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _isConnected;
    final List<dynamic> playerList = _playerMap.values.toList();

    // -----------------------------------------------------------
    // FIX: Force Status Bar to have WHITE icons (Time, Battery, etc.)
    // -----------------------------------------------------------
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        // For Android: White icons
        statusBarIconBrightness: Brightness.light,
        // For iOS: White icons (Dark background)
        statusBarBrightness: Brightness.dark,
        // Transparent background so your app color shows through
        statusBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          await _onWillPop();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF1E293B),
          // Keep this false to fix the "squeeze" issue from before
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    // ... (The rest of your existing build code stays exactly the same)
                    // HEADER
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth * 0.04,
                        vertical: constraints.maxHeight * 0.01,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                            color: Colors.white,
                            onPressed: () => _onWillPop(),
                          ),
                          Text("Lobby",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18 * _adaptiveFontSize,
                                fontWeight: FontWeight.bold,
                              )),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.people_rounded,
                                    color: Colors.white70, size: 16),
                                Text(
                                  "  ${playerList.length}/$_maxSlots",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13 * _adaptiveFontSize,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_isNetworkStable) ...[
                            SizedBox(width: constraints.maxWidth * 0.02),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange),
                              ),
                              child: const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 14),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // BODY CONTENT
                    if (!isReady)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: constraints.maxWidth * 0.1,
                                height: constraints.maxWidth * 0.1,
                                child: CircularProgressIndicator(
                                  color: const Color(0xFF4169E1),
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: constraints.maxHeight * 0.02),
                              Text(
                                _statusText,
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 16 * _adaptiveFontSize,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                              if (_statusText.contains("Attempt")) ...[
                                SizedBox(height: constraints.maxHeight * 0.01),
                                Text(
                                  "Attempt $_connectionRetryCount of $_maxConnectionRetries",
                                  style: GoogleFonts.inter(
                                    color: Colors.white54,
                                    fontSize: 12 * _adaptiveFontSize,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: _LiveRoomBody(
                          statusText: _statusText,
                          isHost: widget.isHost,
                          roomCode: widget.roomCode,
                          playerList: playerList,
                          hasUnreadMessages: _hasUnreadMessages,
                          messages: _messages,
                          userName: widget.userName,
                          myId: _mySessionId,
                          tabController: _tabController,
                          chatController: _chatController,
                          scrollController: _scrollController,
                          onCopy: _copyCode,
                          onShare: _shareCode,
                          onSendChat: _sendChatMessage,
                          onStartGame: _onStartClicked,
                          isDownloading: _isAnyoneBusy,
                          maxSlots: _maxSlots,
                          onWatchAd: _showAdForSlots,
                          isWatchingAd: _isWatchingAd,
                          currentSlotLevel: _currentSlotLevel,
                          isNetworkStable: _isNetworkStable,
                          hasLongConnectionIssue: _shouldWarnAboutConnection(),
                          playerDownloadStatus: _playerDownloadStatus,
                          playerDownloadProgress: _playerDownloadProgress,
                          myDownloadStatus: _myDownloadStatus,
                          myDownloadProgress: _myDownloadProgress,
                          allPlayersReady: _allPlayersReady,
                          constraints: constraints,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

}

// Helper classes
enum DownloadStatus {
  notStarted,
  inProgress,
  completed,
  failed,
  cancelled,
}

class CancelableDownload {
  bool _isCancelled = false;
  Completer? _completer;

  bool get isCancelled => _isCancelled;

  Future<T> execute<T>(Future<T> Function() task) async {
    _isCancelled = false;
    _completer = Completer<T>();

    try {
      final result = await task();

      if (!_isCancelled && !(_completer?.isCompleted ?? true)) {
        _completer!.complete(result);
      }
    } catch (e, stack) {
      if (!_isCancelled && !(_completer?.isCompleted ?? true)) {
        _completer!.completeError(e, stack);
      }
    }

    return (_completer!.future as Future<T>);
  }

  void cancel() {
    _isCancelled = true;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError("Download cancelled");
    }
  }
}

class _ExitConfirmationDialog extends StatelessWidget {
  final bool isHost;
  final int playerCount;

  const _ExitConfirmationDialog({
    required this.isHost,
    required this.playerCount,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontSizeScale = min(screenWidth, 400) / 400;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      backgroundColor: const Color(0xFF1E293B),
      title: Row(
        children: [
          Icon(
            isHost ? Icons.exit_to_app : Icons.logout,
            color: Colors.white,
            size: 24 * fontSizeScale,
          ),
          SizedBox(width: screenWidth * 0.03),
          Text(
            isHost ? "Exit Lobby?" : "Leave Room?",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20 * fontSizeScale,
            ),
          ),
        ],
      ),
      content: Text(
        isHost
            ? "You are the host. If you leave, ${playerCount} other player${playerCount != 1 ? 's' : ''} will be disconnected.\n\nYour upgrade will be saved for next time!"
            : "Are you sure you want to leave the room?",
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 14 * fontSizeScale,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(
            "Stay",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            isHost ? "Exit Room" : "Leave",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LiveRoomBody extends StatelessWidget {
  final String statusText;
  final bool isHost;
  final String roomCode;
  final List<dynamic> playerList;
  final bool hasUnreadMessages;
  final List<Map<String, String>> messages;
  final String userName;
  final String myId;
  final TabController tabController;
  final TextEditingController chatController;
  final ScrollController scrollController;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onSendChat;
  final VoidCallback onStartGame;
  final bool isDownloading;
  final int maxSlots;
  final VoidCallback onWatchAd;
  final bool isWatchingAd;
  final int currentSlotLevel;
  final bool isNetworkStable;
  final bool hasLongConnectionIssue;
  final Map<String, DownloadStatus> playerDownloadStatus;
  final Map<String, double> playerDownloadProgress;
  final DownloadStatus myDownloadStatus;
  final double myDownloadProgress;
  final bool allPlayersReady;
  final BoxConstraints constraints;

  const _LiveRoomBody({
    super.key,
    required this.statusText,
    required this.isHost,
    required this.roomCode,
    required this.playerList,
    required this.hasUnreadMessages,
    required this.messages,
    required this.userName,
    required this.myId,
    required this.tabController,
    required this.chatController,
    required this.scrollController,
    required this.onCopy,
    required this.onShare,
    required this.onSendChat,
    required this.onStartGame,
    required this.isDownloading,
    required this.maxSlots,
    required this.onWatchAd,
    required this.isWatchingAd,
    required this.currentSlotLevel,
    required this.isNetworkStable,
    required this.hasLongConnectionIssue,
    required this.playerDownloadStatus,
    required this.playerDownloadProgress,
    required this.myDownloadStatus,
    required this.myDownloadProgress,
    required this.allPlayersReady,
    required this.constraints,
  });

  String _getAdButtonText() {
    switch (maxSlots) {
      case 3:
        return "Watch Ad for +3 Slots → 6";
      case 6:
        return "Watch Ad for +2 Slots → 8";
      case 8:
        return "Watch Ad for +2 Slots → 10";
      default:
        return "Max Slots Reached!";
    }
  }

  void _showQrDialog(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = min(screenWidth, 400) / 400;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: EdgeInsets.all(24.0 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Scan to Join",
                  style: GoogleFonts.poppins(
                    fontSize: 20 * scale,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  )),
              SizedBox(height: 20 * scale),
              SizedBox(
                width: screenWidth * 0.5,
                height: screenWidth * 0.5,
                child: QrImageView(
                  data: roomCode,
                  version: QrVersions.auto,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E293B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              SizedBox(height: 20 * scale),
              Text(
                roomCode,
                style: GoogleFonts.notoSans(
                  fontSize: 24 * scale,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: const Color(0xFF10B981),
                ),
              ),
              SizedBox(height: 20 * scale),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4169E1),
                  padding: EdgeInsets.symmetric(
                      horizontal: 24 * scale, vertical: 8 * scale),
                ),
                child: const Text("Close"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _responsiveScale => min(constraints.maxWidth, 400) / 400;
  double get _adaptiveFontSize => constraints.maxWidth < 360 ? 0.85 : 1.0;

  @override
  Widget build(BuildContext context) {
    // -----------------------------------------------------------
    // KEYBOARD DETECTION LOGIC
    // -----------------------------------------------------------
    // Because we set resizeToAvoidBottomInset: false in the Scaffold,
    // the viewInsets.bottom will correctly return the keyboard height.
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardHeight > 0;

    return Column(
      children: [
        // -----------------------------------------------------------
        // 1. HEADER SECTION
        // We HIDE this completely when keyboard is open to give space for chat
        // -----------------------------------------------------------
        if (!isKeyboardOpen)
          Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.04,
              vertical: constraints.maxHeight * 0.01,
            ),
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.35,
              minHeight: constraints.maxHeight * 0.25,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth * 0.05,
                vertical: constraints.maxHeight * 0.02,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "ROOM CODE",
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10 * _adaptiveFontSize,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: constraints.maxHeight * 0.005),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      roomCode,
                      style: GoogleFonts.notoSans(
                        color: const Color(0xFF4ADE80),
                        fontSize: 38 * _responsiveScale,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  SizedBox(height: constraints.maxHeight * 0.015),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CircleIconBtn(
                        icon: Icons.copy,
                        color: const Color(0xFF4169E1),
                        onTap: onCopy,
                        size: constraints.maxWidth * 0.12,
                      ),
                      SizedBox(width: constraints.maxWidth * 0.04),
                      _CircleIconBtn(
                        icon: Icons.share,
                        color: Colors.pink.shade300,
                        onTap: onShare,
                        size: constraints.maxWidth * 0.12,
                      ),
                      SizedBox(width: constraints.maxWidth * 0.04),
                      _CircleIconBtn(
                        icon: Icons.qr_code,
                        color: Colors.white,
                        onTap: () => _showQrDialog(context),
                        size: constraints.maxWidth * 0.12,
                      ),
                    ],
                  ),
                  if (isHost && maxSlots < 10 && !isWatchingAd) ...[
                    SizedBox(height: constraints.maxHeight * 0.015),
                    SizedBox(
                      height: constraints.maxHeight * 0.05,
                      child: ElevatedButton(
                        onPressed: onWatchAd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: constraints.maxWidth * 0.03,
                            vertical: constraints.maxHeight * 0.01,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.ads_click_rounded,
                                size: 16 * _adaptiveFontSize),
                            SizedBox(width: 8 * _adaptiveFontSize),
                            Flexible(
                              child: Text(
                                _getAdButtonText(),
                                style: GoogleFonts.inter(
                                  fontSize: 11 * _adaptiveFontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (isHost && currentSlotLevel > 0) ...[
                    SizedBox(height: constraints.maxHeight * 0.015),
                    Text(
                      "Upgraded to $maxSlots slots!",
                      style: GoogleFonts.inter(
                        fontSize: 11 * _adaptiveFontSize,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        // -----------------------------------------------------------
        // Minimal header when keyboard is open to avoid squeezing
        // -----------------------------------------------------------
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "Room: $roomCode",
              style: GoogleFonts.notoSans(
                color: Colors.white70,
                fontSize: 14 * _adaptiveFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        // -----------------------------------------------------------
        // 2. MAIN CONTENT AREA
        // -----------------------------------------------------------
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            // We apply padding to the bottom of this column equal to the keyboard height.
            // This ensures the chat input sits exactly on top of the keyboard.
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: Column(
                children: [
                  // TAB BAR
                  SizedBox(
                    height: 50,
                    child: TabBar(
                      controller: tabController,
                      labelColor: const Color(0xFF1E293B),
                      unselectedLabelColor: const Color(0xFF4169E1),
                      indicatorColor: const Color(0xFF4169E1),
                      indicatorWeight: 3,
                      labelStyle: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14 * _adaptiveFontSize,
                      ),
                      unselectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 14 * _adaptiveFontSize,
                      ),
                      onTap: (index) {
                        if (index == 0) {
                          FocusScope.of(context).unfocus();
                        }
                      },
                      tabs: [
                        const Tab(text: "Players"),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Chat"),
                              if (hasUnreadMessages)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // TAB VIEW
                  Expanded(
                    child: TabBarView(
                      controller: tabController,
                      children: [
                        _buildPlayerList(),
                        _buildChatTab(context),
                      ],
                    ),
                  ),

                  // -----------------------------------------------------------
                  // 3. BOTTOM CONTROLS & AD
                  // We ONLY render these if the keyboard is NOT open.
                  // -----------------------------------------------------------
                  if (!isKeyboardOpen) ...[
                    if (isHost)
                      _buildHostControls()
                    else
                      _buildClientWaitingBar(),
                    const SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: AdBanner(size: AdSize.banner),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildPlayerList() {
    if (playerList.isEmpty) {
      return Center(
        child: Text("Waiting for players...",
            style: GoogleFonts.inter(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: constraints.maxWidth * 0.04,
        vertical: constraints.maxHeight * 0.02,
      ),
      itemCount: playerList.length,
      separatorBuilder: (c, i) =>
          SizedBox(height: constraints.maxHeight * 0.01),
      itemBuilder: (context, index) {
        final p = playerList[index];
        final bool isMe = p['id'] == myId;
        final bool isInactive = p['isInactive'] == true;
        final DownloadStatus status = isMe
            ? myDownloadStatus
            : playerDownloadStatus[p['id']] ?? DownloadStatus.notStarted;
        final double progress = isMe
            ? myDownloadProgress
            : playerDownloadProgress[p['id']] ?? 0.0;

        return _PlayerListItem(
          key: ValueKey('${p['id']}_${p['name']}'),
          player: p,
          isMe: isMe,
          isInactive: isInactive,
          downloadStatus: status,
          downloadProgress: progress,
          constraints: constraints,
        );
      },
    );
  }

  Widget _buildChatTab(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
            child: Text("Say hello! 👋",
                style: GoogleFonts.inter(color: Colors.grey)),
          )
              : ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _ChatBubble(
                key: ValueKey('${msg['sender']}_${msg['msg']}_$index'),
                message: msg,
                isMe: msg['isMe'] == 'true',
                constraints: constraints,
              );
            },
          ),
        ),
        // Chat Input Area
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: chatController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 200,
                    style: GoogleFonts.inter(
                        color: Colors.black87, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      border: InputBorder.none,
                      counterText: "",
                    ),
                    onSubmitted: (_) => onSendChat(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF4169E1)),
                onPressed: onSendChat,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHostControls() {
    final bool canStart =
        playerList.length > 1 && allPlayersReady && !isWatchingAd;

    return Container(
      padding: EdgeInsets.fromLTRB(
        constraints.maxWidth * 0.04,
        constraints.maxHeight * 0.01,
        constraints.maxWidth * 0.04,
        constraints.maxHeight * 0.005,
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: canStart ? onStartGame : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: canStart ? const Color(0xFF10B981) : Colors.grey,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isDownloading || isWatchingAd
                  ? Text(isWatchingAd ? "WATCHING AD..." : "DOWNLOADING...",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold))
                  : Text(
                !allPlayersReady ? "WAITING..." : "START GAME 🚀",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientWaitingBar() {
    final String statusText;
    if (myDownloadStatus == DownloadStatus.inProgress) {
      statusText = "Downloading... ${(myDownloadProgress * 100).toInt()}%";
    } else if (myDownloadStatus == DownloadStatus.completed) {
      statusText = "Ready! Waiting for host...";
    } else {
      statusText = "Connecting...";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (myDownloadStatus == DownloadStatus.inProgress)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (myDownloadStatus == DownloadStatus.completed)
            const Icon(Icons.check_circle, color: Colors.green)
          else
            const Icon(Icons.hourglass_empty, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(child: Text(statusText, style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const _CircleIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: size * 0.45),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, String> message;
  final bool isMe;
  final BoxConstraints constraints;

  const _ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.constraints,
  });

  double get _adaptiveFontSize => constraints.maxWidth < 360 ? 0.85 : 1.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: constraints.maxHeight * 0.005,
        horizontal: constraints.maxWidth * 0.02,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * 0.75,
            minWidth: constraints.maxWidth * 0.15,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.03,
              vertical: constraints.maxHeight * 0.01,
            ),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF3B82F6) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(4),
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe)
                  Padding(
                    padding: EdgeInsets.only(bottom: constraints.maxHeight * 0.003),
                    child: Text(
                      message['sender']!,
                      style: TextStyle(
                        fontSize: 10 * _adaptiveFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  message['msg']!,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 14 * _adaptiveFontSize,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerListItem extends StatelessWidget {
  final Map<String, dynamic> player;
  final bool isMe;
  final bool isInactive;
  final DownloadStatus downloadStatus;
  final double downloadProgress;
  final BoxConstraints constraints;

  const _PlayerListItem({
    super.key,
    required this.player,
    required this.isMe,
    required this.isInactive,
    required this.downloadStatus,
    required this.downloadProgress,
    required this.constraints,
  });

  double get _adaptiveFontSize => constraints.maxWidth < 360 ? 0.85 : 1.0;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarData.get(player['avatar'] ?? 0);
    final avatarSize = constraints.maxWidth * 0.1;

    return Opacity(
      opacity: isInactive ? 0.4 : 1.0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: constraints.maxWidth * 0.04,
          vertical: constraints.maxHeight * 0.015,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isInactive
                ? Colors.grey.shade300
                : (isMe ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: isInactive ? Colors.grey : avatar['color'],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      avatar['emoji'],
                      style: TextStyle(fontSize: avatarSize * 0.5),
                    ),
                  ),
                ),
                SizedBox(width: constraints.maxWidth * 0.03),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              player['name'],
                              style: GoogleFonts.inter(
                                fontSize: 14 * _adaptiveFontSize,
                                fontWeight: FontWeight.w600,
                                color:
                                isInactive ? Colors.grey : const Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (player['isHost'] == true)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: constraints.maxWidth * 0.02,
                                vertical: constraints.maxHeight * 0.005,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFFEDD5)),
                              ),
                              child: Text(
                                "HOST",
                                style: GoogleFonts.inter(
                                  fontSize: 9 * _adaptiveFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFEA580C),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (isMe)
                        Text(
                          "You",
                          style: GoogleFonts.inter(
                            fontSize: 11 * _adaptiveFontSize,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Download progress bar
            SizedBox(height: constraints.maxHeight * 0.01),
            _buildDownloadStatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadStatusBar() {
    Color color;
    String text;
    double progress = 0.0;

    switch (downloadStatus) {
      case DownloadStatus.notStarted:
        color = Colors.grey;
        text = "Not started";
        break;
      case DownloadStatus.inProgress:
        color = Colors.blue;
        text = "Downloading... ${(downloadProgress * 100).toInt()}%";
        progress = downloadProgress;
        break;
      case DownloadStatus.completed:
        color = Colors.green;
        text = "Ready!";
        progress = 1.0;
        break;
      case DownloadStatus.failed:
        color = Colors.red;
        text = "Failed";
        break;
      case DownloadStatus.cancelled:
        color = Colors.orange;
        text = "Cancelled";
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getStatusIcon(downloadStatus),
              size: 12 * _adaptiveFontSize,
              color: color,
            ),
            SizedBox(width: constraints.maxWidth * 0.015),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 10 * _adaptiveFontSize,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (downloadStatus == DownloadStatus.inProgress) ...[
          SizedBox(height: constraints.maxHeight * 0.005),
          Container(
            height: constraints.maxHeight * 0.005,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              widthFactor: progress,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  IconData _getStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.notStarted:
        return Icons.circle_outlined;
      case DownloadStatus.inProgress:
        return Icons.download_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle;
      case DownloadStatus.failed:
        return Icons.error_outline;
      case DownloadStatus.cancelled:
        return Icons.cancel;
    }
  }
}