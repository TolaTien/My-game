import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Lớp bảo vệ hướng màn hình (OrientationGuard) cho game BIG-WAR.
/// Bắt buộc và hướng dẫn người chơi xoay ngang thiết bị khi truy cập bằng điện thoại
/// trên cả ứng dụng di động (Android / iOS) lẫn trình duyệt Web di động (Safari / Chrome).
class OrientationGuard extends StatefulWidget {
  final Widget child;

  const OrientationGuard({
    super.key,
    required this.child,
  });

  @override
  State<OrientationGuard> createState() => _OrientationGuardState();
}

class _OrientationGuardState extends State<OrientationGuard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _rotationAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _rotationAnim = TweenSequence<double>([
      // 1. Giữ dọc 0 độ
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.0)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 20,
      ),
      // 2. Xoay từ dọc sang ngang 90 độ (chiều kim đồng hồ)
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -math.pi / 2)
            .chain(CurveTween(curve: Curves.easeInOutCubicEmphasized)),
        weight: 45,
      ),
      // 3. Giữ ngang một lúc cho người chơi nhận thức
      TweenSequenceItem(
        tween: Tween<double>(begin: -math.pi / 2, end: -math.pi / 2)
            .chain(CurveTween(curve: Curves.linear)),
        weight: 25,
      ),
      // 4. Trả về vị trí ban đầu
      TweenSequenceItem(
        tween: Tween<double>(begin: -math.pi / 2, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
    ]).animate(_animCtrl);

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestLandscape() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // Bỏ qua nếu nền tảng trình duyệt hạn chế API
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;

    // Xác định chế độ màn hình dọc:
    // 1) Hướng orientation là Portrait HOẶC chiều cao lớn hơn chiều rộng
    final isPortrait = mediaQuery.orientation == Orientation.portrait ||
        (size.height > size.width && size.width < 600);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Nội dung game chính
        widget.child,

        // Lớp phủ thông báo xoay ngang màn hình (chỉ hiển thị khi đang dọc)
        if (isPortrait)
          Positioned.fill(
            child: Material(
              color: const Color(0xFF060B16),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Huy hiệu thương hiệu game
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF260B03),
                                  Color(0xFF451505),
                                  Color(0xFF260B03),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFFFD54F),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF5722)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sports_kabaddi_rounded,
                                  color: Color(0xFFFEF08A),
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'BIG-WAR · ĐẤU TRƯỜNG SINH TỬ',
                                  style: TextStyle(
                                    color: Color(0xFFFEF08A),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.sports_kabaddi_rounded,
                                  color: Color(0xFFFEF08A),
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Hoạt ảnh xoay điện thoại từ dọc sang ngang
                        AnimatedBuilder(
                          animation: _animCtrl,
                          builder: (context, _) {
                            return Transform.scale(
                              scale: _pulseAnim.value,
                              child: SizedBox(
                                width: 140,
                                height: 140,
                                child: CustomPaint(
                                  painter: _RotatePhoneGraphicPainter(
                                    rotation: _rotationAnim.value,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Dòng tiêu đề chính
                        ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [
                              Color(0xFFFFFFFF),
                              Color(0xFFFEF08A),
                              Color(0xFFFFD54F),
                              Color(0xFFFF9800),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ).createShader(rect),
                          child: const Text(
                            'VUI LÒNG XOAY NGANG MÀN HÌNH',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Lời giải thích
                        const Text(
                          'Chiến trường BIG-WAR được thiết kế chuyên biệt cho góc nhìn chiến thuật toàn cảnh và cụm phím ảo Joystick ở màn hình ngang (Landscape).',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Khung mẹo hướng dẫn người dùng
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF334155),
                              width: 1.0,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.screen_rotation_rounded,
                                color: Color(0xFF38BDF8),
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Gợi ý: Hãy bật "Tự động xoay" (Auto-Rotate) trong Cài đặt nhanh của điện thoại và xoay ngang máy.',
                                  style: TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Nút yêu cầu xoay ngang / toàn màn hình
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ElevatedButton.icon(
                            onPressed: _requestLandscape,
                            icon: const Icon(
                              Icons.fullscreen_rounded,
                              size: 18,
                              color: Color(0xFF1E1303),
                            ),
                            label: const Text(
                              'KÍCH HOẠT XOAY NGANG NGAY',
                              style: TextStyle(
                                color: Color(0xFF1E1303),
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                                letterSpacing: 0.8,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFB300),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Vẽ điện thoại xoay ngang nghệ thuật và mũi tên định hướng vòng tròn
class _RotatePhoneGraphicPainter extends CustomPainter {
  final double rotation;

  const _RotatePhoneGraphicPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    // 1. Vòng hào quang phát sáng phía sau
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFB300).withValues(alpha: 0.25),
          const Color(0xFF10B981).withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.3));
    canvas.drawCircle(center, radius * 1.25, glowPaint);

    // 2. Vòng tròn cung xoay kèm mũi tên định hướng
    final arcPaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(arcRect, -math.pi * 0.8, math.pi * 0.65, false, arcPaint);
    canvas.drawArc(arcRect, math.pi * 0.2, math.pi * 0.65, false, arcPaint);

    // 3. Điện thoại xoay
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    const phoneW = 44.0;
    const phoneH = 78.0;
    const r = 8.0;
    final phoneRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-phoneW / 2, -phoneH / 2, phoneW, phoneH),
      const Radius.circular(r),
    );

    // Thân điện thoại ngoài
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF334155),
          Color(0xFF0F172A),
          Color(0xFF1E293B),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(phoneRect.outerRect);
    canvas.drawRRect(phoneRect, bodyPaint);

    // Viền kim loại mạ vàng
    final borderPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFEF08A),
          Color(0xFFFFB300),
          Color(0xFFFF6F00),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(phoneRect.outerRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(phoneRect, borderPaint);

    // Màn hình bên trong
    const pad = 4.0;
    final screenRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(
        -phoneW / 2 + pad,
        -phoneH / 2 + pad + 2,
        phoneW - pad * 2,
        phoneH - pad * 2 - 4,
      ),
      const Radius.circular(4.0),
    );

    final screenPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF0284C7),
          Color(0xFF0369A1),
          Color(0xFF0C4A6E),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(screenRect.outerRect);
    canvas.drawRRect(screenRect, screenPaint);

    // Vạch game phong cách chiến trường trên màn hình
    final barPaint = Paint()
      ..color = const Color(0xFFFEF08A).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-12, -18, 24, 6),
        const Radius.circular(2),
      ),
      barPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-16, -6, 32, 18),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.7),
    );

    // Nút Home / Dải loa
    final notchPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, -phoneH / 2 + 2, 12, 2.5),
        const Radius.circular(1),
      ),
      notchPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RotatePhoneGraphicPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
