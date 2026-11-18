import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/constants.dart';
import '../../models/pvp_match.dart';
import '../../registry/asset_registry.dart';
import '../../registry/sprite_image_cache.dart';
import 'dungeon_map.dart';

/// Bản đồ đấu trường đối xứng 960x640 dành cho PvP 1v1 / 2v2 / 4v4:
/// Hỗ trợ nạp ngẫu nhiên: Thần Điện Hoàng Kim / Đấu Trường Băng Giá / Đảo Băng Tuyết.
class PvpArenaMapComponent extends Component {
  static const int mapWidthTiles = 30;
  static const int mapHeightTiles = 20;
  static const double arenaWidth = 960.0;
  static const double arenaHeight = 640.0;
  final double tileSize = GameConstants.tileSize;
  final PvpGameMode gameMode;
  final MapAssetConfig mapConfig;

  ui.Image? _mapImage;

  static final List<ui.Offset> blueTeamPads = [
    const ui.Offset(200, 320),
    const ui.Offset(170, 205),
    const ui.Offset(170, 435),
    const ui.Offset(130, 320),
  ];

  static final List<ui.Offset> redTeamPads = [
    const ui.Offset(760, 320),
    const ui.Offset(790, 205),
    const ui.Offset(790, 435),
    const ui.Offset(830, 320),
  ];

  PvpArenaMapComponent({
    this.gameMode = PvpGameMode.solo1v1,
    MapAssetConfig? mapConfig,
  })  : mapConfig = mapConfig ??
            (GameAssetRegistry.instance.getMap('sunken_golden_sanctum') ??
                GameAssetRegistry.defaultSanctumMap),
        super(priority: -10);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Tải trước ảnh nền map trực tiếp (chờ xong mới render)
    if (mapConfig.imageAsset.isNotEmpty) {
      _mapImage = await SpriteImageCache.instance.loadMapImageByPath(
        mapConfig.imageAsset,
        mapId: mapConfig.id,
      );
    }

    final wallTheme = mapConfig.theme;

