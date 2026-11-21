import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/database_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import 'player_storage.dart';

/// Lớp trừu tượng định nghĩa các hợp đồng dữ liệu cho toàn bộ trò chơi
/// Hỗ trợ cả môi trường Offline Fallback và Firebase Realtime Database
abstract class DatabaseService {
  static DatabaseService? _instance;

  /// Singleton truy cập dịch vụ cơ sở dữ liệu (mặc định nạp MockDatabaseService)
  static DatabaseService get instance {
    _instance ??= MockDatabaseService();
    return _instance!;
  }

  /// Cho phép hoán đổi triển khai tại runtime (ví dụ cho kiểm thử hoặc nạp Firebase)
  static void setInstance(DatabaseService service) {
    _instance = service;
  }

  /// Khởi tạo dịch vụ, nạp cache và thiết lập stream
  Future<void> initialize();

  /// Lưu trữ hồ sơ người chơi
  Future<void> saveProfile(PlayerProfile profile);

  /// Nạp hồ sơ người chơi theo userId (trả về null nếu không tìm thấy)
  Future<PlayerProfile?> loadProfile(String userId);

  /// Stream dữ liệu bảng xếp hạng Top người chơi theo thời gian thực
  Stream<List<LeaderboardEntry>> streamTopLeaderboard({int limit = 20});

  /// Cập nhật điểm và vị trí của người chơi trên bảng xếp hạng
  Future<void> updateLeaderboard(PlayerProfile profile);

  /// Đánh giá vị trí xếp hạng trên Server và xác định tư cách Thách Đấu (Top 10 nhiều sao nhất server)
  Future<({int serverRank, bool isChallengerTop10, int top10CutoffStars})>
      evaluatePlayerServerRank(PlayerProfile profile);

  /// Đăng ký vào hàng đợi tìm trận PvP
  Future<void> joinMatchmakingQueue(PvpQueueTicket ticket);

  /// Theo dõi trạng thái phiên ghép trận PvP theo sessionId
  Stream<PvpMatchSession?> streamMatchSession(String sessionId);

  /// Rời khỏi hoặc hủy hàng đợi tìm trận PvP
  Future<void> leaveMatchmakingQueue(String userId);

  /// Trạng thái kết nối: true nếu đang kết nối Cloud Firebase, false nếu Offline Fallback
  bool get isOnline;

  // --- Các phương thức tương thích ngược (Backward-Compatible) ---
  Future<void> syncPlayerProfile(PlayerProfile profile);
  Future<List<Map<String, dynamic>>> fetchLeaderboard();
  Stream<PvpMatchState> listenToMatch(String matchId);
  Future<String?> findOnlineMatch(PlayerProfile profile);
  Future<void> submitMatchAction(String matchId, String action, Map<String, dynamic> data);
}

/// Dịch vụ giả lập Offline-First Fallback
/// Hoạt động 100% độc lập, không phụ thuộc internet hay cấu hình Firebase
class MockDatabaseService implements DatabaseService {
  static const String storageKeyLeaderboard = 'big_war_mock_leaderboard';

  Duration matchSimulatedDelay;

  MockDatabaseService({
    this.matchSimulatedDelay = const Duration(milliseconds: 300),
  });

  final Map<String, Map<String, dynamic>> _inMemoryData = {};
  final Map<String, PlayerProfile> _profileCache = {};
  final StreamController<PvpMatchState> _matchStreamController =
      StreamController<PvpMatchState>.broadcast();

  final StreamController<List<LeaderboardEntry>> _leaderboardStreamController =
      StreamController<List<LeaderboardEntry>>.broadcast();

  List<LeaderboardEntry> _leaderboard = [];

  final Map<String, PvpMatchSession> _sessions = {};
  final Map<String, StreamController<PvpMatchSession?>> _sessionControllers = {};
  final Map<String, String> _userSessionMap = {};
  final Map<String, Timer> _matchTimers = {};

  bool _initialized = false;

  @override
  bool get isOnline => false;

