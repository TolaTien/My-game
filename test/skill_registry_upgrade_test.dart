import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/registry/asset_registry.dart';

class _CatalogBundle extends CachingAssetBundle {
  final Map<String, dynamic> heroes;
  final Map<String, dynamic> skills;
  final bool failEnemies;

  _CatalogBundle(this.heroes, this.skills, {this.failEnemies = false});

  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (key == 'assets/data/heroes.json') {
      return Future.value(jsonEncode(heroes));
    }
    if (key == 'assets/data/skills.json') {
      return Future.value(jsonEncode(skills));
    }
    if (failEnemies && key == 'assets/data/enemies.json') {
      throw StateError('Simulated unrelated catalog failure');
    }
    return rootBundle.loadString(key, cache: cache);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> heroJson;
  late Map<String, dynamic> skillJson;
  late List<HeroAssetConfig> heroes;
  late List<SkillAssetConfig> skills;

  Map<String, dynamic> copy(Map<String, dynamic> source) =>
      jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

  void validate(Map<String, dynamic> heroData, Map<String, dynamic> skillData) {
    GameAssetRegistry.validateSkillData(
      heroes: (heroData['heroes'] as List).map(
        (h) => HeroAssetConfig.fromJson(h as Map<String, dynamic>),
      ),
      skills: (skillData['skills'] as List).map(
        (s) => SkillAssetConfig.fromJson(s as Map<String, dynamic>),
      ),
    );
  }

  setUpAll(() async {
    heroJson = jsonDecode(
      await rootBundle.loadString('assets/data/heroes.json'),
    ) as Map<String, dynamic>;
    skillJson = jsonDecode(
      await rootBundle.loadString('assets/data/skills.json'),
    ) as Map<String, dynamic>;
    heroes = (heroJson['heroes'] as List)
        .map((h) => HeroAssetConfig.fromJson(h as Map<String, dynamic>))
        .toList();
    skills = (skillJson['skills'] as List)
        .map((s) => SkillAssetConfig.fromJson(s as Map<String, dynamic>))
        .toList();
  });

  test(
    'actual bundled catalog has 10 heroes and 30 owned unique slots',
    () async {
      expect(heroes, hasLength(10));
      expect(skills, hasLength(30));
      validate(heroJson, skillJson);
      final registry = GameAssetRegistry.forTesting();
      await registry.initialize();
      expect(registry.isInitialized, isTrue);
      expect(registry.skills, hasLength(30));
      for (final hero in heroes) {
        final configured = registry.getSkillsForHero(hero.id);
        expect(configured.map((s) => s.id), orderedEquals(hero.skillIds));
        expect(configured.map((s) => s.slot), orderedEquals([1, 2, 3]));
        for (var slot = 1; slot <= 3; slot++) {
          final skill = registry.getSkillForHeroSlot(hero.id, slot)!;
          expect(skill.heroId, hero.id);
          expect(skill.id, hero.skillIds[slot - 1]);
        }
      }
      expect(registry.getSkillForHeroSlot('unknown', 1), isNull);
      expect(registry.getSkillForHeroSlot('george', 0), isNull);
      expect(registry.getSkillForHeroSlot('george', 4), isNull);
      expect(registry.getSkillsForHero('unknown'), isEmpty);
    },
  );

  test('original 21 root numeric values are unchanged', () {
    // Snapshot from the working JSON before this migration, not old runtime.
    const original = <String, List<num>>{
      'nova_energy_slash': [1, 4, 20, 1.2, 80],
      'nova_shadow_dash': [2, 8, 30, 1.5, 120],
      'nova_quantum_burst': [3, 12, 50, 2, 200],
      'shadow_plasma_shot': [1, 4.5, 20, 1.6, 140],
      'shadow_cyber_spin': [2, 8, 35, 2.2, 110],
      'shadow_phantom_dash': [3, 12, 50, 3.2, 170],
      'ember_fireball': [1, 4, 20, 1.7, 130],
      'ember_flame_pillar': [2, 8, 35, 2.4, 115],
      'ember_supernova': [3, 12, 50, 3.5, 180],
      'valeria_frost_fire_slash': [1, 5, 25, 1.9, 150],
      'valeria_elemental_vortex': [2, 9, 40, 2.6, 110],
      'valeria_ice_meteor': [3, 14, 60, 3.6, 180],
      'garrick_landslide': [1, 5, 20, 1.85, 130],
      'garrick_golden_aegis': [2, 9, 35, 2.3, 115],
      'garrick_earth_shatter': [3, 14, 50, 3.5, 175],
      'kaelen_thunder_flash': [1, 5, 30, 1.8, 180],
      'kaelen_storm_vortex': [2, 10, 55, 4.5, 85],
      'kaelen_heaven_judgment': [3, 18, 90, 3.5, 160],
      'george_hurricane': [1, 5, 20, 1.8, 80],
      'george_earth_smash': [2, 8, 35, 2.5, 120],
      'george_berserk': [3, 12, 50, 3.5, 160],
    };
    for (final entry in original.entries) {
      final skill = skills.singleWhere((s) => s.id == entry.key);
      expect(
        [
          skill.slot,
          skill.cooldown,
          skill.kiCost,
          skill.damageMultiplier,
          skill.radius,
        ],
        entry.value,
        reason: entry.key,
      );
    }
    for (final heroId in ['ranger', 'tanker', 'ninja']) {
      for (final skill in skills.where((s) => s.heroId == heroId)) {
        final legacy = SkillAssetConfig.legacy(heroId, skill.slot);
        expect(skill.cooldown, legacy.cooldown);
        expect(skill.kiCost, legacy.kiCost);
        expect(skill.damageMultiplier, legacy.damageMultiplier);
        expect(skill.radius, legacy.radius);
        expect(
          (skillJson['skills'] as List).singleWhere(
            (s) => s['id'] == skill.id,
          )['effects'],
          isA<Map<String, dynamic>>(),
        );
      }
    }
  });

