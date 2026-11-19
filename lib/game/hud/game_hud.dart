import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/constants.dart';
import '../../core/game_keyboard_controller.dart';
import '../../screens/settings_dialog.dart';
import '../components/companion_component.dart';
import '../components/player.dart';
import '../gold_rush_game.dart';
import 'boss_bar_overlay.dart';
import 'virtual_joystick.dart';

class GameHudOverlay extends StatefulWidget {
  final GoldRushGame game;
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

    return SafeArea(
      child: Stack(
        children: [
          // Banner thông báo chiến trường ngẫu nhiên khi vào trận
          Positioned(
            top: 22,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _bannerController,
                builder: (context, child) {
                  if (_bannerController.isCompleted) return const SizedBox.shrink();
                  final map = widget.game.currentMapConfig;
                  final isIceTheme = map.theme == 'ice_arena' || map.theme == 'frost_island';
                  return Opacity(
                    opacity: _bannerOpacityAnim.value,
                    child: Transform.translate(
                      offset: Offset(0, (1.0 - _bannerOpacityAnim.value) * -16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isIceTheme
                                ? [
                                    const Color(0xFF002244).withValues(alpha: 0.92),
                                    const Color(0xFF005588).withValues(alpha: 0.92),
                                  ]
                                : [
                                    const Color(0xFF2C1E0A).withValues(alpha: 0.92),
                                    const Color(0xFF4A3410).withValues(alpha: 0.92),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isIceTheme
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFFFFD700),
                            width: 1.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isIceTheme
                                      ? const Color(0xFF00E5FF)
                                      : const Color(0xFFFFD700))
                                  .withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: 2,
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
                              color: isIceTheme
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFFD700),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'CHIẾN TRƯỜNG: ${map.name.toUpperCase()}',
                              style: TextStyle(
                                color: isIceTheme
                                    ? const Color(0xFFE0F7FA)
                                    : const Color(0xFFFFF8E1),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 1.0,
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

          // 1. TOP BAR: Chỉ số HP, Ki, EXP, Giáp Hoàng Kim và Level
          Positioned(
            top: 12,
            left: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Khung Avatar nhân vật Golden-Cyber & Level
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFFFD700), width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        player.heroId == 'ranger' || player.heroId == 'valeria'
                            ? Icons.gps_fixed_rounded
                            : player.heroId == 'ninja'
                                ? Icons.flash_on_rounded
                                : Icons.shield,
                        color: Colors.orangeAccent,
                        size: 30,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Lv.${player.level}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Cột thanh máu, Ki, EXP và Khiên Hoàng Kim
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatBar(
                      label: 'HP',
                      current: player.currentHp,
                      max: player.maxHp,
                      color: GameColors.hpBar,
                    ),
                    const SizedBox(height: 4),
                    _buildStatBar(
                      label: 'KI',
                      current: player.currentKi,
                      max: player.maxKi,
                      color: GameColors.kiBar,
                    ),
                    const SizedBox(height: 4),
                    _buildExpBar(
                      current: player.currentExp,
                      max: player.expToNextLevel,
                    ),
                    if (player.shieldHp > 0) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFD700), width: 1),
                        ),
                        child: Text(
                          '🛡 KHIÊN HOÀNG KIM +${player.shieldHp.toInt()}',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // 2. TOP RIGHT: Bản đồ ngẫu nhiên, Tầng hiện tại, Xu nhặt được, Nút bật/tắt phím ảo (trên PC/Web) & Nút Pause
          Positioned(
            top: 12,
            right: 16,
            child: Row(
              children: [
                // Huy hiệu bản đồ hiện tại
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2838),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (widget.game.currentMapConfig.theme == 'ice_arena' ||
                              widget.game.currentMapConfig.theme == 'frost_island')
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFFFFD700),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (widget.game.currentMapConfig.theme == 'ice_arena' ||
                                widget.game.currentMapConfig.theme == 'frost_island')
                            ? Icons.ac_unit_rounded
                            : Icons.account_balance_rounded,
                        color: (widget.game.currentMapConfig.theme == 'ice_arena' ||
                                widget.game.currentMapConfig.theme == 'frost_island')
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFFFD700),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.game.currentMapConfig.name,
                        style: TextStyle(
                          color: (widget.game.currentMapConfig.theme == 'ice_arena' ||
                                  widget.game.currentMapConfig.theme == 'frost_island')
                              ? const Color(0xFF80DEEA)
                              : const Color(0xFFFFE082),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2838),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.stairs, color: Colors.cyanAccent, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'TẦNG ${widget.game.currentFloor}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '${player.coinsCollected * GameConstants.goldPerCoinPickup} Vàng',
                        style: const TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDesktopOrWeb) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('toggle_touch_controls_button'),
                    icon: Icon(
                      _showTouchControls ? Icons.gamepad : Icons.keyboard,
                      color: Colors.amberAccent,
                      size: 28,
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Color(0xFF00E5FF), size: 30),
                  tooltip: 'Cài đặt âm lượng & trò chơi',
                  onPressed: () {
                    SettingsDialog.show(context);
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.pause_circle_filled, color: Colors.white, size: 36),
                  onPressed: () {
                    // Mở menu pause hoặc thoát
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),

          // 2.5 TOP CENTER: Boss Health Bar Overlay
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: BossBarOverlay(game: widget.game),
          ),

          // 3. BOTTOM LEFT: Virtual Joystick điều hướng
          if (_showTouchControls || GamePlatformHelper.isMobile)
            Positioned(
              bottom: 24,
              left: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDesktopOrWeb)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.7), width: 1),
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

          // 4. BOTTOM RIGHT: Cụm phím hành động hình cánh cung (Arc Action Cluster: ATK + 3 Skill + Companion PET)
          if (_showTouchControls || GamePlatformHelper.isMobile)
            Positioned(
              bottom: 24,
              right: 24,
              child: SizedBox(
                width: 210,
                height: 210,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    // Nút Đánh Thường (To nhất, góc dưới cùng bên phải)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: _ActionButton(
                        size: 74,
                        icon: Icons.flash_on,
                        label: 'ATK',
                        hotkey: isDesktopOrWeb ? 'SPACE' : null,
                        color: const Color(0xFFE53935),
                        onTap: () => widget.game.onBasicAttack(),
                      ),
                    ),

                    // Skill 1: Lôi Ảnh Trảm / Búa Cuồng Phong (25 Ki)
                    Positioned(
                      bottom: 84,
                      right: 0,
                      child: _ActionButton(
                        size: 52,
                        icon: Icons.cyclone,
                        label: '25 Ki',
                        hotkey: isDesktopOrWeb ? '1' : null,
                        color: const Color(0xFFFF9800),
                        cooldownRemaining: player.skill1VisualCd,
                        maxCooldown: PlayerComponent.skill1MaxCd,
                        hasEnoughKi: player.currentKi >= 25,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill1(),
                      ),
                    ),

                    // Skill 2: Lôi Điện Hộ Thể / Nện Đất (35 Ki)
                    Positioned(
                      bottom: 66,
                      right: 66,
                      child: _ActionButton(
                        size: 52,
                        icon: Icons.landslide,
                        label: '35 Ki',
                        hotkey: isDesktopOrWeb ? '2' : null,
                        color: const Color(0xFF00B0FF),
                        cooldownRemaining: player.skill2VisualCd,
                        maxCooldown: PlayerComponent.skill2MaxCd,
                        hasEnoughKi: player.currentKi >= 35,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill2(),
                      ),
                    ),

                    // Skill 3: Thiên Phạt Lôi Ngục / Cơn Cuồng Nộ (40 Ki)
                    Positioned(
                      bottom: 0,
                      right: 84,
                      child: _ActionButton(
                        size: 52,
                        icon: Icons.whatshot,
                        label: '40 Ki',
                        hotkey: isDesktopOrWeb ? '3' : null,
                        color: const Color(0xFF7B1FA2),
                        cooldownRemaining: player.skill3VisualCd,
                        maxCooldown: PlayerComponent.skill3MaxCd,
                        hasEnoughKi: player.currentKi >= 40,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill3(),
                      ),
                    ),

                    // Companion Active Skill Button (Aegis-X9 / PET: Trường Trọng Lực Hoàng Kim)
                    if (widget.game.companion != null)
                      Positioned(
                        bottom: 124,
                        right: 54,
                        child: _ActionButton(
                          size: 44,
                          icon: Icons.auto_awesome,
                          label: 'PET',
                          hotkey: isDesktopOrWeb ? 'E' : null,
                          color: const Color(0xFFFFB300),
                          cooldownRemaining:
                              widget.game.companion!.specialSkillCooldown,
                          maxCooldown: CompanionComponent.specialSkillMaxCooldown,
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
              bottom: 12,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard, color: Colors.amberAccent, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Di chuyển: WASD / Mũi tên  |  Kỹ năng: [1] Bão Búa  [2] Nện Đất  [3] Cuồng Nộ  |  Đánh: SPACE / J',
                          style: TextStyle(
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
      ),
    );
  }

  Widget _buildStatBar({
    required String label,
    required double current,
    required double max,
    required Color color,
  }) {
    final progress = (current / max).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
        Stack(
          children: [
            Container(
              width: 140,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24, width: 1),
              ),
            ),
            Container(
              width: 140 * progress,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            SizedBox(
              width: 140,
              height: 12,
              child: Center(
                child: Text(
                  '${current.toInt()}/${max.toInt()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpBar({required int current, required int max}) {
    final progress = (current / max).clamp(0.0, 1.0);
    return Row(
      children: [
        const SizedBox(
          width: 24,
          child: Text(
            'EXP',
            style: TextStyle(
              color: GameColors.expBar,
              fontWeight: FontWeight.bold,
              fontSize: 9,
            ),
          ),
        ),
        Stack(
          children: [
            Container(
              width: 140,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Container(
              width: 140 * progress,
              height: 6,
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
