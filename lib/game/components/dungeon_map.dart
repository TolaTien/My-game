import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import '../../core/constants.dart';
import '../ai/astar_pathfinder.dart';

class WallBlock extends PositionComponent with CollisionCallbacks {
  WallBlock({required Vector2 position, required Vector2 size})
      : super(position: position, size: size) {
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final isPillar = size.x > GameConstants.tileSize * 1.2;

    final paintBody = Paint()..color = const Color(0xFF283040);
    final paintTop = Paint()..color = const Color(0xFF3E4A62);
    final paintBorder = Paint()
      ..color = const Color(0xFF151922)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(rect, paintBody);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y * 0.32), paintTop);

    // Đường chỉ vàng cổ đại (Golden Sanctum Trim)
    canvas.drawLine(
      Offset(2, size.y * 0.32),
      Offset(size.x - 2, size.y * 0.32),
      Paint()
        ..color = const Color(0xFFD4AF37).withValues(alpha: 0.75)
        ..strokeWidth = 1.5,
    );

    if (isPillar) {
      // Tinh thể lôi điện & Phù điêu hoàng kim trên trụ đá cổ
      final center = Offset(size.x / 2, size.y / 2);
      final crystalPath = Path()
        ..moveTo(center.dx, center.dy - 14)
        ..lineTo(center.dx + 10, center.dy)
        ..lineTo(center.dx, center.dy + 14)
        ..lineTo(center.dx - 10, center.dy)
        ..close();
      canvas.drawPath(
        crystalPath,
        Paint()..color = const Color(0xFF00F0FF).withValues(alpha: 0.75),
      );
      canvas.drawPath(
        crystalPath,
        Paint()
          ..color = const Color(0xFFFFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawRect(rect, paintBorder);
  }
}

/// Bản đồ Phế Tích Thần Điện Hoàng Kim (Sunken Golden Sanctum)
class DungeonMapComponent extends Component {
  static const int mapWidthTiles = 36;
  static const int mapHeightTiles = 24;

  final double tileSize = GameConstants.tileSize;

  /// Ma trận ô di chuyển (true = đi được, false = tường/cột đá)
  late final List<List<bool>> walkableGrid;

  DungeonMapComponent() {
    walkableGrid = AStarPathfinder.buildDungeonWalkableGrid(
      width: mapWidthTiles,
      height: mapHeightTiles,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Sinh tường bao quanh
    for (int col = 0; col < mapWidthTiles; col++) {
      // Tường trên
      add(WallBlock(
        position: Vector2(col * tileSize, 0),
        size: Vector2(tileSize, tileSize),
      ));
      // Tường dưới
      add(WallBlock(
        position: Vector2(col * tileSize, (mapHeightTiles - 1) * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
    }

    for (int row = 1; row < mapHeightTiles - 1; row++) {
      // Tường trái
      add(WallBlock(
        position: Vector2(0, row * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
      // Tường phải
      add(WallBlock(
        position: Vector2((mapWidthTiles - 1) * tileSize, row * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
    }

    // 6 Trụ đá tinh thể cổ đại trong hầm ngục (khớp hoàn toàn với A* grid)
    _addPillar(8, 6);
    _addPillar(8, 16);
    _addPillar(26, 6);
    _addPillar(26, 16);
    _addPillar(17, 10);
    _addPillar(18, 10);
  }

  void _addPillar(int col, int row) {
    add(WallBlock(
      position: Vector2(col * tileSize, row * tileSize),
      size: Vector2(tileSize * 2, tileSize * 2),
    ));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Vẽ nền sàn đá hoa cương cổ (#222831, #2D3440) với mạch quặng vàng (#D4AF37)
    final lightPaint = Paint()..color = const Color(0xFF2D3440);
    final darkPaint = Paint()..color = const Color(0xFF222831);
    final goldVeinPaint = Paint()
      ..color = const Color(0xFFD4AF37).withValues(alpha: 0.28)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < mapHeightTiles; r++) {
      for (int c = 0; c < mapWidthTiles; c++) {
        final paint = (r + c) % 2 == 0 ? lightPaint : darkPaint;
        final rect = Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);
        canvas.drawRect(rect, paint);

        // Vẽ các rãnh mạch vàng cổ đại trên các ô đặc trưng
        if ((r * 7 + c * 5) % 11 == 0) {
          canvas.drawLine(
            Offset(rect.left + 4, rect.top + 8),
            Offset(rect.right - 6, rect.bottom - 6),
            goldVeinPaint,
          );
        }
      }
    }

    // 2. Quảng trường trung tâm: Vòng Trận Pháp Hoàng Kim (Sunken Golden Sanctum Magic Circle)
    final centerOffset = Offset(
      (mapWidthTiles * tileSize) / 2,
      (mapHeightTiles * tileSize) / 2,
    );
    canvas.drawCircle(
      centerOffset,
      125,
      Paint()..color = const Color(0x18FFD700),
    );
    canvas.drawCircle(
      centerOffset,
      125,
      Paint()
        ..color = const Color(0xFFD4AF37).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(
      centerOffset,
      96,
      Paint()
        ..color = const Color(0xFF00F0FF).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Hình bát giác cổ ngữ trong Vòng Trận Pháp
    final octPath = Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * (pi / 4);
      final pt = Offset(
        centerOffset.dx + cos(angle) * 110,
        centerOffset.dy + sin(angle) * 110,
      );
      if (i == 0) {
        octPath.moveTo(pt.dx, pt.dy);
      } else {
        octPath.lineTo(pt.dx, pt.dy);
      }
    }
    octPath.close();
    canvas.drawPath(
      octPath,
      Paint()
        ..color = const Color(0x55FFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 3. 4 Cổng Spawn Quái (Monster Portals) xoáy không gian màu tím đen phát sáng ở 4 góc đền thờ
    final portalTiles = [
      const Offset(4.5, 4.5),
      const Offset(31.5, 4.5),
      const Offset(4.5, 19.5),
      const Offset(31.5, 19.5),
    ];
    for (final tile in portalTiles) {
      final pCenter = Offset(tile.dx * tileSize, tile.dy * tileSize);
      canvas.drawCircle(
        pCenter,
        24,
        Paint()..color = const Color(0x447B1FA2),
      );
      canvas.drawCircle(
        pCenter,
        18,
        Paint()
          ..color = const Color(0xFFE040FB).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawCircle(
        pCenter,
        10,
        Paint()..color = const Color(0xFF1A0033),
      );
    }
  }
}
