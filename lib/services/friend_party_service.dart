import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
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
  }

  static final FriendPartyService instance = FriendPartyService._();

  static const String _localPartyPrefix = 'gold_rush_shared_party_';

  /// Mã phiên riêng biệt cho mỗi tab / instance để 2 tab Chrome trên cùng máy không bị trùng ID
  final String _sessionPlayerCode =
      'GR${1000 + Random().nextInt(8999)}';

  final ValueNotifier<List<FriendInfo>> friendsNotifier =
      ValueNotifier<List<FriendInfo>>([]);

  final ValueNotifier<PartyRoomState?> partyNotifier =
      ValueNotifier<PartyRoomState?>(null);

  StreamSubscription<DatabaseEvent>? _partySubscription;
  Timer? _localPollTimer;
  String? _watchedPartyCode;

  static const List<FriendInfo> suggestedCommunityPlayers = [
    FriendInfo(
      code: 'GR1024',
      name: 'Kaelen_LôiKiếm',
      rankPoints: 1520,
      rankTier: 'Vàng',
      selectedHeroId: 'kaelen',
      heroLevel: 38,
      isOnline: true,
      statusText: 'Sẵn sàng ghép đội 2v2/4v4',
    ),
    FriendInfo(
      code: 'GR2048',
      name: 'NovaBlade_07',
      rankPoints: 1680,
      rankTier: 'Bạch Kim',
      selectedHeroId: 'nova_blade',
      heroLevel: 45,
      isOnline: true,
      statusText: 'Đang ở Sảnh Chờ',
    ),
    FriendInfo(
      code: 'GR3099',
      name: 'Garrick_CổĐại',
      rankPoints: 1410,
      rankTier: 'Vàng',
      selectedHeroId: 'garrick',
      heroLevel: 29,
      isOnline: true,
      statusText: 'Tìm đội leo Rank',
    ),
    FriendInfo(
      code: 'GR7777',
      name: 'Shadow_01',
      rankPoints: 1850,
      rankTier: 'Kim Cương',
      selectedHeroId: 'shadow_01',
      heroLevel: 64,
      isOnline: true,
      statusText: 'Sẵn sàng chiến đấu',
    ),
    FriendInfo(
      code: 'GR9001',
      name: 'Valeria_BăngHỏa',
      rankPoints: 1740,
      rankTier: 'Bạch Kim',
      selectedHeroId: 'valeria',
      heroLevel: 52,
      isOnline: true,
      statusText: 'Đang Online',
    ),
  ];

  void _seedInitialFriends() {
    if (friendsNotifier.value.isEmpty) {
      friendsNotifier.value = [
        suggestedCommunityPlayers[0],
        suggestedCommunityPlayers[1],
        suggestedCommunityPlayers[2],
      ];
    }
  }

  /// Lấy mã định danh duy nhất cho phiên hiện tại (mỗi tab Chrome có UID/mã riêng)
  String get effectivePlayerCode {
    try {
      if (Firebase.apps.isNotEmpty) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.length >= 4) {
          return 'GR${uid.substring(0, 4).toUpperCase()}';
        }
      }
    } catch (_) {}
    final prof = PlayerStorage.currentProfile;
    if (prof.playerCode != 'GR8899' && prof.playerCode.isNotEmpty) {
      return prof.playerCode.toUpperCase();
    }
    return _sessionPlayerCode;
  }

  String get effectivePlayerName {
    final prof = PlayerStorage.currentProfile;
    final code = effectivePlayerCode;
    if (prof.playerName == 'Chiến Binh #88') {
      return 'Chiến Binh #${code.replaceAll('GR', '')}';
    }
    return prof.playerName;
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

  /// Đăng ký hồ sơ người chơi lên Firebase để người chơi khác có thể tìm theo Mã ID
  Future<void> syncOwnProfileToDirectory(PlayerProfile profile) async {
    try {
      final db = _getDb();
      if (db == null) return;
      final myCode = effectivePlayerCode;
      final myName = effectivePlayerName;
      await db.ref('directory/$myCode').set({
        'code': myCode,
        'name': myName,
        'rankPoints': profile.rankPoints,
        'rankTier': profile.rankTier,
        'selectedHeroId': profile.selectedHeroId,
        'heroLevel': profile.getHeroLevel(),
        'isOnline': true,
        'statusText': 'Đang Online',
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('FriendPartyService sync directory fallback: $e');
    }
  }

  /// Kết bạn theo Mã ID (VD: GR1024) hoặc tên nhân vật
  Future<FriendInfo?> addFriendByCodeOrName(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();

    for (final existing in friendsNotifier.value) {
      if (existing.code.toUpperCase() == upper ||
          existing.name.toLowerCase() == clean.toLowerCase()) {
        return existing;
      }
    }

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

    FriendInfo? match;
    for (final candidate in suggestedCommunityPlayers) {
      if (candidate.code.toUpperCase() == upper ||
          candidate.name.toLowerCase().contains(clean.toLowerCase())) {
        match = candidate;
        break;
      }
    }

    match ??= FriendInfo(
      code: upper.startsWith('GR')
          ? upper
          : 'GR${(1000 + clean.hashCode.abs() % 8999)}',
      name: clean,
      rankPoints: PlayerStorage.currentProfile.rankPoints,
      rankTier: PlayerStorage.currentProfile.rankTier,
      selectedHeroId: 'kaelen',
      heroLevel: max(5, PlayerStorage.currentProfile.getHeroLevel()),
      isOnline: true,
      statusText: 'Vừa kết bạn • Đang Online',
    );

    _appendFriend(match);
    return match;
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
    final created = PartyRoomState(
      partyCode: partyCode,
      leaderCode: myCode,
      leaderName: myName,
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
      mode: mode,
      members: allMembers,
    );
  }

  /// Mời bạn bè vào Tổ Đội hiện tại
  bool inviteFriendToParty(
    FriendInfo friend, {
    PvpGameMode preferredMode = PvpGameMode.duo2v2,
  }) {
    var party = partyNotifier.value;
    if (party == null) {
      final targetMode = preferredMode == PvpGameMode.solo1v1
          ? PvpGameMode.duo2v2
          : preferredMode;
      party = createOrUpdateParty(mode: targetMode);
    } else if (party.mode == PvpGameMode.solo1v1) {
      party = createOrUpdateParty(mode: PvpGameMode.duo2v2);
    }

    if (party.isFull) return false;
    if (party.members.any((m) => m.code == friend.code)) return true;

    final updatedMembers = List<FriendInfo>.from(party.members)..add(friend);
    final updated = party.copyWith(members: updatedMembers);
    partyNotifier.value = updated;
    unawaited(_syncPartyEverywhere(updated));
    return true;
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

    // Nếu mã phòng chưa có trên hệ thống -> Tạo phòng với mã đó và thêm đồng đội
    final ally = friendsNotifier.value.isNotEmpty
        ? friendsNotifier.value.first
        : suggestedCommunityPlayers.first;
    final joined = PartyRoomState(
      partyCode: code.isEmpty ? 'TEAM888' : code,
      leaderCode: myCode,
      leaderName: myName,
      mode: fallbackMode == PvpGameMode.solo1v1
          ? PvpGameMode.duo2v2
          : fallbackMode,
      members: [ally],
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
    _partySubscription?.cancel();
    _partySubscription = null;
    _localPollTimer?.cancel();
    _localPollTimer = null;
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
        'mode': party.mode.code,
        'members': party.members.map((m) => m.toJson()).toList(),
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }
}
