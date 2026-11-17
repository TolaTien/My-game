import 'pvp_match.dart';

/// Đại diện cho một mục trong bảng xếp hạng Top người chơi
class LeaderboardEntry {
  final String uid;
  final String name;
  final int rankPoints;
  final String rankTier;
  final String winRate;
  final int rankNumber;
  final DateTime lastUpdated;
  final bool isLocalPlayer;
  final String heroId;

  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.rankPoints,
    required this.rankTier,
    required this.winRate,
    required this.rankNumber,
    required this.lastUpdated,
    this.isLocalPlayer = false,
    this.heroId = 'george',
  });

  /// Alias tương thích ngược
  String get userId => uid;
  String get playerName => name;
  int get rank => rankNumber;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'name': name,
    'rankPoints': rankPoints,
    'rankTier': rankTier,
    'winRate': winRate,
    'rankNumber': rankNumber,
    'lastUpdated': lastUpdated.toIso8601String(),
    'isLocalPlayer': isLocalPlayer,
    'heroId': heroId,
  };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['lastUpdated'] != null) {
      parsedDate = DateTime.tryParse(json['lastUpdated'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return LeaderboardEntry(
      uid: json['uid'] as String? ?? (json['userId'] as String? ?? 'unknown'),
      name: json['name'] as String? ?? (json['playerName'] as String? ?? 'Vô Danh'),
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 1000,
      rankTier: json['rankTier'] as String? ?? 'Đồng',
      winRate: json['winRate'] as String? ?? '50%',
      rankNumber: (json['rankNumber'] as num?)?.toInt() ?? ((json['rank'] as num?)?.toInt() ?? 1),
      lastUpdated: parsedDate,
      isLocalPlayer: (json['isLocalPlayer'] as bool?) ?? ((json['isCurrentPlayer'] as bool?) ?? false),
      heroId: json['heroId'] as String? ?? 'george',
    );
  }

  LeaderboardEntry copyWith({
    String? uid,
    String? name,
    int? rankPoints,
    String? rankTier,
    String? winRate,
    int? rankNumber,
    DateTime? lastUpdated,
    bool? isLocalPlayer,
    String? heroId,
  }) {
    return LeaderboardEntry(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      rankPoints: rankPoints ?? this.rankPoints,
      rankTier: rankTier ?? this.rankTier,
      winRate: winRate ?? this.winRate,
      rankNumber: rankNumber ?? this.rankNumber,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isLocalPlayer: isLocalPlayer ?? this.isLocalPlayer,
      heroId: heroId ?? this.heroId,
    );
  }

  @override
  String toString() => 'LeaderboardEntry(#$rankNumber $name - $rankPoints RP [$rankTier])';
}

/// Vé hàng đợi tìm trận PvP (Matchmaking Queue Ticket)
class PvpQueueTicket {
  final String ticketId;
  final String userId;
  final String playerName;
  final int rankPoints;
  final DateTime timestamp;
  final String rankTier;
  final String heroId;

  const PvpQueueTicket({
    required this.ticketId,
    required this.userId,
    required this.playerName,
    required this.rankPoints,
    required this.timestamp,
    this.rankTier = 'Đồng',
    this.heroId = 'george',
  });

  Map<String, dynamic> toJson() => {
    'ticketId': ticketId,
    'userId': userId,
    'playerName': playerName,
    'rankPoints': rankPoints,
    'timestamp': timestamp.toIso8601String(),
    'rankTier': rankTier,
    'heroId': heroId,
  };

  factory PvpQueueTicket.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    if (json['timestamp'] is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int);
    } else if (json['timestamp'] != null) {
      parsedTime = DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now();
    } else {
      parsedTime = DateTime.now();
    }

    return PvpQueueTicket(
      ticketId: json['ticketId'] as String? ?? 'ticket_${DateTime.now().millisecondsSinceEpoch}',
      userId: json['userId'] as String? ?? 'unknown',
      playerName: json['playerName'] as String? ?? 'Vô Danh',
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 1000,
      timestamp: parsedTime,
      rankTier: json['rankTier'] as String? ?? 'Đồng',
      heroId: json['heroId'] as String? ?? 'george',
    );
  }

  PvpQueueTicket copyWith({
    String? ticketId,
    String? userId,
    String? playerName,
    int? rankPoints,
    DateTime? timestamp,
    String? rankTier,
    String? heroId,
  }) {
    return PvpQueueTicket(
      ticketId: ticketId ?? this.ticketId,
      userId: userId ?? this.userId,
      playerName: playerName ?? this.playerName,
      rankPoints: rankPoints ?? this.rankPoints,
      timestamp: timestamp ?? this.timestamp,
      rankTier: rankTier ?? this.rankTier,
      heroId: heroId ?? this.heroId,
    );
  }
}