  /// Danh sách bảng xếp hạng ban đầu (không dùng dữ liệu giả lập)
  static List<LeaderboardEntry> createDefaultLeaderboard() {
    return const [];
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKeyLeaderboard);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _leaderboard = decoded
            .map((item) => LeaderboardEntry.fromJson(item as Map<String, dynamic>))
            .where((e) => !e.uid.startsWith('seed_'))
            .toList();
        await _persistLeaderboard();
      } else {
        _leaderboard = [];
      }
    } catch (e) {
      debugPrint('MockDatabaseService init warning: $e. Using in-memory fallback.');
      _leaderboard = _leaderboard.where((e) => !e.uid.startsWith('seed_')).toList();
    }

    _initialized = true;
    _leaderboardStreamController.add(List.unmodifiable(_leaderboard));
  }

  Future<void> _persistLeaderboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _leaderboard.map((e) => e.toJson()).toList();
      await prefs.setString(storageKeyLeaderboard, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('MockDatabaseService save leaderboard warning: $e');
    }
  }

  @override
  Future<void> saveProfile(PlayerProfile profile) async {
    _profileCache[profile.playerName] = profile;
    _profileCache['local_player'] = profile;
    _inMemoryData['player_${profile.playerName}'] = profile.toJson();
    await PlayerStorage.saveProfile(profile);
    await updateLeaderboard(profile);
  }

  @override
  Future<PlayerProfile?> loadProfile(String userId) async {
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }
    if (userId == 'local_player' || userId == PlayerStorage.currentProfile.playerName) {
      return PlayerStorage.currentProfile;
    }
    try {
      final profile = await PlayerStorage.loadProfile();
      if (profile.playerName == userId || userId == 'local_player') {
        _profileCache[userId] = profile;
        return profile;
      }
    } catch (_) {}
    return null;
  }

  @override
  Stream<List<LeaderboardEntry>> streamTopLeaderboard({int limit = 20}) async* {
    if (!_initialized) {
      await initialize();
    }
    yield _getTopEntries(limit);
    yield* _leaderboardStreamController.stream.map((list) => _takeTop(list, limit));
  }

  List<LeaderboardEntry> _getTopEntries(int limit) {
    return _takeTop(_leaderboard, limit);
  }

  List<LeaderboardEntry> _takeTop(List<LeaderboardEntry> list, int limit) {
    if (list.length <= limit) return List.unmodifiable(list);
    return List.unmodifiable(list.take(limit).toList());
  }

  @override
  Future<void> updateLeaderboard(PlayerProfile profile) async {
    if (!_initialized) {
      await initialize();
    }

    // Xóa mục cũ của người chơi nếu đã có
    _leaderboard.removeWhere((e) =>
        e.isLocalPlayer ||
        e.uid == 'local_player' ||
        e.name == profile.playerName);

    final localEntry = LeaderboardEntry(
      uid: 'local_player',
      name: profile.playerName,
      rankPoints: profile.rankPoints,
      rankStars: profile.rankStars,
      rankTier: profile.rankTier,
      winRate: '60%',
      rankNumber: 1,
      lastUpdated: DateTime.now(),
      isLocalPlayer: true,
      heroId: profile.selectedHeroId,
    );

    _leaderboard.add(localEntry);

    // Sắp xếp giảm dần theo điểm RP / tổng số Sao, nếu bằng nhau thì xét theo thời gian
    _leaderboard.sort((a, b) {
      final rpCmp = b.rankPoints.compareTo(a.rankPoints);
      if (rpCmp != 0) return rpCmp;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });

    // Tính lại thứ hạng rankNumber từ 1..N và phân định Thách Đấu (Top 10 nhiều sao nhất server) vs Huyền Thoại
    _leaderboard = [
      for (int i = 0; i < _leaderboard.length; i++)
        () {
          final entry = _leaderboard[i];
          final rankNum = i + 1;
          final isTop10 = rankNum <= PvpRankSystem.challengerTopLimit &&
              entry.rankStars >= PvpRankSystem.legendaryStartTotalStars;
          final resolvedTier = PvpRankSystem.getTierFromStars(
            entry.rankStars,
            isTop10Challenger: isTop10,
          );
          return entry.copyWith(
            rankNumber: rankNum,
            rankTier: resolvedTier,
          );
        }(),
    ];

    await _persistLeaderboard();
    _leaderboardStreamController.add(List.unmodifiable(_leaderboard));
  }

  @override
  Future<({int serverRank, bool isChallengerTop10, int top10CutoffStars})>
      evaluatePlayerServerRank(PlayerProfile profile) async {
    await updateLeaderboard(profile);

    final localIdx = _leaderboard.indexWhere(
      (e) =>
          e.isLocalPlayer ||
          e.uid == 'local_player' ||
          e.name == profile.playerName,
    );
    final serverRank =
        localIdx >= 0 ? _leaderboard[localIdx].rankNumber : _leaderboard.length;
    final isChallengerTop10 =
        serverRank <= PvpRankSystem.challengerTopLimit &&
            profile.rankStars >= PvpRankSystem.legendaryStartTotalStars;

    int top10CutoffStars = PvpRankSystem.legendaryStartTotalStars + 1;
    if (_leaderboard.length >= PvpRankSystem.challengerTopLimit) {
      final tenthEntry = _leaderboard[PvpRankSystem.challengerTopLimit - 1];
      top10CutoffStars = max(
        PvpRankSystem.legendaryStartTotalStars,
        tenthEntry.rankStars,
      );
    }

    return (
      serverRank: serverRank,
      isChallengerTop10: isChallengerTop10,
      top10CutoffStars: top10CutoffStars,
    );
  }

  StreamController<PvpMatchSession?> _getOrCreateSessionController(String sessionId) {
    return _sessionControllers.putIfAbsent(
      sessionId,
      () => StreamController<PvpMatchSession?>.broadcast(),
    );
  }

  void _notifySession(PvpMatchSession session) {
    _getOrCreateSessionController(session.sessionId).add(session);
  }

  @override
  Future<void> joinMatchmakingQueue(PvpQueueTicket ticket) async {
    final sessionId = 'session_${ticket.ticketId}';
    final player1 = PvpOpponentInfo(
      name: ticket.playerName,
      rankPoints: ticket.rankPoints,
      rankTier: ticket.rankTier,
      heroId: ticket.heroId,
      isBot: false,
    );

    final searchingSession = PvpMatchSession(
      sessionId: sessionId,
      player1: player1,
      player2: null,
      state: PvpMatchSessionState.searching,
      createdAt: DateTime.now(),
    );

    _sessions[sessionId] = searchingSession;
    _userSessionMap[ticket.userId] = sessionId;
    _notifySession(searchingSession);

    // Hủy bộ đếm trước đó của người chơi nếu có
    _matchTimers[ticket.userId]?.cancel();

    // Giả lập thời gian tìm trận mạng và tự động ghép Bot phù hợp
    _matchTimers[ticket.userId] = Timer(matchSimulatedDelay, () {
      if (_sessions[sessionId]?.state == PvpMatchSessionState.searching) {
        final bot = PvpOpponentInfo.generateBot(
          ticket.rankPoints,
          playerHeroId: ticket.heroId,
        );
        final matchedSession = _sessions[sessionId]!.copyWith(
          player2: bot,
          state: PvpMatchSessionState.matched,
          matchedAt: DateTime.now(),
        );
        _sessions[sessionId] = matchedSession;
        _notifySession(matchedSession);
      }
    });
  }

  @override
  Stream<PvpMatchSession?> streamMatchSession(String sessionId) async* {
    if (_sessions.containsKey(sessionId)) {
      yield _sessions[sessionId];
    }
    final controller = _getOrCreateSessionController(sessionId);
    yield* controller.stream;
  }

  @override
  Future<void> leaveMatchmakingQueue(String userId) async {
    _matchTimers[userId]?.cancel();
    _matchTimers.remove(userId);

    final sessionId = _userSessionMap[userId];
    if (sessionId != null && _sessions.containsKey(sessionId)) {
      final current = _sessions[sessionId]!;
      if (current.state == PvpMatchSessionState.searching) {
        final cancelled = current.copyWith(state: PvpMatchSessionState.cancelled);
        _sessions[sessionId] = cancelled;
        _notifySession(cancelled);
      }
      _userSessionMap.remove(userId);
    }
  }

  // --- Các phương thức tương thích ngược ---

  @override
  Future<void> syncPlayerProfile(PlayerProfile profile) async {
    await saveProfile(profile);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    if (!_initialized) {
      await initialize();
    }
    return _leaderboard.take(20).map((e) => {
      'name': e.name,
      'rankPoints': e.rankPoints,
      'rankTier': e.rankTier,
      'winRate': e.winRate,
      'heroId': e.heroId,
      'rank': e.rankNumber,
      'isLocalPlayer': e.isLocalPlayer,
    }).toList();
  }

  @override
  Stream<PvpMatchState> listenToMatch(String matchId) {
    return _matchStreamController.stream;
  }

  @override
  Future<String?> findOnlineMatch(PlayerProfile profile) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final rand = Random();
    if (rand.nextDouble() < 0.4) {
      return 'room_${DateTime.now().millisecondsSinceEpoch}';
    }
    return null;
  }

  @override
  Future<void> submitMatchAction(String matchId, String action, Map<String, dynamic> data) async {
    _inMemoryData['action_${matchId}_$action'] = data;
  }
}
