import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'boss_enemy.dart';
import 'dungeon_map.dart';
import 'enemy_skeleton.dart';
import 'enemy_zombie.dart';
import 'player.dart';
import 'pvp_bot_player.dart';

enum HeroProjectileType {
  arrow, // Xạ Thủ Lyra: Mũi tên ánh sáng phong linh
  starArrow, // Xạ Thủ Lyra Ultimate: Mũi tên ánh sao vàng kim
  fireball, // Pháp Sư Ember: Quả cầu lửa bốc cháy rực lửa
  frostOrb, // Pháp Sư Valeria: Cầu băng giá tinh thể tuyết
  shuriken, // Sát Thủ Hayate: Phi tiêu xoay xuyên thấu
  energyWave, // Chiến Binh Nova Blade: Sóng kiếm năng lượng Cyan
  voidBlade, // Sát Thủ Shadow-01: Lưỡi dao hư không tím
}

class HeroProjectile extends PositionComponent with CollisionCallbacks {
  final Vector2 direction;
  final double damage;
  final HeroProjectileType type;
  final bool isFromPlayer;
  final bool piercing;
  final double splashRadius;
  final double? speedOverride;
  final double maxLifetime;
  final Function(PositionComponent target, Vector2 hitPos)? onHit;

  double _lifeTimer = 0.0;
  bool _hasHit = false;
  final Set<PositionComponent> _hitTargets = {};

  final List<Vector2> _trailPositions = [];
  double _trailTimer = 0.0;

  HeroProjectile({
    required Vector2 position,
    required Vector2 direction,
    required this.damage,
    required this.type,
    required this.isFromPlayer,
    this.piercing = false,
    this.splashRadius = 0.0,
    this.speedOverride,
    this.maxLifetime = 1.35,
    this.onHit,
  })  : direction = direction.length2 > 0 ? direction.normalized() : Vector2(1, 0),
        super(
          position: position,
          size: _sizeForType(type),
          anchor: Anchor.center,
        ) {
    angle = atan2(this.direction.y, this.direction.x);

    if (type == HeroProjectileType.arrow ||
        type == HeroProjectileType.starArrow ||
        type == HeroProjectileType.voidBlade) {
      add(RectangleHitbox(
        size: Vector2(size.x - 4, size.y - 2),
        position: Vector2(2, 1),
      ));
    } else {
      add(CircleHitbox(
        radius: size.x / 2 - 2,
        position: Vector2(2, 2),
      ));
    }
  }

  static Vector2 _sizeForType(HeroProjectileType type) {
    switch (type) {
      case HeroProjectileType.arrow:
        return Vector2(24, 8);
      case HeroProjectileType.starArrow:
        return Vector2(28, 10);
      case HeroProjectileType.fireball:
        return Vector2(22, 22);
      case HeroProjectileType.frostOrb:
        return Vector2(20, 20);
      case HeroProjectileType.shuriken:
        return Vector2(18, 18);
      case HeroProjectileType.energyWave:
        return Vector2(26, 38);
      case HeroProjectileType.voidBlade:
        return Vector2(24, 10);
    }
  }

  double get speed {
    if (speedOverride != null) return speedOverride!;
    switch (type) {
      case HeroProjectileType.arrow:
        return 390.0;
      case HeroProjectileType.starArrow:
        return 430.0;
      case HeroProjectileType.fireball:
        return 335.0;
      case HeroProjectileType.frostOrb:
        return 320.0;
      case HeroProjectileType.shuriken:
        return 420.0;
      case HeroProjectileType.energyWave:
        return 360.0;
      case HeroProjectileType.voidBlade:
        return 410.0;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasHit) return;

    _lifeTimer += dt;
    if (_lifeTimer >= maxLifetime) {
      removeFromParent();
      return;
    }

    position.add(direction * speed * dt);

    _trailTimer += dt;
    if (_trailTimer >= 0.035) {
      _trailTimer = 0.0;
      _trailPositions.insert(0, position.clone());
      if (_trailPositions.length > 5) {
        _trailPositions.removeLast();
      }
    }

    _checkDistanceCollisions();
  }

