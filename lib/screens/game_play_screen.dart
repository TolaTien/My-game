import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../core/game_keyboard_controller.dart';
import '../core/stat_growth_formula.dart';
import '../game/gold_rush_game.dart';
import '../game/hud/game_hud.dart';
import '../services/player_storage.dart';

class GamePlayScreen extends StatefulWidget {
  const GamePlayScreen({super.key});

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends State<GamePlayScreen>
    with WidgetsBindingObserver {
  late final GoldRushGame _game;
  late final GameKeyboardController _keyboardController;
  final FocusNode _focusNode = FocusNode(debugLabel: 'gameplay_focus');
  bool _isPauseDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = GoldRushGame(playerProfile: PlayerStorage.currentProfile);
    _keyboardController = GameKeyboardController(
      onMoveDirectionChanged: (dir) => _game.setPlayerMoveDirection(dir),
      onBasicAttack: () => _game.onBasicAttack(),
      onSkill1: () => _game.onSkill1(),
      onSkill2: () => _game.onSkill2(),
      onSkill3: () => _game.onSkill3(),
      onCompanionSkill: () => _game.onCompanionSkill(),
    );
    _keyboardController.attach();

    _game.onVictory = () => _showVictoryDialog();
    _game.onGameOver = () => _showGameOverDialog();
  }

  void _showVictoryDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final levelUpResult = await PlayerStorage.addHeroExpAfterMatch(
        isVictory: true,
        isPvp: false,
        floorOrRounds: _game.currentFloor,
        coinsOrKills: _game.player.coinsCollected,
      );
      _game.player.applyUserHeroLevel(levelUpResult.newLevel);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => _LevelClearDialog(
          floor: _game.currentFloor,
          coinsEarned: _game.player.coinsCollected,
          playerLevel: _game.player.level,
          heroLevelUpResult: levelUpResult,
          onNextFloor: () {
            Navigator.of(dialogCtx).pop();
            _game.advanceToNextFloor();
          },
          onReturnHome: () {
            Navigator.of(dialogCtx).pop();
            Navigator.of(context).pop();
          },
        ),
      );
    });
  }

  void _showGameOverDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final levelUpResult = await PlayerStorage.addHeroExpAfterMatch(
        isVictory: false,
        isPvp: false,
        floorOrRounds: _game.currentFloor,
        coinsOrKills: _game.player.coinsCollected,
      );
      _game.player.applyUserHeroLevel(levelUpResult.newLevel);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => _GameOverDialog(
          floor: _game.currentFloor,
          coinsEarned: _game.player.coinsCollected,
          heroLevelUpResult: levelUpResult,
          onRetry: () {
            Navigator.of(dialogCtx).pop();
            _game.retryFloor();
          },
          onReturnHome: () {
            Navigator.of(dialogCtx).pop();
            Navigator.of(context).pop();
          },
        ),
      );
    });
  }

  Future<void> showPauseMenu() async {
    if (!mounted || _isPauseDialogOpen) return;
    _isPauseDialogOpen = true;
    var shouldLeaveGame = false;
    _game.pauseEngine();
    _keyboardController.setEnabled(false);

    try {
      final shouldLeave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _PauseMenuDialog(
          onResume: () => Navigator.of(dialogContext).pop(false),
          onLeave: () async {
            final confirmed = await showDialog<bool>(
              context: dialogContext,
              builder: (confirmContext) => AlertDialog(
                title: const Text('Rời trận?'),
                content: const Text('Tiến trình tầng hiện tại sẽ không được tiếp tục.'),
                actions: [
                  TextButton(
                    key: const Key('pause_leave_cancel_button'),
                    onPressed: () => Navigator.of(confirmContext).pop(false),
                    child: const Text('Ở lại'),
                  ),
                  FilledButton(
                    key: const Key('pause_leave_confirm_button'),
                    onPressed: () => Navigator.of(confirmContext).pop(true),
                    child: const Text('Rời trận'),
                  ),
                ],
              ),
            );
            if (dialogContext.mounted) {
              // Cancel returns to live gameplay; only positive confirmation exits.
              Navigator.of(dialogContext).pop(confirmed == true);
            }
          },
        ),
      );

      if (!mounted) return;
      shouldLeaveGame = shouldLeave == true;
    } finally {
      _isPauseDialogOpen = false;
      if (mounted && !shouldLeaveGame) {
        _keyboardController.setEnabled(true);
        _game.resumeEngine();
        _focusNode.requestFocus();
      }
    }
    if (mounted && shouldLeaveGame) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _keyboardController.resetMovement();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardController.detach();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: GameWidget<GoldRushGame>(
          game: _game,
          overlayBuilderMap: {
            'HUD': (context, game) => GameHudOverlay(
                  game: game,
                  keyboardController: _keyboardController,
                  onPause: showPauseMenu,
                ),
          },
          initialActiveOverlays: const ['HUD'],
        ),
      ),
    );
  }
}

