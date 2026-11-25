import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/floating_combat_text.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAudioService audio;
  setUp(() {
    final previous = AudioService.instance;
    audio = MockAudioService();
    AudioService.setInstance(audio);
    addTearDown(() => AudioService.setInstance(previous));
  });

  int attackSounds() => audio.callHistory
      .where(
        (event) =>
            event.method == 'playSfx' && event.target == SfxSound.attackHammer,
      )
      .length;

  test('A late press starts one follow-up at the end of recovery', () {
    final player = PlayerComponent(position: Vector2.zero());
    final starts = <int>[];
    void recordStart() => starts.add(player.comboStep);

    expect(player.performBasicAttack(onStarted: recordStart), isTrue);
    player.update(.1);
    expect(player.performBasicAttack(onStarted: recordStart), isFalse);
    expect(player.performBasicAttack(onStarted: recordStart), isFalse);
    expect(starts, [1]);
    expect(attackSounds(), 1);

    player.update(.125);
    expect(starts, [1]);
    player.update(.025);
    expect(starts, [1, 2]);
    expect(player.isAttacking, isTrue);
    expect(player.attackTimer, 0);
    player.update(.25);
    expect(player.isAttacking, isFalse);
    expect(starts, [1, 2]);
    expect(attackSounds(), 2);
  });

  test('Early presses are ignored and stale presses expire on a long tick', () {
    final player = PlayerComponent(position: Vector2.zero());
    player.performBasicAttack();
    player.update(.05);
    expect(player.performBasicAttack(), isFalse);
    player.update(.2);
    expect(player.isAttacking, isFalse);

    player.performBasicAttack();
    player.update(.2);
    expect(player.performBasicAttack(), isFalse);
    player.update(.151);
    expect(player.isAttacking, isFalse);
    expect(player.comboStep, 2);
    expect(attackSounds(), 2);
  });

  final interruptions = <String, void Function(PlayerComponent)>{
    'reset': (player) => player.resetCombatState(),
    'death': (player) => player
      ..currentHp = 0
      ..currentHp = player.maxHp,
    'disabled actions': (player) => player
      ..actionsEnabled = false
      ..actionsEnabled = true,
    'skill 1': (player) => expect(player.useSkill1(), isTrue),
  };
  for (final interruption in interruptions.entries) {
    test('${interruption.key} clears a queued press', () {
      final player = PlayerComponent(position: Vector2.zero());
      player.performBasicAttack();
      player.update(.2);
      expect(player.performBasicAttack(), isFalse);
      interruption.value(player);
      player.update(.06);
      if (interruption.key == 'skill 1') {
        expect(player.isAttacking, isTrue);
        expect(player.performBasicAttack(), isFalse);
        player.update(.25);
      }
      expect(player.isAttacking, isFalse);
      expect(attackSounds(), 1);
    });
  }

  testWidgets('PvE resolves damage and feedback once per swing at start', (
    tester,
  ) async {
    final game = GoldRushGame();
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final target = game.enemies.first;
    game.player.position = Vector2(400, 300);
    target.position = Vector2(440, 300);
    target.currentHp = 1000;
    final damage = game.player.effectiveDamage;
    int damageNumbers() => game.world.children
        .whereType<FloatingCombatText>()
        .where((text) => text.type == CombatTextType.normalDamage)
        .length;

    game.onBasicAttack();
    await tester.pump();
    expect(target.currentHp, closeTo(1000 - damage, 1e-6));
    expect(damageNumbers(), 1);

    game.player.update(.2);
    target.position = Vector2(360, 300);
    game.onBasicAttack();
    game.onBasicAttack();
    expect(target.currentHp, closeTo(1000 - damage, 1e-6));
    expect(damageNumbers(), 1);
    expect(attackSounds(), 1);

    game.player.faceDirection(Vector2(-1, 0));
    game.player.update(.05);
    await tester.pump();
    expect(target.currentHp, closeTo(1000 - 2 * damage, 1e-6));
    expect(damageNumbers(), 2);
    game.player.update(.25);
    expect(game.player.comboStep, 2);
    expect(attackSounds(), 2);

    game.onBasicAttack();
    game.player.update(.2);
    game.onBasicAttack();
    game.paused = true;
    game.paused = false;
    game.player.update(.06);
    expect(game.player.comboStep, 3);
    expect(attackSounds(), 3);
  });

  testWidgets('PvP dispatches one local action per swing at start', (
    tester,
  ) async {
    final game = PvpArenaGame(
      opponentInfo: const PvpOpponentInfo(
        name: 'Opponent',
        rankPoints: 1600,
        rankTier: 'Gold',
        heroId: 'george',
        difficulty: BotDifficulty.goldPlatinum,
      ),
      playerCurrentRp: 1600,
      isOnline: true,
      selectedMapConfig: MapAssetConfig.fromJson({
        'id': 'basic_attack_buffer_test',
        'imageAsset': '',
      }),
    );
    final actions = <String>[];
    game.onLocalAction = (action, {text}) => actions.add(action);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.player.isMounted, isTrue);
    game.startOnlineMatch();
    game.update(PvpArenaGame.roundIntroDuration);
    game.bot.position = game.player.position + Vector2(40, 0);
    game.bot.currentHp = 1000;
    final damage = game.player.effectiveDamage;

    game.onBasicAttack();
    expect(game.bot.currentHp, closeTo(1000 - damage, 1e-6));
    game.update(.2);
    game.onBasicAttack();
    game.onBasicAttack();
    expect(actions, ['basicAttack']);
    expect(game.bot.currentHp, closeTo(1000 - damage, 1e-6));

    game.update(.05);
    expect(actions, ['basicAttack', 'basicAttack']);
    expect(game.bot.currentHp, closeTo(1000 - 2 * damage, 1e-6));
    game.update(.25);
    expect(game.player.comboStep, 2);
    expect(actions, ['basicAttack', 'basicAttack']);

    game.onBasicAttack();
    game.update(.2);
    game.onBasicAttack();
    game.paused = true;
    game.paused = false;
    game.update(.06);
    expect(game.player.comboStep, 3);
    expect(actions, ['basicAttack', 'basicAttack', 'basicAttack']);

    game.bot.actionsEnabled = false;
    game.bot.isAttacking = true;
    game.bot.attackTimer = .1;
    game.applyOpponentAction('basicAttack');
    expect(game.bot.attackTimer, 0);
    expect(actions, ['basicAttack', 'basicAttack', 'basicAttack']);
  });
}
