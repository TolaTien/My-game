import 'dart:math';
import 'package:flutter/material.dart';
import '../models/database_models.dart';
import '../models/player_profile.dart';
import '../models/pvp_match.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/player_storage.dart';
import 'chat_ai_dialog.dart';
import 'friends_party_dialog.dart';
import 'game_play_screen.dart';
import 'lucky_wheel_dialog.dart';
import 'pvp_arena_screen.dart';
import 'shop_dialog.dart';
import 'widgets/hero_showcase_painter.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin {
  bool _isPvpMode = false;
  PvpGameMode _selectedPvpMode = PvpGameMode.solo1v1;
  late AnimationController _breatheController;
  late Animation<double> _breatheAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();

    // Hiệu ứng thở / nhấp nhô nhẹ nhàng
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _breatheAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );

    // Hiệu ứng viền phát sáng nhấp nháy cho nút BẮT ĐẦU
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Vệt sáng quét ngang (Shimmer gleam) cho nút BẮT ĐẦU
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    // Tải dữ liệu người chơi
    PlayerStorage.loadProfile();

    // Bật Lobby BGM
    AudioService.instance.playBgm(BgmTrack.lobby);
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _openLuckyWheel() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const LuckyWheelDialog(),
    );
  }

  void _openShop() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ShopDialog(),
    );
  }

  void _openLeaderboard(PlayerProfile profile) {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _LeaderboardDialog(playerProfile: profile),
    );
  }

  void _openAssetCodex() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _AssetCodexDialog(),
    );
  }

  void _openFriendsParty() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => FriendsPartyDialog(
        initialMode: _selectedPvpMode,
        onStartPartyMatch: (mode) {
          setState(() {
            _isPvpMode = true;
            _selectedPvpMode = mode;
          });
          _startGame();
        },
      ),
    );
  }

  void _openChatAi() {
    AudioService.instance.playSfx(SfxSound.uiClick);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ChatAiDialog(),
    );
  }

  void _startGame() async {
    AudioService.instance.playSfx(SfxSound.uiClick);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _isPvpMode
            ? PvpArenaScreen(initialMode: _selectedPvpMode)
            : const GamePlayScreen(),
      ),
    );
    if (mounted) {
      AudioService.instance.playBgm(BgmTrack.lobby);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      body: SafeArea(
        child: ValueListenableBuilder<PlayerProfile>(
          valueListenable: PlayerStorage.profileNotifier,
          builder: (context, profile, _) {
            final canSpin = profile.canSpinToday();

            return Stack(
              children: [
                // 1. HÌNH NỀN DARK FANTASY DUNGEON SÂU THẲM
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.2),
                        radius: 1.3,
                        colors: [
                          Color(0xFF1E2433),
                          Color(0xFF121620),
                          Color(0xFF090B10),
                        ],
                      ),
                    ),
                  ),
                ),

                // Hiệu ứng hạt bụi vàng lấp lánh và đuốc hầm ngục ma thuật
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DungeonAmbiencePainter(),
                  ),
                ),

                // 2. KHU VỰC TRUNG TÂM: NHÂN VẬT & BỆ THẦN THÁNH
                Align(
                  alignment: const Alignment(0.0, 0.28),
                  child: _buildCenterStage(profile),
                ),

                // 3. TOP BAR: AVATAR, BẬC RANK, VÀNG & KIM CƯƠNG
                Positioned(
                  top: 10,
                  left: 16,
                  right: 16,
                  child: _buildTopBar(profile),
                ),

                // 4. SIDEBAR TRÁI: VÒNG QUAY MAY MẮN, CỬA HÀNG, BXH
                Positioned(
                  left: 16,
                  top: 76,
                  bottom: 16,
                  child: _buildLeftSidebar(canSpin),
                ),

                // 5. GÓC PHẢI DƯỚI: NÚT BẮT ĐẦU SIÊU TO KHỔNG LỒ ACTION RPG
                Positioned(
                  right: 20,
                  bottom: 16,
                  child: _buildStartButton(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- 1. TOP BAR ---
  Widget _buildTopBar(PlayerProfile profile) {
    return Row(
      children: [
        // Khung Profile + Avatar + Rank
        GestureDetector(
          onTap: () => _openLeaderboard(profile),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF222938).withValues(alpha: 0.9),
                  const Color(0xFF141824).withValues(alpha: 0.95),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: profile.rankColor.withValues(alpha: 0.7),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: profile.rankColor.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                // Khung tròn Avatar
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [profile.rankColor, Colors.deepPurpleAccent],
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: profile.rankColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 10),

                // Tên & Bậc Rank
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.playerName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(profile.rankIcon,
                            size: 14, color: profile.rankColor),
                        const SizedBox(width: 4),
                        Text(
                          '${profile.rankTier.toUpperCase()} • ${profile.rankPoints} RP',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: profile.rankColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 11, color: Colors.white38),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Đồng Xu (1 Xu = 1000 Vàng)
        _buildCurrencyPill(
          icon: Icons.toll_rounded,
          value: profile.xu,
          glowColor: const Color(0xFFFFAB40),
          gradientColors: const [Color(0xFFFFD180), Color(0xFFFF6D00)],
          onTap: _openShop,
        ),
        const SizedBox(width: 8),

        // Hũ Vàng Hoàng Kim
        _buildCurrencyPill(
          icon: Icons.monetization_on_rounded,
          value: profile.gold,
          glowColor: const Color(0xFFFFD700),
          gradientColors: const [Color(0xFFFFEA00), Color(0xFFFF9100)],
          onTap: _openShop,
        ),
        const SizedBox(width: 12),

        // Kim Cương Băng Lam
        _buildCurrencyPill(
          icon: Icons.diamond_rounded,
          value: profile.diamonds,
          glowColor: const Color(0xFF00E5FF),
          gradientColors: const [Color(0xFF18FFFF), Color(0xFF0091EA)],
          onTap: _openShop,
        ),
      ],
    );
  }

  Widget _buildCurrencyPill({
    required IconData icon,
    required int value,
    required Color glowColor,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    final formatted =
        value.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF222938).withValues(alpha: 0.85),
              const Color(0xFF141824).withValues(alpha: 0.95),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: glowColor.withValues(alpha: 0.65),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.22),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (bounds) =>
                  LinearGradient(colors: gradientColors).createShader(bounds),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              formatted,
              style: TextStyle(
                color: glowColor,
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glowColor.withValues(alpha: 0.25),
              ),
              child: Icon(Icons.add, size: 13, color: glowColor),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. BỆ PHÁT SÁNG & NHÂN VẬT TRUNG TÂM ---
  Widget _buildCenterStage(PlayerProfile profile) {
    final heroInfo = _getHeroDisplayInfo(profile.selectedHeroId);

    return AnimatedBuilder(
      animation: _breatheAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // BỤC HÀO QUANG TOẢ SÁNG DƯỚI ĐÁY
            Positioned(
              bottom: -24,
              child: Container(
                width: 280,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.elliptical(280, 60)),
                  gradient: RadialGradient(
                    colors: [
                      heroInfo.themeColor.withValues(alpha: 0.55),
                      heroInfo.themeColor.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: heroInfo.themeColor.withValues(alpha: 0.45),
                      blurRadius: 36,
                      spreadRadius: 8,
                    ),
                  ],
                ),
              ),
            ),

            // NHÂN VẬT & CHI TIẾT
            Transform.translate(
              offset: Offset(0, _breatheAnimation.value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Huy hiệu Trợ thủ hoặc Trang phục hiếm
                  if (profile.selectedCompanionId != null ||
                      profile.selectedSkinId != null) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile.selectedCompanionId != null)
                          _buildMiniBadge(
                            icon: Icons.smart_toy_rounded,
                            label: 'TRỢ THỦ AI',
                            color: Colors.cyanAccent,
                          ),
                        if (profile.selectedSkinId != null) ...[
                          const SizedBox(width: 8),
                          _buildMiniBadge(
                            icon: Icons.auto_awesome_rounded,
                            label: 'SKIN HUYỀN THOẠI',
                            color: const Color(0xFFFFD700),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],

                  // SHOWCASE NHÂN VẬT VỚI ĐỒ HỌA MỚI TOÀN DIỆN
                  HeroShowcaseWidget(
                    heroId: profile.selectedHeroId,
                    themeColor: heroInfo.themeColor,
                  ),

                  const SizedBox(height: 8),

                  // Tên tướng + Danh hiệu
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF222836).withValues(alpha: 0.95),
                          const Color(0xFF141722).withValues(alpha: 0.95),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: heroInfo.themeColor.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: heroInfo.themeColor.withValues(alpha: 0.25),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          heroInfo.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                blurRadius: 10,
                                color: heroInfo.themeColor,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${heroInfo.title} • LV.${profile.getHeroLevel()}/100',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: heroInfo.themeColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. SIDEBAR TRÁI ---
  Widget _buildLeftSidebar(bool canSpin) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. VÒNG QUAY MAY MẮN
          _buildSidebarButton(
            icon: Icons.casino_rounded,
            label: 'VÒNG QUAY',
            badgeText: canSpin ? 'QUAY NGAY' : null,
            hasBadge: canSpin,
            accentColor: const Color(0xFFFFB300),
            onTap: _openLuckyWheel,
          ),
          const SizedBox(height: 8),

          // 2. CỬA HÀNG VẬT PHẨM
          _buildSidebarButton(
            icon: Icons.shopping_bag_rounded,
            label: 'CỬA HÀNG',
            accentColor: const Color(0xFF00E5FF),
            onTap: _openShop,
          ),
          const SizedBox(height: 8),

          // 3. BẠN BÈ & TỔ ĐỘI PVP (1v1 / 2v2 / 4v4)
          _buildSidebarButton(
            icon: Icons.groups_rounded,
            label: 'TỔ ĐỘI',
            badgeText: 'TEAM',
            hasBadge: true,
            accentColor: const Color(0xFF00E676),
            onTap: _openFriendsParty,
          ),
          const SizedBox(height: 8),

          // 4. TRỢ LÝ CHAT AI (FAQ & NLP)
          _buildSidebarButton(
            icon: Icons.smart_toy_rounded,
            label: 'CHAT AI',
            accentColor: const Color(0xFF40C4FF),
            onTap: _openChatAi,
          ),
          const SizedBox(height: 8),

          // 5. BẢNG XẾP HẠNG RANK
          _buildSidebarButton(
            icon: Icons.leaderboard_rounded,
            label: 'RANKING',
            accentColor: const Color(0xFFFF5252),
            onTap: () => _openLeaderboard(PlayerStorage.currentProfile),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarButton({
    required IconData icon,
    required String label,
    required Color accentColor,
    required VoidCallback onTap,
    String? badgeText,
    bool hasBadge = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 76,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF252D3D).withValues(alpha: 0.9),
                  const Color(0xFF151924).withValues(alpha: 0.98),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.65),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accentColor, size: 28),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Huy hiệu nhắc nhở nổi bật
        if (hasBadge)
          Positioned(
            top: -5,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF1744), Color(0xFFD50000)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.redAccent,
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                badgeText ?? '!',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- 4. GÓC PHẢI DƯỚI: NÚT BẮT ĐẦU SIÊU TO KHỔNG LỒ (ACTION RPG STYLE) ---
  Widget _buildStartButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Chọn nhanh thể thức ghép trận PvP: 1v1 | 2v2 | 4v4
        if (_isPvpMode)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF141824).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: PvpGameMode.values.map((mode) {
                final selected = _selectedPvpMode == mode;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    key: Key('lobby_pvp_mode_${mode.shortLabel.toLowerCase()}'),
                    borderRadius: BorderRadius.circular(7),
                    onTap: () {
                      AudioService.instance.playSfx(SfxSound.uiClick);
                      setState(() {
                        _selectedPvpMode = mode;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFF8F00)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        mode.title.toUpperCase(),
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

        // Chuyển đổi chế độ chơi (PVE / PVP)
        GestureDetector(
          onTap: () {
            AudioService.instance.playSfx(SfxSound.uiClick);
            setState(() {
              _isPvpMode = !_isPvpMode;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF222838).withValues(alpha: 0.95),
                  const Color(0xFF141722).withValues(alpha: 0.98),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isPvpMode ? const Color(0xFFFF1744) : const Color(0xFFFFD54F),
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isPvpMode ? Colors.redAccent : Colors.amberAccent)
                      .withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isPvpMode
                      ? Icons.military_tech_rounded
                      : Icons.sports_kabaddi_rounded,
                  size: 16,
                  color:
                      _isPvpMode ? const Color(0xFFFF5252) : const Color(0xFFFFD54F),
                ),
                const SizedBox(width: 6),
                Text(
                  _isPvpMode
                      ? 'CHẾ ĐỘ: ĐẤU TRƯỜNG PVP (RANK ${_selectedPvpMode.shortLabel})'
                      : 'CHẾ ĐỘ: VƯỢT ẢI HẦM NGỤC (PVE)',
                  style: TextStyle(
                    color: _isPvpMode
                        ? const Color(0xFFFF5252)
                        : const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ĐỔI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Nút BẮT ĐẦU với hiệu ứng viền phát sáng & Shimmer Gleam
        AnimatedBuilder(
          animation: Listenable.merge([_pulseAnimation, _shimmerController]),
          builder: (context, child) {
            final btnColors = _isPvpMode
                ? const [Color(0xFFFF1744), Color(0xFFB71C1C)]
                : const [Color(0xFFFFB300), Color(0xFFE65100)];

            return Container(
              width: 230,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: btnColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: (_isPvpMode ? const Color(0xFFFF8A80) : const Color(0xFFFFD54F))
                      .withValues(alpha: _pulseAnimation.value),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isPvpMode ? const Color(0xFFFF1744) : const Color(0xFFFF8F00))
                        .withValues(alpha: 0.5 * _pulseAnimation.value),
                    blurRadius: 22 * _pulseAnimation.value,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Vệt sáng lướt qua (Shimmer gleam)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Transform.translate(
                        offset: Offset(
                          -230 + _shimmerController.value * 460,
                          0,
                        ),
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.35),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Nút bấm chính
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _startGame,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isPvpMode
                              ? Icons.military_tech_rounded
                              : Icons.play_arrow_rounded,
                          size: 38,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isPvpMode ? 'TÌM TRẬN RANK' : 'BẮT ĐẦU',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black87,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  _HeroDisplayInfo _getHeroDisplayInfo(String id) {
    switch (id) {
      case 'kaelen':
        return const _HeroDisplayInfo(
          name: 'Kaelen Lôi Quang',
          title: 'Kiếm Khách Thunderblade (Asset 4)',
          themeColor: Color(0xFF00E5FF),
          icon: Icons.bolt_rounded,
        );
      case 'nova_blade':
        return const _HeroDisplayInfo(
          name: 'Nova Blade (NOVA-07)',
          title: 'Chiến Binh Neon Song Kiếm (Asset 1 & 2)',
          themeColor: Color(0xFF18FFFF),
          icon: Icons.flash_on_rounded,
        );
      case 'shadow_01':
        return const _HeroDisplayInfo(
          name: 'SHADOW-01',
          title: 'Sát Thủ Hư Không (Asset 2)',
          themeColor: Color(0xFFE040FB),
          icon: Icons.flare_rounded,
        );
      case 'ember_02':
        return const _HeroDisplayInfo(
          name: 'EMBER-02',
          title: 'Phù Thủy Hỏa Cầu (Asset 2)',
          themeColor: Color(0xFFFF6D00),
          icon: Icons.local_fire_department_rounded,
        );
      case 'valeria':
        return const _HeroDisplayInfo(
          name: 'Pháp Sư Valeria',
          title: 'Pháp Sư Băng Hỏa Nguyên Tố (Asset 3)',
          themeColor: Color(0xFF40C4FF),
          icon: Icons.ac_unit_rounded,
        );
      case 'garrick':
        return const _HeroDisplayInfo(
          name: 'Chiến Binh Garrick',
          title: 'Stone Guardian Cổ Đại (Asset 3)',
          themeColor: Color(0xFFFFD700),
          icon: Icons.fort_rounded,
        );
      case 'ranger':
        return const _HeroDisplayInfo(
          name: 'Xạ Thủ Ranger',
          title: 'Cung Thủ Ánh Sáng Tầm Xa',
          themeColor: Color(0xFF00E676),
          icon: Icons.gps_fixed_rounded,
        );
      case 'tanker':
        return const _HeroDisplayInfo(
          name: 'Hiệp Sĩ Tanker',
          title: 'Hộ Vệ Hoàng Gia Bất Diệt',
          themeColor: Color(0xFF00B0FF),
          icon: Icons.security_rounded,
        );
      case 'ninja':
        return const _HeroDisplayInfo(
          name: 'Ninja Sát Thủ',
          title: 'Ám Sát Bóng Đêm Chí Mạng',
          themeColor: Color(0xFFAB47BC),
          icon: Icons.flash_on_rounded,
        );
      case 'george':
      default:
        return const _HeroDisplayInfo(
          name: 'George',
          title: 'Chiến Binh Búa Sấm Sét',
          themeColor: Color(0xFFFF9800),
          icon: Icons.shield_sharp,
        );
    }
  }
}

class _HeroDisplayInfo {
  final String name;
  final String title;
  final Color themeColor;
  final IconData icon;

  const _HeroDisplayInfo({
    required this.name,
    required this.title,
    required this.themeColor,
    required this.icon,
  });
}

/// Bảng Xếp Hạng Rank Modal
class _LeaderboardDialog extends StatelessWidget {
  final PlayerProfile playerProfile;

  const _LeaderboardDialog({required this.playerProfile});

  static Color _getRankColor(String tier) {
    switch (tier) {
      case 'Thách Đấu':
        return const Color(0xFFFF1744);
      case 'Kim Cương':
        return const Color(0xFF00E5FF);
      case 'Bạch Kim':
        return const Color(0xFF00E676);
      case 'Vàng':
        return const Color(0xFFFFD700);
      case 'Bạc':
        return const Color(0xFFE0E0E0);
      default:
        return const Color(0xFFCD7F32);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 380),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF222838), Color(0xFF121622)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.amberAccent.withValues(alpha: 0.7),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.emoji_events_rounded,
                        color: Colors.amberAccent, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'BẢNG XẾP HẠNG CHIẾN BINH (RANK)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.amberAccent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Danh sách Top người chơi từ DatabaseService (Live stream)
            Expanded(
              child: StreamBuilder<List<LeaderboardEntry>>(
                stream: DatabaseService.instance.streamTopLeaderboard(limit: 20),
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.amberAccent),
                    );
                  }

                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final rank = entry.rankNumber;
                      final name = entry.name;
                      final tier = entry.rankTier;
                      final rp = entry.rankPoints;
                      final color = _getRankColor(tier);
                      final isTop3 = rank <= 3;
                      final isLocal = entry.isLocalPlayer;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isLocal
                              ? Colors.amberAccent.withValues(alpha: 0.2)
                              : (isTop3
                                  ? color.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isLocal
                                ? Colors.amberAccent
                                : (isTop3
                                    ? color.withValues(alpha: 0.6)
                                    : Colors.white12),
                            width: isLocal ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: isLocal
                                      ? Colors.amberAccent
                                      : (isTop3 ? color : Colors.white70),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isLocal
                                          ? Colors.amberAccent
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (isLocal) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent
                                            .withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'BẠN',
                                        style: TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              tier,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              '$rp RP',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Hàng hiển thị vị trí của người chơi hiện tại
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: playerProfile.rankColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: playerProfile.rankColor,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'BẠN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      playerProfile.playerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    playerProfile.rankTier,
                    style: TextStyle(
                      color: playerProfile.rankColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${playerProfile.rankPoints} RP',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vẽ không gian hầm ngục hoàng gia huyền ảo với tàn tro và bụi vàng lơ lửng
class _DungeonAmbiencePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Ánh đuốc hầm ngục ấm áp tỏa ra từ hai góc trên
    final torchGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFB300).withValues(alpha: 0.12),
          const Color(0xFFFF6D00).withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: const Offset(40, 40), radius: 180));
    canvas.drawCircle(const Offset(40, 40), 180, torchGlow);

    final torchRight = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(size.width - 40, 40), radius: 180));
    canvas.drawCircle(Offset(size.width - 40, 40), 180, torchRight);

    // 2. Các hạt bụi vàng lấp lánh cố định vị trí giả lập không gian RPG
    final rand = Random(42);
    final emberPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    for (int i = 0; i < 28; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      final radius = 1.0 + rand.nextDouble() * 2.5;
      final alpha = 0.2 + rand.nextDouble() * 0.45;
      emberPaint.color = const Color(0xFFFFD54F).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, emberPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DungeonAmbiencePainter oldDelegate) => false;
}

/// Hộp thoại Thư Viện Concept Art & Thiết Kế Nhân Vật (Assets Codex)
class _AssetCodexDialog extends StatefulWidget {
  const _AssetCodexDialog();

  @override
  State<_AssetCodexDialog> createState() => _AssetCodexDialogState();
}

class _AssetCodexDialogState extends State<_AssetCodexDialog> {
  int _selectedSheet = 0;

  static const _sheets = [
    (
      title: 'Kaelen & Aegis-X9',
      subtitle: 'Kiếm Khách Lôi Quang & Tinh Linh Lôi Từ',
      assetPath: 'assets/images/asset_1.png',
      desc:
          'Concept Art chuẩn Golden-Cyber Fantasy: Kaelen dùng Song Kiếm Hoàng Kim & Lôi Quang (#00E5FF), đi kèm Trợ Thủ AI Aegis-X9 có kỹ năng Trường Trọng Lực Hoàng Kim.',
    ),
    (
      title: 'Sprite Sheet 4 Trạng Thái',
      subtitle: 'Idle • Run • Attack • Hit & HUD Mobile',
      assetPath: 'assets/images/asset_2.png',
      desc:
          'Bảng phân tách Layer bộ phận (Cape, Body, Dual Swords, Greaves), hoạt ảnh lướt Lôi Ảnh Trảm và cụm nút kỹ năng hình cánh cung 90°.',
    ),
    (
      title: 'Biệt Đội Liên Minh (2v2 / 4v4)',
      subtitle: 'Kaelen • Valeria • Garrick',
      assetPath: 'assets/images/asset_3.png',
      desc:
          'Bộ 3 chiến binh chủ lực cho chế độ Song Đấu 2v2 và Quân Đoàn 4v4: Kiếm Khách Kaelen, Xạ Thủ Nỏ Thần Valeria và Pháo Đài Khiên Tháp Garrick.',
    ),
    (
      title: 'Phế Tích Thần Điện Hoàng Kim',
      subtitle: 'Bản Đồ Sunken Golden Sanctum & Vòng Ma Trận',
      assetPath: 'assets/images/asset_4.png',
      desc:
          'Gạch đá cổ đại rạn nứt nạm mạch quặng Vàng ròng (#D4AF37), Vòng Ma Trận Bát Giác trung tâm và 4 Cổng Không Gian Hắc Ám.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sheet = _sheets[_selectedSheet];
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 420),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2134), Color(0xFF0E1320)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFD700), width: 2),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: Color(0xFFFFD700), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'THƯ VIỆN CONCEPT ART & HƯỚNG DẪN NHÂN VẬT MỚI',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final current = PlayerStorage.currentProfile;
                    final unlockedHeroes = {...current.unlockedHeroIds, 'kaelen', 'valeria', 'garrick'}.toList();
                    final unlockedComps = {...current.unlockedCompanionIds, 'aegis_x9'}.toList();
                    await PlayerStorage.saveProfile(
                      current.copyWith(
                        unlockedHeroIds: unlockedHeroes,
                        selectedHeroId: 'kaelen',
                        unlockedCompanionIds: unlockedComps,
                        selectedCompanionId: 'aegis_x9',
                      ),
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text(
                    'TRẢI NGHIỆM KAELEN + AEGIS-X9',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Tabs chọn 4 tấm Concept Art
            Row(
              children: List.generate(_sheets.length, (idx) {
                final active = idx == _selectedSheet;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => setState(() => _selectedSheet = idx),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: active ? const Color(0xFFFFD700) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          _sheets[idx].title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? const Color(0xFFFFD700) : Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: Colors.black54,
                        child: Image.asset(
                          sheet.assetPath,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.image_not_supported, color: Colors.white38, size: 42),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sheet.subtitle,
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Text(
                                sheet.desc,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
