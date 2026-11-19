import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HeroBaseStatsConfig {
  final double hp;
  final double ki;
  final double attack;
  final double speed;

  const HeroBaseStatsConfig({
    required this.hp,
    required this.ki,
    required this.attack,
    required this.speed,
  });

  factory HeroBaseStatsConfig.fromJson(Map<String, dynamic> json) {
    return HeroBaseStatsConfig(
      hp: (json['hp'] as num?)?.toDouble() ?? 100.0,
      ki: (json['ki'] as num?)?.toDouble() ?? 100.0,
      attack: (json['attack'] as num?)?.toDouble() ?? 25.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 150.0,
    );
  }
}

class HeroGrowthConfig {
  final double hpPerLevel;
  final double kiPerLevel;
  final double attackPerLevel;

  const HeroGrowthConfig({
    required this.hpPerLevel,
    required this.kiPerLevel,
    required this.attackPerLevel,
  });

  factory HeroGrowthConfig.fromJson(Map<String, dynamic> json) {
    return HeroGrowthConfig(
      hpPerLevel: (json['hpPerLevel'] as num?)?.toDouble() ?? 14.0,
      kiPerLevel: (json['kiPerLevel'] as num?)?.toDouble() ?? 3.5,
      attackPerLevel: (json['attackPerLevel'] as num?)?.toDouble() ?? 2.2,
    );
  }
}

class HeroSpriteConfig {
  final int frameWidth;
  final int frameHeight;
  final String idleSheet;
  final String runSheet;
  final String attackSheet;
  final String? skill1Sheet;
  final bool useProceduralFallback;

  const HeroSpriteConfig({
    this.frameWidth = 48,
    this.frameHeight = 48,
    required this.idleSheet,
    required this.runSheet,
    required this.attackSheet,
    this.skill1Sheet,
    this.useProceduralFallback = true,
  });

  factory HeroSpriteConfig.fromJson(Map<String, dynamic> json) {
    return HeroSpriteConfig(
      frameWidth: (json['frameWidth'] as num?)?.toInt() ?? 48,
      frameHeight: (json['frameHeight'] as num?)?.toInt() ?? 48,
      idleSheet: json['idleSheet'] as String? ?? '',
      runSheet: json['runSheet'] as String? ?? '',
      attackSheet: json['attackSheet'] as String? ?? '',
      skill1Sheet: json['skill1Sheet'] as String?,
      useProceduralFallback: json['useProceduralFallback'] as bool? ?? true,
    );
  }
}

class HeroAssetConfig {
  final String id;
  final String name;
  final String role;
  final String classType;
  final int priceGold;
  final bool unlockedByDefault;
  final HeroBaseStatsConfig baseStats;
  final HeroGrowthConfig growthPerLevel;
  final List<String> skillIds;
  final HeroSpriteConfig sprites;

  const HeroAssetConfig({
    required this.id,
    required this.name,
    required this.role,
    required this.classType,
    required this.priceGold,
    required this.unlockedByDefault,
    required this.baseStats,
    required this.growthPerLevel,
    required this.skillIds,
    required this.sprites,
  });

