import 'dart:convert';
import 'dart:math';
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
  final String imageAsset;
  final String theme;
  final String description;
  final List<List<int>>? _obstacles;

  List<List<int>> get obstacles => _obstacles ?? const [];

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
    this.imageAsset = '',
    this.theme = 'golden_sanctum',
    this.description = '',
    // ignore: prefer_initializing_formals
    List<List<int>>? obstacles,
  }) : _obstacles = obstacles; // ignore: prefer_initializing_formals

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

    List<List<int>> parseObstacles(dynamic raw) {
      if (raw is List) {
        return raw.map((e) {
          if (e is List) {
            return e.map((n) => (n as num).toInt()).toList(growable: false);
          }
          return <int>[];
        }).where((l) => l.length >= 2).toList(growable: false);
      }
      return const [];
    }

    return MapAssetConfig(
      id: json['id'] as String? ?? 'sunken_golden_sanctum',
      stage: (json['stage'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Phế Tích Hoàng Kim',
      mode: json['mode'] as String? ?? 'pve',
      cols: (json['cols'] as num?)?.toInt() ?? 36,
      rows: (json['rows'] as num?)?.toInt() ?? 24,
      tileSize: (json['tileSize'] as num?)?.toInt() ?? 32,
      playerSpawn: parseCoord(json['playerSpawn'], const [12, 9]),
      bossSpawn: parseCoord(json['bossSpawn'], const [28, 12]),
      monsterPortals: parseCoordList(json['monsterPortals']),
      buffNodes: parseCoordList(json['buffNodes']),
      tilesetImage: json['tilesetImage'] as String? ?? '',
      tiledMapFile: json['tiledMapFile'] as String? ?? '',
      imageAsset: json['imageAsset'] as String? ?? '',
      theme: json['theme'] as String? ?? (json['id'] as String? ?? 'golden_sanctum'),
      description: json['description'] as String? ?? '',
      obstacles: parseObstacles(json['obstacles']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'stage': stage,
        'name': name,
        'mode': mode,
        'cols': cols,
        'rows': rows,
        'tileSize': tileSize,
        'playerSpawn': playerSpawn,
        'bossSpawn': bossSpawn,
        'monsterPortals': monsterPortals,
        'buffNodes': buffNodes,
        if (obstacles.isNotEmpty) 'obstacles': obstacles,
        'tilesetImage': tilesetImage,
        'tiledMapFile': tiledMapFile,
        'imageAsset': imageAsset,
        'theme': theme,
        'description': description,
      };
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
    if (heroId == 'nova') {
      return _heroes['nova'] ?? _heroes['nova_blade'] ?? _heroes['george']!;
    }
    if (heroId == 'shadow') {
      return _heroes['shadow'] ?? _heroes['shadow_01'] ?? _heroes['george']!;
    }
    if (heroId == 'ember') {
      return _heroes['ember'] ?? _heroes['ember_02'] ?? _heroes['george']!;
    }
    return _heroes[heroId] ?? _heroes['george']!;
  }

  List<SkillAssetConfig> getSkillsForHero(String heroId) {
    var effectiveId = heroId;
    if (effectiveId == 'nova') effectiveId = 'nova_blade';
    if (effectiveId == 'shadow') effectiveId = 'shadow_01';
    if (effectiveId == 'ember') effectiveId = 'ember_02';
    final list = _skills.values
        .where((s) => s.heroId == effectiveId)
        .toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    if (list.isNotEmpty) return list;
    return _skills.values
        .where((s) => s.heroId == 'george')
        .toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
  }

  CompanionAssetConfig? getCompanion(String? companionId) {
    if (companionId == null) return null;
    return _companions[companionId];
  }

  MapAssetConfig? getMap(String id) => _maps[id];

  List<MapAssetConfig> get availableMatchMaps {
    if (_maps.isNotEmpty) return _maps.values.toList();
    return const [defaultSanctumMap];
  }

  MapAssetConfig getRandomMap({String? excludeId}) {
    final pool = availableMatchMaps;
    if (pool.length <= 1) return pool.first;
    final candidates = excludeId != null
        ? pool.where((m) => m.id != excludeId).toList()
        : pool;
    final effectivePool = candidates.isNotEmpty ? candidates : pool;
    return effectivePool[Random().nextInt(effectivePool.length)];
  }

  /// Chọn bản đồ đồng bộ tất định theo [seed] (ví dụ `roomId` trong PvP Online).
  /// Dùng FNV-1a 32-bit trên `codeUnits` + sắp xếp theo `id` để mọi nền tảng
  /// (Web, Android, Windows) luôn cho ra cùng 1 bản đồ cho cùng 1 trận đấu.
  MapAssetConfig getMapFromSeed(String seed) {
    final pool = List<MapAssetConfig>.from(availableMatchMaps)
      ..sort((a, b) => a.id.compareTo(b.id));
    if (pool.length <= 1) return pool.first;
    int hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return pool[hash % pool.length];
  }

  MapAssetConfig getMapForStage(int stage) {
    for (final m in _maps.values) {
      if (m.stage == stage) return m;
    }
    return _maps.values.firstOrNull ?? defaultSanctumMap;
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
        baseStats: HeroBaseStatsConfig(hp: 340, ki: 100, attack: 25, speed: 150),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 24.0,
          kiPerLevel: 3.5,
          attackPerLevel: 2.2,
        ),
        skillIds: ['george_hurricane', 'george_earth_smash', 'george_berserk'],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'ranger',
        name: 'Lyra — Xạ Thủ Tinh Anh',
        role: 'Xạ Thủ / Tầm Xa',
        classType: 'marksman',
        priceGold: 3000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 250, ki: 115, attack: 14, speed: 165),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 15.0,
          kiPerLevel: 4.2,
          attackPerLevel: 1.3,
        ),
        skillIds: ['ranger_multishot', 'ranger_trap_roll', 'ranger_star_rain'],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'tanker',
        name: 'Braum — Hiệp Sĩ Khiên Thép',
        role: 'Đỡ Đòn / Khống Chế',
        classType: 'tank',
        priceGold: 4000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 440, ki: 95, attack: 18, speed: 140),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 30.0,
          kiPerLevel: 3.0,
          attackPerLevel: 1.6,
        ),
        skillIds: [
          'tanker_shield_bash',
          'tanker_iron_fortress',
          'tanker_earthquake',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'ninja',
        name: 'Hayate — Ảnh Vũ Sát Thủ',
        role: 'Sát Thủ / Bạo Kích',
        classType: 'assassin',
        priceGold: 6000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 280, ki: 110, attack: 28, speed: 180),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 18.0,
          kiPerLevel: 4.0,
          attackPerLevel: 2.6,
        ),
        skillIds: [
          'ninja_shuriken_dash',
          'ninja_smoke_veil',
          'ninja_shadow_execution',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'valeria',
        name: 'Valeria — Nữ Hoàng Băng Giá',
        role: 'Pháp Sư / Khống Chế',
        classType: 'mage',
        priceGold: 7500,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 260, ki: 150, attack: 15, speed: 160),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 16.0,
          kiPerLevel: 6.0,
          attackPerLevel: 1.4,
        ),
        skillIds: [
          'valeria_frost_lance',
          'valeria_blizzard_ring',
          'valeria_absolute_zero',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'garrick',
        name: 'Garrick — Pháo Thủ Hơi Nước',
        role: 'Xạ Thủ Hạng Nặng',
        classType: 'marksman',
        priceGold: 8500,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 450, ki: 105, attack: 20, speed: 145),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 32.0,
          kiPerLevel: 3.5,
          attackPerLevel: 1.8,
        ),
        skillIds: [
          'garrick_napalm_shot',
          'garrick_overclock_turret',
          'garrick_orbital_barrage',
        ],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'nova_blade',
        name: 'Nova Blade (NOVA-07) — Chiến Binh Neon',
        role: 'Đấu Sĩ / Cơ Động',
        classType: 'warrior',
        priceGold: 1000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 350, ki: 110, attack: 26, speed: 175),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 25.0,
          kiPerLevel: 4.2,
          attackPerLevel: 2.4,
        ),
        skillIds: ['nova_energy_slash', 'nova_shadow_dash', 'nova_quantum_burst'],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'shadow_01',
        name: 'Shadow (SHADOW-01) — Sát Thủ Hư Không',
        role: 'Sát Thủ / Hư Không',
        classType: 'assassin',
        priceGold: 100,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 280, ki: 120, attack: 28, speed: 185),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 18.0,
          kiPerLevel: 4.5,
          attackPerLevel: 2.6,
        ),
        skillIds: ['shadow_plasma_shot', 'shadow_cyber_spin', 'shadow_phantom_dash'],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
      const HeroAssetConfig(
        id: 'ember_02',
        name: 'Ember (EMBER-02) — Phù Thủy Hỏa Cầu',
        role: 'Pháp Sư / Hỏa Lực',
        classType: 'mage',
        priceGold: 100,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(hp: 260, ki: 145, attack: 15, speed: 160),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 16.0,
          kiPerLevel: 5.8,
          attackPerLevel: 1.4,
        ),
        skillIds: ['ember_fireball', 'ember_flame_pillar', 'ember_supernova'],
        sprites: HeroSpriteConfig(
          idleSheet: '',
          runSheet: '',
          attackSheet: '',
        ),
      ),
    ];

    for (final h in defaultHeroes) {
      _heroes[h.id] = h;
    }

    _maps['sunken_golden_sanctum'] = defaultSanctumMap;
    _maps['volcanic_frost_ruins'] = const MapAssetConfig(
      id: 'volcanic_frost_ruins',
      stage: 2,
      name: 'Phế Tích Núi Lửa & Băng Giá',
      mode: 'all',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [[5, 5], [34, 5], [5, 22], [34, 22]],
      buffNodes: [[20, 4], [10, 14], [30, 14]],
      tilesetImage: '',
      tiledMapFile: '',
      imageAsset: '',
      theme: 'volcanic',
      description: 'Vùng phế tích núi lửa đan xen hàn băng cổ xưa.',
    );
    _maps['neon_city'] = const MapAssetConfig(
      id: 'neon_city',
      stage: 3,
      name: 'Neon City — Sci-Fi Dungeon',
      mode: 'all',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [[5, 5], [34, 5], [5, 22], [34, 22]],
      buffNodes: [[20, 4], [10, 14], [30, 14]],
      tilesetImage: '',
      tiledMapFile: '',
      imageAsset: '',
      theme: 'neon',
      description: 'Đô thị tương lai ánh sáng neon rực rỡ.',
    );
    _maps['cyber_factory'] = const MapAssetConfig(
      id: 'cyber_factory',
      stage: 4,
      name: 'Cyber Factory',
      mode: 'all',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [[5, 5], [34, 5], [5, 22], [34, 22]],
      buffNodes: [[20, 4], [10, 14], [30, 14]],
      tilesetImage: '',
      tiledMapFile: '',
      imageAsset: '',
      theme: 'cyber',
      description: 'Nhà máy cơ khí và robot công nghệ cao.',
    );
    _maps['space_station'] = const MapAssetConfig(
      id: 'space_station',
      stage: 5,
      name: 'Space Station',
      mode: 'all',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [[5, 5], [34, 5], [5, 22], [34, 22]],
      buffNodes: [[20, 4], [10, 14], [30, 14]],
      tilesetImage: '',
      tiledMapFile: '',
      imageAsset: '',
      theme: 'space',
      description: 'Trạm không gian ngoài quỹ đạo Trái Đất.',
    );
    _maps['alien_ruins'] = const MapAssetConfig(
      id: 'alien_ruins',
      stage: 6,
      name: 'Alien Ruins',
      mode: 'all',
      cols: 40,
      rows: 28,
      tileSize: 32,
      playerSpawn: [20, 24],
      bossSpawn: [20, 14],
      monsterPortals: [[5, 5], [34, 5], [5, 22], [34, 22]],
      buffNodes: [[20, 4], [10, 14], [30, 14]],
      tilesetImage: '',
      tiledMapFile: '',
      imageAsset: '',
      theme: 'alien',
      description: 'Di tích sinh vật ngoài hành tinh cổ xưa.',
    );
    _maps['map_bang'] = defaultFrostArenaMap;
    _maps['map_dao_bang_gia'] = defaultFrostIslandMap;
    _maps['map_rung_cay'] = defaultForestMap;
  }

  static const MapAssetConfig defaultSanctumMap = MapAssetConfig(
    id: 'sunken_golden_sanctum',
    stage: 1,
    name: 'Phế Tích Thần Điện Hoàng Kim',
    mode: 'all',
    cols: 36,
    rows: 24,
    tileSize: 32,
    playerSpawn: [12, 9],
    bossSpawn: [28, 12],
    monsterPortals: [
      [4, 4],
      [31, 4],
      [4, 19],
      [31, 19],
    ],
    buffNodes: [
      [18, 4],
      [9, 12],
      [27, 12],
    ],
    tilesetImage: '',
    tiledMapFile: '',
    imageAsset: '',
    theme: 'golden_sanctum',
    description: 'Thần điện cổ đại ngập tràn kho báu và linh khí hoàng kim.',
  );

  static const MapAssetConfig defaultFrostArenaMap = MapAssetConfig(
    id: 'map_bang',
    stage: 2,
    name: 'Đấu Trường Băng Giá',
    mode: 'all',
    cols: 36,
    rows: 24,
    tileSize: 32,
    playerSpawn: [12, 9],
    bossSpawn: [28, 12],
    monsterPortals: [
      [4, 4],
      [31, 4],
      [4, 19],
      [31, 19],
    ],
    buffNodes: [
      [18, 4],
      [9, 12],
      [27, 12],
    ],
    tilesetImage: '',
    tiledMapFile: '',
    imageAsset: 'assets/images/maps/map-bang.png',
    theme: 'ice_arena',
    description: 'Chiến trường băng phong vĩnh cửu với các khối tinh thể hàn băng sắc nhọn.',
  );

  static const MapAssetConfig defaultFrostIslandMap = MapAssetConfig(
    id: 'map_dao_bang_gia',
    stage: 3,
    name: 'Đảo Băng Tuyết',
    mode: 'all',
    cols: 36,
    rows: 24,
    tileSize: 32,
    playerSpawn: [13, 11],
    bossSpawn: [24, 11],
    monsterPortals: [
      [6, 4],
      [29, 4],
      [7, 18],
      [28, 18],
    ],
    buffNodes: [
      [18, 5],
      [12, 12],
      [24, 12],
    ],
    tilesetImage: '',
    tiledMapFile: '',
    imageAsset: 'assets/images/maps/map-dao-bang-gia.png',
    theme: 'frost_island',
    description: 'Quần đảo băng trôi tráng lệ giữa vùng biển bắc cực huyền bí.',
  );

  static const MapAssetConfig defaultForestMap = MapAssetConfig(
    id: 'map_rung_cay',
    stage: 4,
    name: 'Rừng Cây Cổ Thụ',
    mode: 'all',
    cols: 36,
    rows: 24,
    tileSize: 32,
    playerSpawn: [12, 10],
    bossSpawn: [24, 12],
    monsterPortals: [
      [4, 4],
      [31, 4],
      [4, 19],
      [31, 19],
    ],
    buffNodes: [
      [18, 4],
      [8, 12],
      [24, 18],
    ],
    tilesetImage: '',
    tiledMapFile: '',
    imageAsset: 'assets/images/maps/map-rung-cay.png',
    theme: 'forest',
    description: 'Khu rừng rậm nguyên sinh với thảm thực vật kỳ ảo và những tán cây cổ thụ ngút ngàn.',
  );
}