  test(
    'all explicit effects match delivery and duration migration contracts',
    () {
      SkillAssetConfig skill(String id) =>
          skills.singleWhere((s) => s.id == id);
      for (final raw in skillJson['skills'] as List) {
        expect(raw['effects'], isA<Map<String, dynamic>>());
      }
      for (final id in [
        'nova_energy_slash',
        'shadow_plasma_shot',
        'ember_fireball',
        'valeria_frost_fire_slash',
        'garrick_landslide',
        'ranger_multishot',
      ]) {
        expect(skill(id).effects.delivery, SkillDelivery.projectile);
      }
      expect(skill('shadow_plasma_shot').effects.piercing, isTrue);
      expect(skill('valeria_frost_fire_slash').effects.piercing, isTrue);
      expect(skill('garrick_landslide').effects.piercing, isFalse);
      for (final s in skills.where(
        (s) => s.effects.delivery == SkillDelivery.dash,
      )) {
        expect(s.effects.dashDistance, s.radius);
      }
      expect(skill('kaelen_thunder_flash').effects.stunDuration, 0.5);
      final kaelenUlt = skill('kaelen_heaven_judgment').effects;
      expect(kaelenUlt.stunDuration, 1.5);
      expect(kaelenUlt.invulnerabilityDuration, 0.6);
      for (final s in skills.where((s) => s.slot == 3)) {
        expect(s.effects.damageReduction, 0.4);
        expect(s.effects.moveSpeedMultiplier, 1.5);
        expect(s.effects.duration, s.heroId == 'george' ? 5 : 8);
        expect(s.effects.attackMultiplier, s.heroId == 'george' ? 1.6 : 1);
      }
      final kaelenVortex = skill('kaelen_storm_vortex').effects;
      expect(kaelenVortex.duration, 4);
      expect(kaelenVortex.tickInterval, 0.5);
      expect(kaelenVortex.moveSpeedMultiplier, 1.25);
      expect(kaelenVortex.damageReduction, 0.3);
      final valeriaVortex = skill('valeria_elemental_vortex').effects;
      expect(valeriaVortex.duration, 8);
      expect(valeriaVortex.tickInterval, 0.5);
    },
  );

  test(
    'new configs reuse assets available through the real root bundle',
    () async {
      for (final s in skills.where(
        (s) => const {'ranger', 'tanker', 'ninja'}.contains(s.heroId),
      )) {
        expect(
          (await rootBundle.load(s.iconAsset)).lengthInBytes,
          greaterThan(0),
        );
        expect(
          (await rootBundle.load('assets/audio/${s.sfxAsset}')).lengthInBytes,
          greaterThan(0),
        );
      }
    },
  );

