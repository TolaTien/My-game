import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../models/pvp_match.dart';
import '../registry/asset_registry.dart';
import '../services/audio_service.dart';
import '../services/player_storage.dart';
import 'components/floating_combat_text.dart';
import 'components/hero_projectile.dart';
import 'components/player.dart';
import 'components/pvp_arena_map.dart';
import 'components/pvp_bot_player.dart';

class PvpArenaGame extends FlameGame with HasCollisionDetection {
  final PvpOpponentInfo opponentInfo;
  final int playerCurrentRp;
  final int? playerCurrentStars;
  final bool isCurrentChallengerTop10;
  final bool isOnline;
  final bool isPlayerOne;
  final PvpGameMode gameMode;
  final MapAssetConfig? selectedMapConfig;
  final int localBlueSlotIndex;
  final Map<int, String> humanAllyCodes;
  final bool isPartyGuest;
  late MapAssetConfig currentMapConfig;
  late final PvpTeamRoster teamRoster;

  late PlayerComponent player;
  late PvpBotPlayerComponent bot;
  final List<PvpBotPlayerComponent> allies = [];
  final List<int> _allySlotIndices = [];
  final Map<String, PvpBotPlayerComponent> _humanAlliesByCode = {};
  final List<PvpBotPlayerComponent> extraEnemies = [];
  late PvpArenaMapComponent arenaMap;

  List<PvpBotPlayerComponent> get allEnemies => [bot, ...extraEnemies];

  int get blueTeamAliveCount =>
      (player.currentHp > 0 ? 1 : 0) +
      allies.where((a) => a.currentHp > 0).length;

  int get redTeamAliveCount => allEnemies.where((e) => e.currentHp > 0).length;

  static const double roundIntroDuration = 1.5;

  // Trạng thái trận đấu Bo3
  PvpMatchState matchState = PvpMatchState.roundIntro;
  int currentRound = 1;
  int playerWins = 0;
  int opponentWins = 0;
  bool lastRoundPlayerWon = true;
  double roundTimeRemaining = 90.0;
  double stateTimer = roundIntroDuration; // 1.5s chuẩn bị / 2.5s cho roundEnd
  double fightStartBannerTimer = 0.0;
  Vector2 _pendingMoveDirection = Vector2.zero();
  DateTime matchStartTime = DateTime.now();

  // Tọa độ spawn chuẩn đối xứng
  static final Vector2 playerSpawnPos = Vector2(200, 320);
  static final Vector2 botSpawnPos = Vector2(760, 320);

  static final List<Vector2> _blueSlotPositions = [
    Vector2(200, 320),
    Vector2(170, 205),
    Vector2(170, 435),
    Vector2(130, 320),
  ];

  static final List<Vector2> _redSlotPositions = [
    Vector2(760, 320),
    Vector2(790, 205),
    Vector2(790, 435),
    Vector2(830, 320),
  ];

  // Speech bubble trên đầu Player
  String? playerSpeechBubble;
  double playerSpeechTimer = 0.0;

  // Callbacks thông báo ra Flutter Screen
  Function()? onStateChanged;
  Function(PvpMatchResult result)? onMatchFinished;
  Function(String action, {String? text})? onLocalAction;

  Vector2 get _localSpawn => isPlayerOne
      ? _blueSlotPositions[localBlueSlotIndex.clamp(
              0,
              _blueSlotPositions.length - 1,
            )]
            .clone()
      : botSpawnPos.clone();
  Vector2 get _opponentSpawn =>
      (isPlayerOne ? botSpawnPos : playerSpawnPos).clone();

