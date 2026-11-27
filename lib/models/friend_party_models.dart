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
      heroLevel: heroLevel,
      isBot: false,
      isAlly: true,
    );
  }

  PvpOpponentInfo toPvpOpponent() {
    return PvpOpponentInfo(
      name: '$name [$code]',
      rankPoints: rankPoints,
      rankTier: rankTier,
      heroId: selectedHeroId,
      heroLevel: heroLevel,
      isBot: false,
      isAlly: false,
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
  final bool isCustomRoom;
  final String? preferredTeam; // 'blue' | 'red'

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
    this.isCustomRoom = false,
    this.preferredTeam,
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
        'isCustomRoom': isCustomRoom,
        'preferredTeam': preferredTeam,
      };

  factory PartyInvitation.fromJson(Map<String, dynamic> json) {
    final modeCode = json['mode'] as String? ?? '4v4';
    final mode = PvpGameMode.values.firstWhere(
      (m) => m.code == modeCode,
      orElse: () => PvpGameMode.squad4v4,
    );
    final partyCode = json['partyCode'] as String? ?? '';
    final isCustom = (json['isCustomRoom'] as bool?) ??
        partyCode.toUpperCase().startsWith('SOLO');
    return PartyInvitation(
      id: json['id'] as String? ?? '',
      partyCode: partyCode,
      fromCode: json['fromCode'] as String? ?? '',
      fromName: json['fromName'] as String? ?? 'Chủ Phòng',
      toCode: json['toCode'] as String? ?? '',
      toName: json['toName'] as String? ?? '',
      mode: mode,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      declineReason: json['declineReason'] as String?,
      isCustomRoom: isCustom,
      preferredTeam: json['preferredTeam'] as String?,
    );
  }

  PartyInvitation copyWith({
    String? status,
    String? declineReason,
    bool? isCustomRoom,
    String? preferredTeam,
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
      isCustomRoom: isCustomRoom ?? this.isCustomRoom,
      preferredTeam: preferredTeam ?? this.preferredTeam,
    );
  }
}

/// Trạng thái Phòng Đấu Tùy Chọn 4v4 (4 chỗ Đội Xanh VS 4 chỗ Đội Đỏ).
/// Người chơi trong phòng có thể mời bạn bè, tự do đổi chỗ giữa 2 phe (1v1, 1v2, 2v2, 3v3, 4v4...),
/// tất cả bấm Sẵn Sàng xong Chủ Phòng sẽ bấm Vào Game.
class SoloDuelRoomState {
  static const int slotsPerTeam = 4;
  static const List<int> presetBetAmounts = [0, 100, 200, 500, 1000, 2000, 5000];

  final String roomCode;
  final String hostCode;
  final String hostName;
  final List<FriendInfo?> blueSlots; // 4 chỗ Đội Xanh (index 0..3)
  final List<FriendInfo?> redSlots; // 4 chỗ Đội Đỏ (index 0..3)
  final List<String> readyCodes;
  final int betGold;
  final String? selectedMapId; // null hoặc '' = Ngẫu nhiên
  final String matchStatus; // 'idle' | 'in_match'
  final String? activeMatchRoomId;
  final String? resolvedMapId;
  final int updatedAt;

  SoloDuelRoomState({
    required this.roomCode,
    required this.hostCode,
    required this.hostName,
    List<FriendInfo?>? blueSlots,
    List<FriendInfo?>? redSlots,
    this.readyCodes = const [],
    this.betGold = 0,
    this.selectedMapId,
    this.matchStatus = 'idle',
    this.activeMatchRoomId,
    this.resolvedMapId,
    this.updatedAt = 0,
  })  : blueSlots = _normalizeSlots(blueSlots),
        redSlots = _normalizeSlots(redSlots);

  static List<FriendInfo?> _normalizeSlots(List<FriendInfo?>? raw) {
    final list = List<FriendInfo?>.filled(slotsPerTeam, null, growable: false);
    if (raw != null) {
      for (int i = 0; i < slotsPerTeam && i < raw.length; i++) {
        list[i] = raw[i];
      }
    }
    return list;
  }

  List<FriendInfo> get bluePlayers =>
      blueSlots.whereType<FriendInfo>().toList(growable: false);

