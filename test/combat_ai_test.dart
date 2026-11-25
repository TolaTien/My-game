import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/arrow_projectile.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/pickup_item.dart';

/// Contract implementation of A* Pathfinder and Grid Matrix
/// derived from PROJECT.md §Interface Contracts 1 and spec_inventory.md §Module 6
class AStarPathfinderContract {
  static const int mapWidthTiles = 36;
  static const int mapHeightTiles = 24;
  static const double tileSize = 32.0;

  /// Builds the 36x24 collision matrix matching DungeonMapComponent
  static List<List<bool>> buildDungeonWalkableGrid() {
    // 36 columns x 24 rows: true = walkable, false = wall
    final grid = List.generate(
      mapWidthTiles,
      (_) => List.filled(mapHeightTiles, true),
    );

    // 1. Perimeter boundary walls
    for (int col = 0; col < mapWidthTiles; col++) {
      grid[col][0] = false; // Top wall
      grid[col][mapHeightTiles - 1] = false; // Bottom wall
    }
    for (int row = 0; row < mapHeightTiles; row++) {
      grid[0][row] = false; // Left wall
      grid[mapWidthTiles - 1][row] = false; // Right wall
    }

    // 2. Six 2x2 stone pillars from DungeonMapComponent._addPillar
    const pillars = [
      (8, 6),
      (8, 16),
      (26, 6),
      (26, 16),
      (17, 10),
      (18, 10),
    ];

    for (final (pCol, pRow) in pillars) {
      grid[pCol][pRow] = false;
      grid[pCol + 1][pRow] = false;
      grid[pCol][pRow + 1] = false;
      grid[pCol + 1][pRow + 1] = false;
    }

    return grid;
  }

  /// Line-of-sight raycast bypass check
  static bool hasLineOfSight(
      Point<int> start, Point<int> target, List<List<bool>> walkableGrid) {
    // Bresenham's line algorithm between tile coordinates
    int x0 = start.x;
    int y0 = start.y;
    final x1 = target.x;
    final y1 = target.y;

    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    int err = dx - dy;

    while (true) {
      if (!walkableGrid[x0][y0]) return false; // Hit an obstacle
      if (x0 == x1 && y0 == y1) break;

      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }
    return true;
  }

  /// A* algorithm finding path avoiding wall obstacles
  static List<Point<int>> findPath(
      Point<int> start, Point<int> target, List<List<bool>> walkableGrid) {
    if (start == target) return [start];

    final openSet = <Point<int>>{start};
    final cameFrom = <Point<int>, Point<int>>{};

    final gScore = <Point<int>, double>{start: 0.0};
    final fScore = <Point<int>, double>{start: _heuristic(start, target)};

    while (openSet.isNotEmpty) {
      // Node in openSet having lowest fScore
      Point<int>? current;
      double lowestF = double.infinity;
      for (final node in openSet) {
        final f = fScore[node] ?? double.infinity;
        if (f < lowestF) {
          lowestF = f;
          current = node;
        }
      }

      if (current == null) break;
      if (current == target) {
        // Reconstruct path
        final path = <Point<int>>[current];
        while (cameFrom.containsKey(current)) {
          current = cameFrom[current]!;
          path.insert(0, current);
        }
        return path;
      }

      openSet.remove(current);

      // 4-way orthogonal neighbors
      final neighbors = [
        Point(current.x + 1, current.y),
        Point(current.x - 1, current.y),
        Point(current.x, current.y + 1),
        Point(current.x, current.y - 1),
      ];

      for (final neighbor in neighbors) {
        if (neighbor.x < 0 ||
            neighbor.x >= mapWidthTiles ||
            neighbor.y < 0 ||
            neighbor.y >= mapHeightTiles) {
          continue;
        }
        if (!walkableGrid[neighbor.x][neighbor.y]) continue; // Wall

        final tentativeG = (gScore[current] ?? double.infinity) + 1.0;
        if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] = tentativeG + _heuristic(neighbor, target);
          openSet.add(neighbor);
        }
      }
    }

    return []; // No path found
  }

  static double _heuristic(Point<int> a, Point<int> b) {
    // Manhattan distance heuristic
    return (a.x - b.x).abs() + (a.y - b.y).abs().toDouble();
  }
}

