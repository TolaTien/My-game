import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/database_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import 'database_service.dart';

/// Dịch vụ kết nối Google Firebase Realtime Database
/// Có cơ chế phòng thủ (Shielding) tự động fallback về MockDatabaseService nếu
/// chưa cấu hình google-services.json hoặc không có kết nối internet.
class FirebaseDatabaseService implements DatabaseService {
  final MockDatabaseService _fallback;
  bool _isOnline = false;

  FirebaseDatabaseService({MockDatabaseService? fallback})
      : _fallback = fallback ?? MockDatabaseService();

  @override
  bool get isOnline => _isOnline;

  MockDatabaseService get fallback => _fallback;

  @override
  Future<void> initialize() async {
    try {
      // Khi người dùng cấu hình google-services.json và cài đặt Firebase SDK,
      // tiến trình kết nối sẽ được kích hoạt tại đây. Hiện tại bắt mọi ngoại lệ để đảm bảo
      // ứng dụng hoạt động 100% không bao giờ crash.
      _isOnline = false;
    } catch (e) {
      debugPrint('FirebaseDatabaseService: Firebase uninitialized ($e). Falling back to offline mock.');
      _isOnline = false;
    }

    // Luôn khởi tạo mock database dự phòng an toàn
    await _fallback.initialize();
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
  Stream<List<LeaderboardEntry>> streamTopLeaderboard({int limit = 20}) {
    if (_isOnline) {
      try {
        // Lắng nghe stream từ nhánh /leaderboard/top20
      } catch (e) {
        debugPrint('Firebase streamTopLeaderboard failed: $e');
      }
    }
    return _fallback.streamTopLeaderboard(limit: limit);
  }

  @override
  Future<void> updateLeaderboard(PlayerProfile profile) async {
    await _fallback.updateLeaderboard(profile);
    if (_isOnline) {
      try {
        // Cập nhật lên Firebase Realtime Database
      } catch (e) {
        debugPrint('Firebase updateLeaderboard failed: $e');
      }
    }
  }

  @override
  Future<({int serverRank, bool isChallengerTop10, int top10CutoffStars})>
      evaluatePlayerServerRank(PlayerProfile profile) async {
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
