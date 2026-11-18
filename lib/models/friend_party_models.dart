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

  const FriendInfo({
    required this.code,
    required this.name,
    required this.rankPoints,
    required this.rankTier,
    required this.selectedHeroId,
    this.heroLevel = 15,
    this.isOnline = true,
    this.statusText = 'Đang ở Sảnh Chờ',
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
    };
  }

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    final rp = (json['rankPoints'] as num?)?.toInt() ?? 1200;
    return FriendInfo(
      code: json['code'] as String? ?? 'GR0001',
      name: json['name'] as String? ?? 'Chiến Hữu',
      rankPoints: rp,
      rankTier: json['rankTier'] as String? ?? PvpEloCalculator.getRankTier(rp),
      selectedHeroId: json['selectedHeroId'] as String? ?? 'kaelen',
      heroLevel: (json['heroLevel'] as num?)?.toInt() ?? 10,
      isOnline: json['isOnline'] as bool? ?? true,
      statusText: json['statusText'] as String? ?? 'Đang Online',
    );
  }
}

class PartyRoomState {
  final String partyCode;
  final String leaderCode;
  final String leaderName;
  final String leaderHeroId;
  final int leaderHeroLevel;
  final PvpGameMode mode;
  final List<FriendInfo> members;

  const PartyRoomState({
    required this.partyCode,
    required this.leaderCode,
    required this.leaderName,
    this.leaderHeroId = 'george',
    this.leaderHeroLevel = 10,
    required this.mode,
    required this.members,
  });

  int get maxSlots => mode.teamSize;
  int get currentMemberCount => 1 + members.length; // 1 là chủ phòng + đồng đội
  bool get isFull => currentMemberCount >= maxSlots;

  PartyRoomState copyWith({
    String? partyCode,
    String? leaderCode,
    String? leaderName,
    String? leaderHeroId,
    int? leaderHeroLevel,
    PvpGameMode? mode,
    List<FriendInfo>? members,
  }) {
    return PartyRoomState(
      partyCode: partyCode ?? this.partyCode,
      leaderCode: leaderCode ?? this.leaderCode,
      leaderName: leaderName ?? this.leaderName,
      leaderHeroId: leaderHeroId ?? this.leaderHeroId,
      leaderHeroLevel: leaderHeroLevel ?? this.leaderHeroLevel,
      mode: mode ?? this.mode,
      members: members ?? this.members,
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
