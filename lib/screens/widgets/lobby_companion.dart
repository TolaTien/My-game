import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../registry/sprite_image_cache.dart';
import '../../game/rendering/fox_spirit_visual.dart';
import '../../game/rendering/dragon_spirit_visual.dart';

class LobbyCompanion extends StatefulWidget {
  const LobbyCompanion({super.key, required this.companionId});
  final String companionId;
  @override
  State<LobbyCompanion> createState() => _LobbyCompanionState();
}

class _LobbyCompanionState extends State<LobbyCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: CompanionLobbyPainter(widget.companionId, _clock),
        size: const Size(100, 120),
      ),
    ),
  );
}

/// Independent joint rigs and mechanical layers; no whole-body stretching.
class CompanionLobbyPainter extends CustomPainter {
  CompanionLobbyPainter(this.id, this.clock) : super(repaint: clock);
  final String id;
  final Animation<double> clock;
  static const ice = Color(0xFF8BEAFF), gold = Color(0xFFFFD36B);
  Color get basicColor => switch (id) {
    'comp_attack' => const Color(0xFFFF784F),
    'comp_defense' => const Color(0xFF619CFF),
    'comp_control' => const Color(0xFF53E5BE),
    _ => ice,
  };
  @override
  void paint(Canvas c, Size size) {
    final t = (clock.value * 72).floor() / 72 * 2 * math.pi;
    final image = SpriteImageCache.instance.getCompanionImage(id);
    final idleSheet = SpriteImageCache.instance.getCompanionIdleSheet(id);
    final scale = math.min(size.width / 100, size.height / 120);
    c.save();
    c.translate(
      (size.width - 100 * scale) / 2,
      (size.height - 120 * scale) / 2,
    );
    c.scale(scale);
    if (id == 'luna_fox') {
      _walkingFox(c, image, idleSheet);
      c.restore();
      return;
    }
    if (id == 'pyro_frost_dragon' && idleSheet != null) {
      final center = Offset(50 + math.sin(t) * 10, 52 + math.sin(t * 2) * 3);
      c.drawOval(
        Rect.fromCenter(center: Offset(center.dx, 105), width: 25, height: 4),
        Paint()..color = Colors.black.withValues(alpha: .13),
      );
      DragonSpiritVisual.draw(
        c,
        idleSheet,
        center: center,
        width: 104,
        seconds: clock.value * 6,
        facingRight: math.cos(t) >= 0,
      );
      c.restore();
      return;
    }
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(50, 105),
        width: 27 - math.sin(t * 2) * 2,
        height: 4,
      ),
      Paint()..color = Colors.black.withValues(alpha: .15),
    );
    c.translate(50 + math.sin(t) * 1.5, 54 + math.sin(t * 2) * 2.5);
    if (id == 'luna_fox' && idleSheet != null) {
      _foxFrames(c, idleSheet);
    } else if (id == 'luna_fox' && image != null) {
      // While decoding, use the original portrait without deforming its anatomy.
      _image(c, image);
    } else if (image == null) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-19, -15, 38, 30),
          const Radius.circular(8),
        ),
        Paint()..color = Color.lerp(const Color(0xFF172A40), basicColor, .30)!,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-19, -15, 38, 30),
          const Radius.circular(8),
        ),
        Paint()
          ..color = basicColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _lens(c, Offset.zero, 5, t, basicColor);
      _jet(c, const Offset(0, 16), t, basicColor);
    } else if (id == 'luna_fox' ||
        id == 'pyro_frost_dragon' ||
        id == 'cyber_drone') {
      _limbs(c, image, t);
      if (id == 'cyber_drone') {
        _jet(c, const Offset(-9, 27), t);
        _jet(c, const Offset(9, 27), t + .7);
        _lens(c, const Offset(3, -1), 3, t, ice);
      } else if (id == 'luna_fox') {
        for (var i = 0; i < 3; i++) {
          final p = (clock.value * 2 + i / 3) % 1;
          c.drawCircle(
            Offset(22 + p * 12, -22 - p * 10 + math.sin(t * 3 + i) * 2),
            1.2,
            Paint()..color = ice.withValues(alpha: math.sin(p * math.pi) * .7),
          );
        }
      } else {
        final pulse = math.pow(math.max(0, math.sin(t * 2)), 6).toDouble();
        for (var i = 0; i < 4; i++) {
          c.drawCircle(
            Offset(42 + i * 2.4, -8 - i * .7),
            1.3 - i * .2,
            Paint()
              ..color = Color.lerp(
                const Color(0xFFFFA34A),
                ice,
                (math.sin(t) + 1) / 2,
              )!.withValues(alpha: pulse * (1 - i / 5)),
          );
        }
      }
    } else if (id == 'aegis_x9') {
      _ring(c, t * 2, ice, .7, false);
      _ring(c, -t * 2, gold, -.7, false);
      c.save();
      c.clipPath(
        Path()
          ..moveTo(0, -27)
          ..lineTo(20, 0)
          ..lineTo(0, 27)
          ..lineTo(-20, 0)
          ..close(),
      );
      _image(c, image);
      c.restore();
      _lens(c, const Offset(0, -4), 3, t, gold);
      _ring(c, t * 2, ice, .7, true);
      _ring(c, -t * 2, gold, -.7, true);
    } else {
      _image(c, image);
      for (var i = 0; i < 4; i++) {
        c.drawArc(
          const Rect.fromLTWH(-34, -34, 68, 68),
          t * 2 + i * math.pi / 2,
          .32,
          false,
          Paint()
            ..color = gold.withValues(alpha: .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      _lens(c, Offset.zero, 5, t, ice);
      _jet(c, const Offset(0, 31), t);
    }
    c.restore();
  }

  void _walkingFox(Canvas c, ui.Image? portrait, ui.Image? idle) {
    final seconds = clock.value * 6;
    final motion = FoxLobbyMotion.at(seconds);
    final run = SpriteImageCache.instance.getCompanionRunSheet(id);
    final sheet = motion.running ? (run ?? idle) : idle;
    c.drawOval(
      Rect.fromCenter(center: Offset(motion.x, 92), width: 25, height: 4),
      Paint()..color = Colors.black.withValues(alpha: .18),
    );
    if (sheet != null) {
      FoxSpiritVisual.drawSprite(
        c,
        sheet,
        center: Offset(motion.x, motion.running && run != null ? 64 : 60),
        width: 88,
        seconds: seconds,
        facingRight: motion.facingRight,
        running: motion.running && run != null,
      );
    } else if (portrait != null) {
      c.save();
      c.translate(motion.x, 60);
      _image(c, portrait);
      c.restore();
    }
  }

  void _foxFrames(Canvas c, ui.Image sheet) {
    FoxSpiritVisual.drawSprite(
      c,
      sheet,
      center: Offset.zero,
      width: 98,
      seconds: clock.value * 6,
    );
  }

  Rect _bounds(ui.Image image) {
    final ratio = image.width / image.height;
    final w = ratio >= 1 ? 86.0 : 76.0 * ratio;
    return Rect.fromCenter(center: Offset.zero, width: w, height: w / ratio);
  }

  void _image(Canvas c, ui.Image image) => c.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    _bounds(image),
    Paint()..filterQuality = FilterQuality.none,
  );
  double _ease(double a) {
    final v = a.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  Offset _joint(Offset p, Offset pivot, double angle, double weight) {
    final a = angle * _ease(weight), d = p - pivot;
    return pivot +
        Offset(
          d.dx * math.cos(a) - d.dy * math.sin(a),
          d.dx * math.sin(a) + d.dy * math.cos(a),
        );
  }

  void _limbs(Canvas c, ui.Image image, double t) {
    const columns = 36, rows = 32;
    final r = _bounds(image),
        positions = <Offset>[],
        uv = <Offset>[],
        indices = <int>[];
    final w = r.width, h = r.height;
    for (var y = 0; y <= rows; y++) {
      for (var x = 0; x <= columns; x++) {
        final u = x / columns, v = y / rows;
        var p = Offset((u - .5) * w, (v - .5) * h);
        if (id == 'pyro_frost_dragon') {
          final wing = _ease((.62 - u) / .30) * _ease((.56 - v) / .18);
          p = _joint(
            p,
            Offset(.07 * w, -.05 * h),
            (math.sin(t * 6) + .18 * math.sin(t * 12)) * .30,
            wing,
          );
          final tail = _ease((.40 - u) / .30) * _ease((v - .53) / .20);
          p = _joint(
            p,
            Offset(-.05 * w, .14 * h),
            math.sin(t * 3 - .9) * .23,
            tail,
          );
          p = _joint(
            p,
            Offset(.02 * w, .21 * h),
            math.sin(t * 6 - 1.2) * .09,
            _ease((v - .74) / .22),
          );
        } else if (id == 'luna_fox') {
          final tail = _ease((u - .65) / .26);
          p = _joint(p, Offset(.15 * w, .02 * h), math.sin(t * 2) * .22, tail);
          final ears = _ease((.35 - v) / .23) * _ease((.53 - u) / .20);
          p = _joint(
            p,
            Offset(-.26 * w, -.14 * h),
            math.pow(math.max(0, math.sin(t * 2)), 8).toDouble() * .18,
            ears,
          );
          p = _joint(
            p,
            Offset((u - .5) * w, .18 * h),
            math.sin(t * 2 + (u < .5 ? 0 : math.pi)) * .035,
            _ease((v - .71) / .23) * (1 - tail),
          );
        } else {
          final arms =
              _ease((.44 - v) / .22) * _ease(((u - .5).abs() - .15) / .25);
          p = _joint(
            p,
            Offset(u < .5 ? -.17 * w : .17 * w, -.08 * h),
            math.sin(t * 4) * (u < .5 ? -.13 : .13),
            arms,
          );
        }
        positions.add(p);
        uv.add(Offset(u * image.width, v * image.height));
        if (x < columns && y < rows) {
          final n = y * (columns + 1) + x;
          indices.addAll([
            n,
            n + 1,
            n + columns + 1,
            n + 1,
            n + columns + 2,
            n + columns + 1,
          ]);
        }
      }
    }
    final mesh = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: uv,
      indices: indices,
    );
    c.drawVertices(
      mesh,
      BlendMode.srcOver,
      Paint()
        ..filterQuality = FilterQuality.none
        ..shader = ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
        ),
    );
    mesh.dispose();
  }

  void _jet(Canvas c, Offset p, double t, [Color color = ice]) {
    final length = 7 + 2 * math.sin(t * 12);
    c.drawPath(
      Path()
        ..moveTo(p.dx - 3, p.dy)
        ..quadraticBezierTo(p.dx - 2, p.dy + length, p.dx, p.dy + length)
        ..quadraticBezierTo(p.dx + 2, p.dy + length, p.dx + 3, p.dy)
        ..close(),
      Paint()..color = color.withValues(alpha: .55),
    );
    c.drawLine(
      p,
      p + Offset(0, length * .6),
      Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5,
    );
  }

  void _lens(Canvas c, Offset p, double r, double t, Color color) {
    c.drawCircle(
      p,
      r + 2,
      Paint()..color = color.withValues(alpha: .12 + .08 * math.sin(t * 4)),
    );
    c.drawCircle(
      p + Offset(math.sin(t * 2) * r * .35, 0),
      r * .42,
      Paint()..color = Colors.white.withValues(alpha: .85),
    );
  }

  void _ring(Canvas c, double t, Color color, double tilt, bool front) {
    c.save();
    c.rotate(tilt);
    c.drawArc(
      Rect.fromCenter(center: Offset.zero, width: 72, height: 25),
      front ? 0 : math.pi,
      math.pi,
      false,
      Paint()
        ..color = color.withValues(alpha: front ? .85 : .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
    final a = t % (math.pi * 2);
    if ((math.sin(a) >= 0) == front) {
      final p = Offset(math.cos(a) * 36, math.sin(a) * 12.5);
      c.drawCircle(p, 2.2, Paint()..color = color);
      c.drawCircle(p, 1, Paint()..color = Colors.white);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(covariant CompanionLobbyPainter old) =>
      old.id != id || old.clock != clock;
}

/// A short grounded patrol, with pauses before each change of direction.
class FoxLobbyMotion {
  const FoxLobbyMotion(this.x, this.running, this.facingRight);
  final double x;
  final bool running;
  final bool facingRight;
  static FoxLobbyMotion at(double seconds) {
    final t = seconds % 6;
    if (t < 1) return const FoxLobbyMotion(32, false, true);
    if (t < 2.5) return FoxLobbyMotion(32 + (t - 1) / 1.5 * 36, true, true);
    if (t < 3.5) return const FoxLobbyMotion(68, false, false);
    if (t < 5) return FoxLobbyMotion(68 - (t - 3.5) / 1.5 * 36, true, false);
    return const FoxLobbyMotion(32, false, true);
  }
}