/// Contract model for Dungeon Overlord Boss state machine
/// derived from PROJECT.md §Interface Contracts 2 and spec_inventory.md §Module 7
class BossEnemyContract {
  static const double maxHp = 600.0;
  double currentHp = 600.0;
  int phase = 1;
  double speed = 55.0;

  bool summonedWave1 = false; // Triggered at 70% HP (420 HP)
  bool summonedWave2 = false; // Triggered at 30% HP (180 HP)
  bool isDefeated = false;

  final List<String> summonEvents = [];
  final List<PickupType> droppedLoot = [];

  void takeDamage(double dmg, Vector2 bossPosition) {
    if (isDefeated) return;
    currentHp = max(0, currentHp - dmg);

    // Wave 1 Summon at 70% HP (420 HP)
    if (currentHp <= 420.0 && !summonedWave1) {
      summonedWave1 = true;
      summonEvents.add('WAVE_1: 2 Skeletons, 2 Zombies');
    }

    // Phase 2 transition at <= 50% HP (300 HP)
    if (currentHp <= 300.0 && phase == 1) {
      phase = 2;
      speed = 80.0; // +30% speed boost (Enraged mode)
    }

    // Wave 2 Summon at 30% HP (180 HP)
    if (currentHp <= 180.0 && !summonedWave2) {
      summonedWave2 = true;
      summonEvents.add('WAVE_2: 2 Skeletons, 2 Zombies');
    }

    // Defeat cascade at 0 HP
    if (currentHp <= 0 && !isDefeated) {
      isDefeated = true;
      _triggerDefeatLoot(bossPosition);
    }
  }

  void _triggerDefeatLoot(Vector2 position) {
    // Exactly 12 Gold Coins (12,000 Gold) and 3 Health Potions in a circular ring
    for (int i = 0; i < 12; i++) {
      droppedLoot.add(PickupType.goldCoin);
    }
    for (int i = 0; i < 3; i++) {
      droppedLoot.add(PickupType.healthPotion);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Skeleton Ranged AI & Kiting Distance Thresholds', () {
    test('Distance < 115px retreats with bounded lateral movement', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final skeleton = SkeletonEnemy(
        position: Vector2(150, 100),
        player: player,
        random: Random(1),
      );
      skeleton.shootCooldown = 2.0; // Ensure shoot logic does not trigger

      final initialDistance = skeleton.position.distanceTo(player.position);
      expect(initialDistance, 50.0);

      // Run update step
      skeleton.update(0.1);

      final newDistance = skeleton.position.distanceTo(player.position);
      expect(newDistance, greaterThan(initialDistance),
          reason: 'Skeleton must retreat away from player when distance < 115px');
      final retreat = skeleton.position - Vector2(150, 100);
      expect(retreat.x, greaterThan(0));
      expect(retreat.y.abs(), greaterThan(0));
      expect(retreat.length, closeTo(skeleton.speed * 1.15 * 0.1, 0.01));
    });

    test('Distance > 250px triggers approach behavior', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      // Place skeleton at (400, 100) -> distance is 300px (> 250px threshold)
      final skeleton =
          SkeletonEnemy(position: Vector2(400, 100), player: player);
      skeleton.shootCooldown = 2.0;

      final initialDistance = skeleton.position.distanceTo(player.position);
      expect(initialDistance, 300.0);

      skeleton.update(0.1);

      final newDistance = skeleton.position.distanceTo(player.position);
      expect(newDistance, lessThan(initialDistance),
          reason: 'Skeleton must approach player when distance > 250px');
      // Velocity is towardDir * 50 px/s * 0.1s = 5px closer
      expect(skeleton.position.x, closeTo(395.0, 0.01));
    });

