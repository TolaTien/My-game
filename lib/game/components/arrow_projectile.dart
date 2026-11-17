import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'player.dart';
import 'dungeon_map.dart';

class ArrowProjectile extends PositionComponent with CollisionCallbacks {
  final Vector2 direction;
  final double speed = 220.0;
  final double damage = 10.0;

  double _lifeTimer = 0.0;
  bool _hasHit = false;

  ArrowProjectile({
    required Vector2 position,
    required Vector2 direction,
  })  : direction = direction.length2 > 0 ? direction.normalized() : Vector2(1, 0),
        super(
          position: position,
          size: Vector2(16, 6),
          anchor: Anchor.center,
        ) {
    angle = atan2(this.direction.y, this.direction.x);
    add(RectangleHitbox(
      size: Vector2(12, 4),
      position: Vector2(2, 1),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasHit) return;

    _lifeTimer += dt;
    // Tự huỷ sau 3 giây nếu bay ra ngoài tầm
    if (_lifeTimer >= 3.0) {
      removeFromParent();
      return;
    }

    position.add(direction * speed * dt);
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (_hasHit) return;

    if (other is PlayerComponent) {
      _hasHit = true;
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is WallBlock) {
      _hasHit = true;
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Mũi tên pixel art nằm ngang (hướng theo góc angle đã xoay)
    // 1. Thân tên gỗ nâu
    final shaftPaint = Paint()
      ..color = const Color(0xFF8D6E63)
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(3, 3), const Offset(11, 3), shaftPaint);

    // 2. Lông vũ đuôi tên xám trắng
    final featherPaint = Paint()..color = const Color(0xFFECEFF1);
    final fPath = Path()
      ..moveTo(1, 1)
      ..lineTo(4, 3)
      ..lineTo(1, 5)
      ..close();
    canvas.drawPath(fPath, featherPaint);

    // 3. Đầu mũi tên sắt nhọn hình tam giác kim loại
    final headPaint = Paint()..color = const Color(0xFFCFD8DC);
    final hPath = Path()
      ..moveTo(10, 0.5)
      ..lineTo(15, 3)
      ..lineTo(10, 5.5)
      ..close();
    canvas.drawPath(hPath, headPaint);

    // 4. Đốm sáng đỏ tím ma mị trên mũi tên
    final glowPaint = Paint()..color = const Color(0xFFFF5252);
    canvas.drawCircle(const Offset(13, 3), 1.0, glowPaint);
  }
}
