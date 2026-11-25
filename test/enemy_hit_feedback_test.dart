import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/components/pickup_item.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';

class _FeedbackGame extends GoldRushGame {
  @override
  Future<void> onLoad() async {
    await world.add(player);
  }
}

class _LootRandom implements Random {
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

Future<Uint8List> _pixels(PositionComponent enemy) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF123456), BlendMode.src);
  canvas.translate(0, 10);
  enemy.render(canvas);
  // A later sibling must also retain its own paint on the shared canvas.
  canvas.drawRect(
    const Rect.fromLTWH(40, 0, 4, 4),
    Paint()..color = const Color(0xFFABCDEF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(48, 56);
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final pixels = Uint8List.fromList(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return pixels;
}

List<int> _pixel(Uint8List pixels, int x, int y) {
  final offset = (y * 48 + x) * 4;
  return pixels.sublist(offset, offset + 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final zombie in [true, false]) {
    final name = zombie ? 'Zombie' : 'Skeleton';
    final duration = zombie
        ? ZombieEnemy.hitFlashDuration
        : SkeletonEnemy.hitFlashDuration;
    late PlayerComponent player;
    // Both production actors expose the same damage/feedback API without a
    // shared enemy interface; keep this test matrix on their real methods.
    late dynamic enemy;

    group('$name hit feedback', () {
      setUp(() {
        player = PlayerComponent(position: Vector2(1000, 1000));
        enemy = zombie
            ? ZombieEnemy(position: Vector2(100, 100), player: player)
            : SkeletonEnemy(position: Vector2(100, 100), player: player);
      });

      test('positive damage activates, dt decays and clamps at zero', () {
        expect(enemy.hitFlashTimer, 0);
        enemy.takeDamage(5.0);
        expect(enemy.hitFlashTimer, duration);
        enemy.update(0.0);
        expect(enemy.hitFlashTimer, duration);
        enemy.update(0.03);
        expect(enemy.hitFlashTimer, closeTo(duration - 0.03, 1e-9));
        enemy.update(1.0);
        expect(enemy.hitFlashTimer, 0);
      });

      test('repeated hits refresh but never stack beyond the duration', () {
        enemy.takeDamage(1.0);
        enemy.update(0.03);
        enemy.takeDamage(1.0);
        expect(enemy.hitFlashTimer, duration);
        for (var i = 0; i < 20; i++) {
          enemy.takeDamage(0.1);
          expect(enemy.hitFlashTimer, duration);
        }
        enemy.update(duration + 0.01);
        expect(enemy.hitFlashTimer, 0);
      });

      test('zero and negative damage do not activate or refresh feedback', () {
        final hp = enemy.currentHp as double;
        enemy.takeDamage(0.0);
        enemy.takeDamage(-1.0);
        expect(enemy.hitFlashTimer, 0);
        expect(enemy.currentHp, hp + 1);
        enemy.takeDamage(2.0);
        enemy.update(0.03);
        final remaining = enemy.hitFlashTimer;
        enemy.takeDamage(0.0);
        enemy.takeDamage(-1.0);
        expect(enemy.hitFlashTimer, remaining);
      });

      test('feedback decays through stun without changing gameplay stats', () {
        final hp = enemy.currentHp as double;
        final maxHp = enemy.maxHp;
        final speed = enemy.speed;
        final position = (enemy.position as Vector2).clone();
        final hitbox = (enemy.children as Iterable<Component>)
            .whereType<RectangleHitbox>()
            .first;
        final hitboxSize = hitbox.size.clone();
        enemy.stunTimer = 0.5;
        if (zombie) {
          enemy.attackCooldown = 0.7;
        } else {
          enemy.shootCooldown = 0.7;
        }
        enemy.takeDamage(7.0);
        expect(enemy.currentHp, hp - 7);
        expect(enemy.stunTimer, 0.5);
        enemy.update(0.2);
        expect(enemy.hitFlashTimer, 0);
        expect(enemy.stunTimer, closeTo(0.3, 1e-9));
        expect(enemy.currentHp, hp - 7);
        expect(enemy.maxHp, maxHp);
        expect(enemy.speed, speed);
        expect(enemy.position, position);
        expect(hitbox.size, hitboxSize);
        expect(zombie ? enemy.attackCooldown : enemy.shootCooldown, 0.7);
        if (zombie) expect(enemy.damage, 12);
        expect(player.currentHp, player.maxHp);
        expect(player.currentExp, 0);
      });

      test('feedback leaves normal AI movement and cooldowns intact', () {
        player.position = Vector2(400, 100);
        enemy.position = Vector2(150, 100);
        if (zombie) {
          enemy.attackCooldown = 0.7;
        } else {
          enemy.shootCooldown = 0.7;
        }
        enemy.takeDamage(1.0);
        enemy.update(0.1);
        if (zombie) {
          expect(enemy.position.x, closeTo(150 + enemy.speed * 0.1, 1e-9));
          expect(enemy.position.y, 100);
        } else {
          // At 250px the ranged skeleton strafes instead of closing distance.
          expect(enemy.position.x, 150);
          expect(
            (enemy.position.y - 100).abs(),
            closeTo(enemy.speed * .65 * .1, 1e-9),
          );
        }
        expect(
          zombie ? enemy.attackCooldown : enemy.shootCooldown,
          closeTo(0.6, 1e-9),
        );
        expect(enemy.stunTimer, 0);
      });

      test(
        'body tints and recovers without tinting the shared canvas',
        () async {
          final baseline = await _pixels(enemy as PositionComponent);
          enemy.takeDamage(1.0);
          final hit = await _pixels(enemy as PositionComponent);
          expect(_pixel(hit, 15, 14), isNot(_pixel(baseline, 15, 14)));
          expect(_pixel(hit, 0, 10), _pixel(baseline, 0, 10));
          expect(_pixel(hit, 41, 11), [0xAB, 0xCD, 0xEF, 0xFF]);
          expect(_pixel(hit, 16, 44), _pixel(baseline, 16, 44));
          enemy.update(duration);
          final recovered = await _pixels(enemy as PositionComponent);
          expect(_pixel(recovered, 15, 14), _pixel(baseline, 15, 14));
        },
      );

      testWidgets('lethal damage clears flash, hides immediately and removes', (
        tester,
      ) async {
        final game = _FeedbackGame();
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        game.pauseEngine();
        enemy = zombie
            ? ZombieEnemy(position: Vector2(100, 100), player: game.player)
            : SkeletonEnemy(
                position: Vector2(100, 100),
                player: game.player,
                random: _LootRandom(),
              );
        if (zombie) {
          game.enemies.add(enemy as ZombieEnemy);
        } else {
          game.skeletons.add(enemy as SkeletonEnemy);
        }
        await game.world.add(enemy as PositionComponent);
        await tester.runAsync(game.ready);
        expect(enemy.isMounted, isTrue);
        final hp = enemy.currentHp as double;
        final exp = game.player.currentExp;
        final pickups = game.pickups.length;
        enemy.takeDamage(1.0);
        expect(enemy.hitFlashTimer, duration);
        enemy.takeDamage(hp);
        expect(enemy.currentHp, -1);
        expect(enemy.hitFlashTimer, 0);
        expect(game.player.currentExp, exp + (zombie ? 35 : 50));
        expect(game.enemies.contains(enemy), isFalse);
        expect(game.skeletons.contains(enemy), isFalse);
        const roll = 0.5;
        expect(game.pickups.length, pickups + (!zombie && roll < 0.75 ? 1 : 0));
        if (!zombie && roll < 0.75) {
          expect(
            game.pickups.last.type,
            roll < 0.35
                ? PickupType.goldCoin
                : roll < 0.60
                ? PickupType.expGem
                : PickupType.healthPotion,
          );
        }
        final dead = await tester.runAsync(
          () => _pixels(enemy as PositionComponent),
        );
        expect(_pixel(dead!, 15, 14), [0x12, 0x34, 0x56, 0xFF]);
        expect(_pixel(dead, 16, 44), [0x12, 0x34, 0x56, 0xFF]);
        await tester.runAsync(game.ready);
        expect(enemy.isMounted, isFalse);
      });
    });
  }
}
