import 'package:flutter/material.dart';
import '../../models/friend_party_models.dart';
import '../../models/pvp_match.dart';
import '../../services/audio_service.dart';
import '../../services/friend_party_service.dart';
import 'player_profile_inspector.dart';

class LobbyFriendsSidebar extends StatefulWidget {
  final bool isPvpMode;
  final PvpGameMode selectedPvpMode;
  final ValueChanged<FriendInfo> onInviteFriend;
  final VoidCallback onOpenFriendsDialog;
  final VoidCallback? onOpenFriendRequests;
  final VoidCallback? onOpenSoloRoom;

  const LobbyFriendsSidebar({
    super.key,
    required this.isPvpMode,
    required this.selectedPvpMode,
    required this.onInviteFriend,
    required this.onOpenFriendsDialog,
    this.onOpenFriendRequests,
    this.onOpenSoloRoom,
  });

  @override
  State<LobbyFriendsSidebar> createState() => _LobbyFriendsSidebarState();
}

class _LobbyFriendsSidebarState extends State<LobbyFriendsSidebar> {
  bool _isCollapsed = false;

  IconData _getHeroIcon(String heroId) {
    switch (heroId) {
      case 'nova_blade':
        return Icons.flash_on_rounded;
      case 'valeria':
        return Icons.ac_unit_rounded;
      case 'garrick':
        return Icons.fort_rounded;
      case 'shadow_01':
      case 'shadow':
        return Icons.flare_rounded;
      case 'ember_02':
      case 'ember':
        return Icons.local_fire_department_rounded;
      case 'ranger':
        return Icons.gps_fixed_rounded;
      case 'tanker':
        return Icons.security_rounded;
      case 'ninja':
        return Icons.flash_on_rounded;
      case 'george':
      default:
        return Icons.shield_sharp;
    }
  }

  Color _getHeroColor(String heroId) {
    switch (heroId) {
      case 'nova_blade':
        return const Color(0xFF18FFFF);
      case 'valeria':
        return const Color(0xFF40C4FF);
      case 'garrick':
        return const Color(0xFFFFD700);
      case 'shadow_01':
      case 'shadow':
        return const Color(0xFFE040FB);
      case 'ember_02':
      case 'ember':
        return const Color(0xFFFF6D00);
      case 'ranger':
        return const Color(0xFF00E676);
      case 'tanker':
        return const Color(0xFF00B0FF);
      case 'ninja':
        return const Color(0xFFAB47BC);
      case 'george':
      default:
        return const Color(0xFFFF9800);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsed) {
      return _buildCollapsedTab();
    }
    return _buildExpandedSidebar();
  }

