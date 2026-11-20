import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Authored wingbeat frames plus lightweight fire/frost particles.
class DragonSpiritVisual {
  static int frameAt(double seconds) => (seconds * 8).floor() % 8;
  static void draw(
    Canvas canvas,
    ui.Image sheet, {
    required Offset center,
    required double width,
    required double seconds,
    bool facingRight = true,
    bool empowered = false,
  }) {
    final frame = frameAt(seconds),
        cellWidth = sheet.width / 4,
        cellHeight = sheet.height / 2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!facingRight) canvas.scale(-1, 1);
    final destination = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: width * cellHeight / cellWidth,
    );
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(
        (frame % 4) * cellWidth,
        (frame ~/ 4) * cellHeight,
        cellWidth,
        cellHeight,
      ),
      destination,
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.scale(width / 100);
    const fire = Color(0xFFFFAB55), frost = Color(0xFF9CEEFF);
    // Two colors follow different arcs behind the tail, without covering faces.
    for (var i = 0; i < 6; i++) {
      final phase = (seconds * .65 + i / 6) % 1;
      final p = Offset(
        -23 - phase * 15,
        8 + math.sin(phase * math.pi * 2 + i) * 4,
      );
      final color = i.isEven ? fire : frost;
      canvas.drawCircle(
        p,
        (1 - phase) * 1.2 + .3,
        Paint()..color = color.withValues(alpha: (1 - phase) * .5),
      );
    }
    final pulse = empowered
        ? .85
        : math
                  .pow(math.max(0, math.sin(seconds * math.pi / 3)), 10)
                  .toDouble() *
              .6;
    for (var i = 0; i < 5; i++) {
      final d = 5 + i * 2.2;
      canvas.drawCircle(
        Offset(29 + d, -4 + i * .3),
        1.2 - i * .12,
        Paint()..color = fire.withValues(alpha: pulse * (1 - i / 6)),
      );
      canvas.drawCircle(
        Offset(22 + d, -14 - i * .3),
        1.1 - i * .12,
        Paint()..color = frost.withValues(alpha: pulse * (1 - i / 6)),
      );
    }
    canvas.restore();
  }
}