  test('legacy factory preserves explicit PvE/PvP compatibility values', () {
    for (final heroId in heroes.map((h) => h.id)) {
      for (var slot = 1; slot <= 3; slot++) {
        final pve = SkillAssetConfig.legacy(heroId, slot);
        final pvp = SkillAssetConfig.legacy(heroId, slot, pvp: true);
        expect(pve.kiCost, [25, 35, 40][slot - 1]);
        expect(pve.cooldown, [5, 8, 12][slot - 1]);
        expect(pve.damageMultiplier, [1.8, 2.5, 2.5][slot - 1]);
        expect(pvp.damageMultiplier, [1.8, 2.5, 2.2][slot - 1]);
        expect(pve.radius, [85, 110, 160][slot - 1]);
        expect(pvp.radius, [85, 110, 140][slot - 1]);
        expect(pve.effects.attackMultiplier, 1);
        expect(
          pve.sfxAsset,
          [
            'sfx_skill_hurricane.wav',
            'sfx_skill_smash.wav',
            'sfx_skill_berserk.wav',
          ][slot - 1],
        );
        expect(pvp.sfxAsset, pve.sfxAsset);
        if (slot == 3) {
          final self = const {
            'george',
            'ranger',
            'tanker',
            'ninja',
          }.contains(heroId);
          expect(
            pve.effects.delivery,
            self ? SkillDelivery.self : SkillDelivery.area,
          );
          expect(pve.effects.duration, 8);
          expect(pve.effects.moveSpeedMultiplier, 1.5);
          expect(pve.effects.damageReduction, 0.4);
        }
      }
    }
    expect(() => SkillAssetConfig.legacy('george', 0), throwsRangeError);
    expect(() => SkillAssetConfig.legacy('george', 4), throwsRangeError);
    const defaults = SkillEffects();
    expect(defaults.delivery, SkillDelivery.area);
    expect(defaults.duration, 0);
    expect(defaults.tickInterval, 0);
    expect(defaults.dashDistance, 0);
    expect(defaults.piercing, isFalse);
    expect(defaults.knockback, 0);
    expect(defaults.stunDuration, 0);
    expect(defaults.moveSpeedMultiplier, 1);
    expect(defaults.attackMultiplier, 1);
    expect(defaults.damageReduction, 0);
    expect(defaults.invulnerabilityDuration, 0);
  });

  test('duplicate IDs, slots, and hero references are rejected', () {
    final duplicateId = copy(skillJson);
    (duplicateId['skills'] as List).add(copy(duplicateId['skills'][0]));
    expect(() => validate(heroJson, duplicateId), throwsFormatException);

    final duplicateSlot = copy(skillJson);
    duplicateSlot['skills'][1]['slot'] = 1;
    expect(() => validate(heroJson, duplicateSlot), throwsFormatException);

    final duplicateHero = copy(heroJson);
    (duplicateHero['heroes'] as List).add(copy(duplicateHero['heroes'][0]));
    expect(() => validate(duplicateHero, skillJson), throwsFormatException);

    final duplicateRef = copy(heroJson);
    duplicateRef['heroes'][0]['skillIds'][1] = 'george_hurricane';
    expect(() => validate(duplicateRef, skillJson), throwsFormatException);
  });

  test('missing, misowned, reordered, and orphan references are rejected', () {
    final missing = copy(skillJson);
    (missing['skills'] as List).removeAt(0);
    expect(() => validate(heroJson, missing), throwsFormatException);

    final owner = copy(skillJson);
    owner['skills'][0]['heroId'] = 'unknown';
    expect(() => validate(heroJson, owner), throwsFormatException);

    final reordered = copy(heroJson);
    final refs = reordered['heroes'][0]['skillIds'] as List;
    final first = refs[0];
    refs[0] = refs[1];
    refs[1] = first;
    expect(() => validate(reordered, skillJson), throwsFormatException);

    final tooFew = copy(heroJson);
    (tooFew['heroes'][0]['skillIds'] as List).removeLast();
    expect(() => validate(tooFew, skillJson), throwsFormatException);

    expect(
      () => GameAssetRegistry.validateSkillData(
        heroes: heroes.skip(1),
        skills: skills,
      ),
      throwsFormatException,
    );
    expect(
      () => GameAssetRegistry.validateSkillData(
        heroes: const [],
        skills: const [],
      ),
      throwsFormatException,
    );
  });

  test('malformed root numbers and unknown delivery fail closed', () {
    for (final key in [
      'cooldown',
      'kiCost',
      'damageMultiplier',
      'radius',
      'slot',
    ]) {
      for (final value in [-1, double.nan, double.infinity, '5', null]) {
        final raw = copy(skillJson['skills'][0]);
        raw[key] = value;
        expect(
          () => SkillAssetConfig.fromJson(raw),
          throwsFormatException,
          reason: '$key=$value',
        );
      }
    }
    for (final slot in [0, 4, 1.5]) {
      final raw = copy(skillJson['skills'][0])..['slot'] = slot;
      expect(() => SkillAssetConfig.fromJson(raw), throwsFormatException);
    }
    final unknown = copy(skillJson['skills'][0]);
    unknown['effects']['delivery'] = 'typo-projectile';
    expect(() => SkillAssetConfig.fromJson(unknown), throwsFormatException);
    unknown['effects'] = [];
    expect(() => SkillAssetConfig.fromJson(unknown), throwsFormatException);
  });

