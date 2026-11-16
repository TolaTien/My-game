import 'package:flutter/material.dart';
import '../core/stat_growth_formula.dart';

class PlayerProfile {
  final String playerName;
  final String playerCode;
  final int gold;
  final int xu;
  final int diamonds;
  final int rankPoints;
  final List<String> unlockedHeroIds;
  final String selectedHeroId;
  final List<String> unlockedSkinIds;
  final String? selectedSkinId;
  final List<String> unlockedCompanionIds;
  final String? selectedCompanionId;
  final int lastSpinTimestamp;
  final Map<String, int> heroLevels;
  final Map<String, int> heroExp;
  final List<String> friendIds;

  /// Tỷ giá quy đổi chuẩn trong lộ trình: 1 Xu = 1000 Vàng
  static const int goldPerXu = 1000;

  const PlayerProfile({
    this.playerName = 'Chiến Binh #88',
    this.playerCode = 'GR8899',
    this.gold = 2000,
    this.xu = 5,
    this.diamonds = 50,
    this.rankPoints = 1000,
    this.unlockedHeroIds = const ['george'],
    this.selectedHeroId = 'george',
    this.unlockedSkinIds = const [],
    this.selectedSkinId,
    this.unlockedCompanionIds = const [],
    this.selectedCompanionId,
    this.lastSpinTimestamp = 0,
    this.heroLevels = const {'george': 1},
    this.heroExp = const {'george': 0},
    this.friendIds = const [],
  });

  factory PlayerProfile.defaultProfile() {
    return const PlayerProfile();
  }

  /// Lấy cấp độ hiện tại của một nhân vật (1 -> 100)
  int getHeroLevel([String? heroId]) {
    final id = heroId ?? selectedHeroId;
    final lv = heroLevels[id] ?? 1;
    return lv.clamp(
      StatGrowthFormula.minHeroLevel,
      StatGrowthFormula.maxHeroLevel,
    );
  }

  /// Lấy EXP hiện tại của một nhân vật
  int getHeroExp([String? heroId]) {
    final id = heroId ?? selectedHeroId;
    return heroExp[id] ?? 0;
  }

  /// Lấy EXP cần để lên cấp tiếp theo của nhân vật
  int getHeroExpToNextLevel([String? heroId]) {
    return StatGrowthFormula.expRequiredForNextLevel(getHeroLevel(heroId));
  }

  /// Lấy bộ chỉ số thực tế (HP, Ki, Sức đánh) của nhân vật theo cấp độ User (1 -> 100)
  HeroScaledStats getHeroScaledStats([String? heroId]) {
    final id = heroId ?? selectedHeroId;
    return StatGrowthFormula.computeStatsForLevel(
      heroId: id,
      level: getHeroLevel(id),
    );
  }

  /// Tổng giá trị tài sản quy đổi ra Vàng (1 Xu = 1000 Vàng)
  int get totalWealthInGold => gold + (xu * goldPerXu);

  /// Bậc rank theo điểm Rank Elo
  String get rankTier {
    if (rankPoints >= 2000) return 'Thách Đấu';
    if (rankPoints >= 1800) return 'Kim Cương';
    if (rankPoints >= 1600) return 'Bạch Kim';
    if (rankPoints >= 1400) return 'Vàng';
    if (rankPoints >= 1200) return 'Bạc';
    return 'Đồng';
  }

  /// Màu sắc đại diện cho Rank
  Color get rankColor {
    if (rankPoints >= 2000) return const Color(0xFFFF1744); // Đỏ Thách Đấu
    if (rankPoints >= 1800) return const Color(0xFF00E5FF); // Lam Kim Cương
    if (rankPoints >= 1600) return const Color(0xFF00E676); // Lục Bạch Kim
    if (rankPoints >= 1400) return const Color(0xFFFFD700); // Vàng Hoàng Kim
    if (rankPoints >= 1200) return const Color(0xFFCFD8DC); // Bạc Silver
    return const Color(0xFFCD7F32); // Đồng Bronze
  }

  /// Icon đại diện cho Rank
  IconData get rankIcon {
    if (rankPoints >= 2000) return Icons.local_fire_department_rounded;
    if (rankPoints >= 1800) return Icons.diamond_rounded;
    if (rankPoints >= 1600) return Icons.shield_rounded;
    if (rankPoints >= 1400) return Icons.military_tech_rounded;
    if (rankPoints >= 1200) return Icons.star_rounded;
    return Icons.shield_outlined;
  }

