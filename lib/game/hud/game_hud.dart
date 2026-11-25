import 'dart:async';
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
  final Future<void> Function()? onPause;

  const GameHudOverlay({
    super.key,
    required this.game,
    this.keyboardController,
    this.onPause,
  });

  @override
  State<GameHudOverlay> createState() => _GameHudOverlayState();
}

class _GameHudOverlayState extends State<GameHudOverlay>
    with SingleTickerProviderStateMixin {
  // Mặc định luôn hiện nút cảm ứng; trên Desktop/Web có thể bật/tắt để quan sát toàn màn hình
  bool _showTouchControls = true;
  bool _isRebuildScheduled = false;
  Object? _displaySnapshot;
  Timer? _clockTimer;
  late final VoidCallback _statsListener = _onStatsChanged;
  late final Widget _joystick = RepaintBoundary(
    child: VirtualJoystick(onDirectionChanged: _onJoystickDirectionChanged),
  );
  late final AnimationController _bannerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3500),
  );
  late final Animation<double> _bannerOpacityAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 25),
  ]).animate(_bannerController);
  late final VoidCallback _mapListener = _onMapChanged;

  void _onMapChanged() {
    _safeSetState(() => _bannerController.forward(from: 0.0));
  }

  void _onJoystickDirectionChanged(Offset offset) {
    if (offset == Offset.zero &&
        widget.keyboardController != null &&
        widget.keyboardController!.hasKeyboardMovement) {
      widget.game.setPlayerMoveDirection(
        widget.keyboardController!.currentDirection,
      );
    } else {
      widget.game.setPlayerMoveDirection(Vector2(offset.dx, offset.dy));
    }
  }

  Object _captureDisplay() {
    final game = widget.game;
    final player = game.player;
    // Integer labels and subpixel bar changes need no full HUD rebuild.
    (int, int) bar(double value, double maximum) => (
      value.toInt(),
      maximum > 0 ? ((value / maximum).clamp(0.0, 1.0) * 140).round() : 0,
    );
    (bool, int) clock(double remaining) =>
        (remaining > 0, (remaining * 10).round());
    Object skill(int slot) {
      final config = player.skillConfig(slot);
      return (
        config,
        player.skillRuntime(slot).enabled,
        player.currentKi >= config.kiCost,
        clock(player.skillRuntime(slot).cooldownRemaining),
      );
    }

    return (
      player.heroId,
      player.level,
      bar(player.currentHp, player.maxHp),
      player.maxHp,
      bar(player.currentKi, player.maxKi),
      player.maxKi,
      player.currentExp,
      player.expToNextLevel,
      player.shieldHp > 0,
      player.shieldHp.toInt(),
      player.coinsCollected,
      game.currentFloor,
      player.canAct,
      player.insufficientKiFlashTimer > 0,
      skill(1),
      skill(2),
      skill(3),
      game.companion,
      clock(game.companion?.specialSkillCooldown ?? 0),
    );
  }

  bool get _hasActiveClocks {
    final player = widget.game.player;
    return player.skill1VisualCd > 0 ||
        player.skill2VisualCd > 0 ||
        player.skill3VisualCd > 0 ||
        player.insufficientKiFlashTimer > 0 ||
        (widget.game.companion?.specialSkillCooldown ?? 0) > 0;
  }

  void _syncClock() {
    if (!_hasActiveClocks) {
      _clockTimer?.cancel();
      _clockTimer = null;
    } else {
      // Player stat events stop at full Ki, but cooldowns still have to finish.
      // This clock observes game timers; it never advances gameplay itself.
      _clockTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || widget.game.paused) return;
        _onStatsChanged();
      });
    }
  }

  void _onStatsChanged() {
    if (!mounted) return;
    _syncClock();
    final next = _captureDisplay();
    if (_displaySnapshot == next) return;
    _displaySnapshot = next;
    _safeSetState();
  }

  void _safeSetState([VoidCallback? fn]) {
    if (!mounted) return;
    fn?.call();
    if (_isRebuildScheduled) return;

    final isBuilding =
        WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    final isPersistent =
        WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;

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
    _displaySnapshot = _captureDisplay();
    widget.game.onPlayerStatsChanged = _statsListener;
    widget.game.onMapChanged = _mapListener;
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant GameHudOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      if (oldWidget.game.onPlayerStatsChanged == _statsListener) {
        oldWidget.game.onPlayerStatsChanged = null;
      }
      if (oldWidget.game.onMapChanged == _mapListener) {
        oldWidget.game.onMapChanged = null;
      }
      _clockTimer?.cancel();
      _clockTimer = null;
      widget.game.onPlayerStatsChanged = _statsListener;
      widget.game.onMapChanged = _mapListener;
    }
    _displaySnapshot = _captureDisplay();
    _syncClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    if (widget.game.onPlayerStatsChanged == _statsListener) {
      widget.game.onPlayerStatsChanged = null;
    }
    if (widget.game.onMapChanged == _mapListener) {
      widget.game.onMapChanged = null;
    }
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.game.player;
    final isDesktopOrWeb = GamePlatformHelper.isDesktopOrWeb;
    final compactHud = MediaQuery.sizeOf(context).width < 1000;
    final s1 = HeroSkillSystem.getSkillMeta(player.heroId, 1);
    final s2 = HeroSkillSystem.getSkillMeta(player.heroId, 2);
    final s3 = HeroSkillSystem.getSkillMeta(player.heroId, 3);

    return SafeArea(
      child: Stack(
        children: [
          // Banner thông báo chiến trường ngẫu nhiên khi vào trận
          if (!compactHud)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _bannerController,
                  builder: (context, child) {
                    if (_bannerController.isCompleted) {
                      return const SizedBox.shrink();
                    }
                    final map = widget.game.currentMapConfig;
                    final isIceTheme =
                        map.theme == 'ice_arena' || map.theme == 'frost_island';
                    return Opacity(
                      opacity: _bannerOpacityAnim.value,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          (1.0 - _bannerOpacityAnim.value) * -16,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
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
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isIceTheme
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFFD700),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isIceTheme
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

          if (compactHud)
            Positioned(
              top: 78,
              left: 16,
              child: Container(
                key: const Key('hud_compact_map_badge'),
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
                    0.0,
                    320.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xDD101827),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD700)),
                ),
                child: Text(
                  widget.game.currentMapConfig.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 11,
                  ),
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
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 6),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        player.heroId == 'kaelen'
                            ? Icons.bolt_rounded
                            : player.heroId == 'ranger' ||
                                  player.heroId == 'valeria'
                            ? Icons.gps_fixed_rounded
                            : player.heroId == 'ninja'
                            ? Icons.flash_on_rounded
                            : Icons.shield,
                        color: player.heroId == 'kaelen'
                            ? const Color(0xFF00E5FF)
                            : Colors.orangeAccent,
                        size: 30,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFFD700),
                            width: 1,
                          ),
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
                if (!compactHud)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2838),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            (widget.game.currentMapConfig.theme ==
                                    'ice_arena' ||
                                widget.game.currentMapConfig.theme ==
                                    'frost_island')
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFFFD700),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (widget.game.currentMapConfig.theme == 'ice_arena' ||
                                  widget.game.currentMapConfig.theme ==
                                      'frost_island')
                              ? Icons.ac_unit_rounded
                              : Icons.account_balance_rounded,
                          color:
                              (widget.game.currentMapConfig.theme ==
                                      'ice_arena' ||
                                  widget.game.currentMapConfig.theme ==
                                      'frost_island')
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFFFFD700),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.game.currentMapConfig.name,
                          style: TextStyle(
                            color:
                                (widget.game.currentMapConfig.theme ==
                                        'ice_arena' ||
                                    widget.game.currentMapConfig.theme ==
                                        'frost_island')
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2838),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.stairs,
                        color: Colors.cyanAccent,
                        size: 16,
                      ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.orangeAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${player.coinsCollected} Xu',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
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
                  key: const Key('pve_settings_button'),
                  icon: const Icon(
                    Icons.settings_rounded,
                    color: Color(0xFF00E5FF),
                    size: 28,
                  ),
                  tooltip: 'Cài đặt âm lượng & trò chơi',
                  onPressed: () => SettingsDialog.show(context),
                ),
                IconButton(
                  key: const Key('pve_pause_button'),
                  icon: const Icon(
                    Icons.pause_circle_filled,
                    color: Colors.white,
                    size: 36,
                  ),
                  tooltip: 'Tạm dừng',
                  onPressed: widget.onPause == null
                      ? null
                      : () => widget.onPause!.call(),
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
                  _joystick,
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

                    // Skill 1 (riêng biệt theo từng nhân vật)
                    Positioned(
                      bottom: 84,
                      right: 0,
                      child: _ActionButton(
                        key: const Key('pve_skill_1'),
                        size: 52,
                        icon: s1.icon,
                        label: s1.shortLabel,
                        skillName: s1.name,
                        hotkey: isDesktopOrWeb ? '1' : null,
                        color: s1.color,
                        cooldownRemaining: player.skill1VisualCd,
                        maxCooldown: s1.cooldown,
                        hasEnoughKi:
                            player.canAct &&
                            (player.heroId != 'kaelen' ||
                                player.skillRuntime(1).enabled) &&
                            player.currentKi >= s1.kiCost,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill1(),
                      ),
                    ),

                    // Skill 2 (riêng biệt theo từng nhân vật)
                    Positioned(
                      bottom: 66,
                      right: 66,
                      child: _ActionButton(
                        key: const Key('pve_skill_2'),
                        size: 52,
                        icon: s2.icon,
                        label: s2.shortLabel,
                        skillName: s2.name,
                        hotkey: isDesktopOrWeb ? '2' : null,
                        color: s2.color,
                        cooldownRemaining: player.skill2VisualCd,
                        maxCooldown: s2.cooldown,
                        hasEnoughKi:
                            player.canAct &&
                            (player.heroId != 'kaelen' ||
                                player.skillRuntime(2).enabled) &&
                            player.currentKi >= s2.kiCost,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill2(),
                      ),
                    ),

                    // Skill 3 Ultimate (riêng biệt theo từng nhân vật)
                    Positioned(
                      bottom: 0,
                      right: 84,
                      child: _ActionButton(
                        key: const Key('pve_skill_3'),
                        size: 52,
                        icon: s3.icon,
                        label: s3.shortLabel,
                        skillName: s3.name,
                        hotkey: isDesktopOrWeb ? '3' : null,
                        color: s3.color,
                        cooldownRemaining: player.skill3VisualCd,
                        maxCooldown: s3.cooldown,
                        hasEnoughKi:
                            player.canAct &&
                            (player.heroId != 'kaelen' ||
                                player.skillRuntime(3).enabled) &&
                            player.currentKi >= s3.kiCost,
                        lowKiFlash: player.insufficientKiFlashTimer > 0,
                        onTap: () => widget.game.onSkill3(),
                      ),
                    ),

                    // Companion Active Skill Button (Kỹ năng đặc biệt riêng của từng Trợ thủ)
                    if (widget.game.companion != null)
                      Positioned(
                        bottom: 124,
                        right: 54,
                        child: _ActionButton(
                          size: 44,
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
              bottom: 12,
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
  final String? skillName;
  final String? hotkey;
  final Color color;
  final double cooldownRemaining;
  final double maxCooldown;
  final bool hasEnoughKi;
  final bool lowKiFlash;
  final VoidCallback onTap;

  const _ActionButton({
    super.key,
    required this.size,
    required this.icon,
    required this.label,
    this.skillName,
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
    final onCd = widget.cooldownRemaining > 0;
    final borderColor = (!widget.hasEnoughKi && widget.lowKiFlash)
        ? const Color(0xFFFF1744)
        : (widget.hasEnoughKi ? const Color(0xFFFFD700) : Colors.white38);

    return Tooltip(
      message: widget.skillName ?? widget.label,
      child: Semantics(
        button: true,
        label: widget.skillName,
        value: onCd
            ? 'Hồi chiêu ${widget.cooldownRemaining.toStringAsFixed(1)} giây'
            : widget.hasEnoughKi
            ? 'Sẵn sàng'
            : 'Không đủ Ki hoặc không thể hành động',
        enabled: !onCd && widget.hasEnoughKi,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: onCd ? null : widget.onTap,
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
                        color: widget.color.withValues(
                          alpha: widget.hasEnoughKi ? 0.5 : 0.15,
                        ),
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
                            Icon(
                              widget.icon,
                              color: Colors.white,
                              size: size * 0.40,
                            ),
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
                                progress:
                                    (widget.cooldownRemaining /
                                            widget.maxCooldown)
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
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 4,
                                      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141926),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.amberAccent,
                          width: 1.2,
                        ),
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
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, true, paint);
  }

  @override
  bool shouldRepaint(covariant _HudCooldownSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
