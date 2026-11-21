import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import '../models/player_profile.dart';
import '../registry/asset_registry.dart';
import '../services/audio_service.dart';
import '../services/player_storage.dart';
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
  BossEnemy? boss;
  CompanionComponent? companion;

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

    // Kiểm tra quét sạch toàn bộ quái và Boss -> Kích hoạt Chiến Thắng Vượt Ải
    final isBossDefeated = boss == null || boss!.isDefeated || !boss!.isMounted;
    if (!isVictoryTriggered && enemies.isEmpty && skeletons.isEmpty && isBossDefeated) {
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

    if (boss != null && boss!.isMounted) {
      boss!.removeFromParent();
    }
    boss = null;
    bossHpNotifier.value = null;
  }

  @override
  void onRemove() {
    AudioService.instance.stopBgm();
    companion?.cleanup();
    super.onRemove();
  }

  void _spawnZombies({int floor = 1}) {
    final List<Vector2> spawnPoints;
    if (currentMapConfig.monsterPortals.isNotEmpty) {
      spawnPoints = currentMapConfig.monsterPortals.map((p) =>
        Vector2((p[0] + 0.5) * 32.0, (p[1] + 0.5) * 32.0)
      ).toList();
      spawnPoints.add(Vector2(540, 360));
    } else {
      spawnPoints = [
        Vector2(200, 200),
        Vector2(650, 220),
        Vector2(250, 500),
        Vector2(700, 520),
        Vector2(500, 450),
      ];
    }

    final multiplier = 1.0 + (floor - 1) * 0.2;
    for (final pt in spawnPoints) {
      final zombie = ZombieEnemy(position: pt, player: player);
      zombie.maxHp = 60.0 * multiplier;
      zombie.currentHp = zombie.maxHp;
      zombie.damage = 10.0 * multiplier;
      enemies.add(zombie);
      world.add(zombie);
    }
  }

  void _spawnSkeletons({int floor = 1}) {
    final List<Vector2> spawnPoints;
    if (currentMapConfig.monsterPortals.length >= 2) {
      spawnPoints = [
        Vector2((currentMapConfig.monsterPortals.first[0] + 0.5) * 32.0,
                (currentMapConfig.monsterPortals.first[1] + 1.2) * 32.0),
        Vector2((currentMapConfig.monsterPortals.last[0] + 0.5) * 32.0,
                (currentMapConfig.monsterPortals.last[1] - 1.2) * 32.0),
        Vector2(450, 420),
      ];
    } else {
      spawnPoints = [
        Vector2(320, 180),
        Vector2(850, 320),
        Vector2(450, 560),
      ];
    }

    final multiplier = 1.0 + (floor - 1) * 0.2;
    for (final pt in spawnPoints) {
      final skeleton = SkeletonEnemy(position: pt, player: player);
      skeleton.maxHp = 45.0 * multiplier;
      skeleton.currentHp = skeleton.maxHp;
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
    boss = BossEnemy(position: Vector2(bX, bY), player: player);
    if (floor > 1) {
      final multiplier = 1.0 + (floor - 1) * 0.25;
      boss!.maxHp = 500.0 * multiplier;
      boss!.currentHp = boss!.maxHp;
    }
    world.add(boss!);
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
      if (boss != null && boss!.isMounted && !boss!.isDefeated) {
        final d = player.position.distanceTo(boss!.position);
        if (d < closestDist) {
          closestDist = d;
          targetDir = (boss!.position - player.position).normalized();
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
      final dmg = player.damage * (isCombo3 ? 1.4 : 1.0);
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
    final dmg = player.damage;

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

    if (boss != null && boss!.isMounted && !boss!.isDefeated) {
      final distance = player.position.distanceTo(boss!.position);
      if (distance <= attackRange + 15.0) {
        boss!.takeDamage(dmg);
        _spawnDamageNumber(
          boss!.position,
          dmg.toInt(),
          isCombo3 ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
        );
      }
    }
  }

  void onSkill1() {
    if (!player.useSkill1()) return;

    // Búa Cuồng Phong / Lôi Ảnh Trảm: Quét 360 độ (bán kính 85px)
    const aoeRadius = 85.0;
    final skillDmg = player.damage * 1.8;
    for (final enemy in List<ZombieEnemy>.from(enemies)) {
      if (!enemy.isMounted) {
        enemies.remove(enemy);
        continue;
      }
      final distance = player.position.distanceTo(enemy.position);
      if (distance <= aoeRadius) {
        enemy.takeDamage(skillDmg);
        _spawnDamageNumber(enemy.position, skillDmg.toInt(), CombatTextType.skillDamage);
      }
    }

    for (final skeleton in List<SkeletonEnemy>.from(skeletons)) {
      if (!skeleton.isMounted) {
        skeletons.remove(skeleton);
        continue;
      }
      final distance = player.position.distanceTo(skeleton.position);
      if (distance <= aoeRadius) {
        skeleton.takeDamage(skillDmg);
        _spawnDamageNumber(skeleton.position, skillDmg.toInt(), CombatTextType.skillDamage);
      }
    }

    if (boss != null && boss!.isMounted && !boss!.isDefeated) {
      final distance = player.position.distanceTo(boss!.position);
      if (distance <= aoeRadius + 15.0) {
        boss!.takeDamage(skillDmg);
        _spawnDamageNumber(boss!.position, skillDmg.toInt(), CombatTextType.skillDamage);
      }
    }
  }

  void onSkill2() {
    if (!player.useSkill2()) return;

    // Nện Đất / Lôi Điện Hộ Thể: Chấn động cực mạnh (bán kính 110px)
    const aoeRadius = 110.0;
    final skillDmg = player.damage * 2.5;
    for (final enemy in List<ZombieEnemy>.from(enemies)) {
      if (!enemy.isMounted) {
        enemies.remove(enemy);
        continue;
      }
      final distance = player.position.distanceTo(enemy.position);
      if (distance <= aoeRadius) {
        enemy.takeDamage(skillDmg);
        _spawnDamageNumber(enemy.position, skillDmg.toInt(), CombatTextType.criticalDamage);
      }
    }

    for (final skeleton in List<SkeletonEnemy>.from(skeletons)) {
      if (!skeleton.isMounted) {
        skeletons.remove(skeleton);
        continue;
      }
      final distance = player.position.distanceTo(skeleton.position);
      if (distance <= aoeRadius) {
        skeleton.takeDamage(skillDmg);
        _spawnDamageNumber(skeleton.position, skillDmg.toInt(), CombatTextType.criticalDamage);
      }
    }

    if (boss != null && boss!.isMounted && !boss!.isDefeated) {
      final distance = player.position.distanceTo(boss!.position);
      if (distance <= aoeRadius + 15.0) {
        boss!.takeDamage(skillDmg);
        _spawnDamageNumber(boss!.position, skillDmg.toInt(), CombatTextType.criticalDamage);
      }
    }
  }

  void onSkill3() {
    if (player.useSkill3()) {
      final hero = player.heroId;
      String ultText = 'CUỒNG NỘ!';
      switch (hero) {
        case 'nova_blade':
          ultText = 'QUANTUM BURST!';
          break;
        case 'valeria':
          ultText = 'MƯA THIÊN THẠCH BĂNG HỎA!';
          break;
        case 'garrick':
          ultText = 'NỘI ĐỊA CHẤN!';
          break;
        case 'shadow_01':
        case 'shadow':
          ultText = 'PHANTOM DASH!';
          break;
        case 'ember_02':
        case 'ember':
          ultText = 'THÁI DƯƠNG BỘC PHÁ!';
          break;
      }

      if (hero != 'george' &&
          hero != 'ranger' &&
          hero != 'tanker' &&
          hero != 'ninja') {
        const ultRadius = 160.0;
        final ultDmg = player.damage * 2.5;
        for (final enemy in List<ZombieEnemy>.from(enemies)) {
          if (!enemy.isMounted) continue;
          if (player.position.distanceTo(enemy.position) <= ultRadius) {
            enemy.takeDamage(ultDmg);
            _spawnDamageNumber(
              enemy.position,
              ultDmg.toInt(),
              CombatTextType.criticalDamage,
            );
          }
        }
        for (final skeleton in List<SkeletonEnemy>.from(skeletons)) {
          if (!skeleton.isMounted) continue;
          if (player.position.distanceTo(skeleton.position) <= ultRadius) {
            skeleton.takeDamage(ultDmg);
            _spawnDamageNumber(
              skeleton.position,
              ultDmg.toInt(),
              CombatTextType.criticalDamage,
            );
          }
        }
        if (boss != null && boss!.isMounted && !boss!.isDefeated) {
          if (player.position.distanceTo(boss!.position) <= ultRadius + 20.0) {
            boss!.takeDamage(ultDmg);
            _spawnDamageNumber(
              boss!.position,
              ultDmg.toInt(),
              CombatTextType.criticalDamage,
            );
          }
        }
      }

      if (isLoaded) {
        world.add(FloatingCombatText(
          position: player.position,
          text: ultText,
          type: CombatTextType.buff,
        ));
      }
    }
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
          text: 'TRƯỜNG TRỌNG LỰC HOÀNG KIM!',
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
