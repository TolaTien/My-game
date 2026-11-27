import 'dart:async';
import 'package:flutter/material.dart';
import '../models/database_models.dart';
import '../models/friend_party_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import '../registry/asset_registry.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/friend_party_service.dart';
import '../services/player_storage.dart';
import 'chat_ai_dialog.dart';
import 'friends_party_dialog.dart';
import 'game_play_screen.dart';
import 'lucky_wheel_dialog.dart';
import 'pvp_arena_screen.dart';
import 'settings_dialog.dart';
import 'shop_dialog.dart';
import 'solo_room_dialog.dart';
import 'widgets/edit_profile_dialog.dart';
import 'widgets/hero_showcase_painter.dart';
import 'widgets/lobby_friends_sidebar.dart';
import 'widgets/rank_badge.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isPvpMode = true;
  PvpGameMode _selectedPvpMode = PvpGameMode.solo1v1;
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _shimmerController;

  OverlayEntry? _partyInvitePopupOverlay;
  Timer? _partyInvitePopupTimer;

  OverlayEntry? _friendReqPopupOverlay;
  Timer? _friendReqPopupTimer;

  bool _isLaunchingPartyMatch = false;
  String? _lastLaunchedMatchRoomId;
  bool _isLaunchingSoloMatch = false;
  String? _lastLaunchedSoloMatchRoomId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Hiệu ứng thở / nhấp nhô nhẹ nhàng
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _breatheAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Hiệu ứng viền phát sáng nhấp nháy cho nút BẮT ĐẦU
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Vệt sáng quét ngang (Shimmer gleam) cho nút BẮT ĐẦU
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    // Tải dữ liệu người chơi, khôi phục bạn bè & bật trạng thái Online Realtime
    PlayerStorage.loadProfile().then((prof) {
      FriendPartyService.instance.initializeForCurrentUser(prof);
    });

    // Lắng nghe lời mời tổ đội & phản hồi từ bạn bè
    FriendPartyService.instance.incomingInviteNotifier
        .addListener(_handleIncomingInvite);
    FriendPartyService.instance.inviteResponseNotifier
        .addListener(_handleInviteResponse);

    // Lắng nghe yêu cầu kết bạn & phản hồi kết bạn
    FriendPartyService.instance.incomingFriendRequestPopupNotifier
        .addListener(_handleIncomingFriendRequestPopup);
    FriendPartyService.instance.friendRequestResponseNotifier
        .addListener(_handleFriendRequestResponse);

    // Lắng nghe trạng thái phòng tổ đội để đồng bộ chế độ & tự động ghép trận cho khách khi chủ phòng bấm Tìm Trận
    FriendPartyService.instance.partyNotifier
        .addListener(_handlePartyRoomChanged);
    FriendPartyService.instance.soloRoomNotifier
        .addListener(_handleSoloRoomChanged);

    // Bật Lobby BGM
    AudioService.instance.playBgm(BgmTrack.lobby);

    // Hiển thị lời mời đang chờ nếu đã nhận ngay trước khi màn sảnh mount xong
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleIncomingInvite();
      _handleIncomingFriendRequestPopup();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      FriendPartyService.instance.setOfflinePresence();
    } else if (state == AppLifecycleState.resumed) {
      FriendPartyService.instance.setOnlinePresence(PlayerStorage.currentProfile);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dismissPartyInvitePopup();
    _dismissFriendReqPopup();
    FriendPartyService.instance.incomingInviteNotifier
        .removeListener(_handleIncomingInvite);
    FriendPartyService.instance.inviteResponseNotifier
        .removeListener(_handleInviteResponse);
    FriendPartyService.instance.incomingFriendRequestPopupNotifier
        .removeListener(_handleIncomingFriendRequestPopup);
    FriendPartyService.instance.friendRequestResponseNotifier
        .removeListener(_handleFriendRequestResponse);
    FriendPartyService.instance.partyNotifier
        .removeListener(_handlePartyRoomChanged);
    FriendPartyService.instance.soloRoomNotifier
        .removeListener(_handleSoloRoomChanged);
    _breatheController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    AudioService.instance.stopBgm();
    super.dispose();
  }

  void _ensureLobbyBgmPlaying() {
    if (!AudioService.instance.isPlayingBgm && AudioService.instance.isBgmEnabled) {
      AudioService.instance.playBgm(BgmTrack.lobby);
    }
  }

  void _openLuckyWheel() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const LuckyWheelDialog(),
    );
  }

  void _openShop() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ShopDialog(),
    );
  }

  void _openLeaderboard(PlayerProfile profile) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _LeaderboardDialog(playerProfile: profile),
    );
  }

  void _openFriendsDialog({int initialTabIndex = 0}) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FriendsPartyDialog(
        initialMode: _selectedPvpMode,
        initialTabIndex: initialTabIndex,
        onStartPartyMatch: (mode) {
          setState(() {
            _isPvpMode = true;
            _selectedPvpMode = mode;
          });
          _startGame();
        },
      ),
    );
  }

  void _openSettings() {
    SettingsDialog.show(context);
  }

  void _openSoloRoomDialog() {
    SoloRoomDialog.show(context);
  }

  void _dismissPartyInvitePopup() {
    _partyInvitePopupTimer?.cancel();
    _partyInvitePopupTimer = null;
    _partyInvitePopupOverlay?.remove();
    _partyInvitePopupOverlay = null;
  }

  void _handleIncomingInvite() {
    final invite = FriendPartyService.instance.incomingInviteNotifier.value;
    if (invite == null || !mounted) return;

    FriendPartyService.instance.incomingInviteNotifier.value = null;
    _dismissPartyInvitePopup();
    AudioService.instance.playSfx(SfxSound.uiClick);

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PartyInvitePopupBanner(
        invite: invite,
        onAccept: () async {
          _dismissPartyInvitePopup();
          AudioService.instance.playSfx(SfxSound.uiClick);
          await FriendPartyService.instance.respondToInvitation(
            invite,
            accept: true,
          );
          if (mounted) {
            if (invite.isCustomRoom) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Đã vào Phòng Đấu ${invite.partyCode} cùng ${invite.fromName}!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.green.shade800,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              _openSoloRoomDialog();
              return;
            }
            setState(() {
              _isPvpMode = true;
              _selectedPvpMode = invite.mode;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Đã tham gia tổ đội ${invite.mode.shortLabel} cùng ${invite.fromName}!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.green.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onDecline: () async {
          _dismissPartyInvitePopup();
          AudioService.instance.playSfx(SfxSound.uiClick);
          await FriendPartyService.instance.respondToInvitation(
            invite,
            accept: false,
            reason: 'Người chơi đang bận leo Rank.',
          );
        },
        onClose: () {
          _dismissPartyInvitePopup();
          FriendPartyService.instance.dismissExpiredInvitation(invite);
        },
      ),
    );

    _partyInvitePopupOverlay = entry;
    overlay.insert(entry);
    _partyInvitePopupTimer = Timer(const Duration(seconds: 5), () {
      if (_partyInvitePopupOverlay == entry) {
        _dismissPartyInvitePopup();
        FriendPartyService.instance.dismissExpiredInvitation(invite);
      }
    });
  }

  void _handleInviteResponse() {
    final resp = FriendPartyService.instance.inviteResponseNotifier.value;
    if (resp == null || !mounted) return;

    FriendPartyService.instance.inviteResponseNotifier.value = null;

    final isAccepted = resp.status == 'accepted';

    AudioService.instance.playSfx(SfxSound.uiClick);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isAccepted
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: isAccepted
                  ? const Color(0xFF00E676)
                  : const Color(0xFFFF5252),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAccepted
                        ? '${resp.toName} ĐÃ THAM GIA TỔ ĐỘI!'
                        : '${resp.toName} ĐÃ TỪ CHỐI LỜI MỜI!',
                    style: TextStyle(
                      color: isAccepted
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAccepted
                        ? 'Đồng đội đã gia nhập sảnh chờ và sẵn sàng ghép trận.'
                        : (resp.declineReason ?? 'Bạn bè đang bận, hẹn trận sau!'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF101C38),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isAccepted
                ? const Color(0xFF00E676)
                : const Color(0xFFFF5252),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  void _dismissFriendReqPopup() {
    _friendReqPopupTimer?.cancel();
    _friendReqPopupTimer = null;
    _friendReqPopupOverlay?.remove();
    _friendReqPopupOverlay = null;
  }

  void _handleIncomingFriendRequestPopup() {
    final req =
        FriendPartyService.instance.incomingFriendRequestPopupNotifier.value;
    if (req == null || !mounted) return;

    FriendPartyService.instance.incomingFriendRequestPopupNotifier.value = null;
    _dismissFriendReqPopup();
    AudioService.instance.playSfx(SfxSound.uiClick);

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FriendRequestPopupBanner(
        request: req,
        onAccept: () async {
          _dismissFriendReqPopup();
          AudioService.instance.playSfx(SfxSound.uiClick);
          await FriendPartyService.instance
              .respondToFriendRequest(req, accept: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Đã đồng ý kết bạn với ${req.fromName} (${req.fromCode})!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.green.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onDecline: () async {
          _dismissFriendReqPopup();
          AudioService.instance.playSfx(SfxSound.uiClick);
          await FriendPartyService.instance
              .respondToFriendRequest(req, accept: false);
        },
        onClose: _dismissFriendReqPopup,
      ),
    );

    _friendReqPopupOverlay = entry;
    overlay.insert(entry);
    _friendReqPopupTimer = Timer(const Duration(seconds: 5), () {
      if (_friendReqPopupOverlay == entry) {
        _dismissFriendReqPopup();
      }
    });
  }

  void _handleFriendRequestResponse() {
    final resp =
        FriendPartyService.instance.friendRequestResponseNotifier.value;
    if (resp == null || !mounted) return;
    FriendPartyService.instance.friendRequestResponseNotifier.value = null;

    final isAccepted = resp.status == 'accepted';
    AudioService.instance.playSfx(SfxSound.uiClick);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isAccepted ? Icons.how_to_reg_rounded : Icons.person_off_rounded,
              color: isAccepted
                  ? const Color(0xFF00E676)
                  : const Color(0xFFFF5252),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isAccepted
                    ? '${resp.toName} [${resp.toCode}] đã ĐỒNG Ý kết bạn với bạn!'
                    : '${resp.toName} [${resp.toCode}] đã từ chối lời mời kết bạn.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF101C38),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleInviteFriendFromSidebar(FriendInfo friend) {
    AudioService.instance.playSfx(SfxSound.uiClick);

    // Chuyển đổi chế độ theo yêu cầu:
    // Nếu đang ở 1v1 hoặc PvE -> tự động chuyển sang 4v4
    // Còn nếu đang ở 2v2 hoặc 4v4 -> giữ im
    setState(() {
      _isPvpMode = true;
      if (_selectedPvpMode == PvpGameMode.solo1v1) {
        _selectedPvpMode = PvpGameMode.squad4v4;
      }
    });

    FriendPartyService.instance.sendPartyInvitation(
      friend,
      preferredMode: _selectedPvpMode,
    ).then((success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.send_rounded : Icons.warning_amber_rounded,
                color: success ? const Color(0xFF00E5FF) : const Color(0xFFFFB300),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success
                      ? 'Đã gửi lời mời tới ${friend.name}. Đang chờ phản hồi...'
                      : 'Tổ đội ${_selectedPvpMode.shortLabel} đã đủ người!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF142442),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: success ? const Color(0xFF00E5FF) : const Color(0xFFFFB300),
              width: 1.2,
            ),
          ),
        ),
      );
    });
  }

  void _openChatAi() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ChatAiDialog(),
    );
  }

  String? _lastPlayedMapId;

  void _handlePartyRoomChanged() {
    if (!mounted) return;
    final party = FriendPartyService.instance.partyNotifier.value;
    if (party == null) {
      _lastLaunchedMatchRoomId = null;
      return;
    }

    if (!_isPvpMode || _selectedPvpMode != party.mode) {
      setState(() {
        _isPvpMode = true;
        _selectedPvpMode = party.mode;
      });
    }

    final myCode = FriendPartyService.instance.effectivePlayerCode;
    final isLeader = party.isLeader(myCode);
    final matchRoomId = party.activeMatchRoomId;
    if (!isLeader &&
        (party.matchStatus == 'searching' || party.matchStatus == 'in_match') &&
        matchRoomId != null &&
        matchRoomId.isNotEmpty &&
        !_isLaunchingPartyMatch &&
        _lastLaunchedMatchRoomId != matchRoomId) {
      _isLaunchingPartyMatch = true;
      _lastLaunchedMatchRoomId = matchRoomId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _isLaunchingPartyMatch = false;
          return;
        }
        unawaited(AudioService.instance.stopBgm());
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PvpArenaScreen(
              initialMode: party.mode,
              partyRoom: party,
            ),
          ),
        );
        _isLaunchingPartyMatch = false;
        if (mounted) {
          AudioService.instance.playBgm(BgmTrack.lobby);
        }
      });
    }
  }

  void _handleSoloRoomChanged() {
    if (!mounted) return;
    final solo = FriendPartyService.instance.soloRoomNotifier.value;
    if (solo == null) {
      _lastLaunchedSoloMatchRoomId = null;
      return;
    }

    final matchRoomId = solo.activeMatchRoomId;
    if (solo.matchStatus == 'in_match' &&
        matchRoomId != null &&
        matchRoomId.isNotEmpty &&
        !_isLaunchingSoloMatch &&
        _lastLaunchedSoloMatchRoomId != matchRoomId) {
      _isLaunchingSoloMatch = true;
      _lastLaunchedSoloMatchRoomId = matchRoomId;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _isLaunchingSoloMatch = false;
          return;
        }
        unawaited(AudioService.instance.stopBgm());
        final navResult = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => PvpArenaScreen(
              initialMode: PvpGameMode.solo1v1,
              soloRoom: solo,
            ),
          ),
        );
        _isLaunchingSoloMatch = false;
        if (mounted) {
          AudioService.instance.playBgm(BgmTrack.lobby);
          await PlayerStorage.loadProfile();
          setState(() {});
          if (navResult == 'reopen_solo' &&
              mounted &&
              FriendPartyService.instance.soloRoomNotifier.value != null) {
            _openSoloRoomDialog();
          }
        }
      });
    }
  }

  void _startGame() async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final party = FriendPartyService.instance.partyNotifier.value;
    final myCode = FriendPartyService.instance.effectivePlayerCode;

    if (party != null && party.members.isNotEmpty) {
      if (!party.isLeader(myCode)) {
        // Khách chỉ bấm Sẵn Sàng, chỉ Chủ Phòng mới có quyền bấm Tìm Trận
        await FriendPartyService.instance.toggleMyReadyState();
        return;
      }
      if (!party.areAllMembersReady) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hãy chờ tất cả thành viên trong phòng ở trạng thái SẴN SÀNG!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Tắt nhạc sảnh chờ ngay khi bắt đầu vào trận
    await AudioService.instance.stopBgm();
    if (!mounted) return;

    // Bốc ngẫu nhiên map chiến trường mới (tránh lặp lại map vừa chơi)
    final randomMap =
        GameAssetRegistry.instance.getRandomMap(excludeId: _lastPlayedMapId);
    _lastPlayedMapId = randomMap.id;

    PartyRoomState? startedParty;
    if (_isPvpMode && party != null && party.members.isNotEmpty && party.isLeader(myCode)) {
      startedParty = await FriendPartyService.instance
          .startPartyMatchmaking(mapId: randomMap.id);
      _lastLaunchedMatchRoomId = startedParty?.activeMatchRoomId;
    }

    int? selectedPveFloor;
    if (!_isPvpMode) {
      final savedFloor = PlayerStorage.currentProfile.pveCurrentFloor;
      if (savedFloor > 1) {
        final choice = await _showPveFloorResumeDialog(
          savedFloor: savedFloor,
          highestFloor: PlayerStorage.currentProfile.pveHighestFloor,
        );
        if (choice == null || !mounted) return;
        if (choice == 1) {
          await PlayerStorage.resetPveToFloorOne();
        }
        selectedPveFloor = choice;
      } else {
        selectedPveFloor = 1;
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _isPvpMode
            ? PvpArenaScreen(
                initialMode: startedParty?.mode ?? _selectedPvpMode,
                partyRoom: startedParty,
              )
            : GamePlayScreen(
                initialMapConfig: randomMap,
                initialFloor: selectedPveFloor,
              ),
      ),
    );
    if (mounted) {
      // Khi quay lại sảnh chờ: tiếp tục phát lặp lại nhạc sảnh
      AudioService.instance.playBgm(BgmTrack.lobby);
      await PlayerStorage.loadProfile();
      setState(() {});
    }
  }

  /// Hộp thoại chọn tiếp tục tầng PvE đã chinh phục hoặc đánh lại từ Tầng 1.
  Future<int?> _showPveFloorResumeDialog({
    required int savedFloor,
    required int highestFloor,
  }) {
    return showDialog<int>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF10192D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF40E0FF), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF40E0FF).withValues(alpha: 0.28),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.stairs_rounded,
                color: Color(0xFF40E0FF),
                size: 38,
              ),
              const SizedBox(height: 8),
              const Text(
                'TIẾN ĐỘ VƯỢT ẢI HẦM NGỤC',
                style: TextStyle(
                  color: Color(0xFF40E0FF),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bạn đang dừng ở Tầng $savedFloor (Kỷ lục cao nhất: Tầng $highestFloor).\nBạn muốn tiếp tục hay đánh lại từ Tầng 1?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'TIẾP TỤC TẦNG $savedFloor',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(savedFloor),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text(
                    'ĐÁNH LẠI TỪ TẦNG 1',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () => Navigator.of(dialogCtx).pop(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _designWidth = 1763.0;
  static const double _designHeight = 892.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ensureLobbyBgmPlaying(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1633),
        body: ValueListenableBuilder<PlayerProfile>(
        valueListenable: PlayerStorage.profileNotifier,
        builder: (context, profile, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;

              Positioned posBox(
                double x1,
                double y1,
                double x2,
                double y2,
                Widget child,
              ) {
                return Positioned(
                  left: (x1 / _designWidth) * w,
                  top: (y1 / _designHeight) * h,
                  width: ((x2 - x1) / _designWidth) * w,
                  height: ((y2 - y1) / _designHeight) * h,
                  child: child,
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. HÌNH NỀN SẢNH CHỜ SCI-FI (assets/images/ui/sanhcho.png)
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/ui/sanhcho.png',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                    ),
                  ),

                  // 2. NHÂN VẬT ĐỨNG TRÊN BỆ ĐÀI TRUNG TÂM DƯỚI LUỒNG SÁNG
                  Align(
                    alignment: const Alignment(0.0, 0.14),
                    child: _buildCenterStage(profile),
                  ),

                  // 3. GÓC TRÊN TRÁI: KHUNG HỒ SƠ & RANK
                  posBox(
                    16,
                    7,
                    332,
                    100,
                    _buildProfileCard(profile),
                  ),

                  // 3.5 GÓC TRÊN PHẢI: NÚT CÀI ĐẶT HỆ THỐNG
                  posBox(
                    1324,
                    14,
                    1392,
                    84,
                    _buildSettingsHeaderButton(),
                  ),

                  // 4. GÓC TRÊN PHẢI: 2 Ô TIỀN TỆ (XU & VÀNG)
                  posBox(
                    1400,
                    14,
                    1566,
                    84,
                    _buildCurrencyPill(
                      leading: _buildXuCoinIcon(),
                      value: profile.xu,
                      valueColor: Colors.white,
                      plusBgColor: const Color(0xFFE68A00),
                      onTap: _openShop,
                    ),
                  ),
                  posBox(
                    1574,
                    14,
                    1741,
                    84,
                    _buildCurrencyPill(
                      leading: _buildGoldCoinIcon(),
                      value: profile.gold,
                      valueColor: const Color(0xFFFFF59D),
                      plusBgColor: const Color(0xFFE68A00),
                      onTap: _openShop,
                    ),
                  ),

                  // 5. SIDEBAR TRÁI: CÁC NÚT CHỨC NĂNG SẢNH CHỜ
                  // 5.1 VÒNG QUAY
                  posBox(
                    18,
                    118,
                    178,
                    214,
                    _buildSciFiSidebarButton(
                      label: 'VÒNG QUAY',
                      borderColor: const Color(0xFFFFB300),
                      glowColor: const Color(0xFFFFA000),
                      bgColors: const [Color(0xFF282B3A), Color(0xFF1B1E2B)],
                      iconWidget: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.casino_rounded,
                          color: Color(0xFF2B1B00),
                          size: 28,
                        ),
                      ),
                      onTap: _openLuckyWheel,
                    ),
                  ),

                  // 5.2 CỬA HÀNG
                  posBox(
                    18,
                    224,
                    178,
                    318,
                    _buildSciFiSidebarButton(
                      label: 'CỬA HÀNG',
                      borderColor: const Color(0xFF29D8FF),
                      glowColor: const Color(0xFF00B0FF),
                      bgColors: const [Color(0xFF142D52), Color(0xFF0C1D38)],
                      iconWidget: const Icon(
                        Icons.shopping_bag_rounded,
                        color: Color(0xFF4DD0E1),
                        size: 38,
                      ),
                      onTap: _openShop,
                    ),
                  ),

                  // 5.3 BẠN BÈ (FRIENDS)
                  posBox(
                    18,
                    322,
                    178,
                    420,
                    _buildSciFiSidebarButton(
                      label: 'BẠN BÈ',
                      borderColor: const Color(0xFF29D8FF),
                      glowColor: const Color(0xFF00B0FF),
                      bgColors: const [Color(0xFF142D52), Color(0xFF0C1D38)],
                      iconWidget: ValueListenableBuilder<List<FriendRequest>>(
                        valueListenable: FriendPartyService
                            .instance.incomingFriendRequestsNotifier,
                        builder: (context, reqs, _) {
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(
                                Icons.people_alt_rounded,
                                color: Color(0xFF4DD0E1),
                                size: 40,
                              ),
                              if (reqs.isNotEmpty)
                                Positioned(
                                  top: -4,
                                  right: -8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '${reqs.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      onTap: () {
                        final hasReqs = FriendPartyService
                            .instance.incomingFriendRequestsNotifier.value
                            .isNotEmpty;
                        _openFriendsDialog(initialTabIndex: hasReqs ? 1 : 0);
                      },
                    ),
                  ),

                  // 5.4 CHAT AI
                  posBox(
                    18,
                    426,
                    178,
                    521,
                    _buildSciFiSidebarButton(
                      label: 'CHAT AI',
                      borderColor: const Color(0xFF29D8FF),
                      glowColor: const Color(0xFF00B0FF),
                      bgColors: const [Color(0xFF142D52), Color(0xFF0C1D38)],
                      iconWidget: const Icon(
                        Icons.smart_toy_rounded,
                        color: Color(0xFF4DD0E1),
                        size: 38,
                      ),
                      onTap: _openChatAi,
                    ),
                  ),

                  // 5.5 RANKING
                  posBox(
                    18,
                    528,
                    178,
                    624,
                    _buildSciFiSidebarButton(
                      label: 'RANKING',
                      borderColor: const Color(0xFF29D8FF),
                      glowColor: const Color(0xFF00B0FF),
                      bgColors: const [Color(0xFF142D52), Color(0xFF0C1D38)],
                      iconWidget: const Icon(
                        Icons.bar_chart_rounded,
                        color: Color(0xFFFFA726),
                        size: 40,
                      ),
                      onTap: () => _openLeaderboard(profile),
                    ),
                  ),

                  // 5.6 PHÒNG SOLO / TÙY CHỌN 4V4
                  posBox(
                    18,
                    632,
                    178,
                    728,
                    _buildSciFiSidebarButton(
                      label: 'PHÒNG SOLO',
                      borderColor: const Color(0xFFFFB300),
                      glowColor: const Color(0xFFFF8F00),
                      bgColors: const [Color(0xFF2B2112), Color(0xFF1A140B)],
                      iconWidget: const Icon(
                        Icons.sports_kabaddi_rounded,
                        color: Color(0xFFFFD54F),
                        size: 38,
                      ),
                      onTap: _openSoloRoomDialog,
                    ),
                  ),


                  // 5.7 SIDEBAR BÊN PHẢI: DANH SÁCH BẠN BÈ ONLINE/OFFLINE & NÚT MỜI TỔ ĐỘI "+"
                  posBox(
                    1380,
                    96,
                    1746,
                    645,
                    LobbyFriendsSidebar(
                      isPvpMode: _isPvpMode,
                      selectedPvpMode: _selectedPvpMode,
                      onInviteFriend: _handleInviteFriendFromSidebar,
                      onOpenFriendsDialog: () => _openFriendsDialog(initialTabIndex: 0),
                      onOpenFriendRequests: () => _openFriendsDialog(initialTabIndex: 1),
                      onOpenSoloRoom: _openSoloRoomDialog,
                    ),
                  ),

                  // 6. GÓC PHẢI DƯỚI: 3 HÀNG NÚT CHẾ ĐỘ & TÌM TRẬN RANK ĐÚNG NHƯ HÌNH
                  // 6.1 Thanh chọn 1V1 ĐẤU ĐƠN | 2V2 SONG ĐẤU | 4V4 QUÂN ĐOÀN (chỉ hiện khi chọn PvP)
                  if (_isPvpMode)
                    posBox(
                      1332,
                      653,
                      1746,
                      704,
                      _buildPvpModeTabsPill(),
                    ),

                  // 6.2 Thanh hiển thị & chuyển đổi CHẾ ĐỘ: ĐẤU TRƯỜNG PVP (RANK 1v1) (i)
                  posBox(
                    1332,
                    706,
                    1738,
                    756,
                    _buildModeStatusPill(),
                  ),

                  // 6.3 Nút lớn hình lục giác vàng cam: ⚔️ TÌM TRẬN RANK >>
                  posBox(
                    1315,
                    766,
                    1752,
                    872,
                    _buildMainActionButton(),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

  // --- 1. KHUNG HỒ SƠ GÓC TRÊN TRÁI (THEO MẪU SANHCHO.PNG) ---
  Widget _buildProfileCard(PlayerProfile profile) {
    return GestureDetector(
      onTap: () {
        AudioService.instance.playSfx(SfxSound.uiClick);
        EditProfileDialog.show(context, profile);
      },
      child: CustomPaint(
        painter: _SciFiProfilePillPainter(
          borderColor: const Color(0xFF29E5FF),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 18, 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 300,
              child: Row(
                children: [
                  // Avatar tròn tím viền trắng đúng như hình
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFB366FF), Color(0xFF7C3AED)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      border: Border.all(color: Colors.white, width: 2.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9C4DFF).withValues(alpha: 0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Tên người chơi & Bậc Rank
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile.playerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '[${profile.playerCode}]',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF29D8FF),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            RankBadge(
                              rankTier: profile.rankTier,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${profile.rankDisplayLabel.toUpperCase()} • ${profile.rankPoints} RP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFFD54F),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 26,
                    color: Color(0xFF29E5FF),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- 2. CÁC Ô TIỀN TỆ GÓC TRÊN PHẢI (XU, VÀNG) ---
  Widget _buildXuCoinIcon() {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFB300), width: 2.5),
        color: const Color(0xFF2B1D00),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFFFCA28),
          ),
        ),
      ),
    );
  }

  Widget _buildGoldCoinIcon() {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFFFA000)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Text(
          'S',
          style: TextStyle(
            color: Color(0xFF3E2700),
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyPill({
    required Widget leading,
    required int value,
    required Color valueColor,
    required Color plusBgColor,
    required VoidCallback onTap,
  }) {
    final formatted = value
        .toString()
        .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF142A4F), Color(0xFF0C1B36)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: const Color(0xFF29E5FF),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.28),
              blurRadius: 10,
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 8),
              Text(
                formatted,
                style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: plusBgColor,
                  boxShadow: [
                    BoxShadow(
                      color: plusBgColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsHeaderButton() {
    return GestureDetector(
      onTap: _openSettings,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF142A4F), Color(0xFF0C1B36)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(36),
          border: Border.all(
            color: const Color(0xFF29E5FF),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.28),
              blurRadius: 10,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.settings_rounded,
            color: Color(0xFF00E5FF),
            size: 26,
          ),
        ),
      ),
    );
  }

  // --- 3. BỆ ĐÀI TRUNG TÂM & NHÂN VẬT ---
  Widget _buildCenterStage(PlayerProfile profile) {
    return ValueListenableBuilder<PartyRoomState?>(
      valueListenable: FriendPartyService.instance.partyNotifier,
      builder: (context, party, _) {
        if (party == null || party.members.isEmpty) {
          return _buildSingleHeroStage(profile);
        }
        return _buildPartyHeroesStage(profile, party);
      },
    );
  }

  Widget _buildSingleHeroStage(PlayerProfile profile) {
    final heroInfo = _getHeroDisplayInfo(profile.selectedHeroId);

    return AnimatedBuilder(
      animation: _breatheAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _breatheAnimation.value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile.selectedCompanionId != null) ...[
                _buildMiniBadge(
                  icon: Icons.smart_toy_rounded,
                  label: 'TRỢ THỦ AI',
                  color: Colors.cyanAccent,
                ),
                const SizedBox(height: 6),
              ],

              HeroShowcaseWidget(
                heroId: profile.selectedHeroId,
                companionId: profile.selectedCompanionId,
                themeColor: heroInfo.themeColor,
              ),

              const SizedBox(height: 6),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF142A4F), Color(0xFF0B1830)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF29E5FF).withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.25),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      heroInfo.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.6,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: heroInfo.themeColor,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${heroInfo.title} • LV.${profile.getHeroLevel()}/100',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD54F),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPartyHeroesStage(PlayerProfile profile, PartyRoomState party) {
    final myCode =
        FriendPartyService.instance.effectivePlayerCode.toUpperCase();
    final isMeLeader = party.leaderCode.toUpperCase() == myCode;

    final List<_LobbyHeroMemberData> stageMembers = [];

    // 1. CHỦ PHÒNG (LEADER)
    if (isMeLeader) {
      stageMembers.add(_LobbyHeroMemberData(
        heroId: profile.selectedHeroId,
        playerName: profile.playerName,
        heroLevel: profile.getHeroLevel(),
        rankTier: profile.rankTier,
        isLeader: true,
        isMe: true,
      ));
    } else {
      stageMembers.add(_LobbyHeroMemberData(
        heroId: party.leaderHeroId,
        playerName: party.leaderName,
        heroLevel: party.leaderHeroLevel,
        rankTier: 'Kim Cương',
        isLeader: true,
        isMe: false,
      ));
    }

    // 2. CÁC ĐỒNG ĐỘI (MEMBERS)
    for (final member in party.members) {
      final isMemberMe = member.code.toUpperCase() == myCode;
      stageMembers.add(_LobbyHeroMemberData(
        heroId: isMemberMe ? profile.selectedHeroId : member.selectedHeroId,
        playerName: isMemberMe ? profile.playerName : member.name,
        heroLevel: isMemberMe ? profile.getHeroLevel() : member.heroLevel,
        rankTier: isMemberMe ? profile.rankTier : member.rankTier,
        isLeader: false,
        isMe: isMemberMe,
        isReady: party.isMemberReady(member.code),
      ));
    }

    final count = stageMembers.length;
    double heroWidth = 215;
    double heroHeight = 235;
    double spacing = 16;
    if (count == 3) {
      heroWidth = 180;
      heroHeight = 205;
      spacing = 12;
    } else if (count >= 4) {
      heroWidth = 160;
      heroHeight = 185;
      spacing = 8;
    }

    return AnimatedBuilder(
      animation: _breatheAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _breatheAnimation.value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // BANNER TIÊU ĐỀ TỔ ĐỘI & NÚT RỜI ĐỘI
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xF0102446), Color(0xF00A1832)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF00E5FF),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TỔ ĐỘI: ${party.partyCode}  •  ${party.mode.title.toUpperCase()} ($count/${party.maxSlots})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        AudioService.instance.playSfx(SfxSound.uiClick);
                        FriendPartyService.instance.leaveParty();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFF5252).withValues(alpha: 0.8),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              color: Color(0xFFFF5252),
                              size: 12,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'RỜI ĐỘI',
                              style: TextStyle(
                                color: Color(0xFFFF5252),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // HÀNG CÁC NHÂN VẬT ĐỨNG CẠNH NHAU
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: stageMembers.asMap().entries.map((entry) {
                  final member = entry.value;
                  final heroInfo = _getHeroDisplayInfo(member.heroId);

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: spacing / 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // HUY HIỆU VAI TRÒ
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: member.isLeader
                                ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: member.isLeader
                                  ? const Color(0xFFFFD700)
                                  : const Color(0xFF00E5FF),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                member.isLeader
                                    ? Icons.military_tech_rounded
                                    : Icons.shield_rounded,
                                size: 11,
                                color: member.isLeader
                                    ? const Color(0xFFFFD700)
                                    : const Color(0xFF00E5FF),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                member.isLeader
                                    ? 'CHỦ PHÒNG${member.isMe ? ' (BẠN)' : ''}'
                                    : '${member.isReady ? 'SẴN SÀNG' : 'CHƯA SẴN SÀNG'}${member.isMe ? ' (BẠN)' : ''}',
                                style: TextStyle(
                                  color: member.isLeader
                                      ? const Color(0xFFFFD700)
                                      : (member.isReady
                                          ? const Color(0xFF00E676)
                                          : const Color(0xFFFFB74D)),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // CANVAS SHOWCASE NHÂN VẬT
                        HeroShowcaseWidget(
                          heroId: member.heroId,
                          companionId: member.isMe ? profile.selectedCompanionId : null,
                          themeColor: heroInfo.themeColor,
                          width: heroWidth,
                          height: heroHeight,
                        ),

                        const SizedBox(height: 4),

                        // THẺ TÊN & CẤP ĐỘ NHÂN VẬT
                        Container(
                          width: heroWidth * 0.95,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: member.isMe
                                  ? [
                                      const Color(0xFF1E3A6E),
                                      const Color(0xFF102347)
                                    ]
                                  : [
                                      const Color(0xFF142442),
                                      const Color(0xFF0C1628)
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: member.isMe
                                  ? const Color(0xFFFFD54F)
                                  : heroInfo.themeColor.withValues(alpha: 0.6),
                              width: member.isMe ? 1.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (member.isMe
                                        ? const Color(0xFFFFD54F)
                                        : heroInfo.themeColor)
                                    .withValues(alpha: 0.2),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                member.playerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  color: member.isMe
                                      ? const Color(0xFFFFD54F)
                                      : Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${heroInfo.name} • LV.${member.heroLevel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1E3A).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. NÚT SIDEBAR SCI-FI BÊN TRÁI (VÒNG QUAY, CỬA HÀNG, TỔ ĐỘI, CHAT AI, RANKING) ---
  Widget _buildSciFiSidebarButton({
    required String label,
    required Color borderColor,
    required Color glowColor,
    required List<Color> bgColors,
    required Widget iconWidget,
    required VoidCallback onTap,
    String? badgeText,
    bool badgeAlignTopCenter = false,
  }) {
    final topPad = badgeText != null ? 8.0 : 0.0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: topPad,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: bgColors,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconWidget,
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (badgeText != null)
            Positioned(
              top: 0,
              right: badgeAlignTopCenter ? null : 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFC62828)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white70, width: 1.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- 5. GÓC PHẢI DƯỚI: 3 HÀNG NÚT CHẾ ĐỘ & TÌM TRẬN RANK ĐÚNG NHƯ SANHCHO.PNG ---
  Widget _buildPvpModeTabsPill() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172844), Color(0xFF0E1B31)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFB38F40),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: PvpGameMode.values.map((mode) {
          final selected = _isPvpMode && _selectedPvpMode == mode;
          return Expanded(
            child: GestureDetector(
              key: Key('lobby_pvp_mode_${mode.shortLabel.toLowerCase()}'),
              onTap: () {
                AudioService.instance.playSfx(SfxSound.uiClick);
                final party = FriendPartyService.instance.partyNotifier.value;
                final myCode = FriendPartyService.instance.effectivePlayerCode;
                if (party != null && !party.isLeader(myCode)) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chỉ Chủ Phòng mới có thể đổi chế độ đấu!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                setState(() {
                  _isPvpMode = true;
                  _selectedPvpMode = mode;
                });
                if (party != null &&
                    party.isLeader(myCode) &&
                    mode != PvpGameMode.solo1v1) {
                  FriendPartyService.instance.createOrUpdateParty(mode: mode);
                }
              },
              child: Container(
                height: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: [Color(0xFFFFD54F), Color(0xFFF59E0B)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    mode.title.toUpperCase(),
                    style: TextStyle(
                      color: selected ? const Color(0xFF1F1200) : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModeStatusPill() {
    return GestureDetector(
      onTap: () {
        AudioService.instance.playSfx(SfxSound.uiClick);
        final party = FriendPartyService.instance.partyNotifier.value;
        final myCode = FriendPartyService.instance.effectivePlayerCode;
        if (party != null && !party.isLeader(myCode)) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bạn đang ở trong Tổ Đội, chỉ Chủ Phòng mới đổi được chế độ!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        setState(() {
          _isPvpMode = !_isPvpMode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF172742), Color(0xFF0E1A2F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: const Color(0xFF3A5F94),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _isPvpMode
                  ? Icons.emoji_events_rounded
                  : Icons.sports_kabaddi_rounded,
              size: 20,
              color: const Color(0xFFFFB300),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _isPvpMode
                      ? 'CHẾ ĐỘ: ĐẤU TRƯỜNG PVP (RANK ${_selectedPvpMode.shortLabel})'
                      : 'CHẾ ĐỘ: VƯỢT ẢI HẦM NGỤC (PVE • TẦNG ${PlayerStorage.currentProfile.pveCurrentFloor})',
                  style: TextStyle(
                    color: _isPvpMode
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFF40E0FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF40C4FF), Color(0xFF1E88E5)],
                ),
                border: Border.all(color: Colors.white70, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF29B6F6).withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'i',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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

  Widget _buildMainActionButton() {
    return ValueListenableBuilder<PartyRoomState?>(
      valueListenable: FriendPartyService.instance.partyNotifier,
      builder: (context, party, _) {
        final myCode = FriendPartyService.instance.effectivePlayerCode;
        final isPartyGuest = party != null && !party.isLeader(myCode);
        final isGuestReady = isPartyGuest && party.isMemberReady(myCode);

        final buttonLabel = isPartyGuest
            ? (isGuestReady ? 'SẴN SÀNG' : 'CHƯA SẴN SÀNG')
            : (_isPvpMode ? 'TÌM TRẬN RANK' : 'BẮT ĐẦU');

        return AnimatedBuilder(
          animation: Listenable.merge([_pulseAnimation, _shimmerController]),
          builder: (context, child) {
            return GestureDetector(
              key: const Key('lobby_main_action_button'),
              onTap: _startGame,
              child: CustomPaint(
                painter: _SciFiHexButtonPainter(
                  pulse: _pulseAnimation.value,
                  shimmerProgress: _shimmerController.value,
                  isReadyGreen: isPartyGuest && isGuestReady,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isPartyGuest)
                          Icon(
                            isGuestReady
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 32,
                            color: Colors.white,
                          )
                        else
                          CustomPaint(
                            size: const Size(34, 34),
                            painter: _CrossedSwordsIconPainter(),
                          ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              buttonLabel,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.5,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Color(0xFF5D2900),
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            if (isPartyGuest)
                              Text(
                                isGuestReady
                                    ? 'CHỜ CHỦ PHÒNG TÌM TRẬN'
                                    : 'BẤM ĐỂ SẴN SÀNG',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white70,
                                  letterSpacing: 0.8,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          isPartyGuest
                              ? (isGuestReady
                                  ? Icons.hourglass_top_rounded
                                  : Icons.touch_app_rounded)
                              : Icons.keyboard_double_arrow_right_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  _HeroDisplayInfo _getHeroDisplayInfo(String id) {
    switch (id) {
      case 'nova':
      case 'nova_blade':
        return const _HeroDisplayInfo(
          name: 'Nova Blade (NOVA-07)',
          title: 'Chiến Binh Neon Song Kiếm',
          themeColor: Color(0xFF18FFFF),
          icon: Icons.flash_on_rounded,
        );
      case 'shadow':
      case 'shadow_01':
        return const _HeroDisplayInfo(
          name: 'Shadow (SHADOW-01)',
          title: 'Sát Thủ Hư Không',
          themeColor: Color(0xFFE040FB),
          icon: Icons.flare_rounded,
        );
      case 'ember_02':
      case 'ember':
        return const _HeroDisplayInfo(
          name: 'Ember (EMBER-02)',
          title: 'Phù Thủy Hỏa Cầu',
          themeColor: Color(0xFFFF6D00),
          icon: Icons.local_fire_department_rounded,
        );
      case 'valeria':
        return const _HeroDisplayInfo(
          name: 'Pháp Sư Valeria',
          title: 'Pháp Sư Băng Hỏa Nguyên Tố (Asset 3)',
          themeColor: Color(0xFF40C4FF),
          icon: Icons.ac_unit_rounded,
        );
      case 'garrick':
        return const _HeroDisplayInfo(
          name: 'Chiến Binh Garrick',
          title: 'Stone Guardian Cổ Đại (Asset 3)',
          themeColor: Color(0xFFFFD700),
          icon: Icons.fort_rounded,
        );
      case 'ranger':
        return const _HeroDisplayInfo(
          name: 'Xạ Thủ Ranger',
          title: 'Cung Thủ Ánh Sáng Tầm Xa',
          themeColor: Color(0xFF00E676),
          icon: Icons.gps_fixed_rounded,
        );
      case 'tanker':
        return const _HeroDisplayInfo(
          name: 'Hiệp Sĩ Tanker',
          title: 'Hộ Vệ Hoàng Gia Bất Diệt',
          themeColor: Color(0xFF00B0FF),
          icon: Icons.security_rounded,
        );
      case 'ninja':
        return const _HeroDisplayInfo(
          name: 'Ninja Sát Thủ',
          title: 'Ám Sát Bóng Đêm Chí Mạng',
          themeColor: Color(0xFFAB47BC),
          icon: Icons.flash_on_rounded,
        );
      case 'george':
      default:
        return const _HeroDisplayInfo(
          name: 'George',
          title: 'Chiến Binh Búa Sấm Sét',
          themeColor: Color(0xFFFF9800),
          icon: Icons.shield_sharp,
        );
    }
  }
}

class _LobbyHeroMemberData {
  final String heroId;
  final String playerName;
  final int heroLevel;
  final String rankTier;
  final bool isLeader;
  final bool isMe;
  final bool isReady;

  const _LobbyHeroMemberData({
    required this.heroId,
    required this.playerName,
    required this.heroLevel,
    required this.rankTier,
    required this.isLeader,
    required this.isMe,
    this.isReady = true,
  });
}

class _HeroDisplayInfo {
  final String name;
  final String title;
  final Color themeColor;
  final IconData icon;

  const _HeroDisplayInfo({
    required this.name,
    required this.title,
    required this.themeColor,
    required this.icon,
  });
}

/// Bảng Xếp Hạng Rank Modal
class _LeaderboardDialog extends StatelessWidget {
  final PlayerProfile playerProfile;

  const _LeaderboardDialog({required this.playerProfile});

  static Color _getRankColor(String tier) {
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
        return const Color(0xFFE0E0E0);
      default:
        return const Color(0xFFCD7F32);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 420),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF222838), Color(0xFF121622)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.7),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.emoji_events_rounded,
                        color: Colors.amberAccent, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'BẢNG XẾP HẠNG CHIẾN BINH (RANK)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.amberAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text(
                'Rank chung 1v1 • 2v2 • 4v4 | Thắng +1 ⭐ | Đồng → Kim Cương: 3 ⭐/bậc | Huyền Thoại: 0 ⭐+ | Thách Đấu: Top 10 Server',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Danh sách Top người chơi từ DatabaseService (Live stream)
            Expanded(
              child: StreamBuilder<List<LeaderboardEntry>>(
                stream: DatabaseService.instance.streamTopLeaderboard(limit: 20),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.amberAccent),
                    );
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text(
                        'Chưa có dữ liệu bảng xếp hạng',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final rank = entry.rankNumber;
                      final name = entry.name;
                      final tier = entry.rankTier;
                      final rp = entry.rankPoints;
                      final color = _getRankColor(tier);
                      final isTop3 = rank <= 3;
                      final isTop10Challenger = rank <= 10 && tier == 'Thách Đấu';
                      final isLocal = entry.isLocalPlayer;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isLocal
                              ? Colors.amberAccent.withValues(alpha: 0.2)
                              : (isTop3
                                  ? color.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isLocal
                                ? Colors.amberAccent
                                : (isTop3
                                    ? color.withValues(alpha: 0.6)
                                    : Colors.white12),
                            width: isLocal ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: isLocal
                                      ? Colors.amberAccent
                                      : (isTop10Challenger ? color : Colors.white70),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isLocal
                                            ? Colors.amberAccent
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (isLocal) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'BẠN',
                                        style: TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isTop10Challenger) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF1744)
                                            .withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFFFF1744)
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      child: const Text(
                                        'TOP 10',
                                        style: TextStyle(
                                          color: Color(0xFFFF5252),
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            RankBadge(rankTier: tier, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              tier,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.starDisplayText,
                                style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$rp RP',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Hàng hiển thị vị trí của người chơi hiện tại
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: playerProfile.rankColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: playerProfile.rankColor,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'BẠN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      playerProfile.playerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  RankBadge(rankTier: playerProfile.rankTier, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    playerProfile.rankDisplayLabel,
                    style: TextStyle(
                      color: playerProfile.rankColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${playerProfile.rankPoints} RP',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vẽ khung hồ sơ góc trên trái bo tròn bên trái, vát mũi nhọn lục giác bên phải như sanhcho.png
class _SciFiProfilePillPainter extends CustomPainter {
  final Color borderColor;

  const _SciFiProfilePillPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final tipOffset = size.height * 0.34;
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - tipOffset, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - tipOffset, size.height)
      ..lineTo(r, size.height)
      ..arcToPoint(
        Offset(r, 0),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..close();

    final glowPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, glowPaint);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF142A4F), Color(0xFF0C1A34)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SciFiProfilePillPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}

/// Vẽ nút TÌM TRẬN RANK hình lục giác vát cạnh vàng cam phát sáng đúng như sanhcho.png
class _SciFiHexButtonPainter extends CustomPainter {
  final double pulse;
  final double shimmerProgress;
  final bool isReadyGreen;

  const _SciFiHexButtonPainter({
    required this.pulse,
    required this.shimmerProgress,
    this.isReadyGreen = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cut = size.height * 0.34;
    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height / 2)
      ..close();

    // Hào quang phát sáng xung quanh nút
    final outerGlow = Paint()
      ..color = (isReadyGreen
              ? const Color(0xFF00E676)
              : const Color(0xFFFFA000))
          .withValues(alpha: 0.45 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * pulse
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, outerGlow);

    // Nền gradient vàng cam hoặc xanh ngọc (khi Khách Sẵn Sàng)
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: isReadyGreen
            ? const [
                Color(0xFF00E676),
                Color(0xFF00B248),
                Color(0xFF00695C),
              ]
            : const [
                Color(0xFFFFC107),
                Color(0xFFF57C00),
                Color(0xFFE65100),
              ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fillPaint);

    // Hiệu ứng vệt sáng quét ngang
    canvas.save();
    canvas.clipPath(path);
    final shimmerX = -size.width * 0.4 + shimmerProgress * (size.width * 1.6);
    final shimmerRect = Rect.fromLTWH(shimmerX, 0, size.width * 0.25, size.height);
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.28),
          Colors.transparent,
        ],
      ).createShader(shimmerRect);
    canvas.drawRect(shimmerRect, shimmerPaint);
    canvas.restore();

    // Viền sáng bóng
    final borderPaint = Paint()
      ..color = isReadyGreen ? const Color(0xFFA7FFEB) : const Color(0xFFFFE082)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SciFiHexButtonPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.shimmerProgress != shimmerProgress ||
      oldDelegate.isReadyGreen != isReadyGreen;
}

/// Vẽ biểu tượng Song Kiếm Giao Nhau (⚔️) màu trắng trên nút TÌM TRẬN RANK
class _CrossedSwordsIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bladePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;

    final hiltPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Thanh kiếm 1: Từ dưới-trái lên trên-phải
    canvas.drawLine(Offset(w * 0.16, h * 0.84), Offset(w * 0.84, h * 0.16), bladePaint);
    // Chắn kiếm 1
    canvas.drawLine(Offset(w * 0.18, h * 0.62), Offset(w * 0.38, h * 0.82), hiltPaint);

    // Thanh kiếm 2: Từ dưới-phải lên trên-trái
    canvas.drawLine(Offset(w * 0.84, h * 0.84), Offset(w * 0.16, h * 0.16), bladePaint);
    // Chắn kiếm 2
    canvas.drawLine(Offset(w * 0.82, h * 0.62), Offset(w * 0.62, h * 0.82), hiltPaint);
  }

  @override
  bool shouldRepaint(covariant _CrossedSwordsIconPainter oldDelegate) => false;
}

/// Pop-up thông báo yêu cầu kết bạn hiển thị trong 5 giây ở phía trên màn hình
class _FriendRequestPopupBanner extends StatefulWidget {
  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onClose;

  const _FriendRequestPopupBanner({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });

  @override
  State<_FriendRequestPopupBanner> createState() =>
      _FriendRequestPopupBannerState();
}

class _FriendRequestPopupBannerState extends State<_FriendRequestPopupBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 470,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF152544), Color(0xFF0A1426)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF29D8FF), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E5FF)),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: Color(0xFF00E5FF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'LỜI MỜI KẾT BẠN MỚI',
                                style: TextStyle(
                                  color: Color(0xFF29D8FF),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: widget.request.fromName,
                                      style: const TextStyle(
                                        color: Color(0xFFFFD54F),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' [${widget.request.fromCode}] (${widget.request.fromRankTier}) muốn kết bạn với bạn!',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                            side: const BorderSide(color: Color(0xFFFF5252)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          onPressed: widget.onDecline,
                          child: const Text(
                            'TỪ CHỐI',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: const Color(0xFF062412),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          onPressed: widget.onAccept,
                          child: const Text(
                            'ĐỒNG Ý',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (_, _) {
                      return LinearProgressIndicator(
                        value: 1.0 - _progressController.value,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00E5FF),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pop-up thông báo lời mời vào tổ đội hiển thị trong 5 giây ở phía trên màn hình
class _PartyInvitePopupBanner extends StatefulWidget {
  final PartyInvitation invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onClose;

  const _PartyInvitePopupBanner({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });

  @override
  State<_PartyInvitePopupBanner> createState() =>
      _PartyInvitePopupBannerState();
}

class _PartyInvitePopupBannerState extends State<_PartyInvitePopupBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 540),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF152544), Color(0xFF0A1426)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00E676), width: 1.8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00E676).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E676)),
                          ),
                          child: const Icon(
                            Icons.group_add_rounded,
                            color: Color(0xFF00E676),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.invite.isCustomRoom
                                          ? 'LỜI MỜI PHÒNG ĐẤU TÙY CHỌN'
                                          : 'LỜI MỜI VÀO TỔ ĐỘI',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E5FF)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFF00E5FF),
                                      ),
                                    ),
                                    child: Text(
                                      widget.invite.mode.shortLabel.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF00E5FF),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: widget.invite.fromName,
                                      style: const TextStyle(
                                        color: Color(0xFFFFD54F),
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' [${widget.invite.fromCode}] mời bạn vào phòng ${widget.invite.partyCode}!',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                            side: const BorderSide(color: Color(0xFFFF5252)),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          onPressed: widget.onDecline,
                          child: const Text(
                            'TỪ CHỐI',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E676),
                            foregroundColor: const Color(0xFF062412),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                          ),
                          onPressed: widget.onAccept,
                          child: const Text(
                            'THAM GIA',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white54,
                            size: 16,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (_, _) {
                      return LinearProgressIndicator(
                        value: 1.0 - _progressController.value,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF00E676),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