  // --- NÚT THU GỌN MẢNH MAI BÊN PHẢI ---
  Widget _buildCollapsedTab() {
    return ValueListenableBuilder<List<FriendInfo>>(
      valueListenable: FriendPartyService.instance.friendsNotifier,
      builder: (context, friends, _) {
        final onlineCount = friends.where((f) => f.isOnline).length;

        return Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            onTap: () {
              AudioService.instance.playSfx(SfxSound.uiClick);
              setState(() => _isCollapsed = false);
            },
            child: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xF0101C38), Color(0xF0081024)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
                border: Border.all(
                  color: const Color(0xFF29D8FF).withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00B0FF).withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_left_rounded,
                    color: Color(0xFF29D8FF),
                    size: 24,
                  ),
                  const SizedBox(height: 6),
                  ValueListenableBuilder<List<FriendRequest>>(
                    valueListenable:
                        FriendPartyService.instance.incomingFriendRequestsNotifier,
                    builder: (context, reqs, _) {
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.people_alt_rounded,
                            color: Color(0xFF00E5FF),
                            size: 20,
                          ),
                          if (reqs.isNotEmpty)
                            Positioned(
                              top: -5,
                              right: -7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${reqs.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Chấm xanh online
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00E676)),
                    ),
                    child: Text(
                      '$onlineCount',
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const RotatedBox(
                    quarterTurns: 1,
                    child: Text(
                      'BẠN BÈ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- SIDEBAR MỞ RỘNG ĐẦY ĐỦ THÔNG TIN ---
  Widget _buildExpandedSidebar() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xF20F1D38), Color(0xF8081122)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF29D8FF).withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B0FF).withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // 1. THANH TIÊU ĐỀ SIDEBAR
            _buildHeader(),

            // 2. BANNER TRẠNG THÁI TỔ ĐỘI (NẾU CÓ)
            _buildPartyStatusBanner(),

            // 3. DANH SÁCH BẠN BÈ ONLINE & OFFLINE
            Expanded(
              child: ValueListenableBuilder<List<FriendInfo>>(
                valueListenable: FriendPartyService.instance.friendsNotifier,
                builder: (context, friends, _) {
                  final onlineFriends =
                      friends.where((f) => f.isOnline).toList();
                  final offlineFriends =
                      friends.where((f) => !f.isOnline).toList();

                  return ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    children: [
                      // SECTION 1: TRỰC TUYẾN
                      _buildSectionHeader(
                        title: 'TRỰC TUYẾN',
                        count: onlineFriends.length,
                        color: const Color(0xFF00E676),
                        icon: Icons.circle,
                      ),
                      const SizedBox(height: 4),
                      if (onlineFriends.isEmpty)
                        _buildEmptyLabel('Chưa có bạn bè nào online')
                      else
                        ...onlineFriends.map((f) => _buildFriendCard(f, true)),

                      const SizedBox(height: 10),

                      // SECTION 2: NGOẠI TUYẾN
                      _buildSectionHeader(
                        title: 'NGOẠI TUYẾN',
                        count: offlineFriends.length,
                        color: Colors.white38,
                        icon: Icons.circle_outlined,
                      ),
                      const SizedBox(height: 4),
                      if (offlineFriends.isEmpty)
                        _buildEmptyLabel('Không có bạn bè offline')
                      else
                        ...offlineFriends.map((f) => _buildFriendCard(f, false)),
                    ],
                  );
                },
              ),
            ),

