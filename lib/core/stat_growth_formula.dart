import 'dart:math';
import '../registry/asset_registry.dart';

/// Chỉ số nhân vật sau khi đã tính cấp độ thông thạo của User (Level 1 -> 100)
class HeroScaledStats {
  final String heroId;
  final int level;
  final double maxHp;
  final double maxKi;
  final double attackDamage;
  final double moveSpeed;

  final double bonusHp;
  final double bonusKi;
  final double bonusAttack;

  final double hpGainPerLevel;
  final double kiGainPerLevel;
  final double attackGainPerLevel;

  const HeroScaledStats({
    required this.heroId,
    required this.level,
    required this.maxHp,
    required this.maxKi,
    required this.attackDamage,
    required this.moveSpeed,
    required this.bonusHp,
    required this.bonusKi,
    required this.bonusAttack,
    required this.hpGainPerLevel,
    required this.kiGainPerLevel,
    required this.attackGainPerLevel,
  });
}

/// Kết quả tăng cấp nhân vật (Level 1 -> 100) sau khi hoàn thành 1 trận đấu
class HeroLevelUpResult {
  final String heroId;
  final int oldLevel;
  final int newLevel;
  final int expEarned;
  final int currentExp;
  final int expToNextLevel;
  final HeroScaledStats oldStats;
  final HeroScaledStats newStats;

  const HeroLevelUpResult({
    required this.heroId,
    required this.oldLevel,
    required this.newLevel,
    required this.expEarned,
    required this.currentExp,
    required this.expToNextLevel,
    required this.oldStats,
    required this.newStats,
  });

  bool get didLevelUp => newLevel > oldLevel;
  int get levelsGained => newLevel - oldLevel;
  double get hpAdded => newStats.maxHp - oldStats.maxHp;
  double get kiAdded => newStats.maxKi - oldStats.maxKi;
  double get attackAdded => newStats.attackDamage - oldStats.attackDamage;
}

/// Hệ thống công thức tính cấp độ Nhân Vật của mỗi User từ Level 1 đến Level 100.
/// Sau mỗi trận đấu (PvE / PvP), nhân vật nhận EXP và tăng cấp độ vĩnh viễn,
/// cộng thêm HP, Ki, Sức đánh khác nhau tùy theo hệ tướng (Chiến binh, Sát thủ, Xạ thủ, Đỡ đòn, Pháp sư).
class StatGrowthFormula {
  static const int minHeroLevel = 1;
  static const int maxHeroLevel = 100;

  /// Lượng EXP cần thiết để lên từ [level] sang [level + 1]
  static int expRequiredForNextLevel(int level) {
    final clamped = level.clamp(minHeroLevel, maxHeroLevel);
    if (clamped >= maxHeroLevel) return 0;
    return (100 * pow(clamped, 1.32)).round();
  }

  /// Tính toán chỉ số HP, Ki, Sức đánh của nhân vật [heroId] ở cấp độ [level] (1 -> 100)
  static HeroScaledStats computeStatsForLevel({
    required String heroId,
    required int level,
  }) {
    final clampedLevel = level.clamp(minHeroLevel, maxHeroLevel);
    final heroCfg = GameAssetRegistry.instance.getHero(heroId);
    final base = heroCfg.baseStats;
    final growth = heroCfg.growthPerLevel;

    final lvDelta = clampedLevel - 1;
    // Cơ chế RPG phổ thông: cộng tuyến tính theo hệ tướng + hệ số đột phá nhẹ mỗi cấp
    final hpBonus =
        (lvDelta * growth.hpPerLevel * (1.0 + lvDelta * 0.004)).roundToDouble();
    final kiBonus = (lvDelta * growth.kiPerLevel).roundToDouble();
    final atkBonus = (lvDelta * growth.attackPerLevel * (1.0 + lvDelta * 0.003))
        .roundToDouble();

    return HeroScaledStats(
      heroId: heroId,
      level: clampedLevel,
      maxHp: base.hp + hpBonus,
      maxKi: base.ki + kiBonus,
      attackDamage: base.attack + atkBonus,
      moveSpeed: base.speed,
      bonusHp: hpBonus,
      bonusKi: kiBonus,
      bonusAttack: atkBonus,
      hpGainPerLevel: growth.hpPerLevel,
      kiGainPerLevel: growth.kiPerLevel,
      attackGainPerLevel: growth.attackPerLevel,
    );
  }

  /// Tính lượng EXP nhân vật nhận được sau mỗi trận game
  static int calculateMatchExpReward({
    required bool isVictory,
    required bool isPvp,
    int floorOrRounds = 1,
    int coinsOrKills = 0,
  }) {
    final baseExp = isPvp
        ? (isVictory ? 180 : 95)
        : (isVictory ? 150 : 75);
    final stageBonus = max(1, floorOrRounds) * 35;
    final performanceBonus = (coinsOrKills * 0.15).round().clamp(0, 120);
    return baseExp + stageBonus + performanceBonus;
  }

  /// Áp dụng cộng EXP sau trận đấu, tự động xử lý lên nhiều cấp liên tiếp (tối đa cấp 100)
  static HeroLevelUpResult applyExpGain({
    required String heroId,
    required int currentLevel,
    required int currentExp,
    required int expEarned,
  }) {
    int lv = currentLevel.clamp(minHeroLevel, maxHeroLevel);
    int exp = max(0, currentExp) + max(0, expEarned);
    final oldStats = computeStatsForLevel(heroId: heroId, level: lv);

    while (lv < maxHeroLevel) {
      final needed = expRequiredForNextLevel(lv);
      if (exp >= needed) {
        exp -= needed;
        lv++;
      } else {
        break;
      }
    }

    if (lv >= maxHeroLevel) {
      lv = maxHeroLevel;
      exp = 0;
    }

    final newStats = computeStatsForLevel(heroId: heroId, level: lv);
    return HeroLevelUpResult(
      heroId: heroId,
      oldLevel: currentLevel.clamp(minHeroLevel, maxHeroLevel),
      newLevel: lv,
      expEarned: expEarned,
      currentExp: exp,
      expToNextLevel: expRequiredForNextLevel(lv),
      oldStats: oldStats,
      newStats: newStats,
    );
  }
}
