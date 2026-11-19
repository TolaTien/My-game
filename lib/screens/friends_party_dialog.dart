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
  final int initialTabIndex;
  final ValueChanged<PvpGameMode>? onStartPartyMatch;

  const FriendsPartyDialog({
    super.key,
    this.initialMode = PvpGameMode.duo2v2,
    this.initialTabIndex = 0,
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
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _selectedMode = widget.initialMode == PvpGameMode.solo1v1
        ? PvpGameMode.duo2v2
        : widget.initialMode;
    FriendPartyService.instance.initializeForCurrentUser(
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

    final result = await FriendPartyService.instance.sendFriendRequest(query);
    if (!mounted) return;
    switch (result.status) {
      case FriendRequestSendStatus.sent:
        _searchController.clear();
        final target = result.targetFriend!;
        _showToast(
          'Đã gửi yêu cầu kết bạn tới ${target.name} (${target.code})! Chờ đối phương đồng ý.',
        );
        break;
      case FriendRequestSendStatus.autoAccepted:
        _searchController.clear();
        final target = result.targetFriend!;
        _showToast(
          '${target.name} (${target.code}) đã gửi lời mời trước đó — hai bạn đã trở thành bạn bè!',
        );
        break;
      case FriendRequestSendStatus.alreadyFriends:
        final target = result.targetFriend;
        _showToast(
          'Bạn và ${target?.name ?? query} đã là bạn bè rồi!',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.alreadySent:
        final target = result.targetFriend;
        _showToast(
          'Bạn đã gửi yêu cầu kết bạn tới ${target?.name ?? query} trước đó rồi!',
          isSuccess: false,
        );
        break;
      case FriendRequestSendStatus.isSelf:
        _showToast('Không thể tự kết bạn với chính mình!', isSuccess: false);
        break;
      case FriendRequestSendStatus.notFound:
        _showToast(
          'Không tìm thấy người chơi có mã hoặc tên "$query"!',
          isSuccess: false,
        );
        break;
    }
  }

  void _handleInviteToParty(FriendInfo friend) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    final active = FriendPartyService.instance.partyNotifier.value;
    if (active != null &&
        active.members.any(
          (m) => m.code.toUpperCase() == friend.code.toUpperCase(),
        )) {
      _showToast('${friend.name} đã ở trong tổ đội rồi!', isSuccess: false);
      return;
    }
    final ok = FriendPartyService.instance.inviteFriendToParty(
      friend,
      preferredMode: _selectedMode,
    );
    if (ok) {
      _showToast(
        'Đã gửi lời mời vào đội ${_selectedMode.shortLabel} tới ${friend.name}. Đang chờ phản hồi...',
      );
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
                                Icons.badge_rounded,
                                size: 13,
                                color: Color(0xFF29D8FF),
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'HỒ SƠ',
                                style: TextStyle(
                                  color: Color(0xFF29D8FF),
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
                  child: ValueListenableBuilder<List<FriendRequest>>(
                    valueListenable:
                        FriendPartyService.instance.incomingFriendRequestsNotifier,
                    builder: (context, requests, _) {
                      return TabBar(
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
                          fontSize: 11.5,
                        ),
                        tabs: [
                          const Tab(text: 'BẠN BÈ & TÌM KIẾM'),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('YÊU CẦU'),
                                if (requests.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${requests.length}',
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
                          ),
                          const Tab(text: 'TỔ ĐỘI (2V2 / 4V4)'),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsTab(),
                      _buildRequestsTab(),
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
                  'GỬI KẾT BẠN',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Hướng dẫn gửi lời mời kết bạn
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
                    'Nhập Mã ID (VD: GR1234) hoặc tên nhân vật để gửi yêu cầu kết bạn. Đối phương cần nhấn Đồng ý trong mục Yêu Cầu để trở thành bạn bè!',
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
                if (friends.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 46,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Chưa có bạn bè nào. Hãy nhập Mã ID để gửi lời mời kết bạn!',
                          style: TextStyle(color: Colors.white54, fontSize: 12.5),
                        ),
                      ],
                    ),
                  );
                }
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
                          Stack(
                            clipBehavior: Clip.none,
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
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: f.isOnline
                                        ? const Color(0xFF00E676)
                                        : Colors.grey,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0E131D),
                                      width: 1.5,
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
                            onPressed: f.isOnline
                                ? () {
                                    _handleInviteToParty(f);
                                    _tabController.animateTo(2);
                                  }
                                : null,
                            icon: const Icon(Icons.group_add_rounded, size: 15),
                            label: Text(
                              f.isOnline ? 'MỜI VÀO TEAM' : 'NGOẠI TUYẾN',
                              style: const TextStyle(
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

  Widget _buildRequestsTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ValueListenableBuilder<List<FriendRequest>>(
        valueListenable:
            FriendPartyService.instance.incomingFriendRequestsNotifier,
        builder: (context, requests, _) {
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chưa có yêu cầu kết bạn nào đang chờ!',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final req = requests[idx];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: const Color(0xFF1E3A6E),
                      child: Text(
                        req.fromName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF29D8FF),
                          fontWeight: FontWeight.w900,
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
                                req.fromName,
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
                                  color: Colors.amberAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Lv.${req.fromHeroLevel}/100 • ${req.fromRankTier}',
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Mã ID: ${req.fromCode} • Muốn kết bạn với bạn',
                            style: const TextStyle(
                              color: Color(0xFF80D8FF),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () async {
                        AudioService.instance.playSfx(SfxSound.uiClick);
                        await FriendPartyService.instance
                            .respondToFriendRequest(req, accept: false);
                        if (mounted) {
                          _showToast(
                            'Đã từ chối lời mời kết bạn từ ${req.fromName}.',
                            isSuccess: false,
                          );
                        }
                      },
                      child: const Text(
                        'TỪ CHỐI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: const Color(0xFF062412),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () async {
                        AudioService.instance.playSfx(SfxSound.uiClick);
                        await FriendPartyService.instance
                            .respondToFriendRequest(req, accept: true);
                        if (mounted) {
                          _showToast(
                            'Đã đồng ý kết bạn với ${req.fromName} (${req.fromCode})!',
                          );
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: const Text(
                        'ĐỒNG Ý',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
                    onSelected: activeParty.isLeader(
                            FriendPartyService.instance.effectivePlayerCode)
                        ? (_) {
                            setState(() => _selectedMode = PvpGameMode.duo2v2);
                            FriendPartyService.instance.createOrUpdateParty(
                              mode: PvpGameMode.duo2v2,
                            );
                          }
                        : null,
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
                    onSelected: activeParty.isLeader(
                            FriendPartyService.instance.effectivePlayerCode)
                        ? (_) {
                            setState(() => _selectedMode = PvpGameMode.squad4v4);
                            FriendPartyService.instance.createOrUpdateParty(
                              mode: PvpGameMode.squad4v4,
                            );
                          }
                        : null,
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
                  Builder(builder: (context) {
                    final myCode =
                        FriendPartyService.instance.effectivePlayerCode;
                    final isMeLeader = activeParty.isLeader(myCode);
                    final isReady =
                        !isMeLeader && activeParty.isMemberReady(myCode);

                    if (!isMeLeader) {
                      return ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isReady
                              ? const Color(0xFF00B248)
                              : Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () {
                          FriendPartyService.instance.toggleMyReadyState();
                        },
                        icon: Icon(
                          isReady
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 18,
                        ),
                        label: Text(
                          isReady
                              ? 'SẴN SÀNG (CHỜ CHỦ PHÒNG)'
                              : 'BẤM SẴN SÀNG',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }

                    return ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      onPressed: () {
                        if (!activeParty.areAllMembersReady) {
                          _showToast(
                            'Hãy chờ đồng đội bấm SẴN SÀNG!',
                            isSuccess: false,
                          );
                          return;
                        }
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
                    );
                  }),
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
