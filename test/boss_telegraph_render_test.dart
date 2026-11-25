import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (phase, floor, count) in [
    (1, 1, 3),
    (2, 1, 8),
    (2, 3, 10),
    (2, 5, 12),
  ]) {
    test(
      'Phase $phase floor $floor warning is readable within its $count lanes',
      () async {
        const zoom = 1.4;
        const imageSize = 320;
        const imageCenter = ui.Offset(160, 160);
        const floorColor = ui.Color(0xFF20242C);
        const windupTime = BossEnemy.flameBurstTelegraphDuration / 2;
        final boss =
            BossEnemy(
                position: Vector2.zero(),
                player: PlayerComponent(position: Vector2(200, 0)),
              )
              ..phase = phase
              ..applyFloorDifficulty(floor)
              ..flameBurstCooldownTimer = 0;
        boss.update(0);
        expect(boss.state, BossState.radialFlameBurst);
        boss.stateTimer = windupTime;

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..drawColor(floorColor, ui.BlendMode.src)
          ..translate(imageCenter.dx, imageCenter.dy)
          ..scale(zoom)
          ..translate(-boss.size.x / 2, -boss.size.y / 2);
        boss.render(canvas);
        expect(boss.state, BossState.radialFlameBurst);
        expect(boss.stateTimer, windupTime);

        final picture = recorder.endRecording();
        addTearDown(picture.dispose);
        final image = await picture.toImage(imageSize, imageSize);
        addTearDown(image.dispose);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;

        int pixelAt(ui.Offset worldOffset) {
          final pixel = imageCenter + worldOffset * zoom;
          return pixels.getUint32(
            (pixel.dy.floor() * imageSize + pixel.dx.floor()) * 4,
          );
        }

        for (var i = 0; i < count; i++) {
          final angle = phase == 2
              ? pi / count + i * 2 * pi / count
              : (i - 1) * 16 * pi / 180;
          final direction = Vector2(cos(angle), sin(angle));
          final ray = ui.Offset(direction.x, direction.y);
          final normal = ui.Offset(-ray.dy, ray.dx);
          final lane = ray * 96;
          for (final side in [-1, 1]) {
            expect(
              pixelAt(
                    lane + normal * (side * (BossFlameProjectile.hitRadius - 2)),
                  ) >>
                  24,
              greaterThan(140),
              reason: 'Lane $i should contrast with the floor on side $side',
            );
            expect(
              pixelAt(
                lane + normal * (side * (BossFlameProjectile.hitRadius + 2)),
              ),
              0x20242CFF,
              reason: 'Lane $i should leave the floor clear outside side $side',
            );

            // The tip is at 62 world units halfway through the windup.
            final arrowArm = pixelAt(ray * 57 + normal * (side * 2.5));
            expect(
              (arrowArm >> 16) & 0xFF,
              greaterThan(190),
              reason: 'Lane $i should retain arrowhead arm $side',
            );
          }
        }
      },
    );
  }
}