  test(
    'effect numeric and timing constraints reject invalid configurations',
    () {
      for (final key in [
        'duration',
        'tickInterval',
        'dashDistance',
        'knockback',
        'stunDuration',
        'moveSpeedMultiplier',
        'attackMultiplier',
        'damageReduction',
        'invulnerabilityDuration',
      ]) {
        for (final value in [-1, double.nan, double.infinity, '1', null]) {
          expect(
            () => SkillEffects.fromJson({key: value}),
            throwsFormatException,
            reason: '$key=$value',
          );
        }
      }
      for (final raw in <Map<String, dynamic>>[
        {'delivery': 'dash'},
        {'damageReduction': 1.1, 'duration': 8},
        {'moveSpeedMultiplier': 0},
        {'attackMultiplier': 0},
        {'attackMultiplier': 1.5},
        {'tickInterval': 0.5},
        {'duration': 1, 'tickInterval': 2},
        {'piercing': 'true'},
        {'piercing': null},
        {'delivery': null},
      ]) {
        expect(() => SkillEffects.fromJson(raw), throwsFormatException);
      }
      expect(
        () => GameAssetRegistry.validateSkillData(
          heroes: heroes,
          skills: [
            ...skills.skip(1),
            SkillAssetConfig(
              id: skills.first.id,
              heroId: skills.first.heroId,
              slot: 1,
              name: '',
              description: '',
              cooldown: double.nan,
              kiCost: 0,
              damageMultiplier: 1,
              radius: 80,
              iconAsset: '',
              sfxAsset: '',
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  test('known heroes without configs never silently borrow George', () async {
    final registry = GameAssetRegistry.forTesting();
    await registry.initialize();
    final raw = copy(heroJson['heroes'][0]);
    raw['id'] = 'custom';
    raw['skillIds'] = ['missing1', 'missing2', 'missing3'];
    registry.registerCustomHero(HeroAssetConfig.fromJson(raw));
    expect(registry.getSkillsForHero('custom'), isEmpty);
    expect(registry.getSkillForHeroSlot('custom', 1), isNull);
    raw['id'] = 'george';
    raw['skillIds'] = [
      'george_hurricane',
      'george_hurricane',
      'george_berserk',
    ];
    registry.registerCustomHero(HeroAssetConfig.fromJson(raw));
    expect(registry.getSkillsForHero('george'), isEmpty);
  });

  test(
    'invalid load does not partially apply hero/skill catalogs or erase custom',
    () async {
      final registry = GameAssetRegistry.forTesting();
      final customRaw = copy(heroJson['heroes'][0])..['id'] = 'custom';
      registry.registerCustomHero(HeroAssetConfig.fromJson(customRaw));
      final broken = copy(skillJson);
      (broken['skills'] as List).removeAt(0);
      await registry.initialize(bundle: _CatalogBundle(heroJson, broken));
      expect(registry.isInitialized, isFalse);
      expect(registry.skills, isEmpty);
      expect(registry.heroes.any((h) => h.id == 'nova_blade'), isFalse);
      expect(registry.heroes.any((h) => h.id == 'custom'), isTrue);

      await registry.initialize();
      expect(registry.isInitialized, isTrue);
      expect(registry.heroes.any((h) => h.id == 'custom'), isTrue);
      final originalGeorge = registry.getHero('george');
      final changedHeroes = copy(heroJson);
      changedHeroes['heroes'][0]['name'] = 'Must not partially apply';
      await registry.initialize(
        bundle: _CatalogBundle(changedHeroes, skillJson, failEnemies: true),
      );
      expect(registry.isInitialized, isFalse);
      expect(registry.getHero('george'), same(originalGeorge));
      expect(registry.skills, hasLength(30));
      expect(registry.getSkillForHeroSlot('nova_blade', 1)!.kiCost, 20);
    },
  );

  test(
    'valid reload replaces stale skill IDs without duplicate slot candidates',
    () async {
      final registry = GameAssetRegistry.forTesting();
      await registry.initialize();
      final updatedHeroes = copy(heroJson);
      final updatedSkills = copy(skillJson);
      final nova = (updatedHeroes['heroes'] as List).singleWhere(
        (h) => h['id'] == 'nova_blade',
      );
      nova['skillIds'][0] = 'nova_energy_slash_v2';
      updatedSkills['skills'][0]['id'] = 'nova_energy_slash_v2';
      await registry.initialize(
        bundle: _CatalogBundle(updatedHeroes, updatedSkills),
      );
      expect(registry.isInitialized, isTrue);
      expect(registry.skills, hasLength(30));
      expect(registry.skills.any((s) => s.id == 'nova_energy_slash'), isFalse);
      expect(
        registry.getSkillForHeroSlot('nova_blade', 1)!.id,
        'nova_energy_slash_v2',
      );
    },
  );
}
