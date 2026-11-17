import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';

/// Client-side Firebase transport for the two-tab PvP prototype.
/// Match results and writes are not authoritative; this is for a private demo.
///
/// Matchmaking flow:
///  1. Mỗi client ghi vé vào `matchmaking/queue/players/{uid}` và gửi heartbeat
///     `lastSeen` (server timestamp) định kỳ.
///  2. Client chạy transaction ghép cặp định kỳ (không chỉ khi queue thay đổi)
///     và so sánh thời gian theo giờ SERVER (`.info/serverTimeOffset`) để không
///     bị lệch đồng hồ máy làm loại nhầm đối thủ.
///  3. Khi hết giờ, [cancelSearch] rút vé bằng transaction: nếu đã bị ghép thì
///     trả về roomId để vào trận thay vì bỏ rơi đối thủ.
///  4. Trong phòng, mỗi bên ghi `ready = true` khi đã vào màn đấu; trận chỉ
///     bắt đầu khi cả hai cùng sẵn sàng (xem PvpArenaScreen).
class FirebasePvpService {
  FirebasePvpService({FirebaseDatabase? database, FirebaseAuth? auth})
      : _database = database ??
            FirebaseDatabase.instanceFor(
              app: Firebase.app(),
              databaseURL: DefaultFirebaseOptions.databaseUrl,
            ),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseDatabase _database;
  final FirebaseAuth _auth;

  /// Vé quá thời gian này không gửi heartbeat sẽ bị coi là treo/đã thoát.
  static const Duration ticketStaleAfter = Duration(seconds: 15);
  static const Duration heartbeatInterval = Duration(seconds: 4);
  static const Duration pairRetryInterval = Duration(milliseconds: 1500);

  int _serverOffsetMs = 0;
  Completer<String?>? _search;

  String get uid => _auth.currentUser!.uid;
  DatabaseReference get _queue => _database.ref('matchmaking/queue');

  int get serverNow => DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  Future<void> _syncServerOffset() async {
    try {
      final snap = await _database.ref('.info/serverTimeOffset').get();
      final value = snap.value;
      if (value is num) _serverOffsetMs = value.toInt();
    } catch (error) {
      debugPrint('PvP: cannot read serverTimeOffset: $error');
    }
  }