  factory HeroAssetConfig.fromJson(Map<String, dynamic> json) {
    return HeroAssetConfig(
      id: json['id'] as String? ?? 'george',
      name: json['name'] as String? ?? 'George',
      role: json['role'] as String? ?? 'Đấu Sĩ',
      classType: json['classType'] as String? ?? 'warrior',
      priceGold: (json['priceGold'] as num?)?.toInt() ?? 0,
      unlockedByDefault: json['unlockedByDefault'] as bool? ?? false,
      baseStats: HeroBaseStatsConfig.fromJson(
        (json['baseStats'] as Map<String, dynamic>?) ?? const {},
      ),
      growthPerLevel: HeroGrowthConfig.fromJson(
        (json['growthPerLevel'] as Map<String, dynamic>?) ?? const {},
      ),
      skillIds: (json['skillIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sprites: HeroSpriteConfig.fromJson(
        (json['sprites'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

class SkillAssetConfig {
  final String id;
  final String heroId;
  final int slot;
  final String name;
  final String description;
  final double cooldown;
  final double kiCost;
  final double damageMultiplier;
  final double radius;
  final String iconAsset;
  final String sfxAsset;

  double get configuredKiCost => kiCost;

  const SkillAssetConfig({
    required this.id,
    required this.heroId,
    required this.slot,
    required this.name,
    required this.description,
    required this.cooldown,
    required this.kiCost,
    required this.damageMultiplier,
    required this.radius,
    required this.iconAsset,
    required this.sfxAsset,
  });

  factory SkillAssetConfig.fromJson(Map<String, dynamic> json) {
    return SkillAssetConfig(
      id: json['id'] as String? ?? '',
      heroId: json['heroId'] as String? ?? 'george',
      slot: (json['slot'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Kỹ năng',
      description: json['description'] as String? ?? '',
      cooldown: (json['cooldown'] as num?)?.toDouble() ?? 5.0,
      kiCost: (json['kiCost'] as num?)?.toDouble() ?? 20.0,
      damageMultiplier: (json['damageMultiplier'] as num?)?.toDouble() ?? 1.5,
      radius: (json['radius'] as num?)?.toDouble() ?? 80.0,
      iconAsset: json['iconAsset'] as String? ?? '',
      sfxAsset: json['sfxAsset'] as String? ?? '',
    );
  }
}

class CompanionAssetConfig {
  final String id;
  final String name;
  final String role;
  final String type;
  final int priceGold;
  final double autoAttackInterval;
  final double autoAttackRange;
  final double damageRatio;
  final String activeSkillName;
  final double activeSkillCooldown;
  final String activeSkillDescription;
  final String spriteSheet;
  final bool useProceduralFallback;

  const CompanionAssetConfig({
    required this.id,
    required this.name,
    required this.role,
    required this.type,
    required this.priceGold,
    required this.autoAttackInterval,
    required this.autoAttackRange,
    required this.damageRatio,
    required this.activeSkillName,
    required this.activeSkillCooldown,
    required this.activeSkillDescription,
    required this.spriteSheet,
    this.useProceduralFallback = true,
  });

  factory CompanionAssetConfig.fromJson(Map<String, dynamic> json) {
    return CompanionAssetConfig(
      id: json['id'] as String? ?? 'aegis_x9',
      name: json['name'] as String? ?? 'Aegis-X9',
      role: json['role'] as String? ?? 'Trợ Thủ AI',
      type: json['type'] as String? ?? 'hybrid',
      priceGold: (json['priceGold'] as num?)?.toInt() ?? 3000,
      autoAttackInterval: (json['autoAttackInterval'] as num?)?.toDouble() ?? 1.2,
      autoAttackRange: (json['autoAttackRange'] as num?)?.toDouble() ?? 200.0,
      damageRatio: (json['damageRatio'] as num?)?.toDouble() ?? 0.15,
      activeSkillName: json['activeSkillName'] as String? ?? 'Kỹ năng Trợ Thủ',
      activeSkillCooldown:
          (json['activeSkillCooldown'] as num?)?.toDouble() ?? 14.0,
      activeSkillDescription: json['activeSkillDescription'] as String? ?? '',
      spriteSheet: json['spriteSheet'] as String? ?? '',
      useProceduralFallback: json['useProceduralFallback'] as bool? ?? true,
    );
  }
}

class MapAssetConfig {
  final String id;
  final int stage;
  final String name;
  final String mode;
  final int cols;
  final int rows;
  final int tileSize;
  final List<int> playerSpawn;
  final List<int> bossSpawn;
  final List<List<int>> monsterPortals;
  final List<List<int>> buffNodes;
  final String tilesetImage;
  final String tiledMapFile;

  const MapAssetConfig({
    required this.id,
    required this.stage,
    required this.name,
    required this.mode,
    required this.cols,
    required this.rows,
    required this.tileSize,
    required this.playerSpawn,
    required this.bossSpawn,
    required this.monsterPortals,
    required this.buffNodes,
    required this.tilesetImage,
    required this.tiledMapFile,
  });

  factory MapAssetConfig.fromJson(Map<String, dynamic> json) {
    List<int> parseCoord(dynamic raw, List<int> fallback) {
      if (raw is List && raw.length >= 2) {
        return [(raw[0] as num).toInt(), (raw[1] as num).toInt()];
      }
      return fallback;
    }

    List<List<int>> parseCoordList(dynamic raw) {
      if (raw is List) {
        return raw
            .map((e) => parseCoord(e, const [5, 5]))
            .toList(growable: false);
      }
      return const [];
    }

    return MapAssetConfig(
      id: json['id'] as String? ?? 'sunken_golden_sanctum',
      stage: (json['stage'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Phế Tích Hoàng Kim',
      mode: json['mode'] as String? ?? 'pve',
      cols: (json['cols'] as num?)?.toInt() ?? 40,
      rows: (json['rows'] as num?)?.toInt() ?? 28,
      tileSize: (json['tileSize'] as num?)?.toInt() ?? 32,
      playerSpawn: parseCoord(json['playerSpawn'], const [20, 24]),
      bossSpawn: parseCoord(json['bossSpawn'], const [20, 14]),
      monsterPortals: parseCoordList(json['monsterPortals']),
      buffNodes: parseCoordList(json['buffNodes']),
      tilesetImage: json['tilesetImage'] as String? ?? '',
      tiledMapFile: json['tiledMapFile'] as String? ?? '',
    );
  }
}

class EnemyAssetConfig {
  final String id;
  final String name;
  final String type;
  final double baseHp;
  final double baseDamage;
  final double speed;
  final int expReward;
  final int goldReward;
  final String spriteSheet;

  const EnemyAssetConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.baseHp,
    required this.baseDamage,
    required this.speed,
    required this.expReward,
    required this.goldReward,
    required this.spriteSheet,
  });

  factory EnemyAssetConfig.fromJson(Map<String, dynamic> json) {
    return EnemyAssetConfig(
      id: json['id'] as String? ?? 'zombie',
      name: json['name'] as String? ?? 'Quái vật',
      type: json['type'] as String? ?? 'melee',
      baseHp: (json['baseHp'] as num?)?.toDouble() ?? 60.0,
      baseDamage: (json['baseDamage'] as num?)?.toDouble() ?? 10.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 75.0,
      expReward: (json['expReward'] as num?)?.toInt() ?? 25,
      goldReward: (json['goldReward'] as num?)?.toInt() ?? 50,
      spriteSheet: json['spriteSheet'] as String? ?? '',
    );
  }
}

/// Trung tâm quản lý tài nguyên (Data-Driven Asset Registry).
/// Đọc cấu hình từ `assets/data/*.json` giúp người dùng dễ dàng thêm nhân vật,
/// kỹ năng, trợ thủ, bản đồ mới vào `assets/` mà không phải sửa code engine.
class GameAssetRegistry {
  GameAssetRegistry._() {
    _seedFallbackDefaults();
  }

  static final GameAssetRegistry instance = GameAssetRegistry._();

  final Map<String, HeroAssetConfig> _heroes = {};
  final Map<String, SkillAssetConfig> _skills = {};
  final Map<String, CompanionAssetConfig> _companions = {};
  final Map<String, MapAssetConfig> _maps = {};
  final Map<String, EnemyAssetConfig> _enemies = {};

  bool _initialized = false;
  bool get isInitialized => _initialized;

  List<HeroAssetConfig> get heroes => _heroes.values.toList(growable: false);
  List<SkillAssetConfig> get skills => _skills.values.toList(growable: false);
  List<CompanionAssetConfig> get companions =>
      _companions.values.toList(growable: false);
  List<MapAssetConfig> get maps => _maps.values.toList(growable: false);
  List<EnemyAssetConfig> get enemies => _enemies.values.toList(growable: false);

  HeroAssetConfig getHero(String heroId) {
    return _heroes[heroId] ?? _heroes['george']!;
  }

  List<SkillAssetConfig> getSkillsForHero(String heroId) {
    final list = _skills.values
        .where((s) => s.heroId == heroId)
        .toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    if (list.isNotEmpty) return list;
    return _skills.values
        .where((s) => s.heroId == 'george')
        .toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
  }

  SkillAssetConfig? getSkillForHeroSlot(String heroId, int slot) {
    final hero = _heroes[heroId];
    if (hero == null || slot < 1 || slot > hero.skillIds.length) return null;

    final skillId = hero.skillIds[slot - 1];
    final skill = _skills[skillId];
    if (skill != null && skill.heroId == heroId && skill.slot == slot) {
      return skill;
    }

    // Some legacy heroes do not yet have complete skill JSON entries. Keep their
    // existing runtime values rather than borrowing a different hero's config.
    return null;
  }

  CompanionAssetConfig? getCompanion(String? companionId) {
    if (companionId == null) return null;
    return _companions[companionId];
  }

  MapAssetConfig getMapForStage(int stage) {
    for (final m in _maps.values) {
      if (m.mode == 'pve' && m.stage == stage) return m;
    }
    return _maps['sunken_golden_sanctum']!;
  }

  /// Nạp toàn bộ file cấu hình từ `assets/data/*.json`
  Future<void> initialize({AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    try {
      await _loadHeroesJson(assetBundle);
      await _loadSkillsJson(assetBundle);
      await _loadCompanionsJson(assetBundle);
      await _loadMapsJson(assetBundle);
      await _loadEnemiesJson(assetBundle);
      _initialized = true;
    } catch (e) {
      debugPrint('GameAssetRegistry: dùng cấu hình mặc định do lỗi đọc JSON: $e');
      _seedFallbackDefaults();
      _initialized = true;
    }
  }

  /// Cho phép đăng ký nhanh nhân vật tùy chỉnh lúc runtime hoặc test
  void registerCustomHero(HeroAssetConfig hero) {
    _heroes[hero.id] = hero;
  }

  void registerCustomCompanion(CompanionAssetConfig companion) {
    _companions[companion.id] = companion;
  }

  void registerCustomMap(MapAssetConfig mapConfig) {
    _maps[mapConfig.id] = mapConfig;
  }

  Future<void> _loadHeroesJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/heroes.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['heroes'] as List<dynamic>? ?? const [];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cfg = HeroAssetConfig.fromJson(item);
        _heroes[cfg.id] = cfg;
      }
    }
  }

  Future<void> _loadSkillsJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/skills.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['skills'] as List<dynamic>? ?? const [];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cfg = SkillAssetConfig.fromJson(item);
        _skills[cfg.id] = cfg;
      }
    }
  }

  Future<void> _loadCompanionsJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/companions.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['companions'] as List<dynamic>? ?? const [];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cfg = CompanionAssetConfig.fromJson(item);
        _companions[cfg.id] = cfg;
      }
    }
  }

  Future<void> _loadMapsJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/maps.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['maps'] as List<dynamic>? ?? const [];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cfg = MapAssetConfig.fromJson(item);
        _maps[cfg.id] = cfg;
      }
    }
  }

  Future<void> _loadEnemiesJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/enemies.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['enemies'] as List<dynamic>? ?? const [];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        final cfg = EnemyAssetConfig.fromJson(item);
        _enemies[cfg.id] = cfg;
      }
    }
  }

  void _seedFallbackDefaults() {
    final defaultHeroes = <HeroAssetConfig>[
      const HeroAssetConfig(
        id: 'george',
        name: 'George — Chiến Thần Búa Tạ',
        role: 'Đấu Sĩ / Cận Chiến',
        classType: 'warrior',
        priceGold: 0,
        unlockedByDefault: true,
        baseStats: HeroBaseStatsConfig(hp: 100, ki: 100, attack: 25, speed: 150),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 14.0,
          kiPerLevel: 3.5,
          attackPerLevel: 2.2,
        ),
        skillIds: ['george_hurricane', 'george_earth_smash', 'george_berserk'],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/george_idle.png',
          runSheet: 'assets/images/heroes/Tien-run-trimmed.png',
          attackSheet: 'assets/images/heroes/george_attack.png',
          skill1Sheet: 'assets/images/heroes/Tien-asm_hammer_hammer_hurricane.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'kaelen',
        name: 'Kaelen — Kiếm Khách Lôi Quang',
        role: 'Sát Thủ / Đấu Sĩ Cơ Động',
        classType: 'assassin',
        priceGold: 5000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 110, ki: 120, attack: 32, speed: 175),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 11.5,
          kiPerLevel: 4.5,
          attackPerLevel: 3.0,
        ),
        skillIds: [
          'kaelen_thunder_flash',
          'kaelen_storm_vortex',
          'kaelen_heaven_judgment',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/kaelen/kaelen_portrait.png',
          runSheet: 'assets/images/heroes/kaelen/kaelen_sheet.png',
          attackSheet: 'assets/images/heroes/kaelen/kaelen_attack.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'ranger',
        name: 'Lyra — Xạ Thủ Tinh Anh',
        role: 'Xạ Thủ / Tầm Xa',
        classType: 'marksman',
        priceGold: 3000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 90, ki: 115, attack: 30, speed: 165),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 10.0,
          kiPerLevel: 4.2,
          attackPerLevel: 3.1,
        ),
        skillIds: ['ranger_multishot', 'ranger_trap_roll', 'ranger_star_rain'],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/ranger_idle.png',
          runSheet: 'assets/images/heroes/ranger_run.png',
          attackSheet: 'assets/images/heroes/ranger_attack.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'tanker',
        name: 'Braum — Hiệp Sĩ Khiên Thép',
        role: 'Đỡ Đòn / Khống Chế',
        classType: 'tank',
        priceGold: 4000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 145, ki: 95, attack: 22, speed: 140),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 20.0,
          kiPerLevel: 3.0,
          attackPerLevel: 1.8,
        ),
        skillIds: [
          'tanker_shield_bash',
          'tanker_iron_fortress',
          'tanker_earthquake',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/tanker_idle.png',
          runSheet: 'assets/images/heroes/tanker_run.png',
          attackSheet: 'assets/images/heroes/tanker_attack.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'ninja',
        name: 'Hayate — Ảnh Vũ Sát Thủ',
        role: 'Sát Thủ / Bạo Kích',
        classType: 'assassin',
        priceGold: 6000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 95, ki: 110, attack: 34, speed: 180),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 10.5,
          kiPerLevel: 4.0,
          attackPerLevel: 3.3,
        ),
        skillIds: [
          'ninja_shuriken_dash',
          'ninja_smoke_veil',
          'ninja_shadow_execution',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/ninja_idle.png',
          runSheet: 'assets/images/heroes/ninja_run.png',
          attackSheet: 'assets/images/heroes/ninja_attack.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'valeria',
        name: 'Valeria — Nữ Hoàng Băng Giá',
        role: 'Pháp Sư / Khống Chế',
        classType: 'mage',
        priceGold: 7500,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 95, ki: 140, attack: 31, speed: 155),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 11.0,
          kiPerLevel: 5.5,
          attackPerLevel: 2.9,
        ),
        skillIds: [
          'valeria_frost_lance',
          'valeria_blizzard_ring',
          'valeria_absolute_zero',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/valenria/valeria_portrait.png',
          runSheet: 'assets/images/heroes/valenria/valeria_sheet.png',
          attackSheet: 'assets/images/heroes/valenria/valeria_attack.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'garrick',
        name: 'Garrick — Pháo Thủ Hơi Nước',
        role: 'Xạ Thủ Hạng Nặng',
        classType: 'marksman',
        priceGold: 8500,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 115, ki: 110, attack: 33, speed: 150),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 13.5,
          kiPerLevel: 3.8,
          attackPerLevel: 3.0,
        ),
        skillIds: [
          'garrick_napalm_shot',
          'garrick_overclock_turret',
          'garrick_orbital_barrage',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/garrick/garrick_portrait.png',
          runSheet: 'assets/images/heroes/garrick/garrick_sheet.png',
          attackSheet: 'assets/images/heroes/garrick/garrick_attack.png',
        ),
      ),
    ];

    for (final h in defaultHeroes) {
      _heroes[h.id] = h;
    }

    _maps['sunken_golden_sanctum'] = const MapAssetConfig(
      id: 'sunken_golden_sanctum',
      stage: 1,
      name: 'Phế Tích Thần Điện Hoàng Kim',
      mode: 'pve',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [
        [5, 5],
        [34, 5],
        [5, 22],
        [34, 22],
      ],
      buffNodes: [
        [20, 4],
        [10, 14],
        [30, 14],
      ],
      tilesetImage: 'assets/images/maps/sanctum_tileset.png',
      tiledMapFile: 'assets/images/maps/sunken_golden_sanctum.json',
    );
  }
}
