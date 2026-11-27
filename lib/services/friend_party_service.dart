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
import '../registry/asset_registry.dart';
import 'player_storage.dart';

/// Dịch vụ quản lý Kết Bạn (Friends + Friend Requests + Online Presence)
/// và Phòng Tổ Đội (Party Invite) cho PvP 1v1 / 2v2 / 4v4.
class FriendPartyService {
  FriendPartyService._() {
    _seedInitialFriends();
    _initListenersForCode(effectivePlayerCode);
  }

  static final FriendPartyService instance = FriendPartyService._();

  static const String _localPartyPrefix = 'big_war_shared_party_';
  static const String _localInvitePrefix = 'big_war_shared_invite_';
  static const String _localInviteRespPrefix = 'big_war_shared_invite_resp_';
  static const String _localDirectoryPrefix = 'big_war_shared_directory_';
  static const String _localFriendReqPrefix = 'big_war_shared_friend_req_';
  static const String _localFriendReqRespPrefix =
      'big_war_shared_friend_req_resp_';
  static const String _localFriendshipsPrefix =
      'big_war_shared_friendships_';
  static const String _localSoloPrefix = 'big_war_shared_solo_';

  /// Mã phiên dự phòng nếu hồ sơ chưa có mã định danh riêng
  final String _sessionPlayerCode = 'GR${1000 + Random().nextInt(8999)}';

  final ValueNotifier<List<FriendInfo>> friendsNotifier =
      ValueNotifier<List<FriendInfo>>([]);

  final ValueNotifier<List<FriendRequest>> incomingFriendRequestsNotifier =
      ValueNotifier<List<FriendRequest>>([]);

  final ValueNotifier<FriendRequest?> incomingFriendRequestPopupNotifier =
      ValueNotifier<FriendRequest?>(null);

  final ValueNotifier<FriendRequest?> friendRequestResponseNotifier =
      ValueNotifier<FriendRequest?>(null);

  final ValueNotifier<PartyRoomState?> partyNotifier =
      ValueNotifier<PartyRoomState?>(null);

  final ValueNotifier<PartyInvitation?> incomingInviteNotifier =
      ValueNotifier<PartyInvitation?>(null);

  final ValueNotifier<PartyInvitation?> inviteResponseNotifier =
      ValueNotifier<PartyInvitation?>(null);

  final ValueNotifier<SoloDuelRoomState?> soloRoomNotifier =
      ValueNotifier<SoloDuelRoomState?>(null);

  final ValueNotifier<String?> soloRoomNoticeNotifier =
      ValueNotifier<String?>(null);

  final Map<String, StreamSubscription<DatabaseEvent>> _friendDirSubscriptions =
      {};
  final Map<String, FriendInfo> _firebaseDirCache = {};
  final Set<String> _seenFriendRequestIds = {};
  final Set<String> _seenInviteIds = {};

  StreamSubscription<DatabaseEvent>? _partySubscription;
  StreamSubscription<DatabaseEvent>? _soloRoomSubscription;
  StreamSubscription<DatabaseEvent>? _inviteSubscription;
  StreamSubscription<DatabaseEvent>? _inviteRespSubscription;
  StreamSubscription<DatabaseEvent>? _friendReqSubscription;
  StreamSubscription<DatabaseEvent>? _friendReqRespSubscription;
  StreamSubscription<DatabaseEvent>? _friendshipsSubscription;
  StreamSubscription<DatabaseEvent>? _connectedSubscription;

  Timer? _localPollTimer;
  Timer? _soloLocalPollTimer;
  Timer? _invitationPollTimer;
  Timer? _presenceHeartbeatTimer;

  String? _watchedPartyCode;
  String? _watchedSoloCode;
  String? _activeListenerCode;
  bool _isExplicitlyOffline = false;

  static const List<FriendInfo> suggestedCommunityPlayers = [];

  void _seedInitialFriends() {
    const mockCodes = {
      'GR1024',
      'GR2048',
      'GR3099',
      'GR7777',
      'GR9001',
      'GR4040',
      'GR5050',
    };
    final current = friendsNotifier.value;
    final cleaned =
        current.where((f) => !mockCodes.contains(f.code.toUpperCase())).toList();
    if (cleaned.length != current.length) {
      friendsNotifier.value = cleaned;
    }
  }

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

