import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'combat_status.dart';
import 'hero_kit.dart';

class CombatTarget {
  final PositionComponent body;
  final double Function() hp;
  final double maxHp;
  final void Function(double) hit;
  CombatTarget(this.body, this.hp, this.maxHp, this.hit);
  bool get alive => hp() > 0;
}

/// Shared attack geometry for PvE, local PvP, and AI combatants.
/// Targets and collision checks are supplied by each game mode.
class HeroCombat extends Component {
  final PositionComponent owner;
  final String heroId;
  final double Function() damage;
  final Vector2 Function() facing;
  final List<CombatTarget> Function() targets;
  final bool Function(Vector2) canWalk;
  final bool Function() enabled;
  final void Function(double) rage;
  final double maxHp;
  HeroCombat({
    required this.owner,
    required this.heroId,
    required this.damage,
    required this.facing,
    required this.targets,
    required this.canWalk,
    required this.enabled,
    required this.rage,
    required this.maxHp,
  });

  HeroKit get kit => HeroKit.forHero(heroId);
  final List<CombatProjectile> projectiles = [];
  final List<CombatZone> zones = [];

  Vector2 aim([double? range]) {
    final limit = range ?? kit.attackRange;
    final candidates =
        targets()
            .where(
              (t) =>
                  t.alive &&
                  owner.position.distanceTo(t.body.position) <= limit &&
                  _visible(t.body.position),
            )
            .toList()
          ..sort(
            (a, b) => owner.position
                .distanceToSquared(a.body.position)
                .compareTo(owner.position.distanceToSquared(b.body.position)),
          );
    if (candidates.isNotEmpty) {
      final delta = candidates.first.body.position - owner.position;
      if (delta.length2 > 0) return delta.normalized();
    }
    final direction = facing();
    return direction.length2 > 0 ? direction.normalized() : Vector2(1, 0);
  }

  bool _visible(Vector2 end) {
    final delta = end - owner.position;
    final steps = math.max(1, (delta.length / 6).ceil());
    for (var i = 1; i <= steps; i++) {
      if (!canWalk(owner.position + delta * (i / steps))) return false;
    }
    return true;
  }

  void dash(Vector2 direction, double distance) {
    if (direction.length2 == 0) return;
    final step = direction.normalized() * 4;
    for (var travelled = 0.0; travelled < distance; travelled += 4) {
      final next = owner.position + step;
      // Sample the entire body footprint, not just its center.
      if (![
        Vector2(0, 0),
        Vector2(-12, -14),
        Vector2(12, -14),
        Vector2(-12, 14),
        Vector2(12, 14),
      ].every((offset) => canWalk(next + offset))) {
        break;
      }
      owner.position.setFrom(next);
    }
  }

  void _hit(
    CombatTarget target,
    double amount, {
    double stun = 0,
    double slow = 0,
    double knockback = 0,
  }) {
    if (!target.alive || !enabled()) return;
    target.hit(amount);
    final body = target.body;
    if (body is CombatStatus) {
      body.stunRemaining = math.max(body.stunRemaining, stun);
      if (slow > 0) {
        body.slowRemaining = slow;
        body.slowFactor = .55;
      }
    }
    if (knockback > 0) {
      final delta = body.position - owner.position;
      if (delta.length2 > 0) {
        final step = delta.normalized() * 3;
        for (var i = 0.0; i < knockback; i += 3) {
          final next = body.position + step;
          if (!canWalk(next) ||
              !canWalk(next + Vector2(14, 14)) ||
              !canWalk(next - Vector2(14, 14))) {
            break;
          }
          body.position.setFrom(next);
        }
      }
    }
  }

  void melee(
    double range,
    double multiplier, {
    bool circle = false,
    double stun = 0,
    double knockback = 0,
  }) {
    final direction = aim(range);
    for (final target in targets()) {
      final delta = target.body.position - owner.position;
      if (!target.alive ||
          delta.length > range ||
          !_visible(target.body.position)) {
        continue;
      }
      if (!circle &&
          delta.length2 > 0 &&
          delta.normalized().dot(direction) < .25) {
        continue;
      }
      _hit(target, damage() * multiplier, stun: stun, knockback: knockback);
    }
    _zone(
      owner.position,
      range,
      delay: 0,
      duration: .22,
      pulse: 1,
      multiplier: 0,
      visualOnly: true,
    );
  }