  /// Kiểm tra vòng quay may mắn đã reset lúc 00:00 UTC (07:00 VN) chưa
  bool canSpinToday() {
    if (lastSpinTimestamp <= 0) return true;

    final nowUtc = DateTime.now().toUtc();
    final lastSpinUtc = DateTime.fromMillisecondsSinceEpoch(
      lastSpinTimestamp,
      isUtc: true,
    );

    final nowDateUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final lastDateUtc = DateTime.utc(
      lastSpinUtc.year,
      lastSpinUtc.month,
      lastSpinUtc.day,
    );

    return nowDateUtc.isAfter(lastDateUtc);
  }

  /// Thời gian còn lại đến 00:00 UTC (07:00 sáng VN) tiếp theo
  Duration timeUntilNextReset() {
    final nowUtc = DateTime.now().toUtc();
    final nextResetUtc = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day + 1,
    );
    final diff = nextResetUtc.difference(nowUtc);
    return diff.isNegative ? Duration.zero : diff;
  }

  PlayerProfile copyWith({
    String? playerName,
    String? playerCode,
    int? gold,
    int? xu,
    int? diamonds,
    int? rankPoints,
    List<String>? unlockedHeroIds,
    String? selectedHeroId,
    List<String>? unlockedSkinIds,
    String? selectedSkinId,
    bool clearSkin = false,
    List<String>? unlockedCompanionIds,
    String? selectedCompanionId,
    bool clearCompanion = false,
    int? lastSpinTimestamp,
    Map<String, int>? heroLevels,
    Map<String, int>? heroExp,
    List<String>? friendIds,
  }) {
    return PlayerProfile(
      playerName: playerName ?? this.playerName,
      playerCode: playerCode ?? this.playerCode,
      gold: gold ?? this.gold,
      xu: xu ?? this.xu,
      diamonds: diamonds ?? this.diamonds,
      rankPoints: rankPoints ?? this.rankPoints,
      unlockedHeroIds: unlockedHeroIds ?? this.unlockedHeroIds,
      selectedHeroId: selectedHeroId ?? this.selectedHeroId,
      unlockedSkinIds: unlockedSkinIds ?? this.unlockedSkinIds,
      selectedSkinId:
          clearSkin ? null : (selectedSkinId ?? this.selectedSkinId),
      unlockedCompanionIds:
          unlockedCompanionIds ?? this.unlockedCompanionIds,
      selectedCompanionId: clearCompanion
          ? null
          : (selectedCompanionId ?? this.selectedCompanionId),
      lastSpinTimestamp: lastSpinTimestamp ?? this.lastSpinTimestamp,
      heroLevels: heroLevels ?? this.heroLevels,
      heroExp: heroExp ?? this.heroExp,
      friendIds: friendIds ?? this.friendIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playerName': playerName,
      'playerCode': playerCode,
      'gold': gold,
      'xu': xu,
      'diamonds': diamonds,
      'rankPoints': rankPoints,
      'unlockedHeroIds': unlockedHeroIds,
      'selectedHeroId': selectedHeroId,
      'unlockedSkinIds': unlockedSkinIds,
      'selectedSkinId': selectedSkinId,
      'unlockedCompanionIds': unlockedCompanionIds,
      'selectedCompanionId': selectedCompanionId,
      'lastSpinTimestamp': lastSpinTimestamp,
      'heroLevels': heroLevels,
      'heroExp': heroExp,
      'friendIds': friendIds,
    };
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    Map<String, int> parseIntMap(dynamic raw, Map<String, int> fallback) {
      if (raw is Map) {
        final result = <String, int>{};
        raw.forEach((key, value) {
          if (value is num) {
            result[key.toString()] = value.toInt();
          }
        });
        if (result.isNotEmpty) return result;
      }
      return fallback;
    }

    return PlayerProfile(
      playerName: json['playerName'] as String? ?? 'Chiến Binh #88',
      playerCode: json['playerCode'] as String? ?? 'GR8899',
      gold: (json['gold'] as num?)?.toInt() ?? 2000,
      xu: (json['xu'] as num?)?.toInt() ?? 5,
      diamonds: (json['diamonds'] as num?)?.toInt() ?? 50,
      rankPoints: (json['rankPoints'] as num?)?.toInt() ?? 1000,
      unlockedHeroIds: (json['unlockedHeroIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['george'],
      selectedHeroId: json['selectedHeroId'] as String? ?? 'george',
      unlockedSkinIds: (json['unlockedSkinIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      selectedSkinId: json['selectedSkinId'] as String?,
      unlockedCompanionIds: (json['unlockedCompanionIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      selectedCompanionId: json['selectedCompanionId'] as String?,
      lastSpinTimestamp: (json['lastSpinTimestamp'] as num?)?.toInt() ?? 0,
      heroLevels: parseIntMap(json['heroLevels'], const {'george': 1}),
      heroExp: parseIntMap(json['heroExp'], const {'george': 0}),
      friendIds: (json['friendIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