  PvpArenaGame({
    required this.opponentInfo,
    required this.playerCurrentRp,
    this.playerCurrentStars,
    this.isCurrentChallengerTop10 = false,
    this.isOnline = false,
    this.isPlayerOne = true,
    this.gameMode = PvpGameMode.solo1v1,
    PvpTeamRoster? roster,
    this.selectedMapConfig,
    this.localBlueSlotIndex = 0,
    this.humanAllyCodes = const {},
    this.isPartyGuest = false,
  }) {
    // Không bao giờ pause khi chạy đa tab/cửa sổ không focus (Multi-window PvP)
    pauseWhenBackgrounded = false;

    currentMapConfig =
        selectedMapConfig ?? GameAssetRegistry.instance.getRandomMap();

    // Trận online 1v1 chỉ bắt đầu khi CẢ HAI bên đã vào phòng (xem startOnlineMatch)
    if (isOnline) matchState = PvpMatchState.waiting;

    final localHero = PlayerStorage.currentProfile.selectedHeroId;
    teamRoster =
        roster ??
        PvpOpponentInfo.generateTeamRoster(
          playerRp: playerCurrentRp,
          mode: gameMode,
          playerHeroId: localHero,
        );

    arenaMap = PvpArenaMapComponent(
      gameMode: gameMode,
      mapConfig: currentMapConfig,
    );

    player = PlayerComponent(
      position: _localSpawn,
      heroId: localHero,
      // The existing online action strings replay these same legacy effects.
      legacyPvpSkills: true,
    );
    bot = PvpBotPlayerComponent(
      position: _opponentSpawn,
      opponentInfo: opponentInfo,
      targetPlayer: player,
      enableAi: !isOnline && !isPartyGuest,
      getHostileTargets: gameMode == PvpGameMode.solo1v1
          ? null
          : () => <PositionComponent>[player, ...allies],
      canAct: () => matchState == PvpMatchState.fighting,
      getObstacleRects: () => arenaMap.obstacleRects,
      getInteriorObstacleRects: () => arenaMap.pillarRects,
      getWalkableGrid: () => arenaMap.walkableGrid,
    );

    // Khởi tạo thêm Đồng đội & Kẻ địch cho chế độ 2v2 và 4v4
    if (gameMode != PvpGameMode.solo1v1) {
      final availableBlueSlots = <int>[
        for (int s = 0; s < _blueSlotPositions.length; s++)
          if (s != localBlueSlotIndex) s,
      ];

      for (int i = 0; i < teamRoster.allies.length; i++) {
        final allyInfo = teamRoster.allies[i];
        final slotIdx = i < availableBlueSlots.length
            ? availableBlueSlots[i]
            : min(i + 1, _blueSlotPositions.length - 1);
        final humanCode = humanAllyCodes[i]?.trim().toUpperCase();
        final isHumanTeammate = humanCode != null && humanCode.isNotEmpty;

        final allyBot = PvpBotPlayerComponent(
          position: _blueSlotPositions[slotIdx].clone(),
          opponentInfo: allyInfo,
          targetPlayer: player,
          enableAi: !isHumanTeammate && !isPartyGuest,
          getHostileTargets: () => <PositionComponent>[...allEnemies],
          canAct: () => matchState == PvpMatchState.fighting,
          getObstacleRects: () => arenaMap.obstacleRects,
          getInteriorObstacleRects: () => arenaMap.pillarRects,
          getWalkableGrid: () => arenaMap.walkableGrid,
        );
        allies.add(allyBot);
        _allySlotIndices.add(slotIdx);
        if (isHumanTeammate) {
          _humanAlliesByCode[humanCode] = allyBot;
        }
      }

      // Kẻ địch thứ 2..N (bỏ qua phần tử 0 vì đã là `bot`)
      final extraCount = gameMode.teamSize - 1;
      for (int i = 0; i < extraCount; i++) {
        final enemyInfo = (i + 1 < teamRoster.enemies.length)
            ? teamRoster.enemies[i + 1]
            : PvpOpponentInfo.generateBot(
                playerCurrentRp,
                playerHeroId: localHero,
              );
        final spawnIdx = min(i + 1, _redSlotPositions.length - 1);
        final enemyBot = PvpBotPlayerComponent(
          position: _redSlotPositions[spawnIdx].clone(),
          opponentInfo: enemyInfo,
          targetPlayer: player,
          enableAi: !isPartyGuest,
          getHostileTargets: () => <PositionComponent>[player, ...allies],
          canAct: () => matchState == PvpMatchState.fighting,
          getObstacleRects: () => arenaMap.obstacleRects,
          getInteriorObstacleRects: () => arenaMap.pillarRects,
          getWalkableGrid: () => arenaMap.walkableGrid,
        );
        extraEnemies.add(enemyBot);
      }
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1. Bản đồ đấu trường đối xứng 960x640 (Ngẫu nhiên theo currentMapConfig)
    await world.add(arenaMap);

    // 2. Player (Bên trái: X=200, Y=320)
    player.position = _localSpawn;
    player.onStatsChanged = () => onStateChanged?.call();
    await world.add(player);

    // 3. Đồng đội AI (nếu là 2v2 / 4v4)
    for (final ally in allies) {
      ally.onStatsChanged = () => onStateChanged?.call();
      await world.add(ally);
    }

    // 4. Bot chính (Bên phải: X=760, Y=320) & các Bot địch phụ
    bot.onStatsChanged = () => onStateChanged?.call();
    await world.add(bot);
    for (final enemy in extraEnemies) {
      enemy.onStatsChanged = () => onStateChanged?.call();
      await world.add(enemy);
    }

    // 5. Cấu hình Camera bám sát theo Player (toàn màn hình, to và rõ nét như PvE)
    camera.follow(player);
    camera.viewfinder.zoom = 1.4;

    matchStartTime = DateTime.now();

    // Khởi động PvP Combat BGM
    AudioService.instance.playBgm(BgmTrack.pvp);

    // Kích hoạt cập nhật state ra Flutter UI
    onStateChanged?.call();
  }

  @override
  void onRemove() {
    AudioService.instance.stopBgm();
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (!dt.isFinite || dt < 0) return;
    player.actionsEnabled = !paused && matchState == PvpMatchState.fighting;
    super.update(dt);

    // Xử lý speech bubble của Player
    if (playerSpeechTimer > 0) {
      playerSpeechTimer -= dt;
      if (playerSpeechTimer <= 0) {
        playerSpeechBubble = null;
        onStateChanged?.call();
      }
    }

    switch (matchState) {
      case PvpMatchState.waiting:
      case PvpMatchState.matchmaking:
        break;

      case PvpMatchState.roundIntro:
        final prevCountdown = stateTimer.ceil();
        stateTimer -= dt;
        final nextCountdown = stateTimer.ceil();
        if (stateTimer <= 0) {
          matchState = PvpMatchState.fighting;
          player.actionsEnabled = true;
          roundTimeRemaining = 90.0;
          fightStartBannerTimer = 0.7;
          // Áp dụng ngay hướng di chuyển người chơi đang giữ khi đếm ngược kết thúc
          player.moveDirection = _pendingMoveDirection.clone();
          onStateChanged?.call();
        } else if (nextCountdown != prevCountdown) {
          onStateChanged?.call();
        }
        break;

      case PvpMatchState.fighting:
        if (fightStartBannerTimer > 0) {
          fightStartBannerTimer -= dt;
          if (fightStartBannerTimer <= 0) {
            fightStartBannerTimer = 0.0;
            onStateChanged?.call();
          }
        }
        final oldSec = roundTimeRemaining.toInt();
        roundTimeRemaining -= dt;
        final newSec = roundTimeRemaining.toInt();
        if (newSec != oldSec) {
          onStateChanged?.call();
        }

        // Kiểm tra kết thúc hiệp đấu (Toàn bộ đội bị K.O hoặc hết 90s)
        final blueWiped =
            player.currentHp <= 0 && allies.every((a) => a.currentHp <= 0);
        final redWiped = allEnemies.every((e) => e.currentHp <= 0);
        if (blueWiped || redWiped || roundTimeRemaining <= 0) {
          _adjudicateRound();
        }
        break;

      case PvpMatchState.roundEnd:
        stateTimer -= dt;
        if (stateTimer <= 0) {
          if (playerWins >= 2 || opponentWins >= 2) {
            _concludeMatch();
          } else {
            _startNextRound();
          }
        }
        break;

      case PvpMatchState.matchFinished:
        break;
    }
  }

  void _adjudicateRound() {
    matchState = PvpMatchState.roundEnd;
    player.actionsEnabled = false;
    player.moveDirection = Vector2.zero();
    stateTimer = 2.5;

    final blueHp =
        player.currentHp + allies.fold<double>(0.0, (s, a) => s + a.currentHp);
    final blueMaxHp =
        player.maxHp + allies.fold<double>(0.0, (s, a) => s + a.maxHp);
    final redHp = allEnemies.fold<double>(0.0, (s, e) => s + e.currentHp);
    final redMaxHp = allEnemies.fold<double>(0.0, (s, e) => s + e.maxHp);

    final playerHpPct = blueMaxHp > 0 ? (blueHp / blueMaxHp) : 0.0;
    final botHpPct = redMaxHp > 0 ? (redHp / redMaxHp) : 0.0;

    if (playerHpPct > botHpPct) {
      playerWins++;
      lastRoundPlayerWon = true;
    } else if (botHpPct > playerHpPct) {
      opponentWins++;
      lastRoundPlayerWon = false;
    } else {
      // Hòa: nếu % bằng nhau thì ưu tiên người chơi
      playerWins++;
      lastRoundPlayerWon = true;
    }

    onStateChanged?.call();
  }

  void _startNextRound() {
    for (final projectile
        in world.children.whereType<HeroProjectile>().toList()) {
      projectile.removeFromParent();
    }
    currentRound++;
    matchState = PvpMatchState.roundIntro;
    stateTimer = roundIntroDuration;
    fightStartBannerTimer = 0.0;

    // Reset vị trí và máu của tất cả đấu sĩ về vị trí xuất phát đối xứng chuẩn
    player.position = _localSpawn;
    player.currentHp = player.maxHp;
    player.currentKi = player.maxKi;
    player.isBerserk = false;
    player.isAttacking = false;
    player.moveDirection = Vector2.zero();
    player.resetCombatState();

    for (int i = 0; i < allies.length; i++) {
      final spawnIdx = i < _allySlotIndices.length
          ? _allySlotIndices[i]
          : min(i + 1, _blueSlotPositions.length - 1);
      allies[i].resetRound(_blueSlotPositions[spawnIdx].clone());
    }

    bot.resetRound(_opponentSpawn);
    for (int i = 0; i < extraEnemies.length; i++) {
      final spawnIdx = min(i + 1, _redSlotPositions.length - 1);
      extraEnemies[i].resetRound(_redSlotPositions[spawnIdx].clone());
    }

    onStateChanged?.call();
  }

  void _concludeMatch() {
    matchState = PvpMatchState.matchFinished;
    player.actionsEnabled = false;
    player.moveDirection = Vector2.zero();
    final duration = DateTime.now().difference(matchStartTime);

    final result = PvpEloCalculator.calculateResult(
      playerCurrentRp: playerCurrentRp,
      playerCurrentStars: playerCurrentStars,
      isCurrentChallengerTop10: isCurrentChallengerTop10,
      playerRoundsWon: playerWins,
      opponentRoundsWon: opponentWins,
      matchDuration: duration,
      gameMode: gameMode,
    );

    if (result.isWinner) {
      AudioService.instance.playSfx(SfxSound.wheelJackpot);
    }

    onStateChanged?.call();
    onMatchFinished?.call(result);
  }

  // --- ONLINE MATCH LIFECYCLE ---

  bool get isWaitingForOpponent => matchState == PvpMatchState.waiting;

  /// Gọi khi cả hai người chơi đã sẵn sàng trong phòng.
  void startOnlineMatch() {
    if (matchState != PvpMatchState.waiting) return;
    matchState = PvpMatchState.roundIntro;
    stateTimer = roundIntroDuration;
    fightStartBannerTimer = 0.0;
    matchStartTime = DateTime.now();
    onStateChanged?.call();
  }

  /// Đối thủ thoát/mất kết nối giữa trận => xử thắng cho người còn lại.
  void opponentForfeit() {
    if (matchState == PvpMatchState.matchFinished) return;
    playerWins = max(playerWins, 2);
    _concludeMatch();
  }

  // --- ACTIONS ---

  void setPlayerMoveDirection(Vector2 dir) {
    _pendingMoveDirection = dir.clone();
    if (matchState != PvpMatchState.fighting) {
      player.moveDirection = Vector2.zero();
      return;
    }
    player.moveDirection = dir;
  }

  void _damageEnemiesInRange(
    double dmg,
    double range, {
    CombatTextType type = CombatTextType.normalDamage,
    bool directional = false,
  }) {
    for (final enemy in allEnemies) {
      if (enemy.currentHp <= 0) continue;
      final dist = player.position.distanceTo(enemy.position);
      if (dist <= range &&
          (!directional ||
              player.canHitBasicAttack(enemy.position, range: range))) {
        enemy.takeDamage(dmg);
        if (isMounted) {
          world.add(
            FloatingCombatText(
              text: '-${dmg.toInt()}',
              position: enemy.position.clone()..y -= 20,
              type: type,
            ),
          );
        }
      }
    }
  }

  void onBasicAttack() {
    if (paused ||
        matchState != PvpMatchState.fighting ||
        !player.performBasicAttack()) {
      return;
    }

    final heroId = player.heroId;
    final isRanger = heroId == 'ranger';
    final isEmber = heroId == 'ember_02' || heroId == 'ember';
    final isValeria = heroId == 'valeria';
    final isRanged = isRanger || isEmber || isValeria;

    if (isRanged) {
      // Xác định mục tiêu đối thủ gần nhất trong tầm 400px
      Vector2? targetDir;
      double closestDist = 400.0;
      for (final enemy in allEnemies) {
        if (enemy.currentHp <= 0) continue;
        final d = player.position.distanceTo(enemy.position);
        final offset = enemy.position - player.position;
        final inFront =
            offset.length2 == 0 ||
            offset.normalized().dot(player.attackDirection) >= .5;
        if (d < closestDist && inFront) {
          closestDist = d;
          targetDir = (enemy.position - player.position).normalized();
        }
      }

      if (targetDir == null) {
        if (player.moveDirection.length2 > 0) {
          targetDir = player.moveDirection.normalized();
        } else {
          targetDir = player.attackDirection;
        }
      }
      player.faceDirection(targetDir);

      final isCombo3 = player.comboStep == 3;
      final dmg = player.effectiveDamage * (isCombo3 ? 1.4 : 1.0);
      final pType = isRanger
          ? HeroProjectileType.arrow
          : (isEmber
                ? HeroProjectileType.fireball
                : HeroProjectileType.frostOrb);

      final projectile = HeroProjectile(
        position: player.position.clone() + Vector2(0, 2),
        direction: targetDir,
        damage: dmg,
        type: pType,
        isFromPlayer: true,
        onHit: (target, hitPos) {
          if (isMounted) {
            world.add(
              FloatingCombatText(
                text: '-${dmg.toInt()}',
                position: hitPos.clone()..y -= 20,
                type: isCombo3
                    ? CombatTextType.criticalDamage
                    : CombatTextType.normalDamage,
              ),
            );
          }
        },
      );

      world.add(projectile);
      onLocalAction?.call('basicAttack');
      return;
    }

    _damageEnemiesInRange(
      player.effectiveDamage,
      55,
      type: CombatTextType.normalDamage,
      directional: true,
    );
    onLocalAction?.call('basicAttack');
  }

  void onSkill1() {
    if (paused || matchState != PvpMatchState.fighting || !player.canAct) {
      return;
    }
    if (!player.useSkill1()) return;

    _damageEnemiesInRange(
      player.damage * 1.8,
      85,
      type: CombatTextType.skillDamage,
    );
    onLocalAction?.call('skill1');
  }

  void onSkill2() {
    if (paused || matchState != PvpMatchState.fighting || !player.canAct) {
      return;
    }
    if (!player.useSkill2()) return;

    _damageEnemiesInRange(
      player.damage * 2.5,
      110,
      type: CombatTextType.skillDamage,
    );
    onLocalAction?.call('skill2');
  }

  void onSkill3() {
    if (paused || matchState != PvpMatchState.fighting || !player.canAct) {
      return;
    }
    if (player.useSkill3()) {
      if (player.heroId != 'george' &&
          player.heroId != 'ranger' &&
          player.heroId != 'tanker' &&
          player.heroId != 'ninja') {
        _damageEnemiesInRange(
          player.damage * 2.2,
          140,
          type: CombatTextType.criticalDamage,
        );
      }
      onLocalAction?.call('skill3');
    }
  }

  void sendQuickChat(QuickChatPhrase phrase) {
    playerSpeechBubble = phrase.text;
    playerSpeechTimer = 3.0;
    player.say(phrase.text);
    onStateChanged?.call();
    onLocalAction?.call('quickChat', text: phrase.text);

    if (isOnline) return;

    // Bot phản xạ trả lời nếu gặp câu chat khích tướng
    if (Random().nextDouble() < 0.6 && bot.speechBubbleText == null) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!isMounted) return;
        switch (phrase) {
          case QuickChatPhrase.noob:
            bot.say('Đợi đấy!');
            break;
          case QuickChatPhrase.attack:
            bot.say('Nhào vô!');
            break;
          case QuickChatPhrase.awesome:
            bot.say('Cảm ơn!');
            break;
          default:
            bot.say('Chiến nào!');
        }
      });
    }
  }

  void applyOpponentSnapshot(Map<String, dynamic> snapshot) {
    double? number(String key) => (snapshot[key] as num?)?.toDouble();
    final x = number('x');
    final y = number('y');
    final vx = number('vx');
    final vy = number('vy');
    final hp = number('hp');
    final targetHp = number('targetHp');
    final ki = number('ki');
    final round = (snapshot['round'] as num?)?.toInt();
    final remoteSenderWins = (snapshot['playerWins'] as num?)?.toInt();
    final remoteReceiverWins = (snapshot['opponentWins'] as num?)?.toInt();
    final remoteState = snapshot['matchState'] as String?;

    if (x != null && y != null) {
      final newTarget = Vector2(x, y);
      bot.targetPosition = newTarget;
    }
    if (vx != null && vy != null) {
      bot.targetVelocity = Vector2(vx, vy);
    }
    // Snapshot của hiệp cũ (bên kia chưa kịp sang hiệp mới) không được dùng để
    // cập nhật máu, nếu không máu hiệp trước sẽ "đè" lên hiệp mới.
    final isStaleRound = round != null && round < currentRound;
    if (hp != null && !isStaleRound) {
      if (round != null && round > currentRound) {
        bot.currentHp = hp.clamp(0, bot.maxHp);
      } else {
        bot.currentHp = min(bot.currentHp, hp.clamp(0, bot.maxHp));
      }
    }

    // Đồng bộ sát thương đối thủ đã gây ra lên người chơi cục bộ (targetHp)
    if (targetHp != null &&
        !isStaleRound &&
        (round == null || round == currentRound) &&
        matchState == PvpMatchState.fighting) {
      if (targetHp < player.currentHp) {
        player.currentHp = targetHp.clamp(0, player.maxHp);
      }
    }

    if (ki != null && !isStaleRound) bot.currentKi = ki.clamp(0, bot.maxKi);
    bot.isFacingRight = snapshot['facingRight'] as bool? ?? bot.isFacingRight;
    bot.isBerserk = snapshot['berserk'] as bool? ?? bot.isBerserk;
    bot.isAttacking = snapshot['attacking'] as bool? ?? bot.isAttacking;
    if (snapshot['speech'] is String) {
      bot.speechBubbleText = snapshot['speech'] as String;
    }

    // Đồng bộ kết thúc Hiệp (Round End) & kết thúc Trận (Match Finished) giữa 2 máy:
    // Từ góc nhìn của máy hiện tại:
    // - remoteSenderWins (playerWins của đối thủ) chính là opponentWins của mình.
    // - remoteReceiverWins (opponentWins của đối thủ) chính là playerWins của mình.
    if (remoteSenderWins != null &&
        remoteReceiverWins != null &&
        matchState != PvpMatchState.matchFinished) {
      final remoteTotalRounds = remoteSenderWins + remoteReceiverWins;
      final localTotalRounds = playerWins + opponentWins;

      if (remoteTotalRounds > localTotalRounds &&
          matchState == PvpMatchState.fighting) {
        if (remoteSenderWins > opponentWins) {
          player.currentHp = 0;
          lastRoundPlayerWon = false;
        } else if (remoteReceiverWins > playerWins) {
          bot.currentHp = 0;
          lastRoundPlayerWon = true;
        }
        playerWins = remoteReceiverWins;
        opponentWins = remoteSenderWins;
        matchState = PvpMatchState.roundEnd;
        stateTimer = 2.5;
      }

      if (remoteState == PvpMatchState.matchFinished.name &&
          (remoteSenderWins >= 2 || remoteReceiverWins >= 2) &&
          matchState != PvpMatchState.matchFinished) {
        playerWins = remoteReceiverWins;
        opponentWins = remoteSenderWins;
        if (opponentWins > playerWins) {
          player.currentHp = 0;
          lastRoundPlayerWon = false;
        } else {
          bot.currentHp = 0;
          lastRoundPlayerWon = true;
        }
        _concludeMatch();
        return;
      }
    }

    // Nếu toàn bộ đội xanh hoặc đội đỏ vừa bị hạ gục về 0 HP trong hiệp đang đánh -> phân định hiệp ngay (1v1, 2v2, 4v4)
    final blueWiped =
        player.currentHp <= 0 && allies.every((a) => a.currentHp <= 0);
    final redWiped = allEnemies.every((e) => e.currentHp <= 0);
    if (matchState == PvpMatchState.fighting && (blueWiped || redWiped)) {
      _adjudicateRound();
      return;
    }

    onStateChanged?.call();
  }

  void applyOpponentAction(String action, {String? text}) {
    switch (action) {
      case 'basicAttack':
        bot.performBasicAttack(force: true);
        break;
      case 'skill1':
        bot.executeSkill1(force: true);
        break;
      case 'skill2':
        bot.executeSkill2(force: true);
        break;
      case 'skill3':
        bot.executeSkill3(force: true);
        break;
      case 'quickChat':
        if (text != null) bot.say(text);
        break;
    }
    onStateChanged?.call();
  }

  Map<String, Object?> get localSnapshot {
    final effectiveSpeed = player.isBerserk ? player.speed * 1.5 : player.speed;
    final vx = player.moveDirection.x * effectiveSpeed;
    final vy = player.moveDirection.y * effectiveSpeed;

    final map = <String, Object?>{
      'x': double.parse(player.position.x.toStringAsFixed(1)),
      'y': double.parse(player.position.y.toStringAsFixed(1)),
      'vx': double.parse(vx.toStringAsFixed(1)),
      'vy': double.parse(vy.toStringAsFixed(1)),
      'dirX': double.parse(player.moveDirection.x.toStringAsFixed(2)),
      'dirY': double.parse(player.moveDirection.y.toStringAsFixed(2)),
      'hp': player.currentHp,
      'targetHp': bot.currentHp,
      'ki': player.currentKi,
      'facingRight': player.isFacingRight,
      'berserk': player.isBerserk,
      'attacking': player.isAttacking,
      'round': currentRound,
      'playerWins': playerWins,
      'opponentWins': opponentWins,
      'matchState': matchState.name,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (player.speechBubbleText != null &&
        player.speechBubbleText!.isNotEmpty) {
      map['speech'] = player.speechBubbleText!;
    }
    return map;
  }

  // --- PARTY CO-OP SYNC (ĐỒNG BỘ ĐỒNG ĐỘI & CHỦ PHÒNG TRONG CÙNG 1 TRẬN) ---

  void applyPartyAllySnapshot(
    String memberCode,
    Map<String, dynamic> snapshot,
  ) {
    final ally = _humanAlliesByCode[memberCode.trim().toUpperCase()];
    if (ally == null) return;

    double? number(String key) => (snapshot[key] as num?)?.toDouble();
    final x = number('x');
    final y = number('y');
    final vx = number('vx');
    final vy = number('vy');
    final hp = number('hp');
    final ki = number('ki');

    if (x != null && y != null) {
      ally.targetPosition = Vector2(x, y);
    }
    if (vx != null && vy != null) {
      ally.targetVelocity = Vector2(vx, vy);
    }
    if (hp != null) {
      ally.currentHp = hp.clamp(0, ally.maxHp);
    }
    if (ki != null) {
      ally.currentKi = ki.clamp(0, ally.maxKi);
    }
    ally.isFacingRight = snapshot['facingRight'] as bool? ?? ally.isFacingRight;
    ally.isBerserk = snapshot['berserk'] as bool? ?? ally.isBerserk;
    ally.isAttacking = snapshot['attacking'] as bool? ?? ally.isAttacking;
    if (snapshot['speech'] is String) {
      ally.say(snapshot['speech'] as String);
    }
    onStateChanged?.call();
  }

  void applyPartyAllyAction(String memberCode, String action, {String? text}) {
    final ally = _humanAlliesByCode[memberCode.trim().toUpperCase()];
    if (ally == null) return;

    switch (action) {
      case 'basicAttack':
        ally.performBasicAttack(force: true);
        break;
      case 'skill1':
        ally.executeSkill1(force: true);
        break;
      case 'skill2':
        ally.executeSkill2(force: true);
        break;
      case 'skill3':
        ally.executeSkill3(force: true);
        break;
      case 'quickChat':
        if (text != null) ally.say(text);
        break;
    }
    onStateChanged?.call();
  }

  Map<String, Object?> get partyHostSnapshot {
    final enemiesData = allEnemies
        .map(
          (e) => <String, Object?>{
            'x': double.parse(e.position.x.toStringAsFixed(1)),
            'y': double.parse(e.position.y.toStringAsFixed(1)),
            'vx': double.parse(
              (e.moveDirection.x * e.speed).toStringAsFixed(1),
            ),
            'vy': double.parse(
              (e.moveDirection.y * e.speed).toStringAsFixed(1),
            ),
            'hp': e.currentHp,
            'ki': e.currentKi,
            'facingRight': e.isFacingRight,
            'berserk': e.isBerserk,
            'attacking': e.isAttacking,
          },
        )
        .toList();

    final aiAlliesData = <int, Map<String, Object?>>{};
    for (int i = 0; i < allies.length; i++) {
      if (humanAllyCodes.containsKey(i)) continue;
      final a = allies[i];
      aiAlliesData[i] = {
        'x': double.parse(a.position.x.toStringAsFixed(1)),
        'y': double.parse(a.position.y.toStringAsFixed(1)),
        'vx': double.parse((a.moveDirection.x * a.speed).toStringAsFixed(1)),
        'vy': double.parse((a.moveDirection.y * a.speed).toStringAsFixed(1)),
        'hp': a.currentHp,
        'ki': a.currentKi,
        'facingRight': a.isFacingRight,
        'berserk': a.isBerserk,
        'attacking': a.isAttacking,
      };
    }

    return {
      'round': currentRound,
      'playerWins': playerWins,
      'opponentWins': opponentWins,
      'matchState': matchState.name,
      'roundTimeRemaining': roundTimeRemaining,
      'lastRoundPlayerWon': lastRoundPlayerWon,
      'localHp': player.currentHp,
      'enemies': enemiesData,
      'aiAllies': aiAlliesData.map((k, v) => MapEntry('$k', v)),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void applyPartyHostState(Map<String, dynamic> hostState) {
    if (!isPartyGuest) return;
    final enemiesRaw = hostState['enemies'];
    if (enemiesRaw is List) {
      for (int i = 0; i < enemiesRaw.length && i < allEnemies.length; i++) {
        final raw = enemiesRaw[i];
        if (raw is! Map) continue;
        final m = raw.map((k, v) => MapEntry(k.toString(), v));
        final enemy = allEnemies[i];
        final x = (m['x'] as num?)?.toDouble();
        final y = (m['y'] as num?)?.toDouble();
        final vx = (m['vx'] as num?)?.toDouble();
        final vy = (m['vy'] as num?)?.toDouble();
        final hp = (m['hp'] as num?)?.toDouble();
        final ki = (m['ki'] as num?)?.toDouble();
        if (x != null && y != null) enemy.targetPosition = Vector2(x, y);
        if (vx != null && vy != null) enemy.targetVelocity = Vector2(vx, vy);
        if (hp != null) enemy.currentHp = hp.clamp(0, enemy.maxHp);
        if (ki != null) enemy.currentKi = ki.clamp(0, enemy.maxKi);
        enemy.isFacingRight = m['facingRight'] as bool? ?? enemy.isFacingRight;
        enemy.isBerserk = m['berserk'] as bool? ?? enemy.isBerserk;
        enemy.isAttacking = m['attacking'] as bool? ?? enemy.isAttacking;
      }
    }

    final aiAlliesRaw = hostState['aiAllies'];
    if (aiAlliesRaw is Map) {
      aiAlliesRaw.forEach((key, raw) {
        final idx = int.tryParse(key.toString());
        if (idx == null || idx < 0 || idx >= allies.length || raw is! Map) {
          return;
        }
        final m = raw.map((k, v) => MapEntry(k.toString(), v));
        final ally = allies[idx];
        final x = (m['x'] as num?)?.toDouble();
        final y = (m['y'] as num?)?.toDouble();
        final vx = (m['vx'] as num?)?.toDouble();
        final vy = (m['vy'] as num?)?.toDouble();
        final hp = (m['hp'] as num?)?.toDouble();
        if (x != null && y != null) ally.targetPosition = Vector2(x, y);
        if (vx != null && vy != null) ally.targetVelocity = Vector2(vx, vy);
        if (hp != null) ally.currentHp = hp.clamp(0, ally.maxHp);
        ally.isFacingRight = m['facingRight'] as bool? ?? ally.isFacingRight;
        ally.isAttacking = m['attacking'] as bool? ?? ally.isAttacking;
      });
    }

    final hostRound = (hostState['round'] as num?)?.toInt();
    final hostPlayerWins = (hostState['playerWins'] as num?)?.toInt();
    final hostOpponentWins = (hostState['opponentWins'] as num?)?.toInt();
    final hostMatchState = hostState['matchState'] as String?;

    if (hostRound != null && hostRound > currentRound) {
      currentRound = hostRound - 1;
      _startNextRound();
    }

    if (hostPlayerWins != null && hostOpponentWins != null) {
      playerWins = hostPlayerWins;
      opponentWins = hostOpponentWins;
    }

    if (hostMatchState == PvpMatchState.roundEnd.name &&
        matchState == PvpMatchState.fighting) {
      lastRoundPlayerWon = hostState['lastRoundPlayerWon'] as bool? ?? true;
      matchState = PvpMatchState.roundEnd;
      stateTimer = 2.5;
    } else if (hostMatchState == PvpMatchState.matchFinished.name &&
        matchState != PvpMatchState.matchFinished) {
      _concludeMatch();
      return;
    }

    onStateChanged?.call();
  }
}
