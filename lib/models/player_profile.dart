import 'dart:math';

import 'package:flutter/material.dart';

import '../core/stat_growth_formula.dart';
import 'pvp_match.dart';

import '../core/companion_catalog.dart';

class PlayerProfile {
  final String playerName;
  final String playerCode;
  final int gold;
  final int xu;
  final int totalMatches;
  final int totalWins;
  final int rankPoints;
  final int? _rankStars;
  final bool? _isChallengerTop10;
  final int? serverRank;
  final List<String> unlockedHeroIds;
  final String selectedHeroId;
  final List<String> unlockedCompanionIds;
  final String? selectedCompanionId;
  final int lastSpinTimestamp;
  final Map<String, int> heroLevels;
  final Map<String, int> heroExp;
  final List<String> friendIds;
  final int pveCurrentFloor;
  final int pveHighestFloor;

  /// Tỷ giá quy đổi chuẩn trong lộ trình: 1 Xu = 1000 Vàng
  static const int goldPerXu = 1000;

  const PlayerProfile({
    this.playerName = 'Chiến Binh #88',
    this.playerCode = 'GR8899',
    this.gold = 500,
    this.xu = 1,
    this.totalMatches = 0,
    this.totalWins = 0,
    this.rankPoints = 1000,
    int? rankStars,
    bool? isChallengerTop10,
    this.serverRank,
    this.unlockedHeroIds = const ['george'],
    this.selectedHeroId = 'george',
    this.unlockedCompanionIds = const [],
    this.selectedCompanionId,
    this.lastSpinTimestamp = 0,
    this.heroLevels = const {'george': 1},
    this.heroExp = const {'george': 0},
    this.friendIds = const [],
    this.pveCurrentFloor = 1,
    this.pveHighestFloor = 1,
    // ignore: prefer_initializing_formals
  }) : _rankStars = rankStars,
       // ignore: prefer_initializing_formals
       _isChallengerTop10 = isChallengerTop10;

  factory PlayerProfile.defaultProfile({
    String? playerCode,
    String? playerName,
  }) {
    final rand = 1000 + Random().nextInt(8999);
    final code = playerCode ?? 'GR$rand';
    final name = playerName ?? 'Chiến Binh #$rand';
    return PlayerProfile(
      playerName: name,
      playerCode: code,
      rankPoints: 1000,
      rankStars: 0,
      isChallengerTop10: false,
    );
  }

  /// Tổng số sao tích lũy áp dụng chung cho cả 3 chế độ 1v1, 2v2, 4v4
  int get rankStars => _rankStars ?? PvpRankSystem.totalStarsFromRp(rankPoints);

  /// Số sao hiện tại trong bậc Rank:
  /// - Đồng -> Kim Cương: 0, 1, 2 (trên 3 sao để lên bậc tiếp theo)
  /// - Huyền Thoại -> Thách Đấu: 0 sao trở lên (rankStars - 15)
  int get starsInTier => PvpRankSystem.getStarsInTier(rankStars);

  /// Số sao tối đa của bậc hiện tại (3 cho Đồng -> Kim Cương, null cho Huyền Thoại / Thách Đấu)
  int? get maxStarsInTier => PvpRankSystem.getMaxStarsForTier(rankStars);

  /// Đã đạt bậc Huyền Thoại trở lên (tổng sao >= 15)
  bool get isLegendaryOrAbove =>
      rankStars >= PvpRankSystem.legendaryStartTotalStars;

