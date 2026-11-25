import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/big_war_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

Future<int> beamAlpha(CompanionComponent pet) async {
  final recorder = ui.PictureRecorder();
  pet.render(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 80);
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final alpha = pixels!.getUint8((12 * 180 + 60) * 4 + 3);
  image.dispose();
  picture.dispose();
  return alpha;
}

void main() {
  test(
    'Fox runs toward its ground follow point then rests without orbiting',
    () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final fox = CompanionComponent(companionId: 'luna_fox', player: player);
      fox.position.setValues(68, 112);
      for (var i = 0; i < 120; i++) {
        fox.update(1 / 60);
      }
      expect(fox.position.x, closeTo(68, .01));
      expect(fox.position.y, closeTo(112, .01));
      expect(fox.isFoxRunning, isFalse);
      player.position.x += 80;
      player.moveDirection.setValues(1, 0);
      final previous = fox.position.clone();
      fox.update(1 / 60);
      expect(fox.isFoxRunning, isTrue);
      expect(fox.position.x, greaterThan(previous.x));
      expect(fox.position.distanceTo(previous), lessThan(10));
      player.moveDirection.setZero();
      for (var i = 0; i < 180; i++) {
        fox.update(1 / 60);
      }
      expect(fox.isFoxRunning, isFalse);
      expect(fox.position.distanceTo(Vector2(148, 112)), lessThanOrEqualTo(2));
      final resting = fox.position.clone();
      for (var i = 0; i < 120; i++) {
        fox.update(1 / 60);
      }
      expect(fox.position.distanceTo(resting), 0);
      player.position.x += 60;
      fox.update(.016);
      expect(fox.isFoxRunning, isTrue);
      fox.resetForFloor();
      expect(fox.isFoxRunning, isFalse);
      player.currentHp = 0;
      fox.update(.016);
      expect(fox.isFoxRunning, isFalse);
    },
  );
  for (final entry in {
    'comp_defense': (passive: .3, active: .55, duration: 5.1),
    'cyber_drone': (passive: .3, active: .45, duration: 4.6),
    'aegis_x9': (passive: .2, active: .35, duration: 4.1),
  }.entries) {
    test(
      'Temporary PET shield expires and preserves ${entry.key} passive defense',
      () {
        final player = PlayerComponent(position: Vector2.zero());
        player.damageAbsorption = entry.value.passive;
        final pet = CompanionComponent(companionId: entry.key, player: player);
        expect(pet.activateSpecialSkill(), isTrue);
        expect(player.damageAbsorption, closeTo(entry.value.active, .001));
        final cooldown = pet.specialSkillCooldown;
        expect(pet.activateSpecialSkill(), isFalse);
        expect(pet.specialSkillCooldown, cooldown);
        player.update(entry.value.duration);
        pet.update(entry.value.duration);
        expect(player.goldenShieldTimer, 0);
        expect(player.damageAbsorption, closeTo(entry.value.passive, .001));
        final hp = player.currentHp;
        player.takeDamage(40);
        expect(
          hp - player.currentHp,
          closeTo(40 * (1 - entry.value.passive), .001),
        );
      },
    );
  }
  test('All 8 companions have unique special skill names and distinct effects', () {
    final ids = [
      'comp_attack',
      'comp_defense',
      'comp_control',
      'cyber_drone',
      'luna_fox',
      'orbit_03',
      'aegis_x9',
      'pyro_frost_dragon',
    ];
    final names = <String>{};
    for (final id in ids) {
      final p = PlayerComponent(position: Vector2.zero());
      final pet = CompanionComponent(companionId: id, player: p);
      names.add(pet.skillName);
    }
    expect(names.length, ids.length);

    // Cyber Drone heals 25% max HP + grants 45% shield
    final pCyber = PlayerComponent(position: Vector2.zero());
    pCyber.currentHp = pCyber.maxHp * 0.5;
    final cyber = CompanionComponent(companionId: 'cyber_drone', player: pCyber);
    expect(cyber.activateSpecialSkill(), isTrue);
    expect(pCyber.currentHp, closeTo(pCyber.maxHp * 0.75, 0.01));
    expect(pCyber.damageAbsorption, closeTo(0.45, 0.001));

    // Luna Fox restores 40% Ki + reduces all 3 skill cooldowns by 3s
    final pLuna = PlayerComponent(position: Vector2.zero());
    pLuna.currentKi = 10;
    pLuna.skill1VisualCd = 4.0;
    pLuna.skill2VisualCd = 6.0;
    pLuna.skill3VisualCd = 10.0;
    final luna = CompanionComponent(companionId: 'luna_fox', player: pLuna);
    expect(luna.activateSpecialSkill(), isTrue);
    expect(pLuna.currentKi, closeTo(10 + pLuna.maxKi * 0.40, 0.01));
    expect(pLuna.skill1VisualCd, closeTo(1.0, 0.01));
    expect(pLuna.skill2VisualCd, closeTo(3.0, 0.01));
    expect(pLuna.skill3VisualCd, closeTo(7.0, 0.01));

    // ORBIT-03 activates rapid fire overdrive for 4s
    final pOrbit = PlayerComponent(position: Vector2.zero());
    final orbit = CompanionComponent(companionId: 'orbit_03', player: pOrbit);
    expect(orbit.isRapidFireActive, isFalse);
    expect(orbit.activateSpecialSkill(), isTrue);
    expect(orbit.isRapidFireActive, isTrue);
    orbit.update(4.1);
    expect(orbit.isRapidFireActive, isFalse);

    // Pyro-Frost Dragon grants +30% attack buff for 5s & clears on cleanup
    final pDragon = PlayerComponent(position: Vector2.zero());
    final baseDmg = pDragon.damage;
    final dragon = CompanionComponent(
      companionId: 'pyro_frost_dragon',
      player: pDragon,
    );
    expect(dragon.activateSpecialSkill(), isTrue);
    expect(pDragon.effectiveDamage, closeTo(baseDmg * 1.30, 0.01));
    dragon.cleanup();
    expect(pDragon.effectiveDamage, closeTo(baseDmg, 0.01));
  });
  test(
    'Unequip and floor reset remove temporary shield and stale targeting',
    () {
      final player = PlayerComponent(position: Vector2.zero());
      final pet = CompanionComponent(companionId: 'orbit_03', player: player);
      pet.activateSpecialSkill();
      pet.lockedTarget = PositionComponent();
      pet.resetForFloor();
      expect(pet.lockedTarget, isNull);
      expect(pet.specialSkillCooldown, 0);
      expect(player.damageAbsorption, 0);
      pet.activateSpecialSkill();
      pet.cleanup();
      expect(player.goldenShieldTimer, 0);
      expect(player.damageAbsorption, 0);
      player.currentHp = 0;
      pet.specialSkillCooldown = 0;
      expect(pet.activateSpecialSkill(), isFalse);
    },
  );
  test(
    'PET hotkey cannot summon a free companion when nothing is equipped',
    () {
      final game = BigWarGame(playerProfile: const PlayerProfile());
      game.onCompanionSkill();
      expect(game.companion, isNull);
    },
  );

  testWidgets(
    'Restored companion sprites retain lasers and automatic projectile damage',
    (tester) async {
      // Decode/filter textures with real asynchronous image I/O before mounting.
      await tester.runAsync(() async {
        for (final id in ['aegis_x9', 'orbit_03']) {
          for (var i = 0; i < 200; i++) {
            if (SpriteImageCache.instance.getCompanionImage(id) != null) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }
      });
      final game = BigWarGame(
        playerProfile: const PlayerProfile(selectedCompanionId: 'aegis_x9'),
        selectedMapConfig: GameAssetRegistry.defaultSanctumMap,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && !game.isLoaded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      final victim = game.enemies.first;
      expect(victim.isMounted, isTrue);
      for (final id in ['aegis_x9', 'orbit_03']) {
        await tester.runAsync(() async {
          ui.Image? image;
          for (var i = 0; i < 200 && image == null; i++) {
            image = SpriteImageCache.instance.getCompanionImage(id);
            if (image == null) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }
          expect(
            image,
            isNotNull,
            reason: 'Exercise sprite branch, not fallback body',
          );
        });
        final pet = CompanionComponent(companionId: id, player: game.player);
        pet.position = Vector2(100, 100);
        victim.position = Vector2(200, 100);
        victim.currentHp = 100;
        pet.lockedTarget = victim;
        final alpha = await tester.runAsync(() => beamAlpha(pet));
        expect(
          alpha,
          greaterThan(0),
          reason: '$id still draws beam outside its image',
        );
        victim.currentHp = 0;
        final deadAlpha = await tester.runAsync(() => beamAlpha(pet));
        expect(deadAlpha, 0, reason: 'No beam aimed at a defeated target');
        victim.currentHp = 100;
      }
      final livePet = game.companion!;
      victim.position = livePet.position + Vector2(80, 0);
      livePet.actionCooldown = 0;
      livePet.update(.01);
      await tester.pump(const Duration(milliseconds: 1));
      final projectiles = game.world.children
          .whereType<CompanionPlasmaProjectile>()
          .toList();
      expect(projectiles, isNotEmpty);
      final hp = victim.currentHp;
      projectiles.last.onCollision({Vector2.zero()}, victim);
      expect(victim.currentHp, hp - 12);
      game.retryFloor();
      expect(game.companion!.lockedTarget, isNull);
      expect(game.player.goldenShieldTimer, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
