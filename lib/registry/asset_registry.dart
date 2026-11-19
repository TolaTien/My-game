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
      skillIds:
          (json['skillIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sprites: HeroSpriteConfig.fromJson(
        (json['sprites'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

enum SkillDelivery { area, projectile, dash, self }

@immutable
class SkillEffects {
  final SkillDelivery delivery;
  final double duration;
  final double tickInterval;
  final double dashDistance;
  final bool piercing;
  final double knockback;
  final double stunDuration;
  final double moveSpeedMultiplier;
  final double attackMultiplier;
  final double damageReduction;
  final double invulnerabilityDuration;

  const SkillEffects({
    this.delivery = SkillDelivery.area,
    this.duration = 0,
    this.tickInterval = 0,
    this.dashDistance = 0,
    this.piercing = false,
    this.knockback = 0,
    this.stunDuration = 0,
    this.moveSpeedMultiplier = 1,
    this.attackMultiplier = 1,
    this.damageReduction = 0,
    this.invulnerabilityDuration = 0,
  });

  factory SkillEffects.fromJson(Map<String, dynamic> json) {
    final rawDelivery = json.containsKey('delivery')
        ? json['delivery']
        : 'area';
    final delivery = SkillDelivery.values.where((d) => d.name == rawDelivery);
    if (delivery.isEmpty) {
      throw FormatException('Unknown skill delivery: $rawDelivery');
    }
    final piercing = json.containsKey('piercing') ? json['piercing'] : false;
    if (piercing is! bool) {
      throw const FormatException('Skill piercing must be a boolean');
    }
    final effects = SkillEffects(
      delivery: delivery.single,
      duration: _skillNumber(json, 'duration', fallback: 0),
      tickInterval: _skillNumber(json, 'tickInterval', fallback: 0),
      dashDistance: _skillNumber(json, 'dashDistance', fallback: 0),
      piercing: piercing,
      knockback: _skillNumber(json, 'knockback', fallback: 0),
      stunDuration: _skillNumber(json, 'stunDuration', fallback: 0),
      moveSpeedMultiplier: _skillNumber(
        json,
        'moveSpeedMultiplier',
        fallback: 1,
      ),
      attackMultiplier: _skillNumber(json, 'attackMultiplier', fallback: 1),
      damageReduction: _skillNumber(json, 'damageReduction', fallback: 0),
      invulnerabilityDuration: _skillNumber(
        json,
        'invulnerabilityDuration',
        fallback: 0,
      ),
    );
    effects.validate();
    return effects;
  }

  void validate() {
    for (final value in [
      duration,
      tickInterval,
      dashDistance,
      knockback,
      stunDuration,
      moveSpeedMultiplier,
      attackMultiplier,
      damageReduction,
      invulnerabilityDuration,
    ]) {
      if (!value.isFinite || value < 0) {
        throw const FormatException(
          'Skill effects must be finite and nonnegative',
        );
      }
    }
    if (damageReduction > 1 ||
        moveSpeedMultiplier <= 0 ||
        attackMultiplier <= 0) {
      throw const FormatException('Invalid skill modifier');
    }
    if (tickInterval > 0 && (duration <= 0 || tickInterval > duration)) {
      throw const FormatException('Skill ticks require a sufficient duration');
    }
    if (delivery == SkillDelivery.dash && dashDistance <= 0) {
      throw const FormatException('Dash delivery requires a positive distance');
    }
    if ((moveSpeedMultiplier != 1 ||
            attackMultiplier != 1 ||
            damageReduction > 0) &&
        duration <= 0) {
      throw const FormatException('Timed skill modifiers require a duration');
    }
  }
}

double _skillNumber(Map<String, dynamic> json, String key, {double? fallback}) {
  final raw = json[key];
  if (raw == null && !json.containsKey(key) && fallback != null) {
    return fallback;
  }
  if (raw is! num || !raw.isFinite || raw < 0) {
    throw FormatException('Skill $key must be a finite nonnegative number');
  }
  return raw.toDouble();
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
  final SkillEffects effects;

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
    this.effects = const SkillEffects(),
  });

  factory SkillAssetConfig.fromJson(Map<String, dynamic> json) {
    final slot = _skillNumber(json, 'slot');
    if (slot != slot.roundToDouble()) {
      throw const FormatException('Skill slot must be an integer');
    }
    final rawEffects = json['effects'];
    if (json.containsKey('effects') && rawEffects is! Map<String, dynamic>) {
      throw const FormatException('Skill effects must be an object');
    }
    final skill = SkillAssetConfig(
      id: json['id'] as String? ?? '',
      heroId: json['heroId'] as String? ?? '',
      slot: slot.toInt(),
      name: json['name'] as String? ?? 'Kỹ năng',
      description: json['description'] as String? ?? '',
      cooldown: _skillNumber(json, 'cooldown'),
      kiCost: _skillNumber(json, 'kiCost'),
      damageMultiplier: _skillNumber(json, 'damageMultiplier'),
      radius: _skillNumber(json, 'radius'),
      iconAsset: json['iconAsset'] as String? ?? '',
      sfxAsset: json['sfxAsset'] as String? ?? '',
      effects: rawEffects == null
          ? const SkillEffects()
          : SkillEffects.fromJson(rawEffects as Map<String, dynamic>),
    );
    skill.validate();
    return skill;
  }

  /// Explicit compatibility contract, never the primary loaded PvE config.
  factory SkillAssetConfig.legacy(String heroId, int slot, {bool pvp = false}) {
    if (slot < 1 || slot > 3) throw RangeError.range(slot, 1, 3, 'slot');
    final selfUltimate =
        slot == 3 &&
        const {'george', 'ranger', 'tanker', 'ninja'}.contains(heroId);
    return SkillAssetConfig(
      id: '${heroId}_legacy_$slot',
      heroId: heroId,
      slot: slot,
      name: 'Skill $slot',
      description: 'Legacy runtime compatibility fallback',
      cooldown: const [5.0, 8.0, 12.0][slot - 1],
      kiCost: const [25.0, 35.0, 40.0][slot - 1],
      damageMultiplier: slot == 1 ? 1.8 : (slot == 2 ? 2.5 : (pvp ? 2.2 : 2.5)),
      radius: slot == 1 ? 85 : (slot == 2 ? 110 : (pvp ? 140 : 160)),
      iconAsset: '',
      sfxAsset: const [
        'sfx_skill_hurricane.wav',
        'sfx_skill_smash.wav',
        'sfx_skill_berserk.wav',
      ][slot - 1],
      effects: slot == 3
          ? SkillEffects(
              delivery: selfUltimate ? SkillDelivery.self : SkillDelivery.area,
              duration: 8,
              moveSpeedMultiplier: 1.5,
              damageReduction: 0.4,
            )
          : const SkillEffects(),
    );
  }

  void validate() {
    if (id.trim().isEmpty || heroId.trim().isEmpty || slot < 1 || slot > 3) {
      throw const FormatException('Skill requires ID, owner and slot 1..3');
    }
    for (final value in [cooldown, kiCost, damageMultiplier, radius]) {
      if (!value.isFinite || value < 0) {
        throw const FormatException(
          'Skill numbers must be finite and nonnegative',
        );
      }
    }
    effects.validate();
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
      autoAttackInterval:
          (json['autoAttackInterval'] as num?)?.toDouble() ?? 1.2,
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
      imageAsset: json['imageAsset'] as String? ?? '',
      theme:
          json['theme'] as String? ?? json['id'] as String? ?? 'golden_sanctum',
      description: json['description'] as String? ?? '',
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

/// Data-driven asset registry for heroes, skills, companions, maps and enemies.
class GameAssetRegistry {
  GameAssetRegistry._() {
    _seedFallbackDefaults();
  }

  static final GameAssetRegistry instance = GameAssetRegistry._();

  @visibleForTesting
  GameAssetRegistry.forTesting() : this._();

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

  static String canonicalHeroId(String heroId) => switch (heroId) {
    'nova' => 'nova_blade',
    'ember' => 'ember_02',
    'shadow' => 'shadow_01',
    _ => heroId,
  };

  HeroAssetConfig getHero(String heroId) =>
      _heroes[canonicalHeroId(heroId)] ?? _heroes['george']!;

  List<SkillAssetConfig> getSkillsForHero(String heroId) {
    return [
      for (var slot = 1; slot <= 3; slot++) ?getSkillForHeroSlot(heroId, slot),
    ];
  }

  SkillAssetConfig? getSkillForHeroSlot(String heroId, int slot) {
    heroId = canonicalHeroId(heroId);
    final hero = _heroes[heroId];
    if (hero == null ||
        slot < 1 ||
        slot > 3 ||
        hero.skillIds.length != 3 ||
        hero.skillIds.toSet().length != 3) {
      return null;
    }

    final skillId = hero.skillIds[slot - 1];
    final skill = _skills[skillId];
    if (skill != null && skill.heroId == heroId && skill.slot == slot) {
      if (_skills.values
              .where((s) => s.heroId == heroId && s.slot == slot)
              .length !=
          1) {
        return null;
      }
      try {
        skill.validate();
      } on FormatException {
        return null;
      }
      return skill;
    }

    // Callers must deliberately choose legacy fallback, never another hero.
    return null;
  }

  CompanionAssetConfig? getCompanion(String? companionId) {
    if (companionId == null) return null;
    return _companions[companionId];
  }

  MapAssetConfig? getMap(String id) => _maps[id];

  List<MapAssetConfig> get availableMatchMaps => [
    _maps[defaultSanctumMap.id] ?? defaultSanctumMap,
    _maps[defaultFrostArenaMap.id] ?? defaultFrostArenaMap,
    _maps[defaultFrostIslandMap.id] ?? defaultFrostIslandMap,
    _maps[defaultForestMap.id] ?? defaultForestMap,
  ];

  MapAssetConfig getRandomMap({String? excludeId}) {
    final pool = availableMatchMaps
        .where((map) => map.id != excludeId)
        .toList();
    return pool[Random().nextInt(pool.length)];
  }

  MapAssetConfig getMapFromSeed(String seed) {
    final pool = availableMatchMaps..sort((a, b) => a.id.compareTo(b.id));
    // Keep the original MAIN seed mapping for online room compatibility.
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return pool[hash % pool.length];
  }

  MapAssetConfig getMapForStage(int stage) {
    for (final m in _maps.values) {
      if ((m.mode == 'pve' || m.mode == 'all') && m.stage == stage) return m;
    }
    return _maps[defaultSanctumMap.id] ?? defaultSanctumMap;
  }

  Future<void> initialize({AssetBundle? bundle}) async {
    final assetBundle = bundle ?? rootBundle;
    _initialized = false;
    try {
      final heroes = await _loadHeroesJson(assetBundle);
      final skills = await _loadSkillsJson(assetBundle);
      validateSkillData(heroes: heroes, skills: skills);
      final companions = await _loadCatalog(
        assetBundle,
        'companions',
        CompanionAssetConfig.fromJson,
      );
      final maps = await _loadCatalog(
        assetBundle,
        'maps',
        MapAssetConfig.fromJson,
      );
      final enemies = await _loadCatalog(
        assetBundle,
        'enemies',
        EnemyAssetConfig.fromJson,
      );
      // Publish only after every catalog parses, preserving custom registrations.
      _heroes.addEntries(heroes.map((h) => MapEntry(h.id, h)));
      // Skills have no custom-registration API; remove stale loaded IDs/slots.
      _skills.clear();
      _skills.addEntries(skills.map((s) => MapEntry(s.id, s)));
      _companions.addEntries(companions.map((c) => MapEntry(c.id, c)));
      _maps.addEntries(maps.map((m) => MapEntry(m.id, m)));
      _enemies.addEntries(enemies.map((e) => MapEntry(e.id, e)));
      _initialized = true;
    } catch (e) {
      debugPrint('GameAssetRegistry: giữ cấu hình hiện có do lỗi đọc JSON: $e');
    }
  }

  /// Validates the complete linked catalog before any hero/skill data is applied.
  static void validateSkillData({
    required Iterable<HeroAssetConfig> heroes,
    required Iterable<SkillAssetConfig> skills,
  }) {
    final heroMap = <String, HeroAssetConfig>{};
    final skillMap = <String, SkillAssetConfig>{};
    final slots = <String>{};
    for (final hero in heroes) {
      if (hero.id.trim().isEmpty ||
          heroMap.containsKey(hero.id) ||
          hero.skillIds.length != 3 ||
          hero.skillIds.toSet().length != 3) {
        throw FormatException(
          'Invalid/duplicate hero or skill references: ${hero.id}',
        );
      }
      heroMap[hero.id] = hero;
    }
    for (final skill in skills) {
      skill.validate();
      if (skillMap.containsKey(skill.id) ||
          !slots.add('${skill.heroId}:${skill.slot}')) {
        throw FormatException('Duplicate skill ID/slot: ${skill.id}');
      }
      skillMap[skill.id] = skill;
    }
    if (heroMap.isEmpty || skillMap.isEmpty) {
      throw const FormatException('Hero/skill catalogs must not be empty');
    }
    for (final hero in heroMap.values) {
      for (var slot = 1; slot <= 3; slot++) {
        final skill = skillMap[hero.skillIds[slot - 1]];
        if (skill == null || skill.heroId != hero.id || skill.slot != slot) {
          throw FormatException('Missing/misowned skill: ${hero.id}:$slot');
        }
      }
    }
    for (final skill in skillMap.values) {
      if (!(heroMap[skill.heroId]?.skillIds.contains(skill.id) ?? false)) {
        throw FormatException('Unreferenced skill: ${skill.id}');
      }
    }
  }

  /// Cho phép đăng ký nhanh nhân vật tùy chỉnh lúc runtime hoặc test.
  void registerCustomHero(HeroAssetConfig hero) {
    _heroes[hero.id] = hero;
  }

  void registerCustomCompanion(CompanionAssetConfig companion) {
    _companions[companion.id] = companion;
  }

  void registerCustomMap(MapAssetConfig mapConfig) {
    _maps[mapConfig.id] = mapConfig;
  }

  Future<List<HeroAssetConfig>> _loadHeroesJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/heroes.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['heroes'] as List<dynamic>;
    return list
        .map((item) => HeroAssetConfig.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SkillAssetConfig>> _loadSkillsJson(AssetBundle bundle) async {
    final raw = await bundle.loadString('assets/data/skills.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['skills'] as List<dynamic>;
    return list
        .map((item) => SkillAssetConfig.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<T>> _loadCatalog<T>(
    AssetBundle bundle,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final raw = await bundle.loadString('assets/data/$key.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded[key] as List<dynamic>;
    return list.map((item) => parse(item as Map<String, dynamic>)).toList();
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
        baseStats: HeroBaseStatsConfig(
          hp: 100,
          ki: 100,
          attack: 25,
          speed: 150,
        ),
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
          skill1Sheet:
              'assets/images/heroes/Tien-asm_hammer_hammer_hurricane.png',
        ),
      ),
      const HeroAssetConfig(
        id: 'kaelen',
        name: 'Kaelen — Kiếm Khách Lôi Quang',
        role: 'Sát Thủ / Đấu Sĩ Cơ Động',
        classType: 'assassin',
        priceGold: 5000,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(
          hp: 110,
          ki: 120,
          attack: 32,
          speed: 175,
        ),
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
        baseStats: HeroBaseStatsConfig(
          hp: 115,
          ki: 110,
          attack: 33,
          speed: 150,
        ),
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

    for (final map in availableMatchMaps) {
      _maps[map.id] = map;
    }
  }

  static const defaultSanctumMap = MapAssetConfig(
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
    description: 'Thần điện cổ đại ngập tràn kho báu và linh khí hoàng kim.',
  );

  static const defaultFrostArenaMap = MapAssetConfig(
    id: 'map_bang',
    stage: 7,
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

  static const defaultFrostIslandMap = MapAssetConfig(
    id: 'map_dao_bang_gia',
    stage: 8,
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

  static const defaultForestMap = MapAssetConfig(
    id: 'map_rung_cay',
    stage: 9,
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