  /// Kiểm tra người chơi có nằm trong Top 10 Thách Đấu nhiều sao nhất server hay không
  bool get isChallengerTop10 {
    if (!isLegendaryOrAbove) return false;
    if (_isChallengerTop10 != null) return _isChallengerTop10;
    if (serverRank != null) {
      return serverRank! >= 1 &&
          serverRank! <= PvpRankSystem.challengerTopLimit;
    }
    // Tương thích ngược khi khởi tạo const PlayerProfile(rankPoints: >= 2000) không truyền rankStars
    if (_rankStars == null) return rankPoints >= 2000;
    return false;
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

  /// Tỉ lệ thắng (%) tính trên tổng số trận đã đấu
  double get winRate =>
      totalMatches <= 0 ? 0.0 : (totalWins.clamp(0, totalMatches) / totalMatches) * 100.0;

  /// Chuỗi hiển thị gọn gàng cho Tỉ lệ thắng (VD: "0%", "75%", "66.7%")
  String get winRateDisplay {
    if (totalMatches <= 0) return '0%';
    final rate = winRate;
    if ((rate - rate.roundToDouble()).abs() < 0.05) {
      return '${rate.round()}%';
    }
    return '${rate.toStringAsFixed(1)}%';
  }

  /// Bậc rank theo hệ thống Sao (Đồng -> Bạc -> Vàng -> Bạch Kim -> Kim Cương -> Huyền Thoại -> Thách Đấu Top 10)
  String get rankTier {
    return PvpRankSystem.getTierFromStars(
      rankStars,
      isTop10Challenger: isChallengerTop10,
    );
  }

  /// Nhãn hiển thị đầy đủ Bậc Rank và số Sao (VD: "ĐỒNG • 2/3 ⭐" hoặc "HUYỀN THOẠI • 4 ⭐")
  String get rankDisplayLabel {
    return PvpRankSystem.formatRankLabel(
      rankStars,
      isTop10Challenger: isChallengerTop10,
      serverRank: serverRank,
    );
  }

  /// Đường dẫn ảnh huy hiệu Rank tương ứng với bậc Rank hiện tại
  String get rankAssetPath => PvpRankSystem.getRankAssetPath(rankTier);

  /// Màu sắc đại diện cho Rank
  Color get rankColor {
    switch (rankTier) {
      case 'Thách Đấu':
        return const Color(0xFFFF1744); // Đỏ Thách Đấu Top 10
      case 'Huyền Thoại':
        return const Color(0xFFE040FB); // Tím Hoàng Gia Huyền Thoại
      case 'Kim Cương':
        return const Color(0xFF00E5FF); // Lam Kim Cương
      case 'Bạch Kim':
        return const Color(0xFF00E676); // Lục Bạch Kim
      case 'Vàng':
        return const Color(0xFFFFD700); // Vàng Hoàng Kim
      case 'Bạc':
        return const Color(0xFFCFD8DC); // Bạc Silver
      default:
        return const Color(0xFFCD7F32); // Đồng Bronze
    }
  }

  /// Icon đại diện cho Rank
  IconData get rankIcon {
    switch (rankTier) {
      case 'Thách Đấu':
        return Icons.local_fire_department_rounded;
      case 'Huyền Thoại':
        return Icons.auto_awesome_rounded;
      case 'Kim Cương':
        return Icons.diamond_rounded;
      case 'Bạch Kim':
        return Icons.shield_rounded;
      case 'Vàng':
        return Icons.military_tech_rounded;
      case 'Bạc':
        return Icons.star_rounded;
      default:
        return Icons.shield_outlined;
    }
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
    int? totalMatches,
    int? totalWins,
    int? rankPoints,
    int? rankStars,
    bool? isChallengerTop10,
    int? serverRank,
    List<String>? unlockedHeroIds,
    String? selectedHeroId,
    List<String>? unlockedCompanionIds,
    String? selectedCompanionId,
    bool clearCompanion = false,
    int? lastSpinTimestamp,
    Map<String, int>? heroLevels,
    Map<String, int>? heroExp,
    List<String>? friendIds,
    int? pveCurrentFloor,
    int? pveHighestFloor,
  }) {
    final int resolvedRp;
    final int? resolvedStars;
    if (rankStars != null) {
      resolvedStars = rankStars;
      resolvedRp = rankPoints ?? PvpRankSystem.rpFromTotalStars(rankStars);
    } else if (rankPoints != null) {
      resolvedRp = rankPoints;
      resolvedStars = PvpRankSystem.totalStarsFromRp(rankPoints);
    } else {
      resolvedRp = this.rankPoints;
      resolvedStars = _rankStars;
    }

    return PlayerProfile(
      playerName: playerName ?? this.playerName,
      playerCode: playerCode ?? this.playerCode,
      gold: gold ?? this.gold,
      xu: xu ?? this.xu,
      totalMatches: totalMatches ?? this.totalMatches,
      totalWins: totalWins ?? this.totalWins,
      rankPoints: resolvedRp,
      rankStars: resolvedStars,
      isChallengerTop10: isChallengerTop10 ?? _isChallengerTop10,
      serverRank: serverRank ?? this.serverRank,
      unlockedHeroIds: unlockedHeroIds ?? this.unlockedHeroIds,
      selectedHeroId: selectedHeroId ?? this.selectedHeroId,
      unlockedCompanionIds: unlockedCompanionIds ?? this.unlockedCompanionIds,
      selectedCompanionId: clearCompanion
          ? null
          : (selectedCompanionId ?? this.selectedCompanionId),
      lastSpinTimestamp: lastSpinTimestamp ?? this.lastSpinTimestamp,
      heroLevels: heroLevels ?? this.heroLevels,
      heroExp: heroExp ?? this.heroExp,
      friendIds: friendIds ?? this.friendIds,
      pveCurrentFloor: (pveCurrentFloor ?? this.pveCurrentFloor).clamp(1, 9999),
      pveHighestFloor: max(
        (pveHighestFloor ?? this.pveHighestFloor).clamp(1, 9999),
        (pveCurrentFloor ?? this.pveCurrentFloor).clamp(1, 9999),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playerName': playerName,
      'playerCode': playerCode,
      'gold': gold,
      'xu': xu,
      'totalMatches': totalMatches,
      'totalWins': totalWins,
      'rankPoints': rankPoints,
      'rankStars': rankStars,
      'isChallengerTop10': isChallengerTop10,
      'serverRank': serverRank,
      'unlockedHeroIds': unlockedHeroIds,
      'selectedHeroId': selectedHeroId,
      'unlockedCompanionIds': unlockedCompanionIds,
      'selectedCompanionId': selectedCompanionId,
      'lastSpinTimestamp': lastSpinTimestamp,
      'heroLevels': heroLevels,
      'heroExp': heroExp,
      'friendIds': friendIds,
      'pveCurrentFloor': pveCurrentFloor,
      'pveHighestFloor': pveHighestFloor,
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

    List<String> parseStringList(dynamic raw, List<String> fallback) {
      if (raw is List) {
        return raw.where((e) => e != null).map((e) => e.toString()).toList();
      }
      if (raw is Map) {
        return raw.values
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList();
      }
      return fallback;
    }

    final parsedRp = (json['rankPoints'] as num?)?.toInt() ?? 1000;
    final parsedStars = (json['rankStars'] as num?)?.toInt();
    final parsedChallenger = json['isChallengerTop10'] as bool?;
    final parsedServerRank = (json['serverRank'] as num?)?.toInt();

    final parsedMatches = ((json['totalMatches'] as num?)?.toInt() ?? 0).clamp(
      0,
      1000000000,
    );
    final parsedWins = ((json['totalWins'] as num?)?.toInt() ?? 0).clamp(
      0,
      parsedMatches,
    );

    return PlayerProfile(
      playerName: json['playerName'] as String? ?? 'Chiến Binh #88',
      playerCode: json['playerCode'] as String? ?? 'GR8899',
      gold: (json['gold'] as num?)?.toInt() ?? 500,
      xu: (json['xu'] as num?)?.toInt() ?? 1,
      totalMatches: parsedMatches,
      totalWins: parsedWins,
      rankPoints: parsedRp,
      rankStars: parsedStars,
      isChallengerTop10: parsedChallenger,
      serverRank: parsedServerRank,
      unlockedHeroIds: parseStringList(json['unlockedHeroIds'], const [
        'george',
      ]),
      selectedHeroId: json['selectedHeroId'] as String? ?? 'george',
      unlockedCompanionIds: parseStringList(
        json['unlockedCompanionIds'],
        const [],
      ).where(availableCompanionIds.contains).toList(),
      selectedCompanionId:
          availableCompanionIds.contains(json['selectedCompanionId'])
          ? json['selectedCompanionId'] as String?
          : null,
      lastSpinTimestamp: (json['lastSpinTimestamp'] as num?)?.toInt() ?? 0,
      heroLevels: parseIntMap(json['heroLevels'], const {'george': 1}),
      heroExp: parseIntMap(json['heroExp'], const {'george': 0}),
      friendIds: parseStringList(json['friendIds'], const []),
      pveCurrentFloor:
          ((json['pveCurrentFloor'] as num?)?.toInt() ?? 1).clamp(1, 9999),
      pveHighestFloor:
          ((json['pveHighestFloor'] as num?)?.toInt() ?? 1).clamp(1, 9999),
    );
  }
}
