import 'dart:io';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/combat/hero_skill_system.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

void main() {
  const allHeroIds = [
    'george',
    'ranger',
    'tanker',
    'ninja',
    'valeria',
    'garrick',
    'nova_blade',
    'shadow_01',
    'ember_02',
  ];

  test('All 9 heroes have unique skill names across all 27 skills', () {
    final seenNames = <String>{};
    for (final heroId in allHeroIds) {
      for (final slot in [1, 2, 3]) {
        final meta = HeroSkillSystem.getSkillMeta(heroId, slot);
        expect(meta.name.trim(), isNotEmpty);
        expect(meta.kiCost, greaterThan(0));
        expect(meta.cooldown, greaterThan(0));
        expect(
          seenNames.add(meta.name),
          isTrue,
          reason: 'Duplicate skill name "${meta.name}" on hero $heroId slot $slot',
        );
      }
    }
    expect(seenNames.length, equals(27));
  });

  test('George and Ninja Gemini sprite strips exist and are registered', () {
    for (final heroId in ['george', 'ninja']) {
      expect(SpriteImageCache.isStripAnimatedHero(heroId), isTrue);
      expect(SpriteImageCache.isProceduralHero(heroId), isFalse);
      for (final file in ['idle.png', 'run.png', 'attack.png', 'portrait.png']) {
        final f = File('assets/images/heroes/$heroId/$file');
        expect(f.existsSync(), isTrue, reason: 'Missing ${f.path}');
        expect(f.lengthSync(), greaterThan(1000));
      }
    }
  });

  test('Hero skills execute distinct hero-specific mechanics', () {
    // 1. Ranger Skill 1 spawns 5 arrows
    final ranger = PlayerComponent(position: Vector2(200, 200), heroId: 'ranger');
    final rangerWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 1,
      player: ranger,
      world: rangerWorld,
      targets: const [],
      onDamageText: (_, __, ___) {},
      onBannerText: (_, __) {},
    );
    expect(rangerWorld.children.whereType<HeroProjectile>().length, equals(5));

    // 2. Tanker Skill 2 grants Iron Fortress shield and heals
    final tanker = PlayerComponent(position: Vector2(200, 200), heroId: 'tanker');
    tanker.currentHp = tanker.maxHp * 0.5;
    HeroSkillSystem.executeSkill(
      slot: 2,
      player: tanker,
      world: Component(),
      targets: const [],
      onDamageText: (_, __, ___) {},
      onBannerText: (_, __) {},
    );
    expect(tanker.ironShieldTimer, greaterThan(0));
    expect(tanker.damageAbsorption, greaterThanOrEqualTo(0.65));
    expect(tanker.currentHp, greaterThan(tanker.maxHp * 0.5));

    // 3. Ninja Skill 1 dashes forward & fires 3 piercing shurikens
    final ninja = PlayerComponent(position: Vector2(200, 200), heroId: 'ninja');
    final ninjaWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 1,
      player: ninja,
      world: ninjaWorld,
      targets: const [],
      onDamageText: (_, __, ___) {},
      onBannerText: (_, __) {},
    );
    expect(ninja.position.x, greaterThan(250));
    final shurikens = ninjaWorld.children.whereType<HeroProjectile>().toList();
    expect(shurikens.length, equals(3));
    expect(shurikens.every((p) => p.type == HeroProjectileType.shuriken && p.piercing), isTrue);

    // 4. Ember Skill 3 fires 8 radial fireballs
    final ember = PlayerComponent(position: Vector2(200, 200), heroId: 'ember_02');
    final emberWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 3,
      player: ember,
      world: emberWorld,
      targets: const [],
      onDamageText: (_, __, ___) {},
      onBannerText: (_, __) {},
    );
    expect(emberWorld.children.whereType<HeroProjectile>().length, equals(8));
  });
}