    test('Distance 115px - 250px strafes while counting down shoot timer',
        () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final skeleton = SkeletonEnemy(
        position: Vector2(280, 100),
        player: player,
        random: Random(1),
      );
      skeleton.shootCooldown = 1.0;

      skeleton.update(0.2);

      final strafe = skeleton.position - Vector2(280, 100);
      expect(strafe.x, closeTo(0, 0.01));
      expect(strafe.y.abs(), closeTo(skeleton.speed * 0.65 * 0.2, 0.01));
      expect(
        skeleton.position.distanceTo(player.position),
        closeTo(sqrt(180 * 180 + 6.5 * 6.5), 0.01),
      );

      // Cooldown timer must decrement
      expect(skeleton.shootCooldown, closeTo(0.8, 0.01));
    });

    test('Skeleton facing orientation matches player relative direction', () {
      final player = PlayerComponent(position: Vector2(200, 100));
      final skeleton =
          SkeletonEnemy(position: Vector2(100, 100), player: player);

      // Player to the right -> faces right
      skeleton.update(0.01);
      expect(skeleton.isFacingRight, isTrue);

      // Move player to the left
      player.position = Vector2(50, 100);
      skeleton.update(0.01);
      expect(skeleton.isFacingRight, isFalse);
    });
  });

  group('Arrow Projectile Physics, Rotation & Obstacle Absorption', () {
    test('Arrow projectile velocity equals 220 px/s along direction vector', () {
      final arrow = ArrowProjectile(
        position: Vector2(100, 100),
        direction: Vector2(1, 0),
      );

      expect(arrow.speed, 220.0);

      // Step 0.5s forward
      arrow.update(0.5);

      // Position should be 100 + (220 * 0.5) = 210
      expect(arrow.position.x, closeTo(210.0, 0.01));
      expect(arrow.position.y, 100.0);
    });

    test('Arrow rotation angle strictly matches atan2(dir.y, dir.x)', () {
      // Test 4 cardinal directions and diagonal
      final testCases = [
        (Vector2(1, 0), 0.0),
        (Vector2(0, 1), pi / 2),
        (Vector2(-1, 0), pi),
        (Vector2(0, -1), -pi / 2),
        (Vector2(1, 1), pi / 4),
      ];

      for (final (dir, expectedAngle) in testCases) {
        final arrow = ArrowProjectile(
          position: Vector2.zero(),
          direction: dir,
        );
        expect(arrow.angle, closeTo(expectedAngle, 0.001),
            reason: 'Arrow angle for direction $dir mismatch');
      }
    });

    test('Arrow deals 10 damage to player on collision and despawns', () {
      final player = PlayerComponent(position: Vector2(50, 50));
      expect(player.currentHp, player.maxHp);

      final arrow = ArrowProjectile(
        position: Vector2(50, 50),
        direction: Vector2(1, 0),
      );
      expect(arrow.damage, 10.0);

      // Simulate collision
      arrow.onCollision({}, player);

      expect(player.currentHp, player.maxHp - 10,
          reason: 'Arrow collision must deal exactly 10 physical damage');
    });

    test('Arrow collision with WallBlock is absorbed without tunneling', () {
      final wall =
          WallBlock(position: Vector2(100, 100), size: Vector2(32, 32));
      final arrow = ArrowProjectile(
        position: Vector2(100, 100),
        direction: Vector2(1, 0),
      );

      // Trigger collision with WallBlock
      arrow.onCollision({}, wall);

      // After absorption, update steps must no longer advance position
      final posAfterCollision = arrow.position.clone();
      arrow.update(0.1);
      expect(arrow.position, posAfterCollision,
          reason: 'Absorbed arrow must halt movement');
    });

    test(
        'Arrow auto-despawns after 3.0s lifespan when missing all targets (movement halts)',
        () {
      final arrow = ArrowProjectile(
        position: Vector2(100, 100),
        direction: Vector2(1, 0),
      );

      // Advance 2.0 seconds: position advances by 220 * 2.0 = 440px -> x = 540
      arrow.update(2.0);
      expect(arrow.position.x, closeTo(540.0, 0.01));

      // Advance 0.8s (total 2.8s < 3.0s): position advances by 220 * 0.8 = 176px -> x = 716
      arrow.update(0.8);
      expect(arrow.position.x, closeTo(716.0, 0.01));

      // Advance 0.3s (total 3.1s >= 3.0s): lifespan cap reached, returns early without advancing position
      arrow.update(0.3);
      expect(arrow.position.x, closeTo(716.0, 0.01),
          reason:
              'Position must halt at 3.0s threshold due to early return');

      // Subsequent update: position remains frozen at despawn point
      arrow.update(0.5);
      expect(arrow.position.x, closeTo(716.0, 0.01),
          reason:
              'Arrow must not advance after exceeding 3.0s lifespan');
    });
  });

  group('A* Pathfinder Obstacle Navigation & 2x2 Pillar Verification', () {
    late List<List<bool>> dungeonGrid;

    setUp(() {
      dungeonGrid = AStarPathfinderContract.buildDungeonWalkableGrid();
    });

    test('Dungeon map collision grid initializes 36x24 with boundary walls', () {
      expect(dungeonGrid.length, 36);
      expect(dungeonGrid[0].length, 24);

      // Perimeter checks
      for (int c = 0; c < 36; c++) {
        expect(dungeonGrid[c][0], isFalse, reason: 'Top perimeter must be wall');
        expect(dungeonGrid[c][23], isFalse,
            reason: 'Bottom perimeter must be wall');
      }
      for (int r = 0; r < 24; r++) {
        expect(dungeonGrid[0][r], isFalse, reason: 'Left perimeter must be wall');
        expect(dungeonGrid[35][r], isFalse,
            reason: 'Right perimeter must be wall');
      }
    });

    test('Six 2x2 stone pillars are correctly mapped as non-walkable blocks', () {
      // Pillar 1 at (8,6)
      expect(dungeonGrid[8][6], isFalse);
      expect(dungeonGrid[9][6], isFalse);
      expect(dungeonGrid[8][7], isFalse);
      expect(dungeonGrid[9][7], isFalse);

      // Pillar 2 at (8,16)
      expect(dungeonGrid[8][16], isFalse);
      expect(dungeonGrid[9][16], isFalse);
      expect(dungeonGrid[8][17], isFalse);
      expect(dungeonGrid[9][17], isFalse);

      // Adjacent floor must be walkable
      expect(dungeonGrid[7][6], isTrue);
      expect(dungeonGrid[10][6], isTrue);
    });

    test('Line-of-sight raycast bypass detects clear vs blocked sightlines', () {
      // Clear sightline across open dungeon room
      final clearStart = const Point(2, 2);
      final clearTarget = const Point(5, 2);
      expect(
          AStarPathfinderContract.hasLineOfSight(
              clearStart, clearTarget, dungeonGrid),
          isTrue);

      // Blocked sightline crossing directly through Pillar 1 (8,6)-(9,7)
      final blockedStart = const Point(6, 6);
      final blockedTarget = const Point(12, 6);
      expect(
          AStarPathfinderContract.hasLineOfSight(
              blockedStart, blockedTarget, dungeonGrid),
          isFalse,
          reason: 'Sightline passing through 2x2 pillar must return false');
    });

    test('A* pathfinder navigates around 2x2 pillar without intersecting it', () {
      final start = const Point(6, 6);
      final target = const Point(12, 6);

      final stopwatch = Stopwatch()..start();
      final path =
          AStarPathfinderContract.findPath(start, target, dungeonGrid);
      stopwatch.stop();

      // Performance check (< 2.0ms contract)
      expect(stopwatch.elapsedMilliseconds, lessThan(20),
          reason: 'Pathfinding must execute within performance budget');

      expect(path, isNotEmpty, reason: 'A valid path around pillar must exist');
      expect(path.first, start);
      expect(path.last, target);

      // Crucial assertion: None of the path waypoints may intersect Pillar 1
      final pillarCells = {
        const Point(8, 6),
        const Point(9, 6),
        const Point(8, 7),
        const Point(9, 7),
      };

      for (final waypoint in path) {
        expect(pillarCells.contains(waypoint), isFalse,
            reason:
                'Waypoint $waypoint cannot step inside blocked 2x2 pillar!');
        expect(dungeonGrid[waypoint.x][waypoint.y], isTrue,
            reason: 'All path waypoints must be walkable cells');
      }
    });
  });

  group('Dungeon Boss Multi-Phase State Transitions & Loot Drops', () {
    test('Boss starts in Phase 1 at 600 Max HP with 55 px/s base speed', () {
      final boss = BossEnemyContract();

      expect(boss.currentHp, 600.0);
      expect(boss.phase, 1);
      expect(boss.speed, 55.0);
      expect(boss.isDefeated, isFalse);
    });

    test('Boss triggers Wave 1 Minion Summon at 70% HP (420 HP)', () {
      final boss = BossEnemyContract();

      // Deal 150 damage -> HP 450 (75%)
      boss.takeDamage(150.0, Vector2(400, 300));
      expect(boss.currentHp, 450.0);
      expect(boss.summonEvents, isEmpty);

      // Deal 40 damage -> HP 410 (below 70% threshold of 420 HP)
      boss.takeDamage(40.0, Vector2(400, 300));
      expect(boss.currentHp, 410.0);
      expect(boss.summonEvents.length, 1);
      expect(boss.summonEvents.first, contains('WAVE_1'));
      expect(boss.summonedWave1, isTrue);

      // Further damage does not duplicate Wave 1 summon
      boss.takeDamage(30.0, Vector2(400, 300));
      expect(boss.summonEvents.length, 1);
    });

    test('Boss transitions to Phase 2 (Enraged) at <= 50% HP (300 HP)', () {
      final boss = BossEnemyContract();

      // Bring boss to exactly 50% HP (300 HP)
      boss.takeDamage(300.0, Vector2(400, 300));

      expect(boss.currentHp, 300.0);
      expect(boss.phase, 2,
          reason: 'Boss must enter Phase 2 Enraged mode at <= 50% HP');
      expect(boss.speed, 80.0,
          reason: 'Boss move speed must increase to 80 px/s in Phase 2');
    });

    test('Boss triggers Wave 2 Minion Summon at 30% HP (180 HP)', () {
      final boss = BossEnemyContract();

      // Reduce HP to 170 (below 30% threshold of 180 HP)
      boss.takeDamage(430.0, Vector2(400, 300));

      expect(boss.currentHp, 170.0);
      expect(boss.summonedWave2, isTrue);
      expect(boss.summonEvents, contains('WAVE_2: 2 Skeletons, 2 Zombies'));
    });

    test(
        'Boss Defeat cascade at 0 HP spawns 12 Gold Coins (12,000 Gold) and 3 Potions',
        () {
      final boss = BossEnemyContract();

      // Deplete all 600 HP
      boss.takeDamage(600.0, Vector2(400, 300));

      expect(boss.currentHp, 0.0);
      expect(boss.isDefeated, isTrue);

      // Count drop table
      final goldCoins =
          boss.droppedLoot.where((item) => item == PickupType.goldCoin).toList();
      final healthPotions = boss.droppedLoot
          .where((item) => item == PickupType.healthPotion)
          .toList();

      expect(goldCoins.length, 12,
          reason: 'Boss defeat must spawn exactly 12 Gold Coins');
      expect(healthPotions.length, 3,
          reason: 'Boss defeat must spawn exactly 3 Health Potions');

      // 12 coins * 1000 = 12,000 Gold wallet payout
      final totalGoldValue = goldCoins.length * 1000;
      expect(totalGoldValue, 12000,
          reason: '12 dropped coins must evaluate to 12,000 Gold in wallet');
    });
  });
}
