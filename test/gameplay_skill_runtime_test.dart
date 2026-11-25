import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/core/game_keyboard_controller.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/floating_combat_text.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/game/hud/game_hud.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';

import 'support/legacy_pve_fixture.dart';

const heroes = [
  'george',
  'nova_blade',
  'shadow_01',
  'ember_02',
  'valeria',
  'garrick',
  'kaelen',
  'ranger',
  'tanker',
  'ninja',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAudioService audio;
  setUpAll(() async {
    await GameAssetRegistry.instance.initialize();
    expect(GameAssetRegistry.instance.skills.length, 30);
  });
  setUp(() {
    audio = MockAudioService();
    AudioService.setInstance(audio);
  });

  bool cast(PlayerComponent player, int slot) => switch (slot) {
    1 => player.useSkill1(),
    2 => player.useSkill2(),
    _ => player.useSkill3(),
  };

  for (final hero in heroes) {
    for (var slot = 1; slot <= 3; slot++) {
      test(
        '$hero slot$slot enforces production Ki/cooldown and action guards',
        () {
          final player = PlayerComponent(
            position: Vector2.zero(),
            heroId: hero,
          );
          final config = GameAssetRegistry.instance.getSkillForHeroSlot(
            hero,
            slot,
          )!;
          expect(player.skillConfig(slot), same(config));
          player.currentKi = config.kiCost - 0.01;
          expect(cast(player, slot), isFalse);
          expect(player.skillRuntime(slot).cooldownRemaining, 0);
          expect(
            audio.callHistory.where((event) => event.method == 'playSfx'),
            isEmpty,
          );
          player.currentKi = config.kiCost;
          expect(cast(player, slot), isTrue);
          expect(player.currentKi, closeTo(0, 0.000001));
          expect(player.skillRuntime(slot).cooldownRemaining, config.cooldown);
          final visualBefore = player.skill1TrailTimer;
          expect(cast(player, slot), isFalse);
          expect(player.currentKi, 0);
          expect(player.skill1TrailTimer, visualBefore);
          expect(
            audio.callHistory
                .where((event) => event.method == 'playSfx')
                .length,
            1,
          );
          player.update(config.cooldown + 0.001);
          player.currentKi = config.kiCost;
          player.actionsEnabled = false;
          expect(cast(player, slot), isFalse);
          player.actionsEnabled = true;
          player.currentHp = 0;
          expect(cast(player, slot), isFalse);
          player.currentHp = player.maxHp;
          expect(cast(player, slot), isTrue);
        },
      );
    }
  }

  test('Configured timed buffs expire without erasing progression or other shields', () {
    final player = PlayerComponent(position: Vector2.zero(), userHeroLevel: 10);
    expect(player.skillConfig(3).id, 'george_berserk');
    expect(player.useSkill3(), isTrue);
    expect(player.isBerserk, isTrue);
    expect(player.berserkTimer, 6);
    expect(player.skill3VisualCd, 13);
    expect(player.effectiveDamage, closeTo(player.damage * 1.55, 0.00001));
    player.gainExp(100);
    final progressedDamage = player.damage;
    final progressedSpeed = player.speed;
    player.damageAbsorption = 0.3;
    player.currentHp = player.maxHp;
    player.takeDamage(20);
    expect(player.currentHp, closeTo(player.maxHp - 20 * .7 * .6, .00001));
    player.update(6);
    expect(player.isBerserk, isFalse);
    expect(player.damage, progressedDamage);
    expect(player.speed, progressedSpeed);
    expect(player.effectiveDamage, progressedDamage);
    expect(player.damageAbsorption, .3);
  });

  testWidgets(
    'HUD costs, names and touch/keyboard casts share the same runtime',
    (tester) async {
      final profile = PlayerProfile.defaultProfile().copyWith(
        selectedHeroId: 'kaelen',
      );
      final game = GoldRushGame(
        playerProfile: profile,
        selectedMapConfig: legacyTestMap,
      );
      final keyboard = GameKeyboardController(
        onMoveDirectionChanged: game.setPlayerMoveDirection,
        onBasicAttack: game.onBasicAttack,
        onSkill1: game.onSkill1,
        onSkill2: game.onSkill2,
        onSkill3: game.onSkill3,
      );
      keyboard.attach();
      addTearDown(keyboard.detach);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameHudOverlay(game: game, keyboardController: keyboard),
          ),
        ),
      );
      expect(find.text('30 Ki'), findsOneWidget);
      expect(find.text('55 Ki'), findsOneWidget);
      expect(find.text('90 Ki'), findsOneWidget);
      expect(find.byTooltip(game.player.skillConfig(1).name), findsOneWidget);
      final expectedKi = game.player.maxKi - 30;
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      expect(game.player.currentKi, expectedKi);
      await tester.tap(find.byKey(const Key('pve_skill_1')));
      expect(game.player.currentKi, expectedKi);
      expect(game.player.skill1VisualCd, 5);
      game.player.update(5.001);
      game.player.currentKi = 30;
      await tester.pump();
      await tester.tap(find.byKey(const Key('pve_skill_1')));
      expect(game.player.currentKi, 0);
      expect(game.player.skill1VisualCd, 5);
    },
  );

  for (final hero in ['ember_02', 'nova_blade']) {
    testWidgets(
      '$hero projectile has delayed impact and respects piercing once per target',
      (tester) async {
        final game = GoldRushGame(
          selectedMapConfig: legacyTestMap,
          playerProfile: PlayerProfile.defaultProfile().copyWith(
            selectedHeroId: hero,
          ),
        );
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        game.player.position = Vector2(400, 300);
        final first = game.enemies.first;
        final second = game.enemies.last;
        first.position = Vector2(450, 300);
        second.position = Vector2(500, 300);
        first.currentHp = second.currentHp = 1000;
        game.onSkill1();
        expect(first.currentHp, 1000);
        await tester.pump();
        game.pauseEngine();
        final shots = game.world.children.whereType<HeroProjectile>().toList();
        final projectile = hero == 'ember_02' ? shots[1] : shots.single;
        projectile.update(1);
        final damage =
            game.player.damage * game.player.skillConfig(1).damageMultiplier;
        expect(first.currentHp, closeTo(1000 - damage, .00001));
        expect(
          second.currentHp,
          hero == 'nova_blade' ? closeTo(1000 - damage, .00001) : 1000,
        );
        projectile.update(1);
        expect(first.currentHp, closeTo(1000 - damage, .00001));
      },
    );
  }

  testWidgets(
    'Dash respects walls and hits a traversed target once with stun',
    (tester) async {
      final game = GoldRushGame(
        selectedMapConfig: legacyTestMap,
        playerProfile: PlayerProfile.defaultProfile().copyWith(
          selectedHeroId: 'kaelen',
        ),
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.player.position = Vector2(400, 300);
      final target = game.enemies.first;
      target.position = Vector2(450, 300);
      target.currentHp = 1000;
      game.onSkill1();
      expect(game.player.position.x, 580);
      expect(
        target.currentHp,
        closeTo(1000 - game.player.damage * 1.8, .00001),
      );
      final frozen = target.position.clone();
      target.update(.1);
      expect(target.position, frozen);
      game.player.resetCombatState();
      game.player.currentKi = 100;
      game.player.position = Vector2(500, 336);
      game.onSkill1();
      expect(game.player.position.x, lessThan(544));
      expect(game.player.position.x, greaterThanOrEqualTo(500));
    },
  );

  testWidgets(
    'Valeria slot 2 deals its configured damage once and grants a shield',
    (tester) async {
      final game = GoldRushGame(
        selectedMapConfig: legacyTestMap,
        playerProfile: PlayerProfile.defaultProfile().copyWith(
          selectedHeroId: 'valeria',
        ),
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.player.position = Vector2(400, 300);
      final target = game.enemies.first;
      target.position = Vector2(440, 300);
      target.currentHp = 1000;
      final damage =
          game.player.damage * game.player.skillConfig(2).damageMultiplier;
      game.onSkill2();
      expect(target.currentHp, closeTo(1000 - damage, .00001));
      expect(game.player.ironShieldTimer, greaterThan(0));
      game.onSkill2();
      expect(target.currentHp, closeTo(1000 - damage, .00001));
    },
  );

  test('Game terminal states reject all skill resources and reset clears combat clocks', () {
    final game = GoldRushGame(selectedMapConfig: legacyTestMap);
    for (final state in ['paused', 'victory', 'gameOver']) {
      game.isVictoryTriggered = state == 'victory';
      game.isGameOverTriggered = state == 'gameOver';
      if (state == 'paused') {
        game.pauseEngine();
      } else {
        game.resumeEngine();
      }
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      expect(game.player.currentKi, game.player.maxKi);
      expect(game.player.skill1VisualCd, 0);
      expect(game.player.skill2VisualCd, 0);
      expect(game.player.skill3VisualCd, 0);
    }
    final player = game.player;
    player.useSkill1();
    player.currentKi = player.maxKi;
    player.useSkill3();
    player.resetCombatState();
    expect(player.isAttacking, isFalse);
    expect(player.isBerserk, isFalse);
    expect(
      player.skillRuntimes.every(
        (skill) => skill.cooldownRemaining == 0 && skill.effectRemaining == 0,
      ),
      isTrue,
    );
  });

  testWidgets('Projectile cannot cross the real dungeon pillar', (
    tester,
  ) async {
    final game = GoldRushGame(
      selectedMapConfig: legacyTestMap,
      playerProfile: PlayerProfile.defaultProfile().copyWith(
        selectedHeroId: 'valeria',
      ),
    );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    game.player.position = Vector2(520, 336);
    final target = game.enemies.first;
    target.position = Vector2(660, 336);
    target.currentHp = 1000;
    game.onSkill1();
    await tester.pump();
    game.pauseEngine();
    final projectiles = game.world.children
        .whereType<HeroProjectile>()
        .toList();
    expect(projectiles, hasLength(2));
    for (final projectile in projectiles) {
      projectile.update(1);
      expect(projectile.position.x, lessThan(544));
    }
    expect(target.currentHp, 1000);
  });

  testWidgets(
    'Retry clears active effects, buffs, and cooldowns before respawning',
    (tester) async {
      final game = GoldRushGame(selectedMapConfig: legacyTestMap);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.onSkill3();
      await tester.pump();
      expect(game.player.skill3JudgmentTimer, greaterThan(0));
      expect(game.player.isBerserk, isTrue);
      game.retryFloor();
      await tester.pump();
      expect(game.player.skill3JudgmentTimer, 0);
      expect(game.player.isBerserk, isFalse);
      expect(game.player.skill3VisualCd, 0);
      expect(game.player.comboStep, 0);
      expect(game.player.currentHp, game.player.maxHp);
      expect(game.player.currentKi, game.player.maxKi);
    },
  );

  test(
    'PvP explicitly retains legacy costs and rejects duplicate local attacks',
    () {
      final game = PvpArenaGame(
        opponentInfo: PvpOpponentInfo.generateBot(100),
        playerCurrentRp: 100,
      );
      expect(game.player.skillConfig(1).kiCost, 25);
      expect(game.player.skillConfig(2).kiCost, 35);
      expect(game.player.skillConfig(3).kiCost, 40);
      game.matchState = PvpMatchState.fighting;
      game.player.position = Vector2(400, 300);
      game.player.isFacingRight = true;
      game.bot.position = Vector2(440, 300);
      final hp = game.bot.currentHp;
      var actionsSent = 0;
      game.onLocalAction = (action, {text}) => actionsSent++;
      game.onBasicAttack();
      game.onBasicAttack();
      expect(game.bot.currentHp, hp - game.player.damage);
      expect(actionsSent, 1);
    },
  );

  for (final phase in [1, 2]) {
    testWidgets('Configured damage reaches the real boss in phase $phase', (
      tester,
    ) async {
      final game = GoldRushGame(selectedMapConfig: legacyTestMap);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.player.position = Vector2(400, 300);
      final boss = game.boss!;
      boss.position = Vector2(440, 300);
      if (phase == 2) boss.takeDamage(boss.maxHp / 2);
      expect(boss.phase, phase);
      final hp = boss.currentHp;
      final config = game.player.skillConfig(1);
      game.onSkill1();
      game.onSkill1();
      expect(
        boss.currentHp,
        closeTo(hp - game.player.damage * config.damageMultiplier, .00001),
      );
    });
  }

  testWidgets(
    'Accepted hits emit one damage number; repeats and misses emit none',
    (tester) async {
      final game = GoldRushGame(selectedMapConfig: legacyTestMap);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      game.player.position = Vector2(400, 300);
      game.enemies.first.position = Vector2(440, 300);
      game.onBasicAttack();
      game.onBasicAttack();
      await tester.pump();
      Iterable<FloatingCombatText> numbers() => game.world.children
          .whereType<FloatingCombatText>()
          .where((text) => text.type == CombatTextType.normalDamage);
      expect(numbers().length, 1);
      game.player.update(.25);
      game.enemies.first.position = Vector2(360, 300);
      game.onBasicAttack();
      await tester.pump();
      expect(numbers().length, 1);
      expect(
        audio.callHistory
            .where(
              (event) =>
                  event.method == 'playSfx' &&
                  event.target == SfxSound.attackHammer,
            )
            .length,
        2,
      );
    },
  );
}
