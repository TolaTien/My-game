import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/database_models.dart';
import '../../models/friend_party_models.dart';
import '../../models/pvp_match.dart';
import '../../services/audio_service.dart';
import '../../services/friend_party_service.dart';
import '../../services/player_storage.dart';
import 'edit_profile_dialog.dart';
import 'hero_showcase_painter.dart';
import 'rank_badge.dart';

/// Chuyển đổi một dòng Bảng Xếp Hạng thành đối tượng hồ sơ công khai [FriendInfo]
FriendInfo buildFriendInfoFromLeaderboard(LeaderboardEntry entry) {
  final cleanCode = entry.playerCode.trim().toUpperCase();
  return FriendInfo(
    code: cleanCode,
    name: entry.name,
    rankPoints: entry.rankPoints,
    rankStars: entry.rankStars,
    rankTier: entry.rankTier,
    selectedHeroId: entry.heroId,
    heroLevel: entry.heroLevel,
    isOnline: false,
    statusText: 'Hạng #${entry.rankNumber} Server',
    totalMatches: entry.totalMatches,
    totalWins: entry.totalWins,
    unlockedHeroCount: entry.unlockedHeroCount,
    pveHighestFloor: entry.pveHighestFloor,
    isChallengerTop10: entry.rankNumber <= 10 && entry.rankTier == 'Thách Đấu',
    serverRank: entry.rankNumber,
    winRateText: entry.winRate,
  );
}

class _HeroDisplayMeta {
  final String name;
  final String title;
  final Color themeColor;
  final IconData icon;

  const _HeroDisplayMeta({
    required this.name,
    required this.title,
    required this.themeColor,
    required this.icon,
  });
}

_HeroDisplayMeta _resolveHeroMeta(String heroId) {
  switch (heroId) {
    case 'nova':
    case 'nova_blade':
      return const _HeroDisplayMeta(
        name: 'Nova Blade',
        title: 'Chiến Binh Neon Song Kiếm',
        themeColor: Color(0xFF18FFFF),
        icon: Icons.flash_on_rounded,
      );
    case 'shadow':
    case 'shadow_01':
      return const _HeroDisplayMeta(
        name: 'Shadow',
        title: 'Sát Thủ Hư Không',
        themeColor: Color(0xFFE040FB),
        icon: Icons.flare_rounded,
      );
    case 'ember':
    case 'ember_02':
      return const _HeroDisplayMeta(
        name: 'Ember',
        title: 'Phù Thủy Hỏa Cầu',
        themeColor: Color(0xFFFF6D00),
        icon: Icons.local_fire_department_rounded,
      );
    case 'valeria':
      return const _HeroDisplayMeta(
        name: 'Pháp Sư Valeria',
        title: 'Pháp Sư Băng Hỏa Nguyên Tố',
        themeColor: Color(0xFF40C4FF),
        icon: Icons.ac_unit_rounded,
      );
    case 'garrick':
      return const _HeroDisplayMeta(
        name: 'Chiến Binh Garrick',
        title: 'Hộ Vệ Đá Cổ Đại',
        themeColor: Color(0xFFFFD700),
        icon: Icons.fort_rounded,
      );
    case 'ranger':
      return const _HeroDisplayMeta(
        name: 'Xạ Thủ Ranger',
        title: 'Cung Thủ Ánh Sáng Tầm Xa',
        themeColor: Color(0xFF00E676),
        icon: Icons.gps_fixed_rounded,
      );
    case 'tanker':
      return const _HeroDisplayMeta(
        name: 'Hiệp Sĩ Tanker',
        title: 'Hộ Vệ Hoàng Gia Bất Diệt',
        themeColor: Color(0xFF00B0FF),
        icon: Icons.security_rounded,
      );
    case 'ninja':
      return const _HeroDisplayMeta(
        name: 'Ninja Sát Thủ',
        title: 'Ám Sát Bóng Đêm Chí Mạng',
        themeColor: Color(0xFFAB47BC),
        icon: Icons.flash_on_rounded,
      );
    case 'george':
    default:
      return const _HeroDisplayMeta(
        name: 'George',
        title: 'Chiến Binh Búa Sấm Sét',
        themeColor: Color(0xFFFF9800),
        icon: Icons.shield_sharp,
      );
  }
}

