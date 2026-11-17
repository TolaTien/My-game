import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum CombatTextType {
  normalDamage,
  skillDamage,
  criticalDamage,
  heal,
  buff,
  gold,
}

/// Hiển thị số sát thương / hồi máu nảy lên theo chuẩn Game UI Design (Damage Number Pattern)
class FloatingCombatText extends PositionComponent {
  final String text;
  final CombatTextType type;
  final double duration;

  double _elapsed = 0.0;
  late final double _driftX;

  FloatingCombatText({
    required Vector2 position,
    required this.text,
    this.type = CombatTextType.normalDamage,
    this.duration = 0.75,
  }) : super(
          position: position.clone() + Vector2(0, -18),
          anchor: Anchor.center,
          priority: 100,
        ) {
    final rand = Random();
    _driftX = (rand.nextDouble() - 0.5) * 26.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= duration) {
      removeFromParent();
      return;
    }

    // Bay lên nhanh lúc đầu rồi chậm dần (Ease-out)
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final verticalSpeed = (1.0 - progress) * 48.0;
    position.y -= verticalSpeed * dt;
    position.x += _driftX * dt * (1.0 - progress);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final opacity = progress < 0.7 ? 1.0 : ((1.0 - progress) / 0.3).clamp(0.0, 1.0);

    // Hiệu ứng nảy scale ở 0.15s đầu
    double scale = 1.0;
    if (progress < 0.18) {
      scale = 0.8 + (progress / 0.18) * 0.45;
    } else if (progress < 0.35) {
      scale = 1.25 - ((progress - 0.18) / 0.17) * 0.25;
    }

    Color textColor;
    double fontSize;
    switch (type) {
      case CombatTextType.normalDamage:
        textColor = Colors.white;
        fontSize = 11.0;
        break;
      case CombatTextType.skillDamage:
        textColor = const Color(0xFF00F0FF);
        fontSize = 13.0;
        break;
      case CombatTextType.criticalDamage:
        textColor = const Color(0xFFFFD700);
        fontSize = 14.5;
        break;
      case CombatTextType.heal:
        textColor = const Color(0xFF00E676);
        fontSize = 12.0;
        break;
      case CombatTextType.buff:
        textColor = const Color(0xFFFFEA00);
        fontSize = 11.5;
        break;
      case CombatTextType.gold:
        textColor = const Color(0xFFFFD700);
        fontSize = 12.0;
        break;
    }

    canvas.save();
    canvas.scale(scale, scale);

    final strokePainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = Colors.black.withValues(alpha: opacity * 0.9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final fillPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: textColor.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(-fillPainter.width / 2, -fillPainter.height / 2);
    strokePainter.paint(canvas, offset);
    fillPainter.paint(canvas, offset);

    canvas.restore();
  }
}