/// Trạng thái phiên tìm kiếm và ghép trận PvP
enum PvpMatchSessionState {
  searching,
  matched,
  cancelled,
  completed,
}

/// Phiên ghép trận PvP đối kháng trực tuyến hoặc giả lập
class PvpMatchSession {
  final String sessionId;
  final PvpOpponentInfo player1;
  final PvpOpponentInfo? player2;
  final PvpMatchSessionState state;
  final DateTime createdAt;
  final DateTime? matchedAt;

  const PvpMatchSession({
    required this.sessionId,
    required this.player1,
    this.player2,
    required this.state,
    required this.createdAt,
    this.matchedAt,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'player1': player1.toJson(),
    'player2': player2?.toJson(),
    'state': state.name,
    'createdAt': createdAt.toIso8601String(),
    'matchedAt': matchedAt?.toIso8601String(),
  };

  factory PvpMatchSession.fromJson(Map<String, dynamic> json) {
    PvpMatchSessionState sessionState = PvpMatchSessionState.searching;
    final stateStr = json['state'] as String?;
    if (stateStr != null) {
      for (final s in PvpMatchSessionState.values) {
        if (s.name == stateStr) {
          sessionState = s;
          break;
        }
      }
    }

    final p1Map = json['player1'] as Map<String, dynamic>? ?? {};
    final p2Map = json['player2'] as Map<String, dynamic>?;

    DateTime created = DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now();
    DateTime? matched = json['matchedAt'] != null
        ? DateTime.tryParse(json['matchedAt'].toString())
        : null;

    return PvpMatchSession(
      sessionId: json['sessionId'] as String? ?? 'session_unknown',
      player1: pvpOpponentInfoFromJson(p1Map),
      player2: p2Map != null ? pvpOpponentInfoFromJson(p2Map) : null,
      state: sessionState,
      createdAt: created,
      matchedAt: matched,
    );
  }

  PvpMatchSession copyWith({
    String? sessionId,
    PvpOpponentInfo? player1,
    PvpOpponentInfo? player2,
    PvpMatchSessionState? state,
    DateTime? createdAt,
    DateTime? matchedAt,
  }) {
    return PvpMatchSession(
      sessionId: sessionId ?? this.sessionId,
      player1: player1 ?? this.player1,
      player2: player2 ?? this.player2,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      matchedAt: matchedAt ?? this.matchedAt,
    );
  }
}

/// Tiện ích hỗ trợ tuần tự hóa (serialization) cho PvpOpponentInfo
extension PvpOpponentInfoSerialization on PvpOpponentInfo {
  Map<String, dynamic> toJson() => {
    'name': name,
    'rankPoints': rankPoints,
    'rankTier': rankTier,
    'heroId': heroId,
    'isBot': isBot,
    'difficulty': difficulty.name,
  };
}

PvpOpponentInfo pvpOpponentInfoFromJson(Map<String, dynamic> json) {
  BotDifficulty diff = BotDifficulty.bronzeSilver;
  final diffStr = json['difficulty'] as String?;
  if (diffStr != null) {
    for (final d in BotDifficulty.values) {
      if (d.name == diffStr) {
        diff = d;
        break;
      }
    }
  }

  return PvpOpponentInfo(
    name: json['name'] as String? ?? 'Vô Danh',
    rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 1000,
    rankTier: json['rankTier'] as String? ?? 'Đồng',
    heroId: json['heroId'] as String? ?? 'george',
    isBot: json['isBot'] as bool? ?? true,
    difficulty: diff,
  );
}