Color _resolveRankColor(String tier) {
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

FriendInfo _mergePublicProfile(FriendInfo base, FriendInfo? fetched) {
  if (fetched == null) return base;
  final useFetchedWinRate =
      fetched.totalMatches > 0 || (fetched.winRateText?.isNotEmpty ?? false);
  return fetched.copyWith(
    code: fetched.code.isNotEmpty ? fetched.code : base.code,
    isChallengerTop10: fetched.isChallengerTop10 || base.isChallengerTop10,
    serverRank: fetched.serverRank ?? base.serverRank,
    winRateText: useFetchedWinRate ? fetched.winRateText : base.winRateText,
  );
}

void _showActionSnackBar(
  BuildContext context, {
  required String message,
  required bool isSuccess,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            color: isSuccess ? const Color(0xFF00E676) : Colors.amberAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF142442),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Hộp thoại thao tác nhanh khi bấm vào một người chơi khác
/// (Tổ đội ở Sảnh Chờ, Bảng Xếp Hạng Rank, Phòng Solo, Danh sách Bạn bè):
/// - Nếu chưa kết bạn: hiện nút [KẾT BẠN] + nút [XEM PROFILE]
/// - Nếu đã là bạn bè: hiện nhãn [ĐÃ LÀ BẠN BÈ] + nút [XEM PROFILE]
class PlayerQuickActionPopup extends StatefulWidget {
  final FriendInfo initialTarget;
  final BuildContext hostContext;

  const PlayerQuickActionPopup({
    super.key,
    required this.initialTarget,
    required this.hostContext,
  });

  static Future<void> show(BuildContext context, FriendInfo target) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    if (FriendPartyService.instance.isSelfPlayer(
      code: target.code,
      name: target.name,
    )) {
      return EditProfileDialog.show(context, PlayerStorage.currentProfile);
    }

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => PlayerQuickActionPopup(
        initialTarget: target,
        hostContext: context,
      ),
    );
  }

  @override
  State<PlayerQuickActionPopup> createState() => _PlayerQuickActionPopupState();
}

