import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

class _MalformedEnemyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/data/enemies.json') return '{';
    return rootBundle.loadString(key, cache: cache);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production data preserves all ten heroes and thirty skill slots',
    () async {
      final registry = GameAssetRegistry.forTesting();
      await registry.initialize();
      expect(registry.isInitialized, isTrue);
      expect(registry.heroes, hasLength(10));
      expect(registry.skills, hasLength(30));
      for (final hero in registry.heroes) {
        final skills = registry.getSkillsForHero(hero.id);
        expect(skills.map((skill) => skill.id), hero.skillIds);
        expect(skills.map((skill) => skill.slot), [1, 2, 3]);
        expect(skills.map((skill) => skill.heroId), everyElement(hero.id));
      }
      const aliases = {
        'nova': 'nova_blade',
        'ember': 'ember_02',
        'shadow': 'shadow_01',
      };
      for (final entry in aliases.entries) {
        expect(
          registry.getHero(entry.key),
          same(registry.getHero(entry.value)),
        );
        for (var slot = 1; slot <= 3; slot++) {
          expect(
            registry.getSkillForHeroSlot(entry.key, slot),
            same(registry.getSkillForHeroSlot(entry.value, slot)),
          );
        }
      }
      expect(registry.getSkillForHeroSlot('unknown', 1), isNull);
    },
  );

  test('a malformed late catalog leaves all prior catalogs intact', () async {
    final registry = GameAssetRegistry.forTesting();
    await registry.initialize(bundle: _MalformedEnemyBundle());
    expect(registry.isInitialized, isFalse);
    expect(
      registry.getMap('sunken_golden_sanctum'),
      same(GameAssetRegistry.defaultSanctumMap),
    );
    expect(registry.companions, isEmpty);
    expect(registry.skills, isEmpty);

    await registry.initialize();
    final map = registry.getMap('sunken_golden_sanctum');
    final hero = registry.getHero('nova');
    final skill = registry.getSkillForHeroSlot('nova', 1);
    await registry.initialize(bundle: _MalformedEnemyBundle());
    expect(registry.isInitialized, isFalse);
    expect(registry.getMap('sunken_golden_sanctum'), same(map));
    expect(registry.getHero('nova'), same(hero));
    expect(registry.getSkillForHeroSlot('nova', 1), same(skill));
  });

  test(
    'match map selection retains MAIN IDs, images and seeded order',
    () async {
      final registry = GameAssetRegistry.forTesting();
      const mapIds = [
        'sunken_golden_sanctum',
        'map_bang',
        'map_dao_bang_gia',
        'map_rung_cay',
        'dien_tho_co_long',
        'hoa_nguc_dung_nham',
      ];
      const seed = 'integration-room';
      expect(
        registry.getMapForStage(1),
        same(GameAssetRegistry.defaultSanctumMap),
      );
      await registry.initialize();
      expect(registry.isInitialized, isTrue);
      expect(
        registry.availableMatchMaps.map((map) => map.id),
        unorderedEquals(mapIds),
      );
      final peerRegistry = GameAssetRegistry.forTesting();
      await peerRegistry.initialize();
      final seededId = registry.getMapFromSeed(seed).id;
      expect(mapIds, contains(seededId));
      expect(peerRegistry.getMapFromSeed(seed).id, seededId);
      for (var stage = 1; stage < mapIds.length; stage++) {
        expect(registry.getMapForStage(stage).id, mapIds[stage]);
      }
      expect(registry.getMapForStage(7), same(GameAssetRegistry.defaultSanctumMap));
      final cache = SpriteImageCache.forTesting(rootBundle);
      for (final id in mapIds.skip(1)) {
        final map = registry.getMap(id)!;
        expect(registry.getRandomMap(excludeId: id).id, isNot(id));
        final image = await cache.loadMapImageByPath(map.imageAsset, mapId: id);
        expect(image, isNotNull, reason: id);
        expect(cache.getMapImage(id), same(image));
      }
    },
  );

  test('native hero clips select stable rows and keep legacy clips', () async {
    final cache = SpriteImageCache.forTesting(rootBundle);
    for (final hero in [
      'nova_blade',
      'ember_02',
      'shadow_01',
      'kaelen',
      'garrick',
      'valeria',
    ]) {
      await cache.preloadHero(hero);
      expect(cache.getHeroAnimations(hero), isNotNull, reason: hero);
      expect(SpriteImageCache.isProceduralHero(hero), isFalse, reason: hero);
    }
    const runRows = [0, 5, 3, 5, 1];
    for (final hero in ['nova_blade', 'ember_02']) {
      for (var row = 0; row < 5; row++) {
        final sprites = cache.getHeroAnimations(hero, facingRow: row)!;
        expect(cache.getHeroAnimations(hero, facingRow: row), same(sprites));
        expect(sprites.idle.frames, hasLength(5));
        expect(sprites.run.frames, hasLength(8));
        expect(sprites.attack.frames, hasLength(5));
        expect(sprites.idle.frames.first.source.top, row * 256);
        expect(sprites.run.frames.first.source.top, runRows[row] * 256);
        expect(sprites.attack.frames.first.source.top, row * 512);
        expect(sprites.attack.frames.first.worldHeight, 96);
        final nova = hero == 'nova_blade';
        expect(sprites.idle.frames.first.anchor.dy, (nova ? 229 : 236) / 256);
        expect(sprites.attack.frames.first.anchor.dy, (nova ? 477 : 472) / 512);
      }
    }
    final shadow = cache.getHeroAnimations('shadow')!;
    expect(shadow, same(cache.getHeroAnimations('shadow_01', facingRow: 4)));
    for (final clip in [shadow.idle, shadow.run, shadow.attack]) {
      expect(clip.frames, hasLength(16));
      expect(clip.frames.map((frame) => frame.image).toSet(), hasLength(16));
    }
    expect(
      cache.getHeroSequenceFrame('shadow', 'attack', 16),
      same(shadow.attack.frames.first.image),
    );
    for (final hero in [
      'nova',
      'valeria',
      'garrick',
      'kaelen',
      'shadow',
      'ember',
    ]) {
      for (var slot = 1; slot <= 3; slot++) {
        expect(
          cache.getSkillAnimation(hero, slot),
          isNotNull,
          reason: '$hero:$slot',
        );
      }
    }
  });
}
