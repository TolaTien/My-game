import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import '../models/player_profile.dart';
import '../registry/asset_registry.dart';
import '../services/audio_service.dart';
import '../services/player_storage.dart';
import 'combat/hero_skill_system.dart';
import 'components/dungeon_map.dart';
import 'components/player.dart';
import 'components/enemy_zombie.dart';
import 'components/enemy_skeleton.dart';
import 'components/pickup_item.dart';
import 'components/boss_enemy.dart';
import 'components/companion_component.dart';
import 'components/floating_combat_text.dart';
import 'components/hero_projectile.dart';

class BigWarGame extends FlameGame with HasCollisionDetection {
  final PlayerProfile? playerProfile;
  final MapAssetConfig? selectedMapConfig;
  late MapAssetConfig currentMapConfig;

  late final PlayerComponent player;
  late DungeonMapComponent dungeonMap;
  final List<BossEnemy> bosses = [];
  BossEnemy? get boss {
    for (final b in bosses) {
      if (!b.isDefeated && b.isMounted) return b;
    }
    return bosses.isNotEmpty ? bosses.first : null;
  }
  CompanionComponent? companion;

  /// Số lượng Boss tăng dần theo tầng (T1-2: 1, T3-5: 2, T6-8: 3, T9+: 4)
  static int bossCountForFloor(int floor) {
    if (floor <= 2) return 1;
    if (floor <= 5) return 2;
    if (floor <= 8) return 3;
    return 4;
  }

  /// Số Zombie cộng thêm mỗi tầng (+1/tầng, tối đa +6)
  static int extraZombiesForFloor(int floor) => max(0, min(6, floor - 1));

  /// Số Skeleton cộng thêm theo tầng (+1 mỗi 2 tầng, tối đa +4)
  static int extraSkeletonsForFloor(int floor) => max(0, min(4, (floor - 1) ~/ 2));

  void scaleZombieForFloor(ZombieEnemy zombie, int floor) {
    final f = max(1, floor);
    final hpMult = 1.0 + (f - 1) * 0.30;
    final dmgMult = 1.0 + (f - 1) * 0.25;
    final speedMult = min(1.40, 1.0 + (f - 1) * 0.05);
    zombie.maxHp = 60.0 * hpMult;
    zombie.currentHp = zombie.maxHp;
    zombie.damage = 12.0 * dmgMult;
    zombie.speed = 65.0 * speedMult;
  }

  void scaleSkeletonForFloor(SkeletonEnemy skeleton, int floor) {
    final f = max(1, floor);
    final hpMult = 1.0 + (f - 1) * 0.30;
    final dmgMult = 1.0 + (f - 1) * 0.25;
    final speedMult = min(1.40, 1.0 + (f - 1) * 0.05);
    skeleton.maxHp = 45.0 * hpMult;
    skeleton.currentHp = skeleton.maxHp;
    skeleton.speed = 50.0 * speedMult;
    skeleton.arrowDamage = 10.0 * dmgMult;
    skeleton.arrowSpeed = 220.0 * min(1.30, 1.0 + (f - 1) * 0.04);
    skeleton.shootInterval = max(1.1, 1.8 - (f - 1) * 0.08);
  }

  void refreshBossHud() {
    if (bosses.isEmpty) {
      bossHpNotifier.value = null;
      return;
    }
    double totalHp = 0.0;
    double totalMaxHp = 0.0;
    int aliveCount = 0;
    bool anyEnraged = false;
    int maxPhase = 1;
    for (final b in bosses) {
      totalMaxHp += b.maxHp;
      if (!b.isDefeated) {
        aliveCount++;
        totalHp += b.currentHp;
        if (b.isEnraged) anyEnraged = true;
        if (b.phase > maxPhase) maxPhase = b.phase;
      }
    }
    final title = bosses.length > 1
        ? 'CHÚA TỂ HẦM NGỤC • TẦNG $currentFloor ($aliveCount/${bosses.length} BOSS)'
        : 'CHÚA TỂ HẦM NGỤC • TẦNG $currentFloor';
    bossHpNotifier.value = BossHpData(
      currentHp: totalHp,
      maxHp: totalMaxHp > 0 ? totalMaxHp : 1.0,
      phase: maxPhase,
      isEnraged: anyEnraged,
      isDefeated: aliveCount == 0,
      title: title,
    );
  }

