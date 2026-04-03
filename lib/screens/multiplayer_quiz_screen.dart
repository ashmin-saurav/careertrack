import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:typed_data/typed_data.dart';

import '../widgets/smart_text_renderer.dart';
import 'multiplayer_result_screen.dart';

// 🟢 OPTIMIZED CONSTANTS
const int _MAX_RECONNECT_ATTEMPTS = 5;
const int _TIME_SYNC_SAMPLES = 3;
const int _LAG_TOLERANCE_MS = 5000;
const int _ZOMBIE_TIMEOUT_MS = 45000;
const int _HOST_GRACE_PERIOD_MS = 2000;
const int _AUTO_NEXT_DELAY_MS = 1000;
const int _HEARTBEAT_INTERVAL_SEC = 3;
const int _ZOMBIE_CHECK_INTERVAL_SEC = 15;
const int _STATE_UPDATE_DEBOUNCE_MS = 150;
const int _LOCAL_TICKER_INTERVAL_MS = 500;
const int _MIN_CONNECTED_PLAYERS = 1;

class AvatarData {
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

  static Map<String, dynamic> get(int id) =>
      list.firstWhere((e) => e['id'] == id, orElse: () => list[0]);
}

class MultiplayerQuizScreen extends StatefulWidget {
  final bool isHost;
  final String roomCode;
  final String userName;
  final List<dynamic> initialPlayers;
  final List<dynamic> questions;
  final int secondsPerQuestion;
  final String myId;

  const MultiplayerQuizScreen({
    super.key,
    required this.isHost,
    required this.roomCode,
    required this.userName,
    required this.initialPlayers,
    required this.questions,
    this.secondsPerQuestion = 60,
    required this.myId,
  });

  @override
  State<MultiplayerQuizScreen> createState() => _MultiplayerQuizScreenState();
}

