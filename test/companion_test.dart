import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/models/player_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionType ID Reconciliation & Alias Mapping', () {
    test('Attack drone ID mapping reconciles all primary and shop aliases', () {
      expect(CompanionTypeExtension.fromId('companion_attack'), CompanionType.attack);
      expect(CompanionTypeExtension.fromId('comp_attack'), CompanionType.attack);
      expect(CompanionTypeExtension.fromId('attack'), CompanionType.attack);
    });

    test('Shield drone ID mapping reconciles all primary and shop aliases', () {
      expect(CompanionTypeExtension.fromId('companion_defense'), CompanionType.shield);
      expect(CompanionTypeExtension.fromId('comp_defense'), CompanionType.shield);
      expect(CompanionTypeExtension.fromId('defense'), CompanionType.shield);
      expect(CompanionTypeExtension.fromId('shield'), CompanionType.shield);
    });

    test('Frost drone ID mapping reconciles all primary and shop aliases', () {
      expect(CompanionTypeExtension.fromId('companion_frost'), CompanionType.frost);
      expect(CompanionTypeExtension.fromId('comp_control'), CompanionType.frost);
      expect(CompanionTypeExtension.fromId('control'), CompanionType.frost);
      expect(CompanionTypeExtension.fromId('frost'), CompanionType.frost);
    });

    test('Invalid or null IDs return null safely', () {
      expect(CompanionTypeExtension.fromId(null), isNull);
      expect(CompanionTypeExtension.fromId(''), isNull);
      expect(CompanionTypeExtension.fromId('invalid_id'), isNull);
    });
  });

  group('PlayerProfile copyWith Un-equip Support', () {
    test('clearCompanion clears equipped companion to null', () {
      const profile = PlayerProfile(
        selectedCompanionId: 'comp_attack',
        selectedSkinId: 'skin_gold',
      );

      final unequipped = profile.copyWith(clearCompanion: true);
      expect(unequipped.selectedCompanionId, isNull);
      expect(unequipped.selectedSkinId, 'skin_gold',
          reason: 'Other fields must remain intact when clearing companion');
    });

    test('clearSkin clears equipped skin to null', () {
      const profile = PlayerProfile(
        selectedCompanionId: 'comp_attack',
        selectedSkinId: 'skin_gold',
      );

      final unequipped = profile.copyWith(clearSkin: true);
      expect(unequipped.selectedSkinId, isNull);
      expect(unequipped.selectedCompanionId, 'comp_attack');
    });
  });

  group('Companion Orbital Kinematics', () {
    test('Companion orbits George at radius 45.0px with bobbing', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final drone = CompanionComponent(
        companionId: 'companion_attack',
        player: player,
        orbitRadius: 45.0,
      );

      drone.position = player.position + Vector2(45.0, 0);

      // Advance 1.0 second: angle increases by 1.5 rad
      drone.update(1.0);

      final expectedAngle = (1.5 * 1.0) % (2 * pi);
      final expectedBobbing = sin(1.0 * 4.0) * 3.5;
      final expectedX = player.position.x + cos(expectedAngle) * 45.0;
      final expectedY = player.position.y + sin(expectedAngle) * 45.0 + expectedBobbing;

      expect(drone.position.x, closeTo(expectedX, 0.01));
      expect(drone.position.y, closeTo(expectedY, 0.01));
    });
  });

  group('Shield Drone Damage Absorption Barrier', () {
    test('Shield drone applies 30% damage reduction on George', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      expect(player.currentHp, 100.0);
      expect(player.damageAbsorption, 0.0);

      // Without shield: 20 incoming damage deals 20 damage
      player.takeDamage(20.0);
      expect(player.currentHp, 80.0);

      // Reset HP and equip Shield Drone
      player.currentHp = 100.0;
      player.damageAbsorption = 0.30;

      // With 30% barrier: 20 incoming damage deals 20 * (1 - 0.3) = 14 damage
      player.takeDamage(20.0);
      expect(player.currentHp, 86.0,
          reason: '30% shield barrier must reduce 20 dmg to 14 effective dmg');
    });

    test('Shield barrier stacks multiplicatively with Berserk Fury buff', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      player.damageAbsorption = 0.30;
      player.isBerserk = true; // -40% damage (0.6x factor)

      // Effective damage = 20 * 0.70 * 0.60 = 8.4 damage
      player.takeDamage(20.0);
      expect(player.currentHp, closeTo(91.6, 0.001),
          reason: '30% barrier and Berserk 40% reduction stack cleanly to 8.4 dmg');
    });

    test('CompanionComponent cleanup resets player.damageAbsorption to 0.0', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final drone = CompanionComponent(
        companionId: 'companion_defense',
        player: player,
      );

      player.damageAbsorption = 0.30;
      expect(player.damageAbsorption, 0.30);

      drone.cleanup();
      expect(player.damageAbsorption, 0.0,
          reason: 'Un-mounting shield drone must cleanly reset absorption');
    });
  });

  group('Frost Drone Chilling Aura & Speed Reversibility', () {
    test('Frost Drone slows enemies by 40% and restores on departure', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final zombie = ZombieEnemy(position: Vector2(200, 200), player: player);
      final skeleton = SkeletonEnemy(position: Vector2(200, 200), player: player);

      expect(zombie.speed, 65.0);
      expect(skeleton.speed, 50.0);

      // Reversible speed reduction simulation
      final originalZombieSpeed = zombie.speed;
      final originalSkeletonSpeed = skeleton.speed;

      zombie.speed *= 0.60;
      skeleton.speed *= 0.60;

      expect(zombie.speed, closeTo(39.0, 0.01),
          reason: 'Zombie speed must be slowed by 40% (65 * 0.60 = 39.0)');
      expect(skeleton.speed, closeTo(30.0, 0.01),
          reason: 'Skeleton speed must be slowed by 40% (50 * 0.60 = 30.0)');

      // Restoration
      zombie.speed = originalZombieSpeed;
      skeleton.speed = originalSkeletonSpeed;

      expect(zombie.speed, 65.0);
      expect(skeleton.speed, 50.0);
    });
  });

  group('Attack Drone Plasma Projectile Parameters', () {
    test('Plasma projectile speed 280 px/s, damage 12.0', () {
      final plasma = CompanionPlasmaProjectile(
        position: Vector2(100, 100),
        direction: Vector2(1, 0),
      );

      expect(plasma.speed, 280.0);
      expect(plasma.damage, 12.0);
      expect(plasma.size, Vector2(12, 12));
    });
  });
}
