import 'dart:async';
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/game_keyboard_controller.dart';
import '../game/combat/hero_skill_system.dart';
import '../game/hud/virtual_joystick.dart';
import '../game/pvp_arena_game.dart';
import '../models/friend_party_models.dart';
import '../models/pvp_match.dart';
import '../registry/asset_registry.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firebase_pvp_service.dart';
import '../services/friend_party_service.dart';
import '../services/player_storage.dart';
import 'settings_dialog.dart';
import 'widgets/rank_badge.dart';

class PvpArenaScreen extends StatefulWidget {
  final PvpGameMode initialMode;
  final PartyRoomState? partyRoom;
  final SoloDuelRoomState? soloRoom;

  const PvpArenaScreen({
    super.key,
    this.initialMode = PvpGameMode.solo1v1,
    this.partyRoom,
    this.soloRoom,
  });

  @override
  State<PvpArenaScreen> createState() => _PvpArenaScreenState();
}

class _PvpArenaScreenState extends State<PvpArenaScreen>
    with TickerProviderStateMixin {
  static const double _onlineMatchmakingTimeoutSeconds = 20.0;
  static const double _offlineBotFallbackDelaySeconds = 1.8;

  late PvpGameMode _selectedMode;
  bool _isMatchmaking = true;
  double _elapsedSeconds = 0.0;
  double _currentSearchTimeoutSeconds = _onlineMatchmakingTimeoutSeconds;
  bool _hasTriggeredFallback = false;
  Timer? _matchmakingTimer;
  Future<void> _pendingCleanup = Future.value();

  void _enqueueCleanup(Future<void> Function() task) {
    _pendingCleanup = _pendingCleanup
        .catchError((_) {})
        .then((_) => task())
        .catchError((Object e) {
      debugPrint('PvP cleanup error: $e');
    });
  }

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
  bool _hasHandledMatchFinish = false;

  // Party Co-op Matchmaking & Sync
  final List<StreamSubscription> _partySyncSubs = [];
  Timer? _partySyncTimer;
  bool _isPartyStateWritePending = false;
  bool _hasPoppedFromPartyCancel = false;

  // Solo / Custom 4v4 Room Wager & Sync
  final List<StreamSubscription> _soloSyncSubs = [];
  int _escrowedSoloBetGold = 0;
  bool _hasSettledSoloWager = false;

  bool get _isInSoloRoom => widget.soloRoom != null;
  bool get _isInParty => widget.partyRoom != null;
  bool get _isPartyGuest {
    final party = widget.partyRoom;
    if (party == null) return false;
    return !party.isLeader(FriendPartyService.instance.effectivePlayerCode);
  }

  void _safeSetState([VoidCallback? fn]) {
    if (!mounted) return;
    fn?.call();
    if (_isRebuildScheduled) return;

    final isBuilding = WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    final isPersistent = WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;

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
    _selectedMode = widget.partyRoom?.mode ?? widget.initialMode;

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    if (_isInSoloRoom) {
      _selectedMode = PvpGameMode.solo1v1;
      _isMatchmaking = false;
      _startSoloRoomMatch(widget.soloRoom!);
      return;
    }

    if (_isInParty) {
      FriendPartyService.instance.partyNotifier.addListener(_onPartyRoomUpdated);
    }

    _startMatchmakingCountdown();

    if (_isInParty && widget.partyRoom?.matchStatus == 'in_match') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentParty =
            FriendPartyService.instance.partyNotifier.value ?? widget.partyRoom!;
        _startPartyMatchLocally(currentParty);
      });
    }
  }

  void _onPartyRoomUpdated() {
    if (!mounted || !_isInParty) return;
    final party = FriendPartyService.instance.partyNotifier.value;
    if (_isPartyGuest && _isMatchmaking) {
      if (party == null || party.matchStatus == 'idle') {
        if (!_hasPoppedFromPartyCancel) {
          _hasPoppedFromPartyCancel = true;
          _matchmakingTimer?.cancel();
          Navigator.of(context).pop();
        }
        return;
      }
      if (party.matchStatus == 'in_match') {
        _startPartyMatchLocally(party);
      }
    }
  }

  void _selectMatchmakingMode(PvpGameMode mode) {
    if (_isInParty) return;
    if (_selectedMode == mode) return;
    _prepareNextSearch();
    final oldService = _onlineService;
    if (oldService != null) {
      _enqueueCleanup(() => oldService.leaveQueue());
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
    for (final sub in _soloSyncSubs) {
      sub.cancel();
    }
    _soloSyncSubs.clear();
    _partySyncTimer?.cancel();
    for (final sub in _partySyncSubs) {
      sub.cancel();
    }
    _partySyncSubs.clear();
    if (_isInSoloRoom) {
      final soloMatchId = _roomId ?? widget.soloRoom?.activeMatchRoomId;
      final myCode = FriendPartyService.instance.effectivePlayerCode;
      if (soloMatchId != null) {
        unawaited(
          FriendPartyService.instance.leaveSoloMatchRoom(soloMatchId, myCode),
        );
      }
      // Nếu trận chưa kịp bắt đầu (đối thủ chưa vào) thì hoàn lại Vàng đặt cọc
      if (!_hasSettledSoloWager &&
          (_arenaGame?.isWaitingForOpponent ?? true) &&
          _escrowedSoloBetGold > 0) {
        _hasSettledSoloWager = true;
        unawaited(PlayerStorage.addGold(_escrowedSoloBetGold));
      }
      unawaited(FriendPartyService.instance.resetSoloRoomAfterMatch());
    }
    if (_isInParty) {
      FriendPartyService.instance.partyNotifier.removeListener(_onPartyRoomUpdated);
      if (!_isPartyGuest) {
        unawaited(FriendPartyService.instance.resetPartyMatchStatus());
      }
    }
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
    _hasTriggeredFallback = false;

    if (_isInParty) {
      final party =
          FriendPartyService.instance.partyNotifier.value ?? widget.partyRoom!;
      if (_isPartyGuest) {
        _currentSearchTimeoutSeconds = 30.0;
        _matchmakingStatus =
            'Đang chờ Chủ Phòng (${party.leaderName}) ghép trận...';
        _matchmakingTimer?.cancel();
        _matchmakingTimer =
            Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (!mounted) return;
          _safeSetState(() => _elapsedSeconds += 0.1);
        });
        return;
      }

      // Chủ phòng tổ đội: tìm trận nhanh rồi kéo cả tổ đội vào đấu trường
      _currentSearchTimeoutSeconds = _offlineBotFallbackDelaySeconds;
      _matchmakingStatus =
          'Đang ghép trận cùng Tổ Đội (${party.currentMemberCount}/${party.maxSlots})...';
      _matchmakingTimer?.cancel();
      _matchmakingTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        _safeSetState(() => _elapsedSeconds += 0.1);
        if (!_hasTriggeredFallback &&
            _elapsedSeconds >= _currentSearchTimeoutSeconds) {
          _matchmakingTimer?.cancel();
          if (attempt == _searchAttempt) {
            _hasTriggeredFallback = true;
            unawaited(_leaderLaunchPartyMatch());
          }
        }
      });
      return;
    }

    final canSearchOnline =
        FirebaseBootstrap.isReady && AuthService.instance.isSignedIn;
    _currentSearchTimeoutSeconds = canSearchOnline
        ? _onlineMatchmakingTimeoutSeconds
        : _offlineBotFallbackDelaySeconds;

    _matchmakingStatus = canSearchOnline
        ? 'Đang tìm người chơi online... (tự ghép Bot sau ${_onlineMatchmakingTimeoutSeconds.toInt()}s)'
        : 'Chưa có người chơi trực tuyến • Đang tự động ghép Bot AI...';

    _matchmakingTimer?.cancel();
    _matchmakingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      _safeSetState(() {
        _elapsedSeconds += 0.1;
        if (canSearchOnline &&
            !_hasTriggeredFallback &&
            _elapsedSeconds >= 5.0 &&
            _elapsedSeconds < _currentSearchTimeoutSeconds) {
          _matchmakingStatus =
              'Đang mở rộng phạm vi rank tìm người chơi online...';
        }
      });

      // Tự động ghép Bot nếu hết thời gian chờ mà không tìm thấy người chơi online
      if (!_hasTriggeredFallback && _elapsedSeconds >= _currentSearchTimeoutSeconds) {
        _matchmakingTimer?.cancel();
        if (attempt == _searchAttempt) {
          unawaited(_fallbackToBotSafely());
        }
      }
    });
    if (canSearchOnline) unawaited(_findOnlineMatch(attempt));
  }

  Future<void> _leaderLaunchPartyMatch() async {
    if (!mounted || !_isInParty || _isPartyGuest) return;
    await FriendPartyService.instance.markPartyMatchInProgress();
    if (!mounted) return;
    final currentParty =
        FriendPartyService.instance.partyNotifier.value ?? widget.partyRoom!;
    _startPartyMatchLocally(currentParty);
  }

  /// Rút khỏi hàng chờ online trước khi đấu bot. Nếu đúng lúc đó đã bị ghép
  /// với người thật thì vào phòng người thật thay vì bỏ rơi đối thủ.
  Future<void> _fallbackToBotSafely() async {
    if (_hasTriggeredFallback) return;
    _hasTriggeredFallback = true;
    final service = _onlineService;
    if (service != null &&
        _roomId == null &&
        FirebaseBootstrap.isReady &&
        AuthService.instance.isSignedIn) {
      _safeSetState(() => _matchmakingStatus = 'Không có người chơi • Đang ghép Bot AI...');
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
      await _pendingCleanup;
      if (!mounted || attempt != _searchAttempt) return;
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
        _safeSetState(() => _matchmakingStatus = 'Không có người chơi online • Đang ghép Bot AI...');
        _matchmakingTimer?.cancel();
        if (!_hasTriggeredFallback) unawaited(_fallbackToBotSafely());
        return;
      }
      await _joinOnlineRoom(roomId, service);
    } catch (error) {
      if (!mounted || attempt != _searchAttempt) return;
      _safeSetState(() => _matchmakingStatus = 'Không thể ghép online • Đang ghép Bot AI...');
      _matchmakingTimer?.cancel();
      if (!_hasTriggeredFallback && _roomId == null) {
        unawaited(_fallbackToBotSafely());
      }
    }
  }

  Future<void> _joinOnlineRoom(String roomId, FirebasePvpService service) async {
    final room = await service.readRoom(roomId);
    final order = (room['playerOrder'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (order.length != 2) throw StateError('Phòng PvP thiếu danh sách hai người chơi.');

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

    // Đồng bộ cùng 1 bản đồ cho cả 2 người chơi trong phòng
    final metaRaw = room['meta'];
    final metaMap = metaRaw is Map
        ? metaRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final roomMapId = (room['mapId'] as String?) ?? (metaMap['mapId'] as String?);
    final syncedMapConfig = (roomMapId != null && roomMapId.isNotEmpty)
        ? (GameAssetRegistry.instance.getMap(roomMapId) ??
            GameAssetRegistry.instance.getMapFromSeed(roomId))
        : GameAssetRegistry.instance.getMapFromSeed(roomId);

    _safeSetState(() {
      _opponent = opponent;
      _isMatchmaking = false;
      _initGame(
        opponent,
        isOnline: true,
        isPlayerOne: isPlayerOne,
        selectedMapConfig: syncedMapConfig,
      );
    });
    // Bind TRƯỚC khi báo sẵn sàng để không lỡ sự kiện "ready" của đối thủ.
    _bindOnlineRoom(service, roomId, otherUid);
    await service.markReady(roomId);
  }

  void _bindOnlineRoom(FirebasePvpService service, String roomId, String otherUid) {
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

    _roomSubscription = service.watchPlayer(roomId, otherUid).listen((snapshot) {
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
      } else if (!connected && opponentSeenConnected &&
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
      final action = actionRaw.map((key, value) => MapEntry(key.toString(), value));
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

  void _startSoloRoomMatch(SoloDuelRoomState soloRoom) {
    final profile = PlayerStorage.currentProfile;
    final myCode =
        FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
    final isHost = soloRoom.isHost(myCode);
    final myTeam = soloRoom.teamOf(myCode) ?? 'blue';
    final isLocalTeamBlue = myTeam == 'blue';
    final hostTeam = soloRoom.teamOf(soloRoom.hostCode) ?? 'blue';
    final isSameTeamAsHost = myTeam == hostTeam;
    final mySlotIdx = max(0, soloRoom.slotIndexOf(myCode));

    final myTeamSlots = isLocalTeamBlue ? soloRoom.blueSlots : soloRoom.redSlots;
    final oppTeamSlots =
        isLocalTeamBlue ? soloRoom.redSlots : soloRoom.blueSlots;

    final allyInfos = <PvpOpponentInfo>[];
    final allySlots = <int>[];
    final allyCodes = <String>[];
    for (int s = 0; s < SoloDuelRoomState.slotsPerTeam; s++) {
      final m = myTeamSlots[s];
      if (m != null && m.code.trim().toUpperCase() != myCode) {
        allyInfos.add(m.toPvpAlly());
        allySlots.add(s);
        allyCodes.add(m.code.trim().toUpperCase());
      }
    }

    final enemyInfos = <PvpOpponentInfo>[];
    final enemySlots = <int>[];
    final enemyCodes = <String>[];
    for (int s = 0; s < SoloDuelRoomState.slotsPerTeam; s++) {
      final m = oppTeamSlots[s];
      if (m != null) {
        enemyInfos.add(m.toPvpOpponent());
        enemySlots.add(s);
        enemyCodes.add(m.code.trim().toUpperCase());
      }
    }

    if (enemyInfos.isEmpty) {
      enemyInfos.add(
        const PvpOpponentInfo(
          name: 'Đối Thủ Phòng Đấu',
          rankPoints: 1000,
          rankTier: 'Đồng',
          heroId: 'george',
          isBot: false,
        ),
      );
      enemySlots.add(0);
    }

    final opponentInfo = enemyInfos.first;
    final customRoster = PvpTeamRoster(
      mode: PvpGameMode.squad4v4,
      allies: allyInfos,
      enemies: enemyInfos,
    );

    final matchRoomId = soloRoom.activeMatchRoomId ??
        'solo_${soloRoom.roomCode.toUpperCase()}';
    final chosenMapId = soloRoom.resolvedMapId ?? soloRoom.selectedMapId;
    final syncedMapConfig = (chosenMapId != null && chosenMapId.isNotEmpty)
        ? (GameAssetRegistry.instance.getMap(chosenMapId) ??
            GameAssetRegistry.instance.getMapFromSeed(matchRoomId))
        : GameAssetRegistry.instance.getMapFromSeed(matchRoomId);

    // Tạm giữ Vàng đặt cược ngay khi vào phòng đấu để chống thoát ngang trốn cược
    final int betToEscrow =
        soloRoom.betGold.clamp(0, max(0, profile.gold)).toInt();
    if (betToEscrow > 0) {
      _escrowedSoloBetGold = betToEscrow;
      unawaited(PlayerStorage.spendGold(betToEscrow));
    }

    _roomId = matchRoomId;
    _opponent = opponentInfo;
    _isMatchmaking = false;
    _initGame(
      opponentInfo,
      isOnline: true,
      isPlayerOne: isLocalTeamBlue,
      roster: customRoster,
      selectedMapConfig: syncedMapConfig,
      soloMatchRoomId: matchRoomId,
      isCustomRoom: true,
      isLocalTeamBlue: isLocalTeamBlue,
      localCustomSlotIndex: mySlotIdx,
      localPlayerCode: myCode,
      customAllySlots: allySlots,
      customAllyCodes: allyCodes,
      customEnemySlots: enemySlots,
      customEnemyCodes: enemyCodes,
      isCustomRoomHost: isHost,
      isSameTeamAsHost: isSameTeamAsHost,
    );
    _bindSoloMatchSync(
      matchRoomId: matchRoomId,
      myCode: myCode,
      allyCodes: allyCodes,
      enemyCodes: enemyCodes,
      isHost: isHost,
    );
  }

  void _bindSoloMatchSync({
    required String matchRoomId,
    required String myCode,
    required List<String> allyCodes,
    required List<String> enemyCodes,
    required bool isHost,
  }) {
    for (final sub in _soloSyncSubs) {
      sub.cancel();
    }
    _soloSyncSubs.clear();
    _readyTimeoutTimer?.cancel();
    _syncTxCount = 0;
    _syncRxCount = 0;

    final allPeerCodes = <String>[...allyCodes, ...enemyCodes];
    final readyPeers = <String>{};
    final seenEnemies = <String>{};
    final connectedEnemies = <String>{};

    unawaited(
      FriendPartyService.instance.registerSoloMatchPresence(matchRoomId, myCode),
    );

    _readyTimeoutTimer = Timer(const Duration(seconds: 15), () async {
      final game = _arenaGame;
      if (!mounted || game == null || !game.isWaitingForOpponent) return;
      if (connectedEnemies.isNotEmpty) {
        game.startOnlineMatch();
        return;
      }
      await _abortUnstartedSoloMatch(
        'Đối phương không kết nối vào trận kịp thời — đã hoàn lại Vàng cược!',
      );
    });

    for (final peerCode in allPeerCodes) {
      final isEnemyPeer = enemyCodes.contains(peerCode);
      _soloSyncSubs.add(
        FriendPartyService.instance
            .watchPartyPlayerState(matchRoomId, peerCode)
            .listen((snapshot) {
          final game = _arenaGame;
          if (game == null || snapshot.isEmpty) return;
          _syncRxCount++;

          final connected = snapshot['connected'] as bool? ?? true;
          final ready = snapshot['ready'] as bool? ?? false;

          if (connected && ready) {
            readyPeers.add(peerCode);
          } else {
            readyPeers.remove(peerCode);
          }

          if (isEnemyPeer) {
            if (connected) {
              seenEnemies.add(peerCode);
              connectedEnemies.add(peerCode);
            } else {
              connectedEnemies.remove(peerCode);
            }
          }

          if (game.isWaitingForOpponent &&
              readyPeers.length >= allPeerCodes.length &&
              connectedEnemies.isNotEmpty) {
            _readyTimeoutTimer?.cancel();
            game.startOnlineMatch();
          } else if (isEnemyPeer &&
              !connected &&
              seenEnemies.isNotEmpty &&
              connectedEnemies.isEmpty &&
              enemyCodes.every(seenEnemies.contains) &&
              game.matchState != PvpMatchState.matchFinished) {
            if (game.isWaitingForOpponent) {
              unawaited(
                _abortUnstartedSoloMatch(
                  'Đội đối phương đã rời phòng trước khi trận bắt đầu — đã hoàn lại Vàng cược!',
                ),
              );
              return;
            }
            game.opponentForfeit();
            return;
          }

          game.applyCustomPeerSnapshot(peerCode, snapshot);
        }),
      );
    }

    _soloSyncSubs.add(
      FriendPartyService.instance.watchPartyActions(matchRoomId).listen((act) {
        final actor = (act['actorCode'] as String? ?? '').trim().toUpperCase();
        if (actor.isEmpty || actor == myCode) return;
        _arenaGame?.applyCustomPeerAction(
          actor,
          act['action'] as String? ?? '',
          text: act['text'] as String?,
        );
      }),
    );

    if (!isHost) {
      _soloSyncSubs.add(
        FriendPartyService.instance
            .watchPartyHostState(matchRoomId)
            .listen((hostState) {
          _arenaGame?.applyCustomRoomHostState(hostState);
        }),
      );
    }

    _stateSyncTimer?.cancel();
    _isStateWritePending = false;
    _pushLocalStateImmediately(force: true);
    _stateSyncTimer = Timer.periodic(const Duration(milliseconds: 35), (_) {
      _pushLocalStateImmediately();
    });
  }

  Future<void> _abortUnstartedSoloMatch(String message) async {
    _readyTimeoutTimer?.cancel();
    _stateSyncTimer?.cancel();
    if (!_hasSettledSoloWager && _escrowedSoloBetGold > 0) {
      _hasSettledSoloWager = true;
      await PlayerStorage.addGold(_escrowedSoloBetGold);
      _escrowedSoloBetGold = 0;
    }
    await FriendPartyService.instance.resetSoloRoomAfterMatch();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange.shade900,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop('reopen_solo');
  }

  void _startPartyMatchLocally(PartyRoomState party) {
    if (!_isMatchmaking) return;
    _matchmakingTimer?.cancel();
    _searchAttempt++;

    final profile = PlayerStorage.currentProfile;
    final myCode =
        FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
    final leaderCode = party.leaderCode.trim().toUpperCase();
    final isGuest = leaderCode != myCode;

    final orderedBlueCodes = <String>[
      leaderCode,
      ...party.members.map((m) => m.code.trim().toUpperCase()),
    ];
    final rawSlotIdx = orderedBlueCodes.indexOf(myCode);
    final localBlueSlotIndex =
        (rawSlotIdx >= 0 ? rawSlotIdx : 0).clamp(0, _selectedMode.teamSize - 1);

    final partyAllies =
        FriendPartyService.instance.getPartyAlliesForMode(_selectedMode);
    final humanAllyCodes = <int, String>{};
    var allyPtr = 0;
    if (isGuest && allyPtr < partyAllies.length) {
      humanAllyCodes[allyPtr++] = leaderCode;
    }
    for (final m in party.members) {
      final mCode = m.code.trim().toUpperCase();
      if (mCode != myCode && allyPtr < partyAllies.length) {
        humanAllyCodes[allyPtr++] = mCode;
      }
    }

    final seed =
        party.matchSeed != 0 ? party.matchSeed : party.partyCode.hashCode;
    final roster = PvpOpponentInfo.generateTeamRoster(
      playerRp: profile.rankPoints,
      mode: _selectedMode,
      playerHeroId: 'george',
      onlineAllies: partyAllies,
      seed: seed,
    );
    final opponent = roster.primaryOpponent;

    final roomId = party.activeMatchRoomId ??
        'party_${party.partyCode.toUpperCase()}_$seed';
    final syncedMapConfig =
        (party.activeMapId != null && party.activeMapId!.isNotEmpty)
            ? (GameAssetRegistry.instance.getMap(party.activeMapId!) ??
                GameAssetRegistry.instance.getMapFromSeed(roomId))
            : GameAssetRegistry.instance.getMapFromSeed(roomId);

    _safeSetState(() {
      _opponent = opponent;
      _isMatchmaking = false;
      _initGame(
        opponent,
        roster: roster,
        selectedMapConfig: syncedMapConfig,
        localBlueSlotIndex: localBlueSlotIndex,
        humanAllyCodes: humanAllyCodes,
        isPartyGuest: isGuest,
        partyRoomId: roomId,
      );
    });
    _bindPartyMatchSync(roomId, myCode, humanAllyCodes, isGuest);
  }

  void _bindPartyMatchSync(
    String roomId,
    String myCode,
    Map<int, String> humanAllyCodes,
    bool isGuest,
  ) {
    _partySyncTimer?.cancel();
    for (final sub in _partySyncSubs) {
      sub.cancel();
    }
    _partySyncSubs.clear();
    _isPartyStateWritePending = false;

    for (final teammateCode in humanAllyCodes.values) {
      _partySyncSubs.add(
        FriendPartyService.instance
            .watchPartyPlayerState(roomId, teammateCode)
            .listen((snapshot) {
          _arenaGame?.applyPartyAllySnapshot(teammateCode, snapshot);
        }),
      );
    }

    _partySyncSubs.add(
      FriendPartyService.instance.watchPartyActions(roomId).listen((action) {
        final actor =
            (action['actorCode'] as String? ?? '').trim().toUpperCase();
        if (actor.isEmpty || actor == myCode) return;
        _arenaGame?.applyPartyAllyAction(
          actor,
          action['action'] as String? ?? '',
          text: action['text'] as String?,
        );
      }),
    );

    if (isGuest) {
      _partySyncSubs.add(
        FriendPartyService.instance
            .watchPartyHostState(roomId)
            .listen((hostState) {
          _arenaGame?.applyPartyHostState(hostState);
        }),
      );
    }

    _partySyncTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pushPartySyncTick(roomId, myCode, isGuest);
    });
  }

  void _pushPartySyncTick(
    String roomId,
    String myCode,
    bool isGuest, {
    bool force = false,
  }) {
    final game = _arenaGame;
    if (game == null || !mounted) return;
    if (_isPartyStateWritePending && !force) return;
    _isPartyStateWritePending = true;
    final futures = <Future<void>>[
      FriendPartyService.instance
          .writePartyPlayerState(roomId, myCode, game.localSnapshot),
      if (!isGuest)
        FriendPartyService.instance
            .writePartyHostState(roomId, game.partyHostSnapshot),
    ];
    Future.wait(futures).whenComplete(() {
      _isPartyStateWritePending = false;
    });
  }

  void _pushLocalStateImmediately({bool force = false}) {
    final game = _arenaGame;
    if (game == null || !mounted) return;
    if (_isInSoloRoom) {
      final soloMatchId = _roomId;
      if (soloMatchId == null) return;
      if (_isStateWritePending && !force) return;
      _isStateWritePending = true;
      final myCode =
          FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
      final payload = <String, Object?>{
        ...game.localSnapshot,
        'ready': true,
        'connected': true,
      };
      final futures = <Future<void>>[
        FriendPartyService.instance
            .writePartyPlayerState(soloMatchId, myCode, payload),
        if (game.isCustomRoomHost)
          FriendPartyService.instance
              .writePartyHostState(soloMatchId, game.customRoomHostSnapshot),
      ];
      Future.wait(futures).then((_) {
        _syncTxCount++;
      }).catchError((Object err) {
        debugPrint('Solo State Sync Error: $err');
      }).whenComplete(() {
        _isStateWritePending = false;
      });
      return;
    }
    if (_isInParty) {
      final party =
          FriendPartyService.instance.partyNotifier.value ?? widget.partyRoom;
      final partyRoomId = party?.activeMatchRoomId;
      if (partyRoomId != null) {
        final myCode =
            FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
        _pushPartySyncTick(partyRoomId, myCode, _isPartyGuest, force: force);
      }
      return;
    }
    final service = _onlineService;
    final roomId = _roomId;
    if (service == null || roomId == null) return;
    if (_isStateWritePending && !force) return;
    _isStateWritePending = true;
    service.writePlayerState(roomId, game.localSnapshot).then((_) {
      _syncTxCount++;
    }).catchError((err) {
      debugPrint('PvP State Sync Error: $err');
    }).whenComplete(() {
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
    final partyAllies =
        FriendPartyService.instance.getPartyAlliesForMode(_selectedMode);
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
    final oldService = _onlineService;
    final oldRoomId = _roomId;
    if (oldService != null && oldRoomId != null) {
      _enqueueCleanup(() => oldService.leaveRoom(oldRoomId));
    }
    _roomId = null;
  }

  void _initGame(
    PvpOpponentInfo opponent, {
    bool isOnline = false,
    bool isPlayerOne = true,
    PvpTeamRoster? roster,
    MapAssetConfig? selectedMapConfig,
    int localBlueSlotIndex = 0,
    Map<int, String> humanAllyCodes = const {},
    bool isPartyGuest = false,
    String? partyRoomId,
    String? soloMatchRoomId,
    bool isCustomRoom = false,
    bool isLocalTeamBlue = true,
    int localCustomSlotIndex = 0,
    String localPlayerCode = '',
    List<int> customAllySlots = const [],
    List<String> customAllyCodes = const [],
    List<int> customEnemySlots = const [],
    List<String> customEnemyCodes = const [],
    bool isCustomRoomHost = false,
    bool isSameTeamAsHost = true,
  }) {
    _hasHandledMatchFinish = false;
    final profile = PlayerStorage.currentProfile;
    _arenaGame = PvpArenaGame(
      opponentInfo: opponent,
      playerCurrentRp: profile.rankPoints,
      playerCurrentStars: profile.rankStars,
      isCurrentChallengerTop10: profile.isChallengerTop10,
      isOnline: isOnline,
      isPlayerOne: isPlayerOne,
      gameMode: _selectedMode,
      roster: roster,
      selectedMapConfig: selectedMapConfig,
      localBlueSlotIndex: localBlueSlotIndex,
      humanAllyCodes: humanAllyCodes,
      isPartyGuest: isPartyGuest,
      isCustomRoom: isCustomRoom,
      isLocalTeamBlue: isLocalTeamBlue,
      localCustomSlotIndex: localCustomSlotIndex,
      localPlayerCode: localPlayerCode,
      customAllySlots: customAllySlots,
      customAllyCodes: customAllyCodes,
      customEnemySlots: customEnemySlots,
      customEnemyCodes: customEnemyCodes,
      isCustomRoomHost: isCustomRoomHost,
      isSameTeamAsHost: isSameTeamAsHost,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });

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
    if (soloMatchRoomId != null) {
      final myCode =
          FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
      _arenaGame!.onLocalAction = (action, {text}) {
        _pushLocalStateImmediately(force: true);
        unawaited(
          FriendPartyService.instance.sendPartyAction(
            soloMatchRoomId,
            myCode,
            action,
            text: text,
          ),
        );
      };
    } else if (isOnline) {
      _arenaGame!.onLocalAction = (action, {text}) {
        _pushLocalStateImmediately(force: true);
        final roomId = _roomId;
        final service = _onlineService;
        if (roomId != null && service != null) {
          unawaited(service.sendAction(roomId, action, text: text));
        }
      };
    } else if (partyRoomId != null) {
      final myCode =
          FriendPartyService.instance.effectivePlayerCode.trim().toUpperCase();
      _arenaGame!.onLocalAction = (action, {text}) {
        _pushLocalStateImmediately(force: true);
        unawaited(
          FriendPartyService.instance.sendPartyAction(
            partyRoomId,
            myCode,
            action,
            text: text,
          ),
        );
      };
    }
  }

  Future<void> _handleMatchFinished(PvpMatchResult result) async {
    if (_hasHandledMatchFinish) return;
    _hasHandledMatchFinish = true;

    final current = PlayerStorage.currentProfile;

    if (_isInSoloRoom) {
      _hasSettledSoloWager = true;
      final solo = widget.soloRoom!;
      final betGold = solo.betGold;
      final myCode = FriendPartyService.instance.effectivePlayerCode;
      final myTeam = solo.teamOf(myCode) ?? 'blue';
      final myTeamCount =
          max(1, myTeam == 'blue' ? solo.blueCount : solo.redCount);
      final totalPlayers = max(2, solo.totalPlayerCount);
      final totalEscrowPot = _escrowedSoloBetGold * totalPlayers;
      final potWon = result.isWinner ? (totalEscrowPot ~/ myTeamCount) : 0;
      final netGoldDelta = potWon - _escrowedSoloBetGold;

      final soloResult = PvpMatchResult(
        isWinner: result.isWinner,
        playerRoundsWon: result.playerRoundsWon,
        opponentRoundsWon: result.opponentRoundsWon,
        rpDelta: 0,
        newRankPoints: current.rankPoints,
        oldRankTier: current.rankTier,
        newRankTier: current.rankTier,
        isPromotion: false,
        isDemotion: false,
        goldReward: netGoldDelta,
        matchDuration: result.matchDuration,
        gameMode: PvpGameMode.solo1v1,
        starDelta: 0,
        oldTotalStars: current.rankStars,
        newTotalStars: current.rankStars,
        oldStarsInTier: current.starsInTier,
        newStarsInTier: current.starsInTier,
        maxStarsInNewTier: current.maxStarsInTier,
        isChallengerTop10: current.isChallengerTop10,
        serverRank: current.serverRank,
      );

      if (potWon > 0) {
        await PlayerStorage.saveProfile(
          current.copyWith(gold: current.gold + potWon),
        );
      }

      unawaited(
        PlayerStorage.addHeroExpAfterMatch(
          isVictory: soloResult.isWinner,
          isPvp: true,
          floorOrRounds:
              soloResult.playerRoundsWon + soloResult.opponentRoundsWon,
          coinsOrKills: max(0, potWon),
        ),
      );
      unawaited(FriendPartyService.instance.resetSoloRoomAfterMatch());

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _PvpResultModal(
            result: soloResult,
            isSoloRoom: true,
            soloBetGold: betGold,
            onReturnToLobby: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            onPlayAgain: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop('reopen_solo');
            },
          ),
        );
      });
      return;
    }

    final tentativeProfile = current.copyWith(
      rankPoints: result.newRankPoints,
      rankStars: result.newTotalStars,
      gold: current.gold + result.goldReward,
    );

    // Đánh giá vị trí trên BXH Server để xác định Top 10 Thách Đấu (nhiều sao nhất server)
    final serverEval = await DatabaseService.instance.evaluatePlayerServerRank(
      tentativeProfile,
    );

    final resolvedTier = PvpRankSystem.getTierFromStars(
      result.newTotalStars,
      isTop10Challenger: serverEval.isChallengerTop10,
    );

    final enrichedResult = result.copyWithChallengerStatus(
      isChallengerTop10: serverEval.isChallengerTop10,
      resolvedNewTier: resolvedTier,
      serverRank: serverEval.serverRank,
      top10CutoffStars: serverEval.top10CutoffStars,
    );

    final finalProfile = tentativeProfile.copyWith(
      isChallengerTop10: serverEval.isChallengerTop10,
      serverRank: serverEval.serverRank,
    );

    await PlayerStorage.saveProfile(finalProfile);
    await DatabaseService.instance.updateLeaderboard(finalProfile);

    unawaited(
      PlayerStorage.addHeroExpAfterMatch(
        isVictory: enrichedResult.isWinner,
        isPvp: true,
        floorOrRounds:
            enrichedResult.playerRoundsWon + enrichedResult.opponentRoundsWon,
        coinsOrKills: enrichedResult.goldReward,
      ),
    );

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PvpResultModal(
          result: enrichedResult,
          onReturnToLobby: () {
            Navigator.of(context).pop(); // Đóng modal
            Navigator.of(context).pop(); // Thoát về Lobby
          },
          onPlayAgain: () {
            Navigator.of(context).pop();
            if (_isInParty) {
              Navigator.of(context).pop();
              return;
            }
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

            // 3. BANNER INTRO / CHIẾN! / ROUND END OVERLAY (Không chặn thao tác chạm)
            if (_arenaGame!.matchState == PvpMatchState.waiting)
              Center(child: _buildWaitingOpponentBanner()),
            if (_arenaGame!.matchState == PvpMatchState.roundIntro ||
                _arenaGame!.matchState == PvpMatchState.roundEnd ||
                (_arenaGame!.matchState == PvpMatchState.fighting &&
                    _arenaGame!.fightStartBannerTimer > 0))
              IgnorePointer(
                child: Center(child: _buildRoundStatusBanner()),
              ),

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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.7), width: 1),
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
                          _onPlayerMoveDirectionChanged(Vector2(offset.dx, offset.dy));
                        }
                      },
                    ),
                  ],
                ),
              ),

            // 5. CỤM PHÍM HÀNH ĐỘNG (BÊN PHẢI)
            if (_showTouchControls || GamePlatformHelper.isMobile)
              Positioned(
                bottom: 24,
                right: 24,
                child: _buildActionButtons(),
              ),

            // 6. NÚT QUICK CHAT VÀ MENU BÓNG THOẠI
            Positioned(
              bottom: 28,
              left: 170,
              child: _buildQuickChatControl(),
            ),

            // 7. HINT BAR CHO PC/WEB (khi ẩn phím ảo)
            if (!_showTouchControls && isDesktopOrWeb)
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                          Icon(Icons.keyboard, color: Colors.amberAccent, size: 16),
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
    final progress = (_elapsedSeconds / _currentSearchTimeoutSeconds).clamp(0.0, 1.0);
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
                          key: Key('pvp_mode_tab_${mode.shortLabel.toLowerCase()}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: _isInParty ? null : () => _selectMatchmakingMode(mode),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
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
                                  color: isSelected ? Colors.black : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  mode.title.toUpperCase(),
                                  style: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white70,
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
                        const Icon(Icons.radar_rounded, size: 38, color: Colors.cyanAccent),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFD700), width: 1),
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
                  '${_selectedMode.subtitle} • Rank Chung (1v1/2v2/4v4): ${profile.rankDisplayLabel}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Thắng +1 ⭐ • Thua -1 ⭐ • Đồng → Kim Cương: 3 ⭐/bậc • Huyền Thoại: 0 ⭐+ • Thách Đấu: Top 10 Server',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_matchmakingStatus != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _matchmakingStatus!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 14),

                // 3. SƠ ĐỒ ĐỘI HÌNH TRỰC QUAN (ĐỘI XANH VS ĐỘI ĐỎ)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: isLeader
                                  ? const Color(0xFF00E676).withValues(alpha: 0.2)
                                  : const Color(0xFF00B0FF).withValues(alpha: 0.14),
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
                                  isLeader ? Icons.person : Icons.shield_outlined,
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF1744).withValues(alpha: 0.16),
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

                // Đồng hồ đếm ngược ghép trận
                Text(
                  '${_elapsedSeconds.toStringAsFixed(1)}s / ${_currentSearchTimeoutSeconds.toStringAsFixed(1)}s',
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
                    valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
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
                      onPressed: () async {
                        _searchAttempt++;
                        _matchmakingTimer?.cancel();
                        if (_isInParty) {
                          if (_isPartyGuest) {
                            FriendPartyService.instance.leaveParty();
                          } else {
                            await FriendPartyService.instance
                                .resetPartyMatchStatus();
                          }
                        } else if (_onlineService != null) {
                          unawaited(_onlineService!.leaveQueue());
                        }
                        if (mounted) Navigator.of(context).pop();
                      },
                      child: Text(_isPartyGuest ? 'RỜI PHÒNG' : 'HỦY TÌM'),
                    ),
                    if (!_isPartyGuest) ...[
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          _matchmakingTimer?.cancel();
                          if (_isInParty) {
                            _hasTriggeredFallback = true;
                            unawaited(_leaderLaunchPartyMatch());
                          } else {
                            unawaited(_fallbackToBotSafely());
                          }
                        },
                        icon: const Icon(Icons.flash_on),
                        label: const Text('GHÉP NGAY (AI BOT)'),
                      ),
                    ],
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
    final myTeamTotal = 1 + game.allies.length;
    final enemyTeamTotal = game.allEnemies.length;
    final isTeamMode = _isInSoloRoom
        ? (myTeamTotal > 1 || enemyTeamTotal > 1)
        : (game.gameMode != PvpGameMode.solo1v1);

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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E676)),
                      ),
                      child: Text(
                        '${game.blueTeamAliveCount}/$myTeamTotal',
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
              _buildPvpStatBar(game.player.currentHp, game.player.maxHp, const Color(0xFF00E676)),
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
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ally.opponentInfo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 7.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 1),
                          LinearProgressIndicator(
                            value: pct,
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF00E676)),
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

        // Ở GIỮA: CHẾ ĐỘ, ĐỒNG HỒ 90S & NÚT CÀI ĐẶT
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.only(left: 8, right: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0D111A).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isInSoloRoom
                        ? (widget.soloRoom!.betGold > 0
                            ? 'PHÒNG ${widget.soloRoom!.matchupLabel} • QUỸ ${widget.soloRoom!.totalPotGold}G • H${game.currentRound}/3'
                            : 'PHÒNG ${widget.soloRoom!.matchupLabel} • HIỆP ${game.currentRound}/3')
                        : '${game.gameMode.shortLabel} • HIỆP ${game.currentRound} / 3',
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
                          color: _syncRxCount > 0 ? Colors.greenAccent : Colors.orangeAccent,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, color: Color(0xFF00E5FF), size: 26),
              tooltip: 'Cài đặt âm lượng & trò chơi',
              visualDensity: VisualDensity.compact,
              onPressed: () => SettingsDialog.show(context),
            ),
          ],
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF1744)),
                      ),
                      child: Text(
                        '${game.redTeamAliveCount}/$enemyTeamTotal',
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
              _buildPvpStatBar(game.bot.currentHp, game.bot.maxHp, const Color(0xFFFF1744)),
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
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            enemy.opponentInfo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 7.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 1),
                          LinearProgressIndicator(
                            value: pct,
                            minHeight: 3,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF1744)),
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
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
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
    final isFightStart = game.matchState == PvpMatchState.fighting;
    final countdown = game.stateTimer.ceil().clamp(1, 3);

    final String text;
    final Color color;
    if (isIntro) {
      text = 'HIỆP ${game.currentRound} • CHUẨN BỊ ($countdown)';
      color = const Color(0xFF00E5FF);
    } else if (isFightStart) {
      text = 'HIỆP ${game.currentRound} — CHIẾN!';
      color = Colors.amberAccent;
    } else {
      text = game.lastRoundPlayerWon ? 'THẮNG HIỆP!' : 'THUA HIỆP!';
      color = game.lastRoundPlayerWon ? Colors.greenAccent : Colors.redAccent;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 16,
              ),
            ],
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
        ),
        if (isIntro) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final theme = game.currentMapConfig.theme;
              final isIce = theme == 'ice_arena' || theme == 'frost_island';
              final isForest = theme == 'forest' ||
                  theme == 'nature' ||
                  game.currentMapConfig.id == 'map_rung_cay';
              final badgeColor = isIce
                  ? const Color(0xFF00E5FF)
                  : isForest
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFFD700);
              final badgeIcon = isIce
                  ? Icons.ac_unit_rounded
                  : isForest
                      ? Icons.park_rounded
                      : Icons.account_balance_rounded;
              final textColor = isIce
                  ? const Color(0xFFE0F7FA)
                  : isForest
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF8E1);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2838).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, color: badgeColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'CHIẾN TRƯỜNG: ${game.currentMapConfig.name.toUpperCase()}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // --- CỤM NÚT HÀNH ĐỘNG ---
  Widget _buildActionButtons() {
    final game = _arenaGame!;
    final p = game.player;
    final isDesktopOrWeb = GamePlatformHelper.isDesktopOrWeb;
    final s1 = HeroSkillSystem.getSkillMeta(p.heroId, 1);
    final s2 = HeroSkillSystem.getSkillMeta(p.heroId, 2);
    final s3 = HeroSkillSystem.getSkillMeta(p.heroId, 3);

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
              icon: s1.icon,
              label: s1.shortLabel,
              hotkey: isDesktopOrWeb ? '1' : null,
              color: s1.color,
              cooldownRemaining: p.skill1VisualCd,
              maxCooldown: s1.cooldown,
              hasEnoughKi: p.currentKi >= s1.kiCost,
              lowKiFlash: p.insufficientKiFlashTimer > 0,
              onTap: () => game.onSkill1(),
            ),
          ),
          Positioned(
            bottom: 66,
            right: 66,
            child: _PvpActionButton(
              size: 52,
              icon: s2.icon,
              label: s2.shortLabel,
              hotkey: isDesktopOrWeb ? '2' : null,
              color: s2.color,
              cooldownRemaining: p.skill2VisualCd,
              maxCooldown: s2.cooldown,
              hasEnoughKi: p.currentKi >= s2.kiCost,
              lowKiFlash: p.insufficientKiFlashTimer > 0,
              onTap: () => game.onSkill2(),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 84,
            child: _PvpActionButton(
              size: 52,
              icon: s3.icon,
              label: s3.shortLabel,
              hotkey: isDesktopOrWeb ? '3' : null,
              color: s3.color,
              cooldownRemaining: p.skill3VisualCd,
              maxCooldown: s3.cooldown,
              hasEnoughKi: p.currentKi >= s3.kiCost,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2838),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      phrase.text,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () {
                _safeSetState(() {
                  _showQuickChatMenu = !_showQuickChatMenu;
                });
              },
              icon: const Icon(Icons.chat_bubble_rounded, size: 16),
              label: const Text('QUICK CHAT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            if (GamePlatformHelper.isDesktopOrWeb) ...[
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E2838),
                  foregroundColor: Colors.amberAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  _safeSetState(() => _showTouchControls = !_showTouchControls);
                },
                icon: Icon(_showTouchControls ? Icons.gamepad : Icons.keyboard, size: 16),
                label: Text(
                  _showTouchControls ? 'NÚT ẢO: BẬT' : 'PHÍM PC: WASD',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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

    return GestureDetector(
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
                          progress: (cooldownRemaining / maxCooldown).clamp(0.0, 1.0),
                        ),
                        child: Center(
                          child: Text(
                            '${cooldownRemaining.toStringAsFixed(1)}s',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: size * 0.22,
                              fontWeight: FontWeight.w900,
                              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * progress,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CooldownArcPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// --- MODAL KẾT QUẢ TRẬN ĐẤU & TÍNH RANK THEO SAO (DÙNG CHUNG 1V1 • 2V2 • 4V4) ---
class _PvpResultModal extends StatelessWidget {
  final PvpMatchResult result;
  final VoidCallback onReturnToLobby;
  final VoidCallback onPlayAgain;
  final bool isSoloRoom;
  final int soloBetGold;

  const _PvpResultModal({
    required this.result,
    required this.onReturnToLobby,
    required this.onPlayAgain,
    this.isSoloRoom = false,
    this.soloBetGold = 0,
  });

  static Color _tierColor(String tier) {
    switch (tier) {
      case 'Thách Đấu':
        return const Color(0xFFFF1744);
      case 'Huyền Thoại':
        return const Color(0xFFE040FB);
      case 'Kim Cương':
        return const Color(0xFF00E5FF);
      case 'Bạch Kim':
        return const Color(0xFF00E676);
      case 'Vàng':
        return const Color(0xFFFFD700);
      case 'Bạc':
        return const Color(0xFFCFD8DC);
      default:
        return const Color(0xFFCD7F32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = result.isWinner ? 'CHIẾN THẮNG!' : 'THẤT BẠI!';
    final titleColor =
        result.isWinner ? const Color(0xFFFFD700) : const Color(0xFFFF1744);
    final newTierColor = _tierColor(result.newRankTier);
    final oldTierColor = _tierColor(result.oldRankTier);
    final starDeltaText = result.starDelta > 0
        ? '+${result.starDelta} ⭐'
        : (result.starDelta < 0 ? '${result.starDelta} ⭐' : '0 ⭐ (Bảo hộ Đồng)');
    final starDeltaColor = result.starDelta > 0
        ? const Color(0xFF00E676)
        : (result.starDelta < 0
            ? const Color(0xFFFF5252)
            : Colors.amberAccent);

    final nextTierName = PvpRankSystem.getNextTierName(
      result.newTotalStars,
      isTop10Challenger: result.isChallengerTop10,
    );

    final cutoffLegendaryStars = max(
      1,
      (result.top10CutoffStars ?? (PvpRankSystem.legendaryStartTotalStars + 1)) -
          PvpRankSystem.legendaryStartTotalStars,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        width: 430,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2235), Color(0xFF101522)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: titleColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: titleColor.withValues(alpha: 0.35),
              blurRadius: 30,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Tiêu đề Chiến Thắng / Thất Bại + Chế độ Đấu
              Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  isSoloRoom
                      ? 'PHÒNG ĐẤU TÙY CHỌN • TỈ SỐ HIỆP: ${result.playerRoundsWon} - ${result.opponentRoundsWon}'
                      : '${result.gameMode.title} • TỈ SỐ HIỆP: ${result.playerRoundsWon} - ${result.opponentRoundsWon}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (isSoloRoom) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C101A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: titleColor.withValues(alpha: 0.8),
                      width: 1.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        soloBetGold > 0
                            ? 'KẾT QUẢ PHÒNG ĐẤU CƯỢC VÀNG'
                            : 'PHÒNG ĐẤU TÙY CHỌN GIAO HỮU',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        soloBetGold == 0
                            ? '0 VÀNG (GIAO HỮU)'
                            : (result.isWinner
                                ? '+${result.goldReward} VÀNG LỜI (NHẬN ${soloBetGold + result.goldReward}G)'
                                : '${result.goldReward} VÀNG'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: soloBetGold == 0
                              ? Colors.cyanAccent
                              : (result.isWinner
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF5252)),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Phòng Solo Tự Chọn • Giữ nguyên Sao Rank & RP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
              // 2. KHUNG TIẾN TRÌNH RANK & NGÔI SAO (DÙNG CHUNG 1V1 • 2V2 • 4V4)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C101A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: newTierColor.withValues(alpha: 0.75),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: newTierColor.withValues(alpha: 0.18),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Nhãn Rank Chung 3 Chế Độ + Biến động Sao (+1 ⭐ / -1 ⭐)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'RANK CHUNG (1V1 • 2V2 • 4V4)',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: starDeltaColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: starDeltaColor),
                          ),
                          child: Text(
                            starDeltaText,
                            style: TextStyle(
                              color: starDeltaColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Huy hiệu Bậc Rank (Nếu đổi bậc thì hiện Rank Cũ -> Rank Mới)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (result.oldRankTier != result.newRankTier) ...[
                          RankBadge(
                            rankTier: result.oldRankTier,
                            size: 26,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            result.oldRankTier.toUpperCase(),
                            style: TextStyle(
                              color: oldTierColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              Icons.double_arrow_rounded,
                              color: Colors.amberAccent,
                              size: 18,
                            ),
                          ),
                        ],
                        RankBadge(
                          rankTier: result.newRankTier,
                          size: 46,
                          showGlow: true,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.newRankTier.toUpperCase(),
                              style: TextStyle(
                                color: newTierColor,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            if (result.serverRank != null)
                              Text(
                                'Hạng Server hiện tại: #${result.serverRank}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // HIỂN THỊ SAO TRỰC QUAN:
                    // - Từ Đồng đến Kim Cương: 3 Ngôi Sao (★ ★ ☆ - đủ 3 sao lên rank tiếp theo)
                    // - Từ Huyền Thoại đến Thách Đấu: Cộng sao tích lũy từ 0s -> Top 10 Server
                    if (!result.isLegendaryOrAbove) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          PvpRankSystem.starsPerStandardTier,
                          (idx) {
                            final filled = idx < result.newStarsInTier;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                filled
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                size: 34,
                                color: filled
                                    ? const Color(0xFFFFD700)
                                    : Colors.white24,
                                shadows: filled
                                    ? const [
                                        Shadow(
                                          color: Color(0xFFFFA000),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${result.newStarsInTier} / ${PvpRankSystem.starsPerStandardTier} SAO • Còn ${PvpRankSystem.starsPerStandardTier - result.newStarsInTier} sao để lên $nextTierName',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ] else ...[
                      // Bậc Huyền Thoại (0s+) -> Thách Đấu (Top 10 nhiều sao nhất server)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              newTierColor.withValues(alpha: 0.25),
                              Colors.amber.withValues(alpha: 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFFD700),
                            width: 1.4,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFD700),
                              size: 30,
                              shadows: [
                                Shadow(
                                  color: Color(0xFFFF8F00),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${result.newStarsInTier} SAO',
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        result.isChallengerTop10
                            ? '🏆 THÁCH ĐẤU ĐỈNH CAO — TOP #${result.serverRank ?? 1} NHIỀU SAO NHẤT SERVER!'
                            : 'Huyền Thoại cộng sao từ 0⭐ • Đạt Top 10 Server (≥ $cutoffLegendaryStars⭐) để lên THÁCH ĐẤU',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: result.isChallengerTop10
                              ? const Color(0xFFFF5252)
                              : const Color(0xFFE040FB),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ],

              // Banner Thăng Hạng / Giáng Hạng
              if (result.isPromotion) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amberAccent, width: 1.4),
                  ),
                  child: Text(
                    result.newRankTier == 'Thách Đấu'
                        ? '🔥 CHÚC MỪNG! BẠN ĐÃ LỌT TOP 10 SERVER — THĂNG HẠNG THÁCH ĐẤU!'
                        : '🎉 ĐỦ 3 SAO! CHÚC MỪNG BẠN ĐÃ THĂNG HẠNG: ${result.newRankTier.toUpperCase()}!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ] else if (result.isDemotion) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    '⚠️ BẠN ĐÃ LÙI BẬC RANK VỀ: ${result.newRankTier.toUpperCase()} (${result.newStarsInTier} ⭐)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 3. Thưởng Vàng & Tổng Sao Tích Lũy
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                          'SAO TÍCH LŨY',
                          style: TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        Text(
                          '${result.newTotalStars} ⭐ (${result.newRankPoints} RP)',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          isSoloRoom ? 'BIẾN ĐỘNG VÀNG' : 'THƯỞNG VÀNG',
                          style:
                              const TextStyle(color: Colors.white54, fontSize: 10.5),
                        ),
                        Text(
                          result.goldReward >= 0
                              ? '+${result.goldReward}'
                              : '${result.goldReward}',
                          style: TextStyle(
                            color: result.goldReward >= 0
                                ? Colors.amberAccent
                                : const Color(0xFFFF5252),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. Nút Điều Hướng
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
                    child: Text(isSoloRoom ? 'VỀ PHÒNG SOLO' : 'TÌM TRẬN TIẾP'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
