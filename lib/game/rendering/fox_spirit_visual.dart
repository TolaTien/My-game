import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shared authored fox poses for lobby and combat; no texture deformation.
class FoxSpiritVisual {
  static int frameAt(double seconds) {
    const poses = [0, 1, 2, 1, 0, 3, 4, 5, 6, 5, 7, 0];
    const holds = [240, 120, 160, 120, 240, 80, 80, 240, 180, 160, 180, 200];
    final elapsed = (seconds % 2) * 1000;
    var boundary = 0;
    for (var i = 0; i < poses.length; i++) {
      boundary += holds[i];
      if (elapsed < boundary) return poses[i];
    }
    return 0;
  }

  static void drawSprite(
    Canvas canvas,
    ui.Image sheet, {
    required Offset center,
    required double width,
    required double seconds,
    bool facingRight = false,
    bool running = false,
  }) {
    final frame = running ? (seconds * 10).floor() % 8 : frameAt(seconds),
        cellWidth = sheet.width / 4,
        cellHeight = sheet.height / 2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (facingRight) canvas.scale(-1, 1);
    canvas.drawImageRect(
      sheet,
      Rect.fromLTWH(
        (frame % 4) * cellWidth,
        (frame ~/ 4) * cellHeight,
        cellWidth,
        cellHeight,
      ),
      Rect.fromCenter(
        center: Offset.zero,
        width: width,
        height: width * cellHeight / cellWidth,
      ),
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  static void drawAura(
    Canvas canvas, {
    required Offset center,
    required double seconds,
    bool empowered = false,
  }) {
    const cyan = Color(0xFF8BEAFF);
    final base = center + const Offset(0, 13);
    canvas.drawOval(
      Rect.fromCenter(center: base, width: 25, height: 6),
      Paint()..color = const Color(0x260B2338),
    );
    canvas.drawArc(
      Rect.fromCenter(center: base, width: 29, height: 8),
      seconds * .9,
      math.pi * 1.3,
      false,
      Paint()
        ..color = cyan.withValues(alpha: empowered ? .65 : .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    for (var i = 0; i < 5; i++) {
      final phase = (seconds * .55 + i / 5) % 1;
      final a = seconds * .8 + i * 2.4;
      final p =
          center + Offset(math.cos(a) * (15 + phase * 5), 10 - phase * 30);
      final alpha = math.sin(phase * math.pi) * (empowered ? .85 : .5);
      canvas.drawCircle(
        p,
        empowered ? 1.2 : .8,
        Paint()..color = cyan.withValues(alpha: alpha),
      );
      if (i.isEven) {
        canvas.drawLine(
          p - const Offset(1.5, 0),
          p + const Offset(1.5, 0),
          Paint()
            ..color = Colors.white.withValues(alpha: alpha * .7)
            ..strokeWidth = .6,
        );
      }
    }
    if (empowered) {
      final phase = (seconds * 1.5) % 1;
      canvas.drawOval(
        Rect.fromCenter(
          center: base,
          width: 25 + phase * 25,
          height: 7 + phase * 8,
        ),
        Paint()
          ..color = cyan.withValues(alpha: (1 - phase) * .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }
}