  void _checkDistanceCollisions() {
    if (_hasHit || parent == null) return;

    final hitBonus = type == HeroProjectileType.energyWave ? 12.0 : 0.0;
    final targets = parent!.children.whereType<PositionComponent>().toList();
    for (final target in targets) {
      if (target == this || _hitTargets.contains(target)) continue;

      if (isFromPlayer) {
        if (target is ZombieEnemy && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        } else if (target is SkeletonEnemy && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        } else if (target is BossEnemy && target.isMounted && !target.isDefeated) {
          if (position.distanceTo(target.position) <= 38 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        } else if (target is PvpBotPlayerComponent &&
            target.isMounted &&
            target.currentHp > 0 &&
            !target.opponentInfo.isAlly) {
          if (position.distanceTo(target.position) <= 26 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        }
      } else {
        if (target is PlayerComponent && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        } else if (target is PvpBotPlayerComponent &&
            target.isMounted &&
            target.currentHp > 0 &&
            target.opponentInfo.isAlly) {
          if (position.distanceTo(target.position) <= 24 + hitBonus) {
            _handleHit(target);
            if (_hasHit) return;
          }
        }
      }

      if (target is WallBlock && target.isMounted) {
        if (position.distanceTo(target.position) <= 16) {
          _hasHit = true;
          removeFromParent();
          return;
        }
      }
    }
  }

  void _applyDamageTo(PositionComponent target, double dmg) {
    if (target is ZombieEnemy) {
      target.takeDamage(dmg);
    } else if (target is SkeletonEnemy) {
      target.takeDamage(dmg);
    } else if (target is BossEnemy) {
      target.takeDamage(dmg);
    } else if (target is PlayerComponent) {
      target.takeDamage(dmg);
    } else if (target is PvpBotPlayerComponent) {
      target.takeDamage(dmg);
    }
  }

  void _handleHit(PositionComponent target) {
    if (_hasHit || _hitTargets.contains(target)) return;
    _hitTargets.add(target);
    _applyDamageTo(target, damage);
    onHit?.call(target, position.clone());

    if (splashRadius > 0 && parent != null) {
      final splashDmg = damage * 0.6;
      for (final other in parent!.children.whereType<PositionComponent>()) {
        if (other == this || other == target || _hitTargets.contains(other)) continue;
        final isEnemyTarget = isFromPlayer
            ? (other is ZombieEnemy && other.currentHp > 0) ||
                (other is SkeletonEnemy && other.currentHp > 0) ||
                (other is BossEnemy && !other.isDefeated) ||
                (other is PvpBotPlayerComponent &&
                    other.currentHp > 0 &&
                    !other.opponentInfo.isAlly)
            : (other is PlayerComponent && other.currentHp > 0) ||
                (other is PvpBotPlayerComponent &&
                    other.currentHp > 0 &&
                    other.opponentInfo.isAlly);
        if (isEnemyTarget && position.distanceTo(other.position) <= splashRadius) {
          _applyDamageTo(other, splashDmg);
          onHit?.call(other, other.position.clone());
        }
      }
    }

    if (!piercing) {
      _hasHit = true;
      removeFromParent();
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (_hasHit) return;

    if (isFromPlayer) {
      if (other is ZombieEnemy ||
          other is SkeletonEnemy ||
          other is BossEnemy ||
          (other is PvpBotPlayerComponent && !other.opponentInfo.isAlly)) {
        _handleHit(other);
      }
    } else {
      if (other is PlayerComponent ||
          (other is PvpBotPlayerComponent && other.opponentInfo.isAlly)) {
        _handleHit(other);
      }
    }

    if (other is WallBlock) {
      _hasHit = true;
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    switch (type) {
      case HeroProjectileType.arrow:
        _renderRangerArrow(canvas);
        break;
      case HeroProjectileType.starArrow:
        _renderStarArrow(canvas);
        break;
      case HeroProjectileType.fireball:
        _renderEmberFireball(canvas);
        break;
      case HeroProjectileType.frostOrb:
        _renderValeriaFrostOrb(canvas);
        break;
      case HeroProjectileType.shuriken:
        _renderNinjaShuriken(canvas);
        break;
      case HeroProjectileType.energyWave:
        _renderNovaEnergyWave(canvas);
        break;
      case HeroProjectileType.voidBlade:
        _renderShadowVoidBlade(canvas);
        break;
    }
  }

  void _renderRangerArrow(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    canvas.drawCircle(
      Offset(cx, cy),
      8,
      Paint()
        ..color = const Color(0xFF00E676).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      Offset(cx - 9, cy),
      Offset(cx + 6, cy),
      Paint()
        ..color = const Color(0xFFEEFF41)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final featherPath = Path()
      ..moveTo(cx - 11, cy - 3.5)
      ..lineTo(cx - 6, cy)
      ..lineTo(cx - 11, cy + 3.5)
      ..close();
    canvas.drawPath(featherPath, Paint()..color = const Color(0xFF00E676));

    final tipPath = Path()
      ..moveTo(cx + 5, cy - 3.5)
      ..lineTo(cx + 11, cy)
      ..lineTo(cx + 5, cy + 3.5)
      ..close();
    canvas.drawPath(tipPath, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + 10, cy), 1.8, Paint()..color = const Color(0xFF76FF03));
  }

  void _renderStarArrow(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.drawCircle(
      Offset(cx, cy),
      10,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawLine(
      Offset(cx - 12, cy),
      Offset(cx + 9, cy),
      Paint()
        ..color = const Color(0xFFFFF59D)
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    );
    final tip = Path()
      ..moveTo(cx + 6, cy - 4.5)
      ..lineTo(cx + 14, cy)
      ..lineTo(cx + 6, cy + 4.5)
      ..close();
    canvas.drawPath(tip, Paint()..color = Colors.white);
  }

  void _renderEmberFireball(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final pulse = sin(_lifeTimer * 20.0) * 1.5;

    canvas.drawCircle(
      Offset(cx, cy),
      10 + pulse,
      Paint()
        ..color = const Color(0xFFFF3D00).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final flameTrail = Path()
      ..moveTo(cx + 4, cy - 5)
      ..quadraticBezierTo(cx - 8, cy - 6, cx - 12, cy - 2)
      ..quadraticBezierTo(cx - 8, cy + 6, cx + 4, cy + 5)
      ..close();
    canvas.drawPath(
      flameTrail,
      Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      Offset(cx + 1, cy),
      7.5 + pulse * 0.5,
      Paint()..color = const Color(0xFFFF9100),
    );
    canvas.drawCircle(
      Offset(cx + 2, cy),
      4.5,
      Paint()..color = const Color(0xFFFFF9C4),
    );
    canvas.drawCircle(Offset(cx + 3, cy), 2.2, Paint()..color = Colors.white);
  }

  void _renderValeriaFrostOrb(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final spinAngle = _lifeTimer * 12.0;

    canvas.drawCircle(
      Offset(cx, cy),
      9,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final iceTrail = Path()
      ..moveTo(cx + 2, cy - 4)
      ..lineTo(cx - 10, cy)
      ..lineTo(cx + 2, cy + 4)
      ..close();
    canvas.drawPath(
      iceTrail,
      Paint()..color = const Color(0xFF80D8FF).withValues(alpha: 0.7),
    );
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spinAngle);
    canvas.drawRect(
      const Rect.fromLTWH(-5, -5, 10, 10),
      Paint()..color = const Color(0xFF00B0FF),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-2.5, -2.5, 5, 5),
      Paint()..color = Colors.white,
    );
    canvas.restore();
  }

  void _renderNinjaShuriken(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final spin = _lifeTimer * 24.0;

    canvas.drawCircle(
      Offset(cx, cy),
      9,
      Paint()
        ..color = const Color(0xFFE040FB).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spin);
    final bladePaint = Paint()..color = const Color(0xFFE2E8F0);
    final edgePaint = Paint()..color = const Color(0xFFFF1744);
    for (int i = 0; i < 4; i++) {
      canvas.rotate(pi / 2);
      final blade = Path()
        ..moveTo(0, -2)
        ..lineTo(9, 0)
        ..lineTo(2, 3)
        ..close();
      canvas.drawPath(blade, bladePaint);
      canvas.drawLine(const Offset(3, 0), const Offset(8.5, 0), edgePaint..strokeWidth = 1.4);
    }
    canvas.drawCircle(Offset.zero, 2.5, Paint()..color = const Color(0xFF1E1B4B));
    canvas.restore();
  }

  void _renderNovaEnergyWave(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final rect = Rect.fromCenter(center: Offset(cx - 4, cy), width: 22, height: 34);
    canvas.drawArc(
      rect,
      -pi / 2.2,
      pi * 0.9,
      false,
      Paint()
        ..color = const Color(0xFF18FFFF).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawArc(
      rect,
      -pi / 2.2,
      pi * 0.9,
      false,
      Paint()
        ..color = const Color(0xFF18FFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 2, cy), width: 18, height: 28),
      -pi / 2.4,
      pi * 0.82,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _renderShadowVoidBlade(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.drawCircle(
      Offset(cx, cy),
      8,
      Paint()
        ..color = const Color(0xFFD500F9).withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final dagger = Path()
      ..moveTo(cx + 12, cy)
      ..lineTo(cx - 6, cy - 4.5)
      ..lineTo(cx - 11, cy)
      ..lineTo(cx - 6, cy + 4.5)
      ..close();
    canvas.drawPath(dagger, Paint()..color = const Color(0xFFE040FB));
    canvas.drawLine(
      Offset(cx - 6, cy),
      Offset(cx + 10, cy),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.8,
    );
  }
}
