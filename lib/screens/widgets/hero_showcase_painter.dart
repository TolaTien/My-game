import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../registry/sprite_image_cache.dart';
import 'lobby_companion.dart';

class HeroShowcaseWidget extends StatefulWidget {
  final String heroId;
  final Color themeColor;
  final double width;
  final double height;
  final String? companionId;

  const HeroShowcaseWidget({
    super.key,
    required this.heroId,
    required this.themeColor,
    this.width = 260,
    this.height = 270,
    this.companionId,
  });

  @override
  State<HeroShowcaseWidget> createState() => _HeroShowcaseWidgetState();
}

class _HeroShowcaseWidgetState extends State<HeroShowcaseWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _HeroCanvasPainter(
                      heroId: widget.heroId,
                      themeColor: widget.themeColor,
                      time: _animController.value * 2 * pi,
                      animProgress: _animController.value,
                    ),
                  ),
                ),
              ),
              if (widget.companionId != null)
                Positioned(
                  right: -widget.width * .18,
                  bottom: widget.height * (widget.companionId == 'luna_fox' ? .02 : .21),
                  width: widget.width * .30,
                  height: widget.height * .35,
                  child: LobbyCompanion(
                    key: ValueKey(widget.companionId),
                    companionId: widget.companionId!,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroCanvasPainter extends CustomPainter {
  static ui.MaskFilter? _webSafeBlur(double sigma) =>
      kIsWeb ? null : ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);

  final String heroId;
  final Color themeColor;
  final double time;
  final double animProgress;

  _HeroCanvasPainter({
    required this.heroId,
    required this.themeColor,
    required this.time,
    required this.animProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. CỘT SÁNG THẦN THÁNH RỌI XUỐNG BỤC (GOD-RAY SPOTLIGHT)
    final spotlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          themeColor.withValues(alpha: 0.18),
          themeColor.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(cx - 70, 0, 140, size.height));

    final spotPath = Path()
      ..moveTo(cx - 30, 0)
      ..lineTo(cx + 30, 0)
      ..lineTo(cx + 80, size.height - 25)
      ..lineTo(cx - 80, size.height - 25)
      ..close();
    canvas.drawPath(spotPath, spotlightPaint);

    // 2. BỆ ĐÁ MA THUẬT TRIỆU HỒI 3D (3D SUMMONING DAIS & RUNES)
    final daisCenter = Offset(cx, size.height - 30);
    _drawSummoningDais(canvas, daisCenter);

    // 3. CÁC HẠT BỤI PHÉP THUẬT & ĐỐM LỬA BAY LÊN (RISING PARTICLES)
    _drawRisingParticles(canvas, size, cx);

    // 4. VẼ NHÂN VẬT TƯƠNG ỨNG VỚI HERO ID
    final breathOffset = sin(time * 2.2) * 4.0;
    final heroCenterY = cy + 6 + breathOffset;

    // 4.1 SHADOW (shadow_01 / shadow): Chạy đầy đủ 16 frames IDLE trong sảnh
    if (heroId == 'shadow_01' || heroId == 'shadow') {
      final frameIndex = (animProgress * 16).floor().clamp(0, 15);
      final shadowImg = SpriteImageCache.instance
          .getHeroSequenceFrame('shadow_01', 'idle', frameIndex);
      if (shadowImg != null) {
        _drawShadowIdleAnimation(canvas, shadowImg, cx, daisCenter.dy, size);
        return;
      }
    }

    // 4.2 NOVA (nova_blade / nova): Chạy animation IDLE trong sảnh (5 frames nhìn thẳng)
    if (heroId == 'nova_blade' || heroId == 'nova') {
      final novaSheet = SpriteImageCache.instance.getHeroIdleImage(heroId) ??
          SpriteImageCache.instance.getHeroIdleImage('nova_blade');
      if (novaSheet != null) {
        _drawNovaIdleAnimation(canvas, novaSheet, cx, daisCenter.dy, size, animProgress);
        return;
      }
    }

    // 4.4 EMBER (ember_02 / ember): Chạy animation IDLE trong sảnh (5 frames nhìn thẳng)
    if (heroId == 'ember_02' || heroId == 'ember') {
      final emberSheet = SpriteImageCache.instance.getHeroIdleImage(heroId) ??
          SpriteImageCache.instance.getHeroIdleImage('ember_02') ??
          SpriteImageCache.instance.getHeroIdleImage('ember');
      if (emberSheet != null && emberSheet.width >= 1000) {
        _drawEmberIdleAnimation(canvas, emberSheet, cx, daisCenter.dy, size, animProgress);
        return;
      }
    }

    // 4.5 CÁC TƯỚNG DÙNG SPRITE STRIP 4-FRAME NGANG (George, Hayate/Ninja, ...)
    if (SpriteImageCache.isStripAnimatedHero(heroId)) {
      final strip = SpriteImageCache.instance.getHeroIdleImage(heroId);
      if (strip != null && strip.width >= 512) {
        final auraPaint = Paint()
          ..color = themeColor.withValues(alpha: 0.30 + 0.12 * sin(time * 3))
          ..maskFilter = _webSafeBlur(24);
        canvas.drawCircle(Offset(cx, daisCenter.dy - 78), 68, auraPaint);

        final frameCount = max(1, (strip.width / strip.height).round());
        final col = (animProgress * frameCount).floor() % frameCount;
        final cellW = strip.width / frameCount;
        final cellH = strip.height.toDouble();
        final srcRect = Rect.fromLTWH(col * cellW, 0, cellW, cellH);

        final scale = (size.height / 270.0).clamp(0.65, 1.05);
        final dstSize = 196.0 * scale;
        final dstRect = Rect.fromLTWH(
          cx - dstSize / 2,
          (daisCenter.dy - 4.0) - (236.0 / 256.0 * dstSize),
          dstSize,
          dstSize,
        );
        canvas.drawImageRect(
          strip,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.none,
        );
        return;
      }
    }

    // 4 tướng hệ thống cũ (george, ranger, tanker, ninja) luôn dùng hoạt ảnh đa lớp thay vì 1 avatar tĩnh trong Shop
    if (!SpriteImageCache.isProceduralHero(heroId)) {
      final spriteImg = SpriteImageCache.instance.getHeroImage(heroId);
      if (spriteImg != null) {
        _drawAnimatedAssetHero(canvas, spriteImg, cx, heroCenterY);
        return;
      }
    }

    final proceduralScale = (size.height / 270.0).clamp(0.38, 1.0);
    final proceduralCenterY =
        proceduralScale < 0.999 ? (daisCenter.dy - 99.0 + breathOffset) : heroCenterY;
    if (proceduralScale < 0.999) {
      canvas.save();
      canvas.translate(cx, daisCenter.dy);
      canvas.scale(proceduralScale, proceduralScale);
      canvas.translate(-cx, -daisCenter.dy);
    }

    switch (heroId) {
      case 'nova_blade':
        _drawHeroNovaBlade(canvas, cx, proceduralCenterY);
        break;
      case 'valeria':
        _drawHeroValeriaElementalist(canvas, cx, proceduralCenterY);
        break;
      case 'ember_02':
        _drawHeroEmberWitch(canvas, cx, proceduralCenterY);
        break;
      case 'ranger':
        _drawHeroRanger(canvas, cx, proceduralCenterY);
        break;
      case 'garrick':
        _drawHeroGarrickGuardian(canvas, cx, proceduralCenterY);
        break;
      case 'tanker':
        _drawHeroTanker(canvas, cx, proceduralCenterY);
        break;
      case 'shadow_01':
        _drawHeroShadow01(canvas, cx, proceduralCenterY);
        break;
      case 'ninja':
        _drawHeroNinja(canvas, cx, proceduralCenterY);
        break;
      case 'george':
      default:
        _drawHeroGeorge(canvas, cx, proceduralCenterY);
        break;
    }

    if (proceduralScale < 0.999) {
      canvas.restore();
    }
  }

  /// Hiển thị Shadow lặp 16 frame IDLE từ assets/images/heroes/shadow/idle/
  void _drawShadowIdleAnimation(
    Canvas canvas,
    ui.Image img,
    double cx,
    double daisY,
    Size size,
  ) {
    // Hào quang tím hư không phía sau lưng Shadow
    final auraPaint = Paint()
      ..color = const Color(0xFF9C27B0)
          .withValues(alpha: 0.32 + 0.12 * sin(time * 3))
      ..maskFilter = _webSafeBlur(24);
    canvas.drawCircle(Offset(cx, daisY - 78), 68, auraPaint);

    final scale = (size.height / 270.0).clamp(0.65, 1.05);
    final dstSize = 196.0 * scale;

    final feetY = 256.0 * (dstSize / img.height);
    final centerX = (img.width / 2.0) * (dstSize / img.width);

    final dstLeft = cx - centerX;
    final dstTop = (daisY - 4.0) - feetY;

    final srcRect =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstSize, dstSize);

    canvas.drawImageRect(
      img,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// Hiển thị Nova Blade chạy 5 frames IDLE mặt trước (Row 0) từ assets/images/heroes/nova/nova.png
  void _drawNovaIdleAnimation(
    Canvas canvas,
    ui.Image sheet,
    double cx,
    double daisY,
    Size size,
    double animProgress,
  ) {
    // Phòng thủ an toàn: Nếu ảnh chưa phải spritesheet 5x5 (ví dụ ảnh chân dung < 1000px), hiển thị trọn vẹn ảnh
    if (sheet.width < 1000 || sheet.height < 1000) {
      _drawAnimatedAssetHero(canvas, sheet, cx, daisY - 90);
      return;
    }

    const double cellW = 256.0;
    const double cellH = 256.0;

    // Chạy tuần tự đầy đủ 5 frames IDLE mặt trước (Hàng 0: 5 ô cột 0 -> 4)
    final int col = (animProgress * 5).floor() % 5;
    const int row = 0;

    final srcRect = Rect.fromLTWH(
      col * cellW,
      row * cellH,
      cellW,
      cellH,
    );

    // Hào quang năng lượng phía sau lưng Nova
    final auraPaint = Paint()
      ..color = const Color(0xFF00E5FF)
          .withValues(alpha: 0.30 + 0.12 * sin(time * 3))
      ..maskFilter = _webSafeBlur(24);
    canvas.drawCircle(Offset(cx, daisY - 78), 68, auraPaint);

    // Tỉ lệ scale sao cho chân Nova đặt chuẩn xác trên bệ đá sảnh chờ
    final scale = (size.height / 270.0).clamp(0.65, 1.05);
    final dstSize = 196.0 * scale;

    // Trong cell 256x256 của nova.png, chân nằm ở y ≈ 229, tâm x ≈ 117.5
    final feetY = 229.0 * (dstSize / cellW);
    final centerX = 117.5 * (dstSize / cellW);

    final dstLeft = cx - centerX;
    final dstTop = (daisY - 4.0) - feetY;

    final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstSize, dstSize);

    canvas.drawImageRect(
      sheet,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// Hiển thị Ember (EMBER-02) chạy 5 frames IDLE mặt trước (Row 0) với hào quang hỏa diễm
  void _drawEmberIdleAnimation(
    Canvas canvas,
    ui.Image sheet,
    double cx,
    double daisY,
    Size size,
    double animProgress,
  ) {
    if (sheet.width < 1000 || sheet.height < 1000) {
      _drawAnimatedAssetHero(canvas, sheet, cx, daisY - 90);
      return;
    }

    const double cellW = 256.0;
    const double cellH = 256.0;

    // Chạy tuần tự 5 frames IDLE mặt trước (Hàng 0: 5 ô cột 0 -> 4)
    final int col = (animProgress * 5).floor() % 5;
    const int row = 0;

    final srcRect = Rect.fromLTWH(
      col * cellW,
      row * cellH,
      cellW,
      cellH,
    );

    // Hào quang hỏa diễm rực lửa phía sau lưng Ember
    final auraPaint = Paint()
      ..color = const Color(0xFFFF5722)
          .withValues(alpha: 0.35 + 0.15 * sin(time * 3))
      ..maskFilter = _webSafeBlur(24);
    canvas.drawCircle(Offset(cx, daisY - 78), 68, auraPaint);

    final scale = (size.height / 270.0).clamp(0.65, 1.05);
    final dstSize = 196.0 * scale;

    // Trong cell 256x256 của Ember-idle.png, chân nằm ở y ≈ 236, tâm x ≈ 128
    final feetY = 236.0 * (dstSize / cellW);
    final centerX = 128.0 * (dstSize / cellW);

    final dstLeft = cx - centerX;
    final dstTop = (daisY - 4.0) - feetY;

    final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstSize, dstSize);

    canvas.drawImageRect(
      sheet,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  /// Hiển thị trực tiếp Sprite nhân vật thật từ Asset 1-4 với chuyển động 60 FPS mượt mà
  void _drawAnimatedAssetHero(
    Canvas canvas,
    ui.Image img,
    double cx,
    double cy,
  ) {
    // Hào quang năng lượng phía sau lưng nhân vật
    final auraPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.30 + 0.12 * sin(time * 3))
      ..maskFilter = _webSafeBlur(24);
    canvas.drawCircle(Offset(cx, cy - 8), 72, auraPaint);

    final aspect = img.width / max(1, img.height);
    const targetHeight = 186.0;
    final targetWidth = (targetHeight * aspect).clamp(115.0, 195.0);

    // Chuyển động Squash & Stretch (co giãn nhịp thở) + Sway (nghiêng vũ khí/thân người)
    final scaleX = 1.0 - sin(time * 2.2) * 0.018;
    final scaleY = 1.0 + sin(time * 2.2) * 0.026;
    final swayAngle = sin(time * 1.6) * 0.025;

    canvas.save();
    canvas.translate(cx, cy + 62); // Neo tại điểm đặt chân trên bệ đá
    canvas.rotate(swayAngle);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-cx, -(cy + 62));

    final srcRect = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final dstRect = Rect.fromCenter(
      center: Offset(cx, cy - 10),
      width: targetWidth,
      height: targetHeight,
    );

    canvas.drawImageRect(
      img,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.none,
    );
    canvas.restore();
  }

  /// NOVA BLADE (NOVA-07) — Chiến Binh Cyber Song Kiếm Neon (Asset 1 & 2)
  void _drawHeroNovaBlade(Canvas canvas, double cx, double cy) {
    final capeWave = sin(time * 3.2) * 8.0;
    final armSwing = sin(time * 2.6) * 0.14;
    final legStep = sin(time * 2.2) * 2.0;

    // 1. Áo khoác Cyber dài phía sau (tím than viền Neon Cyan/Magenta)
    final coatPath = Path()
      ..moveTo(cx - 24, cy - 18)
      ..lineTo(cx + 24, cy - 18)
      ..quadraticBezierTo(cx + 38 + capeWave, cy + 28, cx + 30 + capeWave, cy + 68)
      ..lineTo(cx - 30 + capeWave * 0.6, cy + 68)
      ..quadraticBezierTo(cx - 36 + capeWave * 0.4, cy + 26, cx - 24, cy - 18)
      ..close();
    canvas.drawPath(
      coatPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF1E1B4B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(cx - 40, cy - 20, 80, 90)),
    );
    canvas.drawPath(
      coatPath,
      Paint()
        ..color = const Color(0xFFE040FB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // 2. Đùi & Hai chân khớp nối liền với hông (Connected Thighs & Cyber Greaves)
    final legFill = Paint()..color = const Color(0xFF334155);
    final legBorder = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final leftLegRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 21, cy + 20 + legStep, 16, 46),
      const Radius.circular(5),
    );
    final rightLegRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + 5, cy + 20 - legStep, 16, 46),
      const Radius.circular(5),
    );
    canvas.drawRRect(leftLegRect, legFill);
    canvas.drawRRect(leftLegRect, legBorder);
    canvas.drawRRect(rightLegRect, legFill);
    canvas.drawRRect(rightLegRect, legBorder);
    // Giáp gối Neon
    canvas.drawRect(
      Rect.fromLTWH(cx - 21, cy + 38 + legStep, 16, 6),
      Paint()..color = const Color(0xFF00E5FF),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 5, cy + 38 - legStep, 16, 6),
      Paint()..color = const Color(0xFF00E5FF),
    );

    // 3. Thắt lưng & Váy giáp hông (Waist Belt & Tassets nối liền thân và chân)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 24, cy + 14, 48, 14),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF4C1D95),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - 24, cy + 14, 48, 6),
      Paint()..color = const Color(0xFF00E5FF),
    );

    // 4. Thân giáp Cyber Neon (Body + Lõi Lượng Tử)
    final bodyRect = Rect.fromLTWH(cx - 24, cy - 22, 48, 38);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF3730A3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      Offset(cx, cy - 3),
      9,
      Paint()
        ..color = const Color(0xFFE040FB)
        ..maskFilter = _webSafeBlur(6),
    );
    canvas.drawCircle(Offset(cx, cy - 3), 4.5, Paint()..color = Colors.white);

    // 5. Vai, Cánh tay trái/phải & Bàn tay nối liền vào Song Kiếm Năng Lượng
    final armPaint = Paint()..color = const Color(0xFF475569);
    // Vai & Cánh tay trái
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 38, cy - 20, 15, 26),
        const Radius.circular(6),
      ),
      armPaint,
    );
    canvas.drawCircle(
      Offset(cx - 33, cy + 6),
      7,
      Paint()..color = const Color(0xFF00E5FF),
    );
    // Vai & Cánh tay phải
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 23, cy - 20, 15, 26),
        const Radius.circular(6),
      ),
      armPaint,
    );
    canvas.drawCircle(
      Offset(cx + 33, cy + 6),
      7,
      Paint()..color = const Color(0xFF00E5FF),
    );

    _drawThunderSword(canvas, Offset(cx - 35, cy + 6), -0.48 + armSwing, isCyan: true);
    _drawThunderSword(canvas, Offset(cx + 35, cy + 6), 0.48 - armSwing, isCyan: true);

    // 6. Cổ & Khuôn mặt da sáng + Tóc Bạc dựng & Mắt Neon
    canvas.drawRect(
      Rect.fromLTWH(cx - 8, cy - 30, 16, 12),
      Paint()..color = const Color(0xFFFBBF24),
    );
    final headRect = Rect.fromCenter(center: Offset(cx, cy - 42), width: 38, height: 34);
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, const Radius.circular(9)),
      Paint()..color = const Color(0xFFFDE68A),
    );
    final hairSway = sin(time * 3.0) * 3.0;
    final hairPath = Path()
      ..moveTo(cx - 22, cy - 44)
      ..lineTo(cx - 32 + hairSway, cy - 68)
      ..lineTo(cx - 12, cy - 58)
      ..lineTo(cx + hairSway, cy - 80)
      ..lineTo(cx + 12, cy - 58)
      ..lineTo(cx + 32 + hairSway, cy - 68)
      ..lineTo(cx + 22, cy - 44)
      ..close();
    canvas.drawPath(hairPath, Paint()..color = const Color(0xFFF1F5F9));
    final eyePaint = Paint()..color = const Color(0xFF0284C7);
    canvas.drawRect(Rect.fromLTWH(cx - 11, cy - 40, 7, 5), eyePaint);
    canvas.drawRect(Rect.fromLTWH(cx + 4, cy - 40, 7, 5), eyePaint);
  }

  /// SHADOW-01 — Sát Thủ Hư Không (Asset 2: Áo trùm đầu tím + Tay cầm Song Dao Plasma)
  void _drawHeroShadow01(Canvas canvas, double cx, double cy) {
    final cloakWave = sin(time * 3.5) * 9.0;
    final armSwing = cos(time * 3.0) * 0.18;
    final legStep = sin(time * 2.4) * 2.2;

    // 1. Áo choàng bóng đêm rách tà
    final cloakPath = Path()
      ..moveTo(cx - 22, cy - 22)
      ..lineTo(cx + 22, cy - 22)
      ..lineTo(cx + 36 + cloakWave, cy + 64)
      ..lineTo(cx + 10 + cloakWave * 0.7, cy + 54)
      ..lineTo(cx - 6 + cloakWave * 0.5, cy + 66)
      ..lineTo(cx - 32 + cloakWave * 0.3, cy + 56)
      ..close();
    canvas.drawPath(cloakPath, Paint()..color = const Color(0xFF3B0764));
    canvas.drawPath(
      cloakPath,
      Paint()
        ..color = const Color(0xFFE040FB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 2. Hai chân sát thủ nối liền hông có viền tím sáng
    final legFill = Paint()..color = const Color(0xFF4C1D95);
    final legBorder = Paint()
      ..color = const Color(0xFFE040FB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final lRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 19, cy + 20 + legStep, 14, 44),
      const Radius.circular(4),
    );
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + 5, cy + 20 - legStep, 14, 44),
      const Radius.circular(4),
    );
    canvas.drawRRect(lRect, legFill);
    canvas.drawRRect(lRect, legBorder);
    canvas.drawRRect(rRect, legFill);
    canvas.drawRRect(rRect, legBorder);

    // 3. Thắt lưng & Thân giáp Hư Không
    final torso = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 22, cy - 20, 44, 44),
      const Radius.circular(8),
    );
    canvas.drawRRect(torso, Paint()..color = const Color(0xFF581C87));
    canvas.drawRRect(torso, legBorder);
    canvas.drawRect(
      Rect.fromLTWH(cx - 22, cy + 14, 44, 6),
      Paint()..color = const Color(0xFFE040FB),
    );

    // 4. Vai, Cánh tay trái & phải + Bàn tay cầm Song Dao Plasma Tím
    for (final side in [-1.0, 1.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + side * 28, cy - 6), width: 13, height: 24),
          const Radius.circular(5),
        ),
        Paint()..color = const Color(0xFF6B21A8),
      );
      canvas.drawCircle(
        Offset(cx + side * 30, cy + 6),
        6.5,
        Paint()..color = const Color(0xFFE040FB),
      );
      canvas.save();
      canvas.translate(cx + side * 30, cy + 6);
      canvas.rotate(side * 0.55 + side * armSwing);
      final daggerPath = Path()
        ..moveTo(-5, 0)
        ..lineTo(0, -46)
        ..lineTo(5, 0)
        ..close();
      canvas.drawPath(
        daggerPath,
        Paint()
          ..color = const Color(0xFFE040FB)
          ..maskFilter = _webSafeBlur(5),
      );
      canvas.drawPath(daggerPath, Paint()..color = const Color(0xFFF3E5F5));
      canvas.restore();
    }

    // 5. Cổ, Mũ trùm đầu Sát Thủ (Hood) & Mắt tím phát sáng
    canvas.drawRect(
      Rect.fromLTWH(cx - 8, cy - 28, 16, 10),
      Paint()..color = const Color(0xFF4C1D95),
    );
    final hoodPath = Path()
      ..moveTo(cx, cy - 72)
      ..quadraticBezierTo(cx + 28, cy - 58, cx + 24, cy - 20)
      ..lineTo(cx - 24, cy - 20)
      ..quadraticBezierTo(cx - 28, cy - 58, cx, cy - 72)
      ..close();
    canvas.drawPath(hoodPath, Paint()..color = const Color(0xFF6B21A8));
    canvas.drawPath(hoodPath, legBorder);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 42), width: 28, height: 24),
      Paint()..color = const Color(0xFF1E1B4B),
    );
    final eyeGlow = Paint()
      ..color = const Color(0xFFE040FB)
      ..maskFilter = _webSafeBlur(4);
    canvas.drawOval(Rect.fromLTWH(cx - 10, cy - 44, 7, 4), eyeGlow);
    canvas.drawOval(Rect.fromLTWH(cx + 3, cy - 44, 7, 4), eyeGlow);
  }

  /// VALERIA — Pháp Sư Băng Hỏa (Asset 3: Tóc xanh băng, Áo choàng Băng-Hỏa, Tay cầm Trượng & Cầu Nguyên Tố)
  void _drawHeroValeriaElementalist(Canvas canvas, double cx, double cy) {
    final hairWave = sin(time * 2.8) * 6.0;
    final staffBob = cos(time * 2.6) * 5.0;
    final legStep = sin(time * 2.2) * 1.8;

    // 1. Tóc dài xanh băng bay phía sau
    final hairBack = Path()
      ..moveTo(cx - 22, cy - 44)
      ..quadraticBezierTo(cx - 36 + hairWave, cy - 5, cx - 28 + hairWave, cy + 36)
      ..lineTo(cx + 28 + hairWave, cy + 36)
      ..quadraticBezierTo(cx + 36 + hairWave, cy - 5, cx + 22, cy - 44)
      ..close();
    canvas.drawPath(hairBack, Paint()..color = const Color(0xFF38BDF8));

    // 2. Chân & Giày pháp sư nối liền tà áo
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 16, cy + 28 + legStep, 12, 36),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF0284C7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 4, cy + 28 - legStep, 12, 36),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFDC2626),
    );

    // 3. Áo choàng Nguyên Tố Băng - Hỏa (Nửa trái Xanh Băng, Nửa phải Đỏ Lửa)
    final leftRobe = Path()
      ..moveTo(cx, cy - 22)
      ..lineTo(cx - 24, cy - 18)
      ..lineTo(cx - 28, cy + 52)
      ..lineTo(cx, cy + 52)
      ..close();
    final rightRobe = Path()
      ..moveTo(cx, cy - 22)
      ..lineTo(cx + 24, cy - 18)
      ..lineTo(cx + 28, cy + 52)
      ..lineTo(cx, cy + 52)
      ..close();
    canvas.drawPath(leftRobe, Paint()..color = const Color(0xFF0284C7));
    canvas.drawPath(rightRobe, Paint()..color = const Color(0xFFDC2626));
    canvas.drawLine(
      Offset(cx, cy - 22),
      Offset(cx, cy + 52),
      Paint()
        ..color = const Color(0xFFFFD700)
        ..strokeWidth = 2.8,
    );
    // Đai lưng Hoàng Kim
    canvas.drawRect(
      Rect.fromLTWH(cx - 24, cy + 10, 48, 6),
      Paint()..color = const Color(0xFFFFD700),
    );

    // 4. Cánh tay trái & Cánh tay phải nối liền từ vai ra Bàn tay cầm Trượng
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 36, cy - 16, 14, 24),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF0284C7),
    );
    canvas.drawCircle(
      Offset(cx - 30, cy + 8),
      6,
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 22, cy - 16, 14, 24),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFFDC2626),
    );
    canvas.drawCircle(
      Offset(cx + 34, cy + 6 + staffBob),
      6.5,
      Paint()..color = const Color(0xFFFDE68A),
    );

    // Quyền Trượng Băng Tinh (Crystal Ice Staff)
    final staffX = cx + 36;
    final staffY = cy + staffBob;
    canvas.drawLine(
      Offset(staffX, staffY - 58),
      Offset(staffX, staffY + 48),
      Paint()
        ..color = const Color(0xFF93C5FD)
        ..strokeWidth = 4.5,
    );
    final crystalPath = Path()
      ..moveTo(staffX, staffY - 76)
      ..lineTo(staffX + 12, staffY - 60)
      ..lineTo(staffX, staffY - 46)
      ..lineTo(staffX - 12, staffY - 60)
      ..close();
    canvas.drawPath(
      crystalPath,
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..maskFilter = _webSafeBlur(6),
    );
    canvas.drawPath(crystalPath, Paint()..color = const Color(0xFFE0F2FE));

    // 5. Quả cầu Băng & Hỏa xoay quanh tay trái
    final iceOrb = Offset(cx - 38 + cos(time * 3) * 8, cy - 6 + sin(time * 3) * 8);
    final fireOrb = Offset(cx - 28 - cos(time * 3) * 8, cy + 8 - sin(time * 3) * 8);
    canvas.drawCircle(iceOrb, 8, Paint()..color = const Color(0xFF00E5FF));
    canvas.drawCircle(fireOrb, 8, Paint()..color = const Color(0xFFFF5252));

    // 6. Cổ, Đầu & Tóc Xanh Băng
    canvas.drawRect(
      Rect.fromLTWH(cx - 7, cy - 30, 14, 10),
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 42), width: 36, height: 32),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFFFDE68A),
    );
    final crownHair = Path()
      ..moveTo(cx - 20, cy - 42)
      ..quadraticBezierTo(cx, cy - 68, cx + 20, cy - 42)
      ..lineTo(cx + 18, cy - 54)
      ..lineTo(cx - 18, cy - 54)
      ..close();
    canvas.drawPath(crownHair, Paint()..color = const Color(0xFF7DD3FC));
    canvas.drawRect(
      Rect.fromLTWH(cx - 10, cy - 42, 6, 5),
      Paint()..color = const Color(0xFF0284C7),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, cy - 42, 6, 5),
      Paint()..color = const Color(0xFFDC2626),
    );
  }

  /// EMBER-02 — Phù Thủy Hỏa Cầu (Asset 2: Mũ phù thủy chóp nhọn + Tóc vàng + Tay cầm Trượng & Cầu lửa)
  void _drawHeroEmberWitch(Canvas canvas, double cx, double cy) {
    final floatBob = sin(time * 3.0) * 5.0;
    final legStep = cos(time * 2.2) * 2.0;

    // 1. Hai chân nối liền dưới váy
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 16, cy + 32 + legStep, 12, 32),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF78350F),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 4, cy + 32 - legStep, 12, 32),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF78350F),
    );

    // 2. Áo choàng Phù Thủy Đỏ Tím viền Vàng Hoàng Kim
    final robePath = Path()
      ..moveTo(cx - 22, cy - 20)
      ..lineTo(cx + 22, cy - 20)
      ..lineTo(cx + 30, cy + 52)
      ..lineTo(cx - 30, cy + 52)
      ..close();
    canvas.drawPath(robePath, Paint()..color = const Color(0xFF7F1D1D));
    canvas.drawPath(
      robePath,
      Paint()
        ..color = const Color(0xFFFFB300)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - 22, cy + 12, 44, 6),
      Paint()..color = const Color(0xFFFFB300),
    );

    // 3. Cánh tay trái & Cánh tay phải nối liền thân
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 35, cy - 16, 13, 24),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF991B1B),
    );
    canvas.drawCircle(
      Offset(cx - 29, cy + 8),
      6,
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 22, cy - 16, 13, 24),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF991B1B),
    );
    canvas.drawCircle(
      Offset(cx + 30, cy + 6),
      6,
      Paint()..color = const Color(0xFFFDE68A),
    );

    // 4. Cổ, Đầu & Tóc vàng
    canvas.drawRect(
      Rect.fromLTWH(cx - 7, cy - 28, 14, 10),
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 40), width: 34, height: 30),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - 20, cy - 44, 7, 26),
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 13, cy - 44, 7, 26),
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - 10, cy - 40, 6, 4),
      Paint()..color = const Color(0xFFFF6D00),
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, cy - 40, 6, 4),
      Paint()..color = const Color(0xFFFF6D00),
    );

    // 5. Mũ Phù Thủy chóp nhọn (Pointed Witch Hat)
    final hatBrim = Rect.fromCenter(center: Offset(cx, cy - 52), width: 64, height: 12);
    canvas.drawOval(hatBrim, Paint()..color = const Color(0xFF31102F));
    final hatCone = Path()
      ..moveTo(cx - 20, cy - 52)
      ..lineTo(cx + 6, cy - 88)
      ..lineTo(cx + 20, cy - 52)
      ..close();
    canvas.drawPath(hatCone, Paint()..color = const Color(0xFF31102F));
    canvas.drawRect(
      Rect.fromLTWH(cx - 16, cy - 56, 32, 5),
      Paint()..color = const Color(0xFFFFB300),
    );

    // 6. Tay phải nâng Hỏa Cầu rực cháy
    final firePos = Offset(cx + 38, cy - 8 + floatBob);
    canvas.drawCircle(
      firePos,
      15,
      Paint()
        ..color = const Color(0xFFFF3D00)
        ..maskFilter = _webSafeBlur(8),
    );
    canvas.drawCircle(firePos, 9, Paint()..color = const Color(0xFFFFAB00));
    canvas.drawCircle(firePos, 4, Paint()..color = Colors.white);
  }

  /// GARRICK — Chiến Binh Cổ Đại (Asset 3: Tóc & Râu Đỏ, Giáp Đá Cổ Đại, Tay vung Đại Đao Khổng Lồ)
  void _drawHeroGarrickGuardian(Canvas canvas, double cx, double cy) {
    final swordSwing = sin(time * 2.2) * 0.10;
    final legStep = sin(time * 2.0) * 2.0;

    // 1. Hai chân giáp đá nặng có viền vàng sáng
    final stoneMid = Paint()..color = const Color(0xFF57534E);
    final goldTrim = Paint()..color = const Color(0xFFFFB300);
    final lLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - 22, cy + 24 + legStep, 17, 42),
      const Radius.circular(5),
    );
    final rLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx + 5, cy + 24 - legStep, 17, 42),
      const Radius.circular(5),
    );
    canvas.drawRRect(lLeg, stoneMid);
    canvas.drawRRect(rLeg, stoneMid);
    canvas.drawRect(Rect.fromLTWH(cx - 22, cy + 38 + legStep, 17, 5), goldTrim);
    canvas.drawRect(Rect.fromLTWH(cx + 5, cy + 38 - legStep, 17, 5), goldTrim);

    // 2. Thân giáp Đá Cổ Đại & Khố chiến binh đỏ thẫm
    final torsoRect = Rect.fromLTWH(cx - 28, cy - 22, 56, 50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFF78716C),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, const Radius.circular(10)),
      Paint()
        ..color = const Color(0xFFFFB300)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx - 16, cy + 16, 32, 24),
      Paint()..color = const Color(0xFFB91C1C),
    );

    // 3. Vai đá, Cánh tay cơ bắp & Bàn tay nắm chặt Đại Đao
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 44, cy - 22, 18, 30),
        const Radius.circular(7),
      ),
      stoneMid,
    );
    canvas.drawCircle(
      Offset(cx - 38, cy + 8),
      8,
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 26, cy - 22, 18, 30),
        const Radius.circular(7),
      ),
      stoneMid,
    );
    canvas.drawCircle(
      Offset(cx + 35, cy + 8),
      8,
      Paint()..color = const Color(0xFFFBBF24),
    );

    // 4. Cổ, Đầu, Bờm Tóc Đỏ & Bộ Râu Đỏ Chiến Binh
    canvas.drawRect(
      Rect.fromLTWH(cx - 10, cy - 30, 20, 12),
      Paint()..color = const Color(0xFFF59E0B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 42), width: 38, height: 34),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFFFDE68A),
    );
    final redHair = Paint()..color = const Color(0xFFDC2626);
    final hairPath = Path()
      ..moveTo(cx - 22, cy - 46)
      ..lineTo(cx - 26, cy - 68)
      ..lineTo(cx, cy - 74)
      ..lineTo(cx + 26, cy - 68)
      ..lineTo(cx + 22, cy - 46)
      ..close();
    canvas.drawPath(hairPath, redHair);
    final beardPath = Path()
      ..moveTo(cx - 18, cy - 34)
      ..lineTo(cx + 18, cy - 34)
      ..lineTo(cx + 13, cy - 8)
      ..lineTo(cx, cy - 2)
      ..lineTo(cx - 13, cy - 8)
      ..close();
    canvas.drawPath(beardPath, redHair);
    canvas.drawRect(
      Rect.fromLTWH(cx - 11, cy - 42, 7, 4),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + 4, cy - 42, 7, 4),
      Paint()..color = Colors.white,
    );

    // 5. Tay phải vung Đại Đao Đá Cổ Đại (Colossal Stone Greatsword)
    canvas.save();
    canvas.translate(cx - 38, cy + 8);
    canvas.rotate(-0.22 + swordSwing);
    canvas.drawRect(const Rect.fromLTWH(-4, -20, 8, 26), goldTrim);
    final greatBlade = Path()
      ..moveTo(-11, 6)
      ..lineTo(11, 6)
      ..lineTo(14, 68)
      ..lineTo(0, 82)
      ..lineTo(-14, 68)
      ..close();
    canvas.drawPath(greatBlade, Paint()..color = const Color(0xFF78716C));
    canvas.drawPath(
      greatBlade,
      Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.restore();
  }

  /// Vẽ bệ triệu hồi đa tầng với vòng cổ ngữ xoay 3D
  void _drawSummoningDais(Canvas canvas, Offset center) {
    // Bóng bệ
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..maskFilter = _webSafeBlur(12);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 8), width: 190, height: 46),
      shadowPaint,
    );

    // Tầng đáy bệ đá (Stone base rim)
    final stoneDark = Paint()..color = const Color(0xFF1E2430);
    final stoneMid = Paint()..color = const Color(0xFF2C3444);
    final goldTrim = Paint()..color = const Color(0xFFFFD54F);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 6), width: 180, height: 44),
      stoneDark,
    );
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 170, height: 40),
      stoneMid,
    );

    // Viền kim loại mạ vàng
    final trimPaint = Paint()
      ..color = goldTrim.color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 168, height: 38),
      trimPaint,
    );

    // Vòng tròn ma thuật phát sáng xoay 3D
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, 0.28); // Phối cảnh dẹt góc nhìn từ trên xuống

    final glowPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.4 + 0.2 * sin(time * 3))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = _webSafeBlur(10);
    canvas.drawCircle(Offset.zero, 75, glowPaint);

    final runeLine = Paint()
      ..color = themeColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(Offset.zero, 74, runeLine);
    canvas.drawCircle(Offset.zero, 54, runeLine);

    // Ký tự cổ ngữ / nan hoa xoay
    canvas.rotate(time * 0.4);
    for (int i = 0; i < 12; i++) {
      final angle = i * pi / 6;
      final p1 = Offset(cos(angle) * 54, sin(angle) * 54);
      final p2 = Offset(cos(angle) * 74, sin(angle) * 74);
      canvas.drawLine(p1, p2, runeLine);
    }

    // Tam giác ma thuật bên trong
    final triPath = Path();
    for (int i = 0; i < 3; i++) {
      final angle = i * 2 * pi / 3 - time * 0.4;
      final pt = Offset(cos(angle) * 44, sin(angle) * 44);
      if (i == 0) {
        triPath.moveTo(pt.dx, pt.dy);
      } else {
        triPath.lineTo(pt.dx, pt.dy);
      }
    }
    triPath.close();
    canvas.drawPath(triPath, runeLine);

    canvas.restore();
  }

  /// Vẽ các hạt bụi phát sáng bay lên
  void _drawRisingParticles(Canvas canvas, Size size, double cx) {
    final rand = Random(88);
    for (int i = 0; i < 16; i++) {
      final seedX = (rand.nextDouble() - 0.5) * 140;
      final speed = 0.35 + rand.nextDouble() * 0.65;
      final progress = (time * speed + i * 0.12) % 1.0;
      final py = size.height - 35 - progress * 170;
      final px = cx + seedX * (1.0 - progress * 0.25);
      final alpha = (sin(progress * pi) * 0.85).clamp(0.0, 1.0);

      final pPaint = Paint()
        ..color = themeColor.withValues(alpha: alpha)
        ..maskFilter = _webSafeBlur(2);
      canvas.drawCircle(Offset(px, py), 2.0 + rand.nextDouble() * 2.2, pPaint);
    }
  }

  // =========================================================================
  // 1. TƯỚNG GEORGE: CHIẾN BINH BÚA HOÀNG GIA (THUNDER WARRIOR)
  // =========================================================================
  void _drawHeroGeorge(Canvas canvas, double cx, double cy) {
    // --- ÁO CHOÀNG HOÀNG GIA BAY PHẤP PHỚI PHÍA SAU (FLOWING ROYAL CAPE) ---
    final capeWave = sin(time * 2.5) * 6;
    final capePath = Path()
      ..moveTo(cx - 24, cy - 14)
      ..lineTo(cx + 24, cy - 14)
      ..quadraticBezierTo(cx + 36 + capeWave, cy + 30, cx + 32 + capeWave, cy + 68)
      ..lineTo(cx - 30 + capeWave * 0.5, cy + 70)
      ..quadraticBezierTo(cx - 36, cy + 30, cx - 24, cy - 14)
      ..close();

    final capeShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF8B0000), Color(0xFF4A0000)],
    ).createShader(Rect.fromLTWH(cx - 40, cy - 20, 80, 95));
    canvas.drawPath(capePath, Paint()..shader = capeShader);

    // Viền vàng áo choàng
    final capeGoldTrim = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(capePath, capeGoldTrim);

    // --- BÓNG DƯỚI BÀN CHÂN ---
    final footShadow = Paint()..color = const Color(0x66000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 74), width: 72, height: 16),
      footShadow,
    );

    // --- ĐÔI CHÂN & BỌC GIÁP ỐNG CHÂN (GREAVES) ---
    final ironDark = Paint()..color = const Color(0xFF263238);
    final ironMid = Paint()..color = const Color(0xFF37474F);
    final goldAccent = Paint()..color = const Color(0xFFFFD54F);

    // Chân trái & phải
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 24, cy + 32, 18, 40), const Radius.circular(5)),
      ironDark,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + 6, cy + 32, 18, 40), const Radius.circular(5)),
      ironMid,
    );
    // Vòng mạ vàng giáp gối
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 24, cy + 34, 18, 8), const Radius.circular(3)),
      goldAccent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + 6, cy + 34, 18, 8), const Radius.circular(3)),
      goldAccent,
    );

    // --- VÁY GIÁP CHIẾN BINH (TASSETS) ---
    final tassetPaint = Paint()..color = const Color(0xFFB71C1C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 25, cy + 20, 50, 18), const Radius.circular(4)),
      tassetPaint,
    );
    // Thắt lưng da & Khóa đầu sư tử vàng
    canvas.drawRect(Rect.fromLTWH(cx - 24, cy + 14, 48, 8), Paint()..color = const Color(0xFF1E272C));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, cy + 12, 20, 12), const Radius.circular(3)),
      goldAccent,
    );

    // --- GIÁP THÂN (PLATE CHESTPLATE WITH GOLD EMBLEM) ---
    final armorShader = LinearGradient(
      colors: const [Color(0xFFD32F2F), Color(0xFF8E0000)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(cx - 26, cy - 24, 52, 42));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 26, cy - 24, 52, 42), const Radius.circular(8)),
      Paint()..shader = armorShader,
    );
    // Viền kim loại ngực
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 26, cy - 24, 52, 42), const Radius.circular(8)),
      Paint()..color = const Color(0xFFFFD54F)..style = PaintingStyle.stroke..strokeWidth = 2,
    );
    // Huy hiệu hoàng gia chữ thập vàng trước ngực
    final crestPath = Path()
      ..moveTo(cx, cy - 16)
      ..lineTo(cx - 12, cy - 4)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx + 12, cy - 4)
      ..close();
    canvas.drawPath(crestPath, Paint()..color = const Color(0xFFFFEB3B));

    // --- GIÁP VAI (HEAVY PAULDRONS) ---
    final pauldronBase = Paint()..color = const Color(0xFF455A64);
    // Vai trái
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 42, cy - 26, 22, 28), const Radius.circular(7)),
      pauldronBase,
    );
    canvas.drawRect(Rect.fromLTWH(cx - 42, cy - 14, 22, 4), goldAccent);
    // Vai phải
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + 20, cy - 26, 22, 28), const Radius.circular(7)),
      pauldronBase,
    );
    canvas.drawRect(Rect.fromLTWH(cx + 20, cy - 14, 22, 4), goldAccent);

    // --- BÚA CHIẾN SẤM SÉT VĨ ĐẠI (THE GREAT THUNDER WARHAMMER) ---
    final hammerX = cx + 44;
    final hammerY = cy - 8 + sin(time * 2.4) * 3.0;
    final hammerSway = sin(time * 2.2) * 0.06;

    canvas.save();
    canvas.translate(hammerX - 4, hammerY + 6);
    canvas.rotate(hammerSway);
    canvas.translate(-(hammerX - 4), -(hammerY + 6));

    // Cán búa bọc da nâu
    final shaftPaint = Paint()..color = const Color(0xFF4E342E)..strokeWidth = 6.5..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(hammerX, hammerY - 60), Offset(hammerX - 12, hammerY + 75), shaftPaint);
    // Chuôi búa bọc vàng
    canvas.drawCircle(Offset(hammerX - 12, hammerY + 75), 6, goldAccent);

    // Đầu búa thiên thạch khổng lồ
    final hammerRect = Rect.fromCenter(center: Offset(hammerX + 2, hammerY - 56), width: 52, height: 38);
    final hammerShader = LinearGradient(
      colors: const [Color(0xFF37474F), Color(0xFF1E272C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(hammerRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hammerRect, const Radius.circular(7)),
      Paint()..shader = hammerShader,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hammerRect, const Radius.circular(7)),
      Paint()..color = const Color(0xFFFFD54F)..style = PaintingStyle.stroke..strokeWidth = 2.2,
    );

    // Cổ ngữ Rune sấm sét phát sáng giữa đầu búa
    final runeCenter = Offset(hammerX + 2, hammerY - 56);
    final runePulse = sin(time * 3.5);
    final runeGlow = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.7 + 0.3 * runePulse)
      ..maskFilter = _webSafeBlur(10);
    canvas.drawCircle(runeCenter, 11, runeGlow);
    canvas.drawCircle(runeCenter, 6, Paint()..color = Colors.white);

    // Tia sét chạy dọc cạnh búa
    final lightning = Path()
      ..moveTo(hammerX - 18, hammerY - 60)
      ..lineTo(hammerX - 6, hammerY - 52)
      ..lineTo(hammerX + 4, hammerY - 62)
      ..lineTo(hammerX + 18, hammerY - 54);
    final lightningPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(lightning, lightningPaint);

    // Găng tay sắt giữ cán búa
    canvas.drawCircle(Offset(hammerX - 4, hammerY + 6), 9.5, Paint()..color = const Color(0xFF607D8B));
    canvas.restore();

    // --- MŨ GIÁP HOÀNG GIA & ĐÔI MẮT PHÁT SÁNG (ROYAL HELM & RADIANT EYES) ---
    final helmRect = Rect.fromCenter(center: Offset(cx, cy - 42), width: 44, height: 38);
    final helmShader = LinearGradient(
      colors: const [Color(0xFF78909C), Color(0xFF37474F)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(helmRect);
    canvas.drawRRect(RRect.fromRectAndRadius(helmRect, const Radius.circular(10)), Paint()..shader = helmShader);
    // Viền vàng mũ giáp
    canvas.drawRRect(
      RRect.fromRectAndRadius(helmRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFFFFD54F)..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    // Khe nhìn đen tuyền & Mắt xanh sấm sét rực sáng
    final visorRect = Rect.fromCenter(center: Offset(cx, cy - 40), width: 30, height: 9);
    canvas.drawRRect(RRect.fromRectAndRadius(visorRect, const Radius.circular(3)), Paint()..color = Colors.black);

    final eyeCyan = Paint()
      ..color = const Color(0xFF00E5FF)
      ..maskFilter = _webSafeBlur(4);
    canvas.drawRect(Rect.fromLTWH(cx - 10, cy - 42, 7, 5), eyeCyan);
    canvas.drawRect(Rect.fromLTWH(cx + 3, cy - 42, 7, 5), eyeCyan);

    // Mào lông vũ đỏ chiến trận uy dũng (WAR PLUME)
    final plumeWave = sin(time * 3.0) * 4;
    final plume = Path()
      ..moveTo(cx - 6, cy - 60)
      ..quadraticBezierTo(cx - 12 + plumeWave, cy - 82, cx + 8, cy - 86)
      ..quadraticBezierTo(cx + 32 + plumeWave, cy - 84, cx + 28, cy - 66)
      ..quadraticBezierTo(cx + 12, cy - 58, cx + 6, cy - 60)
      ..close();
    canvas.drawPath(plume, Paint()..color = const Color(0xFFD50000));
    canvas.drawPath(plume, Paint()..color = const Color(0xFFFF5252)..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  // =========================================================================
  // 2. TƯỚNG RANGER: CUNG THỦ ÁNH SÁNG TẦM XA (ELVEN ARCHER)
  // =========================================================================
  void _drawHeroRanger(Canvas canvas, double cx, double cy) {
    // Áo choàng ngọc bích bay phía sau
    final capeWave = sin(time * 2.8) * 5;
    final capePath = Path()
      ..moveTo(cx - 20, cy - 10)
      ..lineTo(cx + 20, cy - 10)
      ..quadraticBezierTo(cx + 30 + capeWave, cy + 35, cx + 24 + capeWave, cy + 65)
      ..lineTo(cx - 26 + capeWave * 0.5, cy + 68)
      ..quadraticBezierTo(cx - 30, cy + 35, cx - 20, cy - 10)
      ..close();
    canvas.drawPath(capePath, Paint()..color = const Color(0xFF1B5E20));

    // Đôi chân thon gọn lanh lợi
    final bootPaint = Paint()..color = const Color(0xFF3E2723);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 20, cy + 34, 15, 38), const Radius.circular(4)), bootPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 5, cy + 34, 15, 38), const Radius.circular(4)), bootPaint);

    // Áo giáp da dẻo dai màu xanh lá ngọc bảo
    final armorShader = LinearGradient(
      colors: const [Color(0xFF2E7D32), Color(0xFF1B5E20)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(cx - 22, cy - 20, 44, 40));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 22, cy - 20, 44, 40), const Radius.circular(8)), Paint()..shader = armorShader);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - 22, cy - 20, 44, 40), const Radius.circular(8)),
      Paint()..color = const Color(0xFF00E676)..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    // Dây đeo chéo đựng bao tên (Quiver strap)
    canvas.drawLine(Offset(cx - 20, cy - 18), Offset(cx + 20, cy + 18), Paint()..color = const Color(0xFFFFD54F)..strokeWidth = 3);

    // CÂY CUNG DÀI ÁNH SÁNG HUYỀN THOẠI (ELVEN RECURVE BOW)
    final bowX = cx + 38;
    final bowY = cy + sin(time * 2.4) * 3.0;
    final bowSway = sin(time * 2.0) * 0.05;
    canvas.save();
    canvas.translate(bowX - 6, bowY);
    canvas.rotate(bowSway);
    canvas.translate(-(bowX - 6), -bowY);

    final bowPath = Path()
      ..moveTo(bowX - 10, bowY - 60)
      ..quadraticBezierTo(bowX + 22, bowY, bowX - 10, bowY + 60);
    final bowPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(bowPath, bowPaint);

    // Dây cung phát quang màu xanh ngọc nhấp nháy nhịp thở
    final stringAlpha = (0.7 + 0.3 * sin(time * 3.2)).clamp(0.0, 1.0);
    final stringPaint = Paint()
      ..color = const Color(0xFF69F0AE).withValues(alpha: stringAlpha)
      ..strokeWidth = 1.8;
    canvas.drawLine(Offset(bowX - 10, bowY - 60), Offset(bowX - 10, bowY + 60), stringPaint);
    canvas.restore();

    // Mũ trùm đầu thợ săn (Ranger Hood)
    final hoodPath = Path()
      ..moveTo(cx, cy - 65)
      ..quadraticBezierTo(cx - 26, cy - 50, cx - 20, cy - 28)
      ..lineTo(cx + 20, cy - 28)
      ..quadraticBezierTo(cx + 26, cy - 50, cx, cy - 65)
      ..close();
    canvas.drawPath(hoodPath, Paint()..color = const Color(0xFF2E7D32));
    canvas.drawPath(hoodPath, Paint()..color = const Color(0xFF00E676)..style = PaintingStyle.stroke..strokeWidth = 1.8);

    // Đôi mắt ánh sáng xanh lục rực rỡ dưới mũ trùm
    final eyeGreen = Paint()
      ..color = const Color(0xFF00E676)
      ..maskFilter = _webSafeBlur(5);
    canvas.drawCircle(Offset(cx - 7, cy - 38), 3.5, eyeGreen);
    canvas.drawCircle(Offset(cx + 7, cy - 38), 3.5, eyeGreen);
    canvas.drawCircle(Offset(cx - 7, cy - 38), 1.5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + 7, cy - 38), 1.5, Paint()..color = Colors.white);
  }

  // =========================================================================
  // 3. TƯỚNG TANKER: HỘ VỆ HOÀNG GIA BẤT DIỆT (FORTRESS KNIGHT)
  // =========================================================================
  void _drawHeroTanker(Canvas canvas, double cx, double cy) {
    // Thân hình hộ pháp, chân giáp thép to lớn
    final armorSteel = Paint()..color = const Color(0xFF37474F);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 30, cy + 30, 24, 42), const Radius.circular(5)), armorSteel);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 6, cy + 30, 24, 42), const Radius.circular(5)), armorSteel);

    // Giáp thân titan dày cộm
    final chestRect = Rect.fromLTWH(cx - 32, cy - 24, 64, 46);
    canvas.drawRRect(RRect.fromRectAndRadius(chestRect, const Radius.circular(10)), Paint()..color = const Color(0xFF263238));
    canvas.drawRRect(
      RRect.fromRectAndRadius(chestRect, const Radius.circular(10)),
      Paint()..color = const Color(0xFF00B0FF)..style = PaintingStyle.stroke..strokeWidth = 2.5,
    );

    // TẤM KHIÊN THÀNH LŨY KHỔNG LỒ (THE TOWER SHIELD)
    final shieldBob = sin(time * 2.2) * 2.5;
    final shieldX = cx - 28;
    final shieldY = cy + 2 + shieldBob;
    final shieldRect = Rect.fromCenter(center: Offset(shieldX, shieldY), width: 48, height: 78);
    final shieldShader = LinearGradient(
      colors: const [Color(0xFF0277BD), Color(0xFF01579B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(shieldRect);
    canvas.drawRRect(RRect.fromRectAndRadius(shieldRect, const Radius.circular(12)), Paint()..shader = shieldShader);
    // Viền vàng tấm khiên
    canvas.drawRRect(
      RRect.fromRectAndRadius(shieldRect, const Radius.circular(12)),
      Paint()..color = const Color(0xFFFFD54F)..style = PaintingStyle.stroke..strokeWidth = 3,
    );

    // Huy hiệu khiên phòng hộ phát sáng xanh dương
    final shieldGlowAlpha = (0.55 + 0.35 * sin(time * 3.0)).clamp(0.0, 1.0);
    final shieldGlow = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: shieldGlowAlpha)
      ..maskFilter = _webSafeBlur(8);
    canvas.drawCircle(Offset(shieldX, shieldY), 12, shieldGlow);
    canvas.drawCircle(Offset(shieldX, shieldY), 7, Paint()..color = Colors.white);

    // Mũ giáp chiến hạm kiên cố
    final helmRect = Rect.fromCenter(center: Offset(cx + 6, cy - 42), width: 44, height: 38);
    canvas.drawRRect(RRect.fromRectAndRadius(helmRect, const Radius.circular(8)), Paint()..color = const Color(0xFF455A64));
    canvas.drawRRect(
      RRect.fromRectAndRadius(helmRect, const Radius.circular(8)),
      Paint()..color = const Color(0xFF00B0FF)..style = PaintingStyle.stroke..strokeWidth = 2,
    );

    // Khe nhìn mắt bảo hộ xanh băng rực lửa
    final eyeBlue = Paint()
      ..color = const Color(0xFF00E5FF)
      ..maskFilter = _webSafeBlur(4);
    canvas.drawRect(Rect.fromLTWH(cx - 6, cy - 42, 24, 6), eyeBlue);
  }

  // =========================================================================
  // 4. TƯỚNG NINJA: ÁM SÁT BÓNG ĐÊM CHÍ MẠNG (SHADOW ASSASSIN)
  // =========================================================================
  void _drawHeroNinja(Canvas canvas, double cx, double cy) {
    // Luồng khói hư không tím ma mị bao quanh (Shadow Void Mist)
    final mistPaint = Paint()
      ..color = const Color(0xFFAB47BC).withValues(alpha: 0.35 + 0.15 * sin(time * 3))
      ..maskFilter = _webSafeBlur(16);
    canvas.drawCircle(Offset(cx, cy + 20), 45, mistPaint);

    // Khăn quàng cổ Ninja bay trong gió tím thẫm
    final scarfWave = sin(time * 4.0) * 8;
    final scarfPath = Path()
      ..moveTo(cx - 12, cy - 28)
      ..quadraticBezierTo(cx - 36 + scarfWave, cy - 14, cx - 48 + scarfWave, cy - 40)
      ..lineTo(cx - 40 + scarfWave, cy - 44)
      ..quadraticBezierTo(cx - 26, cy - 24, cx - 8, cy - 26)
      ..close();
    canvas.drawPath(scarfPath, Paint()..color = const Color(0xFFE040FB));

    // Thân hình bóng đêm nhanh nhẹn
    final darkCloth = Paint()..color = const Color(0xFF1A1A24);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 18, cy + 32, 14, 38), const Radius.circular(4)), darkCloth);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 4, cy + 32, 14, 38), const Radius.circular(4)), darkCloth);

    final vestRect = Rect.fromLTWH(cx - 20, cy - 20, 40, 42);
    canvas.drawRRect(RRect.fromRectAndRadius(vestRect, const Radius.circular(6)), darkCloth);
    canvas.drawRRect(
      RRect.fromRectAndRadius(vestRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFFAB47BC)..style = PaintingStyle.stroke..strokeWidth = 1.8,
    );

    // SONG ĐAO BÓNG ĐÊM TẨM ĐỘC (DUAL SHADOW DAGGERS)
    final daggerSwing = sin(time * 3.2) * 0.10;
    // Dao trái
    _drawDagger(canvas, Offset(cx - 34, cy + 10), -0.3 + daggerSwing);
    // Dao phải
    _drawDagger(canvas, Offset(cx + 34, cy + 10), 0.3 - daggerSwing);

    // Mặt nạ che mặt Shinobi
    final maskRect = Rect.fromCenter(center: Offset(cx, cy - 40), width: 34, height: 32);
    canvas.drawRRect(RRect.fromRectAndRadius(maskRect, const Radius.circular(8)), darkCloth);

    // Đôi mắt tím dạ quang sắc lạnh
    final eyePurple = Paint()
      ..color = const Color(0xFFE040FB)
      ..maskFilter = _webSafeBlur(5);
    canvas.drawCircle(Offset(cx - 7, cy - 40), 3.0, eyePurple);
    canvas.drawCircle(Offset(cx + 7, cy - 40), 3.0, eyePurple);
    canvas.drawCircle(Offset(cx - 7, cy - 40), 1.2, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx + 7, cy - 40), 1.2, Paint()..color = Colors.white);
  }

  void _drawDagger(Canvas canvas, Offset pos, double angle) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    // Cán dao
    canvas.drawRect(Rect.fromLTWH(-3, 0, 6, 16), Paint()..color = const Color(0xFF424242));
    // Chuôi vàng
    canvas.drawCircle(const Offset(0, 18), 4, Paint()..color = const Color(0xFFFFD54F));

    // Lưỡi dao cong phát sáng tím
    final blade = Path()
      ..moveTo(-4, 0)
      ..lineTo(0, -32)
      ..lineTo(4, 0)
      ..close();
    canvas.drawPath(blade, Paint()..color = const Color(0xFFE0E0E0));

    final poisonGlow = Paint()
      ..color = const Color(0xFFE040FB).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = _webSafeBlur(4);
    canvas.drawPath(blade, poisonGlow);

    canvas.restore();
  }

  void _drawThunderSword(Canvas canvas, Offset pos, double angle, {required bool isCyan}) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final bladeColor = isCyan ? const Color(0xFF00E5FF) : const Color(0xFFFFD700);
    // Chuôi kiếm
    canvas.drawRect(const Rect.fromLTWH(-3, 0, 6, 16), Paint()..color = const Color(0xFF334155));
    canvas.drawRect(const Rect.fromLTWH(-10, -3, 20, 5), Paint()..color = const Color(0xFFFFD700));

    // Thân kiếm phát sáng
    final bladePath = Path()
      ..moveTo(-4, -3)
      ..lineTo(0, -58)
      ..lineTo(4, -3)
      ..close();
    canvas.drawPath(
      bladePath,
      Paint()
        ..color = bladeColor.withValues(alpha: 0.55)
        ..maskFilter = _webSafeBlur(6),
    );
    canvas.drawPath(bladePath, Paint()..color = bladeColor);
    canvas.drawLine(
      const Offset(0, -5),
      const Offset(0, -54),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.6,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroCanvasPainter oldDelegate) {
    return oldDelegate.heroId != heroId ||
        oldDelegate.themeColor != themeColor ||
        oldDelegate.time != time ||
        oldDelegate.animProgress != animProgress;
  }
}
