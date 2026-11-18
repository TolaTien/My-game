import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import '../models/friend_party_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import 'player_storage.dart';

/// Dịch vụ quản lý Kết Bạn (Friends) và Phòng Tổ Đội (Party Invite) cho PvP 1v1 / 2v2 / 4v4.
/// Hỗ trợ Đồng Bộ Kép (Dual-Realtime Sync):
/// 1. Firebase Realtime Database (`parties/{code}.onValue`) giữa các thiết bị online.
/// 2. Local SharedPreferences Sync (mỗi 800ms) giữa nhiều tab Chrome / cửa sổ trên cùng máy.
class FriendPartyService {
  FriendPartyService._() {
    _seedInitialFriends();
    _initInvitationListeners();
  }

  static final FriendPartyService instance = FriendPartyService._();

  static const String _localPartyPrefix = 'gold_rush_shared_party_';
  static const String _localInvitePrefix = 'gold_rush_shared_invite_';
  static const String _localInviteRespPrefix = 'gold_rush_shared_invite_resp_';
  static const String _localDirectoryPrefix = 'gold_rush_shared_directory_';

  /// Mã phiên riêng biệt cho mỗi tab / instance để 2 tab Chrome trên cùng máy không bị trùng ID
  final String _sessionPlayerCode =
      'GR${1000 + Random().nextInt(8999)}';

  final ValueNotifier<List<FriendInfo>> friendsNotifier =
      ValueNotifier<List<FriendInfo>>([]);

  final ValueNotifier<PartyRoomState?> partyNotifier =
      ValueNotifier<PartyRoomState?>(null);

  final ValueNotifier<PartyInvitation?> incomingInviteNotifier =
      ValueNotifier<PartyInvitation?>(null);

  final ValueNotifier<PartyInvitation?> inviteResponseNotifier =
      ValueNotifier<PartyInvitation?>(null);

  StreamSubscription<DatabaseEvent>? _partySubscription;
  StreamSubscription<DatabaseEvent>? _inviteSubscription;
  StreamSubscription<DatabaseEvent>? _inviteRespSubscription;
  Timer? _localPollTimer;
  Timer? _invitationPollTimer;
  String? _watchedPartyCode;

  static const List<FriendInfo> suggestedCommunityPlayers = [];

  void _seedInitialFriends() {
    // Xóa toàn bộ mock data bạn bè giả cũ (nếu có từ phiên trước)
    const mockCodes = {
      'GR1024',
      'GR2048',
      'GR3099',
      'GR7777',
      'GR9001',
      'GR4040',
      'GR5050'
    };
    final current = friendsNotifier.value;
    final cleaned = current.where((f) => !mockCodes.contains(f.code.toUpperCase())).toList();
    if (cleaned.length != current.length) {
      friendsNotifier.value = cleaned;
    }
  }

  /// Lấy mã định danh duy nhất cho phiên hiện tại (mỗi tab Chrome có UID/mã riêng)
  String get effectivePlayerCode {
    final prof = PlayerStorage.currentProfile;
    if (prof.playerCode.isNotEmpty && prof.playerCode != 'GR8899') {
      return prof.playerCode.toUpperCase();
    }
    return _sessionPlayerCode;
  }

  String get effectivePlayerName {
    final prof = PlayerStorage.currentProfile;
    if (prof.playerName.isNotEmpty && prof.playerName != 'Chiến Binh #88') {
      return prof.playerName;
    }
    final code = effectivePlayerCode;
    return 'Chiến Binh #${code.replaceAll('GR', '')}';
  }

