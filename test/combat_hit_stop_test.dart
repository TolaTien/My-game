import 'package:flame/game.dart';
import 'package:my_game/game/components/hero_projectile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  final map = MapAssetConfig.fromJson({
    'id': 'hit_stop_test',
    'imageAsset': '',
  });

  setUp(() {
    final previous = AudioService.instance;
    AudioService.setInstance(MockAudioService());
    addTearDown(() => AudioService.setInstance(previous));
  });

  Future<GoldRushGame> mountGame(
    WidgetTester tester, {
    bool? enabled,
    String heroId = 'george',
  }) async {
    final game = enabled == null
        ? GoldRushGame(
            selectedMapConfig: map,
            playerProfile: PlayerProfile(selectedHeroId: heroId),
          )
        : GoldRushGame(
            selectedMapConfig: map,
            playerProfile: PlayerProfile(selectedHeroId: heroId),
            enableCombatHitStop: enabled,
          );
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    game.player.position = Vector2(400, 300);
    game.player.faceDirection(Vector2(1, 0));
    game.enemies.first
      ..position = Vector2(440, 300)
      ..currentHp = 1000
      ..stunTimer = 10;
    return game;
  }

  void expectStep(GoldRushGame game, double realDt, double simulationDt) {
    final before = game.player.animTime;
    game.update(realDt);
    expect(game.player.animTime - before, closeTo(simulationDt, 1e-8));
  }

  testWidgets('a melee hit slows only the first 50 ms of real time', (
    tester,
  ) async {
    final game = await mountGame(tester);
    game.onBasicAttack();
    expect(game.enemies.first.currentHp, lessThan(1000));
    expect(game.paused, isFalse);
    expectStep(game, .049, .0049);
    expectStep(game, .011, .0101);
    expectStep(game, .016, .016);
  });

  testWidgets('a skill hit 30 ms later extends the stop and accepts input', (
    tester,
  ) async {
    final game = await mountGame(tester);
    final target = game.enemies.first;
    game.onBasicAttack();
    final hpAfterAttack = target.currentHp;
    expectStep(game, .030, .003);

    game.onSkill2();
    expect(target.currentHp, lessThan(hpAfterAttack));
    expectStep(game, .030, .003); // Past the basic attack's original expiry.
    expectStep(game, .025, .007);
    expectStep(game, .016, .016);
  });

  testWidgets('the existing late basic attack buffer works during hit-stop', (
    tester,
  ) async {
    final game = await mountGame(tester, heroId: 'ranger');
    final target = game.enemies.first..position = Vector2(550, 300);
    game.onBasicAttack();
    await tester.pump();
    expectStep(game, .160, .160);
    target.position = game.world.children
        .whereType<HeroProjectile>()
        .first
        .position
        .clone();
    expectStep(game, .010, .010);
    expect(target.currentHp, lessThan(1000));
    game.onBasicAttack();
    expectStep(game, .050, .005);
    expect(game.player.comboStep, 1);
    expectStep(game, .080, .080);
    expect(game.player.comboStep, 2);
  });

  testWidgets(
    'rejected, missed, zero-damage and self-buff inputs do not slow',
    (tester) async {
      final game = await mountGame(tester);
      final target = game.enemies.first;
      game.player.actionsEnabled = false;
      game.onBasicAttack();
      game.onSkill2();
      expect(target.currentHp, 1000);
      expectStep(game, .016, .016);

      game.player.actionsEnabled = true;
      target.position = Vector2(330, 300);
      game.onBasicAttack();
      expect(target.currentHp, 1000);
      expectStep(game, .016, .016);

      game.player.resetCombatState();
      game.player.damage = 0;
      target.position = Vector2(440, 300);
      game.onBasicAttack();
      expect(target.currentHp, 1000);
      expectStep(game, .016, .016);
      game.onSkill3();
      expect(game.player.isBerserk, isTrue);
      expectStep(game, .016, .016);
    },
  );

  testWidgets('a ranged basic attack slows on impact, not launch', (
    tester,
  ) async {
    final game = await mountGame(tester, heroId: 'ranger');
    final target = game.enemies.first;
    final damage = game.player.damage;
    game.player.damage = 0;
    game.onBasicAttack();
    expectStep(game, .080, .080);
    expect(target.currentHp, 1000);
    expectStep(game, .010, .010);

    game.player.resetCombatState();
    game.player.damage = damage;
    game.onBasicAttack();
    expect(target.currentHp, 1000);
    expectStep(game, .010, .010);
    expect(target.currentHp, 1000);
    expectStep(game, .070, .070);
    expect(target.currentHp, lessThan(1000));
    expectStep(game, .010, .001);
  });

  testWidgets('pause and retry clear an in-progress stop', (tester) async {
    final game = await mountGame(tester);
    game.onBasicAttack();
    expectStep(game, .010, .001);
    game.pauseEngine();
    game.resumeEngine();
    expectStep(game, .016, .016);

    game.onSkill2();
    expectStep(game, .010, .001);
    game.retryFloor();
    expectStep(game, .016, .016);
  });

  testWidgets('disabled hit-stop leaves simulation delta intact on hit', (
    tester,
  ) async {
    final game = await mountGame(tester, enabled: false);
    game.onBasicAttack();
    expect(game.enemies.first.currentHp, lessThan(1000));
    expectStep(game, .016, .016);
  });
}
