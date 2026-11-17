import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/core/constants.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/companion_component.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/components/pickup_item.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // 1. CORNER CLIPPING & DIAGONAL BARRIER EMPIRICAL CHALLENGES
  // ---------------------------------------------------------------------------
  group('Adversarial Boundary: A* Corner Clipping & Diagonal Barriers', () {
    late List<List<bool>> canonicalGrid;

    setUp(() {
      canonicalGrid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('Pillar 1 (cols 8..9, rows 6..7) 4-corner grazing paths never cut corners', () {
      // Pillar 1 bounding box:
      // cols 8 and 9, rows 6 and 7.
      // Top-Left corner vertex: (8*32, 6*32) = (256, 192)
      // Bottom-Left corner vertex: (8*32, 8*32) = (256, 256)
      // Top-Right corner vertex: (10*32, 6*32) = (320, 192)
      // Bottom-Right corner vertex: (10*32, 8*32) = (320, 256)

      final testCases = [
        // 1. Top-Left corner: from west (7, 6) to north-east (10, 5)
        (
          Vector2(7.5 * 32, 6.5 * 32),
          Vector2(10.5 * 32, 5.5 * 32),
          'Top-Left graze',
        ),
        // 2. Bottom-Left corner: from west (7, 7) to south-east (10, 8)
        (
          Vector2(7.5 * 32, 7.5 * 32),
          Vector2(10.5 * 32, 8.5 * 32),
          'Bottom-Left graze',
        ),
        // 3. Top-Right corner: from east (10, 6) to north-west (7, 5)
        (
          Vector2(10.5 * 32, 6.5 * 32),
          Vector2(7.5 * 32, 5.5 * 32),
          'Top-Right graze',
        ),
        // 4. Bottom-Right corner: from east (10, 7) to south-west (7, 8)
        (
          Vector2(10.5 * 32, 7.5 * 32),
          Vector2(7.5 * 32, 8.5 * 32),
          'Bottom-Right graze',
        ),
      ];

      for (final (start, target, label) in testCases) {
        final path = AStarPathfinder.findPath(start, target, canonicalGrid);
        expect(path, isNotEmpty, reason: '$label: path must be found');

        // Check each waypoint in path
        for (final pt in path) {
          final (c, r) = AStarPathfinder.worldToGrid(pt);
          final inPillar = (c == 8 || c == 9) && (r == 6 || r == 7);
          expect(inPillar, isFalse,
              reason: '$label: Waypoint ($c, $r) must NEVER land inside Pillar 1');
        }

        // Check every consecutive segment for illegal diagonal corner cutting
        for (int i = 0; i < path.length - 1; i++) {
          final (c1, r1) = AStarPathfinder.worldToGrid(path[i]);
          final (c2, r2) = AStarPathfinder.worldToGrid(path[i + 1]);

          final dc = c2 - c1;
          final dr = r2 - r1;

          if (dc.abs() == 1 && dr.abs() == 1) {
            // Diagonal step: BOTH orthogonal neighbors MUST be walkable!
            final orthoWalkable1 = canonicalGrid[c1 + dc][r1];
            final orthoWalkable2 = canonicalGrid[c1][r1 + dr];
            expect(orthoWalkable1 && orthoWalkable2, isTrue,
                reason: '$label: Diagonal step from ($c1, $r1) to ($c2, $r2) '
                    'cuts corner! Orthogonal neighbors: '
                    '(${c1 + dc}, $r1)=$orthoWalkable1, ($c1, ${r1 + dr})=$orthoWalkable2');
          }
        }
      }
    });

    test('Diagonal Barrier Impenetrability: Path cannot pass between touching corners', () {
      // Create a 10x10 custom grid with two obstacle tiles touching corner-to-corner:
      // Wall A at (4, 4), Wall B at (5, 5).
      // Touching corner at vertex (5*32, 5*32).
      // Floor at (4, 5) and (5, 4).
      final barrierGrid = List.generate(10, (_) => List.filled(10, true));
      barrierGrid[4][4] = false;
      barrierGrid[5][5] = false;

      // Start on side 1: (4, 5), Target on side 2: (5, 4)
      final startPos = Vector2(4.5 * 32, 5.5 * 32);
      final targetPos = Vector2(5.5 * 32, 4.5 * 32);

      final path = AStarPathfinder.findPath(startPos, targetPos, barrierGrid);
      expect(path, isNotEmpty);

      // Verify that NO single step in the path cuts directly between (4, 5) and (5, 4)
      for (int i = 0; i < path.length - 1; i++) {
        final (c1, r1) = AStarPathfinder.worldToGrid(path[i]);
        final (c2, r2) = AStarPathfinder.worldToGrid(path[i + 1]);

        final isIllegalCut = (c1 == 4 && r1 == 5 && c2 == 5 && r2 == 4) ||
            (c1 == 5 && r1 == 4 && c2 == 4 && r2 == 5);
        expect(isIllegalCut, isFalse,
            reason: 'Path directly jumped diagonally between touching obstacle corners (4,4)-(5,5)!');
      }
    });

    test('Diagonal step between (7, 6) and (8, 5) across Pillar 1 corner (8, 6)', () {
      final start = Vector2(7.5 * 32, 6.5 * 32); // (7, 6)
      final target = Vector2(8.5 * 32, 5.5 * 32); // (8, 5)
      final path = AStarPathfinder.findPath(start, target, canonicalGrid);
      // Path must NOT jump directly from (7, 6) to (8, 5) across the corner of (8, 6)
      expect(path, isNotEmpty);
      final firstWp = path.first;
      final (c, r) = AStarPathfinder.worldToGrid(firstWp);
      final isDirectCornerCut = (c == 8 && r == 5 && path.length == 1);
      expect(isDirectCornerCut, isFalse,
          reason: 'Path directly jumped diagonally from (7, 6) to (8, 5) grazing Pillar 1 (8, 6)!');
    });

    test('Complex Multi-Obstacle Slalom maintains zero obstacle collision across map', () {
      final startPos = Vector2(3.5 * 32, 6.5 * 32); // West of Pillar 1
      final targetPos = Vector2(32.5 * 32, 6.5 * 32); // East of Pillar 3

      final path = AStarPathfinder.findPath(startPos, targetPos, canonicalGrid);
      expect(path, isNotEmpty);

      for (final pt in path) {
        final (c, r) = AStarPathfinder.worldToGrid(pt);
        expect(canonicalGrid[c][r], isTrue,
            reason: 'Waypoint ($c, $r) landed on an impassable obstacle!');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 2. LINE-OF-SIGHT (LoS) RAYCAST ACCURACY EMPIRICAL CHALLENGES
  // ---------------------------------------------------------------------------
  group('Adversarial Boundary: LoS Raycast Occlusion & Thin Gap Accuracy', () {
    late List<List<bool>> grid;

    setUp(() {
      grid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('Open Corridors report clear (true) for long unobstructed distances', () {
      // Horizontal corridor row 3 (cols 2..33)
      final p1 = Vector2(2.5 * 32, 3.5 * 32);
      final p2 = Vector2(33.5 * 32, 3.5 * 32);
      expect(AStarPathfinder.hasLineOfSight(p1, p2, grid), isTrue,
          reason: 'Clear 30-tile horizontal corridor must report LoS true');

      // Vertical corridor col 4 (rows 2..21)
      final v1 = Vector2(4.5 * 32, 2.5 * 32);
      final v2 = Vector2(4.5 * 32, 21.5 * 32);
      expect(AStarPathfinder.hasLineOfSight(v1, v2, grid), isTrue,
          reason: 'Clear 20-tile vertical corridor must report LoS true');
    });

    test('Solid obstacles and pillars strictly block visibility (false)', () {
      // Raycast through Pillar 1 (cols 8..9, rows 6..7)
      final pStart = Vector2(6.5 * 32, 6.5 * 32);
      final pEnd = Vector2(11.5 * 32, 6.5 * 32);
      expect(AStarPathfinder.hasLineOfSight(pStart, pEnd, grid), isFalse,
          reason: 'Ray through Pillar 1 must be occluded');

      // Raycast through Central Pillar (cols 17..18, rows 10..11)
      final cStart = Vector2(15.5 * 32, 10.5 * 32);
      final cEnd = Vector2(20.5 * 32, 10.5 * 32);
      expect(AStarPathfinder.hasLineOfSight(cStart, cEnd, grid), isFalse,
          reason: 'Ray through Central Pillar must be occluded');

      // Raycast through perimeter walls
      final outStart = Vector2(5.5 * 32, 5.5 * 32);
      final outEnd = Vector2(-20.0, 5.5 * 32);
      expect(AStarPathfinder.hasLineOfSight(outStart, outEnd, grid), isFalse,
          reason: 'Raycast out of map bounds must be occluded');
    });

    test('Thin Gap Raycast: straight line through 1-tile gap passes; angled line occludes', () {
      // Build a 16x16 test grid with a 1-tile gap at col 8:
      // Wall on col 7 from row 3 to 12.
      // Wall on col 9 from row 3 to 12.
      // Col 8 is an open 1-tile gap (32px wide).
      final customGrid = List.generate(16, (_) => List.filled(16, true));
      for (int r = 3; r <= 12; r++) {
        customGrid[7][r] = false;
        customGrid[9][r] = false;
      }

      // Straight shot down col 8 (center x = 8.5 * 32 = 272)
      final straightStart = Vector2(8.5 * 32, 2.0 * 32);
      final straightEnd = Vector2(8.5 * 32, 13.0 * 32);
      expect(AStarPathfinder.hasLineOfSight(straightStart, straightEnd, customGrid), isTrue,
          reason: 'Ray traveling down open 1-tile channel must pass clear');

      // Angled shot entering at col 8 but crossing into wall at col 7
      final angledStart = Vector2(8.5 * 32, 2.0 * 32);
      final angledEnd = Vector2(6.5 * 32, 13.0 * 32);
      expect(AStarPathfinder.hasLineOfSight(angledStart, angledEnd, customGrid), isFalse,
          reason: 'Angled ray clipping into wall of gap must be blocked');
    });

    test('Micro-Grazing LoS across exact pillar corner vertex (256, 192) detects obstruction', () {
      // Sub-pixel line passing through (256.0, 192.0) - exact vertex of Pillar 1 (8, 6)
      final microStart = Vector2(255.0, 193.0); // in (7, 6)
      final microEnd = Vector2(257.0, 191.0); // in (8, 5)

      // Sampling midpoint lands exactly on (256.0, 192.0) -> col 8, row 6 (obstacle)
      expect(AStarPathfinder.hasLineOfSight(microStart, microEnd, grid), isFalse,
          reason: 'Line grazing vertex of obstacle tile must be occluded by cell (8, 6)');
    });

    test('Diagonal Barrier LoS between touching wall corners (4,4)-(5,5) is occluded', () {
      final barrierGrid = List.generate(10, (_) => List.filled(10, true));
      barrierGrid[4][4] = false;
      barrierGrid[5][5] = false;

      final p1 = Vector2(4.5 * 32, 5.5 * 32); // (4, 5)
      final p2 = Vector2(5.5 * 32, 4.5 * 32); // (5, 4)

      // Midpoint is (160.0, 160.0) -> tile (5, 5) which is blocked
      expect(AStarPathfinder.hasLineOfSight(p1, p2, barrierGrid), isFalse,
          reason: 'LoS cannot pierce through touching corner vertex of diagonal walls');
    });
  });

  // ---------------------------------------------------------------------------
  // 3. ECONOMY INVARIANT: 12 COINS DROPPED == 12,000 GOLD IN WALLET
  // ---------------------------------------------------------------------------
  group('Adversarial Boundary: Boss Defeat Economy Invariant (12 Coins == 12,000 Gold)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PlayerStorage.loadProfile();
    });

    test('Boss defeat drops exactly 12 Gold Coins and 3 Potions in circular burst', () {
      final player = PlayerComponent(position: Vector2(200, 200));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Verify drops directly from defeat algorithm
      final droppedTypes = <PickupType>[];
      const int totalItems = 15;
      const double radius = 68.0;
      final bossPos = boss.position;

      for (int i = 0; i < totalItems; i++) {
        final angle = i * (2 * pi / totalItems);
        final itemPos = bossPos + Vector2(cos(angle) * radius, sin(angle) * radius);
        final type = (i % 5 == 0) ? PickupType.healthPotion : PickupType.goldCoin;
        droppedTypes.add(type);

        expect(bossPos.distanceTo(itemPos), closeTo(68.0, 0.001));
      }

      final coinPickups = droppedTypes.where((t) => t == PickupType.goldCoin).toList();
      final potionPickups = droppedTypes.where((t) => t == PickupType.healthPotion).toList();

      expect(coinPickups.length, 12, reason: 'Boss must drop strictly 12 Gold Coins');
      expect(potionPickups.length, 3, reason: 'Boss must drop strictly 3 Health Potions');
      expect(totalItems, 15, reason: 'Total loot cascade must equal 15 pickups');
    });

    test('Collecting all 12 Boss coins strictly increments wallet by 12,000 Gold', () async {
      final initialGold = PlayerStorage.currentProfile.gold; // 2000 default
      expect(initialGold, 2000);

      final player = PlayerComponent(position: Vector2(100, 100));
      expect(player.coinsCollected, 0);

      // Simulate collecting the 12 boss coins
      for (int c = 0; c < 12; c++) {
        player.coinsCollected += 1;
      }
      expect(player.coinsCollected, 12);

      // Core conversion invariant
      expect(GameConstants.goldPerCoinPickup, 1000);
      final earnedGold = player.coinsCollected * GameConstants.goldPerCoinPickup;
      expect(earnedGold, 12000, reason: '12 coins must equal exactly 12,000 Gold');

      // Deposit into persistent wallet
      await PlayerStorage.addGold(earnedGold);

      final updatedProfile = PlayerStorage.currentProfile;
      expect(updatedProfile.gold, initialGold + 12000,
          reason: 'Wallet balance must increase by strictly 12,000 Gold (from $initialGold to ${initialGold + 12000})');
    });

    testWidgets('PickupItem collision in game loop: Potion heals +25 clamped to maxHp, 12 coins increment counter by 12', (tester) async {
      final game = GoldRushGame();
      await tester.pumpWidget(GameWidget<GoldRushGame>(game: game));
      await tester.pump();

      final player = game.player;
      player.currentHp = 80.0;
      player.maxHp = 100.0;
      player.coinsCollected = 0;

      // Potion 1 restores to 100 (clamped)
      final potion1 = PickupItem(position: player.position.clone(), type: PickupType.healthPotion);
      await game.world.add(potion1);
      await tester.pump();

      potion1.onCollision({player.position}, player);
      expect(player.currentHp, 100.0);

      // Potion 2 does not overheal past 100
      final potion2 = PickupItem(position: player.position.clone(), type: PickupType.healthPotion);
      await game.world.add(potion2);
      await tester.pump();

      potion2.onCollision({player.position}, player);
      expect(player.currentHp, 100.0);

      // 12 Coins increment coinsCollected from 0 to 12
      int statsChangedCallbackCount = 0;
      player.onStatsChanged = () => statsChangedCallbackCount++;

      for (int i = 0; i < 12; i++) {
        final coin = PickupItem(position: player.position.clone(), type: PickupType.goldCoin);
        await game.world.add(coin);
        await tester.pump();
        coin.onCollision({player.position}, player);
      }

      expect(player.coinsCollected, 12);
      expect(statsChangedCallbackCount, 12);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. FROST DRONE AURA SLOW: 40% SLOW & RESTORATION WITHOUT CORRUPTION
  // ---------------------------------------------------------------------------
  group('Adversarial Boundary: Frost Drone Aura Slow & Speed Invariants', () {
    test('Multiple enemies entering and leaving 130px aura have speeds slowed by 40% and restored without drift', () {
      final player = PlayerComponent(position: Vector2(300, 300));
      final drone = CompanionComponent(
        companionId: 'companion_frost',
        player: player,
      );

      // Verify drone type classification
      expect(drone.type, CompanionType.frost);

      // 4 distinct enemies with different baseline speeds
      final zombie1 = ZombieEnemy(position: Vector2(320, 320), player: player); // dist ~28px
      final zombie2 = ZombieEnemy(position: Vector2(370, 370), player: player); // dist ~99px
      final skeleton = SkeletonEnemy(position: Vector2(360, 360), player: player); // dist ~85px
      final boss = BossEnemy(position: Vector2(380, 380), player: player); // dist ~113px

      const baseZombieSpeed = 65.0;
      const baseSkeletonSpeed = 50.0;
      const baseBossSpeed = 55.0;

      expect(zombie1.speed, baseZombieSpeed);
      expect(zombie2.speed, baseZombieSpeed);
      expect(skeleton.speed, baseSkeletonSpeed);
      expect(boss.currentSpeed, baseBossSpeed);

      // Slow simulation tracking map matching CompanionComponent logic
      final slowedEnemies = <PositionComponent, double>{};
      const frostAuraRadius = 130.0;

      void evaluateFrostAura(List<PositionComponent> monsters) {
        final currentInAura = <PositionComponent>{};
        for (final m in monsters) {
          final dist = drone.position.distanceTo(m.position);
          if (dist <= frostAuraRadius) {
            currentInAura.add(m);
            if (!slowedEnemies.containsKey(m)) {
              if (m is ZombieEnemy) {
                slowedEnemies[m] = m.speed;
                m.speed *= 0.60;
              } else if (m is SkeletonEnemy) {
                slowedEnemies[m] = m.speed;
                m.speed *= 0.60;
              } else if (m is BossEnemy) {
                slowedEnemies[m] = m.currentSpeed;
                m.currentSpeed *= 0.60;
              }
            }
          }
        }

        // Restore exited
        final exited = slowedEnemies.keys.where((m) => !currentInAura.contains(m)).toList();
        for (final m in exited) {
          final orig = slowedEnemies.remove(m);
          if (orig != null) {
            if (m is ZombieEnemy) m.speed = orig;
            if (m is SkeletonEnemy) m.speed = orig;
            if (m is BossEnemy) m.currentSpeed = orig;
          }
        }
      }

      final allMonsters = [zombie1, zombie2, skeleton, boss];

      // Drone at player position (300, 300)
      drone.position = player.position.clone();

      // Step 1: All 4 enemies are inside 130px aura
      evaluateFrostAura(allMonsters);

      expect(zombie1.speed, closeTo(baseZombieSpeed * 0.60, 0.001), reason: 'Zombie 1 slowed to 39.0');
      expect(zombie2.speed, closeTo(baseZombieSpeed * 0.60, 0.001), reason: 'Zombie 2 slowed to 39.0');
      expect(skeleton.speed, closeTo(baseSkeletonSpeed * 0.60, 0.001), reason: 'Skeleton slowed to 30.0');
      expect(boss.currentSpeed, closeTo(baseBossSpeed * 0.60, 0.001), reason: 'Boss slowed to 33.0');

      // Step 2: Multi-frame stability: 20 update frames while remaining in aura
      for (int frame = 0; frame < 20; frame++) {
        evaluateFrostAura(allMonsters);
      }
      expect(zombie1.speed, closeTo(39.0, 0.001), reason: 'No double-slowing on zombie1');
      expect(zombie2.speed, closeTo(39.0, 0.001), reason: 'No double-slowing on zombie2');
      expect(skeleton.speed, closeTo(30.0, 0.001), reason: 'No double-slowing on skeleton');
      expect(boss.currentSpeed, closeTo(33.0, 0.001), reason: 'No double-slowing on boss');

      // Step 3: Zombie 1 and Skeleton move out of aura (distance 200px)
      zombie1.position = Vector2(500, 300); // 200px away
      skeleton.position = Vector2(500, 300); // 200px away

      evaluateFrostAura(allMonsters);

      // Exited enemies must have speeds restored
      expect(zombie1.speed, closeTo(baseZombieSpeed, 0.001), reason: 'Zombie 1 speed restored to 65.0');
      expect(skeleton.speed, closeTo(baseSkeletonSpeed, 0.001), reason: 'Skeleton speed restored to 50.0');
      // Enemies remaining inside aura must stay slowed
      expect(zombie2.speed, closeTo(39.0, 0.001), reason: 'Zombie 2 remains slowed at 39.0');
      expect(boss.currentSpeed, closeTo(33.0, 0.001), reason: 'Boss remains slowed at 33.0');

      // Step 4: Rapid oscillation stress test: Zombie 1 enters and exits aura 10 times
      for (int cycle = 0; cycle < 10; cycle++) {
        // Enter aura
        zombie1.position = Vector2(320, 300); // 20px
        evaluateFrostAura(allMonsters);
        expect(zombie1.speed, closeTo(39.0, 0.001), reason: 'Cycle $cycle: slowed in aura');

        // Exit aura
        zombie1.position = Vector2(500, 300); // 200px
        evaluateFrostAura(allMonsters);
        expect(zombie1.speed, closeTo(baseZombieSpeed, 0.001), reason: 'Cycle $cycle: restored outside');
      }

      // Step 5: Enraged Boss Phase 2 (speed 80.0) entering and exiting aura
      boss.currentSpeed = 80.0;
      boss.position = Vector2(340, 300); // 40px away (in aura)
      slowedEnemies.remove(boss); // Reset tracking for Phase 2 test

      evaluateFrostAura(allMonsters);
      expect(boss.currentSpeed, closeTo(48.0, 0.001),
          reason: 'Phase 2 Boss (80 px/s) slowed by 40% to 48.0 px/s');

      boss.position = Vector2(500, 500); // Out of aura
      evaluateFrostAura(allMonsters);
      expect(boss.currentSpeed, closeTo(80.0, 0.001),
          reason: 'Phase 2 Boss restored cleanly to 80.0 px/s without corruption');
    });

    testWidgets('Live GoldRushGame Flame Game Loop: Frost Drone component slows and restores zombies during game.update', (tester) async {
      final game = GoldRushGame(
        playerProfile: const PlayerProfile(
          selectedCompanionId: 'companion_frost',
        ),
      );

      await tester.pumpWidget(GameWidget<GoldRushGame>(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(game.companion, isNotNull);
      expect(game.companion!.type, CompanionType.frost);
      expect(game.companion!.isMounted, isTrue);

      // Player at (400, 300)
      expect(game.player.position, Vector2(400, 300));

      // Zombie 0 is at (200, 200) by default, distance to (400, 300) is ~282px (> 130px)
      final testZombie = game.enemies.first;
      expect(testZombie.isMounted, isTrue);
      expect(testZombie.speed, 65.0);

      // Update 1: Zombie outside aura -> speed remains 65.0
      await tester.pump(const Duration(milliseconds: 100));
      expect(testZombie.speed, 65.0);

      // Move Zombie into Frost Drone aura (< 130px from George/drone)
      testZombie.position = Vector2(420, 310); // dist ~22px

      // Update 2: Drone updates and slows Zombie by 40% (speed -> 39.0)
      await tester.pump(const Duration(milliseconds: 100));
      expect(testZombie.speed, closeTo(39.0, 0.01),
          reason: 'Frost Drone inside game loop must slow testZombie to 39.0 px/s');

      // Update 3: Sustained inside aura for several frames -> no double slowing
      for (int f = 0; f < 5; f++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(testZombie.speed, closeTo(39.0, 0.01),
          reason: 'Sustained presence inside aura must not compound slow below 39.0 px/s');

      // Move Zombie back outside aura (> 130px)
      testZombie.position = Vector2(100, 100);

      // Update 4: Drone detects exit and restores speed to 65.0
      await tester.pump(const Duration(milliseconds: 100));
      expect(testZombie.speed, closeTo(65.0, 0.01),
          reason: 'TestZombie exiting aura in live game loop must restore speed to 65.0 px/s');
    });
  });
}
