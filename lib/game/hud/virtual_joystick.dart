import 'dart:math';
import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final Function(Offset direction) onDirectionChanged;
  final double baseRadius;
  final double knobRadius;

  const VirtualJoystick({
    super.key,
    required this.onDirectionChanged,
    this.baseRadius = 60.0,
    this.knobRadius = 25.0,
  });

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _dragPosition = Offset.zero;
  double get _baseRadius => widget.baseRadius;
  double get _knobRadius => widget.knobRadius;

  @override
  Widget build(BuildContext context) {
    final isDragging = _dragPosition.distance > 4.0;
    final dragAngle = isDragging ? atan2(_dragPosition.dy, _dragPosition.dx) : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _updateOffset(details.localPosition),
      onPanUpdate: (details) => _updateOffset(details.localPosition),
      onPanEnd: (_) => _resetJoystick(),
      onPanCancel: () => _resetJoystick(),
      child: SizedBox(
        width: _baseRadius * 2 + 20,
        height: _baseRadius * 2 + 20,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Đế Joystick Golden-Cyber với 4 mũi tên định hướng (Directional Chevrons)
              CustomPaint(
                size: Size(_baseRadius * 2, _baseRadius * 2),
                painter: _JoystickBasePainter(
                  isDragging: isDragging,
                  dragAngle: dragAngle,
                ),
              ),
              // Cần gạt Knob Kim Loại Vàng Ròng (#FFD700)
              Transform.translate(
                offset: _dragPosition,
                child: Container(
                  width: _knobRadius * 2,
                  height: _knobRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFFFFF59D),
                        Color(0xFFFFD700),
                        Color(0xFFFF8F00),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                    border: Border.all(
                      color: isDragging ? const Color(0xFF00E5FF) : Colors.white,
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: isDragging ? 0.65 : 0.35),
                        blurRadius: isDragging ? 12 : 6,
                        spreadRadius: isDragging ? 2 : 0,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.65),
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateOffset(Offset localPos) {
    final center = Offset(_baseRadius + 10, _baseRadius + 10);
    final delta = localPos - center;
    final distance = delta.distance;

    Offset clampedDelta;
    if (distance > _baseRadius) {
      clampedDelta = Offset(
        (delta.dx / distance) * _baseRadius,
        (delta.dy / distance) * _baseRadius,
      );
    } else {
      clampedDelta = delta;
    }

    setState(() {
      _dragPosition = clampedDelta;
    });

    // Chuẩn hóa vector hướng [-1.0, 1.0]
    final normalized = Offset(
      clampedDelta.dx / _baseRadius,
      clampedDelta.dy / _baseRadius,
    );
    widget.onDirectionChanged(normalized);
  }

  void _resetJoystick() {
    setState(() {
      _dragPosition = Offset.zero;
    });
    widget.onDirectionChanged(Offset.zero);
  }
}

class _JoystickBasePainter extends CustomPainter {
  final bool isDragging;
  final double dragAngle;

  const _JoystickBasePainter({
    required this.isDragging,
    required this.dragAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Nền Obsidian bán trong suốt (rgba(15, 23, 42, 0.45))
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0x730F172A),
    );

    // 2. Viền ngoài Hoàng Kim & viền trong Lôi Quang
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: isDragging ? 0.75 : 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      center,
      radius - 8,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 3. Tâm định vị
    canvas.drawCircle(
      center,
      5,
      Paint()..color = Colors.white24,
    );

    // 4. 4 mũi tên Chevron định hướng
    final chevronAngles = [0.0, pi / 2, pi, -pi / 2];
    for (final angle in chevronAngles) {
      double angleDiff = (dragAngle - angle).abs();
      if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
      final isHighlighted = isDragging && angleDiff < pi / 3;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final tipX = radius - 7;
      final chevronPath = Path()
        ..moveTo(tipX - 6, -5)
        ..lineTo(tipX, 0)
        ..lineTo(tipX - 6, 5);
      canvas.drawPath(
        chevronPath,
        Paint()
          ..color = isHighlighted
              ? const Color(0xFFFFD700)
              : Colors.white.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlighted ? 2.5 : 1.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _JoystickBasePainter oldDelegate) =>
      oldDelegate.isDragging != isDragging ||
      oldDelegate.dragAngle != dragAngle;
}
