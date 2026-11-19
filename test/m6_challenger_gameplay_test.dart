import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/ai/pvp_bot_ai.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/database_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // SECTION 1: A* PATHFINDER EXTREMES & BOUNDARY STRESS
  // ===========================================================================
  group('Adversarial Section 1: A* Pathfinder Extremes & Boundary Stress', () {
    late List<List<bool>> canonicalGrid;

    setUp(() {
      canonicalGrid = AStarPathfinder.buildDungeonWalkableGrid();
    });

    test('Zero Distance: Start point equals target point', () {
      final pos = Vector2(300.0, 300.0);
      final path = AStarPathfinder.findPath(pos, pos, canonicalGrid);

      expect(path.length, 1);
      expect(path.first.x, closeTo(pos.x, 0.001));
      expect(path.first.y, closeTo(pos.y, 0.001));
      expect(AStarPathfinder.hasLineOfSight(pos, pos, canonicalGrid), isTrue);
    });

    test('Zero Distance: Sub-pixel micro distance (< 0.5px) produces single waypoint', () {
      final start = Vector2(250.0, 250.0);
      final target = Vector2(250.2, 250.2);
      final path = AStarPathfinder.findPath(start, target, canonicalGrid);

      expect(path.length, 1);
      expect(path.first.distanceTo(target), closeTo(0.0, 0.001));
      expect(
        AStarPathfinder.hasLineOfSight(start, target, canonicalGrid),
        isTrue,
      );
    });

    test('Unreachable Goal: Target point completely enclosed by 4-wall solid barrier', () {
      // 15x15 custom grid with an isolated 1-tile room at (7, 7) sealed by walls
      final isolatedGrid = List.generate(15, (_) => List.filled(15, true));

      // Construct a sealed wall perimeter around (7, 7)
      for (int c = 6; c <= 8; c++) {
        for (int r = 6; r <= 8; r++) {
          if (c != 7 || r != 7) {
            isolatedGrid[c][r] = false; // Solid wall ring
          }
        }
      }
      isolatedGrid[7][7] = true; // Inner floor

      final startPos = Vector2(2.5 * 32, 2.5 * 32); // Outer open floor
      final targetPos = Vector2(7.5 * 32, 7.5 * 32); // Inner sealed room

      // LoS must be blocked
      expect(
        AStarPathfinder.hasLineOfSight(startPos, targetPos, isolatedGrid),
        isFalse,
      );

      // A* must gracefully exhaust heap and return empty path without crashing or looping
      final path = AStarPathfinder.findPath(startPos, targetPos, isolatedGrid);
      expect(path, isEmpty, reason: 'Enclosed goal must return empty list');
    });

    test(
      'Unreachable Goal: Start point completely enclosed inside sealed cell',
      () {
        final trappedGrid = List.generate(15, (_) => List.filled(15, true));
        // Seal (3, 3)
        for (int c = 2; c <= 4; c++) {
          for (int r = 2; r <= 4; r++) {
            if (c != 3 || r != 3) {
              trappedGrid[c][r] = false;
            }
          }
        }
        trappedGrid[3][3] = true;

        final startPos = Vector2(3.5 * 32, 3.5 * 32); // Trapped
        final targetPos = Vector2(10.5 * 32, 10.5 * 32); // Outside

        final path = AStarPathfinder.findPath(startPos, targetPos, trappedGrid);
        expect(
          path,
          isEmpty,
          reason: 'Trapped start cannot reach outside goal',
        );
      },
    );

    test(
      'Target inside solid wall block with no walkable tile within radius 4',
      () {
        // 20x20 grid where the entire right half (cols 10..19) is solid wall
        final halfWallGrid = List.generate(20, (c) => List.filled(20, c < 10));

        final startPos = Vector2(2.5 * 32, 2.5 * 32);
        final deepWallTarget = Vector2(
          18.5 * 32,
          18.5 * 32,
        ); // 8+ tiles away from any floor

        final path = AStarPathfinder.findPath(
          startPos,
          deepWallTarget,
          halfWallGrid,
        );
        expect(
          path,
          isEmpty,
          reason: 'Deep solid wall target has no walkable neighbor',
        );
      },
    );

    test(
      'Out of Bounds: Negative coordinates clamped safely without RangeError',
      () {
        final negStart = Vector2(-200.0, -450.0);
        final validTarget = Vector2(200.0, 200.0);

        // LoS with negative start must return false safely
        expect(
          AStarPathfinder.hasLineOfSight(negStart, validTarget, canonicalGrid),
          isFalse,
        );

        // findPath clamps negative coordinates to (0, 0) and finds nearest walkable
        final path = AStarPathfinder.findPath(
          negStart,
          validTarget,
          canonicalGrid,
        );
        expect(path, isNotEmpty);
        expect(path.last.distanceTo(validTarget), closeTo(0.0, 0.001));
      },
    );

    test('Out of Bounds: Huge target ends at a safe reachable tile', () {
      final validStart = Vector2(200.0, 200.0);
      final hugeTarget = Vector2(10000.0, 10000.0);

      expect(
        AStarPathfinder.hasLineOfSight(validStart, hugeTarget, canonicalGrid),
        isFalse,
      );

      final path = AStarPathfinder.findPath(
        validStart,
        hugeTarget,
        canonicalGrid,
      );
      expect(path, isNotEmpty);
      expect(path.last, isNot(hugeTarget));
      for (final point in path) {
        final (col, row) = AStarPathfinder.worldToGrid(point);
        expect(col, inInclusiveRange(0, canonicalGrid.length - 1));
        expect(row, inInclusiveRange(0, canonicalGrid[col].length - 1));
        expect(canonicalGrid[col][row], isTrue);
      }
    });

    test(
      'Out of Bounds: Both start and target completely outside grid bounds',
      () {
        final negStart = Vector2(-1000.0, -1000.0);
        final hugeTarget = Vector2(99999.0, 99999.0);

        final path = AStarPathfinder.findPath(
          negStart,
          hugeTarget,
          canonicalGrid,
        );
        expect(path, isNotEmpty);
        expect(path.last, isNot(hugeTarget));
        for (final point in path) {
          final (col, row) = AStarPathfinder.worldToGrid(point);
          expect(col, inInclusiveRange(0, canonicalGrid.length - 1));
          expect(row, inInclusiveRange(0, canonicalGrid[col].length - 1));
          expect(canonicalGrid[col][row], isTrue);
        }
      },
    );

    test(
      'Completely Closed Map: 100% impassable wall matrix returns empty path',
      () {
        final closedGrid = List.generate(12, (_) => List.filled(12, false));

        final start = Vector2(2.5 * 32, 2.5 * 32);
        final target = Vector2(9.5 * 32, 9.5 * 32);

        expect(
          AStarPathfinder.hasLineOfSight(start, target, closedGrid),
          isFalse,
        );
        final path = AStarPathfinder.findPath(start, target, closedGrid);
        expect(path, isEmpty);
      },
    );

    test(
      'Completely Closed Map: Identical blocked endpoints have no safe path',
      () {
        final closedGrid = List.generate(10, (_) => List.filled(10, false));
        final pos = Vector2(64.0, 64.0); // Exactly col 2, row 2

        final path = AStarPathfinder.findPath(pos, pos, closedGrid);
        expect(path, isEmpty);
      },
    );

    test('Empty Grid Matrix: List is empty or has empty row returns fallback target', () {
      final List<List<bool>> emptyGrid = [];
      final posA = Vector2(100, 100);
      final posB = Vector2(200, 200);

      expect(AStarPathfinder.hasLineOfSight(posA, posB, emptyGrid), isFalse);
      final path = AStarPathfinder.findPath(posA, posB, emptyGrid);
      expect(path.length, 1);
      expect(path.first, equals(posB));
    });

    test('Diagonal Barrier Stress: Touching wall corners prevent raycast penetration', () {
      // 10x10 grid with diagonal wall barrier touching at vertex (5*32, 5*32)
      // Wall 1 at (4, 4), Wall 2 at (5, 5).
      // Floor at (4, 5) and (5, 4).
      final diagGrid = List.generate(10, (_) => List.filled(10, true));
      diagGrid[4][4] = false;
      diagGrid[5][5] = false;

      final startPos = Vector2(4.5 * 32, 5.5 * 32); // Cell (4, 5)
      final targetPos = Vector2(5.5 * 32, 4.5 * 32); // Cell (5, 4)

      // Both points are on floor, but the line crosses through touching wall corners
      final hasLoS = AStarPathfinder.hasLineOfSight(
        startPos,
        targetPos,
        diagGrid,
      );
      expect(
        hasLoS,
        isFalse,
        reason: 'Raycast must not penetrate touching diagonal corners',
      );

      final reverseLoS = AStarPathfinder.hasLineOfSight(
        targetPos,
        startPos,
        diagGrid,
      );
      expect(
        reverseLoS,
        isFalse,
        reason: 'Reverse raycast must also be blocked',
      );
    });

    test('Narrow 1-Tile Diagonal Chokepoint: Checkerboard maze strictly enforces orthogonal clearance', () {
      // Checkerboard pattern:
      // (1, 1)=W, (2, 1)=F, (3, 1)=W
      // (1, 2)=F, (2, 2)=W, (3, 2)=F
      // (1, 3)=W, (2, 3)=F, (3, 3)=W
      final checkerGrid = List.generate(10, (_) => List.filled(10, true));
      checkerGrid[1][1] = false;
      checkerGrid[3][1] = false;
      checkerGrid[2][2] = false;
      checkerGrid[1][3] = false;
      checkerGrid[3][3] = false;

      final start = Vector2(2.5 * 32, 1.5 * 32); // (2, 1) floor
      final target = Vector2(1.5 * 32, 2.5 * 32); // (1, 2) floor

      // Diagonal transition from (2, 1) to (1, 2) would cut through (1, 1) and (2, 2)
      final path = AStarPathfinder.findPath(start, target, checkerGrid);
      expect(path, isNotEmpty);

      // Verify that NO step in the path illegally cuts diagonally through (1, 1) or (2, 2)
      for (int i = 0; i < path.length - 1; i++) {
        final (c1, r1) = AStarPathfinder.worldToGrid(path[i]);
        final (c2, r2) = AStarPathfinder.worldToGrid(path[i + 1]);
        if (c1 != c2 && r1 != r2) {
          expect(
            checkerGrid[c1][r2],
            isTrue,
            reason: 'Orthogonal corner 1 must be walkable for diagonal step',
          );
          expect(
            checkerGrid[c2][r1],
            isTrue,
            reason: 'Orthogonal corner 2 must be walkable for diagonal step',
          );
        }
      }
    });

    test('Path Invariant: All generated waypoints in canonical dungeon avoid cutting pillar corners', () {
      // Test 8 distinct traversals across canonical dungeon map with 6 stone pillars
      final routes = [
        (
          Vector2(6.5 * 32, 6.5 * 32),
          Vector2(11.5 * 32, 7.5 * 32),
        ), // Around Pillar 1
        (
          Vector2(11.5 * 32, 7.5 * 32),
          Vector2(6.5 * 32, 6.5 * 32),
        ), // Reverse Pillar 1
        (
          Vector2(6.5 * 32, 15.5 * 32),
          Vector2(11.5 * 32, 17.5 * 32),
        ), // Around Pillar 2
        (
          Vector2(24.5 * 32, 6.5 * 32),
          Vector2(28.5 * 32, 7.5 * 32),
        ), // Around Pillar 3
        (
          Vector2(24.5 * 32, 15.5 * 32),
          Vector2(28.5 * 32, 17.5 * 32),
        ), // Around Pillar 4
        (
          Vector2(15.5 * 32, 10.5 * 32),
          Vector2(20.5 * 32, 11.5 * 32),
        ), // Through center pillars
        (
          Vector2(3.5 * 32, 3.5 * 32),
          Vector2(32.5 * 32, 20.5 * 32),
        ), // Full diagonal cross
      ];

      for (final (from, to) in routes) {
        final path = AStarPathfinder.findPath(from, to, canonicalGrid);
        expect(path, isNotEmpty);

        for (int i = 0; i < path.length - 1; i++) {
          final (c1, r1) = AStarPathfinder.worldToGrid(path[i]);
          final (c2, r2) = AStarPathfinder.worldToGrid(path[i + 1]);

          // Any cell occupied by waypoint must be walkable (except clamped final target)
          if (c1 >= 0 && c1 < 36 && r1 >= 0 && r1 < 24) {
            expect(canonicalGrid[c1][r1], isTrue);
          }

          // If step is diagonal, both orthogonal neighbors must be walkable
          if (c1 != c2 && r1 != r2) {
            expect(
              canonicalGrid[c1][r2],
              isTrue,
              reason:
                  'Diagonal step from ($c1, $r1) to ($c2, $r2) cuts corner ($c1, $r2)',
            );
            expect(
              canonicalGrid[c2][r1],
              isTrue,
              reason:
                  'Diagonal step from ($c1, $r1) to ($c2, $r2) cuts corner ($c2, $r1)',
            );
          }
        }
      }
    });
  });

  // ===========================================================================
  // SECTION 2: BOSS COMBAT STATE MACHINE & MATH INVARIANTS
  // ===========================================================================
  group('Adversarial Section 2: Boss Combat State Machine & Math Invariants', () {
    test('Overkill Damage (1000 dmg on 10 HP): HP clamps to 0.0, defeat triggers once', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Reduce boss to 10 HP
      boss.takeDamage(590.0);
      expect(boss.currentHp, 10.0);
      expect(boss.isDefeated, isFalse);

      // Overkill with 1000 damage
      boss.takeDamage(1000.0);
      expect(
        boss.currentHp,
        0.0,
        reason: 'HP must clamp strictly to 0.0 without underflow',
      );
      expect(boss.isDefeated, isTrue);
      expect(boss.state, BossState.defeated);

      // Subsequent hits after defeat are completely ignored
      boss.takeDamage(500.0);
      expect(boss.currentHp, 0.0);
      expect(boss.isDefeated, isTrue);
    });

    testWidgets(
      'Overkill In-Game: Loot cascade and victory portal do not duplicate on repeated hits',
      (tester) async {
        final game = GoldRushGame(playerProfile: const PlayerProfile());
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();

        final boss = game.boss;
        expect(boss, isNotNull);
        expect(boss!.isMounted, isTrue);

        final initialPickups = game.pickups.length;

        // Bring boss to 10 HP
        boss.takeDamage(590.0);
        expect(boss.currentHp, 10.0);

        // Deal 1000 overkill damage
        boss.takeDamage(1000.0);
        await tester.pump();

        expect(boss.currentHp, 0.0);
        expect(boss.isDefeated, isTrue);

        // Exactly 15 pickups (12 gold coins + 3 potions) created
        final afterFirstDefeatPickups = game.pickups.length;
        expect(afterFirstDefeatPickups - initialPickups, 15);

        final victoryPortals = game.world.children
            .whereType<BossVictoryPortal>()
            .toList();
        expect(victoryPortals.length, 1);

        // Attempt repeated damage attacks on defeated boss in subsequent frames
        boss.takeDamage(500.0);
        boss.takeDamage(999.0);
        await tester.pump();

        expect(
          game.pickups.length,
          afterFirstDefeatPickups,
          reason: 'Loot cascade must NOT duplicate on subsequent damage',
        );
        expect(
          game.world.children.whereType<BossVictoryPortal>().length,
          1,
          reason: 'Victory portal must NOT duplicate',
        );

        game.onRemove();
      },
    );

    test('Phase 2 Enraged threshold at exactly 300.0 HP (50.0% of 600)', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // 1. Damage to 300.1 HP (Phase 1 retained)
      boss.takeDamage(299.9);
      expect(boss.currentHp, closeTo(300.1, 0.001));
      expect(boss.phase, 1);
      expect(boss.isEnraged, isFalse);
      expect(boss.currentSpeed, BossEnemy.speedPhase1);

      // 2. Damage 0.1 HP to reach exactly 300.0 HP (Phase 2 switch)
      boss.takeDamage(0.1);
      expect(boss.currentHp, closeTo(300.0, 0.001));
      expect(
        boss.phase,
        2,
        reason: 'Phase 2 must activate at exactly 50% (300.0 HP)',
      );
      expect(boss.isEnraged, isTrue);
      expect(boss.currentSpeed, BossEnemy.speedPhase2);

      // 3. Further damage keeps boss in Phase 2
      boss.takeDamage(50.0);
      expect(boss.phase, 2);
      expect(boss.isEnraged, isTrue);
    });

    test('Summon Wave 1 at exact 420.0 HP (70%): fires once and hovering does not re-summon', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Damage to 420.1 HP (Wave 1 not triggered)
      boss.takeDamage(179.9);
      expect(boss.currentHp, closeTo(420.1, 0.001));
      expect(boss.summonedWave70, isFalse);

      // Damage 0.1 to hit exactly 420.0 HP (Wave 1 triggered)
      boss.takeDamage(0.1);
      expect(boss.currentHp, closeTo(420.0, 0.001));
      expect(boss.summonedWave70, isTrue);

      // Hover at 420.0 HP with 0 damage and repeated micro-hits
      boss.takeDamage(0.0);
      expect(boss.summonedWave70, isTrue);

      boss.takeDamage(1.0);
      expect(boss.summonedWave70, isTrue);
    });

    test('Summon Wave 2 at exact 180.0 HP (30%): fires once and hovering does not re-summon', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Damage directly to 180.0 HP
      boss.takeDamage(420.0);
      expect(boss.currentHp, closeTo(180.0, 0.001));
      expect(boss.summonedWave70, isTrue);
      expect(boss.summonedWave30, isTrue);

      // Subsequent damage hovering below 180 HP does not reset or re-fire wave 2
      boss.takeDamage(0.0);
      boss.takeDamage(5.0);
      expect(boss.summonedWave30, isTrue);
    });

    testWidgets(
      'Wave summoning in-game spawns exact minion counts without duplication',
      (tester) async {
        final game = GoldRushGame(playerProfile: const PlayerProfile());
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();

        final boss = game.boss!;
        final initialSkeletons = game.skeletons.length;
        final initialZombies = game.enemies.length;

        // Hit exactly 420.0 HP: spawns 2 skeletons, 2 zombies
        boss.takeDamage(180.0);
        expect(boss.currentHp, 420.0);
        expect(game.skeletons.length, initialSkeletons + 2);
        expect(game.enemies.length, initialZombies + 2);

        // Hit 3 times hovering at 420 HP: verify zero additional spawns
        boss.takeDamage(0.0);
        boss.takeDamage(0.0);
        boss.takeDamage(0.0);
        expect(game.skeletons.length, initialSkeletons + 2);
        expect(game.enemies.length, initialZombies + 2);

        // Hit exactly 180.0 HP: spawns another 2 skeletons, 2 zombies
        boss.takeDamage(240.0);
        expect(boss.currentHp, 180.0);
        expect(game.skeletons.length, initialSkeletons + 4);
        expect(game.enemies.length, initialZombies + 4);

        // Hover at 180 HP
        boss.takeDamage(0.0);
        expect(game.skeletons.length, initialSkeletons + 4);
        expect(game.enemies.length, initialZombies + 4);

        game.onRemove();
      },
    );

    test('Massive single hit (450 dmg from 600 HP) flags both waves and phase 2 simultaneously', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // 600 - 450 = 150 HP (crosses 420 HP, 300 HP, and 180 HP thresholds in 1 call)
      boss.takeDamage(450.0);

      expect(boss.currentHp, 150.0);
      expect(boss.phase, 2);
      expect(boss.isEnraged, isTrue);
      expect(boss.summonedWave70, isTrue);
      expect(boss.summonedWave30, isTrue);
      expect(boss.isDefeated, isFalse);
    });

    test('Hardening Verification: Negative damage clamped to maxHp (prevents HP overflow)', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final boss = BossEnemy(position: Vector2(500, 500), player: player);

      // Passing negative damage (accidental negative damage calculation)
      boss.takeDamage(-100.0);

      // Hardened implementation clamps currentHp to [0.0, maxHp]
      expect(
        boss.currentHp,
        boss.maxHp,
        reason: 'Hardened defense: Boss takeDamage clamps currentHp so it cannot exceed maxHp',
      );
      expect(boss.currentHp <= boss.maxHp, isTrue);
    });
  });

  // ===========================================================================
  // SECTION 3: PVP BOT AI & ELO CALCULATIONS
  // ===========================================================================
  group('Adversarial Section 3: PvP Bot AI & Intercept Math Safeguards', () {
    test('Predictive Intercept: Target velocity is (0, 0) produces valid normalized direction', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      final botPos = Vector2(100.0, 100.0);
      final targetPos = Vector2(250.0, 100.0);
      final zeroVel = Vector2.zero();

      final dir = ai.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: zeroVel,
        projectileSpeed: 160.0,
      );

      expect(dir.x.isNaN, isFalse);
      expect(dir.y.isNaN, isFalse);
      expect(dir.x.isInfinite, isFalse);
      expect(dir.y.isInfinite, isFalse);
      expect(dir.length, closeTo(1.0, 0.001));
      expect(dir.x, closeTo(1.0, 0.001)); // Directed along positive X
      expect(dir.y, closeTo(0.0, 0.001));
    });

    test('Predictive Intercept: Projectile speed is 0.0 handles division by zero safely', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      final botPos = Vector2(100.0, 100.0);
      final targetPos = Vector2(200.0, 200.0);
      final targetVel = Vector2(50.0, -50.0);

      final dir = ai.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: targetVel,
        projectileSpeed: 0.0, // Zero projectile speed
      );

      expect(dir.x.isNaN, isFalse);
      expect(dir.y.isNaN, isFalse);
      expect(dir.x.isInfinite, isFalse);
      expect(dir.y.isInfinite, isFalse);
      expect(dir.length, closeTo(1.0, 0.001));
    });

    test('Predictive Intercept: Negative projectile speed handles safely without invalid lead', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      final botPos = Vector2(100.0, 100.0);
      final targetPos = Vector2(300.0, 100.0);
      final targetVel = Vector2(100.0, 0.0);

      final dir = ai.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: targetVel,
        projectileSpeed: -80.0, // Negative speed
      );

      expect(dir.x.isNaN, isFalse);
      expect(dir.length, closeTo(1.0, 0.001));
    });

    test('Predictive Intercept: Identical bot and target positions return safe default vector (1, 0)', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      final samePos = Vector2(200.0, 200.0);

      final dir = ai.calculateAimDirection(
        botPosition: samePos,
        targetPosition: samePos,
        targetVelocity: Vector2.zero(),
        projectileSpeed: 160.0,
      );

      expect(dir.x.isNaN, isFalse);
      expect(dir.y.isNaN, isFalse);
      expect(dir, equals(Vector2(1, 0)));
    });

    test('Predictive Intercept Comparison: Diamond leads target while Bronze aims directly', () {
      final diamondAi = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      final bronzeAi = PvpBotAi(difficulty: BotDifficulty.bronzeSilver);

      final botPos = Vector2(100.0, 100.0);
      final targetPos = Vector2(100.0, 300.0); // Directly below bot
      final targetVel = Vector2(200.0, 0.0); // Moving fast to the right

      // Bronze aims directly at target position with fixed RNG seed (0 error)
      final rng = Random(42);
      final bronzeDir = bronzeAi.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: targetVel,
        projectileSpeed: 200.0,
        random: rng,
      );

      final diamondDir = diamondAi.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: targetVel,
        projectileSpeed: 200.0,
      );

      // Bronze aims towards (100, 300) -> dir.x ~ 0, dir.y > 0 (subject to error)
      expect(bronzeDir.length, closeTo(1.0, 0.001));
      expect(
        bronzeDir.y,
        greaterThan(0.0),
        reason: 'Bronze AI aims downward towards target',
      );
      // Diamond leads ahead in X direction -> dir.x > 0 significantly
      expect(
        diamondDir.x,
        greaterThan(0.5),
        reason: 'Diamond AI must lead target in direction of movement',
      );
    });

    test('Elo Calculator: Bronze loss mitigation and 0 RP floor', () {
      // 1. Loss at 1000 RP (Bronze): -5 RP
      final res1000 = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1000,
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 60),
      );
      expect(res1000.isWinner, isFalse);
      expect(res1000.rpDelta, -5);
      expect(res1000.newRankPoints, 995);

      // 2. Loss at 3 RP: -5 RP drops to exactly 0 RP (floor rule)
      final res3 = PvpEloCalculator.calculateResult(
        playerCurrentRp: 3,
        playerRoundsWon: 1,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 70),
      );
      expect(res3.rpDelta, -5);
      expect(res3.newRankPoints, 0, reason: 'RP must not become negative (-2)');

      // 3. Loss at 0 RP: stays at 0 RP
      final res0 = PvpEloCalculator.calculateResult(
        playerCurrentRp: 0,
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 45),
      );
      expect(res0.rpDelta, -5);
      expect(res0.newRankPoints, 0);
    });

    test('Elo Calculator: 2-0 Clean sweep awards maximum bonus (+35 RP)', () {
      final resSweep = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1500,
        playerRoundsWon: 2,
        opponentRoundsWon: 0,
        matchDuration: const Duration(seconds: 75),
      );
      expect(resSweep.isWinner, isTrue);
      expect(
        resSweep.rpDelta,
        35,
        reason: 'Clean sweep 2-0 awards 30 + 5 = 35 RP',
      );
      expect(resSweep.newRankPoints, 1535);
      expect(resSweep.goldReward, 1500);

      // 2-1 Win awards standard +30 RP
      final resStandard = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1500,
        playerRoundsWon: 2,
        opponentRoundsWon: 1,
        matchDuration: const Duration(seconds: 110),
      );
      expect(resStandard.rpDelta, 30);
      expect(resStandard.newRankPoints, 1530);
    });

    test('Elo Calculator: Silver+ defeat deducts full -20 RP', () {
      final resSilver = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1200,
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 80),
      );
      expect(resSilver.rpDelta, -20);
      expect(resSilver.newRankPoints, 1180);
      expect(resSilver.oldRankTier, 'Bạc');
      expect(resSilver.newRankTier, 'Đồng');
      expect(
        resSilver.isPromotion,
        isFalse,
        reason: 'Demotion must not flag promotion',
      );
    });

    test('Win Rate Calculation: 0 matches played handled safely without division by zero', () {
      // Test empirical win rate helper formula
      String computeWinRate(int wins, int totalMatches) {
        if (totalMatches <= 0) return '0%';
        final percent = (wins / totalMatches) * 100;
        return '${percent.clamp(0.0, 100.0).toStringAsFixed(0)}%';
      }

      // Edge case: 0 matches played
      expect(computeWinRate(0, 0), '0%');
      expect(computeWinRate(5, 0), '0%');
      expect(computeWinRate(-1, 0), '0%');

      // Normal cases
      expect(computeWinRate(10, 20), '50%');
      expect(computeWinRate(3, 4), '75%');
      expect(computeWinRate(10, 10), '100%');
      expect(computeWinRate(0, 10), '0%');
    });

    test(
      'LeaderboardEntry deserializes gracefully with null or missing winRate',
      () {
        final entryNullWinRate = LeaderboardEntry.fromJson({
          'uid': 'test_player',
          'name': 'Test',
          'rankPoints': 1400,
          'winRate': null, // Missing winRate
        });
        expect(
          entryNullWinRate.winRate,
          '50%',
          reason: 'Null winRate must fallback to 50%',
        );

        final entryZeroRp = LeaderboardEntry.fromJson({
          'uid': 'test_zero',
          'name': 'Zero',
          'rankPoints': 0,
          'winRate': '0%',
        });
        expect(entryZeroRp.rankPoints, 0);
        expect(entryZeroRp.winRate, '0%');
      },
    );
  });

  // ===========================================================================
  // SECTION 4: KI CONSERVATION & BOT RESOURCE DISCIPLINE
  // ===========================================================================
  group('Adversarial Section 4: Ki Conservation & Bot Resource Discipline', () {
    test('PvpBotAi strictly guards canCastSkill against insufficient Ki', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);

      // 1. Zero Ki
      expect(ai.canCastSkill1(0.0), isFalse);
      expect(ai.canCastSkill2(0.0), isFalse);
      expect(ai.canCastSkill3(0.0), isFalse);

      // 2. Skill 1 boundary: 24.99 Ki vs 25.0 Ki
      expect(ai.canCastSkill1(24.99), isFalse);
      expect(ai.canCastSkill1(25.0), isTrue);
      expect(ai.canCastSkill2(25.0), isFalse);
      expect(ai.canCastSkill3(25.0), isFalse);

      // 3. Skill 2 boundary: 34.99 Ki vs 35.0 Ki
      expect(ai.canCastSkill2(34.99), isFalse);
      expect(ai.canCastSkill2(35.0), isTrue);
      expect(ai.canCastSkill3(35.0), isFalse);

      // 4. Skill 3 boundary: 39.99 Ki vs 40.0 Ki
      expect(ai.canCastSkill3(39.99), isFalse);
      expect(ai.canCastSkill3(40.0), isTrue);

      // 5. Cooldown gate: Sufficient Ki (100) but cooldown active
      ai.skill1Cooldown = 2.0;
      expect(ai.canCastSkill1(100.0), isFalse);
      ai.skill1Cooldown = 0.0;
      expect(ai.canCastSkill1(100.0), isTrue);
    });

    test('PvpBotPlayerComponent directly rejects skill execution when Ki < skill cost', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final bot = PvpBotPlayerComponent(
        position: Vector2(110, 100), // In point-blank melee range
        opponentInfo: const PvpOpponentInfo(
          name: 'BotTest',
          rankPoints: 1600,
          rankTier: 'Bạch Kim',
          heroId: 'george',
          difficulty: BotDifficulty.diamondChallenger,
        ),
        targetPlayer: player,
      );

      final initialPlayerHp = player.currentHp;

      // 1. Try Skill 1 with 20 Ki (< 25 Ki)
      bot.currentKi = 20.0;
      bot.executeSkill1();
      expect(bot.currentKi, 20.0, reason: 'Ki must NOT be deducted');
      expect(
        player.currentHp,
        initialPlayerHp,
        reason: 'Damage must NOT be dealt',
      );

      // 2. Try Skill 2 with 30 Ki (< 35 Ki)
      bot.currentKi = 30.0;
      bot.executeSkill2();
      expect(bot.currentKi, 30.0);
      expect(player.currentHp, initialPlayerHp);

      // 3. Try Skill 3 with 35 Ki (< 40 Ki)
      bot.currentKi = 35.0;
      bot.executeSkill3();
      expect(bot.currentKi, 35.0);
      expect(bot.isBerserk, isFalse);

      // 4. Successful Skill 1 deduction
      bot.currentKi = 25.0;
      bot.executeSkill1();
      expect(bot.currentKi, 0.0);
      expect(player.currentHp, lessThan(initialPlayerHp));
    });

    test('Skill 3 Berserk Recast Guard: Cannot recast while Berserk is already active', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final bot = PvpBotPlayerComponent(
        position: Vector2(110, 100),
        opponentInfo: const PvpOpponentInfo(
          name: 'BerserkBot',
          rankPoints: 2100,
          rankTier: 'Thách Đấu',
          heroId: 'george',
          difficulty: BotDifficulty.diamondChallenger,
        ),
        targetPlayer: player,
      );

      bot.currentKi = 100.0;
      bot.executeSkill3();

      expect(bot.currentKi, 60.0); // 100 - 40
      expect(bot.isBerserk, isTrue);
      expect(bot.berserkTimer, 8.0);

      // Simulate 2 seconds into berserk
      bot.berserkTimer = 6.0;

      // Attempt to recast Skill 3 while already Berserk
      bot.executeSkill3();
      expect(
        bot.currentKi,
        60.0,
        reason: 'Ki must NOT be deducted on recast attempt',
      );
      expect(
        bot.berserkTimer,
        6.0,
        reason: 'Active timer must NOT reset prematurely',
      );
    });

    test('Diamond Bot AI Tactics: Conserves Ki and does not execute combo skills when Ki is depleted', () {
      final player = PlayerComponent(position: Vector2(100, 100));
      final bot = PvpBotPlayerComponent(
        position: Vector2(140, 100), // Within melee range
        opponentInfo: const PvpOpponentInfo(
          name: 'ChallengerBot',
          rankPoints: 2200,
          rankTier: 'Thách Đấu',
          heroId: 'george',
          difficulty: BotDifficulty.diamondChallenger,
        ),
        targetPlayer: player,
      );

      final initialPlayerHp = player.currentHp;

      // Deplete bot Ki to 5.0
      bot.currentKi = 5.0;

      // Run tactical evaluation
      bot.aiController.evaluateTactics();

      // Bot cannot execute skills 1, 2, or 3 due to insufficient Ki
      expect(bot.currentKi, 5.0, reason: 'Ki must remain untouched');
      expect(bot.isBerserk, isFalse);

      // Bot can only perform basic attack if ready, dealing base damage at most
      if (player.currentHp < initialPlayerHp) {
        // Must be basic attack damage (20.0), NOT skill 1 (36.0) or skill 2 (50.0)
        final dmgDealt = initialPlayerHp - player.currentHp;
        expect(dmgDealt, closeTo(bot.damage, 0.01));
      }
    });
  });
}
