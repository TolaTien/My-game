import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/player.dart';

class _CueCanvas implements Canvas {
  final lines = <(Offset, Offset, Color, double)>[];
  final arcs = <(Rect, double, double, bool, Color, double, PaintingStyle)>[];

  @override
  void drawLine(Offset start, Offset end, Paint paint) {
    lines.add((start, end, Color(paint.color.toARGB32()), paint.strokeWidth));
  }

  @override
  void drawArc(
    Rect rect,
    double start,
    double sweep,
    bool useCenter,
    Paint paint,
  ) {
    arcs.add((
      rect,
      start,
      sweep,
      useCenter,
      Color(paint.color.toARGB32()),
      paint.strokeWidth,
      paint.style,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Object?> _bossSnapshot(BossEnemy boss) => [
  boss.state,
  boss.stateTimer,
  boss.position.clone(),
  boss.size.clone(),
  boss.previousPosition.clone(),
  boss.currentHp,
  boss.phase,
  boss.isEnraged,
  boss.isDefeated,
  boss.currentSpeed,
  boss.meleeCooldownTimer,
  boss.groundSlamCooldownTimer,
  boss.flameBurstCooldownTimer,
  boss.chargeCooldownTimer,
  boss.stunTimer,
  boss.axeSwingAngle,
  boss.auraTimer,
  boss.deathFadeTimer,
  boss.isFacingRight,
  boss.groundSlamCenter?.clone(),
  boss.activeTelegraph,
  boss.children.toList(),
  boss.player.currentHp,
  boss.player.position.clone(),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (phase, floor, count) in [
    (1, 1, 3),
    (2, 1, 8),
    (2, 3, 10),
    (2, 5, 12),
  ]) {
    for (final progress in [0.0, 0.5, 1.0]) {
      test(
        'Phase $phase floor $floor lanes have outlined chevrons at $progress',
        () {
          final boss =
              BossEnemy(
                  position: Vector2(200, 300),
                  player: PlayerComponent(position: Vector2(400, 300)),
                )
                ..phase = phase
                ..applyFloorDifficulty(floor)
                ..flameBurstCooldownTimer = 0;
          boss.update(0);
          expect(boss.state, BossState.radialFlameBurst);
          boss.stateTimer = BossEnemy.flameBurstTelegraphDuration * progress;
          final before = _bossSnapshot(boss);
          final canvas = _CueCanvas();
          boss.render(canvas);
          final repeated = _CueCanvas();
          boss.render(repeated);
          expect(_bossSnapshot(boss), before);
          expect(repeated.lines, canvas.lines);

          final center = Offset(boss.size.x / 2, boss.size.y / 2);
          final speed = boss.flameBurstSpeed * (phase == 2 ? 1 : 1.1);
          final length = speed * BossFlameProjectile.lifetime;
          final lanes = canvas.lines.where((line) => line.$1 == center).toList();
          expect(lanes, hasLength(count));
          for (var i = 0; i < count; i++) {
            final angle = phase == 2
                ? pi / count + i * 2 * pi / count
                : (i - 1) * 16 * pi / 180;
            final direction = Vector2(cos(angle), sin(angle));
            final ray = Offset(direction.x, direction.y);
            final normal = Offset(-ray.dy, ray.dx);
            expect(lanes[i].$2, center + ray * length);
            expect(lanes[i].$3, const Color(0xA6FFB300));
            expect(lanes[i].$4, BossFlameProjectile.hitRadius * 2);
            for (double distance = 120; distance <= length - 28; distance += 72) {
              final tip = center + ray * (distance + 28 * progress);
              for (final side in [-1, 1]) {
                final arm = tip - ray * 10 + normal * (side * 4);
                final strokes = canvas.lines
                    .where(
                      (line) =>
                          (line.$1 - arm).distance < 0.00001 &&
                          (line.$2 - tip).distance < 0.00001,
                    )
                    .toList();
                expect(
                  strokes,
                  hasLength(2),
                  reason: 'Lane $i, distance $distance',
                );
                expect(strokes[0].$3, const Color(0xFF101018));
                expect(strokes[1].$3, const Color(0xFFFFFFFF));
                expect(strokes[0].$4, greaterThan(strokes[1].$4));
                expect(
                  4 + strokes[0].$4 / 2,
                  lessThanOrEqualTo(BossFlameProjectile.hitRadius),
                );
              }
            }
          }
        },
      );
    }
  }

  test('Slam boundary has steady outlined dashes at the damage radius', () {
    final telegraph = GroundSlamTelegraph(position: Vector2(200, 300));
    List<(Rect, double, double, bool, Color, double, PaintingStyle)>? previous;
    for (final time in [0.0, 0.6, 1.199, 1.2, 1.4]) {
      telegraph.timer = time;
      final position = telegraph.position.clone();
      final size = telegraph.size.clone();
      final canvas = _CueCanvas();
      telegraph.render(canvas);
      final repeated = _CueCanvas();
      telegraph.render(repeated);
      expect(telegraph.timer, time);
      expect(telegraph.position, position);
      expect(telegraph.size, size);
      expect(telegraph.duration, BossEnemy.groundSlamTelegraphDuration);
      expect(telegraph.isRemoving, isFalse);
      expect(repeated.arcs, canvas.arcs);
      if (previous != null) expect(canvas.arcs, previous);
      previous = canvas.arcs;
      expect(canvas.arcs, hasLength(48));
      for (var i = 0; i < 24; i++) {
        final outline = canvas.arcs[i * 2];
        final dash = canvas.arcs[i * 2 + 1];
        expect(
          dash.$1,
          Rect.fromCircle(
            center: const Offset(70, 70),
            radius: BossEnemy.groundSlamAoERadius,
          ),
        );
        expect(dash.$2, closeTo(i * pi / 12, 0.00001));
        expect(dash.$3, closeTo(pi / 18, 0.00001));
        expect(
          dash.$3,
          lessThan(pi / 12),
          reason: 'Visible gap between dashes',
        );
        expect(dash.$4, isFalse);
        expect(dash.$5, const Color(0xFFFFFFFF));
        expect(dash.$7, PaintingStyle.stroke);
        expect(outline.$1, dash.$1);
        expect(outline.$2, dash.$2);
        expect(outline.$3, dash.$3);
        expect(outline.$5, const Color(0xFF101018));
        expect(outline.$6, greaterThan(dash.$6));
        expect(outline.$7, PaintingStyle.stroke);
      }
    }
  });

  test('Radial pattern disappears outside the windup state', () {
    final boss = BossEnemy(
      position: Vector2.zero(),
      player: PlayerComponent(position: Vector2.zero()),
    );
    for (final state in BossState.values.where(
      (state) => state != BossState.radialFlameBurst,
    )) {
      boss.state = state;
      final before = _bossSnapshot(boss);
      final canvas = _CueCanvas();
      boss.render(canvas);
      expect(
        canvas.lines.where((line) => line.$3 == const Color(0xFFFFFFFF)),
        isEmpty,
      );
      expect(_bossSnapshot(boss), before);
    }
  });
}
