import 'dart:io';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/big_war_game.dart';
import 'package:my_game/game/combat/hero_skill_system.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/hud/game_hud.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/sprite_image_cache.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  const fourDirHeroIds = [
    'george',
    'ranger',
    'tanker',
    'ninja',
    'valeria',
    'garrick',
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

  test('All 6 non-Nova/Ember/Shadow heroes have 4-dir run & animation strips', () {
    for (final heroId in fourDirHeroIds) {
      expect(SpriteImageCache.isStripAnimatedHero(heroId), isTrue);
      expect(SpriteImageCache.isProceduralHero(heroId), isFalse);
      for (final file in ['idle.png', 'run.png', 'attack.png', 'portrait.png']) {
        final f = File('assets/images/heroes/$heroId/$file');
        expect(f.existsSync(), isTrue, reason: 'Missing ${f.path}');
        expect(f.lengthSync(), greaterThan(1000));
      }
    }
  });

  test('Hero skills execute distinct hero-specific mechanics across all heroes', () {
    // 1. Ranger Skill 1 spawns 5 arrows
    final ranger = PlayerComponent(position: Vector2(200, 200), heroId: 'ranger');
    final rangerWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 1,
      player: ranger,
      world: rangerWorld,
      targets: const [],
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
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
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
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
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
    );
    expect(ninja.position.x, greaterThan(250));
    final shurikens = ninjaWorld.children.whereType<HeroProjectile>().toList();
    expect(shurikens.length, equals(3));
    expect(
      shurikens.every((p) => p.type == HeroProjectileType.shuriken && p.piercing),
      isTrue,
    );

    // 4. Valeria Skill 1 fires paired Frost Orb + Fireball
    final valeria = PlayerComponent(position: Vector2(200, 200), heroId: 'valeria');
    final valeriaWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 1,
      player: valeria,
      world: valeriaWorld,
      targets: const [],
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
    );
    final valeriaProjs = valeriaWorld.children.whereType<HeroProjectile>().toList();
    expect(valeriaProjs.length, equals(2));
    expect(valeriaProjs.any((p) => p.type == HeroProjectileType.frostOrb), isTrue);
    expect(valeriaProjs.any((p) => p.type == HeroProjectileType.fireball), isTrue);

    // 5. Garrick Skill 2 activates Golden Aegis shield + heal
    final garrick = PlayerComponent(position: Vector2(200, 200), heroId: 'garrick');
    garrick.currentHp = garrick.maxHp * 0.6;
    HeroSkillSystem.executeSkill(
      slot: 2,
      player: garrick,
      world: Component(),
      targets: const [],
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
    );
    expect(garrick.ironShieldTimer, greaterThan(0));
    expect(garrick.damageAbsorption, greaterThanOrEqualTo(0.55));
    expect(garrick.currentHp, greaterThan(garrick.maxHp * 0.6));

    // 6. Nova Blade Skill 1 fires piercing Cyan Energy Wave
    final nova = PlayerComponent(position: Vector2(200, 200), heroId: 'nova_blade');
    final novaWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 1,
      player: nova,
      world: novaWorld,
      targets: const [],
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
    );
    final waves = novaWorld.children.whereType<HeroProjectile>().toList();
    expect(waves.length, equals(1));
    expect(waves.first.type, equals(HeroProjectileType.energyWave));
    expect(waves.first.piercing, isTrue);

    // 7. Ember Skill 3 fires 8 radial fireballs
    final ember = PlayerComponent(position: Vector2(200, 200), heroId: 'ember_02');
    final emberWorld = Component();
    HeroSkillSystem.executeSkill(
      slot: 3,
      player: ember,
      world: emberWorld,
      targets: const [],
      onDamageText: (_, _, _) {},
      onBannerText: (_, _) {},
    );
    expect(emberWorld.children.whereType<HeroProjectile>().length, equals(8));
  });

  testWidgets('GameHudOverlay renders all 3 skill buttons cleanly without ParentDataWidget error for all 9 heroes', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    for (final heroId in allHeroIds) {
      final profile = PlayerProfile(selectedHeroId: heroId);
      final game = BigWarGame(playerProfile: profile);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameHudOverlay(game: game),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'HUD threw exception for $heroId');
      expect(find.text('ATK'), findsOneWidget);
      final s1 = HeroSkillSystem.getSkillMeta(heroId, 1);
      final s2 = HeroSkillSystem.getSkillMeta(heroId, 2);
      final s3 = HeroSkillSystem.getSkillMeta(heroId, 3);
      expect(find.byIcon(s1.icon), findsAtLeastNWidgets(1), reason: 'Missing S1 icon for $heroId');
      expect(find.byIcon(s2.icon), findsAtLeastNWidgets(1), reason: 'Missing S2 icon for $heroId');
      expect(find.byIcon(s3.icon), findsAtLeastNWidgets(1), reason: 'Missing S3 icon for $heroId');
    }
  });

  test('PvE floor progress persists across restarts and resets only when requested', () async {
    SharedPreferences.setMockInitialValues({});
    await PlayerStorage.saveProfile(const PlayerProfile(pveCurrentFloor: 1, pveHighestFloor: 1));

    // Clear Floor 1 -> saved next floor is 2
    await PlayerStorage.savePveProgress(2);
    expect(PlayerStorage.currentProfile.pveCurrentFloor, equals(2));
    expect(PlayerStorage.currentProfile.pveHighestFloor, equals(2));

    // Clear Floor 5 -> saved next floor is 6
    await PlayerStorage.savePveProgress(6);
    final reloaded = await PlayerStorage.loadProfile();
    expect(reloaded.pveCurrentFloor, equals(6));
    expect(reloaded.pveHighestFloor, equals(6));

    // Launching BigWarGame without explicit initialFloor resumes at Floor 6
    final resumedGame = BigWarGame(playerProfile: reloaded);
    expect(resumedGame.currentFloor, equals(6));

    // Explicit reset returns to Floor 1 while keeping highest floor record
    await PlayerStorage.resetPveToFloorOne();
    final afterReset = await PlayerStorage.loadProfile();
    expect(afterReset.pveCurrentFloor, equals(1));
    expect(afterReset.pveHighestFloor, equals(6));
  });
}
