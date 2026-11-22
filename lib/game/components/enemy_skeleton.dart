import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'player.dart';
import '../../services/audio_service.dart';
import 'dungeon_map.dart';
import 'arrow_projectile.dart';
import 'pickup_item.dart';
import '../ai/astar_pathfinder.dart';
import '../big_war_game.dart';

class SkeletonEnemy extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  double maxHp = 45.0;
  double currentHp = 45.0;
  double speed = 50.0;
  double arrowDamage = 10.0;
  double arrowSpeed = 220.0;
  double shootInterval = 1.8;

  final PlayerComponent player;
  Vector2 previousPosition = Vector2.zero();
  double shootCooldown = 0.0;
  bool isFacingRight = true;

  // A* Navigation & Tactical Flanking state
  List<Vector2> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _pathRecalcTimer = 0.0;
  bool _isAggroed = false;
  double _strafeTimer = 0.0;
  double _strafeSign = 1.0;
  static const double _pathRecalcInterval = 0.42;
  static const double _waypointReachThreshold = 12.0;

  SkeletonEnemy({required Vector2 position, required this.player})
      : _strafeSign = Random().nextBool() ? 1.0 : -1.0,
        super(
          position: position,
          size: Vector2(32, 38),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(20, 26),
      position: Vector2(6, 8),
    ));
    _pathRecalcTimer = Random().nextDouble() * _pathRecalcInterval;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (shootCooldown > 0) shootCooldown -= dt;
    _strafeTimer += dt;
    if (_strafeTimer >= 1.7) {
      _strafeTimer = 0.0;
      _strafeSign = -_strafeSign;
    }

    final distanceToPlayer = position.distanceTo(player.position);
    if (distanceToPlayer < 460) _isAggroed = true;

    // Luôn quay mặt về phía Player
    isFacingRight = player.position.x >= position.x;

    // AI Kiting thông minh (không lùi đâm tường) & Bắn đón đầu:
    if (distanceToPlayer < 115) {
      _waypoints.clear();
      _currentWaypointIndex = 0;
      final away = (position - player.position);
      final awayDir = away.length2 > 0.01 ? away.normalized() : Vector2(1, 0);
      final strafe = Vector2(-awayDir.y * _strafeSign, awayDir.x * _strafeSign);
      final desired = _isWalkablePoint(position + awayDir * 24)
          ? (awayDir * 0.8 + strafe * 0.5).normalized()
          : strafe;
      previousPosition = position.clone();
      position.add(desired * (speed * 1.15) * dt);
    } else if (distanceToPlayer > 250) {
      if (_isAggroed) {
        if (isMounted && game.walkableGrid.isNotEmpty) {
          _pathRecalcTimer -= dt;
          if (_pathRecalcTimer <= 0) {
            _pathRecalcTimer = _pathRecalcInterval;
            _waypoints = AStarPathfinder.findPath(
              position,
              player.position,
              game.walkableGrid,
            );
            _currentWaypointIndex = 0;
          }
          _followWaypoints(dt);
        } else {
          previousPosition = position.clone();
          final towardDir = (player.position - position).normalized();
          position.add(towardDir * speed * dt);
        }
      }
    } else {
      bool hasLoS = true;
      if (isMounted && game.walkableGrid.isNotEmpty) {
        hasLoS = AStarPathfinder.hasLineOfSight(
          position,
          player.position,
          game.walkableGrid,
        );
      }

      if (hasLoS) {
        _waypoints.clear();
        _currentWaypointIndex = 0;
        // Di chuyển lách ngang khi đang chờ bắn thay vì đứng yên
        final toP = (player.position - position);
        if (toP.length2 > 1.0) {
          final norm = toP.normalized();
          final strafe = Vector2(-norm.y * _strafeSign, norm.x * _strafeSign);
          if (_isWalkablePoint(position + strafe * 18)) {
            previousPosition = position.clone();
            position.add(strafe * (speed * 0.65) * dt);
          } else {
            _strafeSign = -_strafeSign;
          }
        }
        if (shootCooldown <= 0) {
          _shootArrow();
          shootCooldown = shootInterval;
        }
      } else {
        if (isMounted && game.walkableGrid.isNotEmpty) {
          _pathRecalcTimer -= dt;
          if (_pathRecalcTimer <= 0) {
            _pathRecalcTimer = _pathRecalcInterval;
            _waypoints = AStarPathfinder.findPath(
              position,
              player.position,
              game.walkableGrid,
            );
            _currentWaypointIndex = 0;
          }
          _followWaypoints(dt);
        }
      }
    }
  }

  bool _isWalkablePoint(Vector2 pt) {
    if (!isMounted || game.walkableGrid.isEmpty) return true;
    final (col, row) = AStarPathfinder.worldToGrid(pt);
    if (col < 0 || col >= game.walkableGrid.length) return false;
    if (row < 0 || row >= game.walkableGrid[0].length) return false;
    return game.walkableGrid[col][row];
  }

  void _followWaypoints(double dt) {
    if (_waypoints.isEmpty || _currentWaypointIndex >= _waypoints.length) {
      previousPosition = position.clone();
      final towardDir = (player.position - position).normalized();
      position.add(towardDir * speed * dt);
      return;
    }

    var targetPt = _waypoints[_currentWaypointIndex];
    if (_currentWaypointIndex == _waypoints.length - 1) {
      targetPt = player.position;
    }

    final dist = position.distanceTo(targetPt);
    if (dist <= _waypointReachThreshold) {
      _currentWaypointIndex++;
      if (_currentWaypointIndex < _waypoints.length) {
        targetPt = _waypoints[_currentWaypointIndex];
      }
    }

    final toTarget = targetPt - position;
    if (toTarget.length2 > 0.0001) {
      previousPosition = position.clone();
      final dir = toTarget.normalized();
      position.add(dir * speed * dt);
    }
  }

  void _shootArrow() {
    // Bắn đón đầu (Predictive Leading Aim) theo vận tốc di chuyển của Player
    final dist = position.distanceTo(player.position);
    final leadTime = (dist / max(1.0, arrowSpeed)).clamp(0.0, 0.75) * 0.65;
    final predictedPos =
        player.position + (player.moveDirection * player.speed * leadTime);
    final toTarget = predictedPos - position;
    if (toTarget.length2 == 0) return;
    final dir = toTarget.normalized();

    final spawnOffset = Vector2(isFacingRight ? 12 : -12, 0);
    final arrow = ArrowProjectile(
      position: position + spawnOffset,
      direction: dir,
      speed: arrowSpeed,
      damage: arrowDamage,
    );
    game.world.add(arrow);
    AudioService.instance.playSfx(SfxSound.attackArrow);
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is WallBlock) {
      position = previousPosition.clone();
    }
  }

  void takeDamage(double dmg) {
    _isAggroed = true;
    currentHp -= dmg;
    if (currentHp <= 0) {
      // Thưởng 50 EXP cho player
      player.gainExp(50);
      _dropLoot();
      game.skeletons.remove(this);
      removeFromParent();
    }
  }

  void _dropLoot() {
    final rand = Random().nextDouble();
    // 75% tỉ lệ rớt vật phẩm giá trị
    if (rand < 0.75) {
      PickupType dropType;
      if (rand < 0.35) {
        dropType = PickupType.goldCoin;
      } else if (rand < 0.60) {
        dropType = PickupType.expGem;
      } else {
        dropType = PickupType.healthPotion;
      }

      final item = PickupItem(
        position: position.clone(),
        type: dropType,
      );
      game.pickups.add(item);
      game.world.add(item);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Bóng đổ dưới chân
    final shadowPaint = Paint()..color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 2), width: 20, height: 6),
      shadowPaint,
    );

    // 2. Vẽ thân hình bộ xương và cung tên (được lật theo isFacingRight)
    canvas.save();
    if (!isFacingRight) {
      canvas.scale(-1, 1);
      canvas.translate(-size.x, 0);
    }

    final bonePaint = Paint()..color = const Color(0xFFE0E0E0);
    final boneShadow = Paint()..color = const Color(0xFF9E9E9E);

    // 2.1 Chân xương
    canvas.drawRect(Rect.fromLTWH(10, size.y - 10, 3, 8), bonePaint);
    canvas.drawRect(Rect.fromLTWH(19, size.y - 10, 3, 8), bonePaint);

    // 2.2 Cột sống & Xương chậu
    canvas.drawRect(Rect.fromLTWH(15, 14, 2, 13), boneShadow);
    canvas.drawRect(Rect.fromLTWH(11, 26, 10, 2.5), bonePaint);

    // 2.3 Xương sườn
    canvas.drawRect(Rect.fromLTWH(10, 15, 12, 2.2), bonePaint);
    canvas.drawRect(Rect.fromLTWH(11, 19, 10, 2.2), bonePaint);
    canvas.drawRect(Rect.fromLTWH(12, 23, 8, 2.2), bonePaint);

    // 2.4 Hộp sọ Skeleton
    final skullPaint = Paint()..color = const Color(0xFFEEEEEE);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 2, 16, 12), const Radius.circular(3)),
      skullPaint,
    );
    // Hàm dưới & kẽ răng
    canvas.drawRect(const Rect.fromLTWH(11, 12, 10, 2.5), boneShadow);
    final teethPaint = Paint()..color = const Color(0xFF212121);
    canvas.drawRect(const Rect.fromLTWH(13, 12.5, 1.5, 2), teethPaint);
    canvas.drawRect(const Rect.fromLTWH(16, 12.5, 1.5, 2), teethPaint);

    // Hốc mắt đen sâu hoắm
    final eyeSocket = Paint()..color = const Color(0xFF1B1B1B);
    canvas.drawRect(const Rect.fromLTWH(10, 5, 4, 4), eyeSocket);
    canvas.drawRect(const Rect.fromLTWH(17, 5, 4, 4), eyeSocket);

    // Đốm lửa ma mị trong mắt (tím Undead)
    final evilEye = Paint()..color = const Color(0xFFE040FB);
    canvas.drawRect(const Rect.fromLTWH(12, 6, 2, 2), evilEye);
    canvas.drawRect(const Rect.fromLTWH(19, 6, 2, 2), evilEye);

    // 2.5 Cây cung gỗ (Bow)
    final bowPaint = Paint()
      ..color = const Color(0xFF6D4C41)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final bowPath = Path()
      ..moveTo(24, 7)
      ..quadraticBezierTo(28, 19, 24, 31);
    canvas.drawPath(bowPath, bowPaint);

    // Dây cung mảnh
    final stringPaint = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(24, 7), const Offset(24, 31), stringPaint);

    // Cánh tay xương cầm cung
    canvas.drawRect(const Rect.fromLTWH(16, 17, 8, 2.5), bonePaint);

    canvas.restore();

    // 3. Thanh máu tím ma thuật trên đầu Skeleton
    final hpBg = Paint()..color = const Color(0xFF212121);
    final hpFill = Paint()..color = const Color(0xFFAB47BC);
    const barWidth = 26.0;
    const barHeight = 4.0;
    final fillWidth = (currentHp / maxHp).clamp(0.0, 1.0) * barWidth;

    canvas.drawRect(
      const Rect.fromLTWH(3, -8, barWidth, barHeight),
      hpBg,
    );
    canvas.drawRect(
      Rect.fromLTWH(3, -8, fillWidth, barHeight),
      hpFill,
    );
  }
}
