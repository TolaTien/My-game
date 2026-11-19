import 'pvp_match.dart';

class FriendInfo {
  final String code;
  final String name;
  final int rankPoints;
  final String rankTier;
  final String selectedHeroId;
  final int heroLevel;
  final bool isOnline;
  final String statusText;
  final int updatedAt;

  const FriendInfo({
    required this.code,
    required this.name,
    required this.rankPoints,
    required this.rankTier,
    required this.selectedHeroId,
    this.heroLevel = 15,
    this.isOnline = false,
    this.statusText = 'Ngoại tuyến',
    this.updatedAt = 0,
  });

  PvpOpponentInfo toPvpAlly() {
    return PvpOpponentInfo(
      name: '$name [$code]',
      rankPoints: rankPoints,
      rankTier: rankTier,
      heroId: selectedHeroId,
      isBot: false,
      isAlly: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'rankPoints': rankPoints,
      'rankTier': rankTier,
      'selectedHeroId': selectedHeroId,
      'heroLevel': heroLevel,
      'isOnline': isOnline,
      'statusText': statusText,
      'updatedAt': updatedAt,
    };
  }

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    final rp = (json['rankPoints'] as num?)?.toInt() ?? 1200;
    final online = json['isOnline'] as bool? ?? false;
    return FriendInfo(
      code: (json['code'] as String? ?? 'GR0001').toUpperCase(),
      name: json['name'] as String? ?? 'Chiến Hữu',
      rankPoints: rp,
      rankTier: json['rankTier'] as String? ?? PvpEloCalculator.getRankTier(rp),
      selectedHeroId: json['selectedHeroId'] as String? ?? 'george',
      heroLevel: (json['heroLevel'] as num?)?.toInt() ?? 10,
      isOnline: online,
      statusText: json['statusText'] as String? ??
          (online ? 'Đang Online' : 'Ngoại tuyến'),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  FriendInfo copyWith({
    String? code,
    String? name,
    int? rankPoints,
    String? rankTier,
    String? selectedHeroId,
    int? heroLevel,
    bool? isOnline,
    String? statusText,
    int? updatedAt,
  }) {
    return FriendInfo(
      code: code ?? this.code,
      name: name ?? this.name,
      rankPoints: rankPoints ?? this.rankPoints,
      rankTier: rankTier ?? this.rankTier,
      selectedHeroId: selectedHeroId ?? this.selectedHeroId,
      heroLevel: heroLevel ?? this.heroLevel,
      isOnline: isOnline ?? this.isOnline,
      statusText: statusText ?? this.statusText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class FriendRequest {
  final String id;
  final String fromCode;
  final String fromName;
  final int fromRankPoints;
  final String fromRankTier;
  final String fromHeroId;
  final int fromHeroLevel;
  final String toCode;
  final String toName;
  final int timestamp;
  final String status; // 'pending', 'accepted', 'declined'

  const FriendRequest({
    required this.id,
    required this.fromCode,
    required this.fromName,
    required this.fromRankPoints,
    required this.fromRankTier,
    this.fromHeroId = 'george',
    this.fromHeroLevel = 1,
    required this.toCode,
    required this.toName,
    required this.timestamp,
    this.status = 'pending',
  });

  FriendInfo toFriendInfo({bool isOnline = true}) {
    return FriendInfo(
      code: fromCode.toUpperCase(),
      name: fromName,
      rankPoints: fromRankPoints,
      rankTier: fromRankTier,
      selectedHeroId: fromHeroId,
      heroLevel: fromHeroLevel,
      isOnline: isOnline,
      statusText: isOnline ? 'Đang Online' : 'Ngoại tuyến',
      updatedAt: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromCode': fromCode.toUpperCase(),
        'fromName': fromName,
        'fromRankPoints': fromRankPoints,
        'fromRankTier': fromRankTier,
        'fromHeroId': fromHeroId,
        'fromHeroLevel': fromHeroLevel,
        'toCode': toCode.toUpperCase(),
        'toName': toName,
        'timestamp': timestamp,
        'status': status,
      };

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    final rp = (json['fromRankPoints'] as num?)?.toInt() ?? 1000;
    return FriendRequest(
      id: json['id'] as String? ?? '',
      fromCode: (json['fromCode'] as String? ?? '').toUpperCase(),
      fromName: json['fromName'] as String? ?? 'Chiến Binh',
      fromRankPoints: rp,
      fromRankTier:
          json['fromRankTier'] as String? ?? PvpEloCalculator.getRankTier(rp),
      fromHeroId: json['fromHeroId'] as String? ?? 'george',
      fromHeroLevel: (json['fromHeroLevel'] as num?)?.toInt() ?? 1,
      toCode: (json['toCode'] as String? ?? '').toUpperCase(),
      toName: json['toName'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
    );
  }

  FriendRequest copyWith({String? status}) {
    return FriendRequest(
      id: id,
      fromCode: fromCode,
      fromName: fromName,
      fromRankPoints: fromRankPoints,
      fromRankTier: fromRankTier,
      fromHeroId: fromHeroId,
      fromHeroLevel: fromHeroLevel,
      toCode: toCode,
      toName: toName,
      timestamp: timestamp,
      status: status ?? this.status,
    );
  }
}

enum FriendRequestSendStatus {
  sent,
  autoAccepted,
  alreadyFriends,
  alreadySent,
  isSelf,
  notFound,
}

class FriendRequestSendResult {
  final FriendRequestSendStatus status;
  final FriendInfo? targetFriend;

  const FriendRequestSendResult({
    required this.status,
    this.targetFriend,
  });
}

class PartyRoomState {
  final String partyCode;
  final String leaderCode;
  final String leaderName;
  final String leaderHeroId;
  final int leaderHeroLevel;
  final PvpGameMode mode;
  final List<FriendInfo> members;
  final List<String> readyMemberCodes;
  final String matchStatus; // 'idle' | 'searching' | 'in_match'
  final String? activeMatchRoomId;
  final String? activeMapId;
  final int matchSeed;

  const PartyRoomState({
    required this.partyCode,
    required this.leaderCode,
    required this.leaderName,
    this.leaderHeroId = 'george',
    this.leaderHeroLevel = 10,
    required this.mode,
    required this.members,
    this.readyMemberCodes = const [],
    this.matchStatus = 'idle',
    this.activeMatchRoomId,
    this.activeMapId,
    this.matchSeed = 0,
  });

  int get maxSlots => mode.teamSize;
  int get currentMemberCount => 1 + members.length; // 1 là chủ phòng + đồng đội
  bool get isFull => currentMemberCount >= maxSlots;

  bool isLeader(String playerCode) =>
      leaderCode.trim().toUpperCase() == playerCode.trim().toUpperCase();

  bool isMemberReady(String memberCode) {
    final upper = memberCode.trim().toUpperCase();
    return readyMemberCodes.any((c) => c.trim().toUpperCase() == upper);
  }

  bool get areAllMembersReady =>
      members.every((m) => isMemberReady(m.code));

  PartyRoomState copyWith({
    String? partyCode,
    String? leaderCode,
    String? leaderName,
    String? leaderHeroId,
    int? leaderHeroLevel,
    PvpGameMode? mode,
    List<FriendInfo>? members,
    List<String>? readyMemberCodes,
    String? matchStatus,
    String? activeMatchRoomId,
    String? activeMapId,
    int? matchSeed,
    bool clearActiveMatch = false,
  }) {
    return PartyRoomState(
      partyCode: partyCode ?? this.partyCode,
      leaderCode: leaderCode ?? this.leaderCode,
      leaderName: leaderName ?? this.leaderName,
      leaderHeroId: leaderHeroId ?? this.leaderHeroId,
      leaderHeroLevel: leaderHeroLevel ?? this.leaderHeroLevel,
      mode: mode ?? this.mode,
      members: members ?? this.members,
      readyMemberCodes: readyMemberCodes ?? this.readyMemberCodes,
      matchStatus: matchStatus ?? this.matchStatus,
      activeMatchRoomId:
          clearActiveMatch ? null : (activeMatchRoomId ?? this.activeMatchRoomId),
      activeMapId: clearActiveMatch ? null : (activeMapId ?? this.activeMapId),
      matchSeed: matchSeed ?? this.matchSeed,
    );
  }
}

class PartyInvitation {
  final String id;
  final String partyCode;
  final String fromCode;
  final String fromName;
  final String toCode;
  final String toName;
  final PvpGameMode mode;
  final int timestamp;
  final String status; // 'pending', 'accepted', 'declined'
  final String? declineReason;

  const PartyInvitation({
    required this.id,
    required this.partyCode,
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    required this.mode,
    required this.timestamp,
    this.status = 'pending',
    this.declineReason,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'partyCode': partyCode,
        'fromCode': fromCode,
        'fromName': fromName,
        'toCode': toCode,
        'toName': toName,
        'mode': mode.code,
        'timestamp': timestamp,
        'status': status,
        'declineReason': declineReason,
      };

  factory PartyInvitation.fromJson(Map<String, dynamic> json) {
    final modeCode = json['mode'] as String? ?? '4v4';
    final mode = PvpGameMode.values.firstWhere(
      (m) => m.code == modeCode,
      orElse: () => PvpGameMode.squad4v4,
    );
    return PartyInvitation(
      id: json['id'] as String? ?? '',
      partyCode: json['partyCode'] as String? ?? '',
      fromCode: json['fromCode'] as String? ?? '',
      fromName: json['fromName'] as String? ?? 'Chủ Phòng',
      toCode: json['toCode'] as String? ?? '',
      toName: json['toName'] as String? ?? '',
      mode: mode,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      declineReason: json['declineReason'] as String?,
    );
  }

  PartyInvitation copyWith({
    String? status,
    String? declineReason,
  }) {
    return PartyInvitation(
      id: id,
      partyCode: partyCode,
      fromCode: fromCode,
      fromName: fromName,
      toCode: toCode,
      toName: toName,
      mode: mode,
      timestamp: timestamp,
      status: status ?? this.status,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}
