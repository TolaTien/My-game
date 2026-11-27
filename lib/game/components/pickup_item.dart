import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'player.dart';
import '../../services/audio_service.dart';
import '../big_war_game.dart';

enum PickupType {
  healthPotion,
  expGem,
  goldCoin,
}

class PickupItem extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  final PickupType type;
  double _animationTimer = 0.0;
  bool _collected = false;

  PickupItem({
    required Vector2 position,
    required this.type,
  }) : super(
          position: position,
          size: Vector2(22, 22),
          anchor: Anchor.center,
        ) {
    add(CircleHitbox(
      radius: 9,
      position: Vector2(2, 2),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_collected) return;

    _animationTimer += dt;

    // Hiệu ứng expGem: tự động bay hút về phía player khi trong bán kính 70px
    if (type == PickupType.expGem) {
      final playerPos = game.player.position;
      final dist = position.distanceTo(playerPos);
      if (dist <= 70.0 && dist > 1.0) {
        final dir = (playerPos - position).normalized();
        const magnetSpeed = 200.0;
        position.add(dir * magnetSpeed * dt);
      }
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (_collected) return;

    if (other is PlayerComponent) {
      _collected = true;
      switch (type) {
        case PickupType.healthPotion:
          // Hồi ngay 25 HP
          other.heal(25);
          AudioService.instance.playSfx(SfxSound.pickupPotion);
          break;
        case PickupType.expGem:
          // Nhặt ngọc cộng 30 EXP
          other.gainExp(30);
          AudioService.instance.playSfx(SfxSound.pickupGem);
          break;
        case PickupType.goldCoin:
          // Nhặt vàng: tăng coinsCollected thêm 1 (tương đương 1000 vàng)
          other.coinsCollected += 1;
          other.onStatsChanged?.call();
          AudioService.instance.playSfx(SfxSound.pickupCoin);
          break;
      }
      game.pickups.remove(this);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Hiệu ứng trôi nổi bồng bềnh nhẹ (floating bằng sin(time))
    final floatOffsetY = sin(_animationTimer * 4.0) * 3.5;

    // 1. Bóng đổ trên mặt đất (cố định ở đáy, co dãn nhẹ theo độ nổi)
    final shadowScale = (1.0 - (floatOffsetY / 12.0)).clamp(0.6, 1.4);
    final shadowPaint = Paint()..color = const Color(0x44000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 1),
        width: 14 * shadowScale,
        height: 5 * shadowScale,
      ),
      shadowPaint,
    );

    // 2. Nội dung vật phẩm nổi bồng bềnh
    canvas.save();
    canvas.translate(0, floatOffsetY);

    switch (type) {
      case PickupType.healthPotion:
        _renderHealthPotion(canvas);
        break;
      case PickupType.expGem:
        _renderExpGem(canvas);
        break;
      case PickupType.goldCoin:
        _renderGoldCoin(canvas);
        break;
    }

    canvas.restore();
  }

  void _renderHealthPotion(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Hào quang đỏ mờ
    final glowPaint = Paint()..color = const Color(0x44FF1744);
    if (!kIsWeb) {
      glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    }
    canvas.drawCircle(Offset(cx, cy), 9, glowPaint);

    // Thân bình tròn
    final bottlePaint = Paint()..color = const Color(0xFFD50000);
    canvas.drawCircle(Offset(cx, cy + 2), 6.5, bottlePaint);

    // Viền thủy tinh trong suốt
    final glassStroke = Paint()
      ..color = const Color(0xFFECEFF1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(Offset(cx, cy + 2), 6.5, glassStroke);

    // Cổ bình & nút bần gỗ
    final corkPaint = Paint()..color = const Color(0xFF8D6E63);
    canvas.drawRect(Rect.fromLTWH(cx - 2.5, cy - 6, 5, 3), corkPaint);

    // Điểm phản chiếu ánh sáng trắng trên bình
    final highlightPaint = Paint()..color = const Color(0xEEFFFFFF);
    canvas.drawCircle(Offset(cx - 2.5, cy + 0.5), 1.5, highlightPaint);
  }

  void _renderExpGem(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Hào quang xanh ngọc lấp lánh (Cyan glow)
    final glowPaint = Paint()..color = const Color(0x6600E5FF);
    if (!kIsWeb) {
      glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    }
    canvas.drawCircle(Offset(cx, cy), 8, glowPaint);

    // Viên ngọc lục bảo/lam ngọc hình thoi (Diamond gem)
    final gemPath = Path()
      ..moveTo(cx, cy - 8)
      ..lineTo(cx + 6.5, cy)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx - 6.5, cy)
      ..close();

    final gemPaint = Paint()..color = const Color(0xFF00E5FF);
    canvas.drawPath(gemPath, gemPaint);

    // Cạnh đổ bóng tạo khối 3D cho ngọc
    final darkFacetPath = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx + 6.5, cy)
      ..lineTo(cx, cy + 8)
      ..close();
    final darkFacetPaint = Paint()..color = const Color(0xFF0091EA);
    canvas.drawPath(darkFacetPath, darkFacetPaint);

    // Lõi lấp lánh màu trắng sáng
    final innerPath = Path()
      ..moveTo(cx, cy - 4)
      ..lineTo(cx + 2.5, cy)
      ..lineTo(cx, cy + 4)
      ..lineTo(cx - 2.5, cy)
      ..close();
    final innerPaint = Paint()..color = const Color(0xFFE0F7FA);
    canvas.drawPath(innerPath, innerPaint);
  }

  void _renderGoldCoin(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Hào quang vàng hoàng gia
    final glowPaint = Paint()..color = const Color(0x55FFD700);
    if (!kIsWeb) {
      glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    }
    canvas.drawCircle(Offset(cx, cy), 8, glowPaint);

    // Viền vàng đậm bên ngoài
    final borderPaint = Paint()..color = const Color(0xFFFF8F00);
    canvas.drawCircle(Offset(cx, cy), 6.5, borderPaint);

    // Mặt đồng xu vàng óng
    final coinPaint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawCircle(Offset(cx, cy), 5.2, coinPaint);

    // Vòng tròn chạm khắc bên trong đồng xu
    final innerRingPaint = Paint()
      ..color = const Color(0xFFFFE082)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(cx, cy), 3.2, innerRingPaint);

    // Đốm sáng phản quang lấp lánh
    final shinePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(cx - 2, cy - 2), 1.2, shinePaint);
  }
}
