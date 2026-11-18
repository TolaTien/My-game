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
  arrow, // Xạ Thủ Ranger: Mũi tên ánh sáng phong linh
  fireball, // Pháp Sư Ember: Quả cầu lửa bốc cháy rực lửa
  frostOrb, // Pháp Sư Valeria: Cầu băng giá tinh thể tuyết
}

class HeroProjectile extends PositionComponent with CollisionCallbacks {
  final Vector2 direction;
  final double damage;
  final HeroProjectileType type;
  final bool isFromPlayer;
  final Function(PositionComponent target, Vector2 hitPos)? onHit;

  double _lifeTimer = 0.0;
  static const double _maxLifetime = 1.35; // Tầm bay tối đa ~450px
  bool _hasHit = false;

  final List<Vector2> _trailPositions = [];
  double _trailTimer = 0.0;

  HeroProjectile({
    required Vector2 position,
    required Vector2 direction,
    required this.damage,
    required this.type,
    required this.isFromPlayer,
    this.onHit,
  })  : direction = direction.length2 > 0 ? direction.normalized() : Vector2(1, 0),
        super(
          position: position,
          size: type == HeroProjectileType.arrow
              ? Vector2(24, 8)
              : (type == HeroProjectileType.fireball
                  ? Vector2(22, 22)
                  : Vector2(20, 20)),
          anchor: Anchor.center,
        ) {
    angle = atan2(this.direction.y, this.direction.x);

    // Hitbox va chạm
    if (type == HeroProjectileType.arrow) {
      add(RectangleHitbox(
        size: Vector2(18, 6),
        position: Vector2(3, 1),
      ));
    } else {
      add(CircleHitbox(
        radius: size.x / 2 - 2,
        position: Vector2(2, 2),
      ));
    }
  }

  double get speed {
    switch (type) {
      case HeroProjectileType.arrow:
        return 380.0;
      case HeroProjectileType.fireball:
        return 330.0;
      case HeroProjectileType.frostOrb:
        return 315.0;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasHit) return;

    _lifeTimer += dt;
    if (_lifeTimer >= _maxLifetime) {
      removeFromParent();
      return;
    }

    // Di chuyển theo phương
    position.add(direction * speed * dt);

    // Lưu vị trí đuôi đạn để vẽ vệt sáng (trail)
    _trailTimer += dt;
    if (_trailTimer >= 0.035) {
      _trailTimer = 0.0;
      _trailPositions.insert(0, position.clone());
      if (_trailPositions.length > 5) {
        _trailPositions.removeLast();
      }
    }

    // Kiểm tra khoảng cách phòng thủ trực tiếp tránh lọt va chạm
    _checkDistanceCollisions();
  }

