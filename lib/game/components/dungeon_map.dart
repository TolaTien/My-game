import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../registry/asset_registry.dart';
import '../../registry/sprite_image_cache.dart';
import '../ai/astar_pathfinder.dart';

class WallBlock extends PositionComponent with CollisionCallbacks {
  final String theme;
  final bool isBoundary;

  WallBlock({
    required Vector2 position,
    required Vector2 size,
    this.theme = 'golden_sanctum',
    this.isBoundary = false,
  }) : super(position: position, size: size, priority: -5) {
    add(RectangleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    final isPillar = size.x > GameConstants.tileSize * 1.2;
    final isIceTheme = theme == 'ice_arena' ||
        theme == 'frost_island' ||
        theme == 'ice_island' ||
        theme == 'map_bang' ||
        theme == 'map_dao_bang_gia';
    final rect = ui.Rect.fromLTWH(0, 0, size.x, size.y);

    if (isIceTheme) {
      if (isBoundary) {
        // Tường băng biên giới tinh xảo trong suốt để lộ tác phẩm ảnh nền bản đồ
        final iceBarrierPaint = ui.Paint()..color = const ui.Color(0x3500E5FF);
        final iceEdgePaint = ui.Paint()
          ..color = const ui.Color(0x7780DEEA)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRect(rect, iceBarrierPaint);
        canvas.drawRect(rect, iceEdgePaint);
        return;
      }

      // Trụ đá khối băng tinh thể (Glacial Ice Pillar)
      final paintBody = ui.Paint()..color = const ui.Color(0xFF14243B);
      final paintTop = ui.Paint()..color = const ui.Color(0xFF265077);
      final paintBorder = ui.Paint()
        ..color = const ui.Color(0xFF091422)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRect(rect, paintBody);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y * 0.32), paintTop);

      // Đường chỉ pha lê băng sáng
      canvas.drawLine(
        ui.Offset(2, size.y * 0.32),
        ui.Offset(size.x - 2, size.y * 0.32),
        ui.Paint()
          ..color = const ui.Color(0xFF00E5FF).withValues(alpha: 0.85)
          ..strokeWidth = 1.5,
      );

      if (isPillar) {
        // Tinh thể kim cương băng giá phát quang
        final center = ui.Offset(size.x / 2, size.y / 2);
        final crystalPath = ui.Path()
          ..moveTo(center.dx, center.dy - 15)
          ..lineTo(center.dx + 11, center.dy)
          ..lineTo(center.dx, center.dy + 15)
          ..lineTo(center.dx - 11, center.dy)
          ..close();
        // Hào quang băng
        canvas.drawCircle(
          center,
          18,
          ui.Paint()
            ..color = const ui.Color(0x3300FFFF)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
        );
        canvas.drawPath(
          crystalPath,
          ui.Paint()..color = const ui.Color(0xFFB2EBF2),
        );
        canvas.drawPath(
          crystalPath,
          ui.Paint()
            ..color = const ui.Color(0xFF00E5FF)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
      canvas.drawRect(rect, paintBorder);
      return;
    }

    // Theme mặc định: Thần Điện Hoàng Kim (Sunken Golden Sanctum)
    final paintBody = ui.Paint()..color = const ui.Color(0xFF283040);
    final paintTop = ui.Paint()..color = const ui.Color(0xFF3E4A62);
    final paintBorder = ui.Paint()
      ..color = const ui.Color(0xFF151922)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(rect, paintBody);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y * 0.32), paintTop);

    // Đường chỉ vàng cổ đại (Golden Sanctum Trim)
    canvas.drawLine(
      ui.Offset(2, size.y * 0.32),
      ui.Offset(size.x - 2, size.y * 0.32),
      ui.Paint()
        ..color = const ui.Color(0xFFD4AF37).withValues(alpha: 0.75)
        ..strokeWidth = 1.5,
    );

