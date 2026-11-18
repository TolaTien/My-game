import 'package:flutter/material.dart';
import '../models/friend_party_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import '../services/audio_service.dart';
import '../services/friend_party_service.dart';
import '../services/player_storage.dart';
import 'widgets/edit_profile_dialog.dart';
import 'widgets/hero_showcase_painter.dart';

class FriendsPartyDialog extends StatefulWidget {
  final PvpGameMode initialMode;
  final ValueChanged<PvpGameMode>? onStartPartyMatch;

  const FriendsPartyDialog({
    super.key,
    this.initialMode = PvpGameMode.duo2v2,
    this.onStartPartyMatch,
  });

  @override
  State<FriendsPartyDialog> createState() => _FriendsPartyDialogState();
}

class _FriendsPartyDialogState extends State<FriendsPartyDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _partyCodeController = TextEditingController();
  late PvpGameMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedMode = widget.initialMode == PvpGameMode.solo1v1
        ? PvpGameMode.duo2v2
        : widget.initialMode;
    FriendPartyService.instance.syncOwnProfileToDirectory(
      PlayerStorage.currentProfile,
    );
    if (FriendPartyService.instance.partyNotifier.value == null) {
      FriendPartyService.instance.createOrUpdateParty(mode: _selectedMode);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _partyCodeController.dispose();
    super.dispose();
  }

  void _showToast(String msg, {bool isSuccess = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor:
            isSuccess ? Colors.green.shade800 : Colors.orange.shade900,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleAddFriend() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    AudioService.instance.playSfx(SfxSound.uiClick);

    // Chặn ngay lập tức nếu người dùng nhập ID hoặc tên của chính mình
    if (FriendPartyService.instance.isSelfPlayer(code: query, name: query)) {
      _showToast('Không thể kết bạn với chính mình!', isSuccess: false);
      return;
    }

    final added =
        await FriendPartyService.instance.addFriendByCodeOrName(query);
    if (!mounted) return;
    if (added != null) {
      _searchController.clear();
      _showToast('Đã kết bạn với ${added.name} (${added.code})!');
    } else {
      if (FriendPartyService.instance.isSelfPlayer(code: query, name: query)) {
        _showToast('Không thể kết bạn với chính mình!', isSuccess: false);
      } else {
        _showToast('Không tìm thấy người chơi có mã hoặc tên "$query"!', isSuccess: false);
      }
    }
  }

  void _handleInviteToParty(FriendInfo friend) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final ok = FriendPartyService.instance.inviteFriendToParty(
      friend,
      preferredMode: _selectedMode,
    );
    if (ok) {
      _showToast('Đã mời ${friend.name} vào đội ${_selectedMode.shortLabel}!');
    } else {
      _showToast(
        'Đội ${_selectedMode.shortLabel} đã đủ người! Hãy chọn 4v4 hoặc xóa bớt thành viên.',
        isSuccess: false,
      );
    }
  }

  Future<void> _handleJoinPartyCode() async {
    final code = _partyCodeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    AudioService.instance.playSfx(SfxSound.uiClick);

    // 1. Chặn nếu nhập mã phòng hiện tại đang ở
    final active = FriendPartyService.instance.partyNotifier.value;
    if (active != null && active.partyCode.toUpperCase() == code) {
      _showToast('Bạn đang ở trong phòng $code này rồi!', isSuccess: false);
      return;
    }

    try {
      final party = await FriendPartyService.instance.joinPartyByCode(
        code,
        fallbackMode: _selectedMode,
      );
      if (!mounted) return;
      _partyCodeController.clear();
      _showToast('Đã gia nhập tổ đội ${party.partyCode} (${party.mode.shortLabel})!');
    } catch (e) {
      if (!mounted) return;
      final msg = e is ArgumentError
          ? e.message.toString()
          : (e is StateError ? e.message.toString() : 'Không thể gia nhập phòng: $e');
      _showToast(msg, isSuccess: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerProfile>(
      valueListenable: PlayerStorage.profileNotifier,
      builder: (context, profile, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 440),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF171E2E), Color(0xFF0E131D)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.65),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.people_alt_rounded,
                        color: Colors.amberAccent,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DANH SÁCH BẠN BÈ & TÌM KIẾM KẾT BẠN',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => EditProfileDialog.show(context, profile),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'MÃ ID CỦA BẠN: ${profile.playerCode}',
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.edit_rounded,
                                size: 13,
                                color: Color(0xFFFFD54F),
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'ĐỔI ID/TÊN',
                                style: TextStyle(
                                  color: Color(0xFFFFD54F),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                ),

                // Tabs
                Container(
                  height: 36,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'DANH SÁCH BẠN BÈ & KẾT BẠN'),
                      Tab(text: 'PHÒNG TỔ ĐỘI (PARTY 2V2 / 4V4)'),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsTab(),
                      _buildPartyTab(profile),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFriendsTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          // Thanh nhập mã ID kết bạn
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    onSubmitted: (_) => _handleAddFriend(),
                    decoration: InputDecoration(
                      hintText:
                          'Nhập Mã ID bạn bè (VD: GR7777) hoặc tên người chơi để kết bạn...',
                      hintStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                ),
                onPressed: _handleAddFriend,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text(
                  'KẾT BẠN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Mẹo kết bạn 2 tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.cyan.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF00E5FF), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kiểm thử 2 tab: Mở Tab 1 xem mã ID (ở góc trên phải), sang Tab 2 nhập mã đó và bấm KẾT BẠN! Bấm nút "ĐỔI ID/TÊN" để cài đặt nhanh Tab 1 và Tab 2.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Danh sách bạn bè
          Expanded(
            child: ValueListenableBuilder<List<FriendInfo>>(
              valueListenable: FriendPartyService.instance.friendsNotifier,
              builder: (context, friends, _) {
                return ListView.separated(
                  itemCount: friends.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final f = friends[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: f.isOnline
                              ? Colors.greenAccent.withValues(alpha: 0.35)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: f.isOnline
                                ? const Color(0xFF065F46)
                                : Colors.blueGrey.shade800,
                            child: Text(
                              f.name.characters.first.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      f.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Lv.${f.heroLevel}/100 • ${f.rankTier}',
                                        style: const TextStyle(
                                          color: Colors.cyanAccent,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${f.code} • Tướng: ${f.selectedHeroId.toUpperCase()} • ${f.statusText}',
                                  style: TextStyle(
                                    color: f.isOnline
                                        ? Colors.greenAccent
                                        : Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () {
                              _handleInviteToParty(f);
                              _tabController.animateTo(1);
                            },
                            icon: const Icon(Icons.group_add_rounded, size: 15),
                            label: const Text(
                              'MỜI VÀO TEAM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Xóa bạn',
                            onPressed: () =>
                                FriendPartyService.instance.removeFriend(f.code),
                            icon: const Icon(
                              Icons.person_remove_rounded,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyTab(PlayerProfile profile) {
    return ValueListenableBuilder<PartyRoomState?>(
      valueListenable: FriendPartyService.instance.partyNotifier,
      builder: (context, party, _) {
        final activeParty = party ??
            FriendPartyService.instance.createOrUpdateParty(
              mode: _selectedMode,
            );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              // Chế độ đội + Nhập mã đội
              Row(
                children: [
                  const Text(
                    'Chế độ Đội:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('2V2 SONG ĐẤU'),
                    selected: activeParty.mode == PvpGameMode.duo2v2,
                    selectedColor: Colors.amberAccent,
                    labelStyle: TextStyle(
                      color: activeParty.mode == PvpGameMode.duo2v2
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedMode = PvpGameMode.duo2v2);
                      FriendPartyService.instance.createOrUpdateParty(
                        mode: PvpGameMode.duo2v2,
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('4V4 QUÂN ĐOÀN'),
                    selected: activeParty.mode == PvpGameMode.squad4v4,
                    selectedColor: Colors.amberAccent,
                    labelStyle: TextStyle(
                      color: activeParty.mode == PvpGameMode.squad4v4
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (_) {
                      setState(() => _selectedMode = PvpGameMode.squad4v4);
                      FriendPartyService.instance.createOrUpdateParty(
                        mode: PvpGameMode.squad4v4,
                      );
                    },
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amberAccent),
                    ),
                    child: Text(
                      'MÃ PHÒNG: ${activeParty.partyCode}',
                      style: const TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Các slot thành viên trong tổ đội
              Expanded(
                child: Row(
                  children: List.generate(activeParty.mode.teamSize, (slotIdx) {
                    final myCode =
                        FriendPartyService.instance.effectivePlayerCode;
                    final isMeLeader =
                        activeParty.leaderCode.toUpperCase() == myCode;

                    if (slotIdx == 0) {
                      return Expanded(
                        child: _PartySlotCard(
                          title: isMeLeader
                              ? '${activeParty.leaderName} (Bạn • Chủ Phòng)'
                              : '${activeParty.leaderName} (Chủ Phòng)',
                          subtitle: isMeLeader
                              ? 'ID: ${activeParty.leaderCode} • Lv.${profile.getHeroLevel()}/100'
                              : 'ID: ${activeParty.leaderCode} • Đội Trưởng',
                          heroId: isMeLeader ? profile.selectedHeroId : activeParty.leaderHeroId,
                          isLeader: true,
                          isEmpty: false,
                        ),
                      );
                    }

                    final allyIdx = slotIdx - 1;
                    if (allyIdx < activeParty.members.length) {
                      final ally = activeParty.members[allyIdx];
                      final isMeAlly = ally.code.toUpperCase() == myCode;
                      return Expanded(
                        child: _PartySlotCard(
                          title: isMeAlly ? '${ally.name} (Bạn)' : ally.name,
                          subtitle:
                              'ID: ${ally.code} • Lv.${ally.heroLevel}/100 • ${ally.rankTier}',
                          heroId: ally.selectedHeroId,
                          isLeader: false,
                          isEmpty: false,
                          onRemove: isMeLeader
                              ? () => FriendPartyService.instance
                                  .removeMemberFromParty(ally.code)
                              : null,
                        ),
                      );
                    }

                    return Expanded(
                      child: _PartySlotCard(
                        title: 'Ô Trống #${slotIdx + 1}',
                        subtitle:
                            'Nhập mã ${activeParty.partyCode} ở máy khác hoặc mời bạn bè',
                        heroId: '',
                        isLeader: false,
                        isEmpty: true,
                        onInviteTap: () => _tabController.animateTo(0),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 10),

              // Hàng dưới: Nhập mã phòng bạn bè hoặc Bắt đầu ghép trận
              Row(
                children: [
                  SizedBox(
                    width: 210,
                    height: 36,
                    child: TextField(
                      controller: _partyCodeController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Nhập Mã Phòng bạn bè...',
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: const BorderSide(color: Colors.cyanAccent),
                    ),
                    onPressed: _handleJoinPartyCode,
                    child: const Text(
                      'VÀO PHÒNG',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    onPressed: () {
                      final mode = activeParty.mode;
                      Navigator.of(context).pop();
                      widget.onStartPartyMatch?.call(mode);
                    },
                    icon: const Icon(Icons.sports_kabaddi_rounded, size: 18),
                    label: Text(
                      'GHÉP TRẬN ${activeParty.mode.shortLabel.toUpperCase()} CÙNG TEAM',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

Color _getHeroCardColor(String id) {
  switch (id.toLowerCase()) {
    case 'kaelen':
    case 'kale':
      return const Color(0xFF00E5FF);
    case 'nova':
    case 'nova_blade':
      return const Color(0xFF18FFFF);
    case 'shadow':
    case 'shadow_01':
      return const Color(0xFFE040FB);
    case 'ember':
    case 'ember_02':
      return const Color(0xFFFF6D00);
    case 'valeria':
      return const Color(0xFF40C4FF);
    case 'garrick':
      return const Color(0xFFFFD700);
    case 'ranger':
      return const Color(0xFFFFEB3B);
    case 'tanker':
      return const Color(0xFF76FF03);
    case 'ninja':
      return const Color(0xFFFF1744);
    default:
      return const Color(0xFFFFD700);
  }
}

class _PartySlotCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String heroId;
  final bool isLeader;
  final bool isEmpty;
  final VoidCallback? onRemove;
  final VoidCallback? onInviteTap;

  const _PartySlotCard({
    required this.title,
    required this.subtitle,
    required this.heroId,
    required this.isLeader,
    required this.isEmpty,
    this.onRemove,
    this.onInviteTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isEmpty
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLeader
              ? Colors.amberAccent
              : (isEmpty ? Colors.white24 : Colors.cyanAccent.withValues(alpha: 0.6)),
          width: isLeader ? 1.8 : 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isEmpty)
            IconButton(
              onPressed: onInviteTap,
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.amberAccent,
                size: 32,
              ),
            )
          else
            SizedBox(
              width: 76,
              height: 76,
              child: HeroShowcaseWidget(
                heroId: heroId.isNotEmpty ? heroId : 'george',
                themeColor: _getHeroCardColor(heroId),
                width: 76,
                height: 76,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isEmpty ? Colors.white54 : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          if (!isEmpty && heroId.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Tướng: ${heroId.toUpperCase()}',
              style: const TextStyle(
                color: Colors.amberAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (onRemove != null) ...[
            const SizedBox(height: 3),
            InkWell(
              onTap: onRemove,
              child: const Text(
                'Mời ra',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
