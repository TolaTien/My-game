import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../models/database_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import 'database_service.dart';
import 'firebase_bootstrap.dart';

/// Dịch vụ kết nối Google Firebase Realtime Database
/// Có cơ chế phòng thủ (Shielding) tự động fallback về MockDatabaseService nếu
/// chưa cấu hình hoặc không có kết nối internet.
class FirebaseDatabaseService implements DatabaseService {
  final MockDatabaseService _fallback;
  bool _isOnline = false;

  FirebaseDatabaseService({MockDatabaseService? fallback})
      : _fallback = fallback ?? MockDatabaseService();

  @override
  bool get isOnline => _isOnline;

  MockDatabaseService get fallback => _fallback;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.databaseUrl,
      );

  @override
  Future<void> initialize() async {
    try {
      _isOnline = FirebaseBootstrap.isReady && Firebase.apps.isNotEmpty;
    } catch (e) {
      debugPrint('FirebaseDatabaseService: Firebase uninitialized ($e). Falling back to offline.');
      _isOnline = false;
    }

    await _fallback.initialize();
  }

  List<LeaderboardEntry> _parseLeaderboardSnapshot(Object? rawValue) {
    if (rawValue is! Map) return const [];
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final list = <LeaderboardEntry>[];
    for (final entry in rawValue.entries) {
      final key = entry.key.toString();
      if (key.startsWith('seed_')) continue;
      final val = entry.value;
      if (val is! Map) continue;
      final map = val.map((k, v) => MapEntry(k.toString(), v));
      final entryUid = (map['uid'] as String?) ?? key;
      if (entryUid.startsWith('seed_')) continue;
      final parsed = LeaderboardEntry.fromJson({
        ...map,
        'uid': entryUid,
        'isLocalPlayer': currentUid != null && entryUid == currentUid,
      });
      list.add(parsed);
    }

    list.sort((a, b) {
      final rpCmp = b.rankPoints.compareTo(a.rankPoints);
      if (rpCmp != 0) return rpCmp;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });

    return [
      for (int i = 0; i < list.length; i++)
        () {
          final e = list[i];
          final rankNum = i + 1;
          final isTop10 = rankNum <= PvpRankSystem.challengerTopLimit &&
              e.rankStars >= PvpRankSystem.challengerMinTotalStars;
          final resolvedTier = PvpRankSystem.getTierFromStars(
            e.rankStars,
            isTop10Challenger: isTop10,
          );
          return e.copyWith(rankNumber: rankNum, rankTier: resolvedTier);
        }(),
    ];
  }

  @override
  Future<void> saveProfile(PlayerProfile profile) async {
    await _fallback.saveProfile(profile);
    if (_isOnline) {
      try {
        // Đồng bộ lên nhánh /users/{userId}/profile trên Firebase Realtime Database
      } catch (e) {
        debugPrint('Firebase saveProfile failed: $e');
      }
    }
  }

  @override
  Future<PlayerProfile?> loadProfile(String userId) async {
    if (_isOnline) {
      try {
        // Truy vấn dữ liệu từ Firebase Realtime Database
      } catch (e) {
        debugPrint('Firebase loadProfile failed, falling back: $e');
      }
    }
    return _fallback.loadProfile(userId);
  }

  @override
  Stream<List<LeaderboardEntry>> streamTopLeaderboard({int limit = 20}) async* {
    if (_isOnline) {
      try {
        await for (final event in _db.ref('leaderboard').onValue) {
          final parsed = _parseLeaderboardSnapshot(event.snapshot.value);
          yield parsed.length <= limit
              ? List.unmodifiable(parsed)
              : List.unmodifiable(parsed.take(limit).toList());
        }
        return;
      } catch (e) {
        debugPrint('Firebase streamTopLeaderboard failed: $e');
      }
    }
    yield* _fallback.streamTopLeaderboard(limit: limit);
  }

  @override
  Future<void> updateLeaderboard(PlayerProfile profile) async {
    await _fallback.updateLeaderboard(profile);
    if (_isOnline) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      try {
        await _db.ref('leaderboard/${user.uid}').set({
          'uid': user.uid,
          'name': profile.playerName,
          'playerCode': profile.playerCode,
          'rankPoints': profile.rankPoints,
          'rankStars': profile.rankStars,
          'rankTier': profile.rankTier,
          'winRate': profile.winRateDisplay,
          'lastUpdated': DateTime.now().toIso8601String(),
          'heroId': profile.selectedHeroId,
          'heroLevel': profile.getHeroLevel(),
          'totalMatches': profile.totalMatches,
          'totalWins': profile.totalWins,
          'unlockedHeroCount': profile.unlockedHeroIds.length,
          'pveHighestFloor': profile.pveHighestFloor,
        });
      } catch (e) {
        debugPrint('Firebase updateLeaderboard failed: $e');
      }
    }
  }

  @override
  Future<({int serverRank, bool isChallengerTop10, int top10CutoffStars})>
      evaluatePlayerServerRank(PlayerProfile profile) async {
    if (_isOnline) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await updateLeaderboard(profile);
          final snap = await _db.ref('leaderboard').get();
          final list = _parseLeaderboardSnapshot(snap.value);
          final idx = list.indexWhere((e) => e.uid == user.uid);
          final serverRank = idx >= 0 ? list[idx].rankNumber : list.length + 1;
          final isChallengerTop10 =
              serverRank <= PvpRankSystem.challengerTopLimit &&
                  profile.rankStars >= PvpRankSystem.challengerMinTotalStars;
          int top10CutoffStars = PvpRankSystem.challengerMinTotalStars;
          if (list.length >= PvpRankSystem.challengerTopLimit) {
            final tenth = list[PvpRankSystem.challengerTopLimit - 1];
            top10CutoffStars = max(
              PvpRankSystem.challengerMinTotalStars,
              tenth.rankStars,
            );
          }
          return (
            serverRank: serverRank,
            isChallengerTop10: isChallengerTop10,
            top10CutoffStars: top10CutoffStars,
          );
        } catch (e) {
          debugPrint('Firebase evaluatePlayerServerRank failed: $e');
        }
      }
    }
    return _fallback.evaluatePlayerServerRank(profile);
  }

  @override
  Future<void> joinMatchmakingQueue(PvpQueueTicket ticket) async {
    if (_isOnline) {
      try {
        // Đẩy vé vào /matchmaking/queue/{ticketId}
      } catch (e) {
        debugPrint('Firebase joinMatchmakingQueue failed: $e');
      }
    }
    return _fallback.joinMatchmakingQueue(ticket);
  }

  @override
  Stream<PvpMatchSession?> streamMatchSession(String sessionId) {
    if (_isOnline) {
      try {
        // Lắng nghe thay đổi tại /rooms/{sessionId}
      } catch (e) {
        debugPrint('Firebase streamMatchSession failed: $e');
      }
    }
    return _fallback.streamMatchSession(sessionId);
  }

  @override
  Future<void> leaveMatchmakingQueue(String userId) async {
    if (_isOnline) {
      try {
        // Xóa vé tại /matchmaking/queue
      } catch (e) {
        debugPrint('Firebase leaveMatchmakingQueue failed: $e');
      }
    }
    return _fallback.leaveMatchmakingQueue(userId);
  }

  // --- Các phương thức tương thích ngược ---

  @override
  Future<void> syncPlayerProfile(PlayerProfile profile) async {
    await saveProfile(profile);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    if (_isOnline) {
      try {
        final snap = await _db.ref('leaderboard').get();
        final list = _parseLeaderboardSnapshot(snap.value);
        return list.take(20).map((e) => {
          'name': e.name,
          'rankPoints': e.rankPoints,
          'rankTier': e.rankTier,
          'winRate': e.winRate,
          'heroId': e.heroId,
          'rank': e.rankNumber,
          'isLocalPlayer': e.isLocalPlayer,
        }).toList();
      } catch (e) {
        debugPrint('Firebase fetchLeaderboard failed: $e');
      }
    }
    return _fallback.fetchLeaderboard();
  }

  @override
  Stream<PvpMatchState> listenToMatch(String matchId) {
    return _fallback.listenToMatch(matchId);
  }

  @override
  Future<String?> findOnlineMatch(PlayerProfile profile) async {
    return _fallback.findOnlineMatch(profile);
  }

  @override
  Future<void> submitMatchAction(String matchId, String action, Map<String, dynamic> data) async {
    return _fallback.submitMatchAction(matchId, action, data);
  }
}
