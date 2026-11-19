import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../registry/sprite_image_cache.dart';
import 'hero_sprite_animator.dart';

/// A bounded, swept projectile: every target is hit at most once, even at low FPS.
class PlayerSkillProjectile extends PositionComponent {
  final Vector2 direction;
  final double range;
  final bool piercing;
  final Color color;
  final Iterable<PositionComponent> Function() targets;
  final void Function(PositionComponent) onHit;
  final bool Function(Vector2) canTravel;
  final SpriteClip? animation;
  final SpriteFramePainter _painter = SpriteFramePainter();
  final Vector2 _probe = Vector2.zero();
  double _elapsed = 0;
  final Set<PositionComponent> _hit = {};
  double _travelled = 0;
  bool _expired = false;
  static const double speed = 220;

  PlayerSkillProjectile({
    required Vector2 position,
    required Vector2 direction,
    required this.range,
    required this.piercing,
    required this.color,
    required this.targets,
    required this.onHit,
    required this.canTravel,
    this.animation,
  }) : direction = direction.normalized(),
       super(
         position: position.clone(),
         size: Vector2.all(16),
         anchor: Anchor.center,
       );

  @override
  void update(double dt) {
    super.update(dt);
    if (_expired) return;
    _elapsed += dt;
    var remaining = math.min(speed * dt, range - _travelled);
    final candidates = targets().toList(growable: false);
    while (remaining > 0 && !_expired) {
      final step = math.min(4.0, remaining);
      _probe.setValues(
        position.x + direction.x * step,
        position.y + direction.y * step,
      );
      if (!canTravel(_probe)) {
        _expire();
        break;
      }
      position.setFrom(_probe);
      _travelled += step;
      remaining -= step;
      for (final target in candidates) {
        if (_hit.contains(target)) continue;
        final hitRadius = 8 + target.size.x / 2;
        if (position.distanceToSquared(target.position) <=
            hitRadius * hitRadius) {
          _hit.add(target);
          onHit(target);
          if (!piercing) {
            _expire();
            break;
          }
        }
      }
    }
    if (_travelled >= range) _expire();
  }

  void _expire() {
    _expired = true;
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final clip = animation;
    if (clip != null) {
      final frame = clip.frameAt(_elapsed);
      canvas.save();
      canvas.translate(8, 8);
      canvas.rotate(math.atan2(direction.y, direction.x));
      _painter.draw(
        canvas,
        frame,
        Offset.zero,
        height: frame.worldHeight.clamp(20.0, 42.0),
      );
      canvas.restore();
      return;
    }
    canvas.drawCircle(
      const Offset(8, 8),
      8,
      Paint()..color = color.withValues(alpha: 0.35),
    );
    canvas.drawCircle(const Offset(8, 8), 5, Paint()..color = color);
    canvas.drawCircle(
      const Offset(8, 8),
      2,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }
}

/// A visible area and its pulse clock share the same radius and lifetime.
class PlayerSkillArea extends PositionComponent {
  final double radius;
  final double duration;
  final double tickInterval;
  final Color color;
  final PositionComponent? follow;
  final bool Function() isActive;
  final void Function(double fraction)? onPulse;
  final SpriteClip? animation;
  final SpriteFramePainter _painter = SpriteFramePainter();
  double _elapsed = 0;
  int _emitted = 0;

  PlayerSkillArea({
    required Vector2 position,
    required this.radius,
    required this.duration,
    required this.color,
    required this.isActive,
    this.tickInterval = 0,
    this.follow,
    this.onPulse,
    this.animation,
  }) : super(position: position.clone(), priority: -1);

  @override
  void update(double dt) {
    super.update(dt);
    if (!isActive()) {
      removeFromParent();
      return;
    }
    if (follow != null) position.setFrom(follow!.position);
    _elapsed += dt;
    if (tickInterval > 0 && duration > 0) {
      final count = (duration / tickInterval).ceil();
      while (_emitted < count &&
          _elapsed >= math.min((_emitted + 1) * tickInterval, duration)) {
        _emitted++;
        onPulse?.call(1 / count);
      }
    }
    if (_elapsed >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final fade = (1 - _elapsed / duration).clamp(0.0, 1.0);
    final clip = animation;
    if (clip != null) {
      final frame = clip.frameAt(
        _elapsed,
        normalizedProgress: clip.loop ? null : _elapsed / duration,
      );
      final progress = (_elapsed / math.min(.12, duration)).clamp(0.0, 1.0);
      final settle = 1 - math.pow(1 - progress, 3).toDouble();
      final height = math.min(frame.worldHeight, math.max(36.0, radius * 2));
      _painter.draw(
        canvas,
        frame,
        Offset.zero,
        height: height * (.85 + .15 * settle),
        opacity: (_elapsed < duration - .15 ? 1.0 : (duration - _elapsed) / .15)
            .clamp(0.0, 1.0),
      );
      return;
    }
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withValues(alpha: 0.12 * fade),
    );
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.7 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
