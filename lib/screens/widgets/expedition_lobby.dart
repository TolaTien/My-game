import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/player_profile.dart';
import '../../core/hero_skin_style.dart';
import 'hero_showcase_painter.dart';

/// A single scene coordinate system keeps the hero aligned with the painted
/// platform on both wide desktop windows and landscape phones.
class ExpeditionLobby extends StatelessWidget {
  final PlayerProfile profile;
  final String heroName;
  final String heroTitle;
  final Color heroColor;
  final Animation<double> ambience;
  final Widget startAction;
  final VoidCallback onShop, onHeroes, onSkins, onCompanions;
  final VoidCallback onWheel, onParty, onChat, onLeaderboard, onCodex;

  const ExpeditionLobby({
    super.key,
    required this.profile,
    required this.heroName,
    required this.heroTitle,
    required this.heroColor,
    required this.ambience,
    required this.startAction,
    required this.onShop,
    required this.onHeroes,
    required this.onSkins,
    required this.onCompanions,
    required this.onWheel,
    required this.onParty,
    required this.onChat,
    required this.onLeaderboard,
    required this.onCodex,
  });

  static const gold = Color(0xFFE9BE69);

  static BoxDecoration panel({bool highlighted = false}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: highlighted
          ? const [Color(0xFF69472D), Color(0xFF302019)]
          : const [Color(0xF03B2D26), Color(0xF019181D)],
    ),
    border: Border.all(color: gold.withValues(alpha: .75), width: 1.5),
    borderRadius: BorderRadius.circular(8),
    boxShadow: const [
      BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
    ],
  );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback action, {
    bool badge = false,
  }) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: panel(),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: action,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: gold, size: 24),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFEED2),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge)
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFFFFD15C),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _currency(IconData icon, int value, Color color) {
    final amount = value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: panel(),
        child: InkWell(
          onTap: onShop,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 25),
                const SizedBox(width: 9),
                Text(
                  amount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.add_box_rounded, color: gold, size: 21),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, bounds) {
        // Expand the scene on ultrawide screens rather than stretching the art.
        final aspect = bounds.maxWidth / bounds.maxHeight;
        final sceneWidth = math.max(1440.0, 810 * aspect);
        final sceneHeight = sceneWidth / aspect;
        final skin = HeroSkinStyle.resolve(
          profile.selectedHeroId,
          profile.selectedSkinId,
        );
        return SizedBox.expand(
          child: ColoredBox(
            color: const Color(0xFF0C111E),
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: sceneWidth,
                  height: sceneHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/ui/expedition_camp.png',
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x77070A13),
                                  Colors.transparent,
                                  Colors.transparent,
                                  Color(0xAA090C14),
                                ],
                                stops: [0, .22, .66, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(painter: _CampEmbers(ambience)),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        top: 22,
                        width: 300,
                        height: 72,
                        child: Material(
                          color: Colors.transparent,
                          child: Ink(
                            decoration: panel(),
                            child: InkWell(
                              onTap: onLeaderboard,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: panel(highlighted: true),
                                      child: Icon(
                                        profile.rankIcon,
                                        color: gold,
                                        size: 30,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            profile.playerName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            'LV.${profile.getHeroLevel()}   •   ${profile.rankTier.toUpperCase()}   •   ${profile.rankPoints} RP',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: gold,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 23,
                        left: sceneWidth / 2 - 155,
                        width: 310,
                        child: const Column(
                          children: [
                            Icon(
                              Icons.landscape_rounded,
                              color: gold,
                              size: 30,
                            ),
                            Text(
                              'GOLD RUSH',
                              style: TextStyle(
                                color: Color(0xFFFFDA83),
                                fontSize: 34,
                                letterSpacing: 5,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'TRẠI THÁM HIỂM',
                              style: TextStyle(
                                color: Color(0xFFE3CFAF),
                                fontSize: 10,
                                letterSpacing: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 24,
                        top: 28,
                        child: Row(
                          children: [
                            _currency(Icons.toll_rounded, profile.xu, gold),
                            const SizedBox(width: 8),
                            _currency(
                              Icons.monetization_on,
                              profile.gold,
                              const Color(0xFFFFCF4D),
                            ),
                            const SizedBox(width: 8),
                            _currency(
                              Icons.diamond_rounded,
                              profile.diamonds,
                              const Color(0xFF7CE5F2),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 24,
                        top: 146,
                        width: 104,
                        bottom: 154,
                        child: Column(
                          children: [
                            Expanded(
                              child: _button(
                                'VÒNG QUAY',
                                Icons.casino_rounded,
                                onWheel,
                                badge: profile.canSpinToday(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _button(
                                'CỬA HÀNG',
                                Icons.storefront_rounded,
                                onShop,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _button(
                                'TỔ ĐỘI',
                                Icons.groups_rounded,
                                onParty,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: _button(
                                'XẾP HẠNG',
                                Icons.emoji_events_rounded,
                                onLeaderboard,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Hero remains a live widget using the player's selected hero.
                      Positioned(
                        left: sceneWidth / 2 - 210,
                        top: 190,
                        width: 420,
                        height: 382,
                        child: RepaintBoundary(
                          child: FittedBox(
                            child: HeroShowcaseWidget(
                              heroId: profile.selectedHeroId,
                              themeColor: skin?.color ?? heroColor,
                              skinId: profile.selectedSkinId,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: sceneWidth / 2 - 215,
                        top: 582,
                        width: 430,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: panel(),
                          child: Column(
                            children: [
                              Text(
                                (skin?.name ?? heroName).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFFFE1A0),
                                  fontSize: 25,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$heroTitle • LV.${profile.getHeroLevel()}/100',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD7C5AE),
                                  fontSize: 12,
                                ),
                              ),
                              if (profile.selectedCompanionId != null)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    '✦ ĐÃ TRANG BỊ TRỢ THỦ',
                                    style: TextStyle(
                                      color: Color(0xFF97DDE1),
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: sceneWidth / 2 - 270,
                        bottom: 34,
                        width: 540,
                        height: 68,
                        child: Row(
                          children: [
                            Expanded(
                              child: _button(
                                'TƯỚNG',
                                Icons.shield_rounded,
                                onHeroes,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _button(
                                'TRỢ THỦ',
                                Icons.smart_toy_rounded,
                                onCompanions,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _button(
                                'SKIN',
                                Icons.checkroom_rounded,
                                onSkins,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(right: 26, bottom: 34, child: startAction),
                      Positioned(
                        left: 24,
                        bottom: 34,
                        width: 230,
                        height: 54,
                        child: Row(
                          children: [
                            Expanded(
                              child: _button(
                                'CHAT AI',
                                Icons.forum_outlined,
                                onChat,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _button(
                                'THƯ VIỆN',
                                Icons.menu_book_rounded,
                                onCodex,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CampEmbers extends CustomPainter {
  final Animation<double> animation;
  _CampEmbers(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final paint = Paint();
    for (var i = 0; i < 32; i++) {
      final x =
          ((i * .137 + math.sin(t * math.pi * 2 + i) * .009) % 1) * size.width;
      final y = (1 - (i * .073 + t) % 1) * size.height;
      paint.color = const Color(
        0xFFFFD47C,
      ).withValues(alpha: .15 + .35 * math.pow(math.sin(i + t * math.pi), 2));
      canvas.drawCircle(Offset(x, y), i % 3 == 0 ? 2 : 1, paint);
    }
    for (final point in [
      Offset(size.width * .19, size.height * .55),
      Offset(size.width * .86, size.height * .68),
    ]) {
      final radius = 55 + 7 * math.sin(t * math.pi * 8);
      paint.shader = RadialGradient(
        colors: [
          const Color(0xFFFF9B37).withValues(alpha: .12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: point, radius: radius));
      canvas.drawCircle(point, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CampEmbers oldDelegate) =>
      oldDelegate.animation != animation;
}