  void shoot(
    Vector2 direction, {
    double multiplier = 1,
    double range = 330,
    bool piercing = false,
  }) {
    projectiles.add(
      CombatProjectile(
        position: owner.position.clone(),
        direction: direction,
        range: range,
        damage: damage() * multiplier,
        piercing: piercing,
        color: kit.color,
        targets: targets,
        canWalk: canWalk,
        onHit: (target, amount) => _hit(target, amount),
      ),
    );
  }

  void basic(int combo) {
    if (kit.ranged) {
      shoot(aim());
    } else {
      melee(
        kit.attackRange + (combo == 3 ? 15 : 0),
        heroId == 'ninja' ? (combo == 3 ? 1.6 : .85) : 1,
      );
    }
  }

  void _zone(
    Vector2 center,
    double radius, {
    required double delay,
    required double duration,
    required double pulse,
    required double multiplier,
    double stun = 0,
    double slow = 0,
    bool trap = false,
    bool visualOnly = false,
  }) {
    final attackDamage = damage() * multiplier;
    zones.add(
      CombatZone(
        center.clone(),
        radius,
        kit.color,
        delay,
        duration,
        pulse,
        targets,
        (target) {
          if (_visibleFrom(center, target.body.position)) {
            _hit(target, attackDamage, stun: stun, slow: slow);
          }
        },
        trap: trap,
        visualOnly: visualOnly,
        canWalk: canWalk,
      ),
    );
  }

  bool _visibleFrom(Vector2 start, Vector2 end) {
    final delta = end - start;
    final steps = math.max(1, (delta.length / 6).ceil());
    return List.generate(
      steps,
      (i) => start + delta * ((i + 1) / steps),
    ).every(canWalk);
  }

  Vector2 targetPoint(double range) =>
      owner.position +
      aim(range) *
          targets()
              .where(
                (t) =>
                    t.alive &&
                    owner.position.distanceTo(t.body.position) <= range &&
                    _visible(t.body.position),
              )
              .fold<double>(
                range,
                (nearest, t) => math.min(
                  nearest,
                  owner.position.distanceTo(t.body.position),
                ),
              );

  void skill(int slot) {
    final status = owner is CombatStatus ? owner as CombatStatus : null;
    final direction = aim(360);
    switch (heroId) {
      case 'ranger':
        if (slot == 1) {
          for (final angle in [-.22, 0.0, .22]) {
            shoot(
              direction.clone()..rotate(angle),
              multiplier: .75,
              range: 360,
            );
          }
        } else if (slot == 2) {
          final origin = owner.position.clone();
          dash(-direction, 95);
          _zone(
            origin,
            55,
            delay: .15,
            duration: 4,
            pulse: 1,
            multiplier: 1.2,
            stun: .7,
            trap: true,
          );
        } else {
          _zone(
            targetPoint(360),
            90,
            delay: .5,
            duration: 2.4,
            pulse: .6,
            multiplier: .55,
          );
        }
      case 'tanker':
        if (slot == 1) {
          melee(85, 1.4, stun: 1, knockback: 45);
        } else if (slot == 2) {
          status?.barrierHp = maxHp * .35;
          status?.barrierRemaining = 4;
          _zone(
            owner.position,
            45,
            delay: 0,
            duration: .5,
            pulse: 1,
            multiplier: 0,
            visualOnly: true,
          );
        } else {
          _zone(
            owner.position,
            140,
            delay: .6,
            duration: .3,
            pulse: 1,
            multiplier: 2.3,
            stun: 1,
            slow: 3,
          );
        }
      case 'ninja':
        if (slot == 1) {
          shoot(direction, multiplier: 1.3, range: 280, piercing: true);
        } else if (slot == 2) {
          _zone(
            owner.position,
            65,
            delay: 0,
            duration: 2,
            pulse: 3,
            multiplier: 0,
            visualOnly: true,
          );
          dash(direction, 100);
          status?.guardRemaining = 2;
          status?.guardReduction = .6;
          status?.hasteRemaining = 2;
          status?.hasteFactor = 1.3;
        } else {
          final candidates =
              targets()
                  .where(
                    (t) =>
                        t.alive &&
                        owner.position.distanceTo(t.body.position) <= 180 &&
                        _visible(t.body.position),
                  )
                  .toList()
                ..sort(
                  (a, b) => owner.position
                      .distanceToSquared(a.body.position)
                      .compareTo(
                        owner.position.distanceToSquared(b.body.position),
                      ),
                );
          if (candidates.isNotEmpty) {
            final victim = candidates.first;
            final delta = victim.body.position - owner.position;
            dash(delta, math.max(0, delta.length - 24));
            if (owner.position.distanceTo(victim.body.position) <= 65) {
              _hit(
                victim,
                damage() * (victim.hp() / victim.maxHp <= .3 ? 4.4 : 3.2),
              );
            }
          } else {
            dash(direction, 110);
          }
          _zone(
            owner.position,
            50,
            delay: 0,
            duration: .25,
            pulse: 1,
            multiplier: 0,
            visualOnly: true,
          );
        }
      default:
        if (slot == 1) {
          melee(85, 1.8, circle: true);
        } else if (slot == 2) {
          melee(125, 2.2, stun: .6, knockback: 36);
        } else {
          rage(8);
        }
    }
  }