  FirebaseDatabase? _getDb() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.databaseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Đăng ký hồ sơ người chơi lên cả Firebase VÀ SharedPreferences để người chơi khác có thể tìm theo Mã ID
  Future<void> syncOwnProfileToDirectory(PlayerProfile profile) async {
    final myCode = profile.playerCode.isNotEmpty && profile.playerCode != 'GR8899'
        ? profile.playerCode.toUpperCase()
        : effectivePlayerCode;
    final myName = profile.playerName.isNotEmpty && profile.playerName != 'Chiến Binh #88'
        ? profile.playerName
        : effectivePlayerName;

    final data = {
      'code': myCode,
      'name': myName,
      'rankPoints': profile.rankPoints,
      'rankTier': profile.rankTier,
      'selectedHeroId': profile.selectedHeroId,
      'heroLevel': profile.getHeroLevel(),
      'isOnline': true,
      'statusText': 'Đang Online',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    // 1. Lưu vào SharedPreferences để 2 tab trên cùng máy tìm thấy nhau ngay lập tức
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_localDirectoryPrefix$myCode', jsonEncode(data));
    } catch (_) {}

    // 2. Lưu vào Firebase Realtime Database
    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('directory/$myCode').set({
          ...data,
          'updatedAt': ServerValue.timestamp,
        });
      }
    } catch (e) {
      debugPrint('FriendPartyService sync directory fallback: $e');
    }
  }

  /// Kết bạn theo Mã ID (VD: GR1024) hoặc tên nhân vật
  Future<FriendInfo?> addFriendByCodeOrName(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();

    // 1. Không thể tự kết bạn với chính mình
    if (upper == effectivePlayerCode.toUpperCase() ||
        clean.toLowerCase() == effectivePlayerName.toLowerCase()) {
      return null;
    }

    // 2. Đã có trong danh sách bạn bè
    for (final existing in friendsNotifier.value) {
      if (existing.code.toUpperCase() == upper ||
          existing.name.toLowerCase() == clean.toLowerCase()) {
        return existing;
      }
    }

    // 3. Tìm trên Firebase Realtime Database
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('directory/$upper').get();
        if (snap.exists && snap.value is Map) {
          final map = Map<String, dynamic>.from(snap.value as Map);
          final found = FriendInfo.fromJson(map);
          _appendFriend(found);
          return found;
        }
      }
    } catch (_) {}

    // 4. Tìm trong Local SharedPreferences Directory (dành cho các tab Chrome cùng máy)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localDirectoryPrefix$upper');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final found = FriendInfo.fromJson(map);
        _appendFriend(found);
        return found;
      }
    } catch (_) {}

    // 5. Dự phòng khi kiểm thử hoặc ngoại tuyến: chấp nhận mã hợp lệ định dạng GRxxxx
    if (RegExp(r'^GR\d{4}$', caseSensitive: false).hasMatch(upper)) {
      final fallbackFriend = FriendInfo(
        code: upper,
        name: 'Chiến Binh #${upper.replaceAll('GR', '')}',
        rankPoints: 120,
        rankTier: 'Bạc',
        selectedHeroId: 'nova_blade',
        heroLevel: 10,
        isOnline: true,
      );
      _appendFriend(fallbackFriend);
      return fallbackFriend;
    }

    // 6. Nếu không tìm thấy người chơi thật trên hệ thống
    return null;
  }

  void _appendFriend(FriendInfo friend) {
    final current = List<FriendInfo>.from(friendsNotifier.value);
    if (!current.any((f) => f.code == friend.code)) {
      current.insert(0, friend);
      friendsNotifier.value = current;
    }

    final prof = PlayerStorage.currentProfile;
    if (!prof.friendIds.contains(friend.code)) {
      final updatedIds = List<String>.from(prof.friendIds)..add(friend.code);
      PlayerStorage.saveProfile(prof.copyWith(friendIds: updatedIds));
    }
  }

  void removeFriend(String code) {
    final current = List<FriendInfo>.from(friendsNotifier.value)
      ..removeWhere((f) => f.code == code);
    friendsNotifier.value = current;
    removeMemberFromParty(code);
  }

  /// Tạo hoặc cập nhật phòng Tổ Đội (Party) và lắng nghe Realtime
  PartyRoomState createOrUpdateParty({PvpGameMode mode = PvpGameMode.duo2v2}) {
    final myCode = effectivePlayerCode;
    final myName = effectivePlayerName;
    final existing = partyNotifier.value;
    final maxAllies = max(0, mode.teamSize - 1);

    if (existing != null) {
      final trimmed = existing.members.take(maxAllies).toList();
      final updated = existing.copyWith(mode: mode, members: trimmed);
      partyNotifier.value = updated;
      unawaited(_syncPartyEverywhere(updated));
      _listenToPartyRealtime(updated.partyCode);
      return updated;
    }

    final rand = Random();
    final partyCode = 'TEAM${100 + rand.nextInt(900)}';
    final prof = PlayerStorage.currentProfile;
    final created = PartyRoomState(
      partyCode: partyCode,
      leaderCode: myCode,
      leaderName: myName,
      leaderHeroId: prof.selectedHeroId,
      leaderHeroLevel: prof.getHeroLevel(),
      mode: mode,
      members: const [],
    );
    partyNotifier.value = created;
    unawaited(_syncPartyEverywhere(created));
    _listenToPartyRealtime(partyCode);
    return created;
  }

  /// Lắng nghe thay đổi Realtime của phòng tổ đội trên cả Firebase VÀ SharedPreferences (giữa các tab Chrome)
  void _listenToPartyRealtime(String partyCode) {
    final cleanCode = partyCode.trim().toUpperCase();
    if (_watchedPartyCode == cleanCode &&
        (_partySubscription != null || _localPollTimer != null)) {
      return;
    }

    _partySubscription?.cancel();
    _localPollTimer?.cancel();
    _watchedPartyCode = cleanCode;

    // 1. Kênh Firebase Realtime Database
    final db = _getDb();
    if (db != null) {
      _partySubscription = db.ref('parties/$cleanCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw is! Map) return;
        final data = Map<String, dynamic>.from(raw);
        final parsed = _parsePartySnapshot(cleanCode, data);
        if (parsed != null) {
          partyNotifier.value = parsed;
          unawaited(_savePartyToLocalPrefs(parsed));
        }
      }, onError: (Object err) {
        debugPrint('Party stream error: $err');
      });
    }

    // 2. Kênh SharedPreferences Polling (đồng bộ tức thì giữa 2 tab Chrome trên cùng máy)
    _localPollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      if (_watchedPartyCode != cleanCode) return;
      final localParty = await _readPartyFromLocalPrefs(cleanCode);
      if (localParty != null) {
        final current = partyNotifier.value;
        if (current == null ||
            current.partyCode != localParty.partyCode ||
            current.mode != localParty.mode ||
            current.members.length != localParty.members.length) {
          partyNotifier.value = localParty;
        }
      }
    });
  }

  PartyRoomState? _parsePartySnapshot(
    String code,
    Map<String, dynamic> data,
  ) {
    final modeCode = data['mode'] as String? ?? '2v2';
    final mode = PvpGameMode.values.firstWhere(
      (m) => m.code == modeCode,
      orElse: () => PvpGameMode.duo2v2,
    );
    final leaderCode = data['leaderCode'] as String? ?? effectivePlayerCode;
    final leaderName = data['leaderName'] as String? ?? effectivePlayerName;
    final leaderHeroId = data['leaderHeroId'] as String? ?? 'kaelen';
    final leaderHeroLevel = (data['leaderHeroLevel'] as num?)?.toInt() ?? 10;

    final List<FriendInfo> allMembers = [];
    final rawMembers = data['members'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map) {
          allMembers.add(FriendInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (rawMembers is Map) {
      rawMembers.forEach((_, value) {
        if (value is Map) {
          allMembers.add(
            FriendInfo.fromJson(Map<String, dynamic>.from(value)),
          );
        }
      });
    }

    return PartyRoomState(
      partyCode: code,
      leaderCode: leaderCode,
      leaderName: leaderName,
      leaderHeroId: leaderHeroId,
      leaderHeroLevel: leaderHeroLevel,
      mode: mode,
      members: allMembers,
    );
  }

  /// Mời bạn bè vào Tổ Đội hiện tại (gửi lời mời bất đồng bộ)
  bool inviteFriendToParty(
    FriendInfo friend, {
    PvpGameMode preferredMode = PvpGameMode.squad4v4,
  }) {
    var party = partyNotifier.value;
    if (party == null || party.mode == PvpGameMode.solo1v1) {
      party = createOrUpdateParty(
        mode: preferredMode == PvpGameMode.solo1v1
            ? PvpGameMode.squad4v4
            : preferredMode,
      );
    }
    if (!party.isFull && !party.members.any((m) => m.code == friend.code)) {
      final updatedMembers = List<FriendInfo>.from(party.members)..add(friend);
      final updated = party.copyWith(members: updatedMembers);
      partyNotifier.value = updated;
      unawaited(_syncPartyEverywhere(updated));
    }
    sendPartyInvitation(friend, preferredMode: preferredMode);
    return true;
  }

  // =========================================================================
  // LOGIC LỜI MỜI TỔ ĐỘI (PARTY INVITATIONS) & PHẢN HỒI (RESPONSES)
  // =========================================================================

  void _initInvitationListeners() {
    _startLocalInvitationPolling();
    _startFirebaseInvitationListeners();
  }

  void _startLocalInvitationPolling() {
    _invitationPollTimer?.cancel();
    _invitationPollTimer =
        Timer.periodic(const Duration(milliseconds: 900), (_) async {
      final myCode = effectivePlayerCode;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();

        // 1. Kiểm tra lời mời đến
        final rawInvite = prefs.getString('$_localInvitePrefix$myCode');
        if (rawInvite != null && rawInvite.isNotEmpty) {
          final map = jsonDecode(rawInvite) as Map<String, dynamic>;
          final invite = PartyInvitation.fromJson(map);
          if (invite.status == 'pending' &&
              (incomingInviteNotifier.value == null ||
                  incomingInviteNotifier.value?.id != invite.id)) {
            incomingInviteNotifier.value = invite;
          }
        }

        // 2. Kiểm tra phản hồi lời mời
        final rawResp = prefs.getString('$_localInviteRespPrefix$myCode');
        if (rawResp != null && rawResp.isNotEmpty) {
          final map = jsonDecode(rawResp) as Map<String, dynamic>;
          final resp = PartyInvitation.fromJson(map);
          if (inviteResponseNotifier.value == null ||
              inviteResponseNotifier.value?.id != resp.id) {
            inviteResponseNotifier.value = resp;
            await prefs.remove('$_localInviteRespPrefix$myCode');
          }
        }
      } catch (_) {}
    });
  }

  void _startFirebaseInvitationListeners() {
    try {
      final db = _getDb();
      if (db == null) return;
      final myCode = effectivePlayerCode;

      _inviteSubscription?.cancel();
      _inviteSubscription =
          db.ref('invitations/$myCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw is! Map) return;
        final map = Map<String, dynamic>.from(raw);
        final invite = PartyInvitation.fromJson(map);
        if (invite.status == 'pending' &&
            (incomingInviteNotifier.value == null ||
                incomingInviteNotifier.value?.id != invite.id)) {
          incomingInviteNotifier.value = invite;
        }
      }, onError: (_) {});

      _inviteRespSubscription?.cancel();
      _inviteRespSubscription =
          db.ref('invitation_responses/$myCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw is! Map) return;
        final map = Map<String, dynamic>.from(raw);
        final resp = PartyInvitation.fromJson(map);
        if (inviteResponseNotifier.value == null ||
            inviteResponseNotifier.value?.id != resp.id) {
          inviteResponseNotifier.value = resp;
          db.ref('invitation_responses/$myCode').remove();
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Gửi lời mời tới bạn bè vào tổ đội
  Future<bool> sendPartyInvitation(
    FriendInfo friend, {
    PvpGameMode preferredMode = PvpGameMode.squad4v4,
  }) async {
    final mode = preferredMode == PvpGameMode.solo1v1
        ? PvpGameMode.squad4v4
        : preferredMode;

    var party = partyNotifier.value;
    if (party == null || party.mode != mode) {
      party = createOrUpdateParty(mode: mode);
    }

    if (party.isFull) return false;
    if (party.members.any((m) => m.code == friend.code)) return true;

    final myCode = effectivePlayerCode;
    final myName = effectivePlayerName;
    final inviteId =
        'INV_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final invite = PartyInvitation(
      id: inviteId,
      partyCode: party.partyCode,
      fromCode: myCode,
      fromName: myName,
      toCode: friend.code,
      toName: friend.name,
      mode: mode,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
    );

    // Lưu vào Firebase và LocalPrefs cho người nhận
    await _saveInviteEverywhere(invite);

    return true;
  }

  Future<void> _saveInviteEverywhere(PartyInvitation invite) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_localInvitePrefix${invite.toCode}',
        jsonEncode(invite.toJson()),
      );
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('invitations/${invite.toCode}').set(invite.toJson());
      }
    } catch (_) {}
  }

  /// Phản hồi lời mời: Chấp nhận (accept = true) hoặc Từ chối (accept = false)
  Future<void> respondToInvitation(
    PartyInvitation invite, {
    required bool accept,
    String? reason,
  }) async {
    final response = invite.copyWith(
      status: accept ? 'accepted' : 'declined',
      declineReason: reason ?? (accept ? null : 'Người chơi đã từ chối lời mời.'),
    );

    // Xóa incoming invite trên giao diện
    incomingInviteNotifier.value = null;

    // Gửi phản hồi về cho người mời (fromCode)
    await _sendResponseEverywhere(response);

    // Dọn dẹp lời mời đã xử lý
    await _clearInviteEverywhere(invite);

    if (accept) {
      // Người nhận chuyển sang cùng sảnh tổ đội
      await joinPartyByCode(invite.partyCode, fallbackMode: invite.mode);
    }
  }

  Future<void> _sendResponseEverywhere(PartyInvitation response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_localInviteRespPrefix${response.fromCode}',
        jsonEncode(response.toJson()),
      );
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('invitation_responses/${response.fromCode}').set(
          response.toJson(),
        );
      }
    } catch (_) {}
  }

  Future<void> _clearInviteEverywhere(PartyInvitation invite) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_localInvitePrefix${invite.toCode}');
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('invitations/${invite.toCode}').remove();
      }
    } catch (_) {}
  }

  /// Tham gia phòng tổ đội của bạn bè bằng Mã Đội (Party Code).
  /// Ghi trực tiếp thông tin người vào phòng lên cả Firebase VÀ Local Storage để Chủ Phòng thấy ngay lập tức!
  Future<PartyRoomState> joinPartyByCode(
    String rawPartyCode, {
    PvpGameMode fallbackMode = PvpGameMode.duo2v2,
  }) async {
    final code = rawPartyCode.trim().toUpperCase();
    final profile = PlayerStorage.currentProfile;
    var myCode = effectivePlayerCode;
    var myName = effectivePlayerName;

    // 1. Đọc thông tin phòng hiện có từ Firebase hoặc LocalPrefs
    PartyRoomState? existingParty;
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('parties/$code').get();
        if (snap.exists && snap.value is Map) {
          existingParty = _parsePartySnapshot(
            code,
            Map<String, dynamic>.from(snap.value as Map),
          );
        }
      }
    } catch (_) {}

    existingParty ??= await _readPartyFromLocalPrefs(code);

    if (existingParty != null) {
      // Nếu 2 tab Chrome vô tình trùng mã với chủ phòng, cấp ngay mã Khách riêng để vào slot #2!
      if (existingParty.leaderCode.toUpperCase() == myCode) {
        myCode = 'GR${1000 + Random().nextInt(8999)}';
        myName = '${profile.playerName} #${myCode.substring(2)}';
      }

      final myFriendInfo = FriendInfo(
        code: myCode,
        name: myName,
        rankPoints: profile.rankPoints,
        rankTier: profile.rankTier,
        selectedHeroId: profile.selectedHeroId,
        heroLevel: profile.getHeroLevel(),
        isOnline: true,
        statusText: 'Đã vào phòng $code',
      );

      final updatedMembers = List<FriendInfo>.from(existingParty.members);
      if (!updatedMembers.any((m) => m.code.toUpperCase() == myCode)) {
        updatedMembers.add(myFriendInfo);
      }

      final joined = existingParty.copyWith(members: updatedMembers);
      partyNotifier.value = joined;
      await _syncPartyEverywhere(joined);
      _listenToPartyRealtime(code);
      return joined;
    }

    // Nếu mã phòng chưa có trên hệ thống -> Tạo phòng mới với mã đó
    final joined = PartyRoomState(
      partyCode: code.isEmpty ? 'TEAM888' : code,
      leaderCode: myCode,
      leaderName: myName,
      leaderHeroId: profile.selectedHeroId,
      leaderHeroLevel: profile.getHeroLevel(),
      mode: fallbackMode == PvpGameMode.solo1v1
          ? PvpGameMode.duo2v2
          : fallbackMode,
      members: const [],
    );
    partyNotifier.value = joined;
    await _syncPartyEverywhere(joined);
    _listenToPartyRealtime(joined.partyCode);
    return joined;
  }

  void removeMemberFromParty(String friendCode) {
    final party = partyNotifier.value;
    if (party == null) return;
    final updatedMembers = List<FriendInfo>.from(party.members)
      ..removeWhere((m) => m.code.toUpperCase() == friendCode.toUpperCase());
    final updated = party.copyWith(members: updatedMembers);
    partyNotifier.value = updated;
    unawaited(_syncPartyEverywhere(updated));
  }

  void leaveParty() {
    final party = partyNotifier.value;
    if (party != null) {
      final myCode = effectivePlayerCode;
      if (party.leaderCode.toUpperCase() != myCode.toUpperCase()) {
        removeMemberFromParty(myCode);
      }
    }
    _partySubscription?.cancel();
    _partySubscription = null;
    _localPollTimer?.cancel();
    _localPollTimer = null;
    _invitationPollTimer?.cancel();
    _invitationPollTimer = null;
    _watchedPartyCode = null;
    partyNotifier.value = null;
  }

  /// Danh sách đồng đội từ Tổ Đội để đưa vào trận PvP 2v2 / 4v4
  List<PvpOpponentInfo> getPartyAlliesForMode(PvpGameMode mode) {
    final party = partyNotifier.value;
    if (party == null || mode == PvpGameMode.solo1v1) return const [];
    final myCode = effectivePlayerCode;
    final maxAllies = max(0, mode.teamSize - 1);

    final allies = <PvpOpponentInfo>[];
    if (party.leaderCode.toUpperCase() != myCode) {
      allies.add(
        PvpOpponentInfo(
          name: '${party.leaderName} [${party.leaderCode}]',
          rankPoints: PlayerStorage.currentProfile.rankPoints,
          rankTier: PlayerStorage.currentProfile.rankTier,
          heroId: 'kaelen',
          isBot: false,
          isAlly: true,
        ),
      );
    }

    for (final m in party.members) {
      if (m.code.toUpperCase() != myCode && allies.length < maxAllies) {
        allies.add(m.toPvpAlly());
      }
    }
    return allies.take(maxAllies).toList(growable: false);
  }

  Future<void> _syncPartyEverywhere(PartyRoomState party) async {
    await _savePartyToLocalPrefs(party);
    await _syncPartyToFirebase(party);
  }

  Future<void> _savePartyToLocalPrefs(PartyRoomState party) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'partyCode': party.partyCode.toUpperCase(),
        'leaderCode': party.leaderCode,
        'leaderName': party.leaderName,
        'leaderHeroId': party.leaderHeroId,
        'leaderHeroLevel': party.leaderHeroLevel,
        'mode': party.mode.code,
        'members': party.members.map((m) => m.toJson()).toList(),
      });
      await prefs.setString(
        '$_localPartyPrefix${party.partyCode.toUpperCase()}',
        payload,
      );
    } catch (_) {}
  }

  Future<PartyRoomState?> _readPartyFromLocalPrefs(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localPartyPrefix${code.toUpperCase()}');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _parsePartySnapshot(code.toUpperCase(), map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncPartyToFirebase(PartyRoomState party) async {
    try {
      final db = _getDb();
      if (db == null) return;
      await db.ref('parties/${party.partyCode.toUpperCase()}').set({
        'partyCode': party.partyCode.toUpperCase(),
        'leaderCode': party.leaderCode,
        'leaderName': party.leaderName,
        'leaderHeroId': party.leaderHeroId,
        'leaderHeroLevel': party.leaderHeroLevel,
        'mode': party.mode.code,
        'members': party.members.map((m) => m.toJson()).toList(),
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }
}