  final List<ZombieEnemy> enemies = [];
  final List<SkeletonEnemy> skeletons = [];
  final List<PickupItem> pickups = [];

  // Reactive notifier cho Boss Health Bar HUD
  final ValueNotifier<BossHpData?> bossHpNotifier = ValueNotifier(null);

  // Callback thông báo cho Flutter HUD khi Player thay đổi stats
  Function()? onPlayerStatsChanged;

  // Callback thông báo cho Flutter HUD khi đổi map / chuyển tầng
  Function()? onMapChanged;

  // Callback chiến thắng màn chơi khi quét sạch quái hoặc vào portal
  Function()? onVictory;

  // Callback khi Player tử trận
  Function()? onGameOver;

  int currentFloor = 1;
  bool isVictoryTriggered = false;
  bool isGameOverTriggered = false;

  BigWarGame({this.playerProfile, this.selectedMapConfig}) {
    pauseWhenBackgrounded = false;
    currentMapConfig =
        selectedMapConfig ?? GameAssetRegistry.instance.getRandomMap();
    final hero = activeProfile.selectedHeroId;
    final userHeroLv = activeProfile.getHeroLevel(hero);
    player = PlayerComponent(
      position: Vector2(400, 300),
      heroId: hero,
      userHeroLevel: userHeroLv,
    );
  }

  PlayerProfile get activeProfile =>
      playerProfile ?? PlayerStorage.currentProfile;

  List<List<bool>> get walkableGrid => dungeonMap.walkableGrid;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1. Thêm bản đồ hầm ngục
    dungeonMap = DungeonMapComponent(config: currentMapConfig);
    await world.add(dungeonMap);

    // 2. Thêm Player ở tọa độ spawn của bản đồ
    final pSpawnX = currentMapConfig.playerSpawn.isNotEmpty
        ? currentMapConfig.playerSpawn[0] * 32.0
        : 400.0;
    final pSpawnY = currentMapConfig.playerSpawn.length > 1
        ? currentMapConfig.playerSpawn[1] * 32.0
        : 300.0;
    player.position = Vector2(pSpawnX, pSpawnY);
    player.onStatsChanged = () => onPlayerStatsChanged?.call();
    await world.add(player);

    // 3. Thêm một số Zombie quái vật
    _spawnZombies(floor: currentFloor);

    // 4. Thêm Skeleton quái vật cung thủ tầm xa
    _spawnSkeletons(floor: currentFloor);

    // 5. Thêm các vật phẩm rải rác trên bản đồ
    _spawnPickups();

    // 6. Thêm Boss Chúa Tể Hầm Ngục
    _spawnBoss(floor: currentFloor);

    // 7. Thêm AI Companion Drone nếu người chơi đã trang bị
    final companionId = activeProfile.selectedCompanionId;
    if (companionId != null && companionId.isNotEmpty) {
      companion = CompanionComponent(
        companionId: companionId,
        player: player,
      );
      await world.add(companion!);
    }

    // 8. Cấu hình Camera bám sát theo Player
    camera.follow(player);
    camera.viewfinder.zoom = 1.4; // Zoom vừa vặn chuẩn pixel art trên mobile

    // 9. Bật Dungeon BGM
    AudioService.instance.playBgm(BgmTrack.dungeon);

