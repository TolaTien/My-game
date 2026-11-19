import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/ai/chase_navigation.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pvp_arena_map.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';

MapAssetConfig _map(String id) =>
    MapAssetConfig.fromJson({'id': id, 'imageAsset': '', 'theme': id});

const _opponent = PvpOpponentInfo(
  name: 'Integration Bot',
  rankPoints: 1600,
  rankTier: 'Gold',
  heroId: 'george',
  difficulty: BotDifficulty.goldPlatinum,
);

class _MapGame extends FlameGame with HasCollisionDetection {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final id in [
    'sunken_golden_sanctum',
    'map_rung_cay',
    'map_bang',
    'map_dao_bang_gia',
  ]) {
    testWidgets('$id retains selected map and grid matches actual colliders', (
      tester,
    ) async {
      final game = _MapGame();
      final map = DungeonMapComponent(config: _map(id));
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() async {
        await game.toBeLoaded();
        await game.ready();
      });
      await game.world.add(map);
      await tester.runAsync(game.ready);
      game.pauseEngine();
      expect(map.mapConfig.id, id);
      final walls = map.children.whereType<WallBlock>().toList();
      expect(walls, isNotEmpty);
      for (var col = 0; col < map.walkableGrid.length; col++) {
        for (var row = 0; row < map.walkableGrid[col].length; row++) {
          final center = AStarPathfinder.gridToWorld(col, row);
          final blocked = walls.any(
            (wall) => ui.Rect.fromLTWH(
              wall.position.x,
              wall.position.y,
              wall.size.x,
              wall.size.y,
            ).contains(ui.Offset(center.x, center.y)),
          );
          expect(
            map.walkableGrid[col][row],
            !blocked,
            reason: '$id tile ($col,$row) must match collision geometry',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('Forest and island grids keep distinct main obstacles', () {
    final forest = DungeonMapComponent(config: _map('map_rung_cay'));
    final island = DungeonMapComponent(config: _map('map_dao_bang_gia'));
    final sanctum = DungeonMapComponent(config: _map('sunken_golden_sanctum'));
    expect(forest.walkableGrid[12][5], isFalse);
    expect(forest.walkableGrid[8][6], isTrue);
    expect(island.walkableGrid[3][10], isFalse);
    expect(island.walkableGrid[6][6], isFalse);
    expect(sanctum.walkableGrid[8][6], isFalse);
    expect(
      sanctum.walkableGrid[19][10],
      isTrue,
      reason: 'Do not restore the removed overlapping legacy sixth pillar',
    );
    final arena = PvpArenaMapComponent(mapConfig: _map('map_rung_cay'));
    expect(arena.mapConfig.id, 'map_rung_cay');
    expect(arena.pillarRects, PvpArenaMapComponent.defaultPillarRects);
  });

  test(
    'Both A* option names retain safe endpoints and reject non-finite input',
    () {
      final grid = List.generate(12, (_) => List.filled(12, true));
      grid[7][7] = false;
      for (final target in [Vector2(240, 240), Vector2(99999, 99999)]) {
        final path = AStarPathfinder.findPath(
          Vector2(80, 80),
          target,
          grid,
          allowDirectLineOfSight: false,
          useLineOfSightShortcut: false,
        );
        expect(path, isNotEmpty);
        expect(path.last, isNot(target));
        for (final point in path) {
          final (col, row) = AStarPathfinder.worldToGrid(point);
          expect(col, inInclusiveRange(0, 11));
          expect(row, inInclusiveRange(0, 11));
          expect(grid[col][row], isTrue);
        }
      }
      expect(
        AStarPathfinder.findPath(Vector2(double.nan, 1), Vector2(80, 80), grid),
        isEmpty,
      );
      expect(
        AStarPathfinder.findPath(
          Vector2(80, 80),
          Vector2(double.infinity, 1),
          grid,
        ),
        isEmpty,
      );
      expect(
        AStarPathfinder.hasLineOfSight(
          Vector2(80, 80),
          Vector2(double.nan, 1),
          grid,
        ),
        isFalse,
      );
      expect(
        AStarPathfinder.findPath(Vector2.zero(), Vector2(80, 80), [
          [true],
          [],
        ]),
        isEmpty,
      );
    },
  );

  test('Shared body-clearance cache invalidates mutation of the same grid', () {
    final grid = List.generate(14, (_) => List.filled(14, true));
    final first = ChaseNavigation.clearanceGrid(grid, Vector2(22, 28));
    final reused = ChaseNavigation.clearanceGrid(grid, Vector2(22, 28));
    expect(identical(first, reused), isTrue);
    grid[6][6] = false;
    final changed = ChaseNavigation.clearanceGrid(grid, Vector2(22, 28));
    expect(identical(changed, first), isFalse);
    expect(first[6][6], isTrue);
    expect(changed[6][6], isFalse);
    final nav = ChaseNavigation(random: Random(1), halfSize: Vector2(22, 28));
    expect(
      nav.step(
        position: Vector2(100, 100),
        target: Vector2(200, 200),
        grid: grid,
        speed: 80,
        dt: double.nan,
      ),
      Vector2.zero(),
    );
  });

  test('Body corridor rejects a path whose center misses the obstacle', () {
    final grid = List.generate(12, (_) => List.filled(12, true));
    grid[5][5] = false;
    final start = Vector2(130, 153);
    final end = Vector2(220, 153);
    expect(AStarPathfinder.hasLineOfSight(start, end, grid), isTrue);
    expect(
      ChaseNavigation.isBodyPathClear(
        start: start,
        end: end,
        halfSize: Vector2(12, 14),
        grid: grid,
      ),
      isFalse,
    );
  });

  test(
    'Main round gate and WIP action guards preserve explicit forced replay',
    () {
      final target = PlayerComponent(position: Vector2(230, 200));
      var fighting = false;
      final bot = PvpBotPlayerComponent(
        position: Vector2(200, 200),
        opponentInfo: _opponent,
        targetPlayer: target,
        enableAi: false,
        canAct: () => fighting,
        random: Random(2),
      )..isFacingRight = true;
      expect(bot.performBasicAttack(), isFalse);
      expect(target.currentHp, target.maxHp);
      fighting = true;
      expect(bot.performBasicAttack(), isTrue);
      final hp = target.currentHp;
      final elapsed = bot.visualAnimator.actionElapsed;
      expect(bot.performBasicAttack(), isFalse);
      expect(bot.visualAnimator.actionElapsed, elapsed);
      expect(target.currentHp, hp);
      bot.actionsEnabled = false;
      expect(bot.performBasicAttack(force: true), isTrue);
      expect(target.currentHp, hp - bot.damage);
      bot.currentHp = 0;
      expect(bot.performBasicAttack(force: true), isFalse);
    },
  );

  testWidgets('Mounted bot waits, routes around a main pillar, and attacks', (
    tester,
  ) async {
    final game = _MapGame();
    final map = PvpArenaMapComponent(mapConfig: _map('map_rung_cay'));
    final target = PlayerComponent(
      position: Vector2(580, 200),
      legacyPvpSkills: true,
    )..currentHp = 10000;
    var fighting = false;
    final bot = PvpBotPlayerComponent(
      position: Vector2(760, 200),
      opponentInfo: _opponent,
      targetPlayer: target,
      random: Random(8),
      canAct: () => fighting,
      getWalkableGrid: () => map.walkableGrid,
      getObstacleRects: () => map.obstacleRects,
      getInteriorObstacleRects: () => map.pillarRects,
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() async {
      await game.toBeLoaded();
      await game.ready();
    });
    await game.world.addAll([map, target, bot]);
    await tester.runAsync(game.ready);
    game.pauseEngine();
    for (var frame = 0; frame < 60; frame++) {
      game.update(1 / 60);
    }
    expect(bot.position, Vector2(760, 200));
    expect(target.currentHp, 10000);
    fighting = true;
    for (var frame = 0; frame < 360; frame++) {
      game.update(1 / 60);
      final body = ui.Rect.fromLTRB(
        bot.position.x - 12,
        bot.position.y - 10,
        bot.position.x + 12,
        bot.position.y + 18,
      );
      expect(map.obstacleRects.any(body.overlaps), isFalse);
    }
    expect(
      bot.position.x,
      lessThan(656),
      reason: 'bot must route around the pillar: ${bot.position}',
    );
    expect(
      target.currentHp,
      lessThan(10000),
      reason:
          'bot=${bot.position}, move=${bot.moveDirection}, state=${bot.aiController.currentState}, attackCD=${bot.aiController.basicAttackCooldown}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Round reset removes cast, stun and speech presentation state', () {
    final target = PlayerComponent(position: Vector2(400, 200));
    final bot = PvpBotPlayerComponent(
      position: Vector2(200, 200),
      opponentInfo: _opponent,
      targetPlayer: target,
      enableAi: false,
      random: Random(2),
    );
    bot.executeSkill1();
    bot.say('Test');
    bot.applyControl(stunDuration: 2);
    expect(bot.visualAnimator.isPlayingAction, isTrue);
    bot.resetRound(Vector2(300, 300));
    expect(bot.visualAnimator.isPlayingAction, isFalse);
    expect(bot.visualAnimator.actionDuration, 0);
    expect(bot.visualAnimator.gaitDistance, 0);
    expect(bot.attackTimer, 0);
    expect(bot.stunTimer, 0);
    expect(bot.speechBubbleTimer, 0);
    expect(bot.speechBubbleText, isNull);
    expect(bot.previousPosition, Vector2(300, 300));
  });

  test(
    'Arena keeps legacy network skills and rejects repeated/backward basics',
    () {
      final game = PvpArenaGame(
        opponentInfo: _opponent,
        playerCurrentRp: 1600,
        selectedMapConfig: _map('map_rung_cay'),
      );
      expect(game.currentMapConfig.id, 'map_rung_cay');
      expect(game.player.legacyPvpSkills, isTrue);
      game.matchState = PvpMatchState.fighting;
      game.player.isFacingRight = true;
      game.bot.position = game.player.position + Vector2(30, 0);
      var actions = 0;
      game.onLocalAction = (action, {text}) => actions++;
      final hp = game.bot.currentHp;
      game.onBasicAttack();
      final afterFirst = game.bot.currentHp;
      game.onBasicAttack();
      expect(afterFirst, lessThan(hp));
      expect(game.bot.currentHp, afterFirst);
      expect(actions, 1);
      game.player.isAttacking = false;
      game.player.isFacingRight = false;
      game.onBasicAttack();
      expect(game.bot.currentHp, afterFirst);
    },
  );
}
