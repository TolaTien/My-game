import 'package:flutter/material.dart';
import '../big_war_game.dart';
import '../components/boss_enemy.dart';

class BossBarOverlay extends StatelessWidget {
  final BigWarGame game;
  final double maxWidth;
  final bool compact;

  const BossBarOverlay({
    super.key,
    required this.game,
    this.maxWidth = 250,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BossHpData?>(
      valueListenable: game.bossHpNotifier,
      builder: (context, data, child) {
        if (data == null || data.isDefeated) {
          return const SizedBox.shrink();
        }

        final isEnraged = data.isEnraged;
        final hpPercent = data.hpPercent.clamp(0.0, 1.0);
        final barHeight = compact ? 9.5 : 11.0;
        final hPad = compact ? 8.0 : 10.0;
        final vPad = compact ? 4.0 : 5.0;

        return IgnorePointer(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                decoration: BoxDecoration(
                  color: const Color(0xDC12121E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isEnraged
                        ? const Color(0xFFFF3D00)
                        : const Color(0xFFFFD700),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isEnraged
                          ? const Color(0x55FF3D00)
                          : const Color(0x33FFD700),
                      blurRadius: 6,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Row: Icon + Boss Title + Phase Badge
                    Row(
                      children: [
                        Icon(
                          isEnraged ? Icons.whatshot : Icons.dangerous,
                          color: isEnraged
                              ? Colors.deepOrangeAccent
                              : Colors.amberAccent,
                          size: compact ? 13 : 14,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: compact ? 9.5 : 10.5,
                              letterSpacing: 0.6,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isEnraged
                                ? const Color(0xFFD50000)
                                : const Color(0xFF263238),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isEnraged
                                  ? Colors.orangeAccent
                                  : Colors.cyanAccent,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            isEnraged ? 'CUỒNG NỘ' : 'P1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 7.5 : 8.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 3 : 4),

                    // Responsive Health Bar with Ghost Lagging Bar & Threshold Ticks
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final barWidth = constraints.maxWidth;
                        final radius = BorderRadius.circular(barHeight / 2);
                        return SizedBox(
                          width: barWidth,
                          height: barHeight,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // 1. Background Bar
                              Container(
                                width: barWidth,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: radius,
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 0.8,
                                  ),
                                ),
                              ),

                              // 2. Ghost Damage Bar (Lagging)
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: hpPercent,
                                  end: hpPercent,
                                ),
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeOutQuad,
                                builder: (context, value, child) {
                                  return Container(
                                    width: barWidth * value,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFE082),
                                      borderRadius: radius,
                                    ),
                                  );
                                },
                              ),

                              // 3. Active Foreground HP Bar
                              Container(
                                width: barWidth * hpPercent,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isEnraged
                                        ? const [
                                            Color(0xFFFF3D00),
                                            Color(0xFFFF9100),
                                          ]
                                        : const [
                                            Color(0xFFD32F2F),
                                            Color(0xFF880E4F),
                                          ],
                                  ),
                                  borderRadius: radius,
                                ),
                              ),

                              // 4. Threshold Tick Markers: 70%, 50%, 30%
                              Positioned(
                                left: barWidth * 0.70,
                                child: Container(
                                  width: 1.5,
                                  height: barHeight,
                                  color: Colors.cyanAccent
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                              Positioned(
                                left: barWidth * 0.50,
                                child: Container(
                                  width: 2.0,
                                  height: barHeight,
                                  color: Colors.amberAccent,
                                ),
                              ),
                              Positioned(
                                left: barWidth * 0.30,
                                child: Container(
                                  width: 1.5,
                                  height: barHeight,
                                  color: Colors.cyanAccent
                                      .withValues(alpha: 0.75),
                                ),
                              ),

                              // 5. HP Numeric Overlay Text
                              Center(
                                child: Text(
                                  '${data.currentHp.toInt()}/${data.maxHp.toInt()} (${(hpPercent * 100).toInt()}%)',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 7.5 : 8.0,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                    shadows: const [
                                      Shadow(color: Colors.black, blurRadius: 2),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