    if (isPillar) {
      // Tinh thể lôi điện & Phù điêu hoàng kim trên trụ đá cổ
      final center = ui.Offset(size.x / 2, size.y / 2);
      final crystalPath = ui.Path()
        ..moveTo(center.dx, center.dy - 14)
        ..lineTo(center.dx + 10, center.dy)
        ..lineTo(center.dx, center.dy + 14)
        ..lineTo(center.dx - 10, center.dy)
        ..close();
      canvas.drawPath(
        crystalPath,
        ui.Paint()..color = const ui.Color(0xFF00F0FF).withValues(alpha: 0.75),
      );
      canvas.drawPath(
        crystalPath,
        ui.Paint()
          ..color = const ui.Color(0xFFFFD700)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawRect(rect, paintBorder);
  }
}

/// Bản đồ chiến trường ngẫu nhiên (Thần Điện Hoàng Kim / Đấu Trường Băng Giá / Đảo Băng Tuyết)
class DungeonMapComponent extends Component {
  static const int mapWidthTiles = 36;
  static const int mapHeightTiles = 24;

  final double tileSize = GameConstants.tileSize;
  final MapAssetConfig mapConfig;

  ui.Image? _mapImage;

  /// Ma trận ô di chuyển (true = đi được, false = tường/cột đá)
  late final List<List<bool>> walkableGrid;

