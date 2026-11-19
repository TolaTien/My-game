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
  // Eviction only releases cached layouts; it never drops a combat message.
  // Alpha is part of native paragraph paint. Reuse exact text/style layouts
  // rather than adding an offscreen saveLayer on every animated frame.
  static final _layouts = <(String, CombatTextType, double), _CombatTextLayout>{};
  static const _maxCachedLayouts = 192;
  @visibleForTesting
  static int debugLayoutBuildCount = 0;
  @visibleForTesting
  static int get debugCachedLayoutCount => _layouts.length;

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

    final layout = _layoutFor(opacity);
    canvas.save();
    canvas.scale(scale, scale);
    final offset = Offset(-layout.fill.width / 2, -layout.fill.height / 2);
    layout.stroke.paint(canvas, offset);
    layout.fill.paint(canvas, offset);
    canvas.restore();
  }

  _CombatTextLayout _layoutFor(double opacity) {
    final key = (text, type, opacity);
    final cached = _layouts.remove(key);
    if (cached != null) {
      _layouts[key] = cached;
      return cached;
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

    if (_layouts.length >= _maxCachedLayouts) {
      _layouts.remove(_layouts.keys.first)!.dispose();
    }
    final layout = _CombatTextLayout(strokePainter, fillPainter);
    _layouts[key] = layout;
    assert(() {
      debugLayoutBuildCount += 2;
      return true;
    }());
    return layout;
  }
}

class _CombatTextLayout {
  final TextPainter stroke;
  final TextPainter fill;

  _CombatTextLayout(this.stroke, this.fill);

  void dispose() {
    stroke.dispose();
    fill.dispose();
  }
}
