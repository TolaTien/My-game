import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Basic attack accepts one action, preserves combo and rejects disabled/dead', () {
    final player = PlayerComponent(position: Vector2.zero());
    expect(player.performBasicAttack(), isTrue);
    expect(player.performBasicAttack(), isFalse);
    expect(player.comboStep, 1);
    player.update(0.25);
    expect(player.performBasicAttack(), isTrue);
    expect(player.comboStep, 2);
    player.update(0.25);
    player.actionsEnabled = false;
    expect(player.performBasicAttack(), isFalse);
    expect(player.comboStep, 2);
    player.actionsEnabled = true;
    player.currentHp = 0;
    expect(player.performBasicAttack(), isFalse);
  });

  test(
    'Basic attacks use a frontal cone, finisher keeps its 360 degree AoE',
    () {
      final player = PlayerComponent(position: Vector2.zero());
      player.performBasicAttack();
      expect(player.canHitBasicAttack(Vector2(40, 0)), isTrue);
      expect(player.canHitBasicAttack(Vector2(-40, 0)), isFalse);
      expect(player.canHitBasicAttack(Vector2(0, 40)), isFalse);
      expect(player.canHitBasicAttack(Vector2(56, 0)), isFalse);
      player.isFacingRight = false;
      expect(player.canHitBasicAttack(Vector2(-40, 0)), isTrue);
      expect(player.canHitBasicAttack(Vector2(40, 0)), isFalse);
      player.comboStep = 3;
      expect(player.canHitBasicAttack(Vector2(0, 79)), isTrue);
      expect(player.canHitBasicAttack(Vector2(79, 0)), isTrue);
      expect(player.canHitBasicAttack(Vector2(81, 0)), isFalse);
    },
  );

  testWidgets(
    'Production combat rejects repeated input before damage or feedback',
    (tester) async {
      final game = GoldRushGame();
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final front = game.enemies.first;
      final behind = game.enemies.last;
      final skeleton = game.skeletons.first;
      final boss = game.boss!;
      game.player.position = Vector2(400, 300);
      front.position = Vector2(440, 300);
      behind.position = Vector2(360, 300);
      skeleton.position = Vector2(435, 300);
      boss.position = Vector2(460, 300);
      final damage = game.player.damage;
      final frontHp = front.currentHp;
      final behindHp = behind.currentHp;
      final skeletonHp = skeleton.currentHp;
      final bossHp = boss.currentHp;
      game.onBasicAttack();
      game.onBasicAttack();
      expect(front.currentHp, frontHp - damage);
      expect(behind.currentHp, behindHp);
      expect(skeleton.currentHp, skeletonHp - damage);
      expect(boss.currentHp, bossHp - damage);
      game.player.isAttacking = false;
      game.pauseEngine();
      game.onBasicAttack();
      expect(front.currentHp, frontHp - damage);
      game.resumeEngine();
      game.player.actionsEnabled = false;
      game.onBasicAttack();
      expect(front.currentHp, frontHp - damage);
      game.player.actionsEnabled = true;
      game.player.currentHp = 0;
      game.onBasicAttack();
      expect(front.currentHp, frontHp - damage);
    },
  );
}
