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
import '../ai/chase_navigation.dart';
import '../gold_rush_game.dart';

class SkeletonEnemy extends PositionComponent
    with CollisionCallbacks, HasGameReference<GoldRushGame> {
  double maxHp = 45.0;
  double currentHp = 45.0;
  double speed = 50.0;

  final PlayerComponent player;
  Vector2 previousPosition = Vector2.zero();
  double shootCooldown = 0.0;
  double stunTimer = 0;
  bool isFacingRight = true;

  final Random random;
  late final ChaseNavigation navigation;

  SkeletonEnemy({required Vector2 position, required this.player, Random? random})
      : random = random ?? Random(),
        super(
          position: position,
          size: Vector2(32, 38),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(20, 26),
      position: Vector2(6, 8),
    ));
    navigation = ChaseNavigation(random: this.random, halfSize: Vector2(10, 15));
  }

  @override
  void update(double dt) {
    super.update(dt);
    previousPosition.setFrom(position);
    if (stunTimer > 0) {
      stunTimer = max(0, stunTimer - dt);
      navigation.pause();
      return;
    }
    if (shootCooldown > 0) shootCooldown -= dt;

    final distanceToPlayer = position.distanceTo(player.position);

    // Luôn quay mặt về phía Player
    isFacingRight = player.position.x >= position.x;

    // AI Kiting & Tactical Archery Behavior:
    if (distanceToPlayer < 110) {
      // 1. Khoảng cách < 110px: Lùi lại (kiting away)
      final away = position - player.position;
      final retreatTarget = away.length2 > 0
          ? position + away.normalized() * 64
          : position + Vector2(64, 0);
      _navigate(dt, retreatTarget);
    } else if (distanceToPlayer > 240) {
      // 2. Khoảng cách > 240px: Tiến lại gần
      if (distanceToPlayer < 500) {
        _navigate(dt, player.position);
      } else {
        navigation.pause();
      }
    } else {
      // 3. Trong tầm 110-240px: Kiểm tra Line-of-Sight trước khi bắn
      bool hasLoS = true;
      if (isMounted && game.walkableGrid.isNotEmpty) {
        hasLoS = AStarPathfinder.hasLineOfSight(
          position,
          player.position,
          game.walkableGrid,
        );
      }

      if (hasLoS) {
        // Đường đạn thông thoáng -> Giữ vị trí và bắn tên mỗi 1.8s
        navigation.pause();
        if (shootCooldown <= 0) {
          _shootArrow();
          shootCooldown = 1.8;
        }
      } else {
        // Bị cản bởi cột đá -> Dùng A* tìm đường vòng sang để flank
        _navigate(dt, player.position);
      }
    }
  }

  void _navigate(double dt, Vector2 target) {
    previousPosition = position.clone();
    position.add(navigation.step(
      position: position,
      target: target,
      grid: isMounted ? game.walkableGrid : const [],
      speed: speed,
      dt: dt,
    ));
  }

  void _shootArrow() {
    if (!isMounted) return;
    final toPlayer = player.position - position;
    if (toPlayer.length2 == 0) return;
    final dir = toPlayer.normalized();

    final spawnOffset = Vector2(isFacingRight ? 12 : -12, 0);
    final arrow = ArrowProjectile(
      position: position + spawnOffset,
      direction: dir,
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

  void applyControl({double stunDuration = 0, double knockback = 0,
      Vector2? direction}) {
    stunTimer = max(stunTimer, stunDuration);
    navigation.pause();
    if (isMounted && direction != null) {
      position.add(ChaseNavigation.knockbackMovement(
        position: position, direction: direction, distance: knockback,
        halfSize: Vector2(10, 15), grid: game.walkableGrid,
      ));
      previousPosition.setFrom(position);
    }
  }

  void takeDamage(double dmg) {
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
    final rand = random.nextDouble();
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
