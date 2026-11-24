import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'player.dart';
import 'dungeon_map.dart';
import '../ai/chase_navigation.dart';
import '../gold_rush_game.dart';

class ZombieEnemy extends PositionComponent
    with CollisionCallbacks, HasGameReference<GoldRushGame> {
  double maxHp = 60.0;
  double currentHp = 60.0;
  double speed = 65.0;
  double damage = 12.0;

  final PlayerComponent player;
  Vector2 previousPosition = Vector2.zero();
  double attackCooldown = 0.0;
  double stunTimer = 0;
  static const double hitFlashDuration = 0.14;
  double _hitFlashTimer = 0;
  double get hitFlashTimer => _hitFlashTimer;

  final ChaseNavigation navigation;

  ZombieEnemy({required Vector2 position, required this.player, Random? random})
      : navigation = ChaseNavigation(repathInterval: 0.45, random: random,
            halfSize: Vector2(10, 14)),
        super(
          position: position,
          size: Vector2(32, 36),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(20, 24),
      position: Vector2(6, 8),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _hitFlashTimer = max(0, _hitFlashTimer - dt);
    previousPosition.setFrom(position);
    if (stunTimer > 0) {
      stunTimer = max(0, stunTimer - dt);
      navigation.pause();
      return;
    }
    if (attackCooldown > 0) attackCooldown -= dt;

    final distanceToPlayer = position.distanceTo(player.position);

    // Tầm phát hiện: 280 pixel
    if (distanceToPlayer < 280 && distanceToPlayer > 18) {
      previousPosition = position.clone();
      position.add(navigation.step(
        position: position,
        target: player.position,
        grid: isMounted ? game.walkableGrid : const [],
        speed: speed,
        dt: dt,
      ));
    } else {
      navigation.pause();
    }

    // Tấn công người chơi khi áp sát
    if (distanceToPlayer <= 26 && attackCooldown <= 0) {
      player.takeDamage(damage);
      attackCooldown = 1.0; // 1 giây đánh 1 lần
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is WallBlock) {
      position = previousPosition.clone();
    }
  }

  void applyControl({double stunDuration = 0, double knockback = 0,
      Vector2? direction}) {
    stunTimer = max(stunTimer, stunDuration);
    navigation.pause();
    if (isMounted && direction != null) {
      position.add(ChaseNavigation.knockbackMovement(
        position: position, direction: direction, distance: knockback,
        halfSize: Vector2(10, 14), grid: game.walkableGrid,
      ));
      previousPosition.setFrom(position);
    }
  }

  void takeDamage(double dmg) {
    currentHp -= dmg;
    if (currentHp <= 0) {
      _hitFlashTimer = 0;
      // Thưởng EXP cho player
      player.gainExp(35);
      if (isMounted) {
        game.enemies.remove(this);
      }
      removeFromParent();
    } else if (dmg > 0) {
      _hitFlashTimer = hitFlashDuration;
    }
  }

  Color _hitTint(Color base) => Color.lerp(
    base,
    const Color(0xFFFFB3A7),
    0.65 * _hitFlashTimer / hitFlashDuration,
  )!;

  @override
  void render(Canvas canvas) {
    if (currentHp <= 0) return;
    super.render(canvas);

    // 1. Bóng đổ
    final shadowPaint = Paint()..color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 2), width: 20, height: 6),
      shadowPaint,
    );

    // 2. Thân Zombie xanh rêu (Undead)
    final bodyPaint = Paint()..color = _hitTint(const Color(0xFF388E3C));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 14, 16, 16), const Radius.circular(3)),
      bodyPaint,
    );

    // Áo rách tơi tả
    final clothesPaint = Paint()..color = _hitTint(const Color(0xFF4E342E));
    canvas.drawRect(const Rect.fromLTWH(8, 18, 16, 8), clothesPaint);

    // 3. Đầu Zombie
    final headPaint = Paint()..color = _hitTint(const Color(0xFF4CAF50));
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