  List<FriendInfo> get redPlayers =>
      redSlots.whereType<FriendInfo>().toList(growable: false);

  List<FriendInfo> get allPlayers => [...bluePlayers, ...redPlayers];

  int get blueCount => bluePlayers.length;
  int get redCount => redPlayers.length;
  int get totalPlayerCount => blueCount + redCount;
  int get maxPlayers => slotsPerTeam * 2;
  bool get isFull => totalPlayerCount >= maxPlayers;

  bool get hasBothTeams => blueCount >= 1 && redCount >= 1;
  int get totalPotGold => betGold * totalPlayerCount;
  bool get isRandomMap => selectedMapId == null || selectedMapId!.isEmpty;

  String get matchupLabel => '${blueCount}v$redCount';

  bool isHost(String playerCode) =>
      hostCode.trim().toUpperCase() == playerCode.trim().toUpperCase();

  bool containsPlayer(String playerCode) {
    final clean = playerCode.trim().toUpperCase();
    return allPlayers.any((p) => p.code.trim().toUpperCase() == clean);
  }

  /// Trả về 'blue', 'red' hoặc null nếu không ở trong phòng
  String? teamOf(String playerCode) {
    final clean = playerCode.trim().toUpperCase();
    if (blueSlots.any((p) => p != null && p.code.trim().toUpperCase() == clean)) {
      return 'blue';
    }
    if (redSlots.any((p) => p != null && p.code.trim().toUpperCase() == clean)) {
      return 'red';
    }
    return null;
  }

  /// Trả về chỉ số ô (0..3) trong đội của người chơi, hoặc -1
  int slotIndexOf(String playerCode) {
    final clean = playerCode.trim().toUpperCase();
    for (int i = 0; i < slotsPerTeam; i++) {
      if (blueSlots[i]?.code.trim().toUpperCase() == clean) return i;
    }
    for (int i = 0; i < slotsPerTeam; i++) {
      if (redSlots[i]?.code.trim().toUpperCase() == clean) return i;
    }
    return -1;
  }

  bool isPlayerReady(String playerCode) {
    if (isHost(playerCode)) return true;
    final clean = playerCode.trim().toUpperCase();
    return readyCodes.any((c) => c.trim().toUpperCase() == clean);
  }

  List<FriendInfo> get nonHostPlayers =>
      allPlayers.where((p) => !isHost(p.code)).toList(growable: false);

  bool get areAllGuestsReady =>
      nonHostPlayers.every((p) => isPlayerReady(p.code));

  bool get canHostStart =>
      matchStatus == 'idle' && hasBothTeams && areAllGuestsReady;

  FriendInfo? get hostInfo {
    final clean = hostCode.trim().toUpperCase();
    for (final p in allPlayers) {
      if (p.code.trim().toUpperCase() == clean) return p;
    }
    return null;
  }

