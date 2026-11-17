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
  final PvpGameMode mode;
  final List<FriendInfo> members;

  const PartyRoomState({
    required this.partyCode,
    required this.leaderCode,
    required this.leaderName,
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
    PvpGameMode? mode,
    List<FriendInfo>? members,
  }) {
    return PartyRoomState(
      partyCode: partyCode ?? this.partyCode,
      leaderCode: leaderCode ?? this.leaderCode,
      leaderName: leaderName ?? this.leaderName,
      mode: mode ?? this.mode,
      members: members ?? this.members,
    );
  }
}
