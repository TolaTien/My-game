import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../core/constants.dart';
import '../../registry/asset_registry.dart';
import '../../registry/sprite_image_cache.dart';
import '../ai/astar_pathfinder.dart';

class WallBlock extends PositionComponent with CollisionCallbacks {
  final String theme;
  final bool isBoundary;
  ui.Picture? _staticPicture;
  (double, double)? _pictureSize;

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
    final geometry = (size.x, size.y);
    if (_staticPicture == null || _pictureSize != geometry) {
      _staticPicture?.dispose();
      final recorder = ui.PictureRecorder();
      _drawWall(ui.Canvas(recorder));
      _staticPicture = recorder.endRecording();
      _pictureSize = geometry;
    }
    canvas.drawPicture(_staticPicture!);
  }

  @override
  void onRemove() {
    _staticPicture?.dispose();
    _staticPicture = null;
    _pictureSize = null;
    super.onRemove();
  }

  void _drawWall(ui.Canvas canvas) {
    final isPillar = size.x > GameConstants.tileSize * 1.2;
    final isIceTheme =
        theme == 'ice_arena' ||
        theme == 'frost_island' ||
        theme == 'ice_island' ||
        theme == 'map_bang' ||
        theme == 'map_dao_bang_gia';
    final isForestTheme =
        theme == 'forest' ||
        theme == 'nature' ||
        theme == 'forest_island' ||
        theme == 'map_rung_cay';
    final rect = ui.Rect.fromLTWH(0, 0, size.x, size.y);

    if (isForestTheme) {
      if (isBoundary) {
        // Tường ranh giới rừng cây trong suốt tinh tế
        final forestBarrierPaint = ui.Paint()
          ..color = const ui.Color(0x201B5E20);
        final forestEdgePaint = ui.Paint()
          ..color = const ui.Color(0x6669F0AE)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawRect(rect, forestBarrierPaint);
        canvas.drawRect(rect, forestEdgePaint);
        return;
      }

      // Trụ cây cổ thụ rừng nguyên sinh (Ancient Forest Trunk / Mossy Pillar)
      final paintBody = ui.Paint()..color = const ui.Color(0xFF261C14);
      final paintTop = ui.Paint()..color = const ui.Color(0xFF2E4F28);
      final paintBorder = ui.Paint()
        ..color = const ui.Color(0xFF140E0A)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRect(rect, paintBody);
      canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.x, size.y * 0.35), paintTop);

      // Đường viền lá mạ vàng xanh rừng
      canvas.drawLine(
        ui.Offset(2, size.y * 0.35),
        ui.Offset(size.x - 2, size.y * 0.35),
        ui.Paint()
          ..color = const ui.Color(0xFF69F0AE).withValues(alpha: 0.85)
          ..strokeWidth = 1.5,
      );

      if (isPillar) {
        // Tinh thể ngọc bích tự nhiên phát quang (Emerald Rune Core)
        final center = ui.Offset(size.x / 2, size.y / 2);
        final runePath = ui.Path()
          ..moveTo(center.dx, center.dy - 14)
          ..lineTo(center.dx + 11, center.dy)
          ..lineTo(center.dx, center.dy + 14)
          ..lineTo(center.dx - 11, center.dy)
          ..close();

        // Hào quang xanh ngọc
        canvas.drawCircle(
          center,
          18,
          ui.Paint()
            ..color = const ui.Color(0x3300E676)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6),
        );
        canvas.drawPath(
          runePath,
          ui.Paint()..color = const ui.Color(0xFFB9F6CA),
        );
        canvas.drawPath(
          runePath,
          ui.Paint()
            ..color = const ui.Color(0xFF00E676)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
      canvas.drawRect(rect, paintBorder);
      return;
    }

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
  static const int mapWidthTiles = MapAssetConfig.defaultCols;
  static const int mapHeightTiles = MapAssetConfig.defaultRows;

  final double tileSize = GameConstants.tileSize;
  final MapAssetConfig mapConfig;
  late final List<List<int>> _obstacles;

  int get widthTiles => mapConfig.widthTiles;
  int get heightTiles => mapConfig.heightTiles;

  ui.Image? _mapImage;
  ui.Picture? _floorPicture;
  int _backgroundGeneration = 0;

  /// Ma trận ô di chuyển (true = đi được, false = tường/cột đá)
  late final List<List<bool>> walkableGrid;

  DungeonMapComponent({MapAssetConfig? config})
    : mapConfig =
          config ??
          (GameAssetRegistry.instance.getMap('sunken_golden_sanctum') ??
              GameAssetRegistry.defaultSanctumMap),
      super(priority: -10) {
    _obstacles = AStarPathfinder.dungeonObstacles(
      width: widthTiles,
      height: heightTiles,
      mapId: mapConfig.id,
      obstacles: mapConfig.obstacles,
    );
    walkableGrid = AStarPathfinder.buildDungeonWalkableGrid(
      width: widthTiles,
      height: heightTiles,
      mapId: mapConfig.id,
      obstacles: _obstacles,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final generation = ++_backgroundGeneration;
    if (mapConfig.imageAsset.isNotEmpty) {
      _mapImage = SpriteImageCache.instance.getMapImage(mapConfig.id);
      if (_mapImage == null) unawaited(_loadBackground(generation));
    }

    final wallTheme = mapConfig.theme;

    // Sinh tường bao quanh
    for (int col = 0; col < widthTiles; col++) {
      // Tường trên
      add(
        WallBlock(
          position: Vector2(col * tileSize, 0),
          size: Vector2(tileSize, tileSize),
          theme: wallTheme,
          isBoundary: true,
        ),
      );
      // Tường dưới
      if (heightTiles == 1) continue;
      add(
        WallBlock(
          position: Vector2(col * tileSize, (heightTiles - 1) * tileSize),
          size: Vector2(tileSize, tileSize),
          theme: wallTheme,
          isBoundary: true,
        ),
      );
    }

    for (int row = 1; row < heightTiles - 1; row++) {
      // Tường trái
      add(
        WallBlock(
          position: Vector2(0, row * tileSize),
          size: Vector2(tileSize, tileSize),
          theme: wallTheme,
          isBoundary: true,
        ),
      );
      // Tường phải
      if (widthTiles == 1) continue;
      add(
        WallBlock(
          position: Vector2((widthTiles - 1) * tileSize, row * tileSize),
          size: Vector2(tileSize, tileSize),
          theme: wallTheme,
          isBoundary: true,
        ),
      );
    }

    for (final rect in _obstacles) {
      final w = rect.length == 2 ? 2 : rect[2];
      final h = rect.length == 2 ? 2 : rect[3];
      add(
        WallBlock(
          position: Vector2(rect[0] * tileSize, rect[1] * tileSize),
          size: Vector2(w * tileSize, h * tileSize),
          theme: wallTheme,
          isBoundary: w != 2 || h != 2,
        ),
      );
    }
  }

  Future<void> _loadBackground(int generation) async {
    try {
      final image = await SpriteImageCache.instance.loadMapImageByPath(
        mapConfig.imageAsset,
        mapId: mapConfig.id,
      );
      if (generation != _backgroundGeneration ||
          isRemoving ||
          isRemoved ||
          image == null) {
        return;
      }
      _mapImage = image;
      _floorPicture?.dispose();
      _floorPicture = null;
    } catch (_) {
      // Gameplay remains available if decorative art cannot be loaded.
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_mapImage == null && mapConfig.imageAsset.isNotEmpty) {
      final image = SpriteImageCache.instance.getMapImage(mapConfig.id);
      if (image != null) {
        _mapImage = image;
        _floorPicture?.dispose();
        _floorPicture = null;
      }
    }
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    if (_floorPicture == null) {
      final recorder = ui.PictureRecorder();
      _drawFloor(ui.Canvas(recorder));
      _floorPicture = recorder.endRecording();
    }
    canvas.drawPicture(_floorPicture!);
  }

  @override
  void onRemove() {
    _backgroundGeneration++;
    _floorPicture?.dispose();
    _floorPicture = null;
    super.onRemove();
  }

  void _drawFloor(ui.Canvas canvas) {
    final totalW = widthTiles * tileSize;
    final totalH = heightTiles * tileSize;
    final isIceTheme =
        mapConfig.theme == 'ice_arena' ||
        mapConfig.theme == 'frost_island' ||
        mapConfig.theme == 'ice_island' ||
        mapConfig.id == 'map_bang' ||
        mapConfig.id == 'map_dao_bang_gia';
    final isForestTheme =
        mapConfig.theme == 'forest' ||
        mapConfig.theme == 'nature' ||
        mapConfig.id == 'map_rung_cay';

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
      // Nền dự phòng (xanh băng cho theme băng, xanh thảo mộc cho rừng, đá hoàng kim cho thần điện)
      final lightPaint = isIceTheme
          ? (ui.Paint()..color = const ui.Color(0xFF1B324B))
          : isForestTheme
          ? (ui.Paint()..color = const ui.Color(0xFF2E4F28))
          : (ui.Paint()..color = const ui.Color(0xFF2D3440));
      final darkPaint = isIceTheme
          ? (ui.Paint()..color = const ui.Color(0xFF102033))
          : isForestTheme
          ? (ui.Paint()..color = const ui.Color(0xFF223A1E))
          : (ui.Paint()..color = const ui.Color(0xFF222831));
      final veinPaint = isIceTheme
          ? (ui.Paint()
              ..color = const ui.Color(0xFF00E5FF).withValues(alpha: 0.35)
              ..strokeWidth = 1.2
              ..style = ui.PaintingStyle.stroke)
          : isForestTheme
          ? (ui.Paint()
              ..color = const ui.Color(0xFF81C784).withValues(alpha: 0.35)
              ..strokeWidth = 1.2
              ..style = ui.PaintingStyle.stroke)
          : (ui.Paint()
              ..color = const ui.Color(0xFFD4AF37).withValues(alpha: 0.28)
              ..strokeWidth = 1.2
              ..style = ui.PaintingStyle.stroke);

      for (int r = 0; r < heightTiles; r++) {
        for (int c = 0; c < widthTiles; c++) {
          final paint = (r + c) % 2 == 0 ? lightPaint : darkPaint;
          final rect = ui.Rect.fromLTWH(
            c * tileSize,
            r * tileSize,
            tileSize,
            tileSize,
          );
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
    if (isForestTheme) {
      // Vòng Trận Pháp Thảo Mộc / Sinh Mệnh Rừng Xanh
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()..color = const ui.Color(0x1800E676),
      );
      canvas.drawCircle(
        centerOffset,
        125,
        ui.Paint()
          ..color = const ui.Color(0xFF00E676).withValues(alpha: 0.65)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      canvas.drawCircle(
        centerOffset,
        96,
        ui.Paint()
          ..color = const ui.Color(0xFF69F0AE).withValues(alpha: 0.45)
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
          ..color = const ui.Color(0x6669F0AE)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else if (isIceTheme) {
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

    // 3. 4 CỔNG SPAWN QUÁI VẬT (Monster Portals - Động theo MapConfig)
    final portalTiles = mapConfig.monsterPortals.isNotEmpty
        ? mapConfig.monsterPortals
              .map((p) => ui.Offset(p[0] + 0.5, p[1] + 0.5))
              .toList()
        : const [
            ui.Offset(4.5, 4.5),
            ui.Offset(31.5, 4.5),
            ui.Offset(4.5, 19.5),
            ui.Offset(31.5, 19.5),
          ];
    for (final tile in portalTiles) {
      if (tile.dx < 1 ||
          tile.dx >= widthTiles - 1 ||
          tile.dy < 1 ||
          tile.dy >= heightTiles - 1) {
        continue;
      }
      final pCenter = ui.Offset(tile.dx * tileSize, tile.dy * tileSize);
      if (isForestTheme) {
        // Cổng rừng sâu ma mị thảo mộc
        canvas.drawCircle(
          pCenter,
          24,
          ui.Paint()..color = const ui.Color(0x441B5E20),
        );
        canvas.drawCircle(
          pCenter,
          18,
          ui.Paint()
            ..color = const ui.Color(0xFF69F0AE).withValues(alpha: 0.75)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(
          pCenter,
          10,
          ui.Paint()..color = const ui.Color(0xFF0A220F),
        );
      } else if (isIceTheme) {
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
