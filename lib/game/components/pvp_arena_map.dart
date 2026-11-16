import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import '../../core/constants.dart';
import '../../models/pvp_match.dart';
import 'dungeon_map.dart';

/// Bản đồ đấu trường Thần Điện Hoàng Kim đối xứng 960x640 dành cho PvP 1v1 / 2v2 / 4v4:
/// - 30 cột x 20 hàng gạch (32px mỗi ô) = 960x640px.
/// - 4 cột trụ đá cổ tự đối xứng tại (280, 200), (280, 440), (680, 200), (680, 440).
/// - Vòng ma trận giác đấu trung tâm mạ vàng tại (480, 320).
/// - Bệ xuất phát Đội Xanh (Trái) & Đội Đỏ (Phải) hỗ trợ tới 4 đấu sĩ mỗi phe.
class PvpArenaMapComponent extends Component {
  static const int mapWidthTiles = 30;
  static const int mapHeightTiles = 20;
  static const double arenaWidth = 960.0;
  static const double arenaHeight = 640.0;
  final double tileSize = GameConstants.tileSize;
  final PvpGameMode gameMode;

  static final List<Offset> blueTeamPads = [
    const Offset(200, 320),
    const Offset(170, 205),
    const Offset(170, 435),
    const Offset(130, 320),
  ];

  static final List<Offset> redTeamPads = [
    const Offset(760, 320),
    const Offset(790, 205),
    const Offset(790, 435),
    const Offset(830, 320),
  ];

  PvpArenaMapComponent({this.gameMode = PvpGameMode.solo1v1});

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1. Sinh tường bao quanh trên và dưới
    for (int col = 0; col < mapWidthTiles; col++) {
      add(WallBlock(
        position: Vector2(col * tileSize, 0),
        size: Vector2(tileSize, tileSize),
      ));
      add(WallBlock(
        position: Vector2(col * tileSize, (mapHeightTiles - 1) * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
    }

    // 2. Sinh tường bao quanh trái và phải
    for (int row = 1; row < mapHeightTiles - 1; row++) {
      add(WallBlock(
        position: Vector2(0, row * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
      add(WallBlock(
        position: Vector2((mapWidthTiles - 1) * tileSize, row * tileSize),
        size: Vector2(tileSize, tileSize),
      ));
    }

    // 3. 4 Cột trụ đá đấu trường đối xứng (kích thước 48x48)
    _addArenaPillar(Vector2(280 - 24, 200 - 24));
    _addArenaPillar(Vector2(280 - 24, 440 - 24));
    _addArenaPillar(Vector2(680 - 24, 200 - 24));
    _addArenaPillar(Vector2(680 - 24, 440 - 24));
  }

  void _addArenaPillar(Vector2 pos) {
    add(WallBlock(
      position: pos,
      size: Vector2(48, 48),
    ));
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Vẽ gạch sàn đấu trường La Mã (Gladiatorial Stone Tiles)
    final lightStone = Paint()..color = const Color(0xFF222538);
    final darkStone = Paint()..color = const Color(0xFF191B2A);

    for (int r = 0; r < mapHeightTiles; r++) {
      for (int c = 0; c < mapWidthTiles; c++) {
        final paint = (r + c) % 2 == 0 ? lightStone : darkStone;
        canvas.drawRect(
          Rect.fromLTWH(c * tileSize, r * tileSize, tileSize, tileSize),
          paint,
        );
      }
    }

    // 2. Đường kẻ phân làn chiến trường trung tâm
    final dividerPaint = Paint()
      ..color = const Color(0x33FFD700)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      const Offset(480, 40),
      const Offset(480, 600),
      dividerPaint,
    );

    // 3. Vòng tròn giác đấu trung tâm (Center Ring - Golden Gladiatorial Ring)
    final centerOffset = const Offset(480, 320);
    final ringBgPaint = Paint()..color = const Color(0x22FFD54F);
    canvas.drawCircle(centerOffset, 80, ringBgPaint);

    final ringBorderGold = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(centerOffset, 80, ringBorderGold);

    final ringInnerGlow = Paint()
      ..color = const Color(0xFFFF8F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(centerOffset, 74, ringInnerGlow);

    // Biểu tượng mặt trời chiến binh ở tâm
    final sunEmblem = Paint()..color = const Color(0x55FFC107);
    canvas.drawCircle(centerOffset, 24, sunEmblem);

    // 4. Vùng xuất phát Đội Xanh (Bên trái - Blue/Emerald Team Spawn Pads)
    final padCount = gameMode.teamSize;
    for (int i = 0; i < padCount && i < blueTeamPads.length; i++) {
      final padCenter = blueTeamPads[i];
      final radius = i == 0 ? 34.0 : 26.0;
      canvas.drawCircle(
        padCenter,
        radius,
        Paint()..color = const Color(0x3300E676),
      );
      canvas.drawCircle(
        padCenter,
        radius,
        Paint()
          ..color = const Color(0xFF00E676)
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.0 : 1.3,
      );
    }

    // 5. Vùng xuất phát Đội Đỏ (Bên phải - Red/Crimson Team Spawn Pads)
    for (int i = 0; i < padCount && i < redTeamPads.length; i++) {
      final padCenter = redTeamPads[i];
      final radius = i == 0 ? 34.0 : 26.0;
      canvas.drawCircle(
        padCenter,
        radius,
        Paint()..color = const Color(0x33FF1744),
      );
      canvas.drawCircle(
        padCenter,
        radius,
        Paint()
          ..color = const Color(0xFFFF1744)
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2.0 : 1.3,
      );
    }

    // 6. Cổ tự bát giác tại tâm Đấu Trường Hoàng Kim
    final octPath = Path();
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
      Paint()
        ..color = const Color(0x66FFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