  DungeonMapComponent({MapAssetConfig? config})
      : mapConfig = config ??
            (GameAssetRegistry.instance.getMap('sunken_golden_sanctum') ??
                GameAssetRegistry.defaultSanctumMap),
        super(priority: -10) {
    walkableGrid = AStarPathfinder.buildDungeonWalkableGrid(
      width: mapWidthTiles,
      height: mapHeightTiles,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Tải trước ảnh nền map trực tiếp (chờ xong mới render để đảm bảo hiển thị đúng tranh)
    if (mapConfig.imageAsset.isNotEmpty) {
      _mapImage = await SpriteImageCache.instance.loadMapImageByPath(
        mapConfig.imageAsset,
        mapId: mapConfig.id,
      );
    }

    final wallTheme = mapConfig.theme;

    // Sinh tường bao quanh
    for (int col = 0; col < mapWidthTiles; col++) {
      // Tường trên
      add(WallBlock(
        position: Vector2(col * tileSize, 0),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
      // Tường dưới
      add(WallBlock(
        position: Vector2(col * tileSize, (mapHeightTiles - 1) * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
    }

    for (int row = 1; row < mapHeightTiles - 1; row++) {
      // Tường trái
      add(WallBlock(
        position: Vector2(0, row * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
      // Tường phải
      add(WallBlock(
        position: Vector2((mapWidthTiles - 1) * tileSize, row * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
    }

    // 6 Trụ đá / Trụ băng tinh thể trong hầm ngục (khớp hoàn toàn với A* grid)
    _addPillar(8, 6, wallTheme);
    _addPillar(8, 16, wallTheme);
    _addPillar(26, 6, wallTheme);
    _addPillar(26, 16, wallTheme);
    _addPillar(17, 10, wallTheme);
    _addPillar(18, 10, wallTheme);
  }

  void _addPillar(int col, int row, String theme) {
    add(WallBlock(
      position: Vector2(col * tileSize, row * tileSize),
      size: Vector2(tileSize * 2, tileSize * 2),
      theme: theme,
      isBoundary: false,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_mapImage == null && mapConfig.imageAsset.isNotEmpty) {
      _mapImage = SpriteImageCache.instance.getMapImage(mapConfig.id);
    }
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);

    final totalW = mapWidthTiles * tileSize;
    final totalH = mapHeightTiles * tileSize;
    final isIceTheme = mapConfig.theme == 'ice_arena' ||
        mapConfig.theme == 'frost_island' ||
        mapConfig.theme == 'ice_island' ||
        mapConfig.id == 'map_bang' ||
        mapConfig.id == 'map_dao_bang_gia';

    // 1. NỀN BẢN ĐỒ
    if (_mapImage != null) {
      canvas.drawImageRect(
        _mapImage!,
        ui.Rect.fromLTWH(
          0,
          0,
          _mapImage!.width.toDouble(),
          _mapImage!.height.toDouble(),
        ),
        ui.Rect.fromLTWH(0, 0, totalW, totalH),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    } else {
      // Nền dự phòng (xanh băng cho theme băng, đá hoàng kim cho thần điện)
      final lightPaint = isIceTheme
          ? (ui.Paint()..color = const ui.Color(0xFF1B324B))
          : (ui.Paint()..color = const ui.Color(0xFF2D3440));
      final darkPaint = isIceTheme
          ? (ui.Paint()..color = const ui.Color(0xFF102033))
          : (ui.Paint()..color = const ui.Color(0xFF222831));
      final veinPaint = isIceTheme
          ? (ui.Paint()
            ..color = const ui.Color(0xFF00E5FF).withValues(alpha: 0.35)
            ..strokeWidth = 1.2
            ..style = ui.PaintingStyle.stroke)
          : (ui.Paint()
            ..color = const ui.Color(0xFFD4AF37).withValues(alpha: 0.28)
            ..strokeWidth = 1.2
            ..style = ui.PaintingStyle.stroke);

      for (int r = 0; r < mapHeightTiles; r++) {
        for (int c = 0; c < mapWidthTiles; c++) {
          final paint = (r + c) % 2 == 0 ? lightPaint : darkPaint;
          final rect =
              ui.Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize);
          canvas.drawRect(rect, paint);

          if ((r * 7 + c * 5) % 11 == 0) {
            canvas.drawLine(
              ui.Offset(rect.left + 4, rect.top + 8),
              ui.Offset(rect.right - 6, rect.bottom - 6),
              veinPaint,
            );
          }
        }
      }
    }

    // 2. VÒNG MA TRẬN TRUNG TÂM (Phù hợp theo chủ đề bản đồ)
    final centerOffset = ui.Offset(totalW / 2, totalH / 2);
    if (isIceTheme) {
      // Vòng Trận Pháp Băng Tinh (Frost Nexus Circle)
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()..color = const ui.Color(0x1500E5FF),
      );
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()
          ..color = const ui.Color(0xFF00E5FF).withValues(alpha: 0.65)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        centerOffset,
        96,
        ui.Paint()
          ..color = const ui.Color(0xFF80DEEA).withValues(alpha: 0.45)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final octPath = ui.Path();
      for (int i = 0; i < 8; i++) {
        final angle = i * (pi / 4);
        final pt = ui.Offset(
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
        ui.Paint()
          ..color = const ui.Color(0x6600FFFF)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else {
      // Vòng Trận Pháp Hoàng Kim (Sunken Golden Sanctum Magic Circle)
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()..color = const ui.Color(0x18FFD700),
      );
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()
          ..color = const ui.Color(0xFFD4AF37).withValues(alpha: 0.65)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        centerOffset,
        96,
        ui.Paint()
          ..color = const ui.Color(0xFF00F0FF).withValues(alpha: 0.35)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final octPath = ui.Path();
      for (int i = 0; i < 8; i++) {
        final angle = i * (pi / 4);
        final pt = ui.Offset(
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
        ui.Paint()
          ..color = const ui.Color(0x55FFD700)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // 3. 4 CỔNG SPAWN QUÁI VẬT (Monster Portals)
    final portalTiles = [
      const ui.Offset(4.5, 4.5),
      const ui.Offset(31.5, 4.5),
      const ui.Offset(4.5, 19.5),
      const ui.Offset(31.5, 19.5),
    ];
    for (final tile in portalTiles) {
      final pCenter = ui.Offset(tile.dx * tileSize, tile.dy * tileSize);
      if (isIceTheme) {
        // Cổng băng xoáy lạnh sâu thẳm
        canvas.drawCircle(
          pCenter,
          24,
          ui.Paint()..color = const ui.Color(0x3300838F),
        );
        canvas.drawCircle(
          pCenter,
          18,
          ui.Paint()
            ..color = const ui.Color(0xFF00E5FF).withValues(alpha: 0.75)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(
          pCenter,
          10,
          ui.Paint()..color = const ui.Color(0xFF002233),
        );
      } else {
        // Cổng ma thuật tím đen thần điện
        canvas.drawCircle(
          pCenter,
          24,
          ui.Paint()..color = const ui.Color(0x447B1FA2),
        );
        canvas.drawCircle(
          pCenter,
          18,
          ui.Paint()
            ..color = const ui.Color(0xFFE040FB).withValues(alpha: 0.7)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(
          pCenter,
          10,
          ui.Paint()..color = const ui.Color(0xFF1A0033),
        );
      }
    }
  }
}
