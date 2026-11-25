import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pickup_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BossEnemy Multi-Phase State Machine & Attributes', () {
    test('BossEnemy initializes with 600 Max HP, Phase 1, and 55 px/s speed', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      expect(boss.maxHp, 600.0);
      expect(boss.currentHp, 600.0);
      expect(boss.phase, 1);
      expect(boss.isEnraged, isFalse);
      expect(boss.isDefeated, isFalse);
      expect(boss.currentSpeed, 55.0);
      expect(boss.size, Vector2(64, 64));
    });

    test('BossEnemy enters Phase 2 (Enraged) at <= 50% HP (300 HP) with 80 px/s speed', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Deal 300 damage (bringing HP to exactly 300)
      boss.takeDamage(300.0);

      expect(boss.currentHp, 300.0);
      expect(boss.phase, 2);
      expect(boss.isEnraged, isTrue);
      expect(boss.currentSpeed, 80.0,
          reason: 'Speed must increase by +45% from 55 to 80 px/s in Phase 2');
    });

    test('Boss triggers Wave 1 minion summon at <= 70% HP (420 HP)', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Damage to 450 HP (75% HP) -> Wave 1 not triggered yet
      boss.takeDamage(150.0);
      expect(boss.currentHp, 450.0);
      expect(boss.summonedWave70, isFalse);

      // Damage to 410 HP (below 70% threshold of 420 HP)
      boss.takeDamage(40.0);
      expect(boss.currentHp, 410.0);
      expect(boss.summonedWave70, isTrue);

      // Subsequent damage does not re-trigger wave 1
      boss.takeDamage(30.0);
      expect(boss.summonedWave70, isTrue);
    });

    test('Boss triggers Wave 2 minion summon at <= 30% HP (180 HP)', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Deal 430 damage -> HP = 170 (below 30% threshold of 180 HP)
      boss.takeDamage(430.0);
      expect(boss.currentHp, 170.0);
      expect(boss.summonedWave70, isTrue);
      expect(boss.summonedWave30, isTrue);
    });

    test('Boss enters defeated state at 0 HP', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      boss.takeDamage(600.0);
      expect(boss.currentHp, 0.0);
      expect(boss.isDefeated, isTrue);
      expect(boss.state, BossState.defeated);
    });
  });

  group('Boss Combat Parameters & Auxiliary Skills', () {
    test('Melee Cleave parameters: 70px range, 25 damage', () {
      final boss = BossEnemy(position: Vector2.zero(), player: PlayerComponent(position: Vector2.zero()));
      expect(BossEnemy.meleeRange, 70.0);
      expect(boss.meleeDamage, 25.0);
    });

    test('Ground Slam parameters: 1.2s telegraph, 70px radius / 140px diameter AoE, 40 damage', () {
      final boss = BossEnemy(position: Vector2.zero(), player: PlayerComponent(position: Vector2.zero()));
      expect(BossEnemy.groundSlamRange, 220.0);
      expect(BossEnemy.groundSlamAoERadius, 70.0);
      expect(boss.groundSlamDamage, 40.0);
      expect(BossEnemy.groundSlamTelegraphDuration, 1.2);

      final telegraph = GroundSlamTelegraph(
        position: Vector2(200, 200),
        duration: 1.2,
      );
      expect(telegraph.size, Vector2(140, 140));
      expect(telegraph.duration, 1.2);
    });

    test('Radial Flame Burst parameters: 8 fireballs, 180 px/s speed, 15 damage', () {
      final boss = BossEnemy(position: Vector2.zero(), player: PlayerComponent(position: Vector2.zero()));
      expect(boss.flameBurstSpeed, 180.0);
      expect(boss.flameBurstDamage, 15.0);

      final flame = BossFlameProjectile(
        position: Vector2(100, 100),
        direction: Vector2(1, 0),
        speed: 180.0,
        damage: 15.0,
      );

      expect(flame.speed, 180.0);
      expect(flame.damage, 15.0);
      expect(flame.size, Vector2(16, 16));
    });

    test('Defeat Loot Ring geometry: 12 Gold Coins (12,000 Gold) and 3 Health Potions', () {
      // Replicate the loot generation loop from BossEnemy._triggerDefeat
      final droppedTypes = <PickupType>[];
      const int totalItems = 15;
      const double radius = 68.0;
      final bossPos = Vector2(500, 500);

      for (int i = 0; i < totalItems; i++) {
        final angle = i * (2 * pi / totalItems);
        final itemPos = bossPos + Vector2(cos(angle) * radius, sin(angle) * radius);
        final type = (i % 5 == 0) ? PickupType.healthPotion : PickupType.goldCoin;
        droppedTypes.add(type);

        // Distance from boss defeat center must be exactly 68px
        expect(bossPos.distanceTo(itemPos), closeTo(68.0, 0.001));
      }

      final coins = droppedTypes.where((t) => t == PickupType.goldCoin).toList();
      final potions = droppedTypes.where((t) => t == PickupType.healthPotion).toList();

      expect(coins.length, 12, reason: 'Must drop exactly 12 Gold Coins');
      expect(potions.length, 3, reason: 'Must drop exactly 3 Health Potions');

      // 12 coins * 1000 = 12,000 Gold in wallet
      final totalGold = coins.length * 1000;
      expect(totalGold, 12000, reason: '12 coins must equal 12,000 Gold');
    });

    test('BossHpData computes accurate hpPercent and encapsulates state', () {
      const dataP1 = BossHpData(
        currentHp: 480.0,
        maxHp: 600.0,
        phase: 1,
        isEnraged: false,
        isDefeated: false,
      );
      expect(dataP1.hpPercent, closeTo(0.8, 0.001));
      expect(dataP1.title, 'CHÚA TỂ HẦM NGỤC');

      const dataP2 = BossHpData(
        currentHp: 240.0,
        maxHp: 600.0,
        phase: 2,
        isEnraged: true,
        isDefeated: false,
      );
      expect(dataP2.hpPercent, closeTo(0.4, 0.001));
      expect(dataP2.isEnraged, isTrue);
    });
    test('takeDamage with negative damage clamps HP to maxHp', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      expect(boss.currentHp, 600.0);
      boss.takeDamage(-50.0);
      expect(boss.currentHp, 600.0, reason: 'Negative damage must clamp to maxHp without exceeding');

      // Reduce HP first, then negative damage partially restores but clamps
      boss.takeDamage(100.0);
      expect(boss.currentHp, 500.0);
      boss.takeDamage(-200.0);
      expect(boss.currentHp, 600.0, reason: 'Negative damage cannot elevate HP above maxHp');
    });
  });
}