  void reset() {
    projectiles.clear();
    zones.clear();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!enabled()) {
      reset();
      return;
    }
    for (final projectile in projectiles.toList()) {
      projectile.update(dt);
    }
    projectiles.removeWhere((p) => p.finished);
    for (final zone in zones.toList()) {
      zone.update(dt);
    }
    zones.removeWhere((z) => z.finished);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (final zone in zones) {
      zone.draw(canvas);
    }
    for (final projectile in projectiles) {
      projectile.draw(canvas);
    }
  }
}

class CombatProjectile {
  final Vector2 position, direction;
  final double range, damage;
  final bool piercing;
  final Color color;
  final List<CombatTarget> Function() targets;
  final bool Function(Vector2) canWalk;
  final void Function(CombatTarget, double) onHit;
  final Set<PositionComponent> _hit = {};
  double travelled = 0;
  bool finished = false;
  static const speed = 480.0;
  CombatProjectile({
    required this.position,
    required Vector2 direction,
    required this.range,
    required this.damage,
    required this.piercing,
    required this.color,
    required this.targets,
    required this.canWalk,
    required this.onHit,
  }) : direction = direction.length2 > 0
           ? direction.normalized()
           : Vector2(1, 0);

  void update(double dt) {
    if (finished) return;
    // Substeps avoid tunnelling through enemies and walls during slow frames.
    var remaining = math.min(speed * dt, range - travelled);
    while (remaining > 0 && !finished) {
      final step = math.min(4.0, remaining);
      position.add(direction * step);
      travelled += step;
      remaining -= step;
      if (!canWalk(position)) {
        finished = true;
        break;
      }
      for (final target in targets()) {
        if (!target.alive || _hit.contains(target.body)) continue;
        final hitRadius = math.max(
          12.0,
          math.min(target.body.size.x, target.body.size.y) * .4,
        );
        if (position.distanceTo(target.body.position) <= hitRadius) {
          _hit.add(target.body);
          onHit(target, damage);
          if (!piercing) {
            finished = true;
            break;
          }
        }
      }
    }
    if (travelled >= range) finished = true;
  }

