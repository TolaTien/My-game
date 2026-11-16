import 'package:flutter/material.dart';
import '../gold_rush_game.dart';
import '../components/boss_enemy.dart';

class BossBarOverlay extends StatelessWidget {
  final GoldRushGame game;

  const BossBarOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BossHpData?>(
      valueListenable: game.bossHpNotifier,
      builder: (context, data, child) {
        if (data == null || data.isDefeated) {
          return const SizedBox.shrink();
        }

        final isEnraged = data.isEnraged;
        final hpPercent = data.hpPercent;

        return Center(
          child: Container(
            width: 380,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xEE12121E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEnraged ? const Color(0xFFFF3D00) : const Color(0xFFFFD700),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isEnraged ? const Color(0x66FF3D00) : const Color(0x44FFD700),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Row: Skull icon, Title, Phase Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isEnraged ? Icons.whatshot : Icons.dangerous,
                            color: isEnraged ? Colors.deepOrangeAccent : Colors.amberAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            data.title,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isEnraged ? const Color(0xFFD50000) : const Color(0xFF263238),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isEnraged ? Colors.orangeAccent : Colors.cyanAccent,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          isEnraged ? '🔥 CUỒNG NỘ' : 'GIAI ĐOẠN 1',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Health Bar with Ghost Lagging Bar & Minion Summon Ticks
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 1. Background Bar
                      Container(
                        width: 356,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                      ),

                      // 2. Ghost Damage Bar (Lagging)
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: hpPercent, end: hpPercent),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutQuad,
                        builder: (context, value, child) {
                          return Container(
                            width: 356 * value,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE082),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          );
                        },
                      ),

                      // 3. Active Foreground HP Bar
                      Container(
                        width: 356 * hpPercent,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isEnraged
                                ? [const Color(0xFFFF3D00), const Color(0xFFFF9100)]
                                : [const Color(0xFFD32F2F), const Color(0xFF880E4F)],
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),

                      // 4. Threshold Tick Markers: 70%, 50%, 30%
                      Positioned(
                        left: 356 * 0.70,
                        child: Container(
                          width: 2,
                          height: 14,
                          color: Colors.cyanAccent.withValues(alpha: 0.8),
                        ),
                      ),
                      Positioned(
                        left: 356 * 0.50,
                        child: Container(
                          width: 2.5,
                          height: 14,
                          color: Colors.amberAccent,
                        ),
                      ),
                      Positioned(
                        left: 356 * 0.30,
                        child: Container(
                          width: 2,
                          height: 14,
                          color: Colors.cyanAccent.withValues(alpha: 0.8),
                        ),
                      ),

                      // 5. HP Numeric Overlay Text
                      SizedBox(
                        width: 356,
                        height: 14,
                        child: Center(
                          child: Text(
                            '${data.currentHp.toInt()} / ${data.maxHp.toInt()} HP (${(hpPercent * 100).toInt()}%)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
