import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/constants.dart';
import '../../core/game_keyboard_controller.dart';
import '../../screens/settings_dialog.dart';
import '../combat/hero_skill_system.dart';
import '../big_war_game.dart';
import 'boss_bar_overlay.dart';
import 'virtual_joystick.dart';

class GameHudOverlay extends StatefulWidget {
  final BigWarGame game;
  final GameKeyboardController? keyboardController;

  const GameHudOverlay({
    super.key,
    required this.game,
    this.keyboardController,
  });

  @override
  State<GameHudOverlay> createState() => _GameHudOverlayState();
}

class _GameHudOverlayState extends State<GameHudOverlay>
    with SingleTickerProviderStateMixin {
  // Mặc định luôn hiện nút cảm ứng; trên Desktop/Web có thể bật/tắt để quan sát toàn màn hình
  bool _showTouchControls = true;
  bool _isRebuildScheduled = false;

  late final AnimationController _bannerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  );
  late final Animation<double> _bannerOpacityAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
  ]).animate(_bannerController);

  void _safeSetState([VoidCallback? fn]) {
    if (!mounted) return;
    fn?.call();
    if (_isRebuildScheduled) return;

    final isBuilding = WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    final isPersistent = WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks;

    if (isBuilding || isPersistent) {
      _isRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isRebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _bannerController.forward();
    // Đăng ký lắng nghe thay đổi chỉ số của player
    widget.game.onPlayerStatsChanged = () {
      _safeSetState();
    };
    // Đăng ký lắng nghe thay đổi bản đồ khi sang tầng mới -> kích hoạt lại banner chào mừng map mới
    widget.game.onMapChanged = () {
      _safeSetState(() {
        _bannerController.forward(from: 0.0);
      });
    };
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.game.player;
    final isDesktopOrWeb = GamePlatformHelper.isDesktopOrWeb;
    final s1 = HeroSkillSystem.getSkillMeta(player.heroId, 1);
    final s2 = HeroSkillSystem.getSkillMeta(player.heroId, 2);
    final s3 = HeroSkillSystem.getSkillMeta(player.heroId, 3);

    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final safeW = constraints.maxWidth;
          final safeH = constraints.maxHeight;
          final isCompact = safeW < 760 || safeH < 410;
          final canInlineBossBar = safeW >= 840;
          final controlScale =
              min(safeW / 820.0, safeH / 410.0).clamp(0.74, 1.0);

          final avatarSize = isCompact ? 42.0 : 52.0;
          final statBarWidth = isCompact ? 104.0 : 138.0;
          final topEdge = isCompact ? 4.0 : 8.0;
          final sideEdge = isCompact ? 8.0 : 14.0;
          final bottomEdge = isCompact ? 8.0 : 18.0;
          final bossBarMaxWidth = canInlineBossBar
              ? (safeW * 0.28).clamp(210.0, 260.0)
              : (safeW * 0.34).clamp(175.0, 230.0);

          final map = widget.game.currentMapConfig;
          final isIceTheme =
              map.theme == 'ice_arena' || map.theme == 'frost_island';
          final mapAccentColor =
              isIceTheme ? const Color(0xFF00E5FF) : const Color(0xFFFFD700);

          return Stack(
            children: [
              // Banner thông báo chiến trường ngẫu nhiên khi vào trận
              Positioned(
                top: isCompact ? 48 : 56,
                left: sideEdge,
                right: sideEdge,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _bannerController,
                      builder: (context, child) {
                        if (_bannerController.isCompleted) {
                          return const SizedBox.shrink();
                        }
                        return Opacity(
                          opacity: _bannerOpacityAnim.value,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (1.0 - _bannerOpacityAnim.value) * -14,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 14 : 18,
                                vertical: isCompact ? 5 : 7,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isIceTheme
                                      ? [
                                          const Color(0xFF002244)
                                              .withValues(alpha: 0.92),
                                          const Color(0xFF005588)
                                              .withValues(alpha: 0.92),
                                        ]
                                      : [
                                          const Color(0xFF2C1E0A)
                                              .withValues(alpha: 0.92),
                                          const Color(0xFF4A3410)
                                              .withValues(alpha: 0.92),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: mapAccentColor,
                                  width: 1.4,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        mapAccentColor.withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isIceTheme
                                        ? Icons.ac_unit_rounded
                                        : Icons.account_balance_rounded,
                                    color: mapAccentColor,
                                    size: isCompact ? 16 : 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'CHIẾN TRƯỜNG: ${map.name.toUpperCase()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isIceTheme
                                            ? const Color(0xFFE0F7FA)
                                            : const Color(0xFFFFF8E1),
                                        fontWeight: FontWeight.w900,
                                        fontSize: isCompact ? 11 : 12.5,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // 1 & 2. TOP ROW: Player Stats (Left) | Boss Bar (Center on wide screens) | Info & Settings (Right)
              Positioned(
                top: topEdge,
                left: sideEdge,
                right: sideEdge,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TOP LEFT: Chỉ số HP, Ki, EXP, Giáp Hoàng Kim và Level
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                            ),
                            borderRadius:
                                BorderRadius.circular(isCompact ? 10 : 12),
                            border: Border.all(
                              color: const Color(0xFFFFD700),
                              width: 1.8,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 5),
                            ],
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                player.heroId == 'ranger' ||
                                        player.heroId == 'valeria'
                                    ? Icons.gps_fixed_rounded
                                    : player.heroId == 'ninja'
                                        ? Icons.flash_on_rounded
                                        : Icons.shield,
                                color: Colors.orangeAccent,
                                size: isCompact ? 22 : 28,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD700),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Lv.${player.level}',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: isCompact ? 8.5 : 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: isCompact ? 6 : 9),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatBar(
                              label: 'HP',
                              current: player.currentHp,
                              max: player.maxHp,
                              color: GameColors.hpBar,
                              barWidth: statBarWidth,
                              compact: isCompact,
                            ),
                            SizedBox(height: isCompact ? 3 : 4),
                            _buildStatBar(
                              label: 'KI',
                              current: player.currentKi,
                              max: player.maxKi,
                              color: GameColors.kiBar,
                              barWidth: statBarWidth,
                              compact: isCompact,
                            ),
                            SizedBox(height: isCompact ? 3 : 4),
                            _buildExpBar(
                              current: player.currentExp,
                              max: player.expToNextLevel,
                              barWidth: statBarWidth,
                              compact: isCompact,
                            ),
                            if (player.shieldHp > 0) ...[
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: const Color(0xFFFFD700),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '🛡 KHIÊN +${player.shieldHp.toInt()}',
                                  style: TextStyle(
                                    color: const Color(0xFFFFD700),
                                    fontSize: isCompact ? 7.5 : 8.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),

                    // TOP CENTER: Boss Bar đặt inline trên màn hình rộng (>=840dp), không bao giờ đè lên nút 2 bên
                    Expanded(
                      child: canInlineBossBar
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: BossBarOverlay(
                                game: widget.game,
                                maxWidth: bossBarMaxWidth,
                                compact: false,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // TOP RIGHT: Bản đồ (ẩn tên dài trên điện thoại nhỏ), Tầng, Xu, PC toggle & Settings
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (safeW >= 680)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 7 : 9,
                              vertical: isCompact ? 4 : 5,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2838),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: mapAccentColor,
                                width: 1.1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isIceTheme
                                      ? Icons.ac_unit_rounded
                                      : Icons.account_balance_rounded,
                                  color: mapAccentColor,
                                  size: isCompact ? 12 : 14,
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: isCompact ? 72 : 110,
                                  ),
                                  child: Text(
                                    map.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isIceTheme
                                          ? const Color(0xFF80DEEA)
                                          : const Color(0xFFFFE082),
                                      fontWeight: FontWeight.w800,
                                      fontSize: isCompact ? 9.5 : 10.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 7 : 9,
                            vertical: isCompact ? 4 : 5,
                          ),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2838),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.cyanAccent.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.stairs,
                                color: Colors.cyanAccent,
                                size: isCompact ? 13 : 15,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'TẦNG ${widget.game.currentFloor}',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: isCompact ? 10 : 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 8 : 10,
                            vertical: isCompact ? 4 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.orangeAccent.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.currency_exchange_rounded,
                                color: Colors.orangeAccent,
                                size: isCompact ? 14 : 17,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${player.coinsCollected} Xu',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isCompact ? 10.5 : 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isDesktopOrWeb) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            key: const Key('toggle_touch_controls_button'),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: BoxConstraints(
                              minWidth: isCompact ? 34 : 40,
                              minHeight: isCompact ? 34 : 40,
                            ),
                            icon: Icon(
                              _showTouchControls
                                  ? Icons.gamepad
                                  : Icons.keyboard,
                              color: Colors.amberAccent,
                              size: isCompact ? 22 : 26,
                            ),
                            tooltip: _showTouchControls
                                ? 'Chế độ phím PC (Ẩn nút ảo trên màn hình)'
                                : 'Hiện nút cảm ứng trên màn hình',
                            onPressed: () {
                              _safeSetState(() {
                                _showTouchControls = !_showTouchControls;
                              });
                            },
                          ),
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: BoxConstraints(
                            minWidth: isCompact ? 34 : 40,
                            minHeight: isCompact ? 34 : 40,
                          ),
                          icon: Icon(
                            Icons.settings_rounded,
                            color: const Color(0xFF00E5FF),
                            size: isCompact ? 23 : 27,
                          ),
                          tooltip: 'Cài đặt âm lượng & trò chơi',
                          onPressed: () {
                            SettingsDialog.show(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2.5 BOSS HEALTH BAR TRÊN ĐIỆN THOẠI (<840dp): Đặt gọn phía dưới Top Bar, không che nút nào
              if (!canInlineBossBar)
                Positioned(
                  top: topEdge + (isCompact ? 46 : 54),
                  left: sideEdge,
                  right: sideEdge,
                  child: BossBarOverlay(
                    game: widget.game,
                    maxWidth: bossBarMaxWidth,
                    compact: true,
                  ),
                ),

              // 3. BOTTOM LEFT: Virtual Joystick điều hướng (scale theo màn hình điện thoại)
              if (_showTouchControls || GamePlatformHelper.isMobile)
                Positioned(
                  bottom: bottomEdge,
                  left: sideEdge + (isCompact ? 4 : 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isDesktopOrWeb)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.amberAccent.withValues(alpha: 0.7),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'W A S D',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      VirtualJoystick(
                        baseRadius: 58.0 * controlScale,
                        knobRadius: 24.0 * controlScale,
                        onDirectionChanged: (offset) {
                          if (offset == Offset.zero &&
                              widget.keyboardController != null &&
                              widget.keyboardController!.hasKeyboardMovement) {
                            widget.game.setPlayerMoveDirection(
                              widget.keyboardController!.currentDirection,
                            );
                          } else {
                            widget.game.setPlayerMoveDirection(
                              Vector2(offset.dx, offset.dy),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),

              // 4. BOTTOM RIGHT: Cụm phím hành động hình cánh cung (scale theo màn hình iOS/Android)
              if (_showTouchControls || GamePlatformHelper.isMobile)
                Positioned(
                  bottom: bottomEdge,
                  right: sideEdge + (isCompact ? 4 : 10),
                  child: SizedBox(
                    width: 210 * controlScale,
                    height: 210 * controlScale,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        // Nút Đánh Thường (To nhất, góc dưới cùng bên phải)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: _ActionButton(
                            size: 74 * controlScale,
                            icon: Icons.flash_on,
                            label: 'ATK',
                            hotkey: isDesktopOrWeb ? 'SPACE' : null,
                            color: const Color(0xFFE53935),
                            onTap: () => widget.game.onBasicAttack(),
                          ),
                        ),

                        // Skill 1 (riêng biệt theo từng nhân vật)
                        Positioned(
                          bottom: 84 * controlScale,
                          right: 0,
                          child: _ActionButton(
                            size: 52 * controlScale,
                            icon: s1.icon,
                            label: s1.shortLabel,
                            hotkey: isDesktopOrWeb ? '1' : null,
                            color: s1.color,
                            cooldownRemaining: player.skill1VisualCd,
                            maxCooldown: s1.cooldown,
                            hasEnoughKi: player.currentKi >= s1.kiCost,
                            lowKiFlash: player.insufficientKiFlashTimer > 0,
                            onTap: () => widget.game.onSkill1(),
                          ),
                        ),

                        // Skill 2 (riêng biệt theo từng nhân vật)
                        Positioned(
                          bottom: 66 * controlScale,
                          right: 66 * controlScale,
                          child: _ActionButton(
                            size: 52 * controlScale,
                            icon: s2.icon,
                            label: s2.shortLabel,
                            hotkey: isDesktopOrWeb ? '2' : null,
                            color: s2.color,
                            cooldownRemaining: player.skill2VisualCd,
                            maxCooldown: s2.cooldown,
                            hasEnoughKi: player.currentKi >= s2.kiCost,
                            lowKiFlash: player.insufficientKiFlashTimer > 0,
                            onTap: () => widget.game.onSkill2(),
                          ),
                        ),

                        // Skill 3 Ultimate (riêng biệt theo từng nhân vật)
                        Positioned(
                          bottom: 0,
                          right: 84 * controlScale,
                          child: _ActionButton(
                            size: 52 * controlScale,
                            icon: s3.icon,
                            label: s3.shortLabel,
                            hotkey: isDesktopOrWeb ? '3' : null,
                            color: s3.color,
                            cooldownRemaining: player.skill3VisualCd,
                            maxCooldown: s3.cooldown,
                            hasEnoughKi: player.currentKi >= s3.kiCost,
                            lowKiFlash: player.insufficientKiFlashTimer > 0,
                            onTap: () => widget.game.onSkill3(),
                          ),
                        ),

                        // Companion Active Skill Button (Kỹ năng đặc biệt riêng của từng Trợ thủ)
                        if (widget.game.companion != null)
                          Positioned(
                            bottom: 124 * controlScale,
                            right: 54 * controlScale,
                            child: _ActionButton(
                              size: 44 * controlScale,
                              icon: widget.game.companion!.skillIcon,
                              label: 'PET',
                              hotkey: isDesktopOrWeb ? 'E' : null,
                              color: widget.game.companion!.skillColor,
                              cooldownRemaining:
                                  widget.game.companion!.specialSkillCooldown,
                              maxCooldown:
                                  widget.game.companion!.skillCooldownDuration,
                              hasEnoughKi: true,
                              onTap: () => widget.game.onCompanionSkill(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // 5. BOTTOM BAR HINT CHO WEB/PC (khi ẩn nút cảm ứng)
              if (!_showTouchControls && isDesktopOrWeb)
                Positioned(
                  bottom: 10,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.keyboard,
                              color: Colors.amberAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Di chuyển: WASD / Mũi tên  |  Kỹ năng: [1] ${s1.name}  [2] ${s2.name}  [3] ${s3.name}  |  Đánh: SPACE / J',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatBar({
    required String label,
    required double current,
    required double max,
    required Color color,
    double barWidth = 140,
    bool compact = false,
  }) {
    final progress = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    final barHeight = compact ? 10.0 : 12.0;
    return Row(
      children: [
        SizedBox(
          width: compact ? 20 : 24,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 9.5 : 11,
            ),
          ),
        ),
        Stack(
          children: [
            Container(
              width: barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(color: Colors.white24, width: 1),
              ),
            ),
            Container(
              width: barWidth * progress,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(barHeight / 2),
              ),
            ),
            SizedBox(
              width: barWidth,
              height: barHeight,
              child: Center(
                child: Text(
                  '${current.toInt()}/${max.toInt()}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 7.5 : 8,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpBar({
    required int current,
    required int max,
    double barWidth = 140,
    bool compact = false,
  }) {
    final progress = max > 0 ? (current / max).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: compact ? 20 : 24,
          child: Text(
            'EXP',
            style: TextStyle(
              color: GameColors.expBar,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 8 : 9,
            ),
          ),
        ),
        Stack(
          children: [
            Container(
              width: barWidth,
              height: compact ? 5 : 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              width: barWidth * progress,
              height: compact ? 5 : 6,
              decoration: BoxDecoration(
                color: GameColors.expBar,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  final double size;
  final IconData icon;
  final String label;
  final String? hotkey;
  final Color color;
  final double cooldownRemaining;
  final double maxCooldown;
  final bool hasEnoughKi;
  final bool lowKiFlash;
  final VoidCallback onTap;

  const _ActionButton({
    required this.size,
    required this.icon,
    required this.label,
    this.hotkey,
    required this.color,
    this.cooldownRemaining = 0.0,
    this.maxCooldown = 1.0,
    this.hasEnoughKi = true,
    this.lowKiFlash = false,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final onCd = widget.cooldownRemaining > 0.05;
    final borderColor = (!widget.hasEnoughKi && widget.lowKiFlash)
        ? const Color(0xFFFF1744)
        : (widget.hasEnoughKi ? const Color(0xFFFFD700) : Colors.white38);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 70),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.hasEnoughKi
                    ? widget.color.withValues(alpha: 0.92)
                    : widget.color.withValues(alpha: 0.45),
                border: Border.all(color: borderColor, width: 2.2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: widget.hasEnoughKi ? 0.5 : 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: size * 0.40),
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: size * 0.16,
                          ),
                        ),
                      ],
                    ),
                    if (onCd)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _HudCooldownSweepPainter(
                            progress: (widget.cooldownRemaining / widget.maxCooldown)
                                .clamp(0.0, 1.0),
                          ),
                          child: Center(
                            child: Text(
                              '${widget.cooldownRemaining.toStringAsFixed(1)}s',
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontSize: size * 0.22,
                                fontWeight: FontWeight.w900,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.hotkey != null)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141926),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amberAccent, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    widget.hotkey!,
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HudCooldownSweepPainter extends CustomPainter {
  final double progress;

  const _HudCooldownSweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.68)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * progress,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HudCooldownSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