  void draw(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.rotate(math.atan2(direction.y, direction.x));
    if (piercing) {
      canvas.rotate(travelled / 12);
      final star = Path();
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final radius = i.isEven ? 11.0 : 3.0;
        if (i == 0) {
          star.moveTo(math.cos(a) * radius, math.sin(a) * radius);
        } else {
          star.lineTo(math.cos(a) * radius, math.sin(a) * radius);
        }
      }
      canvas.drawPath(star..close(), Paint()..color = color);
      canvas.drawCircle(Offset.zero, 2, Paint()..color = Colors.white);
      canvas.restore();
      return;
    }
    canvas.drawLine(
      const Offset(-20, 0),
      const Offset(8, 0),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 0)
        ..lineTo(3, -5)
        ..lineTo(3, 5)
        ..close(),
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }
}

class CombatZone {
  final Vector2 center;
  final double radius, delay, duration, pulse;
  final Color color;
  final List<CombatTarget> Function() targets;
  final void Function(CombatTarget) hit;
  final bool trap, visualOnly;
  final bool Function(Vector2) canWalk;
  double age = 0, nextPulse = 0;
  bool finished = false;
  CombatZone(
    this.center,
    this.radius,
    this.color,
    this.delay,
    this.duration,
    this.pulse,
    this.targets,
    this.hit, {
    required this.trap,
    required this.visualOnly,
    required this.canWalk,
  });
  void update(double dt) {
    age += dt;
    if (age < delay) return;
    if (visualOnly) {
      finished = age >= delay + duration;
      return;
    }
    if (trap) {
      if (age >= delay + duration) {
        finished = true;
        return;
      }
      final victims = targets()
          .where((t) => t.alive && t.body.position.distanceTo(center) <= radius)
          .toList();
      if (victims.isNotEmpty) {
        for (final target in victims) {
          hit(target);
        }
        finished = true;
      }
    } else {
      while (nextPulse < duration && nextPulse <= age - delay) {
        for (final target in targets()) {
          if (target.alive &&
              target.body.position.distanceTo(center) <= radius) {
            hit(target);
          }
        }
        nextPulse += pulse;
      }
    }
    if (age >= delay + duration) finished = true;
  }

  void draw(Canvas canvas) {
    final point = Offset(center.x, center.y);
    if (visualOnly && duration > 1) {
      for (var i = 0; i < 7; i++) {
        final angle = i * math.pi * 2 / 7;
        final drift = radius * .4 + age * 8;
        canvas.drawCircle(
          point + Offset(math.cos(angle), math.sin(angle)) * drift,
          radius * .4,
          Paint()..color = const Color(0xFF332642).withValues(alpha: .4),
        );
      }
    }
    canvas.drawCircle(
      point,
      radius,
      Paint()..color = color.withValues(alpha: age < delay ? .07 : .16),
    );
    canvas.drawCircle(
      point,
      radius,
      Paint()
        ..color = color.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (trap) {
      canvas.drawLine(
        point - const Offset(12, 12),
        point + const Offset(12, 12),
        Paint()
          ..color = color
          ..strokeWidth = 3,
      );
      canvas.drawLine(
        point - const Offset(12, -12),
        point + const Offset(12, -12),
        Paint()
          ..color = color
          ..strokeWidth = 3,
      );
    } else if (delay > 0 && age < delay) {
      canvas.drawArc(
        Rect.fromCircle(center: point, radius: radius * .75),
        -math.pi / 2,
        math.pi * 2 * (age / delay),
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    } else if (pulse < 1 && !visualOnly) {
      // Arrow rain is tied to the damaging zone, not a separate fake animation.
      for (var i = 0; i < 12; i++) {
        final angle = i * 2.4;
        final distance = radius * math.sqrt((i + 1) / 13);
        final endpoint =
            point + Offset(math.cos(angle), math.sin(angle)) * distance;
        final fall = ((age * 2 + i * .17) % 1) * 70;
        final tip = endpoint - Offset(0, 70 - fall);
        canvas.drawLine(
          tip - const Offset(5, 18),
          tip,
          Paint()
            ..color = Colors.white.withValues(alpha: .8)
            ..strokeWidth = 2,
        );
      }
    } else if (delay > 0 && !trap) {
      final progress = ((age - delay) / duration).clamp(0.0, 1.0);
      canvas.drawCircle(
        point,
        radius * progress,
        Paint()
          ..color = color.withValues(alpha: 1 - progress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    }
  }
}
