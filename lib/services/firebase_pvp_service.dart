import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import '../registry/asset_registry.dart';

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
  static const Duration ticketStaleAfter = Duration(seconds: 30);
  static const Duration heartbeatInterval = Duration(seconds: 4);
  static const Duration pairRetryInterval = Duration(milliseconds: 900);

  int _serverOffsetMs = 0;
  Completer<String?>? _search;
  bool _searchCancelled = false;

  String get uid => _auth.currentUser!.uid;
  DatabaseReference get _queue => _database.ref('matchmaking/queue');

  int get serverNow => DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  StreamSubscription<DatabaseEvent> _listenServerOffset() {
    return _database.ref('.info/serverTimeOffset').onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is num) _serverOffsetMs = value.toInt();
    }, onError: (Object error) {
      debugPrint('PvP: cannot watch serverTimeOffset: $error');
    });
  }

  Future<void> _syncServerOffset() async {
    try {
      final event = await _database
          .ref('.info/serverTimeOffset')
          .onValue
          .first
          .timeout(const Duration(milliseconds: 500));
      final value = event.snapshot.value;
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
    _searchCancelled = false;
    final offsetSub = _listenServerOffset();
    await _syncServerOffset();

    final playerUid = uid;
    final searchStartMs = DateTime.now().millisecondsSinceEpoch;
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
    var retryRequested = false;
    StreamSubscription<DatabaseEvent>? queueSub;
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
      if (result.isCompleted || _searchCancelled) return;
      if (pairing) {
        retryRequested = true;
        return;
      }
      pairing = true;
      try {
        do {
          retryRequested = false;
          if (result.isCompleted || _searchCancelled) break;

          // Đọc trực tiếp từ server để tránh local cache rỗng làm abort transaction.
          final snap = await _queue.get();
          if (result.isCompleted || _searchCancelled) break;

          final root = _stringMap(snap.value);
          final players = _stringMap(root['players']);
          final matches = _stringMap(root['matches']);

          final existingRoom = matches[playerUid];
          if (existingRoom is String && existingRoom.isNotEmpty) {
            await deliver(existingRoom);
            break;
          }

          // Nếu vé của mình bị mất trong lúc đang tìm thì ghi lại ngay.
          if (players[playerUid] == null) {
            await myTicket.set(ticket);
            continue;
          }

          // Dùng chính lastSeen (ServerValue.timestamp) của vé mình làm mốc tham chiếu
          // để loại bỏ hoàn toàn sai lệch đồng hồ giữa 2 thiết bị.
          final myTicketMap = _stringMap(players[playerUid]);
          final myLastSeenRaw = myTicketMap['lastSeen'] ?? myTicketMap['createdAt'];
          final myLastSeen = myLastSeenRaw is num ? myLastSeenRaw.toInt() : null;
          final referenceNow =
              myLastSeen != null ? max(serverNow, myLastSeen) : serverNow;

          final elapsedMs = DateTime.now().millisecondsSinceEpoch - searchStartMs;
          final int? maxRpDiff;
          if (elapsedMs < 2500) {
            maxRpDiff = 250;
          } else if (elapsedMs < 5000) {
            maxRpDiff = 600;
          } else {
            maxRpDiff = null; // Mở rộng ghép mọi mức rank để 2 bên luôn gặp nhau.
          }

          final myRp = profile.rankPoints;
          final candidates = players.entries
              .where((entry) => entry.key != playerUid)
              .where((entry) => entry.value is Map)
              .map((entry) => MapEntry(entry.key, _stringMap(entry.value)))
              .where((entry) {
                final matchVal = matches[entry.key];
                if (matchVal is String && matchVal.isNotEmpty) {
                  return _isExpiredMatch(matchVal, referenceNow, maxAgeMs: 300000);
                }
                return true;
              })
              .where((entry) {
                final entryMode = (entry.value['mode'] as String?) ?? '1v1';
                final rp = (entry.value['rankPoints'] as num?)?.toInt() ?? myRp;
                return entryMode == mode.code &&
                    _isFresh(entry.value, referenceNow) &&
                    (maxRpDiff == null || (rp - myRp).abs() <= maxRpDiff);
              })
              .toList()
            ..sort((a, b) {
              final rpA = (a.value['rankPoints'] as num?)?.toInt() ?? myRp;
              final rpB = (b.value['rankPoints'] as num?)?.toInt() ?? myRp;
              final diffCmp = (rpA - myRp).abs().compareTo((rpB - myRp).abs());
              if (diffCmp != 0) return diffCmp;
              return a.key.compareTo(b.key);
            });

          if (candidates.isEmpty) continue;

          final other = candidates.first;
          final pair = [playerUid, other.key]..sort();
          final roomId = 'pvp_${pair[0]}_${pair[1]}_$referenceNow';

          // Chạy transaction trực tiếp trên node `matches` để:
          // 1) Không bị conflict với heartbeat đang cập nhật vào `players/*`.
          // 2) Không bao giờ abort trên local cache rỗng khi `matches` đang null.
          final tx = await _queue.child('matches').runTransaction((raw) {
            final currentMatches = _stringMap(raw);
            currentMatches.removeWhere((key, value) {
              if (value is! String) return true;
              return _isExpiredMatch(value, referenceNow, maxAgeMs: 1800000);
            });

            final mine = currentMatches[playerUid];
            if (mine is String && mine.isNotEmpty) {
              return Transaction.abort();
            }
            final theirs = currentMatches[other.key];
            if (theirs is String &&
                theirs.isNotEmpty &&
                !_isExpiredMatch(theirs, referenceNow, maxAgeMs: 300000)) {
              return Transaction.abort();
            }

            currentMatches[playerUid] = roomId;
            currentMatches[other.key] = roomId;
            return Transaction.success(currentMatches);
          }, applyLocally: false);

          if (tx.committed) {
            final committedMatches = _stringMap(tx.snapshot.value);
            final assigned = committedMatches[playerUid];
            if (assigned is String && assigned.isNotEmpty) {
              await deliver(assigned);
              break;
            }
          } else {
            // Có thể đối thủ vừa ghép xong cho mình trong lúc transaction chạy.
            final assignedSnap = await assignment.get();
            final assigned = assignedSnap.value;
            if (assigned is String && assigned.isNotEmpty) {
              await deliver(assigned);
              break;
            }
            retryRequested = true;
          }
        } while (retryRequested && !result.isCompleted && !_searchCancelled);
      } catch (error) {
        debugPrint('PvP pairing attempt failed: $error');
      } finally {
        pairing = false;
      }
    }

    assignmentSub = assignment.onValue.listen((event) {
      final roomId = event.snapshot.value;
      if (roomId is String && roomId.isNotEmpty) unawaited(deliver(roomId));
    });

    queueSub = _queue.onValue.listen((_) => unawaited(tryPair()));

    try {
      await myTicket.onDisconnect().remove();
      await myTicket.set(ticket);
      retryTimer = Timer.periodic(pairRetryInterval, (_) => unawaited(tryPair()));
      heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
        if (result.isCompleted || _searchCancelled) return;
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
      await offsetSub.cancel();
      if (identical(_search, result)) _search = null;
    }
  }

  /// Rút khỏi hàng chờ một cách an toàn. Nếu trong lúc đó đã bị ghép cặp,
  /// trả về roomId (và [findMatch] cũng sẽ trả về roomId đó).
  Future<String?> cancelSearch() async {
    _searchCancelled = true;
    final playerUid = uid;
    String? matchedRoom;
    try {
      final matchSnap = await _queue.child('matches/$playerUid').get();
      final existing = matchSnap.value;
      if (existing is String && existing.isNotEmpty) {
        matchedRoom = existing;
      } else {
        await _queue.child('players/$playerUid').remove();
        // Kiểm tra lại thêm 1 lần đề phòng đối thủ vừa ghi matches đúng lúc xóa vé.
        final recheck = (await _queue.child('matches/$playerUid').get()).value;
        if (recheck is String && recheck.isNotEmpty) {
          matchedRoom = recheck;
        }
      }
    } catch (error) {
      debugPrint('PvP cancelSearch failed: $error');
      try {
        await _queue.child('players/$playerUid').remove();
      } catch (_) {}
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

  bool _isExpiredMatch(String roomId, int now, {int maxAgeMs = 1800000}) {
    final ts = int.tryParse(roomId.split('_').last) ?? 0;
    return ts > 0 && (now - ts) > maxAgeMs;
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
    final body = roomId.startsWith('pvp_') ? roomId.substring('pvp_'.length) : roomId;
    final lastSep = body.lastIndexOf('_');
    final pairStr = lastSep > 0 ? body.substring(0, lastSep) : body;
    final parts = pairStr.split('_');
    if (parts.length < 2) throw StateError('Room ID không hợp lệ.');
    final pair = parts.length == 2
        ? parts
        : [parts.first, parts.sublist(1).join('_')];
    final root = _stringMap((await _queue.get()).value);
    final players = _stringMap(root['players']);
    final profiles = <String, Object?>{};
    for (final id in pair) {
      if (id == uid) {
        profiles[id] = <String, Object?>{
          'uid': uid,
          'name': '${profile.playerName} #${uid.substring(0, 4)}',
          'rankPoints': profile.rankPoints,
          'rankTier': profile.rankTier,
          'heroId': profile.selectedHeroId,
        };
      } else {
        profiles[id] = players[id] ?? <String, Object?>{'uid': id, 'name': 'Player'};
      }
    }

    final room = _database.ref('rooms/$roomId');
    final roomMap = GameAssetRegistry.instance.getMapFromSeed(roomId);
    await room.child('meta').runTransaction((raw) {
      if (raw != null) return Transaction.abort();
      return Transaction.success(<String, Object?>{
        'roomId': roomId,
        'mapId': roomMap.id,
        'createdAt': ServerValue.timestamp,
      });
    }, applyLocally: false);
    await room.update({
      'roomId': roomId,
      'mapId': roomMap.id,
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
    _searchCancelled = true;
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
