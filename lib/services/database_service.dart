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
  static const String storageKeyLeaderboard = 'gold_rush_mock_leaderboard';

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

  /// Danh sách 20 game thủ hạt giống mẫu chuẩn Việt Nam
  static List<LeaderboardEntry> createDefaultLeaderboard() {
    final now = DateTime.now();
    return [
      LeaderboardEntry(
        uid: 'seed_1',
        name: 'BáĐạo99',
        rankPoints: 2850,
        rankTier: 'Thách Đấu',
        winRate: '72%',
        rankNumber: 1,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_2',
        name: 'ChiếnThần_SG',
        rankPoints: 2680,
        rankTier: 'Thách Đấu',
        winRate: '69%',
        rankNumber: 2,
        lastUpdated: now,
        heroId: 'tanker',
      ),
      LeaderboardEntry(
        uid: 'seed_3',
        name: 'ĐộcCôCầuBại',
        rankPoints: 2540,
        rankTier: 'Thách Đấu',
        winRate: '66%',
        rankNumber: 3,
        lastUpdated: now,
        heroId: 'ninja',
      ),
      LeaderboardEntry(
        uid: 'seed_4',
        name: 'RồngLửaVN',
        rankPoints: 2420,
        rankTier: 'Thách Đấu',
        winRate: '64%',
        rankNumber: 4,
        lastUpdated: now,
        heroId: 'ranger',
      ),
      LeaderboardEntry(
        uid: 'seed_5',
        name: 'TrùmSolo1v1',
        rankPoints: 2310,
        rankTier: 'Thách Đấu',
        winRate: '62%',
        rankNumber: 5,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_6',
        name: 'SátThủBóngĐêm',
        rankPoints: 2230,
        rankTier: 'Thách Đấu',
        winRate: '61%',
        rankNumber: 6,
        lastUpdated: now,
        heroId: 'ninja',
      ),
      LeaderboardEntry(
        uid: 'seed_7',
        name: 'LôiThầnHàThành',
        rankPoints: 2150,
        rankTier: 'Thách Đấu',
        winRate: '59%',
        rankNumber: 7,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_8',
        name: 'KiếmThánh_VN',
        rankPoints: 2080,
        rankTier: 'Thách Đấu',
        winRate: '58%',
        rankNumber: 8,
        lastUpdated: now,
        heroId: 'ranger',
      ),
      LeaderboardEntry(
        uid: 'seed_9',
        name: 'VôĐịchThiênHạ',
        rankPoints: 1990,
        rankTier: 'Kim Cương',
        winRate: '57%',
        rankNumber: 9,
        lastUpdated: now,
        heroId: 'tanker',
      ),
      LeaderboardEntry(
        uid: 'seed_10',
        name: 'BóngMaHưKhông',
        rankPoints: 1940,
        rankTier: 'Kim Cương',
        winRate: '56%',
        rankNumber: 10,
        lastUpdated: now,
        heroId: 'ninja',
      ),
      LeaderboardEntry(
        uid: 'seed_11',
        name: 'ThầnĐiêuĐạiHiệp',
        rankPoints: 1880,
        rankTier: 'Kim Cương',
        winRate: '55%',
        rankNumber: 11,
        lastUpdated: now,
        heroId: 'ranger',
      ),
      LeaderboardEntry(
        uid: 'seed_12',
        name: 'BấtBại_9x',
        rankPoints: 1820,
        rankTier: 'Kim Cương',
        winRate: '54%',
        rankNumber: 12,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_13',
        name: 'HắcBạchCôngTử',
        rankPoints: 1760,
        rankTier: 'Bạch Kim',
        winRate: '53%',
        rankNumber: 13,
        lastUpdated: now,
        heroId: 'tanker',
      ),
      LeaderboardEntry(
        uid: 'seed_14',
        name: 'TiểuLongNữ',
        rankPoints: 1710,
        rankTier: 'Bạch Kim',
        winRate: '52%',
        rankNumber: 14,
        lastUpdated: now,
        heroId: 'ranger',
      ),
      LeaderboardEntry(
        uid: 'seed_15',
        name: 'CuồngPhong_HN',
        rankPoints: 1640,
        rankTier: 'Bạch Kim',
        winRate: '51%',
        rankNumber: 15,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_16',
        name: 'BãoLửa2026',
        rankPoints: 1580,
        rankTier: 'Vàng',
        winRate: '50%',
        rankNumber: 16,
        lastUpdated: now,
        heroId: 'ranger',
      ),
      LeaderboardEntry(
        uid: 'seed_17',
        name: 'HiệpSĩBóngĐêm',
        rankPoints: 1520,
        rankTier: 'Vàng',
        winRate: '49%',
        rankNumber: 17,
        lastUpdated: now,
        heroId: 'tanker',
      ),
      LeaderboardEntry(
        uid: 'seed_18',
        name: 'NinjaSiêuCấp',
        rankPoints: 1440,
        rankTier: 'Vàng',
        winRate: '48%',
        rankNumber: 18,
        lastUpdated: now,
        heroId: 'ninja',
      ),
      LeaderboardEntry(
        uid: 'seed_19',
        name: 'ThầnSấm_VN',
        rankPoints: 1380,
        rankTier: 'Bạc',
        winRate: '47%',
        rankNumber: 19,
        lastUpdated: now,
        heroId: 'george',
      ),
      LeaderboardEntry(
        uid: 'seed_20',
        name: 'ĐạiHiệpBấtTử',
        rankPoints: 1290,
        rankTier: 'Bạc',
        winRate: '46%',
        rankNumber: 20,
        lastUpdated: now,
        heroId: 'tanker',
      ),
    ];
  }

  @override
  Future<void> initialize() async {
    if (_initialized && _leaderboard.isNotEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKeyLeaderboard);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _leaderboard = decoded
            .map((item) => LeaderboardEntry.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        _leaderboard = createDefaultLeaderboard();
        await _persistLeaderboard();
      }
    } catch (e) {
      debugPrint('MockDatabaseService init warning: $e. Using in-memory fallback.');
      if (_leaderboard.isEmpty) {
        _leaderboard = createDefaultLeaderboard();
      }
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
    if (!_initialized || _leaderboard.isEmpty) {
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
    if (!_initialized || _leaderboard.isEmpty) {
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
      rankTier: profile.rankTier,
      winRate: '60%',
      rankNumber: 1,
      lastUpdated: DateTime.now(),
      isLocalPlayer: true,
      heroId: profile.selectedHeroId,
    );

    _leaderboard.add(localEntry);

    // Sắp xếp giảm dần theo điểm Elo RP, nếu bằng nhau thì xét theo thời gian
    _leaderboard.sort((a, b) {
      final cmp = b.rankPoints.compareTo(a.rankPoints);
      if (cmp != 0) return cmp;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });

    // Tính lại thứ hạng rankNumber từ 1..N
    _leaderboard = [
      for (int i = 0; i < _leaderboard.length; i++)
        _leaderboard[i].copyWith(rankNumber: i + 1),
    ];

    await _persistLeaderboard();
    _leaderboardStreamController.add(List.unmodifiable(_leaderboard));
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
    if (!_initialized || _leaderboard.isEmpty) {
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