  Future<String?> findMatch(
    PlayerProfile profile, {
    PvpGameMode mode = PvpGameMode.solo1v1,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (_search != null && !_search!.isCompleted) {
      throw StateError('Đang tìm trận rồi.');
    }
    await _syncServerOffset();

    final playerUid = uid;
    final ticket = <String, Object?>{
      'uid': playerUid,
      'name': '${profile.playerName} #${playerUid.substring(0, 4)}',
      'rankPoints': profile.rankPoints,
      'rankTier': profile.rankTier,
      'heroId': profile.selectedHeroId,
      'mode': mode.code,
      'createdAt': ServerValue.timestamp,
      'lastSeen': ServerValue.timestamp,
    };
    final myTicket = _queue.child('players/$playerUid');
    final assignment = _queue.child('matches/$playerUid');
    await assignment.remove();

    final result = Completer<String?>();
    _search = result;
    var pairing = false;
    StreamSubscription<DatabaseEvent> queueSub;
    StreamSubscription<DatabaseEvent>? assignmentSub;
    Timer? timeoutTimer;
    Timer? retryTimer;
    Timer? heartbeatTimer;

    Future<void> deliver(String roomId) async {
      if (result.isCompleted) return;
      try {
        await _ensureRoom(roomId, profile);
        if (!result.isCompleted) result.complete(roomId);
      } catch (error) {
        if (!result.isCompleted) result.completeError(error);
      }
    }

    Future<void> tryPair() async {
      if (pairing || result.isCompleted) return;
      pairing = true;
      try {
        final now = serverNow;
        final transaction = await _queue.runTransaction((raw) {
          final root = _stringMap(raw);
          final players = _stringMap(root['players']);
          final matches = _stringMap(root['matches']);
          final existingRoom = matches[playerUid];
          if (existingRoom is String && existingRoom.isNotEmpty) {
            return Transaction.abort();
          }
          // Vé của mình phải còn trong queue (nếu đã bị rút thì không ghép).
          if (players[playerUid] == null) return Transaction.abort();

          final myRp = profile.rankPoints;
          final candidates = players.entries
              .where((entry) => entry.key != playerUid)
              .where((entry) => entry.value is Map)
              .map((entry) => MapEntry(entry.key, _stringMap(entry.value)))
              .where((entry) => matches[entry.key] == null)
              .where((entry) {
                final entryMode = (entry.value['mode'] as String?) ?? '1v1';
                final rp = (entry.value['rankPoints'] as num?)?.toInt() ?? myRp;
                return entryMode == mode.code &&
                    _isFresh(entry.value, now) &&
                    (rp - myRp).abs() <= 150;
              }).toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          if (candidates.isEmpty) return Transaction.abort();

          final other = candidates.first;
          final pair = [playerUid, other.key]..sort();
          final roomId = 'pvp_${pair[0]}_${pair[1]}_$now';

          // Dọn rác: vé treo quá 1 phút và kết quả ghép quá 30 phút.
          players.removeWhere((key, value) =>
              key != playerUid &&
              key != other.key &&
              (value is! Map || !_isFresh(_stringMap(value), now, maxAgeMs: 60000)));
          matches.removeWhere((key, value) {
            if (value is! String) return true;
            final ts = int.tryParse(value.split('_').last) ?? 0;
            return now - ts > const Duration(minutes: 30).inMilliseconds;
          });

          matches[playerUid] = roomId;
          matches[other.key] = roomId;
          root['players'] = players;
          root['matches'] = matches;
          return Transaction.success(root);
        }, applyLocally: false);

        if (transaction.committed) {
          final matches = _stringMap(_stringMap(transaction.snapshot.value)['matches']);
          final roomId = matches[playerUid];
          if (roomId is String && roomId.isNotEmpty) await deliver(roomId);
        }
      } catch (error) {
        // Transaction có thể thất bại tạm thời khi 2 tab tranh nhau ghi;
        // lần thử lại kế tiếp sẽ xử lý.
        debugPrint('PvP pairing attempt failed: $error');
      } finally {
        pairing = false;
      }
    }

    assignmentSub = assignment.onValue.listen((event) {
      final roomId = event.snapshot.value;
      if (roomId is String && roomId.isNotEmpty) unawaited(deliver(roomId));
    });

    // Lắng nghe toàn bộ node queue để transaction luôn có cache đầy đủ
    // (transaction RTDB chạy lần đầu trên cache cục bộ).
    queueSub = _queue.onValue.listen((_) => unawaited(tryPair()));

    try {
      await myTicket.onDisconnect().remove();
      await myTicket.set(ticket);
      retryTimer = Timer.periodic(pairRetryInterval, (_) => unawaited(tryPair()));
      heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
        if (result.isCompleted) return;
        unawaited(myTicket.update({'lastSeen': ServerValue.timestamp}).catchError((_) {}));
      });
      timeoutTimer = Timer(timeout, () => unawaited(cancelSearch()));
      unawaited(tryPair());
      return await result.future;
    } finally {
      timeoutTimer?.cancel();
      retryTimer?.cancel();
      heartbeatTimer?.cancel();
      await queueSub.cancel();
      await assignmentSub.cancel();
      if (identical(_search, result)) _search = null;
    }
  }

  /// Rút khỏi hàng chờ một cách an toàn. Nếu trong lúc đó đã bị ghép cặp,
  /// trả về roomId (và [findMatch] cũng sẽ trả về roomId đó).
  Future<String?> cancelSearch() async {
    final playerUid = uid;
    String? matchedRoom;
    try {
      await _queue.runTransaction((raw) {
        final root = _stringMap(raw);
        final players = _stringMap(root['players']);
        final matches = _stringMap(root['matches']);
        final room = matches[playerUid];
        if (room is String && room.isNotEmpty) {
          matchedRoom = room;
          return Transaction.abort();
        }
        matchedRoom = null;
        if (!players.containsKey(playerUid)) return Transaction.abort();
        players.remove(playerUid);
        root['players'] = players;
        root['matches'] = matches;
        return Transaction.success(root);
      }, applyLocally: false);
    } catch (error) {
      debugPrint('PvP cancelSearch failed: $error');
      await _queue.child('players/$playerUid').remove();
    }

    final search = _search;
    if (search != null && !search.isCompleted) {
      if (matchedRoom == null) {
        search.complete(null);
      }
      // Nếu đã có phòng, listener assignment sẽ tự deliver roomId.
    }
    return matchedRoom;
  }

  bool _isFresh(Map<String, dynamic> ticket, int now, {int? maxAgeMs}) {
    final seenRaw = ticket['lastSeen'] ?? ticket['createdAt'];
    // Giá trị chưa được server điền (placeholder {.sv: timestamp}) => vé mới.
    if (seenRaw is Map) return true;
    final seen = (seenRaw as num?)?.toInt();
    if (seen == null) return false;
    // Không chặn giá trị âm: đồng hồ server có thể nhanh hơn máy khách.
    return (now - seen) < (maxAgeMs ?? ticketStaleAfter.inMilliseconds);
  }

  Future<void> _ensureRoom(String roomId, PlayerProfile profile) async {
    final parts = roomId.substring('pvp_'.length).split('_');
    if (parts.length < 3) throw StateError('Room ID không hợp lệ.');
    final pair = parts.take(2).toList();
    final root = _stringMap((await _queue.get()).value);
    final players = _stringMap(root['players']);
    final profiles = <String, Object?>{};
    for (final id in pair) {
      profiles[id] = players[id] ?? <String, Object?>{'uid': id, 'name': 'Player'};
    }

    final room = _database.ref('rooms/$roomId');
    await room.child('meta').runTransaction((raw) {
      if (raw != null) return Transaction.abort();
      return Transaction.success(<String, Object?>{
        'roomId': roomId,
        'createdAt': ServerValue.timestamp,
      });
    }, applyLocally: false);
    await room.update({
      'roomId': roomId,
      'playerOrder': pair,
      'profiles/$uid': profiles[uid],
    });
    // Bổ sung profile đối thủ nếu chưa có (không ghi đè dữ liệu bên kia tự ghi).
    final otherUid = pair.firstWhere((id) => id != uid, orElse: () => '');
    if (otherUid.isNotEmpty) {
      await room.child('profiles/$otherUid').runTransaction((raw) {
        if (raw != null) return Transaction.abort();
        return Transaction.success(profiles[otherUid]);
      }, applyLocally: false);
    }
    await room.child('players/$uid/connected').onDisconnect().set(false);
    await room.child('players/$uid').update({
      'name': profile.playerName,
      'heroId': profile.selectedHeroId,
      'rankPoints': profile.rankPoints,
      'rankTier': profile.rankTier,
      'connected': true,
      'ready': false,
    });
  }

  Stream<Map<String, dynamic>> watchRoom(String roomId) =>
      _database.ref('rooms/$roomId').onValue.map((event) => _stringMap(event.snapshot.value));

  Stream<Map<String, dynamic>> watchPlayer(String roomId, String targetUid) {
    return _database
        .ref('rooms/$roomId/players/$targetUid')
        .onValue
        .map((event) => _stringMap(event.snapshot.value));
  }

  Future<Map<String, dynamic>> readRoom(String roomId) async =>
      _stringMap((await _database.ref('rooms/$roomId').get()).value);

  /// Đánh dấu đã vào màn đấu và sẵn sàng chiến.
  Future<void> markReady(String roomId) =>
      _database.ref('rooms/$roomId/players/$uid').update({
        'ready': true,
        'connected': true,
        'readyAt': ServerValue.timestamp,
      });

  Future<void> writePlayerState(String roomId, Map<String, Object?> state) =>
      _database.ref('rooms/$roomId/players/$uid').update(state);

  Future<void> sendAction(String roomId, String action, {String? text}) async {
    final payload = <String, Object?>{
      'actorUid': uid,
      'action': action,
      'createdAt': ServerValue.timestamp,
    };
    if (text != null) payload['text'] = text;
    await _database.ref('rooms/$roomId/actions').push().set(payload);
  }

  Stream<DatabaseEvent> watchActions(String roomId) =>
      _database.ref('rooms/$roomId/actions').onChildAdded;

  Future<void> leaveQueue() async {
    final search = _search;
    if (search != null && !search.isCompleted) {
      await cancelSearch();
    } else {
      await _queue.child('players/$uid').remove();
    }
  }

  Future<void> leaveRoom(String roomId) async {
    await _database.ref('rooms/$roomId/players/$uid').update({
      'connected': false,
      'ready': false,
    });
    await _queue.child('matches/$uid').remove();
    await _queue.child('players/$uid').remove();
  }

  static Map<String, dynamic> _stringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is List) {
      // RTDB có thể trả về List khi key là số liên tiếp.
      final map = <String, dynamic>{};
      for (var i = 0; i < raw.length; i++) {
        if (raw[i] != null) map['$i'] = raw[i];
      }
      return map;
    }
    return <String, dynamic>{};
  }
}
