import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/friend_party_models.dart';
import '../models/player_profile.dart';
import '../registry/asset_registry.dart';
import '../services/audio_service.dart';
import '../services/friend_party_service.dart';
import '../services/player_storage.dart';

class SoloRoomDialog extends StatefulWidget {
  final ValueChanged<SoloDuelRoomState>? onStartSoloMatch;

  const SoloRoomDialog({
    super.key,
    this.onStartSoloMatch,
  });

  static Future<void> show(
    BuildContext context, {
    ValueChanged<SoloDuelRoomState>? onStartSoloMatch,
  }) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => SoloRoomDialog(onStartSoloMatch: onStartSoloMatch),
    );
  }

  @override
  State<SoloRoomDialog> createState() => _SoloRoomDialogState();
}

class _SoloRoomDialogState extends State<SoloRoomDialog> {
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _createBetController =
      TextEditingController(text: '0');

  int _draftBetGold = 0;
  String? _draftMapId; // null = Ngẫu nhiên
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    FriendPartyService.instance.initializeForCurrentUser(
      PlayerStorage.currentProfile,
    );
    FriendPartyService.instance.soloRoomNotifier
        .addListener(_onSoloRoomUpdated);
    FriendPartyService.instance.soloRoomNoticeNotifier
        .addListener(_onSoloNotice);
  }

  @override
  void dispose() {
    FriendPartyService.instance.soloRoomNotifier
        .removeListener(_onSoloRoomUpdated);
    FriendPartyService.instance.soloRoomNoticeNotifier
        .removeListener(_onSoloNotice);
    _joinCodeController.dispose();
    _createBetController.dispose();
    super.dispose();
  }

  void _onSoloRoomUpdated() {
    if (!mounted) return;
    final room = FriendPartyService.instance.soloRoomNotifier.value;
    if (room != null &&
        room.matchStatus == 'in_match' &&
        room.activeMatchRoomId != null &&
        room.activeMatchRoomId!.isNotEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  void _onSoloNotice() {
    final msg = FriendPartyService.instance.soloRoomNoticeNotifier.value;
    if (msg == null || !mounted) return;
    FriendPartyService.instance.soloRoomNoticeNotifier.value = null;
    _showToast(msg, isSuccess: false);
  }

  void _showToast(String msg, {bool isSuccess = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        backgroundColor:
            isSuccess ? Colors.green.shade800 : Colors.deepOrange.shade900,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatGold(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _getMapDisplayName(String? mapId) {
    if (mapId == null || mapId.isEmpty) return '🎲 Ngẫu nhiên';
    final map = GameAssetRegistry.instance.getMap(mapId);
    return map != null ? '🗺️ ${map.name}' : '🎲 Ngẫu nhiên';
  }

  Future<void> _handleCreateRoom(PlayerProfile profile) async {
    if (_isBusy) return;
    AudioService.instance.playSfx(SfxSound.uiClick);
    final parsed =
        int.tryParse(_createBetController.text.trim()) ?? _draftBetGold;
    if (parsed > profile.gold) {
      _showToast(
        'Bạn chỉ có ${_formatGold(profile.gold)} Vàng, không đủ tạo phòng cược ${_formatGold(parsed)} Vàng!',
        isSuccess: false,
      );
      return;
    }

    setState(() => _isBusy = true);
    try {
      final created = await FriendPartyService.instance.createSoloRoom(
        betGold: max(0, parsed),
        selectedMapId: _draftMapId,
      );
      if (!mounted) return;
      _showToast(
        'Đã tạo phòng 4v4 (${created.roomCode})! Mời bạn bè và xếp 2 phe để bắt đầu.',
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _handleJoinRoom() async {
    if (_isBusy) return;
    final code = _joinCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      _showToast('Vui lòng nhập Mã Phòng!', isSuccess: false);
      return;
    }
    AudioService.instance.playSfx(SfxSound.uiClick);
    setState(() => _isBusy = true);
    try {
      final joined = await FriendPartyService.instance.joinSoloRoomByCode(code);
      if (!mounted) return;
      _joinCodeController.clear();
      _showToast(
        'Đã vào phòng ${joined.roomCode} của ${joined.hostName}!',
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ArgumentError
          ? e.message.toString()
          : (e is StateError ? e.message.toString() : 'Không thể vào phòng: $e');
      _showToast(msg, isSuccess: false);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _copyRoomCode(String code) async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    await Clipboard.setData(ClipboardData(text: code));
    _showToast(
      'Đã sao chép mã phòng $code! Bạn bè có thể nhập mã hoặc nhận lời mời từ bạn.',
    );
  }

  Future<void> _openInviteFriendsSheet(
    SoloDuelRoomState room, {
    String? preferredTeam,
  }) async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InviteFriendsToCustomRoomDialog(
        room: room,
        preferredTeam: preferredTeam,
        onInvited: (friend, team) {
          final teamName = team == 'red'
              ? 'Đội Đỏ'
              : (team == 'blue' ? 'Đội Xanh' : 'phòng');
          _showToast('Đã gửi lời mời vào $teamName tới ${friend.name}!');
        },
      ),
    );
  }

  Future<void> _promptCustomBetDialog(
    SoloDuelRoomState room,
    PlayerProfile profile,
  ) async {
    final ctrl = TextEditingController(text: '${room.betGold}');
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141E33),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amberAccent, width: 1.5),
        ),
        title: const Text(
          'CÀI ĐẶT MỨC CƯỢC VÀNG / NGƯỜI',
          style: TextStyle(
            color: Colors.amberAccent,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Số dư của bạn: ${_formatGold(profile.gold)} Vàng\nNhập 0 nếu muốn đấu giao hữu không cược.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                suffixText: 'Vàng',
                suffixStyle: const TextStyle(color: Colors.amberAccent),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('HỦY', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.of(ctx).pop(val);
            },
            child: const Text(
              'XÁC NHẬN',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (chosen == null || !mounted) return;
    if (chosen > profile.gold) {
      _showToast(
        'Bạn chỉ có ${_formatGold(profile.gold)} Vàng, không thể đặt cược cao hơn số dư!',
        isSuccess: false,
      );
      return;
    }
    await FriendPartyService.instance.updateSoloRoomSettings(betGold: chosen);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerProfile>(
      valueListenable: PlayerStorage.profileNotifier,
      builder: (context, profile, _) {
        return ValueListenableBuilder<SoloDuelRoomState?>(
          valueListenable: FriendPartyService.instance.soloRoomNotifier,
          builder: (context, soloRoom, _) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 880, maxHeight: 500),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF161F33), Color(0xFF0B101B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.8),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.78),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHeader(profile, soloRoom),
                    const Divider(height: 1, color: Colors.white12),
                    Expanded(
                      child: soloRoom == null
                          ? _buildCreateOrJoinBody(profile)
                          : _buildActiveCustomRoomBody(profile, soloRoom),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(PlayerProfile profile, SoloDuelRoomState? soloRoom) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.6),
              ),
            ),
            child: const Icon(
              Icons.sports_kabaddi_rounded,
              color: Colors.amberAccent,
              size: 19,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                soloRoom == null
                    ? 'TẠO PHÒNG ĐẤU TÙY CHỌN 4V4 (2 PHE XANH • ĐỎ)'
                    : 'PHÒNG ĐẤU 4V4 (${soloRoom.totalPlayerCount}/8 NGƯỜI • ĐỘI HÌNH ${soloRoom.matchupLabel})',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          if (soloRoom != null) ...[
            const SizedBox(width: 6),
            ElevatedButton.icon(
              key: const Key('solo_open_invite_friends_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B0FF),
                foregroundColor: Colors.black,
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: soloRoom.isFull
                  ? null
                  : () => _openInviteFriendsSheet(soloRoom),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
              label: const Text(
                'MỜI BẠN BÈ',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              key: const Key('solo_copy_code_chip'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _copyRoomCode(soloRoom.roomCode),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00E5FF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MÃ: ${soloRoom.roomCode}',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: Color(0xFF00E5FF),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Color(0xFFFFD54F),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${_formatGold(profile.gold)}G',
                  style: const TextStyle(
                    color: Color(0xFFFFF59D),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (soloRoom != null) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              key: const Key('solo_leave_room_button'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF5252),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              onPressed: () async {
                AudioService.instance.playSfx(SfxSound.uiClick);
                await FriendPartyService.instance.leaveSoloRoom();
              },
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text(
                'RỜI',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // --- MÀN HÌNH 1: TẠO PHÒNG 4V4 MẶC ĐỊNH HOẶC NHẬP MÃ PHÒNG ---
  Widget _buildCreateOrJoinBody(PlayerProfile profile) {
    final maps = GameAssetRegistry.instance.availableMatchMaps;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // CỘT TRÁI: TẠO PHÒNG 4V4 TÙY CHỌN
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.amberAccent.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.groups_rounded,
                                color: Colors.amberAccent,
                                size: 19,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'TẠO PHÒNG 4V4 (2 TEAM XANH • ĐỎ)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Mặc định tạo phòng có 4 chỗ Đội Xanh và 4 chỗ Đội Đỏ. Người chơi trong phòng tự do mời bạn bè và đổi sang phe bất kỳ (Solo 1v1, 1v2, 2v2, 3v3, 4v4...).',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),

                          const Text(
                            '1. Mức cược Vàng mỗi người (tùy chọn):',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                SoloDuelRoomState.presetBetAmounts.map((amt) {
                              final selected = _draftBetGold == amt;
                              final affordable = amt <= profile.gold;
                              return ChoiceChip(
                                label: Text(
                                  amt == 0
                                      ? '0 (Giao hữu)'
                                      : '${_formatGold(amt)} Vàng',
                                ),
                                selected: selected,
                                selectedColor: Colors.amberAccent,
                                backgroundColor: const Color(0xFF1A253D),
                                disabledColor:
                                    Colors.white.withValues(alpha: 0.03),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                labelStyle: TextStyle(
                                  color: !affordable
                                      ? Colors.white24
                                      : (selected ? Colors.black : Colors.white),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                                onSelected: affordable
                                    ? (_) {
                                        setState(() {
                                          _draftBetGold = amt;
                                          _createBetController.text = '$amt';
                                        });
                                      }
                                    : null,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              const Text(
                                'Hoặc nhập mức cược:',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                height: 32,
                                child: TextField(
                                  key: const Key('solo_custom_bet_input'),
                                  controller: _createBetController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (v) {
                                    setState(() {
                                      _draftBetGold = int.tryParse(v) ?? 0;
                                    });
                                  },
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    suffixText: 'Vàng',
                                    suffixStyle: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 10,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    filled: true,
                                    fillColor: Colors.black26,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          const Text(
                            '2. Chọn Bản đồ thi đấu:',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            height: 36,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A253D),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color:
                                    Colors.cyanAccent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                key: const Key('solo_create_map_dropdown'),
                                value: _draftMapId ?? '',
                                isExpanded: true,
                                dropdownColor: const Color(0xFF162035),
                                iconEnabledColor: Colors.cyanAccent,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: '',
                                    child: Text(
                                      '🎲 Ngẫu nhiên (Hệ thống bốc tự động)',
                                    ),
                                  ),
                                  ...maps.map(
                                    (m) => DropdownMenuItem<String>(
                                      value: m.id,
                                      child: Text('🗺️ ${m.name}'),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _draftMapId = (val == null || val.isEmpty)
                                        ? null
                                        : val;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('solo_create_room_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB300),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          _isBusy ? null : () => _handleCreateRoom(profile),
                      icon: const Icon(Icons.meeting_room_rounded, size: 18),
                      label: const Text(
                        'TẠO PHÒNG 4V4 MỚI',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),

          // CỘT PHẢI: VÀO PHÒNG BẰNG MÃ
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.login_rounded,
                                color: Color(0xFF00E5FF),
                                size: 18,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'VÀO PHÒNG BẰNG MÃ',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Nhập Mã Phòng (VD: SOLO4829) hoặc chấp nhận lời mời trực tiếp từ bạn bè để vào phòng xếp đội.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('solo_join_code_input'),
                            controller: _joinCodeController,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _handleJoinRoom(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'VD: SOLO4829',
                              hintStyle: const TextStyle(
                                color: Colors.white30,
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Dán mã từ bộ nhớ tạm',
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  color: Color(0xFF00E5FF),
                                  size: 18,
                                ),
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                    Clipboard.kTextPlain,
                                  );
                                  final txt = data?.text?.trim();
                                  if (txt != null && txt.isNotEmpty && mounted) {
                                    setState(() {
                                      _joinCodeController.text =
                                          txt.toUpperCase();
                                    });
                                  }
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.cyan.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.cyan.withValues(alpha: 0.25),
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '⚡ CÁCH CHƠI PHÒNG TÙY CHỌN 4V4:',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '• 2 đội Xanh & Đỏ, mỗi đội tối đa 4 chỗ.\n'
                                  '• Ai trong phòng cũng mời thêm bạn và tự bấm ô trống để chuyển phe (1v1, 2v2, 1v3, 4v4...).\n'
                                  '• Tất cả bấm Sẵn Sàng xong Chủ Phòng bấm Vào Game.',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('solo_join_room_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isBusy ? null : _handleJoinRoom,
                      icon: const Icon(Icons.login_rounded, size: 18),
                      label: const Text(
                        'VÀO PHÒNG',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
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
    );
  }

  // --- MÀN HÌNH 2: SẢNH PHÒNG TÙY CHỌN 4V4 (4 CHỖ ĐỘI XANH VS 4 CHỖ ĐỘI ĐỎ) ---
  Widget _buildActiveCustomRoomBody(
    PlayerProfile profile,
    SoloDuelRoomState room,
  ) {
    final myCode = FriendPartyService.instance.effectivePlayerCode;
    final isMeHost = room.isHost(myCode);
    final maps = GameAssetRegistry.instance.availableMatchMaps;
    final canAffordBet = profile.gold >= room.betGold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          // KHU XẾP ĐỘI 2 PHE: ĐỘI XANH (4 CHỖ) VS ĐỘI ĐỎ (4 CHỖ)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CỘT TRÁI: ĐỘI XANH (4 CHỖ)
                Expanded(
                  flex: 5,
                  child: _buildTeamColumn(
                    teamKey: 'blue',
                    teamTitle: 'ĐỘI XANH (${room.blueCount}/4)',
                    accentColor: const Color(0xFF00E5FF),
                    slots: room.blueSlots,
                    room: room,
                    myCode: myCode,
                    isMeHost: isMeHost,
                    profile: profile,
                  ),
                ),

                // CỘT GIỮA: THÔNG TIN KÈO ĐẤU & BẢN ĐỒ
                SizedBox(
                  width: 146,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF6D00), Color(0xFFD50000)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '⚔️ ${room.blueCount} VS ${room.redCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Cọc Cược Vàng
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.amberAccent.withValues(alpha: 0.8),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    room.betGold > 0
                                        ? 'TỔNG QUỸ THƯỞNG'
                                        : 'CHẾ ĐỘ ĐẤU',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      room.betGold > 0
                                          ? '💰 ${_formatGold(room.totalPotGold)}G'
                                          : 'GIAO HỮU (0G)',
                                      style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (room.betGold > 0)
                                    Text(
                                      '${_formatGold(room.betGold)}G / người',
                                      style: const TextStyle(
                                        color: Color(0xFFFFF59D),
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 7),

                            // Bản đồ đang chọn
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.cyan.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.cyanAccent.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                _getMapDisplayName(room.selectedMapId),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 7),

                            // Trạng thái sẵn sàng của cả phòng
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: room.canHostStart
                                    ? const Color(0xFF00E676).withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: room.canHostStart
                                      ? const Color(0xFF00E676)
                                      : Colors.white24,
                                ),
                              ),
                              child: Text(
                                !room.hasBothTeams
                                    ? 'Cần mỗi phe ≥ 1 người'
                                    : (!room.areAllGuestsReady
                                        ? 'Chờ tất cả Sẵn Sàng'
                                        : 'Sẵn sàng Vào Game!'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: room.canHostStart
                                      ? const Color(0xFF00E676)
                                      : Colors.amberAccent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // CỘT PHẢI: ĐỘI ĐỎ (4 CHỖ)
                Expanded(
                  flex: 5,
                  child: _buildTeamColumn(
                    teamKey: 'red',
                    teamTitle: 'ĐỘI ĐỎ (${room.redCount}/4)',
                    accentColor: const Color(0xFFFF5252),
                    slots: room.redSlots,
                    room: room,
                    myCode: myCode,
                    isMeHost: isMeHost,
                    profile: profile,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // THANH ĐIỀU KHIỂN DƯỚI CÙNG
          if (isMeHost)
            _buildHostBottomBar(profile, room, maps, canAffordBet)
          else
            _buildGuestBottomBar(profile, room, myCode, canAffordBet),
        ],
      ),
    );
  }

  Widget _buildTeamColumn({
    required String teamKey,
    required String teamTitle,
    required Color accentColor,
    required List<FriendInfo?> slots,
    required SoloDuelRoomState room,
    required String myCode,
    required bool isMeHost,
    required PlayerProfile profile,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: accentColor, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  teamTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: room.isFull
                    ? null
                    : () => _openInviteFriendsSheet(
                          room,
                          preferredTeam: teamKey,
                        ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '+ Mời vào phe',
                    style: TextStyle(
                      color: room.isFull ? Colors.white24 : accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Column(
              children: List.generate(SoloDuelRoomState.slotsPerTeam, (slotIdx) {
                final member = slots[slotIdx];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: slotIdx < SoloDuelRoomState.slotsPerTeam - 1 ? 5 : 0,
                    ),
                    child: member == null
                        ? _buildEmptyTeamSlot(
                            teamKey: teamKey,
                            slotIdx: slotIdx,
                            accentColor: accentColor,
                            room: room,
                          )
                        : _buildOccupiedTeamSlot(
                            member: member,
                            teamKey: teamKey,
                            accentColor: accentColor,
                            room: room,
                            myCode: myCode,
                            isMeHost: isMeHost,
                            profile: profile,
                          ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTeamSlot({
    required String teamKey,
    required int slotIdx,
    required Color accentColor,
    required SoloDuelRoomState room,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ô #${slotIdx + 1} • Trống',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            key: Key('solo_slot_${teamKey}_$slotIdx'),
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              AudioService.instance.playSfx(SfxSound.uiClick);
              await FriendPartyService.instance.switchSoloTeamSlot(
                targetTeam: teamKey,
                targetSlot: slotIdx,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accentColor.withValues(alpha: 0.55)),
              ),
              child: Text(
                'Đổi sang đây',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openInviteFriendsSheet(room, preferredTeam: teamKey),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 14,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOccupiedTeamSlot({
    required FriendInfo member,
    required String teamKey,
    required Color accentColor,
    required SoloDuelRoomState room,
    required String myCode,
    required bool isMeHost,
    required PlayerProfile profile,
  }) {
    final isMe = member.code.toUpperCase() == myCode.toUpperCase();
    final isMemberHost = room.isHost(member.code);
    final isReady = room.isPlayerReady(member.code);
    final heroId = isMe ? profile.selectedHeroId : member.selectedHeroId;
    final heroLv = isMe ? profile.getHeroLevel() : member.heroLevel;
    final displayName = isMe ? profile.playerName : member.name;

    final statusLabel = isMemberHost
        ? 'CHỦ PHÒNG'
        : (isReady ? 'SẴN SÀNG' : 'CHỜ SẴN SÀNG');
    final statusColor = isMemberHost
        ? const Color(0xFFFFD54F)
        : (isReady ? const Color(0xFF00E676) : const Color(0xFFFFB74D));

    final canSwitchOtherTeam = isMe || isMeHost;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMe
            ? accentColor.withValues(alpha: 0.18)
            : const Color(0xFF172238),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe ? accentColor : accentColor.withValues(alpha: 0.4),
          width: isMe ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withValues(alpha: 0.6)),
            ),
            child: Center(
              child: Text(
                displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? '$displayName (Bạn)' : displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? const Color(0xFFFFF59D) : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: statusColor, width: 0.8),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${heroId.toUpperCase()} Lv.$heroLv • ${member.rankTier}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          if (canSwitchOtherTeam) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: teamKey == 'blue'
                  ? 'Chuyển sang Đội Đỏ'
                  : 'Chuyển sang Đội Xanh',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  AudioService.instance.playSfx(SfxSound.uiClick);
                  final ok = await FriendPartyService.instance
                      .moveSoloMemberToOppositeTeam(member.code);
                  if (!ok && mounted) {
                    _showToast('Phe bên kia đã kín 4/4 chỗ!', isSuccess: false);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    size: 15,
                    color: Colors.amberAccent,
                  ),
                ),
              ),
            ),
          ],
          if (isMeHost && !isMe) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'Mời ra khỏi phòng',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    FriendPartyService.instance.kickSoloMember(member.code),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Color(0xFFFF5252),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHostBottomBar(
    PlayerProfile profile,
    SoloDuelRoomState room,
    List<MapAssetConfig> maps,
    bool canAffordBet,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Text(
            'Cược:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 5),
          ...[0, 100, 200, 500, 1000].map((amt) {
            final selected = room.betGold == amt;
            final ok = amt <= profile.gold;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: ok
                    ? () {
                        AudioService.instance.playSfx(SfxSound.uiClick);
                        FriendPartyService.instance
                            .updateSoloRoomSettings(betGold: amt);
                      }
                    : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.amberAccent
                        : Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? Colors.amberAccent : Colors.white24,
                    ),
                  ),
                  child: Text(
                    amt == 1000 ? '1K' : '$amt',
                    style: TextStyle(
                      color: !ok
                          ? Colors.white24
                          : (selected ? Colors.black : Colors.white),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _promptCustomBetDialog(room, profile),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amberAccent.withValues(alpha: 0.6),
                ),
              ),
              child: const Icon(
                Icons.edit_rounded,
                size: 13,
                color: Colors.amberAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A253D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('solo_room_map_dropdown'),
                  value: (room.selectedMapId != null &&
                          maps.any((m) => m.id == room.selectedMapId))
                      ? room.selectedMapId!
                      : '',
                  isExpanded: true,
                  dropdownColor: const Color(0xFF162035),
                  iconEnabledColor: Colors.cyanAccent,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text(
                        '🎲 Bản đồ Ngẫu nhiên',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...maps.map(
                      (m) => DropdownMenuItem<String>(
                        value: m.id,
                        child: Text(
                          '🗺️ ${m.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    AudioService.instance.playSfx(SfxSound.uiClick);
                    if (val == null || val.isEmpty) {
                      FriendPartyService.instance.updateSoloRoomSettings(
                        clearSelectedMap: true,
                      );
                    } else {
                      FriendPartyService.instance.updateSoloRoomSettings(
                        selectedMapId: val,
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          ElevatedButton.icon(
            key: const Key('solo_start_match_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: (room.canHostStart && canAffordBet)
                  ? const Color(0xFF00E676)
                  : Colors.blueGrey.shade700,
              foregroundColor: (room.canHostStart && canAffordBet)
                  ? const Color(0xFF042310)
                  : Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              AudioService.instance.playSfx(SfxSound.uiClick);
              if (!room.hasBothTeams) {
                _showToast(
                  'Cần có ít nhất 1 người chơi ở Đội Xanh và 1 người chơi ở Đội Đỏ!',
                  isSuccess: false,
                );
                return;
              }
              if (!room.areAllGuestsReady) {
                _showToast(
                  'Hãy chờ tất cả người chơi trong phòng bấm SẴN SÀNG!',
                  isSuccess: false,
                );
                return;
              }
              if (!canAffordBet) {
                _showToast(
                  'Bạn không đủ ${_formatGold(room.betGold)} Vàng để đặt cược!',
                  isSuccess: false,
                );
                return;
              }
              final started =
                  await FriendPartyService.instance.startSoloDuelMatch();
              if (started != null && mounted) {
                widget.onStartSoloMatch?.call(started);
              }
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 19),
            label: Text(
              'VÀO GAME (${room.matchupLabel})',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestBottomBar(
    PlayerProfile profile,
    SoloDuelRoomState room,
    String myCode,
    bool canAffordBet,
  ) {
    final isReady = room.isPlayerReady(myCode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canAffordBet
              ? Colors.white12
              : const Color(0xFFFF5252).withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Icon(
            canAffordBet
                ? Icons.swap_calls_rounded
                : Icons.warning_amber_rounded,
            color: canAffordBet
                ? const Color(0xFF00E5FF)
                : const Color(0xFFFF5252),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              canAffordBet
                  ? (isReady
                      ? 'Đã SẴN SÀNG! Đang chờ các thành viên khác & Chủ Phòng bấm Vào Game.'
                      : 'Tự do mời thêm bạn hoặc bấm "Đổi sang đây" ở ô trống để xếp phe, xong bấm Sẵn Sàng!')
                  : 'Bạn cần ${_formatGold(room.betGold)} Vàng để theo cược (hiện có ${_formatGold(profile.gold)} Vàng)!',
              style: TextStyle(
                color: canAffordBet ? Colors.white70 : const Color(0xFFFF8A80),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            key: const Key('solo_guest_ready_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isReady
                  ? const Color(0xFF00B248)
                  : (canAffordBet
                      ? const Color(0xFFFFB300)
                      : Colors.blueGrey.shade700),
              foregroundColor: isReady ? Colors.white : Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              AudioService.instance.playSfx(SfxSound.uiClick);
              final ok =
                  await FriendPartyService.instance.toggleSoloGuestReady();
              if (!ok && mounted) {
                _showToast(
                  'Bạn không đủ ${_formatGold(room.betGold)} Vàng để theo cược!',
                  isSuccess: false,
                );
              }
            },
            icon: Icon(
              isReady
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 17,
            ),
            label: Text(
              isReady ? 'ĐÃ SẴN SÀNG (HỦY)' : 'BẤM SẴN SÀNG',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hộp thoại chọn Bạn Bè đang Online để mời thẳng vào Phòng Đấu 4v4 Tùy Chọn
class _InviteFriendsToCustomRoomDialog extends StatelessWidget {
  final SoloDuelRoomState room;
  final String? preferredTeam;
  final void Function(FriendInfo friend, String? team) onInvited;

  const _InviteFriendsToCustomRoomDialog({
    required this.room,
    this.preferredTeam,
    required this.onInvited,
  });

  @override
  Widget build(BuildContext context) {
    final teamTitle = preferredTeam == 'blue'
        ? 'ĐỘI XANH'
        : (preferredTeam == 'red' ? 'ĐỘI ĐỎ' : 'PHÒNG ĐẤU ${room.roomCode}');

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00E5FF), width: 1.6),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1_rounded,
                  color: Color(0xFF00E5FF),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MỜI BẠN BÈ VÀO $teamTitle',
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 12),
            Expanded(
              child: ValueListenableBuilder<List<FriendInfo>>(
                valueListenable: FriendPartyService.instance.friendsNotifier,
                builder: (context, friends, _) {
                  final onlineFriends =
                      friends.where((f) => f.isOnline).toList();
                  if (onlineFriends.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có bạn bè nào đang Online.\nBạn cũng có thể gửi Mã Phòng ${room.roomCode} cho bạn bè nhập vào!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: onlineFriends.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, idx) {
                      final f = onlineFriends[idx];
                      final alreadyInRoom = room.containsPlayer(f.code);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${f.name} [${f.code}]',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Lv.${f.heroLevel} • ${f.rankTier}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: alreadyInRoom
                                    ? Colors.blueGrey
                                    : const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                              ),
                              onPressed: alreadyInRoom
                                  ? null
                                  : () async {
                                      AudioService.instance
                                          .playSfx(SfxSound.uiClick);
                                      final ok = await FriendPartyService
                                          .instance
                                          .inviteFriendToSoloRoom(
                                        f,
                                        preferredTeam: preferredTeam,
                                      );
                                      if (ok && ctx.mounted) {
                                        onInvited(f, preferredTeam);
                                        Navigator.of(ctx).pop();
                                      }
                                    },
                              child: Text(
                                alreadyInRoom ? 'ĐÃ Ở PHÒNG' : 'MỜI NGAY',
                                style: const TextStyle(
                                  fontSize: 10.5,
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
            ),
          ],
        ),
      ),
    );
  }
}
