import 'package:flutter/material.dart';
import '../../models/pvp_match.dart';

/// Widget hiển thị huy hiệu Rank bằng bộ asset PNG riêng cho từng bậc:
/// Đồng -> Bạc -> Vàng -> Bạch Kim -> Kim Cương -> Huyền Thoại -> Thách Đấu.
class RankBadge extends StatelessWidget {
  final String rankTier;
  final double size;
  final bool showGlow;

  const RankBadge({
    super.key,
    required this.rankTier,
    this.size = 32,
    this.showGlow = false,
  });

  static Color colorForTier(String tier) {
    switch (tier) {
      case 'Thách Đấu':
        return const Color(0xFFFF1744);
      case 'Huyền Thoại':
        return const Color(0xFFE040FB);
      case 'Kim Cương':
        return const Color(0xFF00E5FF);
      case 'Bạch Kim':
        return const Color(0xFF00E676);
      case 'Vàng':
        return const Color(0xFFFFD700);
      case 'Bạc':
        return const Color(0xFFCFD8DC);
      case 'Đồng':
      default:
        return const Color(0xFFCD7F32);
    }
  }

  static IconData iconForTier(String tier) {
    switch (tier) {
      case 'Thách Đấu':
        return Icons.local_fire_department_rounded;
      case 'Huyền Thoại':
        return Icons.auto_awesome_rounded;
      case 'Kim Cương':
        return Icons.diamond_rounded;
      case 'Bạch Kim':
        return Icons.shield_rounded;
      case 'Vàng':
        return Icons.military_tech_rounded;
      case 'Bạc':
        return Icons.star_rounded;
      case 'Đồng':
      default:
        return Icons.shield_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = colorForTier(rankTier);
    final assetPath = PvpRankSystem.getRankAssetPath(rankTier);

    final badge = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tierColor.withValues(alpha: 0.2),
            border: Border.all(color: tierColor, width: 1.5),
          ),
          child: Icon(
            iconForTier(rankTier),
            color: tierColor,
            size: size * 0.6,
          ),
        );
      },
    );

    if (!showGlow) return badge;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.45),
            blurRadius: size * 0.35,
            spreadRadius: 1,
          ),
        ],
      ),
      child: badge,
    );
  }
}