  /// Kiểm tra xem mã hoặc tên có thuộc về chính bản thân người chơi hay không
  bool isSelfPlayer({String? code, String? name}) {
    final prof = PlayerStorage.currentProfile;
    final myCodes = <String>{
      effectivePlayerCode.toUpperCase(),
      prof.playerCode.toUpperCase(),
      _sessionPlayerCode.toUpperCase(),
    }..removeWhere((c) => c.isEmpty);

    final myNames = <String>{
      effectivePlayerName.toLowerCase(),
      prof.playerName.toLowerCase(),
    }..removeWhere((n) => n.isEmpty);

    if (code != null) {
      final cleanCode = code.trim().toUpperCase();
      if (cleanCode.isNotEmpty && myCodes.contains(cleanCode)) {
        return true;
      }
    }
    if (name != null) {
      final cleanName = name.trim().toLowerCase();
      if (cleanName.isNotEmpty && myNames.contains(cleanName)) {
        return true;
      }
    }
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid != null && authUid.isNotEmpty) {
        if (code != null && code.trim() == authUid) return true;
        if (name != null && name.trim() == authUid) return true;
      }
    } catch (_) {}

    return false;
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

  // =========================================================================
  // KHỞI TẠO PHIÊN, ONLINE PRESENCE & ĐỒNG BỘ DANH SÁCH BẠN BÈ BỀN VỮNG
  // =========================================================================

  /// Khởi tạo toàn bộ hệ thống bạn bè, trạng thái Online và lắng nghe lời mời cho user hiện tại
  Future<void> initializeForCurrentUser(PlayerProfile profile) async {
    _isExplicitlyOffline = false;
    await syncOwnProfileToDirectory(profile, isOnline: true);
    final myCode = effectivePlayerCode;
    if (_activeListenerCode != myCode) {
      _initListenersForCode(myCode);
    }
    await loadAndSubscribeFriends(profile);
  }

  /// Đặt trạng thái Online khi quay lại ứng dụng
  Future<void> setOnlinePresence(PlayerProfile profile) async {
    _isExplicitlyOffline = false;
    await syncOwnProfileToDirectory(profile, isOnline: true);
  }

  /// Đặt trạng thái Ngoại tuyến ngay lập tức (khi tắt app / ẩn app / đăng xuất)
  Future<void> setOfflinePresence() async {
    _isExplicitlyOffline = true;
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;

    final myCode = effectivePlayerCode;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_localDirectoryPrefix$myCode';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map['isOnline'] = false;
        map['statusText'] = 'Ngoại tuyến';
        map['updatedAt'] = now;
        await prefs.setString(key, jsonEncode(map));
      }
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('directory/$myCode').update({
          'isOnline': false,
          'statusText': 'Ngoại tuyến',
          'updatedAt': ServerValue.timestamp,
        });
      }
    } catch (_) {}
  }

  /// Dọn dẹp khi người chơi đăng xuất (phải gọi trước khi FirebaseAuth.signOut())
  Future<void> onUserLoggedOut() async {
    await setOfflinePresence();
    _cancelAllSubscriptions();
    _activeListenerCode = null;
    _seenFriendRequestIds.clear();
    _seenInviteIds.clear();
    _firebaseDirCache.clear();
    friendsNotifier.value = [];
    incomingFriendRequestsNotifier.value = [];
    incomingFriendRequestPopupNotifier.value = null;
    friendRequestResponseNotifier.value = null;
    incomingInviteNotifier.value = null;
    inviteResponseNotifier.value = null;
    partyNotifier.value = null;
    soloRoomNotifier.value = null;
    soloRoomNoticeNotifier.value = null;
  }

  /// Dừng toàn bộ Timer & Subscription (dùng khi dọn dẹp hoặc trong test)
  void stopPolling() => _cancelAllSubscriptions();

  void _cancelAllSubscriptions() {
    _partySubscription?.cancel();
    _partySubscription = null;
    _soloRoomSubscription?.cancel();
    _soloRoomSubscription = null;
    _inviteSubscription?.cancel();
    _inviteSubscription = null;
    _inviteRespSubscription?.cancel();
    _inviteRespSubscription = null;
    _friendReqSubscription?.cancel();
    _friendReqSubscription = null;
    _friendReqRespSubscription?.cancel();
    _friendReqRespSubscription = null;
    _friendshipsSubscription?.cancel();
    _friendshipsSubscription = null;
    _connectedSubscription?.cancel();
    _connectedSubscription = null;
    _localPollTimer?.cancel();
    _localPollTimer = null;
    _soloLocalPollTimer?.cancel();
    _soloLocalPollTimer = null;
    _invitationPollTimer?.cancel();
    _invitationPollTimer = null;
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;
    _watchedPartyCode = null;
    _watchedSoloCode = null;
    for (final sub in _friendDirSubscriptions.values) {
      sub.cancel();
    }
    _friendDirSubscriptions.clear();
  }

  /// Đăng ký hồ sơ người chơi lên Firebase & SharedPreferences kèm Firebase onDisconnect()
  Future<void> syncOwnProfileToDirectory(
    PlayerProfile profile, {
    bool isOnline = true,
  }) async {
    final myCode = profile.playerCode.isNotEmpty && profile.playerCode != 'GR8899'
        ? profile.playerCode.toUpperCase()
        : effectivePlayerCode;
    final myName =
        profile.playerName.isNotEmpty && profile.playerName != 'Chiến Binh #88'
            ? profile.playerName
            : effectivePlayerName;

    final effectiveOnline = isOnline && !_isExplicitlyOffline;
    final data = {
      'code': myCode,
      'name': myName,
      'rankPoints': profile.rankPoints,
      'rankStars': profile.rankStars,
      'rankTier': profile.rankTier,
      'selectedHeroId': profile.selectedHeroId,
      'heroLevel': profile.getHeroLevel(),
      'totalMatches': profile.totalMatches,
      'totalWins': profile.totalWins,
      'unlockedHeroCount': profile.unlockedHeroIds.length,
      'pveHighestFloor': profile.pveHighestFloor,
      'isChallengerTop10': profile.isChallengerTop10,
      if (profile.serverRank != null) 'serverRank': profile.serverRank,
      'winRateText': profile.winRateDisplay,
      'isOnline': effectiveOnline,
      'statusText': effectiveOnline ? 'Đang Online' : 'Ngoại tuyến',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_localDirectoryPrefix$myCode', jsonEncode(data));
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        final ref = db.ref('directory/$myCode');
        await ref.set({
          ...data,
          'updatedAt': ServerValue.timestamp,
        });
        if (effectiveOnline) {
          await ref.onDisconnect().update({
            'isOnline': false,
            'statusText': 'Ngoại tuyến',
            'updatedAt': ServerValue.timestamp,
          });
          _ensureConnectedPresenceListener(myCode);
        }
      }
    } catch (e) {
      debugPrint('FriendPartyService sync directory fallback: $e');
    }

    if (effectiveOnline) {
      _startPresenceHeartbeat(myCode);
    }
  }

  void _ensureConnectedPresenceListener(String myCode) {
    final db = _getDb();
    if (db == null) return;
    _connectedSubscription?.cancel();
    _connectedSubscription =
        db.ref('.info/connected').onValue.listen((event) async {
      final connected = event.snapshot.value == true;
      if (connected && !_isExplicitlyOffline && _activeListenerCode == myCode) {
        try {
          final ref = db.ref('directory/$myCode');
          await ref.onDisconnect().update({
            'isOnline': false,
            'statusText': 'Ngoại tuyến',
            'updatedAt': ServerValue.timestamp,
          });
          await ref.update({
            'isOnline': true,
            'statusText': 'Đang Online',
            'updatedAt': ServerValue.timestamp,
          });
        } catch (_) {}
      }
    }, onError: (_) {});
  }

  void _startPresenceHeartbeat(String myCode) {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer =
        Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_isExplicitlyOffline || effectivePlayerCode != myCode) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = '$_localDirectoryPrefix$myCode';
        final raw = prefs.getString(key);
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          map['isOnline'] = true;
          map['statusText'] = 'Đang Online';
          map['updatedAt'] = now;
          await prefs.setString(key, jsonEncode(map));
        }
      } catch (_) {}

      try {
        final db = _getDb();
        if (db != null) {
          await db.ref('directory/$myCode').update({
            'isOnline': true,
            'statusText': 'Đang Online',
            'updatedAt': ServerValue.timestamp,
          });
        }
      } catch (_) {}
    });
  }

  /// Khôi phục danh sách bạn bè từ Profile, Local Storage & Firebase `friendships`
  /// và đăng ký lắng nghe trạng thái Online/Offline Realtime của từng bạn bè.
  Future<void> loadAndSubscribeFriends(PlayerProfile profile) async {
    final myCode = effectivePlayerCode;
    final mergedCodes = <String>{
      for (final id in profile.friendIds)
        if (id.trim().isNotEmpty && !isSelfPlayer(code: id))
          id.trim().toUpperCase(),
    };

    // 1. Đọc từ Local SharedPreferences friendships
    try {
      final localCodes = await _readLocalFriendshipCodes(myCode);
      for (final code in localCodes) {
        if (!isSelfPlayer(code: code)) {
          mergedCodes.add(code.toUpperCase());
        }
      }
    } catch (_) {}

    // 2. Đọc từ Firebase `friendships/$myCode`
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('friendships/$myCode').get();
        if (snap.exists && snap.value is Map) {
          final map = Map<dynamic, dynamic>.from(snap.value as Map);
          map.forEach((k, v) {
            if (v == true) {
              final code = k.toString().trim().toUpperCase();
              if (code.isNotEmpty && !isSelfPlayer(code: code)) {
                mergedCodes.add(code);
              }
            }
          });
        }

        // Đồng bộ ngược lại các bạn từ profile cũ lên node friendships nếu còn thiếu
        for (final code in mergedCodes) {
          unawaited(db.ref('friendships/$myCode/$code').set(true));
        }
      }
    } catch (_) {}

    // 3. Lưu lại friendIds vào profile nếu có thay đổi từ server
    final currentProfileIds =
        profile.friendIds.map((e) => e.trim().toUpperCase()).toSet();
    if (mergedCodes.length != currentProfileIds.length ||
        !mergedCodes.containsAll(currentProfileIds)) {
      await PlayerStorage.saveProfile(
        profile.copyWith(friendIds: mergedCodes.toList()),
      );
    }

    // 4. Lưu vào local friendships
    await _saveLocalFriendshipCodes(myCode, mergedCodes.toList());

    // 5. Nạp thông tin & đăng ký realtime status cho từng bạn bè
    final initialList = <FriendInfo>[];
    for (final code in mergedCodes) {
      final info = await _fetchLatestFriendInfo(code);
      initialList.add(
        info ??
            FriendInfo(
              code: code,
              name: 'Chiến Binh #${code.replaceAll('GR', '')}',
              rankPoints: 1000,
              rankTier: PvpEloCalculator.getRankTier(1000),
              selectedHeroId: 'george',
              heroLevel: 1,
              isOnline: false,
              statusText: 'Ngoại tuyến',
            ),
      );
      _subscribeToFriendDirectory(code);
    }

    _setSortedFriends(initialList);
  }

  void _setSortedFriends(List<FriendInfo> list) {
    final sorted = List<FriendInfo>.from(list)
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) {
          return a.isOnline ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    friendsNotifier.value = sorted;
  }

  Future<FriendInfo?> _fetchLatestFriendInfo(String friendCode) async {
    final cleanCode = friendCode.trim().toUpperCase();

    // 1. Firebase directory
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('directory/$cleanCode').get();
        if (snap.exists && snap.value != null) {
          final norm = _normalizeMap(snap.value);
          if (norm != null) {
            final info = FriendInfo.fromJson(norm);
            _firebaseDirCache[cleanCode] = info;
            return info;
          }
        }
      }
    } catch (_) {}

    // 2. Local SharedPreferences directory
    return _readLocalDirectoryFriend(cleanCode);
  }

  Future<FriendInfo?> _readLocalDirectoryFriend(String cleanCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localDirectoryPrefix$cleanCode');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) {
          final norm = _normalizeMap(map);
          if (norm != null) {
            final parsed = FriendInfo.fromJson(norm);
            // Nếu tab/instance local tắt đột ngột không cập nhật heartbeat quá 50s -> Offline
            if (parsed.isOnline && parsed.updatedAt > 0) {
              final age = DateTime.now().millisecondsSinceEpoch - parsed.updatedAt;
              if (age > 50000) {
                return parsed.copyWith(
                  isOnline: false,
                  statusText: 'Ngoại tuyến',
                );
              }
            }
            return parsed;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _subscribeToFriendDirectory(String friendCode) {
    final cleanCode = friendCode.trim().toUpperCase();
    if (cleanCode.isEmpty || isSelfPlayer(code: cleanCode)) return;
    if (_friendDirSubscriptions.containsKey(cleanCode)) return;

    final db = _getDb();
    if (db == null) return;

    _friendDirSubscriptions[cleanCode] =
        db.ref('directory/$cleanCode').onValue.listen((event) {
      final norm = _normalizeMap(event.snapshot.value);
      if (norm == null) return;
      final updated = FriendInfo.fromJson(norm);
      _firebaseDirCache[cleanCode] = updated;
      _upsertFriendInNotifier(updated);
    }, onError: (_) {});
  }

  void _upsertFriendInNotifier(FriendInfo friend) {
    final cleanCode = friend.code.trim().toUpperCase();
    final current = List<FriendInfo>.from(friendsNotifier.value);
    final idx = current.indexWhere((f) => f.code.toUpperCase() == cleanCode);
    if (idx >= 0) {
      current[idx] = friend;
    } else {
      current.add(friend);
    }
    _setSortedFriends(current);
  }

  // =========================================================================
  // YÊU CẦU KẾT BẠN (FRIEND REQUESTS -> ACCEPT / DECLINE)
  // =========================================================================

  /// Kiểm tra người chơi có trong danh sách bạn bè hiện tại hay không
  bool isFriendPlayer({String? code, String? name}) {
    final cleanCode = code?.trim().toUpperCase() ?? '';
    final cleanName = name?.trim().toLowerCase() ?? '';
    for (final f in friendsNotifier.value) {
      if (cleanCode.isNotEmpty && f.code.trim().toUpperCase() == cleanCode) {
        return true;
      }
      if (cleanName.isNotEmpty && f.name.trim().toLowerCase() == cleanName) {
        return true;
      }
    }
    return false;
  }

  /// Tra cứu thông tin hồ sơ công khai mới nhất của một người chơi khác từ Directory
  Future<FriendInfo?> lookupPublicProfile({String? code, String? name}) async {
    final cleanCode = code?.trim().toUpperCase() ?? '';
    if (cleanCode.isNotEmpty) {
      final byCode = await _fetchLatestFriendInfo(cleanCode);
      if (byCode != null) return byCode;
    }
    final cleanName = name?.trim() ?? '';
    if (cleanName.isNotEmpty) {
      return _findPlayerInDirectory(cleanName);
    }
    return null;
  }

  /// Tìm người chơi thật trong hệ thống theo Mã ID hoặc Tên hiển thị
  Future<FriendInfo?> _findPlayerInDirectory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return null;
    final upper = clean.toUpperCase();

    // 1. Tìm trực tiếp theo Mã ID trên Firebase
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('directory/$upper').get();
        if (snap.exists && snap.value != null) {
          final norm = _normalizeMap(snap.value);
          if (norm != null) {
            return FriendInfo.fromJson(norm);
          }
        }
      }
    } catch (_) {}

    // 2. Tìm trực tiếp theo Mã ID trong SharedPreferences
    final localByCode = await _readLocalDirectoryFriend(upper);
    if (localByCode != null) return localByCode;

    // 3. Tìm theo Tên người chơi trong SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_localDirectoryPrefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final map = jsonDecode(raw);
        if (map is Map) {
          final norm = _normalizeMap(map);
          if (norm != null) {
            final candidate = FriendInfo.fromJson(norm);
            if (candidate.name.trim().toLowerCase() == clean.toLowerCase()) {
              return candidate;
            }
          }
        }
      }
    } catch (_) {}

    // 4. Tìm theo Tên người chơi trong Firebase directory
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('directory').get();
        if (snap.exists && snap.value is Map) {
          final all = Map<dynamic, dynamic>.from(snap.value as Map);
          for (final entry in all.values) {
            final norm = _normalizeMap(entry);
            if (norm != null) {
              final candidate = FriendInfo.fromJson(norm);
              if (candidate.name.trim().toLowerCase() == clean.toLowerCase()) {
                return candidate;
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Gửi lời mời kết bạn tới người chơi khác (cần người nhận Đồng ý)
  Future<FriendRequestSendResult> sendFriendRequest(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return const FriendRequestSendResult(
        status: FriendRequestSendStatus.notFound,
      );
    }
    final upper = clean.toUpperCase();

    if (isSelfPlayer(code: upper, name: clean)) {
      return const FriendRequestSendResult(
        status: FriendRequestSendStatus.isSelf,
      );
    }

    // Kiểm tra đã là bạn bè chưa
    for (final existing in friendsNotifier.value) {
      if (existing.code.toUpperCase() == upper ||
          existing.name.toLowerCase() == clean.toLowerCase()) {
        return FriendRequestSendResult(
          status: FriendRequestSendStatus.alreadyFriends,
          targetFriend: existing,
        );
      }
    }

    final target = await _findPlayerInDirectory(clean);
    if (target == null || isSelfPlayer(code: target.code, name: target.name)) {
      if (isSelfPlayer(code: upper, name: clean)) {
        return const FriendRequestSendResult(
          status: FriendRequestSendStatus.isSelf,
        );
      }
      return const FriendRequestSendResult(
        status: FriendRequestSendStatus.notFound,
      );
    }

    final targetCode = target.code.toUpperCase();
    if (friendsNotifier.value.any((f) => f.code.toUpperCase() == targetCode)) {
      return FriendRequestSendResult(
        status: FriendRequestSendStatus.alreadyFriends,
        targetFriend: target,
      );
    }

    // Nếu đối phương đã gửi yêu cầu kết bạn cho mình từ trước -> tự động đồng ý thành bạn luôn!
    final incomingFromTarget = incomingFriendRequestsNotifier.value
        .where((r) => r.fromCode.toUpperCase() == targetCode)
        .toList();
    if (incomingFromTarget.isNotEmpty) {
      await respondToFriendRequest(incomingFromTarget.first, accept: true);
      return FriendRequestSendResult(
        status: FriendRequestSendStatus.autoAccepted,
        targetFriend: target,
      );
    }

    final myCode = effectivePlayerCode;
    // Kiểm tra đã gửi yêu cầu pending trước đó chưa
    final alreadySent = await _hasPendingOutgoingRequest(myCode, targetCode);
    if (alreadySent) {
      return FriendRequestSendResult(
        status: FriendRequestSendStatus.alreadySent,
        targetFriend: target,
      );
    }

    final prof = PlayerStorage.currentProfile;
    final req = FriendRequest(
      id: 'FREQ_${myCode}_$targetCode',
      fromCode: myCode,
      fromName: effectivePlayerName,
      fromRankPoints: prof.rankPoints,
      fromRankTier: prof.rankTier,
      fromHeroId: prof.selectedHeroId,
      fromHeroLevel: prof.getHeroLevel(),
      toCode: targetCode,
      toName: target.name,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
    );

    await _saveFriendRequestEverywhere(req);
    return FriendRequestSendResult(
      status: FriendRequestSendStatus.sent,
      targetFriend: target,
    );
  }

  Future<bool> _hasPendingOutgoingRequest(
    String myCode,
    String targetCode,
  ) async {
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('friend_requests/$targetCode/$myCode').get();
        if (snap.exists && snap.value is Map) {
          final map = _normalizeMap(snap.value);
          if (map != null && (map['status'] as String? ?? 'pending') == 'pending') {
            return true;
          }
        }
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localFriendReqPrefix$targetCode');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map && map[myCode] is Map) {
          final reqMap = _normalizeMap(map[myCode]);
          if (reqMap != null &&
              (reqMap['status'] as String? ?? 'pending') == 'pending') {
            return true;
          }
        }
      }
    } catch (_) {}

    return false;
  }

  Future<void> _saveFriendRequestEverywhere(FriendRequest req) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final key = '$_localFriendReqPrefix${req.toCode}';
      Map<String, dynamic> map = {};
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        }
      }
      map[req.fromCode] = req.toJson();
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db
            .ref('friend_requests/${req.toCode}/${req.fromCode}')
            .set(req.toJson());
      }
    } catch (_) {}
  }

  /// Người nhận phản hồi lời mời kết bạn: Đồng ý (accept = true) hoặc Từ chối (accept = false)
  Future<void> respondToFriendRequest(
    FriendRequest req, {
    required bool accept,
  }) async {
    final myCode = effectivePlayerCode;
    final fromCode = req.fromCode.toUpperCase();

    // 1. Gỡ khỏi danh sách yêu cầu pending & popup
    final remaining = List<FriendRequest>.from(incomingFriendRequestsNotifier.value)
      ..removeWhere((r) => r.fromCode.toUpperCase() == fromCode);
    incomingFriendRequestsNotifier.value = remaining;
    if (incomingFriendRequestPopupNotifier.value?.fromCode.toUpperCase() ==
        fromCode) {
      incomingFriendRequestPopupNotifier.value = null;
    }

    // 2. Xóa request trên Firebase & LocalPrefs
    await _removeFriendRequestEverywhere(myCode, fromCode);

    // 3. Gửi phản hồi về cho người gửi
    final response = req.copyWith(status: accept ? 'accepted' : 'declined');
    await _sendFriendReqResponseEverywhere(response);

    if (accept) {
      // 4. Ghi quan hệ bạn bè 2 chiều (Firebase + LocalPrefs + Profile)
      await _persistMutualFriendship(myCode, fromCode);
      final latestInfo = await _fetchLatestFriendInfo(fromCode);
      _appendFriend(latestInfo ?? req.toFriendInfo(isOnline: true));
      _subscribeToFriendDirectory(fromCode);
    }
  }

  Future<void> _removeFriendRequestEverywhere(
    String toCode,
    String fromCode,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final key = '$_localFriendReqPrefix$toCode';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded)..remove(fromCode);
          await prefs.setString(key, jsonEncode(map));
        }
      }
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('friend_requests/$toCode/$fromCode').remove();
      }
    } catch (_) {}
  }

  Future<void> _sendFriendReqResponseEverywhere(FriendRequest response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_localFriendReqRespPrefix${response.fromCode}',
        jsonEncode(response.toJson()),
      );
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db
            .ref('friend_request_responses/${response.fromCode}')
            .set(response.toJson());
      }
    } catch (_) {}
  }

  Future<void> _persistMutualFriendship(String codeA, String codeB) async {
    final a = codeA.trim().toUpperCase();
    final b = codeB.trim().toUpperCase();
    if (a.isEmpty || b.isEmpty || a == b) return;

    // Local SharedPreferences cho cả 2 phía
    try {
      final listA = (await _readLocalFriendshipCodes(a))..add(b);
      await _saveLocalFriendshipCodes(a, listA);
      final listB = (await _readLocalFriendshipCodes(b))..add(a);
      await _saveLocalFriendshipCodes(b, listB);
    } catch (_) {}

    // Firebase Realtime Database cho cả 2 phía
    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('friendships/$a/$b').set(true);
        await db.ref('friendships/$b/$a').set(true);
      }
    } catch (_) {}
  }

  Future<Set<String>> _readLocalFriendshipCodes(String code) async {
    final result = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localFriendshipsPrefix$code');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            final clean = e.toString().trim().toUpperCase();
            if (clean.isNotEmpty) result.add(clean);
          }
        }
      }
    } catch (_) {}
    return result;
  }

  Future<void> _saveLocalFriendshipCodes(String code, Iterable<String> codes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final unique = codes.map((e) => e.trim().toUpperCase()).toSet().toList();
      await prefs.setString('$_localFriendshipsPrefix$code', jsonEncode(unique));
    } catch (_) {}
  }

  void _appendFriend(FriendInfo friend) {
    final cleanCode = friend.code.trim().toUpperCase();
    final normalized = friend.copyWith(code: cleanCode);
    _upsertFriendInNotifier(normalized);
    _subscribeToFriendDirectory(cleanCode);

    final prof = PlayerStorage.currentProfile;
    if (!prof.friendIds.any((e) => e.toUpperCase() == cleanCode)) {
      final updatedIds = List<String>.from(prof.friendIds)..add(cleanCode);
      PlayerStorage.saveProfile(prof.copyWith(friendIds: updatedIds));
    }
  }

  Future<void> removeFriend(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final myCode = effectivePlayerCode;

    final current = List<FriendInfo>.from(friendsNotifier.value)
      ..removeWhere((f) => f.code.toUpperCase() == cleanCode);
    friendsNotifier.value = current;
    removeMemberFromParty(cleanCode);

    _friendDirSubscriptions.remove(cleanCode)?.cancel();

    final prof = PlayerStorage.currentProfile;
    if (prof.friendIds.any((e) => e.toUpperCase() == cleanCode)) {
      final updatedIds = prof.friendIds
          .where((e) => e.toUpperCase() != cleanCode)
          .toList();
      await PlayerStorage.saveProfile(prof.copyWith(friendIds: updatedIds));
    }

    try {
      final listA = (await _readLocalFriendshipCodes(myCode))..remove(cleanCode);
      await _saveLocalFriendshipCodes(myCode, listA);
      final listB = (await _readLocalFriendshipCodes(cleanCode))..remove(myCode);
      await _saveLocalFriendshipCodes(cleanCode, listB);
    } catch (_) {}

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('friendships/$myCode/$cleanCode').remove();
        await db.ref('friendships/$cleanCode/$myCode').remove();
      }
    } catch (_) {}
  }

  // =========================================================================
  // LẮNG NGHE REALTIME: YÊU CẦU KẾT BẠN, BẠN BÈ, LỜI MỜI TỔ ĐỘI
  // =========================================================================

  void _initListenersForCode(String myCode) {
    _activeListenerCode = myCode;
    _startLocalPolling(myCode);
    _startFirebaseListeners(myCode);
  }

  void _mergeIncomingFriendRequests(List<FriendRequest> freshList) {
    final myCode = effectivePlayerCode;
    final currentFriends =
        friendsNotifier.value.map((f) => f.code.toUpperCase()).toSet();

    final filtered = freshList
        .where(
          (r) =>
              r.status == 'pending' &&
              r.fromCode.isNotEmpty &&
              r.toCode.toUpperCase() == myCode &&
              !isSelfPlayer(code: r.fromCode) &&
              !currentFriends.contains(r.fromCode.toUpperCase()),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    incomingFriendRequestsNotifier.value = filtered;

    // Kích hoạt pop-up thông báo 5 giây cho yêu cầu mới chưa hiển thị
    for (final req in filtered) {
      if (!_seenFriendRequestIds.contains(req.id)) {
        _seenFriendRequestIds.add(req.id);
        incomingFriendRequestPopupNotifier.value = req;
        break;
      }
    }
  }

  void _handleIncomingInviteSnapshot(PartyInvitation invite) {
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (invite.status != 'pending') return;
    if (invite.toCode.trim().toUpperCase() != myCode) return;
    if (isSelfPlayer(code: invite.fromCode)) return;
    if (_seenInviteIds.contains(invite.id)) return;
    _seenInviteIds.add(invite.id);
    incomingInviteNotifier.value = invite;
  }

  void _startLocalPolling(String myCode) {
    _invitationPollTimer?.cancel();
    _invitationPollTimer =
        Timer.periodic(const Duration(milliseconds: 900), (_) async {
      if (_activeListenerCode != myCode || _isExplicitlyOffline) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();

        // 1. Kiểm tra lời mời tổ đội đến
        final rawInvite = prefs.getString('$_localInvitePrefix$myCode');
        if (rawInvite != null && rawInvite.isNotEmpty) {
          final map = jsonDecode(rawInvite) as Map<String, dynamic>;
          final invite = PartyInvitation.fromJson(map);
          _handleIncomingInviteSnapshot(invite);
        }

        // 2. Kiểm tra phản hồi lời mời tổ đội
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

        // 3. Kiểm tra yêu cầu kết bạn đến (SharedPreferences)
        final rawFriendReq = prefs.getString('$_localFriendReqPrefix$myCode');
        if (rawFriendReq != null && rawFriendReq.isNotEmpty) {
          final decoded = jsonDecode(rawFriendReq);
          if (decoded is Map) {
            final parsedList = <FriendRequest>[];
            decoded.forEach((_, val) {
              if (val is Map) {
                final norm = _normalizeMap(val);
                if (norm != null) {
                  parsedList.add(FriendRequest.fromJson(norm));
                }
              }
            });
            if (parsedList.isNotEmpty) {
              _mergeIncomingFriendRequests(parsedList);
            }
          }
        }

        // 4. Kiểm tra phản hồi kết bạn
        final rawFriendResp =
            prefs.getString('$_localFriendReqRespPrefix$myCode');
        if (rawFriendResp != null && rawFriendResp.isNotEmpty) {
          final map = jsonDecode(rawFriendResp) as Map<String, dynamic>;
          final resp = FriendRequest.fromJson(map);
          friendRequestResponseNotifier.value = resp;
          await prefs.remove('$_localFriendReqRespPrefix$myCode');
          if (resp.status == 'accepted') {
            final info = await _fetchLatestFriendInfo(resp.toCode);
            if (info != null) _appendFriend(info);
          }
        }

        // 5. Đồng bộ lại bạn bè & trạng thái Online từ Local Directory (hữu ích khi test đa tab Chrome hoặc offline Firebase)
        final localFriendCodes = await _readLocalFriendshipCodes(myCode);
        if (localFriendCodes.isNotEmpty) {
          for (final code in localFriendCodes) {
            if (isSelfPlayer(code: code)) continue;
            if (!friendsNotifier.value.any((f) => f.code.toUpperCase() == code)) {
              final info = await _fetchLatestFriendInfo(code);
              if (info != null) _appendFriend(info);
            } else if (!_firebaseDirCache.containsKey(code)) {
              final localDir = await _readLocalDirectoryFriend(code);
              if (localDir != null) {
                _upsertFriendInNotifier(localDir);
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  void _startFirebaseListeners(String myCode) {
    try {
      final db = _getDb();
      if (db == null) return;

      // 1. Lời mời tổ đội
      _inviteSubscription?.cancel();
      _inviteSubscription =
          db.ref('invitations/$myCode').onValue.listen((event) {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm == null) return;
        final invite = PartyInvitation.fromJson(norm);
        _handleIncomingInviteSnapshot(invite);
      }, onError: (_) {});

      // 2. Phản hồi lời mời tổ đội
      _inviteRespSubscription?.cancel();
      _inviteRespSubscription =
          db.ref('invitation_responses/$myCode').onValue.listen((event) {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm == null) return;
        final resp = PartyInvitation.fromJson(norm);
        if (inviteResponseNotifier.value == null ||
            inviteResponseNotifier.value?.id != resp.id) {
          inviteResponseNotifier.value = resp;
          db.ref('invitation_responses/$myCode').remove();
        }
      }, onError: (_) {});

      // 3. Yêu cầu kết bạn đến
      _friendReqSubscription?.cancel();
      _friendReqSubscription =
          db.ref('friend_requests/$myCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw == null) {
          incomingFriendRequestsNotifier.value = [];
          return;
        }
        if (raw is Map) {
          final parsedList = <FriendRequest>[];
          raw.forEach((_, val) {
            final norm = _normalizeMap(val);
            if (norm != null) {
              parsedList.add(FriendRequest.fromJson(norm));
            }
          });
          _mergeIncomingFriendRequests(parsedList);
        }
      }, onError: (_) {});

      // 4. Phản hồi yêu cầu kết bạn (khi người kia đồng ý/từ chối)
      _friendReqRespSubscription?.cancel();
      _friendReqRespSubscription =
          db.ref('friend_request_responses/$myCode').onValue.listen((event) async {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm == null) return;
        final resp = FriendRequest.fromJson(norm);
        friendRequestResponseNotifier.value = resp;
        unawaited(db.ref('friend_request_responses/$myCode').remove());
        if (resp.status == 'accepted') {
          final info = await _fetchLatestFriendInfo(resp.toCode);
          if (info != null) {
            _appendFriend(info);
          }
        }
      }, onError: (_) {});

      // 5. Theo dõi node friendships/{myCode} để tự động cập nhật khi bạn chấp nhận hoặc xóa bạn
      _friendshipsSubscription?.cancel();
      _friendshipsSubscription =
          db.ref('friendships/$myCode').onValue.listen((event) async {
        final raw = event.snapshot.value;
        final serverCodes = <String>{};
        if (raw is Map) {
          raw.forEach((k, v) {
            if (v == true) {
              final c = k.toString().trim().toUpperCase();
              if (c.isNotEmpty && !isSelfPlayer(code: c)) {
                serverCodes.add(c);
              }
            }
          });
        }
        for (final code in serverCodes) {
          if (!friendsNotifier.value.any((f) => f.code.toUpperCase() == code)) {
            final info = await _fetchLatestFriendInfo(code);
            _appendFriend(
              info ??
                  FriendInfo(
                    code: code,
                    name: 'Chiến Binh #${code.replaceAll('GR', '')}',
                    rankPoints: 1000,
                    rankTier: PvpEloCalculator.getRankTier(1000),
                    selectedHeroId: 'george',
                    heroLevel: 1,
                    isOnline: false,
                    statusText: 'Ngoại tuyến',
                  ),
            );
          }
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  // =========================================================================
  // TỔ ĐỘI (PARTY) & LỜI MỜI TỔ ĐỘI
  // =========================================================================

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

  Map<String, dynamic>? _normalizeMap(dynamic raw) {
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  bool _areMembersEqual(List<FriendInfo> a, List<FriendInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].code.toUpperCase() != b[i].code.toUpperCase() ||
          a[i].selectedHeroId != b[i].selectedHeroId ||
          a[i].heroLevel != b[i].heroLevel ||
          a[i].name != b[i].name) {
        return false;
      }
    }
    return true;
  }

  bool _areCodeListsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toUpperCase() != b[i].toUpperCase()) return false;
    }
    return true;
  }

  bool _isPartyStateChanged(PartyRoomState? current, PartyRoomState next) {
    if (current == null) return true;
    return current.partyCode != next.partyCode ||
        current.mode != next.mode ||
        current.leaderHeroId != next.leaderHeroId ||
        current.matchStatus != next.matchStatus ||
        current.activeMatchRoomId != next.activeMatchRoomId ||
        current.activeMapId != next.activeMapId ||
        current.matchSeed != next.matchSeed ||
        !_areMembersEqual(current.members, next.members) ||
        !_areCodeListsEqual(current.readyMemberCodes, next.readyMemberCodes);
  }

  void _listenToPartyRealtime(String partyCode) {
    final cleanCode = partyCode.trim().toUpperCase();
    if (_watchedPartyCode == cleanCode &&
        (_partySubscription != null || _localPollTimer != null)) {
      return;
    }

    _partySubscription?.cancel();
    _localPollTimer?.cancel();
    _watchedPartyCode = cleanCode;

    final db = _getDb();
    if (db != null) {
      _partySubscription = db.ref('parties/$cleanCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw == null) return;
        final data = _normalizeMap(raw);
        if (data == null) return;
        final parsed = _parsePartySnapshot(cleanCode, data);
        if (parsed != null && _isPartyStateChanged(partyNotifier.value, parsed)) {
          partyNotifier.value = parsed;
          unawaited(_savePartyToLocalPrefs(parsed));
        }
      }, onError: (Object err) {
        debugPrint('Party stream error: $err');
      });
    }

    _localPollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (_watchedPartyCode != cleanCode) return;
      final localParty = await _readPartyFromLocalPrefs(cleanCode);
      if (localParty != null &&
          _isPartyStateChanged(partyNotifier.value, localParty)) {
        partyNotifier.value = localParty;
      }
    });
  }

  PartyRoomState? _parsePartySnapshot(
    String code,
    Map<String, dynamic> data,
  ) {
    if (data['roomType'] == 'solo_duel' || data['closed'] == true) {
      return null;
    }
    final modeCode = data['mode'] as String? ?? '2v2';
    final mode = PvpGameMode.values.firstWhere(
      (m) => m.code == modeCode,
      orElse: () => PvpGameMode.duo2v2,
    );
    final leaderCode = data['leaderCode'] as String? ?? effectivePlayerCode;
    final leaderName = data['leaderName'] as String? ?? effectivePlayerName;
    final leaderHeroId = data['leaderHeroId'] as String? ?? 'george';
    final leaderHeroLevel = (data['leaderHeroLevel'] as num?)?.toInt() ?? 10;

    final List<FriendInfo> allMembers = [];
    final rawMembers = data['members'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map) {
          final normItem = _normalizeMap(item);
          if (normItem != null) {
            allMembers.add(FriendInfo.fromJson(normItem));
          }
        }
      }
    } else if (rawMembers is Map) {
      rawMembers.forEach((_, value) {
        if (value is Map) {
          final normItem = _normalizeMap(value);
          if (normItem != null) {
            allMembers.add(FriendInfo.fromJson(normItem));
          }
        }
      });
    }

    final List<String> readyCodes = [];
    final rawReady = data['readyMembers'];
    if (rawReady is List) {
      for (final item in rawReady) {
        final s = item.toString().trim().toUpperCase();
        if (s.isNotEmpty && !readyCodes.contains(s)) readyCodes.add(s);
      }
    } else if (!data.containsKey('readyMembers')) {
      // Tương thích ngược với snapshot cũ chưa có readyMembers
      for (final m in allMembers) {
        readyCodes.add(m.code.toUpperCase());
      }
    }

    final matchStatus = (data['matchStatus'] as String?) ?? 'idle';
    final activeMatchRoomId = data['activeMatchRoomId'] as String?;
    final activeMapId = data['activeMapId'] as String?;
    final matchSeed = (data['matchSeed'] as num?)?.toInt() ?? 0;

    return PartyRoomState(
      partyCode: code,
      leaderCode: leaderCode,
      leaderName: leaderName,
      leaderHeroId: leaderHeroId,
      leaderHeroLevel: leaderHeroLevel,
      mode: mode,
      members: allMembers,
      readyMemberCodes: readyCodes,
      matchStatus: matchStatus,
      activeMatchRoomId: activeMatchRoomId,
      activeMapId: activeMapId,
      matchSeed: matchSeed,
    );
  }

  /// Gửi lời mời vào tổ đội (CHỈ gửi lời mời, tuyệt đối không tự ý thêm vào đội
  /// khi người nhận chưa đồng ý).
  bool inviteFriendToParty(
    FriendInfo friend, {
    PvpGameMode preferredMode = PvpGameMode.squad4v4,
  }) {
    final mode = preferredMode == PvpGameMode.solo1v1
        ? PvpGameMode.squad4v4
        : preferredMode;
    var party = partyNotifier.value;
    if (party == null || party.mode == PvpGameMode.solo1v1) {
      party = createOrUpdateParty(mode: mode);
    }
    final toCode = friend.code.trim().toUpperCase();
    if (isSelfPlayer(code: toCode)) return false;
    if (party.isFull) return false;
    if (party.members.any((m) => m.code.trim().toUpperCase() == toCode)) {
      return false;
    }

    unawaited(sendPartyInvitation(friend, preferredMode: mode));
    return true;
  }

  Future<bool> sendPartyInvitation(
    FriendInfo friend, {
    PvpGameMode preferredMode = PvpGameMode.squad4v4,
  }) async {
    final mode = preferredMode == PvpGameMode.solo1v1
        ? PvpGameMode.squad4v4
        : preferredMode;
    final toCode = friend.code.trim().toUpperCase();
    if (isSelfPlayer(code: toCode)) return false;

    var party = partyNotifier.value;
    if (party == null || party.mode != mode) {
      party = createOrUpdateParty(mode: mode);
    }

    if (party.isFull) return false;
    if (party.members.any((m) => m.code.trim().toUpperCase() == toCode)) {
      return false;
    }

    // Đồng bộ phòng tổ đội lên Firebase/Prefs TRƯỚC khi gửi lời mời
    // để người nhận có thể vào phòng ngay lập tức khi bấm Đồng Ý.
    await _syncPartyEverywhere(party);

    final myCode = effectivePlayerCode.trim().toUpperCase();
    final myName = effectivePlayerName;
    final inviteId =
        'INV_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final invite = PartyInvitation(
      id: inviteId,
      partyCode: party.partyCode,
      fromCode: myCode,
      fromName: myName,
      toCode: toCode,
      toName: friend.name,
      mode: mode,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
    );

    await _saveInviteEverywhere(invite);
    return true;
  }

  Future<void> dismissExpiredInvitation(PartyInvitation invite) async {
    if (incomingInviteNotifier.value?.id == invite.id) {
      incomingInviteNotifier.value = null;
    }
    await _clearInviteEverywhere(invite);
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

  Future<void> respondToInvitation(
    PartyInvitation invite, {
    required bool accept,
    String? reason,
  }) async {
    final response = invite.copyWith(
      status: accept ? 'accepted' : 'declined',
      declineReason: reason ?? (accept ? null : 'Người chơi đã từ chối lời mời.'),
    );

    incomingInviteNotifier.value = null;
    await _sendResponseEverywhere(response);
    await _clearInviteEverywhere(invite);

    if (accept) {
      if (invite.isCustomRoom) {
        await joinSoloRoomByCode(
          invite.partyCode,
          preferredTeam: invite.preferredTeam,
        );
      } else {
        await joinPartyByCode(invite.partyCode, fallbackMode: invite.mode);
      }
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
        await db
            .ref('invitation_responses/${response.fromCode}')
            .set(response.toJson());
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

  Future<void> updateMyPartyHero(String newHeroId) async {
    final current = partyNotifier.value;
    if (current == null) return;
    final myCode = effectivePlayerCode.toUpperCase();
    PartyRoomState updated;
    if (current.leaderCode.toUpperCase() == myCode) {
      if (current.leaderHeroId == newHeroId) return;
      updated = current.copyWith(leaderHeroId: newHeroId);
    } else {
      var changed = false;
      final updatedMembers = current.members.map((m) {
        if (m.code.toUpperCase() == myCode) {
          if (m.selectedHeroId != newHeroId) {
            changed = true;
            return m.copyWith(selectedHeroId: newHeroId);
          }
        }
        return m;
      }).toList();
      if (!changed) return;
      updated = current.copyWith(members: updatedMembers);
    }
    partyNotifier.value = updated;
    await _syncPartyEverywhere(updated);
  }

  Future<PartyRoomState> joinPartyByCode(
    String rawPartyCode, {
    PvpGameMode fallbackMode = PvpGameMode.duo2v2,
    String? asGuestCode,
    String? asGuestName,
    String? asGuestHeroId,
  }) async {
    final code = rawPartyCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw ArgumentError('Mã phòng không được để trống!');
    }
    if (code.startsWith('SOLO')) {
      throw ArgumentError(
        'Mã "$code" là mã Phòng Solo 1v1! Hãy mở mục PHÒNG SOLO để nhập mã này.',
      );
    }
    final profile = PlayerStorage.currentProfile;
    final myCode = asGuestCode ?? effectivePlayerCode;
    final myName = asGuestName ?? effectivePlayerName;
    final myHeroId = asGuestHeroId ?? profile.selectedHeroId;

    final currentActive = partyNotifier.value;
    if (currentActive != null && currentActive.partyCode.toUpperCase() == code) {
      if (asGuestCode == null) {
        throw StateError('Bạn đang ở trong phòng $code này rồi!');
      }
    }

    PartyRoomState? existingParty;
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('parties/$code').get();
        if (snap.exists && snap.value != null) {
          final norm = _normalizeMap(snap.value);
          if (norm != null) {
            existingParty = _parsePartySnapshot(code, norm);
          }
        }
      }
    } catch (_) {}

    existingParty ??= await _readPartyFromLocalPrefs(code);

    if (existingParty != null) {
      if (asGuestCode == null && isSelfPlayer(code: existingParty.leaderCode)) {
        throw StateError('Bạn là chủ phòng của phòng $code, không thể tự tham gia lại!');
      }

      if (asGuestCode == null &&
          existingParty.members.any((m) => isSelfPlayer(code: m.code, name: m.name))) {
        partyNotifier.value = existingParty;
        return existingParty;
      }

      if (existingParty.isFull) {
        throw StateError(
          'Phòng $code (${existingParty.mode.shortLabel}) đã đủ ${existingParty.maxSlots} người!',
        );
      }

      final myFriendInfo = FriendInfo(
        code: myCode,
        name: myName,
        rankPoints: profile.rankPoints,
        rankTier: profile.rankTier,
        selectedHeroId: myHeroId,
        heroLevel: profile.getHeroLevel(),
        isOnline: true,
        statusText: 'Đã vào phòng $code',
      );

      final updatedMembers = List<FriendInfo>.from(existingParty.members);
      if (!updatedMembers.any((m) => m.code.toUpperCase() == myCode.toUpperCase())) {
        updatedMembers.add(myFriendInfo);
      }
      final updatedReady = List<String>.from(existingParty.readyMemberCodes);
      final upperMyCode = myCode.toUpperCase();
      if (!updatedReady.any((c) => c.toUpperCase() == upperMyCode)) {
        updatedReady.add(upperMyCode);
      }

      final joined = existingParty.copyWith(
        members: updatedMembers,
        readyMemberCodes: updatedReady,
      );
      partyNotifier.value = joined;
      await _syncPartyEverywhere(joined);
      _listenToPartyRealtime(code);
      return joined;
    }

    throw ArgumentError(
        'Không tìm thấy phòng có mã "$code"! Vui lòng kiểm tra lại mã phòng.');
  }

  /// Khách trong tổ đội bật/tắt trạng thái Sẵn Sàng
  Future<void> toggleMyReadyState() async {
    final party = partyNotifier.value;
    if (party == null) return;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (party.isLeader(myCode)) return;

    final updatedReady = List<String>.from(party.readyMemberCodes);
    final idx = updatedReady.indexWhere((c) => c.toUpperCase() == myCode);
    if (idx >= 0) {
      updatedReady.removeAt(idx);
    } else {
      updatedReady.add(myCode);
    }
    final updated = party.copyWith(readyMemberCodes: updatedReady);
    partyNotifier.value = updated;
    await _syncPartyEverywhere(updated);
  }

  /// Chủ phòng bắt đầu tìm trận cho cả tổ đội
  Future<PartyRoomState?> startPartyMatchmaking({required String mapId}) async {
    final party = partyNotifier.value;
    if (party == null) return null;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (!party.isLeader(myCode)) return null;

    final roomId =
        'party_${party.partyCode.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}';
    final seed = Random().nextInt(1 << 30);
    final updated = party.copyWith(
      matchStatus: 'searching',
      activeMatchRoomId: roomId,
      activeMapId: mapId,
      matchSeed: seed,
    );
    partyNotifier.value = updated;
    await _syncPartyEverywhere(updated);
    return updated;
  }

  /// Chủ phòng báo cả đội bước vào đấu trường
  Future<void> markPartyMatchInProgress() async {
    final party = partyNotifier.value;
    if (party == null) return;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (!party.isLeader(myCode)) return;
    if (party.matchStatus == 'in_match') return;

    final updated = party.copyWith(matchStatus: 'in_match');
    partyNotifier.value = updated;
    await _syncPartyEverywhere(updated);
  }

  /// Đưa trạng thái trận của tổ đội về 'idle' (khi hủy tìm hoặc kết thúc trận)
  Future<void> resetPartyMatchStatus() async {
    final party = partyNotifier.value;
    if (party == null) return;
    if (party.matchStatus == 'idle' && party.activeMatchRoomId == null) return;

    final updated = party.copyWith(
      matchStatus: 'idle',
      clearActiveMatch: true,
    );
    partyNotifier.value = updated;
    await _syncPartyEverywhere(updated);
  }

  void removeMemberFromParty(String friendCode) {
    final party = partyNotifier.value;
    if (party == null) return;
    final cleanCode = friendCode.trim().toUpperCase();
    final updatedMembers = List<FriendInfo>.from(party.members)
      ..removeWhere((m) => m.code.toUpperCase() == cleanCode);
    final updatedReady = List<String>.from(party.readyMemberCodes)
      ..removeWhere((c) => c.toUpperCase() == cleanCode);
    final updated = party.copyWith(
      members: updatedMembers,
      readyMemberCodes: updatedReady,
    );
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
    _watchedPartyCode = null;
    partyNotifier.value = null;
  }

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
          heroId: party.leaderHeroId.isNotEmpty ? party.leaderHeroId : 'george',
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

  // =========================================================================
  // ĐỒNG BỘ REALTIME TRẬN ĐẤU TỔ ĐỘI (FIREBASE rooms/{roomId} + PREFS)
  // =========================================================================

  static const String _localMatchPrefix = 'big_war_party_match_';

  Future<void> writePartyPlayerState(
    String roomId,
    String playerCode,
    Map<String, Object?> state,
  ) async {
    final cleanCode = playerCode.trim().toUpperCase();
    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('rooms/$roomId/players/$cleanCode').update(state);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_localMatchPrefix${roomId}_p_$cleanCode';
      await prefs.setString(key, jsonEncode(state));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> readPartyPlayerState(
    String roomId,
    String playerCode,
  ) async {
    final cleanCode = playerCode.trim().toUpperCase();
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('rooms/$roomId/players/$cleanCode').get();
        if (snap.exists && snap.value is Map) {
          return _normalizeMap(snap.value);
        }
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localMatchPrefix${roomId}_p_$cleanCode');
      if (raw != null && raw.isNotEmpty) {
        return jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Stream<Map<String, dynamic>> watchPartyPlayerState(
    String roomId,
    String playerCode,
  ) {
    final cleanCode = playerCode.trim().toUpperCase();
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    StreamSubscription<DatabaseEvent>? fbSub;
    Timer? localTimer;

    final db = _getDb();
    if (db != null) {
      fbSub = db
          .ref('rooms/$roomId/players/$cleanCode')
          .onValue
          .listen((event) {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm != null && !controller.isClosed) controller.add(norm);
      }, onError: (_) {});
    }

    localTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (controller.isClosed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final raw = prefs.getString('$_localMatchPrefix${roomId}_p_$cleanCode');
        if (raw != null && raw.isNotEmpty && !controller.isClosed) {
          controller.add(jsonDecode(raw) as Map<String, dynamic>);
        }
      } catch (_) {}
    });

    controller.onCancel = () {
      fbSub?.cancel();
      localTimer?.cancel();
    };
    return controller.stream;
  }

  Future<void> writePartyHostState(
    String roomId,
    Map<String, Object?> hostState,
  ) async {
    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('rooms/$roomId/host').set(hostState);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_localMatchPrefix${roomId}_host', jsonEncode(hostState));
    } catch (_) {}
  }

  Stream<Map<String, dynamic>> watchPartyHostState(String roomId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    StreamSubscription<DatabaseEvent>? fbSub;
    Timer? localTimer;

    final db = _getDb();
    if (db != null) {
      fbSub = db.ref('rooms/$roomId/host').onValue.listen((event) {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm != null && !controller.isClosed) controller.add(norm);
      }, onError: (_) {});
    }

    localTimer = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (controller.isClosed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final raw = prefs.getString('$_localMatchPrefix${roomId}_host');
        if (raw != null && raw.isNotEmpty && !controller.isClosed) {
          controller.add(jsonDecode(raw) as Map<String, dynamic>);
        }
      } catch (_) {}
    });

    controller.onCancel = () {
      fbSub?.cancel();
      localTimer?.cancel();
    };
    return controller.stream;
  }

  Future<void> sendPartyAction(
    String roomId,
    String actorCode,
    String action, {
    String? text,
  }) async {
    final payload = <String, Object?>{
      'id': '${actorCode}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999)}',
      'actorCode': actorCode.trim().toUpperCase(),
      'action': action,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (text != null) payload['text'] = text;

    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('rooms/$roomId/actions').push().set(payload);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_localMatchPrefix${roomId}_last_action';
      await prefs.setString(key, jsonEncode(payload));
    } catch (_) {}
  }

  Stream<Map<String, dynamic>> watchPartyActions(String roomId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    StreamSubscription<DatabaseEvent>? fbSub;
    Timer? localTimer;
    String? lastSeenId;

    final db = _getDb();
    if (db != null) {
      fbSub = db.ref('rooms/$roomId/actions').onChildAdded.listen((event) {
        final norm = _normalizeMap(event.snapshot.value);
        if (norm != null && !controller.isClosed) {
          final id = norm['id'] as String?;
          if (id != null && id == lastSeenId) return;
          lastSeenId = id;
          controller.add(norm);
        }
      }, onError: (_) {});
    }

    localTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      if (controller.isClosed) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final raw = prefs.getString('$_localMatchPrefix${roomId}_last_action');
        if (raw != null && raw.isNotEmpty) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final id = map['id'] as String?;
          if (id != null && id != lastSeenId && !controller.isClosed) {
            lastSeenId = id;
            controller.add(map);
          }
        }
      } catch (_) {}
    });

    controller.onCancel = () {
      fbSub?.cancel();
      localTimer?.cancel();
    };
    return controller.stream;
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
        'readyMembers': party.readyMemberCodes,
        'matchStatus': party.matchStatus,
        'activeMatchRoomId': party.activeMatchRoomId,
        'activeMapId': party.activeMapId,
        'matchSeed': party.matchSeed,
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
        'readyMembers': party.readyMemberCodes,
        'matchStatus': party.matchStatus,
        'activeMatchRoomId': party.activeMatchRoomId,
        'activeMapId': party.activeMapId,
        'matchSeed': party.matchSeed,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  // =========================================================================
  // PHÒNG ĐẤU TÙY CHỌN 4V4 (4 CHỖ ĐỘI XANH VS 4 CHỖ ĐỘI ĐỎ • MỜI BẠN & XẾP ĐỘI)
  // =========================================================================

  FriendInfo _buildMyFriendInfo(
    PlayerProfile profile, {
    String statusText = 'Đang Online',
  }) {
    return FriendInfo(
      code: effectivePlayerCode,
      name: effectivePlayerName,
      rankPoints: profile.rankPoints,
      rankStars: profile.rankStars,
      rankTier: profile.rankTier,
      selectedHeroId: profile.selectedHeroId,
      heroLevel: profile.getHeroLevel(),
      totalMatches: profile.totalMatches,
      totalWins: profile.totalWins,
      unlockedHeroCount: profile.unlockedHeroIds.length,
      pveHighestFloor: profile.pveHighestFloor,
      isChallengerTop10: profile.isChallengerTop10,
      serverRank: profile.serverRank,
      winRateText: profile.winRateDisplay,
      isOnline: true,
      statusText: statusText,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Tạo phòng đấu tùy chọn mặc định 4v4 (4 chỗ Đội Xanh vs 4 chỗ Đội Đỏ)
  Future<SoloDuelRoomState> createSoloRoom({
    int betGold = 0,
    String? selectedMapId,
  }) async {
    if (partyNotifier.value != null && partyNotifier.value!.members.isNotEmpty) {
      leaveParty();
    }
    if (soloRoomNotifier.value != null) {
      await leaveSoloRoom();
    }

    final profile = PlayerStorage.currentProfile;
    final int safeBet = betGold.clamp(0, max(0, profile.gold)).toInt();
    final rand = Random();
    final roomCode = 'SOLO${1000 + rand.nextInt(9000)}';
    final cleanMapId =
        (selectedMapId != null && selectedMapId.isNotEmpty) ? selectedMapId : null;
    final hostInfo =
        _buildMyFriendInfo(profile, statusText: 'Chủ phòng $roomCode');

    final created = SoloDuelRoomState(
      roomCode: roomCode,
      hostCode: hostInfo.code,
      hostName: hostInfo.name,
      blueSlots: [hostInfo, null, null, null],
      redSlots: [null, null, null, null],
      readyCodes: const [],
      betGold: safeBet,
      selectedMapId: cleanMapId,
      matchStatus: 'idle',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = created;
    await _syncSoloRoomEverywhere(created);
    _listenToSoloRoomRealtime(roomCode);
    return created;
  }

  (String, int)? _findOpenSoloSlot(
    SoloDuelRoomState room, {
    String? preferredTeam,
    int? preferredSlot,
  }) {
    int firstEmpty(List<FriendInfo?> slots) =>
        slots.indexWhere((element) => element == null);

    if (preferredTeam == 'blue' || preferredTeam == 'red') {
      final targetSlots =
          preferredTeam == 'blue' ? room.blueSlots : room.redSlots;
      if (preferredSlot != null &&
          preferredSlot >= 0 &&
          preferredSlot < SoloDuelRoomState.slotsPerTeam &&
          targetSlots[preferredSlot] == null) {
        return (preferredTeam!, preferredSlot);
      }
      final idx = firstEmpty(targetSlots);
      if (idx >= 0) return (preferredTeam!, idx);
    }

    // Tự động cân bằng 2 đội khi vào phòng (người thứ 2 tự sang Đội Đỏ để sẵn sàng đấu ngay)
    if (room.redCount < room.blueCount) {
      final rIdx = firstEmpty(room.redSlots);
      if (rIdx >= 0) return ('red', rIdx);
    }
    final bIdx = firstEmpty(room.blueSlots);
    if (bIdx >= 0) return ('blue', bIdx);
    final rFallback = firstEmpty(room.redSlots);
    if (rFallback >= 0) return ('red', rFallback);
    return null;
  }

  /// Gia nhập phòng 4v4 tùy chọn bằng Mã Phòng hoặc từ Lời Mời của bạn bè
  Future<SoloDuelRoomState> joinSoloRoomByCode(
    String rawRoomCode, {
    String? preferredTeam,
    int? preferredSlot,
  }) async {
    final code = rawRoomCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw ArgumentError('Vui lòng nhập Mã Phòng!');
    }
    if (code.startsWith('TEAM')) {
      throw ArgumentError(
        'Mã "$code" là mã Tổ Đội! Hãy nhập ở mục Tổ Đội.',
      );
    }

    final currentSolo = soloRoomNotifier.value;
    if (currentSolo != null && currentSolo.roomCode.toUpperCase() == code) {
      return currentSolo;
    }

    SoloDuelRoomState? existing;
    try {
      final db = _getDb();
      if (db != null) {
        final snap = await db.ref('parties/$code').get();
        if (snap.exists && snap.value != null) {
          final norm = _normalizeMap(snap.value);
          if (norm != null &&
              norm['roomType'] == 'solo_duel' &&
              norm['closed'] != true) {
            existing = SoloDuelRoomState.fromJson(code, norm);
          }
        }
      }
    } catch (_) {}

    existing ??= await _readSoloFromLocalPrefs(code);

    if (existing == null) {
      throw ArgumentError(
        'Không tìm thấy phòng có mã "$code"! Hãy kiểm tra lại mã phòng.',
      );
    }

    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (existing.containsPlayer(myCode)) {
      soloRoomNotifier.value = existing;
      _listenToSoloRoomRealtime(code);
      return existing;
    }

    if (existing.matchStatus == 'in_match') {
      throw StateError('Phòng $code đang trong trận đấu, vui lòng chờ trận sau!');
    }

    final openSlot = _findOpenSoloSlot(
      existing,
      preferredTeam: preferredTeam,
      preferredSlot: preferredSlot,
    );
    if (openSlot == null) {
      throw StateError('Phòng $code đã đủ 8/8 người chơi!');
    }

    if (partyNotifier.value != null && partyNotifier.value!.members.isNotEmpty) {
      leaveParty();
    }
    if (soloRoomNotifier.value != null &&
        soloRoomNotifier.value!.roomCode.toUpperCase() != code) {
      await leaveSoloRoom();
    }

    final profile = PlayerStorage.currentProfile;
    final myInfo = _buildMyFriendInfo(profile, statusText: 'Phòng $code');

    final nextBlue = List<FriendInfo?>.from(existing.blueSlots);
    final nextRed = List<FriendInfo?>.from(existing.redSlots);
    if (openSlot.$1 == 'blue') {
      nextBlue[openSlot.$2] = myInfo;
    } else {
      nextRed[openSlot.$2] = myInfo;
    }
    final nextReady = List<String>.from(existing.readyCodes)
      ..removeWhere((c) => c.toUpperCase() == myCode);

    final joined = existing.copyWith(
      blueSlots: nextBlue,
      redSlots: nextRed,
      readyCodes: nextReady,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = joined;
    await _syncSoloRoomEverywhere(joined);
    _listenToSoloRoomRealtime(code);
    return joined;
  }

  /// Bất kỳ người chơi nào trong phòng đều có thể mời bạn bè Online vào phòng tùy chọn 4v4
  Future<bool> inviteFriendToSoloRoom(
    FriendInfo friend, {
    String? preferredTeam,
  }) async {
    var room = soloRoomNotifier.value;
    room ??= await createSoloRoom();

    if (room.isFull || room.matchStatus != 'idle') return false;
    final toCode = friend.code.trim().toUpperCase();
    if (isSelfPlayer(code: toCode) || room.containsPlayer(toCode)) {
      return false;
    }

    await _syncSoloRoomEverywhere(room);

    final myCode = effectivePlayerCode.trim().toUpperCase();
    final myName = effectivePlayerName;
    final inviteId =
        'SINV_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final invite = PartyInvitation(
      id: inviteId,
      partyCode: room.roomCode,
      fromCode: myCode,
      fromName: myName,
      toCode: toCode,
      toName: friend.name,
      mode: PvpGameMode.squad4v4,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      status: 'pending',
      isCustomRoom: true,
      preferredTeam: preferredTeam,
    );

    await _saveInviteEverywhere(invite);
    return true;
  }

  /// Chuyển vị trí / đổi phe sang một ô trống ở Đội Xanh ('blue') hoặc Đội Đỏ ('red').
  /// Mọi thành viên đều tự đổi chỗ của mình được; Chủ phòng có thể đổi chỗ cho bất kỳ ai.
  Future<bool> switchSoloTeamSlot({
    required String targetTeam,
    required int targetSlot,
    String? memberCode,
  }) async {
    final current = soloRoomNotifier.value;
    if (current == null || current.matchStatus != 'idle') return false;
    if (targetTeam != 'blue' && targetTeam != 'red') return false;
    if (targetSlot < 0 || targetSlot >= SoloDuelRoomState.slotsPerTeam) {
      return false;
    }

    final myCode = effectivePlayerCode.trim().toUpperCase();
    final movingCode = (memberCode ?? myCode).trim().toUpperCase();
    if (movingCode != myCode && !current.isHost(myCode)) {
      return false;
    }

    final destList = targetTeam == 'blue' ? current.blueSlots : current.redSlots;
    if (destList[targetSlot] != null) return false;

    FriendInfo? movingPlayer;
    final nextBlue = List<FriendInfo?>.from(current.blueSlots);
    final nextRed = List<FriendInfo?>.from(current.redSlots);

    for (int i = 0; i < SoloDuelRoomState.slotsPerTeam; i++) {
      if (nextBlue[i]?.code.toUpperCase() == movingCode) {
        movingPlayer = nextBlue[i];
        nextBlue[i] = null;
      }
      if (nextRed[i]?.code.toUpperCase() == movingCode) {
        movingPlayer = nextRed[i];
        nextRed[i] = null;
      }
    }
    if (movingPlayer == null) return false;

    if (movingCode == myCode) {
      movingPlayer = _buildMyFriendInfo(
        PlayerStorage.currentProfile,
        statusText: 'Phòng ${current.roomCode}',
      );
    }

    if (targetTeam == 'blue') {
      nextBlue[targetSlot] = movingPlayer;
    } else {
      nextRed[targetSlot] = movingPlayer;
    }

    // Khi đổi phe/vị trí, người chơi đó xác nhận lại Sẵn Sàng (trừ Chủ Phòng)
    final nextReady = List<String>.from(current.readyCodes)
      ..removeWhere((c) => c.toUpperCase() == movingCode);

    final updated = current.copyWith(
      blueSlots: nextBlue,
      redSlots: nextRed,
      readyCodes: nextReady,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
    return true;
  }

  /// Chuyển nhanh một người chơi sang ô trống đầu tiên của phe đối diện
  Future<bool> moveSoloMemberToOppositeTeam(String memberCode) async {
    final current = soloRoomNotifier.value;
    if (current == null || current.matchStatus != 'idle') return false;
    final curTeam = current.teamOf(memberCode);
    if (curTeam == null) return false;
    final oppTeam = curTeam == 'blue' ? 'red' : 'blue';
    final oppSlots = oppTeam == 'blue' ? current.blueSlots : current.redSlots;
    final emptyIdx = oppSlots.indexWhere((e) => e == null);
    if (emptyIdx < 0) return false;
    return switchSoloTeamSlot(
      targetTeam: oppTeam,
      targetSlot: emptyIdx,
      memberCode: memberCode,
    );
  }

  /// Chủ phòng thay đổi Mức Cược Vàng hoặc Bản Đồ Thi Đấu.
  /// Tự động đặt lại Sẵn Sàng của toàn bộ khách để mọi người xác nhận lại.
  Future<void> updateSoloRoomSettings({
    int? betGold,
    String? selectedMapId,
    bool clearSelectedMap = false,
  }) async {
    final current = soloRoomNotifier.value;
    if (current == null || current.matchStatus != 'idle') return;
    final myCode = effectivePlayerCode;
    if (!current.isHost(myCode)) return;

    final profile = PlayerStorage.currentProfile;
    final int nextBet = betGold != null
        ? betGold.clamp(0, max(0, profile.gold)).toInt()
        : current.betGold.clamp(0, max(0, profile.gold)).toInt();
    final nextMap =
        clearSelectedMap ? null : (selectedMapId ?? current.selectedMapId);

    final settingsChanged =
        nextBet != current.betGold || nextMap != current.selectedMapId;

    final updated = _updateMemberInfoInSlots(
      current,
      myCode,
      _buildMyFriendInfo(profile, statusText: 'Chủ phòng ${current.roomCode}'),
    ).copyWith(
      betGold: nextBet,
      selectedMapId: nextMap,
      clearSelectedMap: clearSelectedMap,
      readyCodes: settingsChanged ? const [] : current.readyCodes,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
  }

  SoloDuelRoomState _updateMemberInfoInSlots(
    SoloDuelRoomState room,
    String targetCode,
    FriendInfo updatedInfo,
  ) {
    final clean = targetCode.trim().toUpperCase();
    final nextBlue = List<FriendInfo?>.from(room.blueSlots);
    final nextRed = List<FriendInfo?>.from(room.redSlots);
    for (int i = 0; i < SoloDuelRoomState.slotsPerTeam; i++) {
      if (nextBlue[i]?.code.toUpperCase() == clean) {
        nextBlue[i] = updatedInfo;
      }
      if (nextRed[i]?.code.toUpperCase() == clean) {
        nextRed[i] = updatedInfo;
      }
    }
    return room.copyWith(blueSlots: nextBlue, redSlots: nextRed);
  }

  /// Thành viên trong phòng (không phải Chủ Phòng) bật/tắt trạng thái Sẵn Sàng
  Future<bool> toggleSoloGuestReady() async {
    final current = soloRoomNotifier.value;
    if (current == null || current.matchStatus != 'idle') return false;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (current.isHost(myCode) || !current.containsPlayer(myCode)) return false;

    final profile = PlayerStorage.currentProfile;
    final currentlyReady = current.isPlayerReady(myCode);
    final nextReady = !currentlyReady;
    if (nextReady && profile.gold < current.betGold) {
      return false;
    }

    final nextReadyCodes = List<String>.from(current.readyCodes);
    if (nextReady) {
      if (!nextReadyCodes.any((c) => c.toUpperCase() == myCode)) {
        nextReadyCodes.add(myCode);
      }
    } else {
      nextReadyCodes.removeWhere((c) => c.toUpperCase() == myCode);
    }

    final updated = _updateMemberInfoInSlots(
      current,
      myCode,
      _buildMyFriendInfo(profile, statusText: 'Phòng ${current.roomCode}'),
    ).copyWith(
      readyCodes: nextReadyCodes,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
    return true;
  }

  /// Chủ phòng mời một thành viên ra khỏi phòng
  Future<void> kickSoloMember(String memberCode) async {
    final current = soloRoomNotifier.value;
    if (current == null || current.matchStatus != 'idle') return;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    final cleanTarget = memberCode.trim().toUpperCase();
    if (!current.isHost(myCode) || cleanTarget == myCode) return;

    final nextBlue = current.blueSlots
        .map((p) => p?.code.toUpperCase() == cleanTarget ? null : p)
        .toList();
    final nextRed = current.redSlots
        .map((p) => p?.code.toUpperCase() == cleanTarget ? null : p)
        .toList();
    final nextReady = List<String>.from(current.readyCodes)
      ..removeWhere((c) => c.toUpperCase() == cleanTarget);

    final updated = current.copyWith(
      blueSlots: nextBlue,
      redSlots: nextRed,
      readyCodes: nextReady,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
  }

  /// Rời khỏi hoặc đóng phòng hiện tại
  Future<void> leaveSoloRoom() async {
    final current = soloRoomNotifier.value;
    _soloRoomSubscription?.cancel();
    _soloRoomSubscription = null;
    _soloLocalPollTimer?.cancel();
    _soloLocalPollTimer = null;
    _watchedSoloCode = null;
    soloRoomNotifier.value = null;

    if (current == null) return;
    final code = current.roomCode.toUpperCase();
    final myCode = effectivePlayerCode.trim().toUpperCase();

    if (current.isHost(myCode)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_localSoloPrefix$code');
      } catch (_) {}
      try {
        final db = _getDb();
        if (db != null) {
          await db.ref('parties/$code').remove();
        }
      } catch (_) {}
    } else if (current.containsPlayer(myCode)) {
      final nextBlue = current.blueSlots
          .map((p) => p?.code.toUpperCase() == myCode ? null : p)
          .toList();
      final nextRed = current.redSlots
          .map((p) => p?.code.toUpperCase() == myCode ? null : p)
          .toList();
      final nextReady = List<String>.from(current.readyCodes)
        ..removeWhere((c) => c.toUpperCase() == myCode);

      final updated = current.copyWith(
        blueSlots: nextBlue,
        redSlots: nextRed,
        readyCodes: nextReady,
        matchStatus: 'idle',
        clearActiveMatch: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _syncSoloRoomEverywhere(updated);
    }
  }

  /// Đồng bộ lại nhân vật xuất chiến khi người chơi đổi tướng trong Cửa Hàng
  Future<void> updateMySoloHero(String newHeroId) async {
    final current = soloRoomNotifier.value;
    if (current == null) return;
    final myCode = effectivePlayerCode.trim().toUpperCase();
    if (!current.containsPlayer(myCode)) return;

    final profile = PlayerStorage.currentProfile;
    final refreshed = _buildMyFriendInfo(
      profile,
      statusText: 'Phòng ${current.roomCode}',
    ).copyWith(
      selectedHeroId: newHeroId,
      heroLevel: profile.getHeroLevel(newHeroId),
    );

    final updated = _updateMemberInfoInSlots(current, myCode, refreshed)
        .copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch);
    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
  }

  /// Chủ phòng bấm VÀO GAME sau khi cả 2 đội đã có người & tất cả thành viên đã Sẵn Sàng
  Future<SoloDuelRoomState?> startSoloDuelMatch() async {
    final current = soloRoomNotifier.value;
    if (current == null || !current.canHostStart) return null;
    final myCode = effectivePlayerCode;
    if (!current.isHost(myCode)) return null;

    final profile = PlayerStorage.currentProfile;
    if (profile.gold < current.betGold) return null;

    final resolvedMapId = !current.isRandomMap
        ? current.selectedMapId!
        : GameAssetRegistry.instance.getRandomMap().id;
    final matchRoomId =
        'solo_${current.roomCode.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}';

    final started = _updateMemberInfoInSlots(
      current,
      myCode,
      _buildMyFriendInfo(profile, statusText: 'Đang đấu phòng ${current.roomCode}'),
    ).copyWith(
      matchStatus: 'in_match',
      activeMatchRoomId: matchRoomId,
      resolvedMapId: resolvedMapId,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = started;
    await _syncSoloRoomEverywhere(started);
    return started;
  }

  /// Đặt lại trạng thái phòng sau khi trận đấu kết thúc để cả phòng có thể xếp đội tái đấu
  Future<void> resetSoloRoomAfterMatch() async {
    final current = soloRoomNotifier.value;
    if (current == null) return;

    final profile = PlayerStorage.currentProfile;
    final myCode = effectivePlayerCode;
    final isMeHost = current.isHost(myCode);

    final updated = _updateMemberInfoInSlots(
      current,
      myCode,
      _buildMyFriendInfo(profile, statusText: 'Phòng ${current.roomCode}'),
    ).copyWith(
      betGold: isMeHost
          ? current.betGold.clamp(0, max(0, profile.gold)).toInt()
          : current.betGold,
      readyCodes: const [],
      matchStatus: 'idle',
      clearActiveMatch: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    soloRoomNotifier.value = updated;
    await _syncSoloRoomEverywhere(updated);
  }

  /// Đăng ký onDisconnect cho người chơi trong phòng đấu tùy chọn
  Future<void> registerSoloMatchPresence(
    String matchRoomId,
    String playerCode,
  ) async {
    final cleanCode = playerCode.trim().toUpperCase();
    try {
      final db = _getDb();
      if (db != null) {
        final ref = db.ref('rooms/$matchRoomId/players/$cleanCode');
        await ref.onDisconnect().update({
          'connected': false,
          'ready': false,
        });
      }
    } catch (_) {}
  }

  /// Đánh dấu người chơi rời trận (để xử thắng khi cả đội địch rời trận)
  Future<void> leaveSoloMatchRoom(
    String matchRoomId,
    String playerCode,
  ) async {
    final cleanCode = playerCode.trim().toUpperCase();
    final state = <String, Object?>{
      'connected': false,
      'ready': false,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      final db = _getDb();
      if (db != null) {
        await db.ref('rooms/$matchRoomId/players/$cleanCode').update(state);
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_localMatchPrefix${matchRoomId}_p_$cleanCode';
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final existing = jsonDecode(raw);
        if (existing is Map) {
          final merged = Map<String, dynamic>.from(existing)..addAll(state);
          await prefs.setString(key, jsonEncode(merged));
          return;
        }
      }
      await prefs.setString(key, jsonEncode(state));
    } catch (_) {}
  }

  bool _areSlotsEqual(List<FriendInfo?> a, List<FriendInfo?> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final pa = a[i];
      final pb = b[i];
      if ((pa == null) != (pb == null)) return false;
      if (pa != null && pb != null) {
        if (pa.code.toUpperCase() != pb.code.toUpperCase() ||
            pa.selectedHeroId != pb.selectedHeroId ||
            pa.heroLevel != pb.heroLevel ||
            pa.name != pb.name) {
          return false;
        }
      }
    }
    return true;
  }

  bool _isSoloRoomChanged(SoloDuelRoomState? current, SoloDuelRoomState next) {
    if (current == null) return true;
    return current.roomCode != next.roomCode ||
        current.hostCode != next.hostCode ||
        current.betGold != next.betGold ||
        current.selectedMapId != next.selectedMapId ||
        current.matchStatus != next.matchStatus ||
        current.activeMatchRoomId != next.activeMatchRoomId ||
        current.resolvedMapId != next.resolvedMapId ||
        !_areSlotsEqual(current.blueSlots, next.blueSlots) ||
        !_areSlotsEqual(current.redSlots, next.redSlots) ||
        !_areCodeListsEqual(current.readyCodes, next.readyCodes);
  }

  void _applyIncomingSoloSnapshot(String cleanCode, SoloDuelRoomState? parsed) {
    final current = soloRoomNotifier.value;
    if (current == null || current.roomCode.toUpperCase() != cleanCode) return;
    final myCode = effectivePlayerCode;

    if (parsed == null) {
      if (!current.isHost(myCode)) {
        soloRoomNoticeNotifier.value =
            'Chủ phòng đã đóng phòng $cleanCode.';
        _soloRoomSubscription?.cancel();
        _soloRoomSubscription = null;
        _soloLocalPollTimer?.cancel();
        _soloLocalPollTimer = null;
        _watchedSoloCode = null;
        soloRoomNotifier.value = null;
      }
      return;
    }

    if (!parsed.containsPlayer(myCode)) {
      soloRoomNoticeNotifier.value = 'Bạn đã rời khỏi phòng $cleanCode.';
      _soloRoomSubscription?.cancel();
      _soloRoomSubscription = null;
      _soloLocalPollTimer?.cancel();
      _soloLocalPollTimer = null;
      _watchedSoloCode = null;
      soloRoomNotifier.value = null;
      return;
    }

    if (_isSoloRoomChanged(current, parsed)) {
      soloRoomNotifier.value = parsed;
      unawaited(_saveSoloToLocalPrefs(parsed));
    }
  }

  void _listenToSoloRoomRealtime(String roomCode) {
    final cleanCode = roomCode.trim().toUpperCase();
    if (_watchedSoloCode == cleanCode &&
        (_soloRoomSubscription != null || _soloLocalPollTimer != null)) {
      return;
    }

    _soloRoomSubscription?.cancel();
    _soloLocalPollTimer?.cancel();
    _watchedSoloCode = cleanCode;

    final db = _getDb();
    if (db != null) {
      _soloRoomSubscription =
          db.ref('parties/$cleanCode').onValue.listen((event) {
        final raw = event.snapshot.value;
        if (raw == null) {
          _applyIncomingSoloSnapshot(cleanCode, null);
          return;
        }
        final norm = _normalizeMap(raw);
        if (norm == null ||
            norm['roomType'] != 'solo_duel' ||
            norm['closed'] == true) {
          _applyIncomingSoloSnapshot(cleanCode, null);
          return;
        }
        final parsed = SoloDuelRoomState.fromJson(cleanCode, norm);
        _applyIncomingSoloSnapshot(cleanCode, parsed);
      }, onError: (Object err) {
        debugPrint('Solo room stream error: $err');
      });
    }

    _soloLocalPollTimer =
        Timer.periodic(const Duration(milliseconds: 350), (_) async {
      if (_watchedSoloCode != cleanCode) return;
      final localSolo = await _readSoloFromLocalPrefs(cleanCode);
      if (localSolo != null) {
        _applyIncomingSoloSnapshot(cleanCode, localSolo);
      } else if (_getDb() == null) {
        _applyIncomingSoloSnapshot(cleanCode, null);
      }
    });
  }

  Future<void> _syncSoloRoomEverywhere(SoloDuelRoomState room) async {
    await _saveSoloToLocalPrefs(room);
    await _syncSoloToFirebase(room);
  }

  Future<void> _saveSoloToLocalPrefs(SoloDuelRoomState room) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_localSoloPrefix${room.roomCode.toUpperCase()}',
        jsonEncode(room.toJson()),
      );
    } catch (_) {}
  }

  Future<SoloDuelRoomState?> _readSoloFromLocalPrefs(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString('$_localSoloPrefix${code.toUpperCase()}');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['closed'] == true) return null;
      return SoloDuelRoomState.fromJson(code.toUpperCase(), map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncSoloToFirebase(SoloDuelRoomState room) async {
    try {
      final db = _getDb();
      if (db == null) return;
      await db.ref('parties/${room.roomCode.toUpperCase()}').set({
        ...room.toJson(),
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {}
  }
}