class _MultiplayerQuizScreenState extends State<MultiplayerQuizScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  MqttServerClient? _client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Language preference
  bool _isHindi = false;
  bool _isLoadingLanguage = true;

  // Time synchronization
  int _timeOffsetMs = 0;
  int _pendingOffsetMs = 0;
  int _roundEndsAtMs = 0;
  final List<int> _timeSyncOffsets = [];

  // Question tracking
  int _liveIndex = 0;
  int _viewingIndex = 0;

  // Answer tracking - FIXED: Only track final answers
  late List<int?> _myFinalAnswers; // Final answers, once set cannot be changed
  late List<bool> _isAnswerLocked; // Track if question is locked (time passed)
  int _lastSubmittedQuestionIndex = -1;

  // Player management
  final Map<String, PlayerData> _playersMap = {};
  List<PlayerData> _playersList = [];
  bool _playersDirty = false;

  // Connection state
  bool _isConnected = false;
  bool _isInitializing = true;
  bool _isExiting = false;
  bool _isLowEndDevice = false;
  int _reconnectAttempts = 0;
  bool _hasGameStarted = false;
  bool _hasShownScoreboard = false;
  bool _isTransitioning = false;
  bool _isProcessingRoundEnd = false;
  bool _isBackButtonPressed = false;

  late String _myId;

  // Timers
  Timer? _localTicker;
  Timer? _heartbeatTimer;
  Timer? _zombieTimer;
  Timer? _reconnectTimer;
  Timer? _answerDebounceTimer;
  Timer? _hostGraceTimer;
  Timer? _autoNextTimer;
  Timer? _stateUpdateDebouncer;

  // Animations
  late AnimationController _pulseController;
  final ValueNotifier<int> _timeLeftNotifier = ValueNotifier(0);

  // Caching
  final Map<int, List<Map<String, dynamic>>> _optionsCache = {};
  final Map<String, Widget> _textRendererCache = {};

  // MQTT topics
  String get _hostTopic => "room/${widget.roomCode}/host";
  String get _updateTopic => "room/${widget.roomCode}/update";

  // Store current question answers temporarily (for host)
  final Map<int, Map<String, int?>> _allQuestionAnswers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _timeLeftNotifier.value = widget.secondsPerQuestion;
    _myFinalAnswers = List.filled(widget.questions.length, null);
    _isAnswerLocked = List.filled(widget.questions.length, false);

    _initializeMyId();
    _loadLanguagePreference();
    _detectDeviceCapabilities();
    _setupAnimations();
    _initializePlayers();
    _connectToGame();
    _startTimers();
    WakelockPlus.enable();
  }

  void _initializeMyId() {
    if (widget.isHost) {
      final me = widget.initialPlayers.firstWhere(
            (p) => p['isHost'] == true,
        orElse: () => <String, dynamic>{'id': widget.myId},
      );
      _myId = me['id'] ?? widget.myId;
    } else {
      final me = widget.initialPlayers.firstWhere(
            (p) => p['name'] == widget.userName,
        orElse: () => <String, dynamic>{'id': widget.myId},
      );
      _myId = me['id'] ?? widget.myId;
    }
  }

  Future<void> _loadLanguagePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isHindi = prefs.getBool('isHindi') ?? false;

      if (mounted) {
        setState(() {
          _isHindi = isHindi;
          _isLoadingLanguage = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading language preference: $e');
      if (mounted) {
        setState(() {
          _isHindi = false;
          _isLoadingLanguage = false;
        });
      }
    }
  }

  Future<void> _toggleLanguage() async {
    try {
      final newValue = !_isHindi;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isHindi', newValue);

      setState(() {
        _isHindi = newValue;
        _textRendererCache.clear();
      });

      if (!_isLowEndDevice) {
        HapticFeedback.lightImpact();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newValue ? 'भाषा बदली गई: हिंदी' : 'Language changed: English',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling language: $e');
    }
  }

  void _detectDeviceCapabilities() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final size = MediaQuery.of(context).size;
      final platform = Theme.of(context).platform;
      final bool isLowEndPlatform = platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS;
      final bool isLargeText = MediaQuery.of(context).textScaler.scale(1) > 1.2;

      _isLowEndDevice = isLowEndPlatform ||
          size.width < 360 ||
          size.height < 700 ||
          isLargeText;

      if (_isLowEndDevice) {
        _pulseController.duration = const Duration(seconds: 3);
      }
    });
  }

  void _startTimers() {
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _HEARTBEAT_INTERVAL_SEC),
          (_) => _performHeartbeat(),
    );

    _localTicker = Timer.periodic(
      const Duration(milliseconds: _LOCAL_TICKER_INTERVAL_MS),
          (_) => _updateLocalTimer(),
    );

    if (widget.isHost) {
      _zombieTimer = Timer.periodic(
        const Duration(seconds: _ZOMBIE_CHECK_INTERVAL_SEC),
            (_) => _pruneZombies(),
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isExiting) {
          _broadcastNextQuestion();
        }
      });
    }
  }

  void _initializePlayers() {
    for (var p in widget.initialPlayers) {
      _playersMap[p['id']] = PlayerData(
        id: p['id'],
        name: p['name'],
        avatar: p['avatar'] ?? 0,
        score: p['score'] ?? 0,
        roundScore: 0,
        hasAnswered: false,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        isConnected: true,
      );
    }
    _updatePlayersList();
  }

  void _updatePlayersList() {
    if (!_playersDirty) return;

    _playersList = _playersMap.values.toList();
    _playersList.sort((a, b) {
      final scoreA = a.score + a.roundScore;
      final scoreB = b.score + b.roundScore;
      return scoreB.compareTo(scoreA);
    });
    _playersDirty = false;
  }

  // ============================================================================
  // ZOMBIE DETECTION & PLAYER MANAGEMENT
  // ============================================================================

  void _pruneZombies() {
    if (!widget.isHost || _isExiting) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;

    _playersMap.forEach((id, player) {
      if (id == _myId) return;

      final timeSinceLastSeen = now - player.lastSeen;
      final isZombie = timeSinceLastSeen > _ZOMBIE_TIMEOUT_MS;

      if (isZombie && player.isConnected) {
        debugPrint('🧟 Marking player as disconnected: ${player.name}');
        player.isConnected = false;
        player.hasAnswered = false;
        changed = true;
      }
    });

    if (changed) {
      _playersDirty = true;
      _debouncedBroadcastState();
      _checkRoundComplete();
      _checkForLastManStanding();
    }
  }

  void _checkForLastManStanding() {
    if (_isExiting || !_hasGameStarted || !mounted) return;

    final activePlayers = _playersMap.values.where((p) => p.isConnected).length;

    if (activePlayers < _MIN_CONNECTED_PLAYERS && _playersMap.isNotEmpty) {
      debugPrint('⚠️ Only $activePlayers active player(s) remaining');

      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || _isExiting) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text("Game Ending"),
            content: Text(activePlayers == 0
                ? "All other players have disconnected."
                : "Most players have disconnected."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  _endGameEarly();
                },
                child: const Text(
                  "End Game",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      });
    }
  }

  void _endGameEarly() {
    if (_isExiting) return;

    _commitRoundScores();

    if (widget.isHost) {
      _publish(_updateTopic, {
        'type': 'over',
        's': _playersList.map((p) => p.toMap()).toList()
      });
    }

    _showScoreboard(_playersList);
  }

  void _commitRoundScores() {
    _playersMap.forEach((id, player) {
      player.score += player.roundScore;
      player.roundScore = 0;
      player.hasAnswered = false;
    });
    _playersDirty = true;
  }

  // ============================================================================
  // TIME SYNCHRONIZATION
  // ============================================================================

  void _performHeartbeat() {
    if (!_isConnected || _isExiting) return;

    final int now = DateTime.now().millisecondsSinceEpoch;

    if (_playersMap.containsKey(_myId)) {
      _playersMap[_myId]!.lastSeen = now;
    }

    _sendToHost({
      'type': 'ping',
      'id': _myId,
      'name': widget.userName,
      'clientTime': now,
      'avatar': widget.initialPlayers.firstWhere(
            (p) => p['id'] == _myId,
        orElse: () => {'avatar': 0},
      )['avatar'] ?? 0,
    });

    if ((_timeSyncOffsets.isEmpty || now % 30000 < 3000) && !widget.isHost) {
      _sendToHost({'type': 'time_sync_req', 'clientTime': now});
    }
  }

  void _handleTimeSync(Map data) {
    if (widget.isHost) return;

    try {
      final int clientSendTime = data['clientTime'];
      final int serverRecvTime = data['serverTime'];
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int rtt = now - clientSendTime;

      final int newOffset = serverRecvTime - (clientSendTime + (rtt ~/ 2));

      _timeSyncOffsets.add(newOffset);
      if (_timeSyncOffsets.length > _TIME_SYNC_SAMPLES) {
        _timeSyncOffsets.removeAt(0);
      }

      final List<int> sorted = List.from(_timeSyncOffsets)..sort();
      final int medianOffset = sorted[sorted.length ~/ 2];

      if (_roundEndsAtMs == 0) {
        _timeOffsetMs = medianOffset;
      } else {
        _pendingOffsetMs = medianOffset;
      }
    } catch (e) {
      debugPrint('⚠️ Time sync error: $e');
    }
  }

  void _updateLocalTimer() {
    if (_roundEndsAtMs == 0 || _isExiting) return;

    try {
      // Calculate remaining time based on REAL CLOCK, not a simple counter
      final int nowSynced = DateTime.now().millisecondsSinceEpoch + _timeOffsetMs;
      final int remainingMs = _roundEndsAtMs - nowSynced;
      final int remainingSec = max(0, (remainingMs / 1000).ceil());

      // Update UI
      if (_timeLeftNotifier.value != remainingSec) {
        _timeLeftNotifier.value = remainingSec;
      }

      // --- HOST FAILSAFE ---
      // If I am Host, and time has run out (even if I was asleep/backgrounded),
      // I must trigger the end of the round IMMEDIATELY.
      if (widget.isHost && remainingMs <= 0 && !_isProcessingRoundEnd) {
        debugPrint("⏰ Time expired while host was likely backgrounded. Ending round now.");
        _handleRoundTimeUp();
      }

      // Lock current question when time runs out (Visual only)
      if (_viewingIndex == _liveIndex && remainingMs <= 0 && !_isAnswerLocked[_liveIndex]) {
        _lockCurrentQuestion();
      }
    } catch (e) {
      debugPrint('⚠️ Timer update error: $e');
    }
  }


  void _lockCurrentQuestion() {
    if (_isAnswerLocked[_liveIndex]) return;

    setState(() {
      _isAnswerLocked[_liveIndex] = true;
    });
    debugPrint('🔒 Locked question $_liveIndex');
  }

  void _lockPreviousQuestions() {
    // Lock all questions that have passed
    for (int i = 0; i < _liveIndex; i++) {
      if (!_isAnswerLocked[i]) {
        setState(() {
          _isAnswerLocked[i] = true;
        });
      }
    }
  }

  void _handleRoundTimeUp() {
    // If we are already waiting for grace period or processing, DO NOT run again
    if (_hostGraceTimer?.isActive ?? false) return;
    if (_isExiting || !mounted || _isProcessingRoundEnd) return;

    // Double check: Has time actually passed?
    // (Prevents edge cases where a timer fires 1ms too early)
    final int nowSynced = DateTime.now().millisecondsSinceEpoch + _timeOffsetMs;
    if (nowSynced < _roundEndsAtMs - 500) return; // Allow 500ms buffer

    debugPrint('⏰ Round time up, starting grace period');

    // Start grace period (e.g., 2 seconds to allow last-second answers to arrive)
    _hostGraceTimer = Timer(
      const Duration(milliseconds: _HOST_GRACE_PERIOD_MS),
          () {
        if (!_isExiting && mounted && !_isProcessingRoundEnd) {
          debugPrint('⏰ Grace period ended, committing scores');
          _roundEndsAtMs = 0; // Mark round as officially over
          _commitScoresAndNext();
        }
      },
    );
  }
  // ============================================================================
  // MQTT CONNECTION
  // ============================================================================

  Future<void> _connectToGame() async {
    if (_isExiting) return;

    try {
      final String clientId = "p_${_myId}_${Random().nextInt(9999)}";
      _client = MqttServerClient.withPort('test.mosquitto.org', clientId, 1883);
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.onBadCertificate = (dynamic a) => true;

      final lwtTopic = widget.isHost ? _updateTopic : _hostTopic;
      final lwtMessage = widget.isHost
          ? jsonEncode({"type": "room_closed"})
          : jsonEncode({
        "type": "leave",
        "id": _myId,
        "name": widget.userName,
      });

      _client!.connectionMessage = MqttConnectMessage()
          .withWillTopic(lwtTopic)
          .withWillMessage(lwtMessage)
          .withWillQos(MqttQos.atLeastOnce)
          .withClientIdentifier(clientId)
          .startClean();

      await _client!.connect();

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        debugPrint('✅ Connected to MQTT');

        if (mounted) {
          setState(() {
            _isConnected = true;
            _isInitializing = false;
            _reconnectAttempts = 0;
          });
        }

        _client!.subscribe(_updateTopic, MqttQos.atLeastOnce);
        if (widget.isHost) {
          _client!.subscribe(_hostTopic, MqttQos.atLeastOnce);
        }

        if (!widget.isHost) {
          _sendToHost({
            'type': 'join',
            'id': _myId,
            'name': widget.userName,
            'avatar': widget.initialPlayers.firstWhere(
                  (p) => p['id'] == _myId,
              orElse: () => {'avatar': 0},
            )['avatar'] ?? 0,
          });
        }

        _client!.updates!.listen(
              (List<MqttReceivedMessage<MqttMessage?>> c) {
            if (_isExiting) return;

            try {
              final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
              final String payload = MqttPublishPayload.bytesToStringAsString(
                recMess.payload.message,
              );

              if (payload.trim().isEmpty) {
                return;
              }

              if (!payload.trim().startsWith('{')) {
                return;
              }

              _handleMessage(c[0].topic, jsonDecode(payload));
            } catch (e) {
              debugPrint('⚠️ Message parse error: $e');
            }
          },
          onError: (error) {
            debugPrint('⚠️ MQTT stream error: $error');
          },
          cancelOnError: false,
        );

        _client!.onDisconnected = () {
          debugPrint('🔌 Disconnected from MQTT');
          if (mounted && !_isExiting) {
            setState(() => _isConnected = false);
            _scheduleReconnect();
          }
        };
      } else {
        _scheduleReconnect();
      }
    } catch (e) {
      debugPrint('❌ Connection error: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isExiting) return;

    if (_reconnectAttempts >= _MAX_RECONNECT_ATTEMPTS) {
      _showConnectionFailedDialog();
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: min(_reconnectAttempts * 2, 10));

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_isExiting && mounted) {
        debugPrint('🔄 Reconnecting... Attempt $_reconnectAttempts');
        _connectToGame();
      }
    });
  }

  void _showConnectionFailedDialog() {
    if (!mounted || _isExiting) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Connection Failed"),
        content: const Text(
          "Unable to connect to the game server. Please check your internet connection.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              _handleExit();
              Navigator.pop(context);
            },
            child: const Text("Exit", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              _reconnectAttempts = 0;
              _connectToGame();
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MESSAGE HANDLING
  // ============================================================================

  void _handleMessage(String topic, Map data) {
    if (_isExiting) return;

    try {
      if (widget.isHost && topic == _hostTopic) {
        _handleHostMessage(data);
      }

      if (topic == _updateTopic) {
        _handleBroadcastMessage(data);
      }
    } catch (e) {
      debugPrint('⚠️ Message handling error: $e');
    }
  }

  void _handleHostMessage(Map data) {
    final String? pid = data['id'];
    if (pid == null) return;

    try {
      switch (data['type']) {
        case 'time_sync_req':
          _publish(_updateTopic, {
            'type': 'time_sync_res',
            'clientTime': data['clientTime'],
            'serverTime': DateTime.now().millisecondsSinceEpoch,
          });
          break;

        case 'ping':
        case 'join':
          _refreshPlayer(pid, data['name'] ?? 'Player', data['avatar'] ?? 0);

          if (_roundEndsAtMs > 0 && data['type'] == 'join') {
            _updatePlayersList();
            _publish(_updateTopic, {
              'type': 'sync_state',
              'i': _liveIndex,
              'e': _roundEndsAtMs,
              'players': _playersList.map((p) => p.toMap()).toList(),
            });
          }
          break;

        case 'submit_answer':
        // FIX: Properly parse question index
          final dynamic qIdxDynamic = data['qIdx'];
          final int questionIndex = (qIdxDynamic is int)
              ? qIdxDynamic
              : (qIdxDynamic is String)
              ? int.tryParse(qIdxDynamic) ?? _liveIndex
              : _liveIndex;

          if (data['qHash'] == _getQuestionHash(questionIndex)) {
            final int clientTime = data['t'];
            final int serverTime = DateTime.now().millisecondsSinceEpoch;

            // Store answer for the specific question
            if (!_allQuestionAnswers.containsKey(questionIndex)) {
              _allQuestionAnswers[questionIndex] = {};
            }

            // FIX: Properly parse answer index
            final dynamic idxDynamic = data['idx'];
            final int? answerIdx = (idxDynamic is int)
                ? idxDynamic
                : (idxDynamic is String)
                ? int.tryParse(idxDynamic)
                : null;

            _allQuestionAnswers[questionIndex]![pid] = answerIdx;

            // For current live question, mark player as answered
            if (questionIndex == _liveIndex) {
              final player = _playersMap[pid];
              if (player != null && !player.hasAnswered) {
                player.hasAnswered = true;
                _playersDirty = true;
                _debouncedBroadcastState();
                _checkRoundComplete();
              }
            } else {
              // For non-live questions, score immediately
              _scoreQuestionAnswer(questionIndex, pid, answerIdx);
            }
          }
          break;

        case 'leave':
          final player = _playersMap[pid];
          if (player != null) {
            player.isConnected = false;
            player.hasAnswered = true;
            _playersDirty = true;
            _debouncedBroadcastState();
            _checkRoundComplete();
            _checkForLastManStanding();
          }
          break;

        case 'host_exit':
          _handleHostExit();
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Host message handling error: $e');
    }
  }

  void _scoreQuestionAnswer(int questionIndex, String playerId, int? answerIdx) {
    if (!widget.isHost || _isExiting) return;

    try {
      final player = _playersMap[playerId];
      if (player == null) return;

      final currentQ = widget.questions[questionIndex];
      int correctIdx = int.tryParse((currentQ['a'] ?? '0').toString()) ?? 0;
      int points = (answerIdx == correctIdx) ? 10 : 0;

      player.score += points;
      _playersDirty = true;
      _debouncedBroadcastState();

      debugPrint('💯 Scored $points for ${player.name} on question $questionIndex');
    } catch (e) {
      debugPrint('⚠️ Score question answer error: $e');
    }
  }

  void _handleHostExit() {
    if (_isExiting) return;
    _isExiting = true;

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Host has ended the game."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _handleBroadcastMessage(Map data) {
    try {
      switch (data['type']) {
        case 'time_sync_res':
          if (!widget.isHost) {
            _handleTimeSync(data);
          }
          break;

        case 'next':
        case 'sync_state':
          _hasGameStarted = true;

          if (data['type'] == 'next') {
            _isTransitioning = true;
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _isTransitioning = false;
                });
              }
            });
          }

          if (mounted) {
            setState(() {
              if (_pendingOffsetMs != 0) {
                _timeOffsetMs = _pendingOffsetMs;
                _pendingOffsetMs = 0;
              }

              _liveIndex = data['i'];
              _roundEndsAtMs = data['e'];

              if (data['type'] == 'next') {
                _viewingIndex = _liveIndex;
                // Reset hasAnswered for all players on next question
                _playersMap.forEach((id, player) {
                  player.hasAnswered = false;
                });
                _playersDirty = true;
              }

              if (data['players'] != null) {
                final List<dynamic> playersData = data['players'];
                for (var pData in playersData) {
                  final id = pData['id'].toString();
                  if (_playersMap.containsKey(id)) {
                    final player = _playersMap[id]!;
                    player.score = pData['score'] ?? 0;
                    player.roundScore = pData['roundScore'] ?? 0;
                    player.hasAnswered = pData['hasAnswered'] ?? false;
                    player.isConnected = pData['isConnected'] ?? true;
                    if (player.isConnected) {
                      player.lastSeen = DateTime.now().millisecondsSinceEpoch;
                    }
                  }
                }
                _playersDirty = true;
                _updatePlayersList();
              }
            });
          }
          break;

        case 'score_update':
        case 'state_update':
          if (widget.isHost) return;
          if (mounted) {
            setState(() {
              final List<dynamic> playersData = data['players'];
              for (var pData in playersData) {
                final id = pData['id'].toString();
                if (_playersMap.containsKey(id)) {
                  final player = _playersMap[id]!;
                  if (pData['score'] != null) player.score = pData['score'];
                  if (pData['roundScore'] != null) {
                    player.roundScore = pData['roundScore'];
                  }
                  if (pData['hasAnswered'] != null) {
                    player.hasAnswered = pData['hasAnswered'];
                  }
                  if (pData['isConnected'] != null) {
                    player.isConnected = pData['isConnected'];
                  }
                  if (player.isConnected) {
                    player.lastSeen = DateTime.now().millisecondsSinceEpoch;
                  }
                }
              }
              _playersDirty = true;
              _updatePlayersList();
            });
          }
          break;

        case 'over':
          if (!_hasShownScoreboard) {
            final scores =
            (data['s'] as List).map((p) => PlayerData.fromMap(p)).toList();
            _showScoreboard(scores);
          }
          break;

        case 'room_closed':
          if (!widget.isHost && !_isExiting) {
            _isExiting = true;
            _client?.disconnect();

            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Host ended the game."),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Broadcast message handling error: $e');
    }
  }

  // ============================================================================
  // ANSWER PROCESSING - COMPLETELY FIXED LOGIC
  // ============================================================================

  void _submitAnswer(int index) {
    if (_answerDebounceTimer?.isActive ?? false) return;
    if (_isExiting) return;

    _answerDebounceTimer = Timer(const Duration(milliseconds: 300), () {});

    final bool isCurrentQuestion = _viewingIndex == _liveIndex;
    final bool isPastQuestion = _viewingIndex < _liveIndex;
    final bool isFutureQuestion = _viewingIndex > _liveIndex;
    final bool hasAnswered = _myFinalAnswers[_viewingIndex] != null;

    // Check if the timer is strictly still running for the live question
    final bool isRoundActive = _roundEndsAtMs > 0 &&
        (DateTime.now().millisecondsSinceEpoch + _timeOffsetMs) < _roundEndsAtMs;

    // ---------------------------------------------------------
    // SCENARIO 1: PAST QUESTION
    // Logic: If already answered (locked), block. If NOT answered, allow once.
    // ---------------------------------------------------------
    if (isPastQuestion) {
      if (hasAnswered) {
        // You already answered this (either during live or just now). It is locked.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Answer locked! Marks already allocated."),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      // You missed this question during the live round.
      // We allow you to answer it now, but it locks immediately after this.
      setState(() {
        _myFinalAnswers[_viewingIndex] = index;
      });

      if (!_isLowEndDevice) {
        HapticFeedback.lightImpact();
      }

      final options = _getOptions(_viewingIndex);

      _sendToHost({
        'type': 'submit_answer',
        'id': _myId,
        'qIdx': _viewingIndex,
        'idx': options[index]['originalIndex'],
        'qHash': _getQuestionHash(_viewingIndex),
        't': DateTime.now().millisecondsSinceEpoch + _timeOffsetMs,
      });

      debugPrint('✅ Late submission for past question $_viewingIndex: $index');
      return;
    }

    // ---------------------------------------------------------
    // SCENARIO 2: FUTURE QUESTION
    // ---------------------------------------------------------
    if (isFutureQuestion) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Wait for this question to go live!"),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    // ---------------------------------------------------------
    // SCENARIO 3: CURRENT LIVE QUESTION
    // Logic: Allow changes as long as time is ticking.
    // ---------------------------------------------------------
    if (isCurrentQuestion) {
      // If time has run out, treat it as locked
      if (!isRoundActive || _isAnswerLocked[_liveIndex]) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Time's up! Answer is locked."),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      // Allow answer/update
      setState(() {
        _myFinalAnswers[_liveIndex] = index;
      });

      if (!_isLowEndDevice) {
        HapticFeedback.lightImpact();
      }

      final options = _getOptions(_liveIndex);

      _sendToHost({
        'type': 'submit_answer',
        'id': _myId,
        'qIdx': _liveIndex,
        'idx': options[index]['originalIndex'],
        'qHash': _getQuestionHash(_liveIndex),
        't': DateTime.now().millisecondsSinceEpoch + _timeOffsetMs,
      });

      debugPrint('✅ Answer updated for live question $_liveIndex: $index');
    }
  }


  void _checkRoundComplete() {
    if (_playersMap.isEmpty || !widget.isHost || _isExiting || _isProcessingRoundEnd) return;

    try {
      final connectedPlayers = _playersMap.values.where((p) => p.isConnected);
      if (connectedPlayers.isEmpty) return;

      final bool allAnswered = connectedPlayers.every((p) => p.hasAnswered);
      final int answeredCount = connectedPlayers.where((p) => p.hasAnswered).length;
      final int totalConnected = connectedPlayers.length;

      debugPrint('📊 Round status: $answeredCount/$totalConnected answered, allAnswered: $allAnswered');

      if (allAnswered) {
        debugPrint('✅ All players answered! Auto-advancing...');
        _autoNextTimer?.cancel();
        _autoNextTimer = Timer(
          const Duration(milliseconds: _AUTO_NEXT_DELAY_MS),
              () {
            if (!_isExiting && mounted && !_isProcessingRoundEnd) {
              _roundEndsAtMs = 0;
              _hostGraceTimer?.cancel();
              _commitScoresAndNext();
            }
          },
        );
      }
    } catch (e) {
      debugPrint('⚠️ Round complete check error: $e');
    }
  }

  void _commitScoresAndNext() {
    if (!widget.isHost || _isExiting || _isProcessingRoundEnd) return;

    try {
      _isProcessingRoundEnd = true;
      debugPrint('📝 Committing scores for question $_liveIndex');

      // Score the current live question
      final currentQ = widget.questions[_liveIndex];
      int correctIdx = int.tryParse((currentQ['a'] ?? '0').toString()) ?? 0;

      // Check if we have answers for this question
      if (_allQuestionAnswers.containsKey(_liveIndex)) {
        final questionAnswers = _allQuestionAnswers[_liveIndex]!;
        questionAnswers.forEach((pid, answerIdx) {
          final player = _playersMap[pid];
          if (player != null) {
            int points = (answerIdx == correctIdx) ? 10 : 0;
            player.roundScore = points;
            debugPrint('💯 ${player.name} scored $points points for question $_liveIndex');
          }
        });
      }

      // Commit round scores to total
      _commitRoundScores();
      _debouncedBroadcastState();

      if (_liveIndex + 1 >= widget.questions.length) {
        debugPrint('🏁 Game over!');
        if (mounted) {
          _publish(_updateTopic, {
            'type': 'over',
            's': _playersList.map((p) => p.toMap()).toList()
          });
        }
      } else {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!_isExiting && mounted) {
            _liveIndex++;
            _isProcessingRoundEnd = false;
            _broadcastNextQuestion();
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ Commit scores error: $e');
      _isProcessingRoundEnd = false;
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  void _refreshPlayer(String pid, String name, int avatar) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      if (_playersMap.containsKey(pid)) {
        final player = _playersMap[pid]!;
        player.lastSeen = now;
        player.isConnected = true;
        player.name = name;
        debugPrint('🔄 Refreshed player: $name');
      } else {
        _playersMap[pid] = PlayerData(
          id: pid,
          name: name,
          avatar: avatar,
          score: 0,
          roundScore: 0,
          hasAnswered: false,
          lastSeen: now,
          isConnected: true,
        );
        debugPrint('➕ Added new player: $name');
      }

      _playersDirty = true;
      if (mounted) {
        setState(() {
          _updatePlayersList();
        });
      }

      if (widget.isHost) {
        _debouncedBroadcastState();
      }
    } catch (e) {
      debugPrint('⚠️ Refresh player error: $e');
    }
  }

  String _getQuestionHash(int index) {
    if (index >= widget.questions.length) return "";

    try {
      final q = widget.questions[index];
      final options = q['o'] ?? q['options'] ?? [];
      return "${q['q']}_${options.join('|')}";
    } catch (e) {
      debugPrint('⚠️ Question hash error: $e');
      return "";
    }
  }

  List<Map<String, dynamic>> _getOptions(int qIndex) {
    return _optionsCache.putIfAbsent(qIndex, () {
      try {
        final q = widget.questions[qIndex];
        final List raw = q['o'] ?? q['options'] ?? [];

        List<Map<String, dynamic>> mapped = [];
        for (int i = 0; i < raw.length; i++) {
          mapped.add({'text': raw[i], 'originalIndex': i});
        }

        mapped.shuffle(Random(_myId.hashCode + qIndex));

        return mapped;
      } catch (e) {
        debugPrint('⚠️ Get options error: $e');
        return [];
      }
    });
  }

  String _getQuestionText(int qIndex) {
    if (qIndex >= widget.questions.length) return "Loading...";

    try {
      final q = widget.questions[qIndex];

      if (_isHindi && q['hq'] != null && q['hq'].toString().isNotEmpty) {
        return q['hq'];
      }

      return q['q'] ?? "Question not available";
    } catch (e) {
      debugPrint('⚠️ Get question text error: $e');
      return "Error loading question";
    }
  }

  String _getOptionText(int qIndex, int optionIndex) {
    if (qIndex >= widget.questions.length) return "";

    try {
      final q = widget.questions[qIndex];

      if (_isHindi && q['ho'] != null) {
        final hindiOptions = q['ho'] as List;
        if (optionIndex < hindiOptions.length) {
          return hindiOptions[optionIndex].toString();
        }
      }

      final englishOptions = q['o'] ?? q['options'] ?? [];
      if (optionIndex < englishOptions.length) {
        return englishOptions[optionIndex].toString();
      }

      return "";
    } catch (e) {
      debugPrint('⚠️ Get option text error: $e');
      return "";
    }
  }

  Widget _getCachedText(String text, Color color, double scale) {
    try {
      final key = '${text.hashCode}_${color.value}_$scale';
      return _textRendererCache.putIfAbsent(key, () {
        return SmartTextRenderer(
          text: text,
          textColor: color,
          devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
        );
      });
    } catch (e) {
      debugPrint('⚠️ Cached text error: $e');
      return Text(text, style: TextStyle(color: color));
    }
  }

  void _broadcastNextQuestion() {
    if (!widget.isHost || _isExiting) return;

    try {
      final int now = DateTime.now().millisecondsSinceEpoch;
      _roundEndsAtMs = now + (widget.secondsPerQuestion * 1000);

      // Lock previous questions when moving to next
      _lockPreviousQuestions();

      // Reset hasAnswered for all players on next question
      _playersMap.forEach((id, player) {
        player.hasAnswered = false;
      });
      _playersDirty = true;
      _updatePlayersList();

      debugPrint('📢 Broadcasting next question: $_liveIndex');

      _publish(_updateTopic, {
        'type': 'next',
        'i': _liveIndex,
        'e': _roundEndsAtMs,
        'players': _playersList.map((p) => p.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('⚠️ Broadcast next question error: $e');
    }
  }

  void _broadcastScoreUpdate() {
    if (!widget.isHost || _isExiting) return;

    try {
      _updatePlayersList();
      _publish(_updateTopic, {
        'type': 'score_update',
        'players': _playersList.map((p) => p.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('⚠️ Broadcast score update error: $e');
    }
  }

  void _broadcastState() {
    if (!widget.isHost || _isExiting) return;

    try {
      _updatePlayersList();
      _publish(_updateTopic, {
        'type': 'state_update',
        'players': _playersList.map((p) => p.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('⚠️ Broadcast state error: $e');
    }
  }

  void _debouncedBroadcastState() {
    if (!widget.isHost || _isExiting) return;

    _stateUpdateDebouncer?.cancel();
    _stateUpdateDebouncer = Timer(
      const Duration(milliseconds: _STATE_UPDATE_DEBOUNCE_MS),
          () {
        if (!_isExiting) {
          _broadcastState();
        }
      },
    );
  }

  void _sendToHost(Map data) => _publish(_hostTopic, data);

  void _publish(String topic, Map data) {
    if (!_isConnected || _client == null) return;

    try {
      final String jsonString = jsonEncode(data);

      final builder = MqttClientPayloadBuilder();
      final buffer = Uint8Buffer();
      buffer.addAll(utf8.encode(jsonString));
      builder.addBuffer(buffer);

      _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    } catch (e) {
      debugPrint('⚠️ Publish error: $e');
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  // ============================================================================
  // BACK BUTTON HANDLING & EXIT PROTECTION
  // ============================================================================

  Future<bool> _onWillPop() async {
    if (_isExiting || _isBackButtonPressed) return true;

    _isBackButtonPressed = true;

    if (widget.isHost) {
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text("End Game?"),
          content: const Text(
            "Are you sure you want to end the game for all players?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c, false);
                _isBackButtonPressed = false;
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text(
                "End Game",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        // Notify all players that host is ending the game
        _publish(_updateTopic, {'type': 'room_closed'});
        await Future.delayed(const Duration(milliseconds: 300));
        _isExiting = true;
        _client?.disconnect();
        return true;
      }
    } else {
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text("Leave Game?"),
          content: const Text(
            "Are you sure you want to leave the game?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(c, false);
                _isBackButtonPressed = false;
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text(
                "Leave",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (shouldExit == true) {
        _sendToHost({'type': 'leave', 'id': _myId});
        await Future.delayed(const Duration(milliseconds: 200));
        _isExiting = true;
        _client?.disconnect();
        return true;
      }
    }

    _isBackButtonPressed = false;
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Pause timers to save resources
      _heartbeatTimer?.cancel();
      _localTicker?.cancel();
      if (widget.isHost) _zombieTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint("📱 App Resumed - Syncing State...");

      // 1. Reconnect Network if needed
      if (!_isConnected && !_isExiting) {
        _reconnectAttempts = 0;
        _connectToGame();
        // _connectToGame automatically sends 'join' on success
      }
      // 2. IF WE ARE ALREADY CONNECTED (Socket didn't die):
      // We might have missed 'next' messages while backgrounded.
      // Force a 'join' to trigger a full State Sync (Question Index + Time) from Host.
      else if (!widget.isHost && _isConnected) {

        // Find my avatar safely
        int myAvatarId = 0;
        try {
          // Try finding in current players map first (most up to date)
          if (_playersMap.containsKey(_myId)) {
            myAvatarId = _playersMap[_myId]!.avatar;
          } else {
            // Fallback to initial players
            final me = widget.initialPlayers.firstWhere(
                    (p) => p['id'] == _myId,
                orElse: () => {'avatar': 0}
            );
            myAvatarId = me['avatar'] ?? 0;
          }
        } catch (e) {
          debugPrint("⚠️ Avatar lookup error: $e");
        }

        _sendToHost({
          'type': 'join',
          'id': _myId,
          'name': widget.userName,
          'avatar': myAvatarId,
        });
      }

      // 3. Restart Timers
      _localTicker?.cancel();
      _localTicker = Timer.periodic(
        const Duration(milliseconds: _LOCAL_TICKER_INTERVAL_MS),
            (_) => _updateLocalTimer(),
      );

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: _HEARTBEAT_INTERVAL_SEC),
            (_) => _performHeartbeat(),
      );

      if (widget.isHost) {
        _zombieTimer?.cancel();
        _zombieTimer = Timer.periodic(
          const Duration(seconds: _ZOMBIE_CHECK_INTERVAL_SEC),
              (_) => _pruneZombies(),
        );
      }

      // 4. FORCE IMMEDIATE UPDATE (Fixes frozen UI instantly)
      _updateLocalTimer();
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _isExiting = true;
    WidgetsBinding.instance.removeObserver(this);

    _localTicker?.cancel();
    _heartbeatTimer?.cancel();
    _hostGraceTimer?.cancel();
    _reconnectTimer?.cancel();
    _answerDebounceTimer?.cancel();
    _autoNextTimer?.cancel();
    _zombieTimer?.cancel();
    _stateUpdateDebouncer?.cancel();

    _pulseController.dispose();
    _timeLeftNotifier.dispose();

    _textRendererCache.clear();
    _optionsCache.clear();

    _client?.disconnect();

    super.dispose();
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    await _onWillPop();
  }

  void _showScoreboard(List<PlayerData> scores) {
    if (!mounted || _hasShownScoreboard) return;
    _hasShownScoreboard = true;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MultiplayerResultScreen(
              scores: scores.map((p) => p.toMap()).toList(),
              totalQuestions: widget.questions.length,
              roomCode: widget.roomCode,
              userName: widget.userName,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ============================================================================
  // UI BUILD METHODS - RESPONSIVE & FIXED
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLanguage) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    final Size size = MediaQuery.of(context).size;
    final bool isSmallScreen = size.width < 400;
    final bool isVerySmallScreen = size.width < 350;

    // Lock previous questions when timer updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lockPreviousQuestions();
    });

    return WillPopScope(
      onWillPop: _onWillPop,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF0F172A),
          endDrawer: _buildDrawer(),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isInitializing
                ? _buildLoadingScreen()
                : Stack(
              children: [
                // Background gradient
                Positioned.fill( // <--- Added Positioned.fill here for safety
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF1E293B),
                          Color(0xFF334155),
                        ],
                      ),
                    ),
                  ),
                ),

                // Main content
                Positioned.fill( // <--- CRITICAL FIX: Wrap LayoutBuilder in Positioned.fill
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SafeArea(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min, // Ensure column takes minimum space
                              children: [
                                // Header
                                _buildModernHeader(isSmallScreen, isVerySmallScreen),

                                // Progress bar
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 12 : 16),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: widget.questions.isEmpty
                                          ? 0
                                          : (_liveIndex + 1) / widget.questions.length,
                                      backgroundColor: Colors.white.withOpacity(0.1),
                                      valueColor: const AlwaysStoppedAnimation(
                                        Color(0xFF6366F1),
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                                SizedBox(height: isVerySmallScreen ? 6 : 8),

                                // Answered players count
                                if (_isConnected && _hasGameStarted)
                                  Container(
                                    margin: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 12 : 16),
                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.1),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.people,
                                              color: Colors.white.withOpacity(0.7),
                                              size: 16,
                                            ),
                                            SizedBox(width: isVerySmallScreen ? 4 : 6),
                                            Text(
                                              "Players",
                                              style: GoogleFonts.inter(
                                                color: Colors.white.withOpacity(0.7),
                                                fontSize: isVerySmallScreen ? 11 : 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          "${_playersList.where((p) => p.hasAnswered && p.isConnected).length}/${_playersList.where((p) => p.isConnected).length} answered",
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: isVerySmallScreen ? 11 : 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                SizedBox(height: isVerySmallScreen ? 8 : 12),

                                // Players grid
                                SizedBox(
                                  height: isVerySmallScreen ? 90 : 100,
                                  child: _buildModernPlayerGrid(isSmallScreen, isVerySmallScreen),
                                ),
                                SizedBox(height: isVerySmallScreen ? 8 : 12),

                                // Question content - Use Flexible instead of Expanded inside SingleChildScrollView
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 8 : 12),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    child: _buildQuestionContent(isSmallScreen, isVerySmallScreen),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Live indicator (remains Positioned)
                if (_viewingIndex != _liveIndex &&
                    _liveIndex < widget.questions.length &&
                    !_isTransitioning)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _viewingIndex = _liveIndex);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isVerySmallScreen ? 12 : 16,
                          vertical: isVerySmallScreen ? 8 : 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.4),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: isVerySmallScreen ? 4 : 8),
                            Text(
                              "GO LIVE",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: isVerySmallScreen ? 11 : 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Reconnecting overlay
                if (!_isConnected && !_isInitializing && !_isExiting)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.8),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            SizedBox(height: isVerySmallScreen ? 12 : 16),
                            Text(
                              "Reconnecting...",
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: isVerySmallScreen ? 14 : 16,
                              ),
                            ),
                            SizedBox(height: isVerySmallScreen ? 6 : 8),
                            Text(
                              "Attempt $_reconnectAttempts/$_MAX_RECONNECT_ATTEMPTS",
                              style: GoogleFonts.inter(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: isVerySmallScreen ? 11 : 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionContent(bool isSmallScreen, bool isVerySmallScreen) {
    return Column(
      key: ValueKey(_viewingIndex),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ... (Timer and Question Number Header remains the same) ...
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isVerySmallScreen ? 12 : 16,
            vertical: isVerySmallScreen ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: isVerySmallScreen ? 32 : 36,
                    height: isVerySmallScreen ? 32 : 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "${_viewingIndex + 1}",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: isVerySmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isVerySmallScreen ? 8 : 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Question ${_viewingIndex + 1}",
                        style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: isVerySmallScreen ? 10 : 12,
                        ),
                      ),
                      Text(
                        _viewingIndex == _liveIndex ? "LIVE NOW" : "REVIEW",
                        style: GoogleFonts.inter(
                          color: _viewingIndex == _liveIndex
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                          fontSize: isVerySmallScreen ? 9 : 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Timer
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isVerySmallScreen ? 12 : 16,
                  vertical: isVerySmallScreen ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _timeLeftNotifier,
                  builder: (_, val, __) {
                    return Row(
                      children: [
                        Icon(
                          Icons.timer,
                          color: val <= 10
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF60A5FA),
                          size: isVerySmallScreen ? 14 : 16,
                        ),
                        SizedBox(width: isVerySmallScreen ? 4 : 6),
                        Text(
                          "$val",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: isVerySmallScreen ? 16 : 18,
                          ),
                        ),
                        Text(
                          "s",
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: isVerySmallScreen ? 11 : 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isVerySmallScreen ? 12 : 16),

        // Question text
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isVerySmallScreen ? 16 : 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Language toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _toggleLanguage,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmallScreen ? 10 : 12,
                        vertical: isVerySmallScreen ? 5 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.translate,
                            color: Colors.white,
                            size: isVerySmallScreen ? 12 : 14,
                          ),
                          SizedBox(width: isVerySmallScreen ? 4 : 6),
                          Text(
                            _isHindi ? 'हिंदी' : 'English',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: isVerySmallScreen ? 11 : 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isVerySmallScreen ? 12 : 16),

              // Question text - USING SmartTextRenderer
              // 🔥 FIX 1: Wrap Question Text in IgnorePointer
              IgnorePointer(
                child: _getCachedText(
                  _getQuestionText(_viewingIndex),
                  Colors.white,
                  isVerySmallScreen ? 0.8 : (isSmallScreen ? 0.9 : 1.0),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isVerySmallScreen ? 16 : 24),

        // Options grid
        _buildModernOptionsGrid(isSmallScreen, isVerySmallScreen),
        SizedBox(height: isVerySmallScreen ? 20 : 40),
      ],
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              "Connecting to game...",
              style: GoogleFonts.inter(
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernPlayerGrid(bool isSmallScreen, bool isVerySmallScreen) {
    _updatePlayersList();
    final double avatarSize = isVerySmallScreen ? 40 : (isSmallScreen ? 45 : 50);
    final int maxPlayersToShow = isVerySmallScreen ? 3 : (isSmallScreen ? 4 : 5);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 8 : 12),
      itemCount: min(_playersList.length, maxPlayersToShow),
      itemBuilder: (context, index) {
        final player = _playersList[index];
        final avatar = AvatarData.get(player.avatar);
        final totalScore = player.score + player.roundScore;

        return Container(
          width: avatarSize + (isVerySmallScreen ? 20 : 25),
          margin: EdgeInsets.only(right: isVerySmallScreen ? 4 : 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatar['color'],
                      boxShadow: [
                        BoxShadow(
                          color: avatar['color'].withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        avatar['emoji'],
                        style: TextStyle(fontSize: avatarSize * 0.4),
                      ),
                    ),
                  ),

                  // Connection indicator
                  if (!player.isConnected)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: avatarSize * 0.3,
                        height: avatarSize * 0.3,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFEF4444),
                        ),
                        child: Icon(
                          Icons.wifi_off,
                          size: avatarSize * 0.15,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // Answered indicator
                  if (player.hasAnswered && player.isConnected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: avatarSize * 0.35,
                        height: avatarSize * 0.35,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10B981),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Icon(
                          Icons.check,
                          size: avatarSize * 0.18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: isVerySmallScreen ? 4 : 6),

              // Player name
              Text(
                player.name.length > 6
                    ? "${player.name.substring(0, 5)}.."
                    : player.name,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: isVerySmallScreen ? 9 : 10,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),

              // Score
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isVerySmallScreen ? 6 : 8,
                  vertical: isVerySmallScreen ? 1 : 2,
                ),
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$totalScore",
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: isVerySmallScreen ? 10 : 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              // Round score indicator
              if (player.roundScore > 0)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: EdgeInsets.symmetric(
                    horizontal: isVerySmallScreen ? 4 : 6,
                    vertical: isVerySmallScreen ? 0 : 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "+${player.roundScore}",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isVerySmallScreen ? 7 : 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernOptionsGrid(bool isSmallScreen, bool isVerySmallScreen) {
    final options = _getOptions(_viewingIndex);
    final int? selectedIndex = _myFinalAnswers[_viewingIndex];
    final bool isCurrentQuestion = _viewingIndex == _liveIndex;
    final bool isPastQuestion = _viewingIndex < _liveIndex;

    final bool isRoundActive = _roundEndsAtMs > 0 &&
        (DateTime.now().millisecondsSinceEpoch + _timeOffsetMs) < _roundEndsAtMs;

    final bool hasAnswered = selectedIndex != null;

    return Column(
      children: [
        ...options.asMap().entries.map((entry) {
          final int index = entry.key;
          final bool isSelected = selectedIndex == index;

          Color borderColor = Colors.transparent;
          Color bgColor = Colors.white.withOpacity(0.05);
          Color textColor = Colors.white.withOpacity(0.9);
          List<BoxShadow> shadows = [];

          // -------------------------------------------------------------
          // 1. DISABLE LOGIC
          // -------------------------------------------------------------
          bool isDisabled = false;

          if (isCurrentQuestion) {
            isDisabled = !isRoundActive;
          } else if (isPastQuestion) {
            isDisabled = hasAnswered;
          } else {
            isDisabled = true;
          }

          // -------------------------------------------------------------
          // 2. STYLE LOGIC
          // -------------------------------------------------------------
          if (isSelected) {
            bool showAsActive = isCurrentQuestion && isRoundActive;

            if (showAsActive) {
              borderColor = const Color(0xFF3B82F6);
              bgColor = const Color(0xFF3B82F6).withOpacity(0.1);
              textColor = const Color(0xFF3B82F6);
            } else {
              borderColor = const Color(0xFFF59E0B);
              bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
              textColor = const Color(0xFFF59E0B);
            }

            shadows = [
              BoxShadow(
                color: borderColor.withOpacity(0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ];
          } else if (isDisabled) {
            bgColor = Colors.white.withOpacity(0.02);
            textColor = Colors.white.withOpacity(0.4);
          }

          final originalIndex = entry.value['originalIndex'];
          final optionText = _getOptionText(_viewingIndex, originalIndex);

          return Padding(
            padding: EdgeInsets.only(bottom: isVerySmallScreen ? 8 : 10),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Only allow tap if NOT disabled
              onTap: isDisabled ? null : () => _submitAnswer(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  vertical: isVerySmallScreen ? 14 : 16,
                  horizontal: isVerySmallScreen ? 12 : 16,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(isVerySmallScreen ? 14 : 16),
                  border: Border.all(
                    color: borderColor,
                    width: isSelected ? 2.0 : 1.0,
                  ),
                  boxShadow: shadows,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isVerySmallScreen ? 4 : 8),
                        // 🔥 FIX 2: Wrap Option Text in IgnorePointer
                        // This fixes the "click on letters" issue and disables copying
                        child: IgnorePointer(
                          child: _getCachedText(
                            optionText,
                            textColor,
                            isVerySmallScreen ? 0.8 : (isSmallScreen ? 0.9 : 1.0),
                          ),
                        ),
                      ),
                    ),

                    // LOCK ICON
                    if (isSelected && (isPastQuestion || (isCurrentQuestion && !isRoundActive)))
                      Positioned(
                        top: isVerySmallScreen ? 6 : 8,
                        right: isVerySmallScreen ? 6 : 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF59E0B),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.lock,
                            color: const Color(0xFFF59E0B),
                            size: isVerySmallScreen ? 12 : 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }


  Widget _buildModernHeader(bool isSmallScreen, bool isVerySmallScreen) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isVerySmallScreen ? 8 : 12,
        isVerySmallScreen ? 6 : 8,
        isVerySmallScreen ? 8 : 12,
        isVerySmallScreen ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left side - Room info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmallScreen ? 8 : 10,
                        vertical: isVerySmallScreen ? 4 : 5,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.meeting_room,
                            color: Colors.white,
                            size: isVerySmallScreen ? 10 : 12,
                          ),
                          SizedBox(width: isVerySmallScreen ? 3 : 4),
                          Text(
                            widget.roomCode,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: isVerySmallScreen ? 11 : 12,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isVerySmallScreen ? 4 : 6),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isVerySmallScreen ? 6 : 8,
                        vertical: isVerySmallScreen ? 3 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isHost
                            ? const Color(0xFF10B981).withOpacity(0.2)
                            : const Color(0xFF3B82F6).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.isHost
                              ? const Color(0xFF10B981)
                              : const Color(0xFF3B82F6),
                        ),
                      ),
                      child: Text(
                        widget.isHost ? "HOST" : "PLAYER",
                        style: GoogleFonts.inter(
                          fontSize: isVerySmallScreen ? 8 : 9,
                          fontWeight: FontWeight.w800,
                          color: widget.isHost
                              ? const Color(0xFF10B981)
                              : const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_hasGameStarted)
                  Padding(
                    padding: EdgeInsets.only(top: 4, left: isVerySmallScreen ? 2 : 4),
                    child: Text(
                      "Q${min(_liveIndex + 1, widget.questions.length)}/${widget.questions.length}",
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: isVerySmallScreen ? 9 : 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Right side - Menu button
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
            child: Container(
              width: isVerySmallScreen ? 36 : 40,
              height: isVerySmallScreen ? 36 : 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Center(
                child: Icon(
                  Icons.grid_view_rounded,
                  color: Colors.white,
                  size: isVerySmallScreen ? 16 : 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final Size size = MediaQuery.of(context).size;
    final bool isVerySmallScreen = size.width < 350;
    final bool isSmallScreen = size.width < 400;
    final int totalQuestionsShown = min(_liveIndex + 1, widget.questions.length);
    final int crossAxisCount = isVerySmallScreen ? 3 : (isSmallScreen ? 4 : 5);
    final double spacing = isVerySmallScreen ? 6 : (isSmallScreen ? 8 : 10);

    return Drawer(
      width: size.width * (isVerySmallScreen ? 0.75 : 0.8),
      backgroundColor: const Color(0xFF1E293B),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(isVerySmallScreen ? 12 : 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                  ],
                ),
              ),
              child: Column(
                children: [
                  SizedBox(height: isVerySmallScreen ? 12 : 16),
                  Text(
                    "Questions",
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isVerySmallScreen ? 18 : 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: isVerySmallScreen ? 4 : 8),
                  Text(
                    "Questions ${totalQuestionsShown}/${widget.questions.length}",
                    style: GoogleFonts.inter(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: isVerySmallScreen ? 11 : 12,
                    ),
                  ),
                ],
              ),
            ),

            // Question grid - Only show questions that have come
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isVerySmallScreen ? 8 : 12),
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                  ),
                  itemCount: totalQuestionsShown,
                  itemBuilder: (context, index) {
                    final bool isAnswered = _myFinalAnswers[index] != null;
                    final bool isCurrent = index == _liveIndex;
                    final bool isViewing = index == _viewingIndex;

                    Color bgColor;
                    Color textColor;
                    Widget? icon;

                    if (isViewing) {
                      bgColor = const Color(0xFF6366F1);
                      textColor = Colors.white;
                    } else if (isAnswered) {
                      bgColor = const Color(0xFF10B981);
                      textColor = Colors.white;
                      icon = Icon(
                        Icons.check,
                        size: isVerySmallScreen ? 8 : 10,
                        color: Colors.white,
                      );
                    } else if (isCurrent) {
                      bgColor = const Color(0xFFEF4444);
                      textColor = Colors.white;
                    } else {
                      bgColor = Colors.white.withOpacity(0.1);
                      textColor = Colors.white.withOpacity(0.7);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _viewingIndex = index;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(isVerySmallScreen ? 6 : 8),
                          boxShadow: isViewing
                              ? [
                            BoxShadow(
                              color: bgColor.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                              : [],
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "${index + 1}",
                                    style: GoogleFonts.inter(
                                      color: textColor,
                                      fontSize: isVerySmallScreen ? 12 : 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (icon != null) ...[
                                    SizedBox(height: isVerySmallScreen ? 2 : 4),
                                    icon,
                                  ],
                                ],
                              ),
                            ),

                            // Live indicator
                            if (isCurrent && !isViewing)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: isVerySmallScreen ? 4 : 5,
                                  height: isVerySmallScreen ? 4 : 5,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Exit button
            Padding(
              padding: EdgeInsets.all(isVerySmallScreen ? 8 : 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleExit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    foregroundColor: const Color(0xFFEF4444),
                    padding: EdgeInsets.symmetric(vertical: isVerySmallScreen ? 10 : 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isVerySmallScreen ? 8 : 10),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                  icon: Icon(Icons.exit_to_app, size: isVerySmallScreen ? 14 : 16),
                  label: Text(
                    "Exit Game",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isVerySmallScreen ? 13 : 14,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: isVerySmallScreen ? 8 : 12),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DATA CLASSES FOR TYPE SAFETY
// ============================================================================

class PlayerData {
  final String id;
  String name;
  int avatar;
  int score;
  int roundScore;
  bool hasAnswered;
  int lastSeen;
  bool isConnected;

  PlayerData({
    required this.id,
    required this.name,
    required this.avatar,
    required this.score,
    required this.roundScore,
    required this.hasAnswered,
    required this.lastSeen,
    required this.isConnected,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
      'score': score,
      'roundScore': roundScore,
      'hasAnswered': hasAnswered,
      'lastSeen': lastSeen,
      'isConnected': isConnected,
    };
  }

  static PlayerData fromMap(Map<String, dynamic> map) {
    return PlayerData(
      id: map['id'].toString(),
      name: map['name'] ?? 'Player',
      avatar: map['avatar'] ?? 0,
      score: map['score'] ?? 0,
      roundScore: map['roundScore'] ?? 0,
      hasAnswered: map['hasAnswered'] ?? false,
      lastSeen: map['lastSeen'] ?? DateTime.now().millisecondsSinceEpoch,
      isConnected: map['isConnected'] ?? true,
    );
  }
}