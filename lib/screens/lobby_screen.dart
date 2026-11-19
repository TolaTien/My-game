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
import '../core/hero_skin_style.dart';
import 'widgets/edit_profile_dialog.dart';
import 'widgets/hero_showcase_painter.dart';
import 'widgets/lobby_friends_sidebar.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin {
  bool _isPvpMode = true;
  PvpGameMode _selectedPvpMode = PvpGameMode.solo1v1;
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _shimmerController;
  bool _isShowingInviteDialog = false;

  @override
  void initState() {
    super.initState();

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

    // Tải dữ liệu người chơi và đồng bộ thư mục bạn bè
    PlayerStorage.loadProfile().then((prof) {
      FriendPartyService.instance.syncOwnProfileToDirectory(prof);
    });

    // Lắng nghe lời mời tổ đội & phản hồi từ bạn bè
    FriendPartyService.instance.incomingInviteNotifier
        .addListener(_handleIncomingInvite);
    FriendPartyService.instance.inviteResponseNotifier
        .addListener(_handleInviteResponse);

    // Bật Lobby BGM
    AudioService.instance.playBgm(BgmTrack.lobby);
  }

  @override
  void dispose() {
    FriendPartyService.instance.incomingInviteNotifier
        .removeListener(_handleIncomingInvite);
    FriendPartyService.instance.inviteResponseNotifier
        .removeListener(_handleInviteResponse);
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

  void _openAssetCodex() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _AssetCodexDialog(),
    );
  }

  void _openFriendsDialog() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FriendsPartyDialog(
        initialMode: _selectedPvpMode,
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

  void _handleIncomingInvite() {
    final invite = FriendPartyService.instance.incomingInviteNotifier.value;
    if (invite == null || !mounted || _isShowingInviteDialog) return;

    _isShowingInviteDialog = true;
    AudioService.instance.playSfx(SfxSound.uiClick);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF142442), Color(0xFF0C1628)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF29D8FF), width: 2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF29D8FF).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon & Tiêu đề
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00E5FF),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.group_add_rounded,
                        color: Color(0xFF00E5FF),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'LỜI MỜI VÀO TỔ ĐỘI',
                      style: TextStyle(
                        color: Color(0xFF29D8FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Nội dung lời mời
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                          children: [
                            TextSpan(
                              text: invite.fromName,
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: ' [${invite.fromCode}]',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const TextSpan(
                              text: '\nmuốn mời bạn tham gia tổ đội chiến đấu!',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B0FF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF00B0FF)),
                            ),
                            child: Text(
                              'CHẾ ĐỘ: ${invite.mode.title.toUpperCase()}',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber),
                            ),
                            child: Text(
                              'PHÒNG: ${invite.partyCode}',
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2 Nút: Từ chối / Tham gia
                Row(
                  children: [
                    // NÚT TỪ CHỐI
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color(0xFFFF5252),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          AudioService.instance.playSfx(SfxSound.uiClick);
                          Navigator.of(ctx).pop();
                          FriendPartyService.instance.respondToInvitation(
                            invite,
                            accept: false,
                            reason: 'Người chơi đang bận leo Rank.',
                          );
                        },
                        child: const Text(
                          'TỪ CHỐI',
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // NÚT THAM GIA
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: const Color(0xFF072412),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          AudioService.instance.playSfx(SfxSound.uiClick);
                          Navigator.of(ctx).pop();
                          await FriendPartyService.instance.respondToInvitation(
                            invite,
                            accept: true,
                          );
                          if (mounted) {
                            setState(() {
                              _isPvpMode = true;
                              _selectedPvpMode = invite.mode;
                            });
                          }
                        },
                        child: const Text(
                          'THAM GIA',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isShowingInviteDialog = false;
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

  void _startGame() async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    // Tắt nhạc sảnh chờ ngay khi bắt đầu vào trận
    await AudioService.instance.stopBgm();
    if (!mounted) return;

    // Bốc ngẫu nhiên map chiến trường mới (tránh lặp lại map vừa chơi)
    final randomMap =
        GameAssetRegistry.instance.getRandomMap(excludeId: _lastPlayedMapId);
    _lastPlayedMapId = randomMap.id;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _isPvpMode
            ? PvpArenaScreen(initialMode: _selectedPvpMode)
            : GamePlayScreen(initialMapConfig: randomMap),
      ),
    );
    if (mounted) {
      // Khi quay lại sảnh chờ: tiếp tục phát lặp lại nhạc sảnh
      AudioService.instance.playBgm(BgmTrack.lobby);
    }
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
          final canSpin = profile.canSpinToday();

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

                  // 5. SIDEBAR TRÁI: 5 NÚT CHỨC NĂNG ĐÚNG THEO ẢNH SANHCHO.PNG
                  // 5.1 VÒNG QUAY (QUAY NGAY)
                  posBox(
                    18,
                    108,
                    187,
                    220,
                    _buildSciFiSidebarButton(
                      label: 'VÒNG QUAY',
                      borderColor: const Color(0xFFFFB300),
                      glowColor: const Color(0xFFFFA000),
                      bgColors: const [Color(0xFF282B3A), Color(0xFF1B1E2B)],
                      badgeText: canSpin ? 'QUAY NGAY' : 'ĐÃ QUAY',
                      badgeAlignTopCenter: true,
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

                  // 5.3 TỔ ĐỘI / BẠN BÈ (FRIENDS)
                  posBox(
                    18,
                    322,
                    178,
                    420,
                    _buildSciFiSidebarButton(
                      label: 'TỔ ĐỘI',
                      borderColor: const Color(0xFF29D8FF),
                      glowColor: const Color(0xFF00B0FF),
                      bgColors: const [Color(0xFF142D52), Color(0xFF0C1D38)],
                      badgeText: 'BẠN',
                      badgeAlignTopCenter: false,
                      iconWidget: const Icon(
                        Icons.people_alt_rounded,
                        color: Color(0xFF4DD0E1),
                        size: 40,
                      ),
                      onTap: _openFriendsDialog,
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
                      onOpenFriendsDialog: _openFriendsDialog,
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
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit_rounded,
                              size: 13,
                              color: Color(0xFFFFD54F),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF26E6A6),
                              ),
                              child: Icon(
                                profile.rankIcon,
                                size: 10,
                                color: const Color(0xFF082218),
                              ),
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

  // --- 2. CÁC Ô TIỀN TỆ GÓC TRÊN PHẢI (XU, VÀNG, KIM CƯƠNG) ---
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
              if (profile.selectedCompanionId != null ||
                  HeroSkinStyle.resolve(profile.selectedHeroId, profile.selectedSkinId) != null) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (profile.selectedCompanionId != null)
                      _buildMiniBadge(
                        icon: Icons.smart_toy_rounded,
                        label: 'TRỢ THỦ AI',
                        color: Colors.cyanAccent,
                      ),
                    if (HeroSkinStyle.resolve(profile.selectedHeroId, profile.selectedSkinId) != null) ...[
                      const SizedBox(width: 8),
                      _buildMiniBadge(
                        icon: Icons.auto_awesome_rounded,
                        label: 'SKIN HUYỀN THOẠI',
                        color: const Color(0xFFFFD700),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
              ],

              HeroShowcaseWidget(
                heroId: profile.selectedHeroId,
                skinId: profile.selectedSkinId,
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
                                    : 'ĐỒNG ĐỘI${member.isMe ? ' (BẠN)' : ''}',
                                style: TextStyle(
                                  color: member.isLeader
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF00E5FF),
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
                          skinId: member.isMe ? profile.selectedSkinId : null,
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
                setState(() {
                  _isPvpMode = true;
                  _selectedPvpMode = mode;
                });
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
                      : 'CHẾ ĐỘ: VƯỢT ẢI HẦM NGỤC (PVE)',
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
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _shimmerController]),
      builder: (context, child) {
        return GestureDetector(
          onTap: _startGame,
          child: CustomPaint(
            painter: _SciFiHexButtonPainter(
              pulse: _pulseAnimation.value,
              shimmerProgress: _shimmerController.value,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(34, 34),
                      painter: _CrossedSwordsIconPainter(),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isPvpMode ? 'TÌM TRẬN RANK' : 'BẮT ĐẦU',
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
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.keyboard_double_arrow_right_rounded,
                      size: 32,
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
  }

  _HeroDisplayInfo _getHeroDisplayInfo(String id) {
    switch (id) {
      case 'kale':
      case 'kaelen':
        return const _HeroDisplayInfo(
          name: 'Kale (Kaelen)',
          title: 'Kiếm Khách Thunderblade',
          themeColor: Color(0xFF00E5FF),
          icon: Icons.bolt_rounded,
        );
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

  const _LobbyHeroMemberData({
    required this.heroId,
    required this.playerName,
    required this.heroLevel,
    required this.rankTier,
    required this.isLeader,
    required this.isMe,
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
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.amberAccent),
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

  const _SciFiHexButtonPainter({
    required this.pulse,
    required this.shimmerProgress,
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
      ..color = const Color(0xFFFFA000).withValues(alpha: 0.45 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * pulse
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, outerGlow);

    // Nền gradient vàng cam rực rỡ
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
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

    // Viền vàng sáng bóng
    final borderPaint = Paint()
      ..color = const Color(0xFFFFE082)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SciFiHexButtonPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.shimmerProgress != shimmerProgress;
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

/// Hộp thoại Thư Viện Concept Art & Thiết Kế Nhân Vật (Assets Codex)
class _AssetCodexDialog extends StatefulWidget {
  const _AssetCodexDialog();

  @override
  State<_AssetCodexDialog> createState() => _AssetCodexDialogState();
}

class _AssetCodexDialogState extends State<_AssetCodexDialog> {
  int _selectedSheet = 0;

  static const _sheets = [
    (
      title: 'Kaelen & Aegis-X9',
      subtitle: 'Kiếm Khách Lôi Quang & Tinh Linh Lôi Từ',
      assetPath: 'assets/images/asset_1.png',
      desc:
          'Concept Art chuẩn Golden-Cyber Fantasy: Kaelen dùng Song Kiếm Hoàng Kim & Lôi Quang (#00E5FF), đi kèm Trợ Thủ AI Aegis-X9 có kỹ năng Trường Trọng Lực Hoàng Kim.',
    ),
    (
      title: 'Sprite Sheet 4 Trạng Thái',
      subtitle: 'Idle • Run • Attack • Hit & HUD Mobile',
      assetPath: 'assets/images/asset_2.png',
      desc:
          'Bảng phân tách Layer bộ phận (Cape, Body, Dual Swords, Greaves), hoạt ảnh lướt Lôi Ảnh Trảm và cụm nút kỹ năng hình cánh cung 90°.',
    ),
    (
      title: 'Biệt Đội Liên Minh (2v2 / 4v4)',
      subtitle: 'Kaelen • Valeria • Garrick',
      assetPath: 'assets/images/asset_3.png',
      desc:
          'Bộ 3 chiến binh chủ lực cho chế độ Song Đấu 2v2 và Quân Đoàn 4v4: Kiếm Khách Kaelen, Xạ Thủ Nỏ Thần Valeria và Pháo Đài Khiên Tháp Garrick.',
    ),
    (
      title: 'Phế Tích Thần Điện Hoàng Kim',
      subtitle: 'Bản Đồ Sunken Golden Sanctum & Vòng Ma Trận',
      assetPath: 'assets/images/asset_4.png',
      desc:
          'Gạch đá cổ đại rạn nứt nạm mạch quặng Vàng ròng (#D4AF37), Vòng Ma Trận Bát Giác trung tâm và 4 Cổng Không Gian Hắc Ám.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sheet = _sheets[_selectedSheet];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 420),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2134), Color(0xFF0E1320)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 2),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: Color(0xFFFFD700), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'THƯ VIỆN CONCEPT ART & HƯỚNG DẪN NHÂN VẬT MỚI',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final current = PlayerStorage.currentProfile;
                    final unlockedHeroes = {...current.unlockedHeroIds, 'kaelen', 'valeria', 'garrick'}.toList();
                    final unlockedComps = {...current.unlockedCompanionIds, 'aegis_x9'}.toList();
                    await PlayerStorage.saveProfile(
                      current.copyWith(
                        unlockedHeroIds: unlockedHeroes,
                        selectedHeroId: 'kaelen',
                        unlockedCompanionIds: unlockedComps,
                        selectedCompanionId: 'aegis_x9',
                      ),
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text(
                    'TRẢI NGHIỆM KAELEN + AEGIS-X9',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Tabs chọn 4 tấm Concept Art
            Row(
              children: List.generate(_sheets.length, (idx) {
                final active = idx == _selectedSheet;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => setState(() => _selectedSheet = idx),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? const Color(0xFFFFD700) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          _sheets[idx].title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? const Color(0xFFFFD700) : Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.black54,
                        child: Image.asset(
                          sheet.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.image_not_supported, color: Colors.white38, size: 42),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sheet.subtitle,
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                sheet.desc,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
