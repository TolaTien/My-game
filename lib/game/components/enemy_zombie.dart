import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'player.dart';
import 'dungeon_map.dart';
import '../ai/astar_pathfinder.dart';
import '../big_war_game.dart';

class ZombieEnemy extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  double maxHp = 60.0;
  double currentHp = 60.0;
  double speed = 65.0;
  double damage = 12.0;

  final PlayerComponent player;
  Vector2 previousPosition = Vector2.zero();
  double attackCooldown = 0.0;

  // A* Navigation, Flanking & Lunge state
  List<Vector2> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _pathRecalcTimer = 0.0;
  bool _isAggroed = false;
  double _lungeTimer = 0.0;
  double _lungeCooldown = 2.0;
  final double _flankSign;
  static const double _pathRecalcInterval = 0.38;
  static const double _waypointReachThreshold = 12.0;

  ZombieEnemy({required Vector2 position, required this.player})
      : _flankSign = Random().nextBool() ? 1.0 : -1.0,
        super(
          position: position,
          size: Vector2(32, 36),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(20, 24),
      position: Vector2(6, 8),
    ));
    _pathRecalcTimer = Random().nextDouble() * _pathRecalcInterval;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (attackCooldown > 0) attackCooldown -= dt;
    if (_lungeCooldown > 0) _lungeCooldown -= dt;
    if (_lungeTimer > 0) _lungeTimer = max(0.0, _lungeTimer - dt);

    final distanceToPlayer = position.distanceTo(player.position);

    // Tầm phát hiện chủ động: 380px (hoặc toàn bản đồ nếu đã bị đánh trúng)
    if (distanceToPlayer < 380) {
      _isAggroed = true;
    }

    if (_isAggroed && distanceToPlayer > 18) {
      // Lao vồ tăng tốc ngắn khi áp sát 65..135px có tầm nhìn thẳng
      if (_lungeCooldown <= 0 &&
          distanceToPlayer >= 65 &&
          distanceToPlayer <= 135 &&
          isMounted &&
          (game.walkableGrid.isEmpty ||
              AStarPathfinder.hasLineOfSight(position, player.position, game.walkableGrid))) {
        _lungeTimer = 0.45;
        _lungeCooldown = 4.2;
      }

      if (isMounted && game.walkableGrid.isNotEmpty) {
        _pathRecalcTimer -= dt;
        if (_pathRecalcTimer <= 0) {
          _pathRecalcTimer = _pathRecalcInterval;
          _recalculatePath();
        }
        _followWaypoints(dt, distanceToPlayer);
      } else {
        previousPosition = position.clone();
        final dir = (player.position - position).normalized();
        position.add(dir * _effectiveSpeed * dt);
      }
    } else {
      _waypoints.clear();
      _currentWaypointIndex = 0;
    }

    // Tấn công người chơi khi áp sát
    if (distanceToPlayer <= 28 && attackCooldown <= 0) {
      player.takeDamage(damage);
      attackCooldown = 0.9;
    }
  }

  double get _effectiveSpeed => _lungeTimer > 0 ? speed * 1.65 : speed;

  Vector2 _computeSeparation() {
    if (!isMounted) return Vector2.zero();
    final sep = Vector2.zero();
    for (final other in game.enemies) {
      if (other == this || !other.isMounted) continue;
      final diff = position - other.position;
      final d = diff.length;
      if (d > 0.1 && d < 26.0) {
        sep.add(diff.normalized() * ((26.0 - d) / 26.0));
      }
    }
    return sep;
  }

  void _recalculatePath() {
    _waypoints = AStarPathfinder.findPath(
      position,
      player.position,
      game.walkableGrid,
    );
    _currentWaypointIndex = 0;
  }

  void _followWaypoints(double dt, double distanceToPlayer) {
    Vector2 moveDir;
    if (_waypoints.isEmpty || _currentWaypointIndex >= _waypoints.length) {
      moveDir = (player.position - position);
    } else {
      var targetPt = _waypoints[_currentWaypointIndex];
      if (_currentWaypointIndex == _waypoints.length - 1) {
        targetPt = player.position;
      }
      if (position.distanceTo(targetPt) <= _waypointReachThreshold) {
        _currentWaypointIndex++;
        if (_currentWaypointIndex < _waypoints.length) {
          targetPt = _waypoints[_currentWaypointIndex];
        }
      }
      moveDir = targetPt - position;
    }

    if (moveDir.length2 > 0.0001) {
      moveDir.normalize();
      // Áp dụng tách đàn + đánh bọc sườn nhẹ khi ở tầm trung
      if (distanceToPlayer > 48 && distanceToPlayer < 170) {
        final flank = Vector2(-moveDir.y * _flankSign, moveDir.x * _flankSign) * 0.28;
        moveDir.add(flank);
      }
      final sep = _computeSeparation();
      if (sep.length2 > 0.001) {
        moveDir.add(sep * 0.65);
      }
      if (moveDir.length2 > 0.0001) {
        previousPosition = position.clone();
        position.add(moveDir.normalized() * _effectiveSpeed * dt);
      }
    }
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
      // Thưởng EXP cho player
      player.gainExp(35);
      if (isMounted) {
        game.enemies.remove(this);
      }
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Bóng đổ
    final shadowPaint = Paint()..color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 2), width: 20, height: 6),
      shadowPaint,
    );

    // 2. Thân Zombie xanh rêu (Undead)
    final bodyPaint = Paint()..color = const Color(0xFF388E3C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 14, 16, 16), const Radius.circular(3)),
      bodyPaint,
    );

    // Áo rách tơi tả
    final clothesPaint = Paint()..color = const Color(0xFF4E342E);
    canvas.drawRect(const Rect.fromLTWH(8, 18, 16, 8), clothesPaint);

    // 3. Đầu Zombie
    final headPaint = Paint()..color = const Color(0xFF4CAF50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(7, 2, 18, 14), const Radius.circular(4)),
      headPaint,
    );

    // Mắt đỏ phát sáng rùng rợn
    final eyePaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawRect(const Rect.fromLTWH(11, 7, 3, 3), eyePaint);
    canvas.drawRect(const Rect.fromLTWH(19, 7, 3, 3), eyePaint);

    // 4. Thanh máu nhỏ trên đầu
    final hpBg = Paint()..color = const Color(0xFF212121);
    final hpFill = Paint()..color = const Color(0xFFE53935);
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
