import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/game_keyboard_controller.dart';
import '../game/hud/virtual_joystick.dart';
import '../game/pvp_arena_game.dart';
import '../models/pvp_match.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firebase_pvp_service.dart';
import '../services/friend_party_service.dart';
import '../services/player_storage.dart';

class PvpArenaScreen extends StatefulWidget {
  final PvpGameMode initialMode;

  const PvpArenaScreen({super.key, this.initialMode = PvpGameMode.solo1v1});

  @override
  State<PvpArenaScreen> createState() => _PvpArenaScreenState();
}

class _PvpArenaScreenState extends State<PvpArenaScreen>
    with TickerProviderStateMixin {
  late PvpGameMode _selectedMode;
  bool _isMatchmaking = true;
  double _elapsedSeconds = 0.0;
  Timer? _matchmakingTimer;

  late AnimationController _radarController;
  PvpOpponentInfo? _opponent;
  PvpArenaGame? _arenaGame;
  bool _showQuickChatMenu = false;
  FirebasePvpService? _onlineService;
  String? _roomId;
  StreamSubscription<Map<String, dynamic>>? _roomSubscription;
  StreamSubscription? _actionSubscription;
  Timer? _stateSyncTimer;
  Timer? _readyTimeoutTimer;
  String? _matchmakingStatus;
  int _searchAttempt = 0;
  int _syncTxCount = 0;
  int _syncRxCount = 0;
  bool _isStateWritePending = false;

  GameKeyboardController? _keyboardController;
  final FocusNode _focusNode = FocusNode(debugLabel: 'pvp_focus');
  bool _showTouchControls = true;
  bool _isRebuildScheduled = false;

  void _safeSetState([VoidCallback? fn]) {
    if (!mounted) return;
    fn?.call();
    if (_isRebuildScheduled) return;

    final isBuilding =
        WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    final isPersistent =
        WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;

    if (isBuilding || isPersistent) {
      _isRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _startMatchmakingCountdown();
  }

  void _selectMatchmakingMode(PvpGameMode mode) {
    if (_selectedMode == mode) return;
    _prepareNextSearch();
    if (_onlineService != null) {
      unawaited(_onlineService!.leaveQueue());
    }
    _safeSetState(() {
      _selectedMode = mode;
      _startMatchmakingCountdown();
    });
  }

  @override
  void dispose() {
    _matchmakingTimer?.cancel();
    _stateSyncTimer?.cancel();
    _readyTimeoutTimer?.cancel();
    _roomSubscription?.cancel();
    _actionSubscription?.cancel();
    if (_onlineService != null && _roomId != null) {
      unawaited(_onlineService!.leaveRoom(_roomId!));
    } else if (_onlineService != null) {
      unawaited(_onlineService!.leaveQueue());
    }
    _radarController.dispose();
    _keyboardController?.detach();
    _focusNode.dispose();
    super.dispose();
  }

  void _startMatchmakingCountdown() {
    final attempt = ++_searchAttempt;
    _elapsedSeconds = 0.0;
    _matchmakingStatus = FirebaseBootstrap.isReady
        ? 'Đang tìm người chơi online...'
        : 'Firebase chưa cấu hình • sẽ chuyển sang đấu bot';
    _matchmakingTimer?.cancel();
    _matchmakingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!mounted) return;
      _safeSetState(() {
        _elapsedSeconds += 0.1;
      });

      // Cơ chế 60 giây fallback Bot đúng theo mục 4.2 tài liệu
      if (_elapsedSeconds >= 60.0) {
        _matchmakingTimer?.cancel();
        if (attempt == _searchAttempt) {
          unawaited(_fallbackToBotSafely());
        }
      }
    });
    if (FirebaseBootstrap.isReady) unawaited(_findOnlineMatch(attempt));
  }

  /// Rút khỏi hàng chờ online trước khi đấu bot. Nếu đúng lúc đó đã bị ghép
  /// với người thật thì vào phòng người thật thay vì bỏ rơi đối thủ.
  Future<void> _fallbackToBotSafely() async {
    final service = _onlineService;
    if (service != null && _roomId == null && FirebaseBootstrap.isReady) {
      _safeSetState(() => _matchmakingStatus = 'Đang rút khỏi hàng chờ...');
      try {
        final roomId = await service.cancelSearch();
        if (!mounted) return;
        if (roomId != null) {
          // findMatch() sẽ tự trả về roomId này và gọi _joinOnlineRoom.
          return;
        }
      } catch (error) {
        debugPrint('PvP cancelSearch error: $error');
      }
    }
    if (!mounted || _roomId != null) return;
    _lockInOpponent(isFallback: true);
  }

  Future<void> _findOnlineMatch(int attempt) async {
    try {
      final service = FirebasePvpService();
      _onlineService = service;
      final roomId = await service.findMatch(
        PlayerStorage.currentProfile,
        mode: _selectedMode,
      );
      if (!mounted || attempt != _searchAttempt) {
        if (roomId != null) unawaited(service.leaveRoom(roomId));
        return;
      }
      if (roomId == null) {
        _safeSetState(
          () => _matchmakingStatus =
              'Chưa tìm thấy đối thủ. Có thể chọn đấu bot.',
        );
        return;
      }
      await _joinOnlineRoom(roomId, service);
    } catch (error) {
      if (!mounted || attempt != _searchAttempt) return;
      _safeSetState(() => _matchmakingStatus = 'Lỗi kết nối Firebase: $error');
    }
  }

  Future<void> _joinOnlineRoom(
    String roomId,
    FirebasePvpService service,
  ) async {
    final room = await service.readRoom(roomId);
    final order = (room['playerOrder'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (order.length != 2) {
      throw StateError('Phòng PvP thiếu danh sách hai người chơi.');
    }

    final profilesRaw = room['profiles'];
    final profiles = profilesRaw is Map
        ? profilesRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final isPlayerOne = order.first == service.uid;
    final otherUid = isPlayerOne ? order.last : order.first;
    final opponentRaw = profiles[otherUid];
    final opponentMap = opponentRaw is Map
        ? opponentRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final opponent = PvpOpponentInfo(
      name: opponentMap['name'] as String? ?? 'Người chơi',
      rankPoints: (opponentMap['rankPoints'] as num?)?.toInt() ?? 1000,
      rankTier: opponentMap['rankTier'] as String? ?? 'Đồng',
      heroId: opponentMap['heroId'] as String? ?? 'george',
      isBot: false,
    );

    _roomId = roomId;
    _matchmakingTimer?.cancel();
    if (!mounted) return;
    _safeSetState(() {
      _opponent = opponent;
      _isMatchmaking = false;
      _initGame(opponent, isOnline: true, isPlayerOne: isPlayerOne);
    });
    // Bind TRƯỚC khi báo sẵn sàng để không lỡ sự kiện "ready" của đối thủ.
    _bindOnlineRoom(service, roomId, otherUid);
    await service.markReady(roomId);
  }

  void _bindOnlineRoom(
    FirebasePvpService service,
    String roomId,
    String otherUid,
  ) {
    _roomSubscription?.cancel();
    _actionSubscription?.cancel();
    _readyTimeoutTimer?.cancel();
    _syncTxCount = 0;
    _syncRxCount = 0;
    var opponentSeenConnected = false;

    // Đối thủ phải vào phòng trong 15s, nếu không quay lại tìm trận.
    _readyTimeoutTimer = Timer(const Duration(seconds: 15), () {
      final game = _arenaGame;
      if (!mounted || game == null || !game.isWaitingForOpponent) return;
      _abandonRoomAndResearch('Đối thủ không vào phòng. Đang tìm trận mới...');
    });

    _roomSubscription = service.watchPlayer(roomId, otherUid).listen((
      snapshot,
    ) {
      final game = _arenaGame;
      if (game == null) return;
      if (snapshot.isEmpty) return;
      _syncRxCount++;

      final connected = snapshot['connected'] as bool? ?? true;
      final ready = snapshot['ready'] as bool? ?? false;
      if (connected) opponentSeenConnected = true;

      if (game.isWaitingForOpponent && ready && connected) {
        _readyTimeoutTimer?.cancel();
        game.startOnlineMatch();
      } else if (!connected &&
          opponentSeenConnected &&
          game.matchState != PvpMatchState.matchFinished) {
        if (game.isWaitingForOpponent) {
          _abandonRoomAndResearch('Đối thủ đã rời phòng. Đang tìm trận mới...');
          return;
        }
        game.opponentForfeit();
        return;
      }
      game.applyOpponentSnapshot(snapshot);
    });
    _actionSubscription = service.watchActions(roomId).listen((event) {
      final actionRaw = event.snapshot.value;
      if (actionRaw is! Map) return;
      final action = actionRaw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (action['actorUid'] == otherUid) {
        _arenaGame?.applyOpponentAction(
          action['action'] as String? ?? '',
          text: action['text'] as String?,
        );
      }
    });
    _stateSyncTimer?.cancel();
    _isStateWritePending = false;
    _stateSyncTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _pushLocalStateImmediately();
    });
  }

  void _pushLocalStateImmediately({bool force = false}) {
    final game = _arenaGame;
    final service = _onlineService;
    final roomId = _roomId;
    if (game == null || service == null || roomId == null || !mounted) return;
    if (_isStateWritePending && !force) return;
    _isStateWritePending = true;
    service
        .writePlayerState(roomId, game.localSnapshot)
        .then((_) {
          _syncTxCount++;
        })
        .catchError((err) {
          debugPrint('PvP State Sync Error: $err');
        })
        .whenComplete(() {
          _isStateWritePending = false;
        });
  }

  void _onPlayerMoveDirectionChanged(Vector2 dir) {
    _arenaGame?.setPlayerMoveDirection(dir);
    _pushLocalStateImmediately();
  }

  void _abandonRoomAndResearch(String status) {
    _prepareNextSearch();
    _safeSetState(() {
      _isMatchmaking = true;
      _arenaGame = null;
      _opponent = null;
      _startMatchmakingCountdown();
      _matchmakingStatus = status;
    });
  }

  void _lockInOpponent({bool isFallback = false}) {
    _searchAttempt++;
    if (_onlineService != null) unawaited(_onlineService!.leaveQueue());
    final profile = PlayerStorage.currentProfile;
    final partyAllies = FriendPartyService.instance.getPartyAlliesForMode(
      _selectedMode,
    );
    final roster = PvpOpponentInfo.generateTeamRoster(
      playerRp: profile.rankPoints,
      mode: _selectedMode,
      playerHeroId: profile.selectedHeroId,
      onlineAllies: partyAllies,
    );
    final opponent = roster.primaryOpponent;

    _safeSetState(() {
      _opponent = opponent;
      _isMatchmaking = false;
      _initGame(opponent, roster: roster);
    });
  }

  void _prepareNextSearch() {
    _stateSyncTimer?.cancel();
    _readyTimeoutTimer?.cancel();
    _roomSubscription?.cancel();
    _actionSubscription?.cancel();
    if (_onlineService != null && _roomId != null) {
      unawaited(_onlineService!.leaveRoom(_roomId!));
    }
    _roomId = null;
  }

  void _initGame(
    PvpOpponentInfo opponent, {
    bool isOnline = false,
    bool isPlayerOne = true,
    PvpTeamRoster? roster,
  }) {
    final profile = PlayerStorage.currentProfile;
    _arenaGame = PvpArenaGame(
      opponentInfo: opponent,
      playerCurrentRp: profile.rankPoints,
      isOnline: isOnline,
      isPlayerOne: isPlayerOne,
      gameMode: _selectedMode,
      roster: roster,
    );

    _keyboardController?.detach();
    _keyboardController = GameKeyboardController(
      onMoveDirectionChanged: _onPlayerMoveDirectionChanged,
      onBasicAttack: () {
        _arenaGame?.onBasicAttack();
        _pushLocalStateImmediately();
      },
      onSkill1: () {
        _arenaGame?.onSkill1();
        _pushLocalStateImmediately();
      },
      onSkill2: () {
        _arenaGame?.onSkill2();
        _pushLocalStateImmediately();
      },
      onSkill3: () {
        _arenaGame?.onSkill3();
        _pushLocalStateImmediately();
      },
    );
    _keyboardController!.attach();

    _arenaGame!.onStateChanged = () {
      final state = _arenaGame?.matchState;
      if (state == PvpMatchState.roundEnd ||
          state == PvpMatchState.matchFinished) {
        _pushLocalStateImmediately(force: true);
      }
      _safeSetState();
    };

    _arenaGame!.onMatchFinished = (result) {
      _pushLocalStateImmediately(force: true);
      if (!mounted) return;
      _handleMatchFinished(result);
    };
    if (isOnline) {
      _arenaGame!.onLocalAction = (action, {text}) {
        _pushLocalStateImmediately(force: true);
        final roomId = _roomId;
        final service = _onlineService;
        if (roomId != null && service != null) {
          unawaited(service.sendAction(roomId, action, text: text));
        }
      };
    }
  }

  void _handleMatchFinished(PvpMatchResult result) {
    final current = PlayerStorage.currentProfile;
    final updated = current.copyWith(
      rankPoints: result.newRankPoints,
      gold: current.gold + result.goldReward,
    );
    PlayerStorage.saveProfile(updated);
    unawaited(
      PlayerStorage.addHeroExpAfterMatch(
        isVictory: result.isWinner,
        isPvp: true,
        floorOrRounds: result.playerRoundsWon + result.opponentRoundsWon,
        coinsOrKills: result.goldReward,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PvpResultModal(
          result: result,
          onReturnToLobby: () {
            Navigator.of(context).pop(); // Đóng modal
            Navigator.of(context).pop(); // Thoát về Lobby
          },
          onPlayAgain: () {
            Navigator.of(context).pop();
            _prepareNextSearch();
            _safeSetState(() {
              _isMatchmaking = true;
              _arenaGame = null;
              _startMatchmakingCountdown();
            });
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isMatchmaking) {
      return _buildMatchmakingView();
    }

    if (_arenaGame == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDesktopOrWeb = GamePlatformHelper.isDesktopOrWeb;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // 1. GAME CANVAS
            GameWidget<PvpArenaGame>(game: _arenaGame!),

            // 2. TOP HUD: ĐỐI KHÁNG BO3, HP 2 ĐẤU SĨ & ĐỒNG HỒ 90S
            Positioned(
              top: 10,
              left: 14,
              right: 14,
              child: _buildTopArenaBar(),
            ),

            // 3. BANNER INTRO / ROUND END OVERLAY
            if (_arenaGame!.matchState == PvpMatchState.waiting)
              Center(child: _buildWaitingOpponentBanner()),
            if (_arenaGame!.matchState == PvpMatchState.roundIntro ||
                _arenaGame!.matchState == PvpMatchState.roundEnd)
              Center(child: _buildRoundStatusBanner()),

            // 4. VIRTUAL JOYSTICK (BÊN TRÁI)
            if (_showTouchControls || GamePlatformHelper.isMobile)
              Positioned(
                bottom: 24,
                left: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDesktopOrWeb)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.amberAccent.withValues(alpha: 0.7),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'W A S D',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    VirtualJoystick(
                      onDirectionChanged: (offset) {
                        if (offset == Offset.zero &&
                            _keyboardController != null &&
                            _keyboardController!.hasKeyboardMovement) {
                          _onPlayerMoveDirectionChanged(
                            _keyboardController!.currentDirection,
                          );
                        } else {
                          _onPlayerMoveDirectionChanged(
                            Vector2(offset.dx, offset.dy),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

            // 5. CỤM PHÍM HÀNH ĐỘNG (BÊN PHẢI)
            if (_showTouchControls || GamePlatformHelper.isMobile)
              Positioned(bottom: 24, right: 24, child: _buildActionButtons()),

            // 6. NÚT QUICK CHAT VÀ MENU BÓNG THOẠI
            Positioned(bottom: 28, left: 170, child: _buildQuickChatControl()),

            // 7. HINT BAR CHO PC/WEB (khi ẩn phím ảo)
            if (!_showTouchControls && isDesktopOrWeb)
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.keyboard,
                            color: Colors.amberAccent,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Di chuyển: WASD / Mũi tên  |  Kỹ năng: [1] Bão Búa  [2] Nện Đất  [3] Cuồng Nộ  |  Đánh: SPACE / J',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- GIAI ĐOẠN 1: RADAR MATCHMAKING (HỖ TRỢ 1V1 / 2V2 / 4V4) ---
  Widget _buildMatchmakingView() {
    final profile = PlayerStorage.currentProfile;
    final progress = (_elapsedSeconds / 60.0).clamp(0.0, 1.0);
    final teamSize = _selectedMode.teamSize;

    return Scaffold(
      backgroundColor: const Color(0xFF0D111A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. BỘ CHỌN CHẾ ĐỘ ĐẤU: 1v1 | 2v2 | 4v4
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141C2B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: PvpGameMode.values.map((mode) {
                      final isSelected = _selectedMode == mode;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          key: Key(
                            'pvp_mode_tab_${mode.shortLabel.toLowerCase()}',
                          ),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _selectMatchmakingMode(mode),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFFD700),
                                        Color(0xFFFF8F00),
                                      ],
                                    )
                                  : null,
                              color: isSelected ? null : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mode == PvpGameMode.solo1v1
                                      ? Icons.person
                                      : mode == PvpGameMode.duo2v2
                                      ? Icons.group
                                      : Icons.groups_rounded,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  mode.title.toUpperCase(),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Radar quét 360 độ
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 156,
                      height: 156,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF161F30),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.35),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                    ),
                    RotationTransition(
                      turns: _radarController,
                      child: Container(
                        width: 146,
                        height: 146,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Colors.cyanAccent.withValues(alpha: 0.6),
                              Colors.transparent,
                            ],
                            stops: const [0.25, 0.25],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          size: 38,
                          color: Colors.cyanAccent,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFFFD700),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _selectedMode.shortLabel,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  'ĐANG TÌM TRẬN ĐỐI KHÁNG RANK (${_selectedMode.shortLabel})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_selectedMode.subtitle} • Phạm vi ±150 RP (Bậc: ${profile.rankTier})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
                if (_matchmakingStatus != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _matchmakingStatus!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // 3. SƠ ĐỒ ĐỘI HÌNH TRỰC QUAN (ĐỘI XANH VS ĐỘI ĐỎ)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141C2B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ĐỘI XANH
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(teamSize, (idx) {
                          final isLeader = idx == 0;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isLeader
                                  ? const Color(0xFF00E676)
                                        .withValues(alpha: 0.2)
                                  : const Color(0xFF00B0FF)
                                        .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isLeader
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFF00B0FF),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isLeader
                                      ? Icons.person
                                      : Icons.shield_outlined,
                                  size: 16,
                                  color: isLeader
                                      ? const Color(0xFF00E676)
                                      : const Color(0xFF80D8FF),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isLeader ? 'BẠN' : 'Đ.ĐỘI ${idx + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      // ĐỘI ĐỎ
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(teamSize, (idx) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF1744)
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFFF1744),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  size: 16,
                                  color: Color(0xFFFF5252),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ĐỐI THỦ ${idx + 1}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Đồng hồ đếm ngược 60s
                Text(
                  '${_elapsedSeconds.toStringAsFixed(1)}s / 60.0s',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),

                // Thanh tiến trình
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(
                      Colors.amberAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Nút Hủy & Nút Ghép Ngay
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                      ),
                      onPressed: () {
                        _searchAttempt++;
                        if (_onlineService != null) {
                          unawaited(_onlineService!.leaveQueue());
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('HỦY TÌM'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        _matchmakingTimer?.cancel();
                        unawaited(_fallbackToBotSafely());
                      },
                      icon: const Icon(Icons.flash_on),
                      label: const Text('GHÉP NGAY (AI BOT)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- GIAI ĐOẠN 2: TOP ARENA BAR (BO3, ĐỘI HÌNH 1v1/2v2/4v4 & ĐỒNG HỒ) ---
  Widget _buildTopArenaBar() {
    final game = _arenaGame!;
    final profile = PlayerStorage.currentProfile;
    final opponent = _opponent!;
    final isTeamMode = game.gameMode != PvpGameMode.solo1v1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // BÊN TRÁI: ĐỘI XANH (PLAYER + ĐỒNG ĐỘI)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _roomId == null || _onlineService == null
                          ? profile.playerName
                          : '${profile.playerName} #${_onlineService!.uid.substring(0, 4)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (isTeamMode) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E676)),
                      ),
                      child: Text(
                        '${game.blueTeamAliveCount}/${game.gameMode.teamSize}',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  _buildBo3Dots(game.playerWins, Colors.greenAccent),
                ],
              ),
              const SizedBox(height: 4),
              _buildPvpStatBar(
                game.player.currentHp,
                game.player.maxHp,
                const Color(0xFF00E676),
              ),
              if (game.allies.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  children: game.allies.map((ally) {
                    final pct = (ally.currentHp / ally.maxHp).clamp(0.0, 1.0);
                    return Container(
                      width: 68,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ally.opponentInfo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1),
                          LinearProgressIndicator(
                            value: pct,
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFF00E676),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),

        // Ở GIỮA: CHẾ ĐỘ, ĐỒNG HỒ 90S & ROUND
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D111A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${game.gameMode.shortLabel} • HIỆP ${game.currentRound} / 3',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${max(0, game.roundTimeRemaining.toInt())}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_roomId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'LIVE TX:$_syncTxCount RX:$_syncRxCount',
                    style: TextStyle(
                      color: _syncRxCount > 0
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // BÊN PHẢI: ĐỘI ĐỎ (ĐỐI THỦ BOT + ĐỒNG BỌN)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildBo3Dots(game.opponentWins, Colors.redAccent),
                  if (isTeamMode) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF1744)),
                      ),
                      child: Text(
                        '${game.redTeamAliveCount}/${game.gameMode.teamSize}',
                        style: const TextStyle(
                          color: Color(0xFFFF5252),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      opponent.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _buildPvpStatBar(
                game.bot.currentHp,
                game.bot.maxHp,
                const Color(0xFFFF1744),
              ),
              if (game.extraEnemies.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 3,
                  alignment: WrapAlignment.end,
                  children: game.extraEnemies.map((enemy) {
                    final pct = (enemy.currentHp / enemy.maxHp).clamp(0.0, 1.0);
                    return Container(
                      width: 68,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            enemy.opponentInfo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1),
                          LinearProgressIndicator(
                            value: pct,
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFFF1744),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBo3Dots(int wins, Color winColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(2, (index) {
        final isWon = index < wins;
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isWon ? winColor : Colors.white24,
            border: Border.all(color: Colors.white70, width: 1),
          ),
        );
      }),
    );
  }

  Widget _buildPvpStatBar(double cur, double maxVal, Color color) {
    final progress = (cur / maxVal).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingOpponentBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent, width: 2),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.cyanAccent,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'ĐANG CHỜ ĐỐI THỦ VÀO TRẬN...',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundStatusBanner() {
    final game = _arenaGame!;
    final isIntro = game.matchState == PvpMatchState.roundIntro;
    final text = isIntro
        ? 'HIỆP ${game.currentRound} — CHIẾN!'
        : (game.player.currentHp > game.bot.currentHp
              ? 'THẮNG HIỆP!'
              : 'THUA HIỆP!');

    final color = isIntro
        ? Colors.amberAccent
        : (game.player.currentHp > game.bot.currentHp
              ? Colors.greenAccent
              : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }

  // --- CỤM NÚT HÀNH ĐỘNG ---
  Widget _buildActionButtons() {
    final game = _arenaGame!;
    final p = game.player;
    final isDesktopOrWeb = GamePlatformHelper.isDesktopOrWeb;

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Positioned(
            bottom: 0,
            right: 0,
            child: _PvpActionButton(
              size: 74,
              icon: Icons.flash_on,
              label: 'ATK',
              hotkey: isDesktopOrWeb ? 'SPACE' : null,
              color: const Color(0xFFE53935),
              onTap: () => game.onBasicAttack(),
            ),
          ),
          Positioned(
            bottom: 84,
            right: 0,
            child: _PvpActionButton(
              size: 52,
              icon: p.kit.skills[0].icon,
              description:
                  '${p.kit.skills[0].name}: ${p.kit.skills[0].description}',
              label: '${p.kit.skills[0].cost.toInt()} Ki',
              hotkey: isDesktopOrWeb ? '1' : null,
              color: const Color(0xFFFF9800),
              cooldownRemaining: p.skill1VisualCd,
              maxCooldown: p.kit.skills[0].cooldown,
              hasEnoughKi: p.currentKi >= p.kit.skills[0].cost,
              lowKiFlash: p.insufficientKiFlashTimer > 0,
              onTap: () => game.onSkill1(),
            ),
          ),
          Positioned(
            bottom: 66,
            right: 66,
            child: _PvpActionButton(
              size: 52,
              icon: p.kit.skills[1].icon,
              description:
                  '${p.kit.skills[1].name}: ${p.kit.skills[1].description}',
              label: '${p.kit.skills[1].cost.toInt()} Ki',
              hotkey: isDesktopOrWeb ? '2' : null,
              color: const Color(0xFF00B0FF),
              cooldownRemaining: p.skill2VisualCd,
              maxCooldown: p.kit.skills[1].cooldown,
              hasEnoughKi: p.currentKi >= p.kit.skills[1].cost,
              lowKiFlash: p.insufficientKiFlashTimer > 0,
              onTap: () => game.onSkill2(),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 84,
            child: _PvpActionButton(
              size: 52,
              icon: p.kit.skills[2].icon,
              description:
                  '${p.kit.skills[2].name}: ${p.kit.skills[2].description}',
              label: '${p.kit.skills[2].cost.toInt()} Ki',
              hotkey: isDesktopOrWeb ? '3' : null,
              color: const Color(0xFF7B1FA2),
              cooldownRemaining: p.skill3VisualCd,
              maxCooldown: p.kit.skills[2].cooldown,
              hasEnoughKi: p.currentKi >= p.kit.skills[2].cost,
              lowKiFlash: p.insufficientKiFlashTimer > 0,
              onTap: () => game.onSkill3(),
            ),
          ),
        ],
      ),
    );
  }

  // --- QUICK CHAT ---
  Widget _buildQuickChatControl() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showQuickChatMenu)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyanAccent, width: 1.5),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: QuickChatPhrase.values.map((phrase) {
                return InkWell(
                  onTap: () {
                    _arenaGame?.sendQuickChat(phrase);
                    _safeSetState(() => _showQuickChatMenu = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2838),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      phrase.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B0FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                _safeSetState(() {
                  _showQuickChatMenu = !_showQuickChatMenu;
                });
              },
              icon: const Icon(Icons.chat_bubble_rounded, size: 16),
              label: const Text(
                'QUICK CHAT',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            if (GamePlatformHelper.isDesktopOrWeb) ...[
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2838),
                  foregroundColor: Colors.amberAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  _safeSetState(() => _showTouchControls = !_showTouchControls);
                },
                icon: Icon(
                  _showTouchControls ? Icons.gamepad : Icons.keyboard,
                  size: 16,
                ),
                label: Text(
                  _showTouchControls ? 'NÚT ẢO: BẬT' : 'PHÍM PC: WASD',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PvpActionButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final String label;
  final String? hotkey;
  final String? description;
  final Color color;
  final double cooldownRemaining;
  final double maxCooldown;
  final bool hasEnoughKi;
  final bool lowKiFlash;
  final VoidCallback onTap;

  const _PvpActionButton({
    required this.size,
    required this.icon,
    required this.label,
    this.hotkey,
    this.description,
    required this.color,
    this.cooldownRemaining = 0.0,
    this.maxCooldown = 1.0,
    this.hasEnoughKi = true,
    this.lowKiFlash = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onCd = cooldownRemaining > 0.05;
    final borderColor = (!hasEnoughKi && lowKiFlash)
        ? const Color(0xFFFF1744)
        : (hasEnoughKi ? const Color(0xFFFFD700) : Colors.white38);

    return Tooltip(
      message: description ?? label,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasEnoughKi
                    ? color.withValues(alpha: 0.92)
                    : color.withValues(alpha: 0.45),
                border: Border.all(color: borderColor, width: 2.2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: hasEnoughKi ? 0.45 : 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: Colors.white, size: size * 0.40),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: size * 0.16,
                          ),
                        ),
                      ],
                    ),
                    if (onCd)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _CooldownArcPainter(
                            progress: (cooldownRemaining / maxCooldown).clamp(
                              0.0,
                              1.0,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${cooldownRemaining.toStringAsFixed(1)}s',
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: size * 0.22,
                                fontWeight: FontWeight.w900,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (hotkey != null)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141926),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    hotkey!,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CooldownArcPainter extends CustomPainter {
  final double progress;

  const _CooldownArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.68)
      ..style = PaintingStyle.fill;
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, true, paint);
  }

  @override
  bool shouldRepaint(covariant _CooldownArcPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// --- MODAL KẾT QUẢ TRẬN ĐẤU ---
class _PvpResultModal extends StatelessWidget {
  final PvpMatchResult result;
  final VoidCallback onReturnToLobby;
  final VoidCallback onPlayAgain;

  const _PvpResultModal({
    required this.result,
    required this.onReturnToLobby,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    final title = result.isWinner ? 'CHIẾN THẮNG!' : 'THẤT BẠI!';
    final titleColor = result.isWinner
        ? const Color(0xFFFFD700)
        : const Color(0xFFFF1744);
    final deltaStr = result.rpDelta >= 0
        ? '+${result.rpDelta}'
        : '${result.rpDelta}';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF141926),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: titleColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: titleColor.withValues(alpha: 0.35),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'TỈ SỐ HIỆP: ${result.playerRoundsWon} - ${result.opponentRoundsWon}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Điểm Rank
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'ĐIỂM RANK',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      Text(
                        '$deltaStr RP',
                        style: TextStyle(
                          color: result.rpDelta >= 0
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        'THƯỞNG VÀNG',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      Text(
                        '+${result.goldReward}',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (result.isPromotion) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amberAccent),
                ),
                child: Text(
                  '🎉 CHÚC MỪNG BẠN ĐÃ THĂNG HẠNG: ${result.newRankTier.toUpperCase()}!',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                  onPressed: onReturnToLobby,
                  child: const Text('VỀ SẢNH'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: titleColor,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: onPlayAgain,
                  child: const Text('TÌM TRẬN TIẾP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