class _PauseMenuDialog extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onLeave;

  const _PauseMenuDialog({required this.onResume, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF151A26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_filled, color: Colors.amberAccent, size: 48),
                const SizedBox(height: 8),
                const Text('TẠM DỪNG', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('pause_resume_button'),
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('TIẾP TỤC'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('pause_leave_button'),
                    onPressed: onLeave,
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('RỜI TRẬN'),
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

class _LevelClearDialog extends StatelessWidget {
  final int floor;
  final int coinsEarned;
  final int playerLevel;
  final HeroLevelUpResult heroLevelUpResult;
  final VoidCallback onNextFloor;
  final VoidCallback onReturnHome;

  const _LevelClearDialog({
    required this.floor,
    required this.coinsEarned,
    required this.playerLevel,
    required this.heroLevelUpResult,
    required this.onNextFloor,
    required this.onReturnHome,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amberAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.amberAccent.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF263238),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.amberAccent,
                  size: 38,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'CHIẾN THẮNG TẦNG $floor!',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Đã tiêu diệt toàn bộ quái vật và Chúa Tể Hầm Ngục!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatBadge(
                      icon: Icons.monetization_on,
                      iconColor: Colors.amber,
                      label: 'Vàng tích lũy',
                      value: '$coinsEarned Vàng',
                    ),
                    Container(width: 1, height: 28, color: Colors.white24),
                    _StatBadge(
                      icon: Icons.military_tech,
                      iconColor: Colors.cyanAccent,
                      label: 'Cấp trong trận',
                      value: 'Lv.$playerLevel / 15',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _HeroLevelProgressBanner(result: heroLevelUpResult),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: onReturnHome,
                      child: const Text(
                        'VỀ SẢNH',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: onNextFloor,
                      child: Text(
                        'SANG TẦNG ${floor + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOverDialog extends StatelessWidget {
  final int floor;
  final int coinsEarned;
  final HeroLevelUpResult heroLevelUpResult;
  final VoidCallback onRetry;
  final VoidCallback onReturnHome;

  const _GameOverDialog({
    required this.floor,
    required this.coinsEarned,
    required this.heroLevelUpResult,
    required this.onRetry,
    required this.onReturnHome,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1115),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withValues(alpha: 0.35),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E151A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.dangerous,
                  color: Colors.redAccent,
                  size: 38,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'BẠN ĐÃ THẤT THỦ TẠI TẦNG $floor!',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sinh lực đã cạn kiệt! Nhân vật vẫn nhận được EXP rèn luyện sau trận.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Vàng đã thu thập: $coinsEarned Vàng',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _HeroLevelProgressBanner(result: heroLevelUpResult),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: onReturnHome,
                      child: const Text(
                        'VỀ SẢNH',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: onRetry,
                      child: const Text(
                        'THỬ LẠI TẦNG NÀY',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroLevelProgressBanner extends StatelessWidget {
  final HeroLevelUpResult result;

  const _HeroLevelProgressBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final progress = result.expToNextLevel > 0
        ? (result.currentExp / result.expToNextLevel).clamp(0.0, 1.0)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: result.didLevelUp
              ? [const Color(0xFF2B2208), const Color(0xFF171C29)]
              : [const Color(0xFF151C28), const Color(0xFF0E131C)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.didLevelUp ? Colors.amberAccent : Colors.cyanAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.didLevelUp ? Icons.auto_awesome : Icons.trending_up_rounded,
                color: result.didLevelUp ? Colors.amberAccent : Colors.cyanAccent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  result.didLevelUp
                      ? 'THĂNG CẤP NHÂN VẬT: Lv.${result.oldLevel} ➔ Lv.${result.newLevel}/100!'
                      : 'CẤP NHÂN VẬT: Lv.${result.newLevel}/100 (+${result.expEarned} EXP)',
                  style: TextStyle(
                    color: result.didLevelUp ? Colors.amberAccent : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                result.didLevelUp ? Colors.amberAccent : Colors.cyanAccent,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.didLevelUp
                ? 'Tăng vĩnh viễn: +${result.hpAdded.toInt()} HP | +${result.kiAdded.toInt()} Ki | +${result.attackAdded.toInt()} Sức Đánh'
                : 'Tổng chỉ số hiện tại: ${result.newStats.maxHp.toInt()} HP | ${result.newStats.maxKi.toInt()} Ki | ${result.newStats.attackDamage.toInt()} ATK',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatBadge({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}