    // Kích hoạt cập nhật HUD sau khi hoàn tất tải toàn bộ game world
    onPlayerStatsChanged?.call();
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Kiểm tra nhân vật tử trận -> Kích hoạt Thất Bại
    if (!isGameOverTriggered && player.currentHp <= 0) {
      isGameOverTriggered = true;
      AudioService.instance.playSfx(SfxSound.attackHammer);
      onGameOver?.call();
      return;
    }

    // Dọn dẹp quái đã bị tiêu diệt
    enemies.removeWhere((e) => !e.isMounted || e.currentHp <= 0);
    skeletons.removeWhere((s) => !s.isMounted || s.currentHp <= 0);

    // Kiểm tra quét sạch toàn bộ quái và tất cả Boss -> Kích hoạt Chiến Thắng Vượt Ải
    final allBossesDefeated =
        bosses.every((b) => b.isDefeated || !b.isMounted);
    if (!isVictoryTriggered &&
        enemies.isEmpty &&
        skeletons.isEmpty &&
        allBossesDefeated) {
      isVictoryTriggered = true;
      AudioService.instance.playSfx(SfxSound.wheelJackpot);
      onVictory?.call();
    }
  }

  Future<void> _switchDungeonMap(MapAssetConfig newMap) async {
    currentMapConfig = newMap;
    if (dungeonMap.isMounted) {
      dungeonMap.removeFromParent();
    }
    dungeonMap = DungeonMapComponent(config: currentMapConfig);
    await world.add(dungeonMap);
  }

  void advanceToNextFloor({MapAssetConfig? nextMap}) {
    currentFloor++;
    isVictoryTriggered = false;
    isGameOverTriggered = false;

    // Đổi sang một map ngẫu nhiên mới cho tầng tiếp theo (đảm bảo khác map hiện tại)
    final newMap = nextMap ??
        GameAssetRegistry.instance.getRandomMap(excludeId: currentMapConfig.id);
    _switchDungeonMap(newMap);

    // Hồi phục sinh lực và Ki cho tầng mới
    final pSpawnX = currentMapConfig.playerSpawn.isNotEmpty
        ? currentMapConfig.playerSpawn[0] * 32.0
        : 400.0;
    final pSpawnY = currentMapConfig.playerSpawn.length > 1
        ? currentMapConfig.playerSpawn[1] * 32.0
        : 300.0;
    player.position = Vector2(pSpawnX, pSpawnY);
    player.currentHp = player.maxHp;
    player.currentKi = player.maxKi;

    _cleanupFloorEntities();

    // Sinh quái tầng mới mạnh hơn theo cấp tầng
    _spawnZombies(floor: currentFloor);
    _spawnSkeletons(floor: currentFloor);
    _spawnPickups();
    _spawnBoss(floor: currentFloor);

    onPlayerStatsChanged?.call();
    onMapChanged?.call();
  }

  void retryFloor() {
    isVictoryTriggered = false;
    isGameOverTriggered = false;

    // Khi chơi lại, cũng chọn ngẫu nhiên map mới để trải nghiệm phong phú
    final newMap =
        GameAssetRegistry.instance.getRandomMap(excludeId: currentMapConfig.id);
    _switchDungeonMap(newMap);

    final pSpawnX = currentMapConfig.playerSpawn.isNotEmpty
        ? currentMapConfig.playerSpawn[0] * 32.0
        : 400.0;
    final pSpawnY = currentMapConfig.playerSpawn.length > 1
        ? currentMapConfig.playerSpawn[1] * 32.0
        : 300.0;
    player.position = Vector2(pSpawnX, pSpawnY);
    player.currentHp = player.maxHp;
    player.currentKi = player.maxKi;

    _cleanupFloorEntities();

    _spawnZombies(floor: currentFloor);
    _spawnSkeletons(floor: currentFloor);
    _spawnPickups();
    _spawnBoss(floor: currentFloor);

    onPlayerStatsChanged?.call();
    onMapChanged?.call();
  }

  void _cleanupFloorEntities() {
    companion?.resetForFloor();
    for (final e in List<ZombieEnemy>.from(enemies)) {
      if (e.isMounted) e.removeFromParent();
    }
    enemies.clear();

    for (final s in List<SkeletonEnemy>.from(skeletons)) {
      if (s.isMounted) s.removeFromParent();
    }
    skeletons.clear();

    for (final p in List<PickupItem>.from(pickups)) {
      if (p.isMounted) p.removeFromParent();
    }
    pickups.clear();

    for (final b in List<BossEnemy>.from(bosses)) {
      if (b.isMounted) b.removeFromParent();
    }
    bosses.clear();
    bossHpNotifier.value = null;
  }

  @override
  void onRemove() {
    AudioService.instance.stopBgm();
    companion?.cleanup();
    super.onRemove();
  }

  void _spawnZombies({int floor = 1}) {
    final List<Vector2> basePoints;
    if (currentMapConfig.monsterPortals.isNotEmpty) {
      basePoints = currentMapConfig.monsterPortals
          .map((p) => Vector2((p[0] + 0.5) * 32.0, (p[1] + 0.5) * 32.0))
          .toList();
      basePoints.add(Vector2(540, 360));
    } else {
      basePoints = [
        Vector2(200, 200),
        Vector2(650, 220),
        Vector2(250, 500),
        Vector2(700, 520),
        Vector2(500, 450),
      ];
    }

    final totalCount = basePoints.length + extraZombiesForFloor(floor);
    final maxW = max(200.0, currentMapConfig.cols * currentMapConfig.tileSize.toDouble() - 64.0);
    final maxH = max(200.0, currentMapConfig.rows * currentMapConfig.tileSize.toDouble() - 64.0);

    for (int i = 0; i < totalCount; i++) {
      final base = basePoints[i % basePoints.length];
      final ring = i ~/ basePoints.length;
      final offset = ring == 0
          ? Vector2.zero()
          : Vector2(cos(i * 1.7) * 44.0 * ring, sin(i * 1.7) * 44.0 * ring);
      final pt = Vector2(
        (base.x + offset.x).clamp(64.0, maxW),
        (base.y + offset.y).clamp(64.0, maxH),
      );
      final zombie = ZombieEnemy(position: pt, player: player);
      scaleZombieForFloor(zombie, floor);
      enemies.add(zombie);
      world.add(zombie);
    }
  }

  void _spawnSkeletons({int floor = 1}) {
    final List<Vector2> basePoints;
    if (currentMapConfig.monsterPortals.length >= 2) {
      basePoints = [
        Vector2((currentMapConfig.monsterPortals.first[0] + 0.5) * 32.0,
            (currentMapConfig.monsterPortals.first[1] + 1.2) * 32.0),
        Vector2((currentMapConfig.monsterPortals.last[0] + 0.5) * 32.0,
            (currentMapConfig.monsterPortals.last[1] - 1.2) * 32.0),
        Vector2(450, 420),
      ];
    } else {
      basePoints = [
        Vector2(320, 180),
        Vector2(850, 320),
        Vector2(450, 560),
      ];
    }

    final totalCount = basePoints.length + extraSkeletonsForFloor(floor);
    final maxW = max(200.0, currentMapConfig.cols * currentMapConfig.tileSize.toDouble() - 64.0);
    final maxH = max(200.0, currentMapConfig.rows * currentMapConfig.tileSize.toDouble() - 64.0);

    for (int i = 0; i < totalCount; i++) {
      final base = basePoints[i % basePoints.length];
      final ring = i ~/ basePoints.length;
      final offset = ring == 0
          ? Vector2.zero()
          : Vector2(cos(i * 2.1) * 48.0 * ring, sin(i * 2.1) * 48.0 * ring);
      final pt = Vector2(
        (base.x + offset.x).clamp(64.0, maxW),
        (base.y + offset.y).clamp(64.0, maxH),
      );
      final skeleton = SkeletonEnemy(position: pt, player: player);
      scaleSkeletonForFloor(skeleton, floor);
      skeletons.add(skeleton);
      world.add(skeleton);
    }
  }

  void _spawnBoss({int floor = 1}) {
    final bX = currentMapConfig.bossSpawn.isNotEmpty
        ? currentMapConfig.bossSpawn[0] * 32.0
        : 920.0;
    final bY = currentMapConfig.bossSpawn.length > 1
        ? currentMapConfig.bossSpawn[1] * 32.0
        : 380.0;
    final maxW = max(240.0, currentMapConfig.cols * currentMapConfig.tileSize.toDouble() - 80.0);
    final maxH = max(240.0, currentMapConfig.rows * currentMapConfig.tileSize.toDouble() - 80.0);

    final count = bossCountForFloor(floor);
    final offsets = <Vector2>[
      Vector2.zero(),
      Vector2(-110, -85),
      Vector2(-110, 85),
      Vector2(-200, 0),
    ];

    for (int i = 0; i < count; i++) {
      final off = offsets[i % offsets.length];
      final pos = Vector2(
        (bX + off.x).clamp(80.0, maxW),
        (bY + off.y).clamp(80.0, maxH),
      );
      final spawnedBoss = BossEnemy(position: pos, player: player);
      spawnedBoss.applyFloorDifficulty(floor);
      bosses.add(spawnedBoss);
      world.add(spawnedBoss);
    }
    refreshBossHud();
  }

  void _spawnPickups() {
    final List<(Vector2, PickupType)> pickupSpawns;
    if (currentMapConfig.buffNodes.isNotEmpty) {
      pickupSpawns = [];
      for (int i = 0; i < currentMapConfig.buffNodes.length; i++) {
        final node = currentMapConfig.buffNodes[i];
        final pos = Vector2((node[0] + 0.5) * 32.0, (node[1] + 0.5) * 32.0);
        final type = i == 0
            ? PickupType.healthPotion
            : (i % 2 == 1 ? PickupType.goldCoin : PickupType.expGem);
        pickupSpawns.add((pos, type));
      }
      if (currentMapConfig.buffNodes.length >= 2) {
        final midNode = currentMapConfig.buffNodes[1];
        pickupSpawns.add((
          Vector2((midNode[0] + 2.0) * 32.0, (midNode[1] + 0.5) * 32.0),
          PickupType.goldCoin,
        ));
      }
    } else {
      pickupSpawns = [
        (Vector2(160, 360), PickupType.healthPotion),
        (Vector2(550, 180), PickupType.expGem),
        (Vector2(750, 400), PickupType.expGem),
        (Vector2(350, 420), PickupType.goldCoin),
        (Vector2(900, 200), PickupType.goldCoin),
        (Vector2(600, 550), PickupType.goldCoin),
      ];
    }

    for (final (pt, type) in pickupSpawns) {
      final item = PickupItem(position: pt, type: type);
      pickups.add(item);
      world.add(item);
    }
  }

  // --- ĐIỀU KHIỂN TỪ JOYSTICK & HUD ---

  void setPlayerMoveDirection(Vector2 direction) {
    player.moveDirection = direction;
  }

  void onBasicAttack() {
    player.performBasicAttack();

    final heroId = player.heroId;
    final isRanger = heroId == 'ranger';
    final isEmber = heroId == 'ember_02' || heroId == 'ember';
    final isValeria = heroId == 'valeria';
    final isRanged = isRanger || isEmber || isValeria;

    if (isRanged) {
      if (isRanger) {
        AudioService.instance.playSfx(SfxSound.attackArrow);
      } else {
        AudioService.instance.playSfx(SfxSound.attackHammer);
      }

      // Xác định phương bắn: Ưu tiên quái vật gần nhất trong phạm vi 380px
      Vector2? targetDir;
      double closestDist = 380.0;

      for (final enemy in enemies) {
        if (!enemy.isMounted || enemy.currentHp <= 0) continue;
        final d = player.position.distanceTo(enemy.position);
        if (d < closestDist) {
          closestDist = d;
          targetDir = (enemy.position - player.position).normalized();
        }
      }
      for (final skel in skeletons) {
        if (!skel.isMounted || skel.currentHp <= 0) continue;
        final d = player.position.distanceTo(skel.position);
        if (d < closestDist) {
          closestDist = d;
          targetDir = (skel.position - player.position).normalized();
        }
      }
      for (final b in bosses) {
        if (!b.isMounted || b.isDefeated) continue;
        final d = player.position.distanceTo(b.position);
        if (d < closestDist) {
          closestDist = d;
          targetDir = (b.position - player.position).normalized();
        }
      }

      // Nếu không có mục tiêu trong tầm: Bắn theo hướng di chuyển hoặc hướng đang nhìn
      if (targetDir == null) {
        if (player.moveDirection.length2 > 0) {
          targetDir = player.moveDirection.normalized();
        } else {
          targetDir = Vector2(player.isFacingRight ? 1.0 : -1.0, 0.0);
        }
      } else {
        if (targetDir.x != 0) {
          player.isFacingRight = targetDir.x > 0;
        }
      }

      final isCombo3 = player.comboStep == 3;
      final dmg = player.effectiveDamage * (isCombo3 ? 1.4 : 1.0);
      final pType = isRanger
          ? HeroProjectileType.arrow
          : (isEmber ? HeroProjectileType.fireball : HeroProjectileType.frostOrb);

      final projectile = HeroProjectile(
        position: player.position.clone() + Vector2(0, 2),
        direction: targetDir,
        damage: dmg,
        type: pType,
        isFromPlayer: true,
        onHit: (target, hitPos) {
          _spawnDamageNumber(
            hitPos,
            dmg.toInt(),
            isCombo3 ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
          );
        },
      );

      world.add(projectile);
      return;
    }

    // TƯỚNG CẬN CHIẾN: Gây sát thương quái trong phạm vi cận chiến (55px, hoặc 80px ở đòn combo thứ 3)
    final isCombo3 = player.comboStep == 3;
    final attackRange = isCombo3 ? 80.0 : 55.0;
    final dmg = player.effectiveDamage;

    for (final enemy in List<ZombieEnemy>.from(enemies)) {
      if (!enemy.isMounted) {
        enemies.remove(enemy);
        continue;
      }
      final distance = player.position.distanceTo(enemy.position);
      if (distance <= attackRange) {
        enemy.takeDamage(dmg);
        _spawnDamageNumber(
          enemy.position,
          dmg.toInt(),
          isCombo3 ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
        );
      }
    }

    for (final skeleton in List<SkeletonEnemy>.from(skeletons)) {
      if (!skeleton.isMounted) {
        skeletons.remove(skeleton);
        continue;
      }
      final distance = player.position.distanceTo(skeleton.position);
      if (distance <= attackRange) {
        skeleton.takeDamage(dmg);
        _spawnDamageNumber(
          skeleton.position,
          dmg.toInt(),
          isCombo3 ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
        );
      }
    }

    for (final b in List<BossEnemy>.from(bosses)) {
      if (!b.isMounted || b.isDefeated) continue;
      final distance = player.position.distanceTo(b.position);
      if (distance <= attackRange + 15.0) {
        b.takeDamage(dmg);
        _spawnDamageNumber(
          b.position,
          dmg.toInt(),
          isCombo3 ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
        );
      }
    }
  }

  List<SkillTargetAdapter> _buildPveSkillTargets() {
    final list = <SkillTargetAdapter>[];
    for (final enemy in List<ZombieEnemy>.from(enemies)) {
      if (!enemy.isMounted) continue;
      list.add(SkillTargetAdapter(
        getPosition: () => enemy.position,
        isAlive: () => enemy.isMounted && enemy.currentHp > 0,
        applyDamage: (dmg, textType) {
          enemy.takeDamage(dmg);
          _spawnDamageNumber(enemy.position, dmg.toInt(), textType);
        },
        pushBy: (delta) => enemy.position.add(delta),
      ));
    }
    for (final skel in List<SkeletonEnemy>.from(skeletons)) {
      if (!skel.isMounted) continue;
      list.add(SkillTargetAdapter(
        getPosition: () => skel.position,
        isAlive: () => skel.isMounted && skel.currentHp > 0,
        applyDamage: (dmg, textType) {
          skel.takeDamage(dmg);
          _spawnDamageNumber(skel.position, dmg.toInt(), textType);
        },
        pushBy: (delta) => skel.position.add(delta),
      ));
    }
    for (final b in List<BossEnemy>.from(bosses)) {
      if (!b.isMounted || b.isDefeated) continue;
      list.add(SkillTargetAdapter(
        getPosition: () => b.position,
        isAlive: () => b.isMounted && !b.isDefeated,
        applyDamage: (dmg, textType) {
          b.takeDamage(dmg);
          _spawnDamageNumber(b.position, dmg.toInt(), textType);
        },
        extraHitRadius: 18.0,
      ));
    }
    return list;
  }

  void _clampPlayerToDungeon(Vector2 pos) {
    final maxW = currentMapConfig.cols * currentMapConfig.tileSize.toDouble() - 48.0;
    final maxH = currentMapConfig.rows * currentMapConfig.tileSize.toDouble() - 48.0;
    pos.x = pos.x.clamp(48.0, maxW > 48.0 ? maxW : 48.0);
    pos.y = pos.y.clamp(48.0, maxH > 48.0 ? maxH : 48.0);
  }

  void _executeHeroSkillSlot(int slot) {
    HeroSkillSystem.executeSkill(
      slot: slot,
      player: player,
      world: world,
      targets: _buildPveSkillTargets(),
      onDamageText: _spawnDamageNumber,
      onBannerText: (pos, text) {
        if (isLoaded) {
          world.add(FloatingCombatText(
            position: pos,
            text: text,
            type: CombatTextType.buff,
          ));
        }
      },
      clampPlayerPos: _clampPlayerToDungeon,
    );
  }

  void onSkill1() {
    if (!player.useSkill1()) return;
    _executeHeroSkillSlot(1);
  }

  void onSkill2() {
    if (!player.useSkill2()) return;
    _executeHeroSkillSlot(2);
  }

  void onSkill3() {
    if (!player.useSkill3()) return;
    _executeHeroSkillSlot(3);
  }

  /// Kích hoạt Kỹ năng Đặc biệt của Trợ thủ (Trường Trọng Lực Hoàng Kim - Aegis-X9)
  void onCompanionSkill() {
    if (activeProfile.selectedCompanionId == null || player.currentHp <= 0 || isGameOverTriggered || isVictoryTriggered) return;
    companion ??= CompanionComponent(
      companionId: activeProfile.selectedCompanionId ?? 'aegis_x9',
      player: player,
    );
    if (!companion!.isMounted && isLoaded) {
      world.add(companion!);
    }
    if (companion!.activateSpecialSkill()) {
      if (isLoaded) {
        world.add(FloatingCombatText(
          position: player.position,
          text: companion!.skillName,
          type: CombatTextType.buff,
        ));
      }
    }
  }

  void _spawnDamageNumber(Vector2 pos, int dmg, CombatTextType type) {
    if (!isLoaded) return;
    world.add(FloatingCombatText(
      position: pos,
      text: '-$dmg',
      type: type,
    ));
  }
}

/// Giữ tương thích ngược cho các module cũ
typedef GoldRushGame = BigWarGame;
