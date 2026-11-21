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

  // A* Navigation state
  List<Vector2> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _pathRecalcTimer = 0.0;
  static const double _pathRecalcInterval = 0.45; // 0.45s re-path
  static const double _waypointReachThreshold = 12.0; // 12px reach radius

  ZombieEnemy({required Vector2 position, required this.player})
      : super(
          position: position,
          size: Vector2(32, 36),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(20, 24),
      position: Vector2(6, 8),
    ));
    // Stagger recalculation across entities to prevent CPU spike on the same frame
    _pathRecalcTimer = Random().nextDouble() * _pathRecalcInterval;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (attackCooldown > 0) attackCooldown -= dt;

    final distanceToPlayer = position.distanceTo(player.position);

    // Tầm phát hiện: 280 pixel
    if (distanceToPlayer < 280 && distanceToPlayer > 18) {
      if (isMounted && game.walkableGrid.isNotEmpty) {
        _pathRecalcTimer -= dt;
        if (_pathRecalcTimer <= 0) {
          _pathRecalcTimer = _pathRecalcInterval;
          _recalculatePath();
        }
        _followWaypoints(dt);
      } else {
        // Fallback di chuyển thẳng nếu chưa mount game
        previousPosition = position.clone();
        final dir = (player.position - position).normalized();
        position.add(dir * speed * dt);
      }
    } else {
      _waypoints.clear();
      _currentWaypointIndex = 0;
    }

    // Tấn công người chơi khi áp sát
    if (distanceToPlayer <= 26 && attackCooldown <= 0) {
      player.takeDamage(damage);
      attackCooldown = 1.0; // 1 giây đánh 1 lần
    }
  }

  void _recalculatePath() {
    _waypoints = AStarPathfinder.findPath(
      position,
      player.position,
      game.walkableGrid,
    );
    _currentWaypointIndex = 0;
  }

  void _followWaypoints(double dt) {
    if (_waypoints.isEmpty || _currentWaypointIndex >= _waypoints.length) {
      // Direct approach fallback
      previousPosition = position.clone();
      final dir = (player.position - position).normalized();
      position.add(dir * speed * dt);
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

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is WallBlock) {
      position = previousPosition.clone();
    }
  }

  void takeDamage(double dmg) {
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
