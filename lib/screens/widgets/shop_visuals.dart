import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Snap to the card grid after dragging, including when the last page is partial.
class ShopCardScrollPhysics extends ScrollPhysics {
  final double extent;
  const ShopCardScrollPhysics(this.extent, {super.parent});
  @override
  ShopCardScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      ShopCardScrollPhysics(extent, parent: buildParent(ancestor));
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    var card = position.pixels / extent;
    if (velocity.abs() > tolerance.velocity) card += velocity.sign * .35;
    final target = (card.round() * extent)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - target).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

/// Display one real frame from a transparent sprite sheet, without editing it.
class ShopSpritePreview extends StatefulWidget {
  final String asset;
  final int columns, rows;
  final Widget fallback;
  const ShopSpritePreview({
    super.key,
    required this.asset,
    this.columns = 1,
    this.rows = 1,
    required this.fallback,
  });
  @override
  State<ShopSpritePreview> createState() => _ShopSpritePreviewState();
}

class _ShopSpritePreviewState extends State<ShopSpritePreview> {
  ui.Image? _image;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShopSpritePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final bytes = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      final previous = _image;
      setState(() => _image = frame.image);
      previous?.dispose();
    } catch (error) {
      debugPrint('Shop preview could not load ${widget.asset}: $error');
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? widget.fallback
      : CustomPaint(
          painter: _FramePainter(_image!, widget.columns, widget.rows),
        );
}

class _FramePainter extends CustomPainter {
  final ui.Image image;
  final int columns, rows;
  _FramePainter(this.image, this.columns, this.rows);
  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width / columns, height = image.height / rows;
    final scale = math.min(size.width / width, size.height / height);
    final destination = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width * scale,
      height: height * scale,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, width, height),
      destination,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter oldDelegate) =>
      image != oldDelegate.image ||
      columns != oldDelegate.columns ||
      rows != oldDelegate.rows;
}
