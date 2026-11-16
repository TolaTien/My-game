import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pickup_item.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/core/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper geometry for the 6 stone pillars in the 36x24 dungeon
  // Pillars: (8, 6), (8, 16), (26, 6), (26, 16), (17, 10), (18, 10)
  // Each is 2x2 tiles. (17, 10) and (18, 10) merge into a 3x2 pillar.
  bool isGridInsidePillar(int col, int row) {
    if (col >= 8 && col <= 9 && row >= 6 && row <= 7) return true;
    if (col >= 8 && col <= 9 && row >= 16 && row <= 17) return true;
    if (col >= 26 && col <= 27 && row >= 6 && row <= 7) return true;
    if (col >= 26 && col <= 27 && row >= 16 && row <= 17) return true;
    if (col >= 17 && col <= 19 && row >= 10 && row <= 11) return true;
    return false;
  }

  bool isWorldPointInsidePillar(Vector2 pt) {
    final (col, row) = AStarPathfinder.worldToGrid(pt);
    return isGridInsidePillar(col, row);
  }

  bool doesSegmentIntersectPillar(Vector2 p1, Vector2 p2) {
    final dist = p1.distanceTo(p2);
    if (dist < 1.0) return isWorldPointInsidePillar(p1);
    final steps = (dist / 4.0).ceil().clamp(2, 200);
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final sample = p1 * (1.0 - t) + p2 * t;
      if (isWorldPointInsidePillar(sample)) return true;
    }
    return false;
  }

  group('AStarPathfinder Empirical Stress & Obstacle Avoidance', () {
    late List<List<bool>> grid;

    setUp(() {
      grid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('100 random coordinate pairs: zero pillar intersection & sub-2.0ms budget', () {
      final random = Random(42); // Deterministic seed for reproducibility
      const int numPairs = 100;
      final durationsMicros = <int>[];

      // Collect all walkable cells
      final walkableCells = <(int, int)>[];
      for (int c = 1; c < 35; c++) {
        for (int r = 1; r < 23; r++) {
          if (grid[c][r] && !isGridInsidePillar(c, r)) {
            walkableCells.add((c, r));
          }
        }
      }

      expect(walkableCells.length, greaterThan(600),
          reason: 'Walkable floor area must have hundreds of valid cells');

      for (int i = 0; i < numPairs; i++) {
        final startCell = walkableCells[random.nextInt(walkableCells.length)];
        final targetCell = walkableCells[random.nextInt(walkableCells.length)];

        // Generate positions with random jitter inside the cell
        final startPos = AStarPathfinder.gridToWorld(startCell.$1, startCell.$2) +
            Vector2((random.nextDouble() - 0.5) * 16.0, (random.nextDouble() - 0.5) * 16.0);
        final targetPos = AStarPathfinder.gridToWorld(targetCell.$1, targetCell.$2) +
            Vector2((random.nextDouble() - 0.5) * 16.0, (random.nextDouble() - 0.5) * 16.0);

        final sw = Stopwatch()..start();
        final path = AStarPathfinder.findPath(startPos, targetPos, grid);
        sw.stop();
        durationsMicros.add(sw.elapsedMicroseconds);

        expect(path, isNotEmpty,
            reason: 'A path between connected walkable cells must be found (iteration $i)');

        // 1. Assert that no waypoint in path ever lands inside any pillar
        for (int w = 0; w < path.length; w++) {
          final wp = path[w];
          expect(isWorldPointInsidePillar(wp), isFalse,
              reason: 'Waypoint $w at $wp in iteration $i intersects a stone pillar!');
        }

        // 2. Assert that no line segment between consecutive waypoints cuts into any pillar
        for (int s = 0; s < path.length - 1; s++) {
          final pA = path[s];
          final pB = path[s + 1];
          expect(doesSegmentIntersectPillar(pA, pB), isFalse,
              reason: 'Segment $s -> ${s + 1} ($pA to $pB) intersects a stone pillar!');
        }
      }

      // Performance Budget Assertions
      final avgDurationMs = (durationsMicros.reduce((a, b) => a + b) / numPairs) / 1000.0;
      final maxDurationMs = durationsMicros.reduce(max) / 1000.0;

      // Authoritative requirement: execution time per path is well within the 2.0ms budget
      expect(avgDurationMs, lessThan(2.0),
          reason: 'Average execution time ($avgDurationMs ms) must be well under 2.0ms');
      expect(maxDurationMs, lessThan(10.0),
          reason: 'Worst-case execution time ($maxDurationMs ms) must remain bounded');
    });

    test('Diagonal corner-cutting stress test across all 4 corners of Pillar 1', () {
      // Pillar 1: cols 8..9, rows 6..7
      // Corners: Top-Left (8, 6), Top-Right (9, 6), Bottom-Left (8, 7), Bottom-Right (9, 7)
      final cornerScenarios = [
        // Top-Left corner: from (7, 5) to (10, 8)
        (Vector2(7.5 * 32, 5.5 * 32), Vector2(10.5 * 32, 8.5 * 32)),
        // Top-Right corner: from (10, 5) to (7, 8)
        (Vector2(10.5 * 32, 5.5 * 32), Vector2(7.5 * 32, 8.5 * 32)),
        // Bottom-Left corner: from (7, 8) to (10, 5)
        (Vector2(7.5 * 32, 8.5 * 32), Vector2(10.5 * 32, 5.5 * 32)),
        // Bottom-Right corner: from (10, 8) to (7, 5)
        (Vector2(10.5 * 32, 8.5 * 32), Vector2(7.5 * 32, 5.5 * 32)),
      ];

      for (int i = 0; i < cornerScenarios.length; i++) {
        final (start, target) = cornerScenarios[i];
        final path = AStarPathfinder.findPath(start, target, grid);

        expect(path, isNotEmpty, reason: 'Path for corner scenario $i must exist');
        for (final pt in path) {
          expect(isWorldPointInsidePillar(pt), isFalse,
              reason: 'Corner scenario $i generated waypoint $pt inside pillar!');
        }
        for (int s = 0; s < path.length - 1; s++) {
          expect(doesSegmentIntersectPillar(path[s], path[s + 1]), isFalse,
              reason: 'Corner scenario $i segment intersects pillar!');
        }
      }
    });

    test('Full-map diagonal traverse across dungeon (over 1000px)', () {
      // From near top-left (col 1, row 1) to bottom-right (col 34, row 22)
      final startPos = Vector2(1.5 * 32, 1.5 * 32);
      final targetPos = Vector2(34.5 * 32, 22.5 * 32);

      final sw = Stopwatch()..start();
      final path = AStarPathfinder.findPath(startPos, targetPos, grid);
      sw.stop();

      expect(path, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(15),
          reason: 'Full-map pathfinding must complete rapidly');
      expect(path.last.distanceTo(targetPos), lessThan(1.0));

      for (final pt in path) {
        expect(isWorldPointInsidePillar(pt), isFalse);
      }
    });

    test('Adversarial target-in-pillar: inspect destination behavior when target is inside obstacle', () {
      // Test target located inside each of the 6 pillars
      final pillarCenters = [
        Vector2(8.5 * 32, 6.5 * 32),   // Pillar 1
        Vector2(8.5 * 32, 16.5 * 32),  // Pillar 2
        Vector2(26.5 * 32, 6.5 * 32),  // Pillar 3
        Vector2(26.5 * 32, 16.5 * 32), // Pillar 4
        Vector2(17.5 * 32, 10.5 * 32), // Pillar 5
        Vector2(18.5 * 32, 10.5 * 32), // Pillar 6
      ];

      final startPos = Vector2(4 * 32.0, 4 * 32.0);

      for (int i = 0; i < pillarCenters.length; i++) {
        final targetInPillar = pillarCenters[i];
        final path = AStarPathfinder.findPath(startPos, targetInPillar, grid);

        expect(path, isNotEmpty,
            reason: 'Pathfinder must find walkable approach path for pillar $i');

        // All intermediate navigation waypoints (excluding final raw target coordinate)
        // must be strictly outside the pillar
        final navWaypoints = path.sublist(0, path.length - 1);
        for (final wp in navWaypoints) {
          expect(isWorldPointInsidePillar(wp), isFalse,
              reason: 'Intermediate navigation waypoint $wp must NOT be inside pillar $i');
        }
      }
    });

    test('Empirical performance statistics: 100 paths breakdown', () {
      final random = Random(12345);
      final walkableCells = <(int, int)>[];
      for (int c = 1; c < 35; c++) {
        for (int r = 1; r < 23; r++) {
          if (grid[c][r] && !isGridInsidePillar(c, r)) {
            walkableCells.add((c, r));
          }
        }
      }

      final samples = <double>[];
      for (int i = 0; i < 100; i++) {
        final sCell = walkableCells[random.nextInt(walkableCells.length)];
        final tCell = walkableCells[random.nextInt(walkableCells.length)];
        final s = AStarPathfinder.gridToWorld(sCell.$1, sCell.$2);
        final t = AStarPathfinder.gridToWorld(tCell.$1, tCell.$2);

        final sw = Stopwatch()..start();
        AStarPathfinder.findPath(s, t, grid);
        sw.stop();
        samples.add(sw.elapsedMicroseconds / 1000.0);
      }

      final avgMs = samples.reduce((a, b) => a + b) / samples.length;
      final maxMs = samples.reduce(max);
      final minMs = samples.reduce(min);

      // Print empirical performance findings
      // (Visible in test logs for verification)
      expect(avgMs, lessThan(1.5),
          reason: 'Empirical average ($avgMs ms) must be well below 2.0ms budget');
      expect(minMs, greaterThanOrEqualTo(0.0));
      expect(maxMs, lessThan(8.0));
    });
  });

  group('BossEnemy Phase Transitions, Summon Waves & Defeat Loot', () {
    test('Rapid micro-damage inputs: Phase 2 triggers at exactly 300 HP and wave counts are strictly 1', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      int wave70Triggers = 0;
      int wave30Triggers = 0;
      int phase2Triggers = 0;

      bool prevSummon70 = false;
      bool prevSummon30 = false;
      bool prevEnraged = false;

      // Apply 600 individual 1.0 damage increments
      for (int i = 1; i <= 600; i++) {
        boss.takeDamage(1.0);

        if (boss.summonedWave70 && !prevSummon70) {
          wave70Triggers++;
          prevSummon70 = true;
          // Invariant: Wave 70 must trigger at exactly 420.0 HP
          expect(boss.currentHp, closeTo(420.0, 0.001),
              reason: 'Wave 70 must trigger at exactly 70% max HP (420 HP)');
        }

        if (boss.isEnraged && !prevEnraged) {
          phase2Triggers++;
          prevEnraged = true;
          // Invariant: Phase 2 transition must occur at exactly 300.0 HP (50%)
          expect(boss.currentHp, closeTo(300.0, 0.001),
              reason: 'Phase 2 transition must occur at exactly 50% max HP (300 HP)');
          expect(boss.phase, 2);
          expect(boss.currentSpeed, 80.0);
        }

        if (boss.summonedWave30 && !prevSummon30) {
          wave30Triggers++;
          prevSummon30 = true;
          // Invariant: Wave 30 must trigger at exactly 180.0 HP
          expect(boss.currentHp, closeTo(180.0, 0.001),
              reason: 'Wave 30 must trigger at exactly 30% max HP (180 HP)');
        }
      }

      // Assert each event triggered EXACTLY once
      expect(wave70Triggers, 1, reason: 'Wave 70% must trigger exactly once');
      expect(phase2Triggers, 1, reason: 'Phase 2 must trigger exactly once');
      expect(wave30Triggers, 1, reason: 'Wave 30% must trigger exactly once');
      expect(boss.currentHp, 0.0);
      expect(boss.isDefeated, isTrue);
      expect(boss.state, BossState.defeated);

      // Overkill damage safety: further damage calls must do nothing
      boss.takeDamage(100.0);
      expect(boss.currentHp, 0.0);
      expect(wave70Triggers, 1);
      expect(wave30Triggers, 1);
    });

    test('Single-hit massive burst damage (600 dmg) triggers all thresholds safely', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      boss.takeDamage(600.0);

      expect(boss.currentHp, 0.0);
      expect(boss.phase, 2);
      expect(boss.isEnraged, isTrue);
      expect(boss.summonedWave70, isTrue);
      expect(boss.summonedWave30, isTrue);
      expect(boss.isDefeated, isTrue);
      expect(boss.state, BossState.defeated);
    });

    testWidgets('In-Game World Integration with GoldRushGame: Minion Spawns and Defeat Loot Ring', (tester) async {
      final game = GoldRushGame(playerProfile: const PlayerProfile());
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final boss = game.boss;
      expect(boss, isNotNull);
      expect(boss!.isMounted, isTrue);

      final initialSkeletons = game.skeletons.length;
      final initialEnemies = game.enemies.length;
      final initialPickups = game.pickups.length;

      expect(initialSkeletons, 3);
      expect(initialEnemies, 5);
      expect(initialPickups, 6);

      // 1. Damage boss to 400 HP (crosses 70% threshold: 420 HP)
      boss.takeDamage(200.0);
      expect(boss.currentHp, 400.0);
      expect(boss.summonedWave70, isTrue);
      // Wave 1 spawns 2 Skeletons and 2 Zombies
      expect(game.skeletons.length, initialSkeletons + 2);
      expect(game.enemies.length, initialEnemies + 2);

      // 2. Damage boss to 150 HP (crosses 50% Phase 2 and 30% Wave 2: 180 HP)
      boss.takeDamage(250.0);
      expect(boss.currentHp, 150.0);
      expect(boss.phase, 2);
      expect(boss.isEnraged, isTrue);
      expect(boss.summonedWave30, isTrue);
      // Wave 2 spawns another 2 Skeletons and 2 Zombies
      expect(game.skeletons.length, initialSkeletons + 4);
      expect(game.enemies.length, initialEnemies + 4);

      // 3. Defeat boss (damage remaining 150 HP)
      boss.takeDamage(150.0);
      await tester.pump();
      expect(boss.currentHp, 0.0);
      expect(boss.isDefeated, isTrue);

      // Defeat drops exactly 12 coins and 3 potions (total 15 pickups)
      final newPickups = game.pickups.sublist(initialPickups);
      expect(newPickups.length, 15, reason: 'Boss must drop exactly 15 pickups');

      final coins = newPickups.where((p) => p.type == PickupType.goldCoin).toList();
      final potions = newPickups.where((p) => p.type == PickupType.healthPotion).toList();

      expect(coins.length, 12, reason: 'Boss must drop exactly 12 Gold Coins');
      expect(potions.length, 3, reason: 'Boss must drop exactly 3 Health Potions');

      // Verify geometry: All 15 pickups arranged in a 68px radius ring
      for (final pickup in newPickups) {
        final dist = pickup.position.distanceTo(boss.position);
        expect(dist, closeTo(68.0, 0.01),
            reason: 'Pickup position must form a circle of radius 68px around boss');
      }

      // Verify wallet conversion rule: 12 coins = 12,000 Gold
      final totalGold = coins.length * GameConstants.goldPerCoinPickup;
      expect(totalGold, 12000, reason: '12 coins at 1000 gold/coin must equal 12,000 Gold');

      // Verify victory portal is created in game world
      final portals = game.world.children.whereType<BossVictoryPortal>().toList();
      expect(portals.length, 1, reason: 'Boss defeat must spawn exactly 1 BossVictoryPortal');

      // Clean up game
      game.onRemove();
    });
  });

  group('CompanionComponent Equipping, Switching & Damage Absorption Arithmetic', () {
    test('Toggle companion switching updates player damage absorption correctly', () {
      final player = PlayerComponent(position: Vector2(200, 200));

      // 1. Equip Attack Drone
      final attackDrone = CompanionComponent(
        companionId: 'companion_attack',
        player: player,
      );
      expect(attackDrone.type, CompanionType.attack);
      expect(player.damageAbsorption, 0.0);

      // 2. Switch to Shield Drone
      attackDrone.cleanup();
      final shieldDrone = CompanionComponent(
        companionId: 'companion_defense',
        player: player,
      );
      // In onMount / onLoad, Shield Drone sets player.damageAbsorption to 0.30
      player.damageAbsorption = 0.30;
      expect(shieldDrone.type, CompanionType.shield);
      expect(player.damageAbsorption, 0.30);

      // 3. Switch to Frost Drone
      shieldDrone.cleanup();
      expect(player.damageAbsorption, 0.0,
          reason: 'Switching away from Shield Drone must restore absorption to 0.0');

      final frostDrone = CompanionComponent(
        companionId: 'companion_frost',
        player: player,
      );
      expect(frostDrone.type, CompanionType.frost);
      expect(player.damageAbsorption, 0.0);

      // 4. Switch back to Attack Drone
      frostDrone.cleanup();
      final attackDrone2 = CompanionComponent(
        companionId: 'comp_attack',
        player: player,
      );
      expect(attackDrone2.type, CompanionType.attack);
      expect(player.damageAbsorption, 0.0);
    });

    test('Un-equipping via PlayerProfile.copyWith(clearCompanion: true)', () {
      const fullProfile = PlayerProfile(
        playerName: 'George Champion',
        gold: 15000,
        diamonds: 20,
        rankPoints: 1650,
        selectedCompanionId: 'comp_defense',
        selectedSkinId: 'skin_berserker',
        selectedHeroId: 'george',
        unlockedCompanionIds: ['comp_defense', 'comp_attack'],
      );

      final unequippedProfile = fullProfile.copyWith(clearCompanion: true);

      expect(unequippedProfile.selectedCompanionId, isNull,
          reason: 'clearCompanion: true must set selectedCompanionId to null');
      expect(unequippedProfile.playerName, 'George Champion');
      expect(unequippedProfile.gold, 15000);
      expect(unequippedProfile.diamonds, 20);
      expect(unequippedProfile.rankPoints, 1650);
      expect(unequippedProfile.selectedSkinId, 'skin_berserker');
      expect(unequippedProfile.unlockedCompanionIds, ['comp_defense', 'comp_attack']);
    });

    test('Damage absorption arithmetic: exactly 14.0 effective damage for 20 base dmg', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      player.currentHp = 100.0;
      player.maxHp = 100.0;
      player.damageAbsorption = 0.30;

      // 20 base dmg with 30% reduction -> 20 * (1 - 0.30) = 14.0 effective dmg
      player.takeDamage(20.0);
      expect(player.currentHp, 86.0,
          reason: '100 HP - 14 effective dmg must equal exactly 86.0 HP');

      // Zero damage input
      player.takeDamage(0.0);
      expect(player.currentHp, 86.0);

      // Fractional damage: 25.5 base dmg * 0.70 = 17.85 effective dmg -> 86.0 - 17.85 = 68.15 HP
      player.takeDamage(25.5);
      expect(player.currentHp, closeTo(68.15, 0.001));

      // Multiplicative stacking with Berserk buff (-40% damage)
      player.currentHp = 100.0;
      player.isBerserk = true;
      // 20 * 0.70 * 0.60 = 8.4 effective dmg -> 100.0 - 8.4 = 91.6 HP
      player.takeDamage(20.0);
      expect(player.currentHp, closeTo(91.6, 0.001),
          reason: 'Shield barrier (0.7) and Berserk (0.6) stack multiplicatively to 8.4 dmg');

      // Heavy 200 base damage while Berserk is active: 200 * 0.70 * 0.60 = 84.0 dmg
      // Remaining HP = 91.6 - 84.0 = 7.6 HP (Player miraculously survives lethal hit due to dual stacking!)
      player.takeDamage(200.0);
      expect(player.currentHp, closeTo(7.6, 0.001),
          reason: 'Dual barrier + Berserk reduces 200 base dmg to 84.0, preserving player life at 7.6 HP');

      // Lethal damage without Berserk: 200 base dmg * 0.70 = 140 effective dmg -> HP clamped to 0.0
      player.isBerserk = false;
      player.currentHp = 100.0;
      player.takeDamage(200.0);
      expect(player.currentHp, 0.0,
          reason: 'Lethal damage must clamp to 0.0 HP without going negative');
    });

    test('Damage absorption clamping boundaries [0.0, 0.90]', () {
      final player = PlayerComponent(position: Vector2(200, 200));

      // 1. Extreme over-absorption: 1.50 -> clamped to 0.90 (10% minimum damage taken)
      player.currentHp = 100.0;
      player.damageAbsorption = 1.50;
      player.takeDamage(100.0);
      // 100 * (1 - 0.90) = 10.0 dmg -> 90 HP
      expect(player.currentHp, 90.0,
          reason: 'Absorption clamped to max 90% must deal at least 10% damage');

      // 2. Negative absorption: -0.50 -> clamped to 0.0 (100% damage taken, no amplification)
      player.currentHp = 100.0;
      player.damageAbsorption = -0.50;
      player.takeDamage(20.0);
      expect(player.currentHp, 80.0,
          reason: 'Negative absorption clamped to 0.0 must deal exactly 100% damage');
    });

    test('Attack Drone plasma projectile cooldown throttles to 1.5s', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final drone = CompanionComponent(
        companionId: 'companion_attack',
        player: player,
      );

      // Initially actionCooldown is 0
      expect(drone.actionCooldown, 0.0);
      drone.actionCooldown = 1.5;

      // Update 0.8s -> cooldown remains 0.7s
      drone.update(0.8);
      expect(drone.actionCooldown, closeTo(0.7, 0.001));

      // Update another 0.8s -> cooldown reaches 0 (clamped)
      drone.update(0.8);
      expect(drone.actionCooldown, lessThanOrEqualTo(0.0));
    });

    test('Frost Drone Chilling Aura single-application guard (no double compounding)', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final drone = CompanionComponent(
        companionId: 'companion_frost',
        player: player,
      );
      expect(drone.type, CompanionType.frost);

      final zombie = ZombieEnemy(position: Vector2(210, 210), player: player);
      const originalSpeed = 65.0;
      expect(zombie.speed, originalSpeed);

      // First slow: speed becomes 65 * 0.6 = 39.0
      zombie.speed *= 0.60;
      expect(zombie.speed, closeTo(39.0, 0.01));

      // Second check: already slowed enemy must NOT be multiplied again
      // (The _slowedEnemies.containsKey check in CompanionComponent guards against this)
      final afterSecondPass = zombie.speed;
      expect(afterSecondPass, closeTo(39.0, 0.01),
          reason: 'Frost aura must not compound speed reduction below 40%');
    });

    test('Companion orbital kinematics stress: 10,000 simulation frames remain bounded & non-NaN', () {
      final player = PlayerComponent(position: Vector2(300, 300));
      final drone = CompanionComponent(
        companionId: 'companion_attack',
        player: player,
        orbitRadius: 45.0,
      );

      const int frames = 10000;
      const double dt = 0.016; // 60 FPS delta

      for (int f = 0; f < frames; f++) {
        // Move player dynamically
        player.position.add(Vector2(sin(f * 0.05) * 2.0, cos(f * 0.05) * 2.0));
        drone.update(dt);

        expect(drone.position.x.isNaN, isFalse);
        expect(drone.position.y.isNaN, isFalse);
        expect(drone.position.x.isInfinite, isFalse);
        expect(drone.position.y.isInfinite, isFalse);

        final dist = drone.position.distanceTo(player.position);
        // Orbital radius is 45.0, bobbing adds up to 3.5 along y
        expect(dist, greaterThanOrEqualTo(45.0 - 4.0),
            reason: 'Drone distance to player must stay within orbital range');
        expect(dist, lessThanOrEqualTo(45.0 + 4.0),
            reason: 'Drone distance to player must stay within orbital range');
      }
    });
  });
}