            // 4. CHÂN SIDEBAR: NÚT TÌM KIẾM & KẾT BẠN
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // --- 1. HEADER ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF29D8FF).withValues(alpha: 0.25),
          ),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 390,
          child: Row(
            children: [
              const Icon(
                Icons.people_alt_rounded,
            color: Color(0xFF29D8FF),
            size: 18,
          ),
          const SizedBox(width: 7),
          const Text(
            'BẠN BÈ & TỔ ĐỘI',
            style: TextStyle(
              color: Color(0xFF29D8FF),
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),

          // Badge Online counter
          ValueListenableBuilder<List<FriendInfo>>(
            valueListenable: FriendPartyService.instance.friendsNotifier,
            builder: (context, friends, _) {
              final online = friends.where((f) => f.isOnline).length;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00E676).withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$online Online',
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // Nút thu gọn
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              AudioService.instance.playSfx(SfxSound.uiClick);
              setState(() => _isCollapsed = true);
            },
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Colors.white60,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  // --- 2. BANNER TRẠNG THÁI TỔ ĐỘI HOẶC PHÒNG SOLO ---
  Widget _buildPartyStatusBanner() {
    return ValueListenableBuilder<SoloDuelRoomState?>(
      valueListenable: FriendPartyService.instance.soloRoomNotifier,
      builder: (context, soloRoom, _) {
        if (soloRoom != null) {
          return Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFB300).withValues(alpha: 0.22),
                  const Color(0xFFFF6D00).withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: const Color(0xFFFFB300).withValues(alpha: 0.65),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'SOLO 1V1',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '#${soloRoom.roomCode} • Đội ${soloRoom.matchupLabel} (${soloRoom.totalPlayerCount}/8)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (widget.onOpenSoloRoom != null)
                  InkWell(
                    onTap: widget.onOpenSoloRoom,
                    child: const Text(
                      'Mở phòng ›',
                      style: TextStyle(
                        color: Color(0xFFFFD54F),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return ValueListenableBuilder<PartyRoomState?>(
          valueListenable: FriendPartyService.instance.partyNotifier,
          builder: (context, party, _) {
        if (party == null || party.members.isEmpty) {
          return Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF4DD0E1),
                  size: 13,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Bấm dấu + để mời bạn bè vào tổ đội 4v4',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final modeLabel = party.mode == PvpGameMode.squad4v4
            ? '4V4 QUÂN ĐOÀN'
            : party.mode == PvpGameMode.duo2v2
                ? '2V2 SONG ĐẤU'
                : '1V1';

        return Container(
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00B0FF).withValues(alpha: 0.22),
                const Color(0xFF00E5FF).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  modeLabel,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${party.currentMemberCount}/${party.maxSlots} người • #${party.partyCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onOpenFriendsDialog,
                child: const Text(
                  'Chi tiết ›',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
          },
        );
      },
    );
  }

  // --- TIÊU ĐỀ TỪNG MỤC (ONLINE / OFFLINE) ---
  Widget _buildSectionHeader({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2, left: 2, right: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 7, color: color),
            const SizedBox(width: 5),
            Text(
              '$title ($count)',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 9.5,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 10,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // --- THẺ BẠN BÈ (CÓ NÚT DẤU + CHO ONLINE) ---
  Widget _buildFriendCard(FriendInfo friend, bool isOnline) {
    final heroColor = _getHeroColor(friend.selectedHeroId);
    final heroIcon = _getHeroIcon(friend.selectedHeroId);

    return ValueListenableBuilder<PartyRoomState?>(
      valueListenable: FriendPartyService.instance.partyNotifier,
      builder: (context, party, _) {
        final isInParty =
            party != null && party.members.any((m) => m.code == friend.code);

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isOnline
                ? (isInParty
                    ? const Color(0xFF00B0FF).withValues(alpha: 0.12)
                    : const Color(0xFF162544).withValues(alpha: 0.6))
                : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isInParty
                  ? const Color(0xFF00E676).withValues(alpha: 0.5)
                  : isOnline
                      ? const Color(0xFF29D8FF).withValues(alpha: 0.25)
                      : Colors.white10,
              width: isInParty ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar nhân vật + Thông tin (Bấm để xem Profile bạn bè)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => PlayerQuickActionPopup.show(context, friend),
                  child: Row(
                    children: [
                      // Avatar nhân vật + Chấm online
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: heroColor.withValues(alpha: isOnline ? 0.2 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: heroColor.withValues(alpha: isOnline ? 0.5 : 0.2),
                              ),
                            ),
                            child: Icon(
                              heroIcon,
                              color: isOnline ? heroColor : Colors.white30,
                              size: 18,
                            ),
                          ),
                          Positioned(
                            bottom: -1,
                            right: -1,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFF757575),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF0D1B36),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),

                      // Thông tin tên, cấp, rank
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    friend.name,
                                    style: TextStyle(
                                      color: isOnline ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '[${friend.code}]',
                                    style: TextStyle(
                                      color: isOnline
                                          ? const Color(0xFF40C4FF)
                                          : Colors.white30,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 1.5),
                            Text(
                              isOnline
                                  ? 'Lv.${friend.heroLevel} • Rank ${friend.rankTier} • ${friend.statusText}'
                                  : friend.statusText,
                              style: TextStyle(
                                color: isOnline ? Colors.white60 : Colors.white30,
                                fontSize: 9,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // NÚT DẤU "+" DÀNH CHO BẠN BÈ ONLINE
              if (isOnline) ...[
                if (isInParty) ...[
                  // ĐÃ TRONG TỔ ĐỘI
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.7),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          color: Color(0xFF00E676),
                          size: 11,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'TRONG ĐỘI',
                          style: TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // NÚT "+" MỜI VÀO TỔ ĐỘI
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onInviteFriend(friend),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00E5FF), Color(0xFF0091EA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  // --- 4. CHÂN SIDEBAR (CHỈ HIỆN KHI CÓ YÊU CẦU KẾT BẠN) ---
  Widget _buildBottomBar() {
    return ValueListenableBuilder<List<FriendRequest>>(
      valueListenable:
          FriendPartyService.instance.incomingFriendRequestsNotifier,
      builder: (context, reqs, _) {
        if (reqs.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border(
              top: BorderSide(
                color: const Color(0xFF29D8FF).withValues(alpha: 0.2),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              onPressed: widget.onOpenFriendRequests ??
                  widget.onOpenFriendsDialog,
              child: Text(
                'YÊU CẦU KẾT BẠN (${reqs.length})',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