  void _checkDistanceCollisions() {
    if (_hasHit || parent == null) return;

    final targets = parent!.children.whereType<PositionComponent>();
    for (final target in targets) {
      if (target == this) continue;

      if (isFromPlayer) {
        // Đạn của người chơi: Đánh quái hầm ngục hoặc bot địch
        if (target is ZombieEnemy && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24) {
            _handleHit(target);
            return;
          }
        } else if (target is SkeletonEnemy && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24) {
            _handleHit(target);
            return;
          }
        } else if (target is BossEnemy && target.isMounted && !target.isDefeated) {
          if (position.distanceTo(target.position) <= 38) {
            _handleHit(target);
            return;
          }
        } else if (target is PvpBotPlayerComponent &&
            target.isMounted &&
            target.currentHp > 0 &&
            !target.opponentInfo.isAlly) {
          if (position.distanceTo(target.position) <= 26) {
            _handleHit(target);
            return;
          }
        }
      } else {
        // Đạn của bot địch: Đánh người chơi hoặc đồng minh
        if (target is PlayerComponent && target.isMounted && target.currentHp > 0) {
          if (position.distanceTo(target.position) <= 24) {
            _handleHit(target);
            return;
          }
        } else if (target is PvpBotPlayerComponent &&
            target.isMounted &&
            target.currentHp > 0 &&
            target.opponentInfo.isAlly) {
          if (position.distanceTo(target.position) <= 24) {
            _handleHit(target);
            return;
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

  void _handleHit(PositionComponent target) {
    if (_hasHit) return;
    _hasHit = true;

    if (target is ZombieEnemy) {
      target.takeDamage(damage);
    } else if (target is SkeletonEnemy) {
      target.takeDamage(damage);
    } else if (target is BossEnemy) {
      target.takeDamage(damage);
    } else if (target is PlayerComponent) {
      target.takeDamage(damage);
    } else if (target is PvpBotPlayerComponent) {
      target.takeDamage(damage);
    }

    onHit?.call(target, position.clone());
    removeFromParent();
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
      case HeroProjectileType.fireball:
        _renderEmberFireball(canvas);
        break;
      case HeroProjectileType.frostOrb:
        _renderValeriaFrostOrb(canvas);
        break;
    }
  }

  /// 1. XẠ THỦ RANGER: MŨI TÊN ÁNH SÁNG PHONG LINH
  void _renderRangerArrow(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Hào quang xanh ngọc phát sáng rực rỡ
    final auraPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy), 8, auraPaint);

    // 1. Thân tên ánh sáng vàng chanh
    final shaftPaint = Paint()
      ..color = const Color(0xFFEEFF41)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 9, cy), Offset(cx + 6, cy), shaftPaint);

    // 2. Lông vũ đuôi tên xanh lục
    final featherPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..style = PaintingStyle.fill;
    final featherPath = Path()
      ..moveTo(cx - 11, cy - 3.5)
      ..lineTo(cx - 6, cy)
      ..lineTo(cx - 11, cy + 3.5)
      ..close();
    canvas.drawPath(featherPath, featherPaint);

    // 3. Đầu mũi tên nhọn kim loại phát sáng
    final tipPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final tipPath = Path()
      ..moveTo(cx + 5, cy - 3.5)
      ..lineTo(cx + 11, cy)
      ..lineTo(cx + 5, cy + 3.5)
      ..close();
    canvas.drawPath(tipPath, tipPaint);

    // Điểm sáng lóe đầu mũi tên
    final sparkPaint = Paint()..color = const Color(0xFF76FF03);
    canvas.drawCircle(Offset(cx + 10, cy), 1.8, sparkPaint);
  }

  /// 2. PHÁP SƯ EMBER: QUẢ CẦU LỬA BỐC CHÁY (FIREBALL)
  void _renderEmberFireball(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final pulse = sin(_lifeTimer * 20.0) * 1.5;

    // 1. Lớp hào quang lửa đỏ ngoài cùng
    final outerAura = Paint()
      ..color = const Color(0xFFFF3D00).withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cx, cy), 10 + pulse, outerAura);

    // 2. Đuôi ngọn lửa bay phía sau
    final flameTrail = Path()
      ..moveTo(cx + 4, cy - 5)
      ..quadraticBezierTo(cx - 8, cy - 6, cx - 12, cy - 2)
      ..quadraticBezierTo(cx - 8, cy + 6, cx + 4, cy + 5)
      ..close();
    canvas.drawPath(
      flameTrail,
      Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.8),
    );

    // 3. Quả cầu lửa cam rực rỡ ở giữa
    final midFlame = Paint()
      ..color = const Color(0xFFFF9100)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 1, cy), 7.5 + pulse * 0.5, midFlame);

    // 4. Lõi ngọn lửa vàng trắng siêu nhiệt
    final coreFlame = Paint()
      ..color = const Color(0xFFFFF9C4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx + 2, cy), 4.5, coreFlame);

    // 5. Tâm trắng chói sáng
    canvas.drawCircle(Offset(cx + 3, cy), 2.2, Paint()..color = Colors.white);
  }

  /// 3. PHÁP SƯ VALERIA: CẦU BĂNG GIÁ TINH THỂ TUYẾT (FROST ORB)
  void _renderValeriaFrostOrb(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final spinAngle = _lifeTimer * 12.0;

    // 1. Hào quang băng lam lấp lánh
    final frostAura = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(cx, cy), 9, frostAura);

    // 2. Vệt sương tuyết đuôi
    final iceTrail = Path()
      ..moveTo(cx + 2, cy - 4)
      ..lineTo(cx - 10, cy)
      ..lineTo(cx + 2, cy + 4)
      ..close();
    canvas.drawPath(
      iceTrail,
      Paint()..color = const Color(0xFF80D8FF).withValues(alpha: 0.7),
    );

    // 3. Quả cầu tinh thể băng xoay tròn
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spinAngle);

    final iceCrystal = Paint()
      ..color = const Color(0xFF00B0FF)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(-5, -5, 10, 10),
      iceCrystal,
    );

    final innerCore = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      const Rect.fromLTWH(-2.5, -2.5, 5, 5),
      innerCore,
    );

    canvas.restore();
  }
}