    // 1. Sinh tường bao quanh trên và dưới
    for (int col = 0; col < mapWidthTiles; col++) {
      add(WallBlock(
        position: Vector2(col * tileSize, 0),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
      add(WallBlock(
        position: Vector2(col * tileSize, (mapHeightTiles - 1) * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
    }

    // 2. Sinh tường bao quanh trái và phải
    for (int row = 1; row < mapHeightTiles - 1; row++) {
      add(WallBlock(
        position: Vector2(0, row * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
      add(WallBlock(
        position: Vector2((mapWidthTiles - 1) * tileSize, row * tileSize),
        size: Vector2(tileSize, tileSize),
        theme: wallTheme,
        isBoundary: true,
      ));
    }

    // 3. 4 Cột trụ đá/băng đấu trường đối xứng (kích thước 48x48)
    _addArenaPillar(Vector2(280 - 24, 200 - 24), wallTheme);
    _addArenaPillar(Vector2(280 - 24, 440 - 24), wallTheme);
    _addArenaPillar(Vector2(680 - 24, 200 - 24), wallTheme);
    _addArenaPillar(Vector2(680 - 24, 440 - 24), wallTheme);
  }

  void _addArenaPillar(Vector2 pos, String theme) {
    add(WallBlock(
      position: pos,
      size: Vector2(48, 48),
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

    final isIceTheme = mapConfig.theme == 'ice_arena' ||
        mapConfig.theme == 'frost_island' ||
        mapConfig.theme == 'ice_island' ||
        mapConfig.id == 'map_bang' ||
        mapConfig.id == 'map_dao_bang_gia';

    // 0. Nền không gian mở rộng phía ngoài tường đấu trường (tránh hẫng đen khi Camera follow)
    final outerBgPaint = ui.Paint()
      ..color = isIceTheme
          ? const ui.Color(0xFF0D1B2A)
          : const ui.Color(0xFF141722);
    canvas.drawRect(
      const ui.Rect.fromLTWH(-600, -400, arenaWidth + 1200, arenaHeight + 800),
      outerBgPaint,
    );

    // 1. Vẽ nền sàn đấu trường
    if (_mapImage != null) {
      canvas.drawImageRect(
        _mapImage!,
        ui.Rect.fromLTWH(
          0,
          0,
          _mapImage!.width.toDouble(),
          _mapImage!.height.toDouble(),
        ),
        const ui.Rect.fromLTWH(0, 0, arenaWidth, arenaHeight),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
    } else {
      final lightStone = ui.Paint()..color = const ui.Color(0xFF222538);
      final darkStone = ui.Paint()..color = const ui.Color(0xFF191B2A);

      for (int r = 0; r < mapHeightTiles; r++) {
        for (int c = 0; c < mapWidthTiles; c++) {
          final paint = (r + c) % 2 == 0 ? lightStone : darkStone;
          canvas.drawRect(
            ui.Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize),
            paint,
          );
        }
      }
    }

    // 2. Đường kẻ phân làn chiến trường trung tâm
    final dividerPaint = ui.Paint()
      ..color = isIceTheme
          ? const ui.Color(0x4400E5FF)
          : const ui.Color(0x33FFD700)
      ..strokeWidth = 2
      ..style = ui.PaintingStyle.stroke;
    canvas.drawLine(
      const ui.Offset(480, 40),
      const ui.Offset(480, 600),
      dividerPaint,
    );

    // 3. Vòng tròn giác đấu trung tâm
    final centerOffset = const ui.Offset(480, 320);
    final ringBgColor = isIceTheme
        ? const ui.Color(0x2200E5FF)
        : const ui.Color(0x22FFD54F);
    canvas.drawCircle(centerOffset, 80, ui.Paint()..color = ringBgColor);

    final ringBorderColor = isIceTheme
        ? const ui.Color(0xFF00E5FF)
        : const ui.Color(0xFFFFD54F);
    canvas.drawCircle(
      centerOffset,
      80,
      ui.Paint()
        ..color = ringBorderColor
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final ringInnerColor = isIceTheme
        ? const ui.Color(0xFF80DEEA)
        : const ui.Color(0xFFFF8F00);
    canvas.drawCircle(
      centerOffset,
      74,
      ui.Paint()
        ..color = ringInnerColor
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Biểu tượng mặt trời/hoa tuyết ở tâm
    final centerEmblemColor = isIceTheme
        ? const ui.Color(0x5500FFFF)
        : const ui.Color(0x55FFC107);
    canvas.drawCircle(centerOffset, 24, ui.Paint()..color = centerEmblemColor);

    // 4. Vùng xuất phát Đội Xanh (Bên trái)
    final padCount = gameMode.teamSize;
    for (int i = 0; i < padCount && i < blueTeamPads.length; i++) {
      final padCenter = blueTeamPads[i];
      final radius = i == 0 ? 34.0 : 26.0;
      canvas.drawCircle(
        padCenter,
        radius,
        ui.Paint()..color = const ui.Color(0x3300E676),
      );
      canvas.drawCircle(
        padCenter,
        radius,
        ui.Paint()
          ..color = const ui.Color(0xFF00E676)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.0 : 1.3,
      );
    }

    // 5. Vùng xuất phát Đội Đỏ (Bên phải)
    for (int i = 0; i < padCount && i < redTeamPads.length; i++) {
      final padCenter = redTeamPads[i];
      final radius = i == 0 ? 34.0 : 26.0;
      canvas.drawCircle(
        padCenter,
        radius,
        ui.Paint()..color = const ui.Color(0x33FF1744),
      );
      canvas.drawCircle(
        padCenter,
        radius,
        ui.Paint()
          ..color = const ui.Color(0xFFFF1744)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.0 : 1.3,
      );
    }

    // 6. Cổ tự bát giác tại tâm Đấu Trường
    final octPath = ui.Path();
    for (int i = 0; i < 8; i++) {
      final angle = i * pi / 4;
      final ox = centerOffset.dx + cos(angle) * 52;
      final oy = centerOffset.dy + sin(angle) * 52;
      if (i == 0) {
        octPath.moveTo(ox, oy);
      } else {
        octPath.lineTo(ox, oy);
      }
    }
    octPath.close();
    canvas.drawPath(
      octPath,
      ui.Paint()
        ..color = isIceTheme
            ? const ui.Color(0x6600E5FF)
            : const ui.Color(0x66FFD700)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
