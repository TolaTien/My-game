import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/player_profile.dart';
import '../../models/pvp_match.dart';
import '../../services/audio_service.dart';
import 'rank_badge.dart';

/// Hộp thoại hiển thị thông tin hồ sơ và bậc Rank người chơi (Chỉ xem - Read-only)
/// Tên người chơi và Mã ID là cố định, không thể chỉnh sửa.
class EditProfileDialog extends StatelessWidget {
  final PlayerProfile profile;

  const EditProfileDialog({super.key, required this.profile});

  static Future<void> show(BuildContext context, PlayerProfile profile) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => EditProfileDialog(profile: profile),
    );
  }

  Widget _buildRankCard(PlayerProfile profile) {
    final tierColor = profile.rankColor;
    final starsInTier = profile.starsInTier;
    final maxStars = profile.maxStarsInTier;
    final nextTier = PvpRankSystem.getNextTierName(
      profile.rankStars,
      isTop10Challenger: profile.isChallengerTop10,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.20),
            const Color(0xFF0A1426).withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.16),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          RankBadge(
            rankTier: profile.rankTier,
            size: 72,
            showGlow: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'RANK ${profile.rankTier.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (profile.isChallengerTop10 &&
                        profile.serverRank != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1744),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TOP #${profile.serverRank}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (maxStars != null) ...[
                  Row(
                    children: [
                      for (int i = 0; i < maxStars; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            i < starsInTier
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: i < starsInTier
                                ? const Color(0xFFFFD54F)
                                : Colors.white24,
                            size: 18,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        '$starsInTier/$maxStars Sao',
                        style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFD54F),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$starsInTier Sao Tích Lũy',
                        style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Text(
                        '${profile.rankPoints} RP',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Kế tiếp: $nextTier',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, Color color, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: maxDialogHeight),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF142442), Color(0xFF0C1628)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF29D8FF), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF29D8FF).withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Tiêu đề hộp thoại
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Color(0xFF00E5FF),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'HỒ SƠ NGƯỜI CHƠI & BẬC RANK',
                        style: TextStyle(
                          color: Color(0xFF29D8FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2. Khung Bậc Rank hiện tại của User
                _buildRankCard(profile),
                const SizedBox(height: 14),

                // 3. Thông tin Tên nhân vật (Cố định, không chỉnh sửa)
                _buildInfoTile(
                  icon: Icons.person_rounded,
                  iconColor: const Color(0xFF00E5FF),
                  label: 'TÊN NGƯỜI CHƠI',
                  value: profile.playerName,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'Chính chủ',
                      style: TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 4. Thông tin Mã ID người chơi (Cố định, không chỉnh sửa, có nút sao chép)
                _buildInfoTile(
                  icon: Icons.fingerprint_rounded,
                  iconColor: const Color(0xFFFFD54F),
                  label: 'MÃ ID ĐỊNH DANH (MÃ KẾT BẠN)',
                  value: profile.playerCode,
                  trailing: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      AudioService.instance.playSfx(SfxSound.uiClick);
                      Clipboard.setData(ClipboardData(text: profile.playerCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF00E676),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Đã sao chép mã ID: ${profile.playerCode}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: const Color(0xFF142442),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0288D1).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0288D1)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 14, color: Color(0xFF29D8FF)),
                          SizedBox(width: 4),
                          Text(
                            'SAO CHÉP',
                            style: TextStyle(
                              color: Color(0xFF29D8FF),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 5. Thống kê tài sản, Tỉ lệ thắng & Tướng
                Row(
                  children: [
                    _buildStatChip(
                      Icons.monetization_on_rounded,
                      Colors.amberAccent,
                      'Vàng',
                      '${profile.gold}',
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      Icons.stars_rounded,
                      Colors.amber,
                      'Xu',
                      '${profile.xu}',
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      Icons.emoji_events_rounded,
                      const Color(0xFF00E5FF),
                      'Tỉ lệ thắng',
                      profile.winRateDisplay,
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      Icons.shield_rounded,
                      const Color(0xFF00E676),
                      'Tướng mở',
                      '${profile.unlockedHeroIds.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 6. Nút Đóng
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A6E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF29D8FF), width: 1.2),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      AudioService.instance.playSfx(SfxSound.uiClick);
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'ĐÓNG',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.2,
                        color: Color(0xFF29D8FF),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