class _PlayerQuickActionPopupState extends State<PlayerQuickActionPopup> {
  late FriendInfo _target;
  bool _isSendingRequest = false;
  bool _requestSent = false;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _enrichFromDirectory();
  }

  Future<void> _enrichFromDirectory() async {
    final latest = await FriendPartyService.instance.lookupPublicProfile(
      code: _target.code,
      name: _target.name,
    );
    if (!mounted || latest == null) return;
    setState(() {
      _target = _mergePublicProfile(_target, latest);
    });
  }

  Future<void> _handleSendFriendRequest() async {
    if (_isSendingRequest || _requestSent) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() => _isSendingRequest = true);

    final query = _target.code.trim().isNotEmpty ? _target.code : _target.name;
    final res = await FriendPartyService.instance.sendFriendRequest(query);
    if (!mounted) return;

    setState(() => _isSendingRequest = false);
    final toastContext = widget.hostContext;
    final messenger = toastContext.mounted
        ? ScaffoldMessenger.maybeOf(toastContext)
        : ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    void showMsg(String message, {required bool isSuccess}) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isSuccess
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: isSuccess ? const Color(0xFF00E676) : Colors.amberAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF142442),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    switch (res.status) {
      case FriendRequestSendStatus.sent:
        setState(() => _requestSent = true);
        showMsg(
          'Đã gửi lời mời kết bạn tới ${_target.name}!',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.autoAccepted:
        showMsg(
          'Bạn và ${_target.name} đã trở thành bạn bè!',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.alreadyFriends:
        showMsg(
          'Bạn và ${_target.name} đã là bạn bè.',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.alreadySent:
        setState(() => _requestSent = true);
        showMsg(
          'Bạn đã gửi lời mời kết bạn tới ${_target.name} trước đó.',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.notFound:
        showMsg(
          'Không tìm thấy hồ sơ trực tuyến của ${_target.name} để gửi kết bạn.',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.isSelf:
        showMsg(
          'Không thể gửi lời mời kết bạn cho chính mình.',
          isSuccess: false,
        );
        break;
    }
  }

  void _openFullProfile() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final resolvedTarget = _target;
    final hostCtx = widget.hostContext;
    Navigator.of(context).pop();
    if (hostCtx.mounted) {
      PlayerProfileDialog.show(hostCtx, resolvedTarget);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heroMeta = _resolveHeroMeta(_target.selectedHeroId);
    final rankColor = _resolveRankColor(_target.rankTier);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF162748), Color(0xFF0C1628)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF29D8FF).withValues(alpha: 0.85),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29D8FF).withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: ValueListenableBuilder<List<FriendInfo>>(
              valueListenable: FriendPartyService.instance.friendsNotifier,
              builder: (context, _, _) {
                final isFriend = FriendPartyService.instance.isFriendPlayer(
                  code: _target.code,
                  name: _target.name,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Header người chơi
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: heroMeta.themeColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: heroMeta.themeColor.withValues(alpha: 0.7),
                                  width: 1.4,
                                ),
                              ),
                              child: Icon(
                                heroMeta.icon,
                                color: heroMeta.themeColor,
                                size: 24,
                              ),
                            ),
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: _target.isOnline
                                      ? const Color(0xFF00E676)
                                      : const Color(0xFF90A4AE),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF0C1628),
                                    width: 1.8,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _target.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (_target.code.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: const Color(0xFF00E5FF)
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Text(
                                        _target.code,
                                        style: const TextStyle(
                                          color: Color(0xFF40C4FF),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Flexible(
                                    child: Text(
                                      '${heroMeta.name} • Lv.${_target.heroLevel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white60,
                            size: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // 2. Dải thông tin Rank tóm tắt
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: rankColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: rankColor.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          RankBadge(
                            rankTier: _target.rankTier,
                            size: 32,
                            showGlow: false,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Rank ${_target.rankTier}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: rankColor,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${_target.rankPoints} RP • Tỉ lệ thắng ${_target.winRateDisplay}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isFriend)
                            Container(
                              key: const Key('quick_action_already_friend_badge'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E676)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF00E676)
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.how_to_reg_rounded,
                                    color: Color(0xFF00E676),
                                    size: 13,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'BẠN BÈ',
                                    style: TextStyle(
                                      color: Color(0xFF00E676),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 3. Hàng nút thao tác: KẾT BẠN (nếu chưa là bạn) + XEM PROFILE
                    Row(
                      children: [
                        if (!isFriend) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              key: const Key('quick_action_add_friend'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _requestSent
                                    ? const Color(0xFF1F385E)
                                    : const Color(0xFF00E676),
                                foregroundColor: _requestSent
                                    ? Colors.white70
                                    : const Color(0xFF032312),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 11,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              onPressed: (_isSendingRequest || _requestSent)
                                  ? null
                                  : _handleSendFriendRequest,
                              icon: _isSendingRequest
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF032312),
                                      ),
                                    )
                                  : Icon(
                                      _requestSent
                                          ? Icons.check_rounded
                                          : Icons.person_add_alt_1_rounded,
                                      size: 16,
                                    ),
                              label: Text(
                                _requestSent ? 'ĐÃ GỬI' : 'KẾT BẠN',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton.icon(
                            key: const Key('quick_action_view_profile'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0288D1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                                side: const BorderSide(
                                  color: Color(0xFF29D8FF),
                                  width: 1.2,
                                ),
                              ),
                            ),
                            onPressed: _openFullProfile,
                            icon: const Icon(Icons.badge_rounded, size: 16),
                            label: const Text(
                              'XEM PROFILE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
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

/// Hộp thoại hiển thị đầy đủ Hồ Sơ Công Khai (Public Profile) của một người chơi khác.
class PlayerProfileDialog extends StatefulWidget {
  final FriendInfo initialTarget;

  const PlayerProfileDialog({
    super.key,
    required this.initialTarget,
  });

  static Future<void> show(BuildContext context, FriendInfo target) {
    if (FriendPartyService.instance.isSelfPlayer(
      code: target.code,
      name: target.name,
    )) {
      return EditProfileDialog.show(context, PlayerStorage.currentProfile);
    }

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => PlayerProfileDialog(initialTarget: target),
    );
  }

  @override
  State<PlayerProfileDialog> createState() => _PlayerProfileDialogState();
}

class _PlayerProfileDialogState extends State<PlayerProfileDialog> {
  late FriendInfo _target;
  bool _isSendingRequest = false;
  bool _requestSent = false;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _enrichProfile();
  }

  Future<void> _enrichProfile() async {
    final fetched = await FriendPartyService.instance.lookupPublicProfile(
      code: _target.code,
      name: _target.name,
    );
    if (!mounted || fetched == null) return;
    setState(() {
      _target = _mergePublicProfile(_target, fetched);
    });
  }

  Future<void> _handleSendFriendRequest() async {
    if (_isSendingRequest || _requestSent) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() => _isSendingRequest = true);

    final query = _target.code.trim().isNotEmpty ? _target.code : _target.name;
    final res = await FriendPartyService.instance.sendFriendRequest(query);
    if (!mounted) return;

    setState(() => _isSendingRequest = false);
    switch (res.status) {
      case FriendRequestSendStatus.sent:
        setState(() => _requestSent = true);
        _showActionSnackBar(
          context,
          message: 'Đã gửi lời mời kết bạn tới ${_target.name}!',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.autoAccepted:
        _showActionSnackBar(
          context,
          message: 'Bạn và ${_target.name} đã trở thành bạn bè!',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.alreadyFriends:
        _showActionSnackBar(
          context,
          message: 'Bạn và ${_target.name} đã là bạn bè.',
          isSuccess: true,
        );
        break;
      case FriendRequestSendStatus.alreadySent:
        setState(() => _requestSent = true);
        _showActionSnackBar(
          context,
          message: 'Bạn đã gửi lời mời kết bạn tới ${_target.name} trước đó.',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.notFound:
        _showActionSnackBar(
          context,
          message:
              'Không tìm thấy hồ sơ trực tuyến của ${_target.name} để gửi kết bạn.',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.isSelf:
        break;
    }
  }

  Widget _buildHeroShowcaseCard(_HeroDisplayMeta heroMeta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            heroMeta.themeColor.withValues(alpha: 0.16),
            const Color(0xFF0A1426).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: heroMeta.themeColor.withValues(alpha: 0.55),
          width: 1.3,
        ),
      ),
      child: Row(
        children: [
          HeroShowcaseWidget(
            heroId: _target.selectedHeroId,
            themeColor: heroMeta.themeColor,
            width: 84,
            height: 92,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TƯỚNG ĐẠI DIỆN',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  heroMeta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: heroMeta.themeColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  heroMeta.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD54F).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFFFD54F).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        'LV.${_target.heroLevel}/100',
                        style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: (_target.isOnline
                                ? const Color(0xFF00E676)
                                : Colors.white54)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (_target.isOnline
                                  ? const Color(0xFF00E676)
                                  : Colors.white38)
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        _target.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _target.isOnline
                              ? const Color(0xFF00E676)
                              : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankCard() {
    final totalStars = _target.effectiveRankStars;
    final tierColor = _resolveRankColor(_target.rankTier);
    final starsInTier = PvpRankSystem.getStarsInTier(totalStars);
    final maxStars = PvpRankSystem.getMaxStarsForTier(totalStars);
    final nextTier = PvpRankSystem.getNextTierName(
      totalStars,
      isTop10Challenger: _target.isChallengerTop10,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.20),
            const Color(0xFF0A1426).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          RankBadge(
            rankTier: _target.rankTier,
            size: 66,
            showGlow: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'RANK ${_target.rankTier.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (_target.isChallengerTop10 &&
                        _target.serverRank != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1744),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOP #${_target.serverRank}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (maxStars != null) ...[
                  Row(
                    children: [
                      for (int i = 0; i < maxStars; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            i < starsInTier
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: i < starsInTier
                                ? const Color(0xFFFFD54F)
                                : Colors.white24,
                            size: 17,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$starsInTier/$maxStars Sao',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFD54F),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD54F),
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$starsInTier Sao Tích Lũy',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFD54F),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        '${_target.rankPoints} RP',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Kế tiếp: $nextTier',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, Color color, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.88;
    final heroMeta = _resolveHeroMeta(_target.selectedHeroId);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 490, maxHeight: maxDialogHeight),
        child: Container(
          key: const Key('player_profile_dialog'),
          padding: const EdgeInsets.all(20),
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
          child: SingleChildScrollView(
            child: ValueListenableBuilder<List<FriendInfo>>(
              valueListenable: FriendPartyService.instance.friendsNotifier,
              builder: (context, _, _) {
                final isFriend = FriendPartyService.instance.isFriendPlayer(
                  code: _target.code,
                  name: _target.name,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Tiêu đề
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF)
                                .withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.badge_rounded,
                            color: Color(0xFF00E5FF),
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'HỒ SƠ NGƯỜI CHƠI',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF29D8FF),
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 2. Tướng đại diện
                    _buildHeroShowcaseCard(heroMeta),
                    const SizedBox(height: 12),

                    // 3. Khung Bậc Rank
                    _buildRankCard(),
                    const SizedBox(height: 12),

                    // 4. Tên người chơi
                    _buildInfoTile(
                      icon: Icons.person_rounded,
                      iconColor: const Color(0xFF00E5FF),
                      label: 'TÊN NGƯỜI CHƠI',
                      value: _target.name,
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: (isFriend
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFF00E5FF))
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (isFriend
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFF00E5FF))
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          isFriend ? 'Bạn bè' : 'Chiến binh',
                          style: TextStyle(
                            color: isFriend
                                ? const Color(0xFF00E676)
                                : const Color(0xFF00E5FF),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    if (_target.code.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildInfoTile(
                        icon: Icons.fingerprint_rounded,
                        iconColor: const Color(0xFFFFD54F),
                        label: 'MÃ ID ĐỊNH DANH (MÃ KẾT BẠN)',
                        value: _target.code,
                        trailing: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            AudioService.instance.playSfx(SfxSound.uiClick);
                            Clipboard.setData(
                              ClipboardData(text: _target.code),
                            );
                            _showActionSnackBar(
                              context,
                              message: 'Đã sao chép mã ID: ${_target.code}',
                              isSuccess: true,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0288D1)
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF0288D1),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: Color(0xFF29D8FF),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'SAO CHÉP',
                                  style: TextStyle(
                                    color: Color(0xFF29D8FF),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // 5. Thống kê chiến đấu công khai (Không hiển thị Vàng / Xu riêng tư)
                    Row(
                      children: [
                        _buildStatChip(
                          Icons.emoji_events_rounded,
                          const Color(0xFF00E5FF),
                          'Tỉ lệ thắng',
                          _target.winRateDisplay,
                        ),
                        const SizedBox(width: 8),
                        _buildStatChip(
                          Icons.sports_esports_rounded,
                          const Color(0xFFFFD54F),
                          'Thắng / Trận',
                          _target.totalMatches > 0
                              ? '${_target.totalWins}/${_target.totalMatches}'
                              : '--',
                        ),
                        const SizedBox(width: 8),
                        _buildStatChip(
                          Icons.shield_rounded,
                          const Color(0xFF00E676),
                          'Tướng mở',
                          '${_target.unlockedHeroCount}',
                        ),
                        const SizedBox(width: 8),
                        _buildStatChip(
                          Icons.whatshot_rounded,
                          const Color(0xFFFF6D00),
                          'Kỷ lục PvE',
                          'Tầng ${_target.pveHighestFloor}',
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 6. Chân hộp thoại: Nút KẾT BẠN (nếu chưa kết bạn) + ĐÓNG
                    Row(
                      children: [
                        if (!isFriend) ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              key: const Key('profile_dialog_add_friend'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _requestSent
                                    ? const Color(0xFF1F385E)
                                    : const Color(0xFF00E676),
                                foregroundColor: _requestSent
                                    ? Colors.white70
                                    : const Color(0xFF032312),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: (_isSendingRequest || _requestSent)
                                  ? null
                                  : _handleSendFriendRequest,
                              icon: _isSendingRequest
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF032312),
                                      ),
                                    )
                                  : Icon(
                                      _requestSent
                                          ? Icons.check_rounded
                                          : Icons.person_add_alt_1_rounded,
                                      size: 17,
                                    ),
                              label: Text(
                                _requestSent ? 'ĐÃ GỬI KẾT BẠN' : 'KẾT BẠN',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A6E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(
                                  color: Color(0xFF29D8FF),
                                  width: 1.2,
                                ),
                              ),
                              elevation: 4,
                            ),
                            onPressed: () {
                              AudioService.instance.playSfx(SfxSound.uiClick);
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'ĐÓNG',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 1.2,
                                color: Color(0xFF29D8FF),
                              ),
                            ),
                          ),
                        ),
                      ],
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
