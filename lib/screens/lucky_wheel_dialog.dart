import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/player_storage.dart';

class WheelReward {
  final int coins;
  final String label;
  final Color primaryColor;
  final Color secondaryColor;
  final IconData icon;
  final bool isJackpot;

  const WheelReward({
    required this.coins,
    required this.label,
    required this.primaryColor,
    required this.secondaryColor,
    required this.icon,
    this.isJackpot = false,
  });

  int get goldValue => coins * 1000;
}

class LuckyWheelDialog extends StatefulWidget {
  const LuckyWheelDialog({super.key});

  @override
  State<LuckyWheelDialog> createState() => _LuckyWheelDialogState();
}

class _LuckyWheelDialogState extends State<LuckyWheelDialog>
    with SingleTickerProviderStateMixin {
  // 6 ô phần thưởng chuẩn hóa theo tài liệu
  static const List<WheelReward> rewards = [
    WheelReward(
      coins: 0,
      label: '0 Xu',
      primaryColor: Color(0xFFE53935),
      secondaryColor: Color(0xFFC62828),
      icon: Icons.sentiment_dissatisfied_rounded,
    ),
    WheelReward(
      coins: 1,
      label: '1 Xu',
      primaryColor: Color(0xFF1E88E5),
      secondaryColor: Color(0xFF1565C0),
      icon: Icons.monetization_on_outlined,
    ),
    WheelReward(
      coins: 2,
      label: '2 Xu',
      primaryColor: Color(0xFF8E24AA),
      secondaryColor: Color(0xFF6A1B9A),
      icon: Icons.monetization_on_rounded,
    ),
    WheelReward(
      coins: 3,
      label: '3 Xu',
      primaryColor: Color(0xFF00ACC1),
      secondaryColor: Color(0xFF00838F),
      icon: Icons.stars_rounded,
    ),
    WheelReward(
      coins: 5,
      label: '5 Xu',
      primaryColor: Color(0xFF43A047),
      secondaryColor: Color(0xFF2E7D32),
      icon: Icons.auto_awesome_rounded,
    ),
    WheelReward(
      coins: 10,
      label: '10 Xu',
      primaryColor: Color(0xFFFFB300),
      secondaryColor: Color(0xFFFF8F00),
      icon: Icons.military_tech_rounded,
      isJackpot: true,
    ),
  ];

  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentRotation = 0.0;
  bool _isSpinning = false;

  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    final profile = PlayerStorage.currentProfile;
    if (!profile.canSpinToday() && mounted) {
      setState(() {
        _remainingTime = profile.timeUntilNextReset();
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _spinWheel() {
    if (_isSpinning) return;
    final profile = PlayerStorage.currentProfile;
    if (!profile.canSpinToday()) return;

    setState(() {
      _isSpinning = true;
    });

    // Chọn ngẫu nhiên ô trúng thưởng với tỉ lệ hợp lý
    // Trọng số: 0 xu (20%), 1 xu (35%), 2 xu (25%), 3 xu (12%), 5 xu (6%), 10 xu JACKPOT (2%)
    final rand = Random().nextInt(100);
    int targetIndex = 1;
    if (rand < 20) {
      targetIndex = 0; // 0 xu
    } else if (rand < 55) {
      targetIndex = 1; // 1 xu
    } else if (rand < 80) {
      targetIndex = 2; // 2 xu
    } else if (rand < 92) {
      targetIndex = 3; // 3 xu
    } else if (rand < 98) {
      targetIndex = 4; // 5 xu
    } else {
      targetIndex = 5; // 10 xu JACKPOT
    }

    final targetReward = rewards[targetIndex];

    // Tính góc quay sao cho kim trên cùng (270 độ / 3*pi/2) dừng đúng giữa ô targetIndex
    const sweepAngle = 2 * pi / 6;
    final targetCenterAngle = (targetIndex + 0.5) * sweepAngle;

    // Vị trí kim chỉ ở trên đỉnh = 3 * pi / 2
    final baseTargetAngle = (3 * pi / 2) - targetCenterAngle;

    // Quay thêm từ 5 đến 7 vòng đầy đủ để tạo cảm giác hồi hộp
    const fullRotations = 6 * 2 * pi;
    final startAngle = _currentRotation % (2 * pi);
    final targetAngle = startAngle + fullRotations + (baseTargetAngle - (startAngle % (2 * pi)));

    int lastSector = -1;
    _animation = Tween<double>(
      begin: startAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ))..addListener(() {
        final currentSector = ((_animation.value / (2 * pi / 6)).floor()) % 6;
        if (currentSector != lastSector) {
          lastSector = currentSector;
          AudioService.instance.playSfx(SfxSound.wheelSpin);
        }
        setState(() {
          _currentRotation = _animation.value;
        });
      });

    _controller.forward(from: 0.0).then((_) async {
      _currentRotation = targetAngle;
      _isSpinning = false;

      // Cộng Vàng theo quy tắc cốt lõi: 1 Xu = 1000 Vàng
      final goldWon = targetReward.goldValue;
      await PlayerStorage.recordSpin(goldWon);

      if (mounted) {
        setState(() {});
        _showRewardDialog(targetReward);
      }
    });
  }

  void _showRewardDialog(WheelReward reward) {
    if (reward.isJackpot) {
      AudioService.instance.playSfx(SfxSound.wheelJackpot);
    } else {
      AudioService.instance.playSfx(SfxSound.pickupCoin);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E1A47), Color(0xFF160E28)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: reward.isJackpot
                    ? const Color(0xFFFFD700)
                    : const Color(0xFF9C27B0),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: (reward.isJackpot
                          ? Colors.amberAccent
                          : Colors.purpleAccent)
                      .withValues(alpha: 0.4),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  reward.coins > 0
                      ? Icons.military_tech_rounded
                      : Icons.sentiment_dissatisfied_rounded,
                  size: 64,
                  color: reward.isJackpot
                      ? const Color(0xFFFFD700)
                      : Colors.amberAccent,
                ),
                const SizedBox(height: 12),
                Text(
                  reward.coins > 0
                      ? (reward.isJackpot ? '🎉 JACKPOT KHỦNG! 🎉' : 'CHÚC MỪNG!')
                      : 'TIẾC QUÁ!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: reward.isJackpot
                        ? const Color(0xFFFFD700)
                        : Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (reward.coins > 0) ...[
                  Text(
                    'Bạn đã trúng ${reward.label}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amberAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'Tỷ giá quy đổi (1 Xu = 1000 Vàng):\n+${reward.goldValue.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} VÀNG',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFE082),
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Chúc bạn may mắn vào ngày mai nhé!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: const Text(
                    'NHẬN THƯỞNG',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerProfile>(
      valueListenable: PlayerStorage.profileNotifier,
      builder: (context, profile, _) {
        final canSpin = profile.canSpinToday() && !_isSpinning;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 380),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1736), Color(0xFF0F0C1B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: [
                // VÒNG QUAY BÊN TRÁI
                Expanded(
                  flex: 5,
                  child: Center(
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Bánh đĩa quay
                          Transform.rotate(
                            angle: _currentRotation,
                            child: CustomPaint(
                              size: const Size(270, 270),
                              painter: _WheelPainter(rewards: rewards),
                            ),
                          ),
                          // Vòng viền ngoài trang trí kim loại vàng
                          Container(
                            width: 276,
                            height: 276,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFD700),
                                width: 5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amberAccent.withValues(alpha: 0.3),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                          // Trục tâm đĩa
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFFFFEE58), Color(0xFFF57F17)],
                              ),
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                )
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.star_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                          // MŨI KIM CHỈ Ở TRÊN ĐỈNH
                          Positioned(
                            top: 0,
                            child: CustomPaint(
                              size: const Size(28, 36),
                              painter: _NeedlePainter(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // BẢNG THÔNG TIN VÀ NÚT QUAY BÊN PHẢI
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Tiêu đề & Nút đóng
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.casino_rounded,
                                color: Color(0xFFFFD700),
                                size: 26,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'VÒNG QUAY MAY MẮN',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFFD700),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: _isSpinning
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Tỷ giá quy đổi
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.amberAccent.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.currency_exchange_rounded,
                                size: 20, color: Color(0xFFFFD700)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Quy tắc vàng: 1 Xu trúng = 1.000 Vàng vào tài khoản!',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFFECB3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Quy định reset
                      const Text(
                        '• Miễn phí 1 lượt quay mỗi ngày.\n• Tự động làm mới lúc 00:00 UTC (07:00 sáng VN).',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const Spacer(),

                      // KHU VỰC NÚT QUAY HOẶC ĐỒNG HỒ ĐẾM NGƯỢC
                      if (canSpin) ...[
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB300), Color(0xFFFF6F00)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.5),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _spinWheel,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.play_arrow_rounded,
                                    size: 26, color: Colors.black87),
                                SizedBox(width: 8),
                                Text(
                                  'QUAY MIỄN PHÍ NGAY',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'ĐÃ HẾT LƯỢT QUAY HÔM NAY',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 18, color: Colors.amberAccent),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Làm mới sau: ${_formatDuration(_remainingTime)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                      color: Colors.amberAccent,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// CustomPainter vẽ 6 nan quạt đĩa quay
class _WheelPainter extends CustomPainter {
  final List<WheelReward> rewards;

  const _WheelPainter({required this.rewards});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sweepAngle = 2 * pi / rewards.length;

    final paint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.7);

    for (int i = 0; i < rewards.length; i++) {
      final reward = rewards[i];
      final startAngle = i * sweepAngle;

      // Vẽ lát quạt
      paint.shader = SweepGradient(
        center: Alignment.center,
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [reward.primaryColor, reward.secondaryColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Vẽ đường phân chia
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      // Vẽ chữ và icon trên nan quạt
      canvas.save();
      canvas.translate(center.dx, center.dy);
      // Xoay tới tâm của nan quạt
      canvas.rotate(startAngle + sweepAngle / 2);

      // Đoạn text chữ
      final textSpan = TextSpan(
        text: reward.label + (reward.isJackpot ? '\n⭐JACKPOT⭐' : ''),
        style: TextStyle(
          color: Colors.white,
          fontSize: reward.isJackpot ? 11 : 13,
          fontWeight: FontWeight.w900,
          shadows: const [
            Shadow(blurRadius: 4, color: Colors.black87, offset: Offset(1, 1)),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      // Đặt chữ ở vị trí khoảng 65% bán kính
      textPainter.paint(
        canvas,
        Offset(radius * 0.55 - textPainter.width / 2, -textPainter.height / 2),
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}

/// CustomPainter vẽ kim chỉ định hướng góc trên đỉnh
class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    // Tam giác nhọn chúc xuống
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();

    final paint = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.fill;

    final border = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final shadowPaint = Paint()
      ..color = Colors.black45
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(path.shift(const Offset(0, 2)), shadowPaint);
    canvas.drawPath(path, paint);
    canvas.drawPath(path, border);

    // Điểm nhấn ngọc ở đầu kim
    final gemPaint = Paint()..color = const Color(0xFFFFEE58);
    canvas.drawCircle(Offset(size.width / 2, 8), 4, gemPaint);
  }

  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) => false;
}
