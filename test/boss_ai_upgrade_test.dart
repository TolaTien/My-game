import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/ai/pvp_bot_ai.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/pvp_match.dart';

// Keep the production GoldRushGame type required by enemy game references,
// while isolating the actors under test from unrelated spawning and pickups.
class _AiGame extends GoldRushGame {
  final List<List<bool>> grid;
  _AiGame(this.grid);

  @override
  List<List<bool>> get walkableGrid => grid;

  @override
  Future<void> onLoad() async {
    await world.add(player);
  }
}

List<List<bool>> _openGrid() => List.generate(20, (_) => List.filled(20, true));

Future<_AiGame> _mount(WidgetTester tester, List<List<bool>> grid) async {
  final game = _AiGame(grid);
  await tester.pumpWidget(GameWidget(game: game));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  game.pauseEngine();
  expect(game.player.isMounted, isTrue);
  return game;
}

Future<void> _add(_AiGame game, Component actor, WidgetTester tester) async {
  await game.world.add(actor);
  await tester.runAsync(game.ready);
  expect(actor.isMounted, isTrue);
}

class _DodgeRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

PvpBotPlayerComponent _bot(
  PlayerComponent target, {
  BotDifficulty difficulty = BotDifficulty.goldPlatinum,
  int seed = 1,
  Random? random,
}) {
  return PvpBotPlayerComponent(
    position: Vector2(200, 200),
    targetPlayer: target,
    enableAi: false,
    random: random ?? Random(seed),
    opponentInfo: PvpOpponentInfo(
      name: 'Test Bot',
      rankPoints: 1600,
      rankTier: 'Gold',
      heroId: 'george',
      difficulty: difficulty,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Radial windup emits no damage; impact emits eight once then cools down',
    (tester) async {
      final game = await _mount(tester, _openGrid());
      final player = game.player..position = Vector2(380, 300);
      final boss =
          BossEnemy(
              position: Vector2(300, 300),
              player: player,
              random: Random(1),
            )
            ..phase = 2
            ..flameBurstCooldownTimer = 0
            ..groundSlamCooldownTimer = 100;
      await _add(game, boss, tester);
      final hp = player.currentHp;
      boss.update(0);
      expect(boss.state, BossState.radialFlameBurst);
      boss.update(BossEnemy.flameBurstTelegraphDuration - 0.001);
      await tester.runAsync(game.ready);
      expect(boss.state, BossState.radialFlameBurst);
      expect(game.world.children.whereType<BossFlameProjectile>(), isEmpty);
      expect(player.currentHp, hp);

      boss.update(0.002);
      await tester.runAsync(game.ready);
      expect(boss.state, BossState.radialFlameImpact);
      final flames = game.world.children
          .whereType<BossFlameProjectile>()
          .toList();
      expect(flames, hasLength(BossEnemy.flameBurstProjectileCount));
      expect(player.currentHp, hp, reason: 'Emission alone is not an AoE hit');
      for (int i = 0; i < flames.length; i++) {
        expect(flames[i].position, boss.position);
        expect(flames[i].direction, BossEnemy.flameDirection(i));
        expect(flames[i].speed, BossEnemy.flameBurstSpeed);
      }
      boss.update(0.01);
      expect(boss.state, BossState.radialFlameCooldown);
      boss.update(BossEnemy.flameBurstRecoveryDuration);
      expect(boss.state, BossState.chase);
      expect(boss.flameBurstCooldownTimer, greaterThan(0));
      await tester.runAsync(game.ready);
      expect(
        game.world.children.whereType<BossFlameProjectile>(),
        hasLength(8),
      );

      final flame = flames.first;
      flame.onCollision({}, player);
      flame.onCollision({}, player);
      expect(
        player.currentHp,
        hp - BossEnemy.flameBurstDamage,
        reason: 'One projectile cannot hit twice',
      );
      final blocked = flames[1];
      blocked.onCollision(
        {},
        WallBlock(position: Vector2.zero(), size: Vector2.all(32)),
      );
      blocked.onCollision({}, player);
      expect(player.currentHp, hp - BossEnemy.flameBurstDamage);
    },
  );

  for (final escaped in [false, true]) {
    testWidgets(
      'Engine collision hits radial lane; leaving it avoids damage: $escaped',
      (tester) async {
        final game = await _mount(tester, _openGrid());
        final player = game.player..position = Vector2(380, 300);
        final boss = BossEnemy(position: Vector2(300, 300), player: player)
          ..phase = 2
          ..flameBurstCooldownTimer = 0
          ..groundSlamCooldownTimer = 100;
        await _add(game, boss, tester);
        boss.update(0);
        final hp = player.currentHp;
        if (escaped) player.position = Vector2(380, 340);
        boss.update(BossEnemy.flameBurstTelegraphDuration);
        await tester.runAsync(game.ready);
        boss.removeFromParent();
        await tester.runAsync(game.ready);
        for (int i = 0; i < 50; i++) {
          game.update(0.02);
        }
        expect(
          player.currentHp,
          hp - (escaped ? 0 : BossEnemy.flameBurstDamage),
        );
      },
    );
  }

  for (final escaped in [false, true]) {
    testWidgets(
      'Slam locks its warning center and hits once; escaped=$escaped',
      (tester) async {
        final game = await _mount(tester, _openGrid());
        final player = game.player..position = Vector2(350, 300);
        final boss = BossEnemy(position: Vector2(200, 300), player: player)
          ..groundSlamCooldownTimer = 0;
        await _add(game, boss, tester);
        final hp = player.currentHp;
        boss.update(0);
        expect(boss.state, BossState.groundSlamTelegraph);
        final center = boss.groundSlamCenter!.clone();
        expect(boss.activeTelegraph!.position, center);
        expect(
          boss.activeTelegraph!.size,
          Vector2.all(BossEnemy.groundSlamAoERadius * 2),
        );
        if (escaped) {
          player.position =
              center + Vector2(BossEnemy.groundSlamAoERadius + 1, 0);
        }
        boss.update(BossEnemy.groundSlamTelegraphDuration - 0.001);
        expect(player.currentHp, hp);
        expect(boss.activeTelegraph!.position, center);
        boss.update(0.002);
        expect(boss.state, BossState.groundSlamImpact);
        expect(
          player.currentHp,
          hp - (escaped ? 0 : BossEnemy.groundSlamDamage),
        );
        boss.update(0.05);
        boss.update(0.05);
        expect(
          player.currentHp,
          hp - (escaped ? 0 : BossEnemy.groundSlamDamage),
        );
      },
    );
  }

  testWidgets(
    'Mounted zombie follows production A* around a pillar with large ticks',
    (tester) async {
      final grid = _openGrid();
      for (int col = 7; col <= 8; col++) {
        for (int row = 5; row <= 6; row++) {
          grid[col][row] = false;
        }
      }
      final game = await _mount(tester, grid);
      final player = game.player..position = Vector2(336, 176);
      final zombie = ZombieEnemy(
        position: Vector2(176, 176),
        player: player,
        random: Random(2),
      );
      await _add(
        game,
        WallBlock(position: Vector2(224, 160), size: Vector2.all(64)),
        tester,
      );
      await _add(game, zombie, tester);
      final trace = <String>[];
      for (int i = 0; i < 30; i++) {
        final before = zombie.position.clone();
        game.update(0.2);
        expect(
          AStarPathfinder.hasLineOfSight(before, zombie.position, grid),
          isTrue,
        );
        expect(before.distanceTo(zombie.position), lessThanOrEqualTo(13.001));
        trace.add('${zombie.position} / ${zombie.navigation.recoveryCount}');
      }
      expect(
        zombie.position.distanceTo(player.position),
        lessThan(27),
        reason: trace.join('; '),
      );
      expect(zombie.navigation.recoveryCount, 0);
      expect(zombie.navigation.repathCount, lessThan(20));
    },
  );

  testWidgets('Boss navigates a pillar with clearance for its larger body', (
    tester,
  ) async {
    final grid = _openGrid();
    for (int col = 7; col <= 8; col++) {
      for (int row = 5; row <= 6; row++) {
        grid[col][row] = false;
      }
    }
    final game = await _mount(tester, grid);
    final boss =
        BossEnemy(
            position: Vector2(176, 176),
            player: game.player..position = Vector2(336, 176),
            random: Random(7),
          )
          ..groundSlamCooldownTimer = 100
          ..meleeCooldownTimer = 100;
    await _add(
      game,
      WallBlock(position: Vector2(224, 160), size: Vector2.all(64)),
      tester,
    );
    await _add(game, boss, tester);
    for (int i = 0; i < 45; i++) {
      game.update(0.2);
    }
    expect(boss.position.distanceTo(game.player.position), lessThan(40));
    expect(boss.navigation.recoveryCount, 0);
  });

  testWidgets(
    'Unreachable targets stay behind walls with bounded periodic searches',
    (tester) async {
      final grid = _openGrid();
      grid[8] = List.filled(20, false);
      final game = await _mount(tester, grid);
      final player = game.player..position = Vector2(400, 200);
      final zombie = ZombieEnemy(
        position: Vector2(200, 200),
        player: player,
        random: Random(3),
      );
      final skeleton = SkeletonEnemy(
        position: Vector2(112, 200),
        player: player,
        random: Random(3),
      );
      final boss = BossEnemy(
        position: Vector2(200, 300),
        player: player,
        random: Random(3),
      )..groundSlamCooldownTimer = 100;
      for (final actor in [zombie, skeleton, boss]) {
        await _add(game, actor, tester);
      }
      final starts = [
        zombie.position.clone(),
        skeleton.position.clone(),
        boss.position.clone(),
      ];
      for (int i = 0; i < 300; i++) {
        zombie.update(0.02);
        skeleton.update(0.02);
        boss.update(0.02);
      }
      expect(zombie.position, starts[0]);
      expect(skeleton.position, starts[1]);
      expect(boss.position, starts[2]);
      for (final nav in [
        zombie.navigation,
        skeleton.navigation,
        boss.navigation,
      ]) {
        expect(nav.repathCount, inInclusiveRange(10, 15));
        expect(
          nav.recoveryCount,
          0,
          reason: 'No route is a search, not a physical stall',
        );
      }
    },
  );

  testWidgets(
    'Collision rollback causes recovery and bounded searching, then resumes',
    (tester) async {
      final game = await _mount(tester, _openGrid());
      final player = game.player..position = Vector2(400, 200);
      final zombie = ZombieEnemy(
        position: Vector2(200, 200),
        player: player,
        random: Random(4),
      );
      await _add(game, zombie, tester);
      final wall = WallBlock(
        position: Vector2(210, 200),
        size: Vector2.all(32),
      );
      var searched = false;
      for (int i = 0; i < 150; i++) {
        zombie.update(0.02);
        zombie.onCollision({}, wall);
        searched |= zombie.navigation.isSearching;
      }
      expect(zombie.position, Vector2(200, 200));
      expect(zombie.navigation.recoveryCount, greaterThanOrEqualTo(2));
      expect(zombie.navigation.repathCount, lessThan(10));
      expect(searched, isTrue);
      for (int i = 0; i < 150; i++) {
        zombie.update(0.02);
      }
      expect(zombie.position.x, greaterThan(250));
    },
  );

  testWidgets(
    'Standing archery and boss windup do not accumulate false stalls',
    (tester) async {
      final game = await _mount(tester, _openGrid());
      final player = game.player..position = Vector2(400, 300);
      final skeleton = SkeletonEnemy(
        position: Vector2(200, 300),
        player: player,
        random: Random(5),
      );
      final boss = BossEnemy(
        position: Vector2(250, 400),
        player: player,
        random: Random(5),
      )..groundSlamCooldownTimer = 0;
      await _add(game, skeleton, tester);
      await _add(game, boss, tester);
      boss.update(0);
      for (int i = 0; i < 55; i++) {
        skeleton.update(0.02);
        boss.update(0.02);
      }
      expect(skeleton.position, Vector2(200, 300));
      expect(skeleton.navigation.recoveryCount, 0);
      expect(skeleton.navigation.repathCount, 0);
      expect(boss.state, BossState.groundSlamTelegraph);
      expect(boss.navigation.recoveryCount, 0);
      boss.applyControl(stunDuration: 2);
      for (int i = 0; i < 90; i++) {
        boss.update(0.02);
      }
      expect(boss.groundSlamCenter, isNull);
      expect(boss.navigation.recoveryCount, 0);
    },
  );

  testWidgets('Knockback checks the body footprint and cannot cross a wall', (
    tester,
  ) async {
    final grid = _openGrid();
    grid[8] = List.filled(20, false);
    final game = await _mount(tester, grid);
    final zombie = ZombieEnemy(
      position: Vector2(220, 200),
      player: game.player,
    );
    await _add(game, zombie, tester);
    zombie.applyControl(knockback: 200, direction: Vector2(1, 0));
    expect(zombie.position.x, greaterThan(220));
    expect(zombie.position.x + 10, lessThan(256));
  });

  test('Production A* never appends blocked or out-of-bounds exact goals', () {
    final grid = _openGrid()..[8][8] = false;
    for (final goal in [Vector2(272, 272), Vector2(-20, 120)]) {
      final path = AStarPathfinder.findPath(Vector2(100, 100), goal, grid);
      expect(path, isNotEmpty);
      for (final point in path) {
        final (col, row) = AStarPathfinder.worldToGrid(point);
        expect(col, inInclusiveRange(0, 19));
        expect(row, inInclusiveRange(0, 19));
        expect(grid[col][row], isTrue);
      }
    }
  });

  for (final difficulty in BotDifficulty.values) {
    test('Bot visible attack response respects rank latency: $difficulty', () {
      final target = PlayerComponent(position: Vector2(280, 200));
      final bot = _bot(target, difficulty: difficulty, random: _DodgeRandom());
      final ai = bot.aiController;
      ai.decisionTimer = ai.decisionInterval - 0.001;
      target.isAttacking = true;
      ai.update(0.002);
      expect(
        ai.dodgeTimer,
        0,
        reason: 'A near-ready decision is not instant reflex',
      );
      ai.update(ai.decisionInterval - 0.001);
      expect(ai.dodgeTimer, 0);
      ai.update(0.002);
      if (difficulty == BotDifficulty.bronzeSilver) {
        expect(ai.dodgeTimer, 0);
      } else {
        expect(ai.currentState, BotCombatState.dodging);
        expect(ai.dodgeDirection.length, closeTo(1, 0.00001));
      }
    });
  }

  test('Seeded production bots ignore target Ki and hidden cooldown state', () {
    final low = PlayerComponent(position: Vector2(270, 200))..currentKi = 0;
    final high = PlayerComponent(position: Vector2(270, 200))..currentKi = 100;
    final a = _bot(low, seed: 17);
    final b = _bot(high, seed: 17);
    for (int i = 0; i < 20; i++) {
      low.currentKi = i.isEven ? 0 : 100;
      high.currentKi = i.isEven ? 100 : 0;
      low.skill1VisualCd = i.isEven ? 0 : 4;
      high.skill1VisualCd = i.isEven ? 4 : 0;
      a.aiController.update(0.1);
      b.aiController.update(0.1);
      expect(a.aiController.currentState, b.aiController.currentState);
      expect(a.moveDirection, b.moveDirection);
      expect(a.currentKi, b.currentKi);
      expect(a.aiController.dodgeTimer, 0);
    }
  });

  test(
    'Injected random reproduces bot aim and decisions across visible attacks',
    () {
      final targetA = PlayerComponent(position: Vector2(280, 200));
      final targetB = PlayerComponent(position: Vector2(280, 200));
      final a = _bot(targetA, seed: 42);
      final b = _bot(targetB, seed: 42);
      for (int i = 0; i < 40; i++) {
        targetA.isAttacking = targetB.isAttacking = i % 10 < 4;
        a.aiController.update(0.1);
        b.aiController.update(0.1);
        expect(a.aiController.currentState, b.aiController.currentState);
        expect(a.aiController.dodgeDirection, b.aiController.dodgeDirection);
        expect(a.moveDirection, b.moveDirection);
      }
    },
  );

  test('Bot basics reject repeated and disabled input and respect facing', () {
    final target = PlayerComponent(position: Vector2(230, 200));
    final bot = _bot(target)..isFacingRight = true;
    final hp = target.currentHp;
    bot.performBasicAttack();
    bot.performBasicAttack();
    expect(target.currentHp, hp - bot.damage);
    bot.isAttacking = false;
    bot.isFacingRight = false;
    bot.performBasicAttack();
    expect(target.currentHp, hp - bot.damage);
    bot.isAttacking = false;
    bot.actionsEnabled = false;
    bot.isFacingRight = true;
    bot.performBasicAttack();
    expect(target.currentHp, hp - bot.damage);
    bot.performBasicAttack(force: true);
    expect(
      target.currentHp,
      hp - bot.damage * 2,
      reason: 'Explicit network replay retains its forced action contract',
    );
  });
}