  SoloDuelRoomState copyWith({
    String? roomCode,
    String? hostCode,
    String? hostName,
    List<FriendInfo?>? blueSlots,
    List<FriendInfo?>? redSlots,
    List<String>? readyCodes,
    int? betGold,
    String? selectedMapId,
    bool clearSelectedMap = false,
    String? matchStatus,
    String? activeMatchRoomId,
    String? resolvedMapId,
    bool clearActiveMatch = false,
    int? updatedAt,
  }) {
    return SoloDuelRoomState(
      roomCode: roomCode ?? this.roomCode,
      hostCode: hostCode ?? this.hostCode,
      hostName: hostName ?? this.hostName,
      blueSlots: blueSlots ?? List<FriendInfo?>.from(this.blueSlots),
      redSlots: redSlots ?? List<FriendInfo?>.from(this.redSlots),
      readyCodes: readyCodes ?? List<String>.from(this.readyCodes),
      betGold: betGold ?? this.betGold,
      selectedMapId:
          clearSelectedMap ? null : (selectedMapId ?? this.selectedMapId),
      matchStatus: matchStatus ?? this.matchStatus,
      activeMatchRoomId: clearActiveMatch
          ? null
          : (activeMatchRoomId ?? this.activeMatchRoomId),
      resolvedMapId:
          clearActiveMatch ? null : (resolvedMapId ?? this.resolvedMapId),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> encodeSlots(List<FriendInfo?> slots) {
      final map = <String, dynamic>{};
      for (int i = 0; i < slotsPerTeam; i++) {
        if (slots[i] != null) {
          map['s$i'] = slots[i]!.toJson();
        }
      }
      return map;
    }

    return {
      'roomType': 'solo_duel',
      'roomCode': roomCode.toUpperCase(),
      'hostCode': hostCode.toUpperCase(),
      'hostName': hostName,
      'blueSlots': encodeSlots(blueSlots),
      'redSlots': encodeSlots(redSlots),
      'readyCodes': readyCodes.map((e) => e.toUpperCase()).toList(),
      'betGold': betGold,
      'selectedMapId': selectedMapId,
      'matchStatus': matchStatus,
      'activeMatchRoomId': activeMatchRoomId,
      'resolvedMapId': resolvedMapId,
      'updatedAt': updatedAt,
    };
  }

  factory SoloDuelRoomState.fromJson(
    String fallbackCode,
    Map<String, dynamic> json,
  ) {
    Map<String, dynamic>? normMap(dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    List<FriendInfo?> decodeSlots(dynamic raw) {
      final result = List<FriendInfo?>.filled(slotsPerTeam, null);
      if (raw is Map) {
        for (int i = 0; i < slotsPerTeam; i++) {
          final item = raw['s$i'] ?? raw['$i'] ?? raw[i];
          final m = normMap(item);
          if (m != null) {
            result[i] = FriendInfo.fromJson(m);
          }
        }
      } else if (raw is List) {
        for (int i = 0; i < slotsPerTeam && i < raw.length; i++) {
          final m = normMap(raw[i]);
          if (m != null) {
            result[i] = FriendInfo.fromJson(m);
          }
        }
      }
      return result;
    }

    final parsedBlue = decodeSlots(json['blueSlots']);
    final parsedRed = decodeSlots(json['redSlots']);

    // Tương thích ngược với dữ liệu host/guest đơn lẻ nếu có
    final legacyHost = normMap(json['host']);
    if (legacyHost != null && parsedBlue.every((e) => e == null)) {
      parsedBlue[0] = FriendInfo.fromJson(legacyHost);
    }
    final legacyGuest = normMap(json['guest']);
    if (legacyGuest != null && parsedRed.every((e) => e == null)) {
      parsedRed[0] = FriendInfo.fromJson(legacyGuest);
    }

    final parsedReady = <String>[];
    final rawReady = json['readyCodes'];
    if (rawReady is List) {
      for (final item in rawReady) {
        final s = item.toString().trim().toUpperCase();
        if (s.isNotEmpty && !parsedReady.contains(s)) {
          parsedReady.add(s);
        }
      }
    } else if (rawReady is Map) {
      for (final val in rawReady.values) {
        final s = val.toString().trim().toUpperCase();
        if (s.isNotEmpty && !parsedReady.contains(s)) {
          parsedReady.add(s);
        }
      }
    } else if (json['isGuestReady'] == true && parsedRed[0] != null) {
      parsedReady.add(parsedRed[0]!.code.toUpperCase());
    }

    final resolvedHostCode = (json['hostCode'] as String?) ??
        parsedBlue[0]?.code ??
        'GR1000';
    final resolvedHostName = (json['hostName'] as String?) ??
        parsedBlue[0]?.name ??
        'Chủ Phòng';
    final rawSelMap = json['selectedMapId'] as String?;

    return SoloDuelRoomState(
      roomCode: (json['roomCode'] as String? ?? fallbackCode).toUpperCase(),
      hostCode: resolvedHostCode.toUpperCase(),
      hostName: resolvedHostName,
      blueSlots: parsedBlue,
      redSlots: parsedRed,
      readyCodes: parsedReady,
      betGold: ((json['betGold'] as num?)?.toInt() ?? 0).clamp(0, 1000000000).toInt(),
      selectedMapId:
          (rawSelMap != null && rawSelMap.isNotEmpty) ? rawSelMap : null,
      matchStatus: json['matchStatus'] as String? ?? 'idle',
      activeMatchRoomId: json['activeMatchRoomId'] as String?,
      resolvedMapId: json['resolvedMapId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
