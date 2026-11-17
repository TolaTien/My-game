import 'package:flame/components.dart';

import 'combat/hero_combat.dart';
import 'combat/hero_kit.dart';
import 'combat/combat_targets.dart';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';

import '../models/player_profile.dart';
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

class GoldRushGame extends FlameGame with HasCollisionDetection {
  final PlayerProfile? playerProfile;

  HeroCombat? _heroCombat;
  HeroCombat get heroCombat => _heroCombat ??= HeroCombat(
    owner: player,
    heroId: player.heroId,
    damage: () => player.attackDamage,
    facing: () => player.attackDirection,
    targets: () => <PositionComponent>[...enemies, ...skeletons, ?boss]
        .where((body) => body.isMounted)
        .map(
          (body) => combatTarget(
            body,
            onHit: (damage) {
              _spawnDamageNumber(
                body.position,
                damage.toInt(),
                CombatTextType.skillDamage,
              );
            },
          ),
        )
        .toList(),
    canWalk: (point) => !isLoaded || pointInMap(point, dungeonMap, 1152, 768),
    enabled: () =>
        player.currentHp > 0 && !isVictoryTriggered && !isGameOverTriggered,
    rage: (duration) {
      player.isBerserk = true;
      player.berserkTimer = duration;
    },
    maxHp: player.maxHp,
  );
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

  // Callback chiến thắng màn chơi khi quét sạch quái hoặc vào portal
  Function()? onVictory;

  // Callback khi Player tử trận
  Function()? onGameOver;

  int currentFloor = 1;
  bool isVictoryTriggered = false;
  bool isGameOverTriggered = false;

  GoldRushGame({this.playerProfile}) {
    pauseWhenBackgrounded = false;
    final hero = activeProfile.selectedHeroId;
    final userHeroLv = activeProfile.getHeroLevel(hero);
    player = PlayerComponent(
      position: Vector2(400, 300),
      heroId: hero,
      skinId: activeProfile.selectedSkinId,
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
    dungeonMap = DungeonMapComponent();
    await world.add(dungeonMap);

    // 2. Thêm Player ở tọa độ trung tâm
    player.position = Vector2(400, 300);
    player.onStatsChanged = () => onPlayerStatsChanged?.call();
    await world.add(player);
    await world.add(heroCombat);

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
      companion = CompanionComponent(companionId: companionId, player: player);
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
    if (!isVictoryTriggered &&
        enemies.isEmpty &&
        skeletons.isEmpty &&
        isBossDefeated) {
      isVictoryTriggered = true;
      AudioService.instance.playSfx(SfxSound.wheelJackpot);
      onVictory?.call();
    }
  }

  void advanceToNextFloor() {
    currentFloor++;
    isVictoryTriggered = false;
    isGameOverTriggered = false;

    // Thưởng vàng vượt ải
    player.coinsCollected += 50 * currentFloor;
    PlayerStorage.addGold(50 * currentFloor);

    // Hồi phục sinh lực và Ki cho tầng mới
    player.position = Vector2(400, 300);
    player.currentHp = player.maxHp;
    player.currentKi = player.maxKi;

    _cleanupFloorEntities();

    // Sinh quái tầng mới mạnh hơn theo cấp tầng
    _spawnZombies(floor: currentFloor);
    _spawnSkeletons(floor: currentFloor);
    _spawnPickups();
    _spawnBoss(floor: currentFloor);

    onPlayerStatsChanged?.call();
  }

  void retryFloor() {
    isVictoryTriggered = false;
    isGameOverTriggered = false;

    player.position = Vector2(400, 300);
    player.currentHp = player.maxHp;
    player.currentKi = player.maxKi;

    _cleanupFloorEntities();

    _spawnZombies(floor: currentFloor);
    _spawnSkeletons(floor: currentFloor);
    _spawnPickups();
    _spawnBoss(floor: currentFloor);

    onPlayerStatsChanged?.call();
  }

  void _cleanupFloorEntities() {
    _heroCombat?.reset();
    player.resetCombat();
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
    final spawnPoints = [
      Vector2(200, 200),
      Vector2(650, 220),
      Vector2(250, 500),
      Vector2(700, 520),
      Vector2(500, 450),
    ];

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
    final spawnPoints = [
      Vector2(320, 180),
      Vector2(850, 320),
      Vector2(450, 560),
    ];

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
    boss = BossEnemy(position: Vector2(920, 380), player: player);
    if (floor > 1) {
      final multiplier = 1.0 + (floor - 1) * 0.25;
      boss!.maxHp = 500.0 * multiplier;
      boss!.currentHp = boss!.maxHp;
    }
    world.add(boss!);
  }

  void _spawnPickups() {
    final pickupSpawns = [
      (Vector2(160, 360), PickupType.healthPotion),
      (Vector2(550, 180), PickupType.expGem),
      (Vector2(750, 400), PickupType.expGem),
      (Vector2(350, 420), PickupType.goldCoin),
      (Vector2(900, 200), PickupType.goldCoin),
      (Vector2(600, 550), PickupType.goldCoin),
    ];

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
    if (!player.performBasicAttack()) return;
    if (HeroKit.isSpecialized(player.heroId)) {
      heroCombat.basic(player.comboStep);
      return;
    }

    // Gây sát thương quái trong phạm vi cận chiến (55px, hoặc 80px ở đòn combo thứ 3)
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
          isCombo3
              ? CombatTextType.criticalDamage
              : CombatTextType.normalDamage,
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
          isCombo3
              ? CombatTextType.criticalDamage
              : CombatTextType.normalDamage,
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
          isCombo3
              ? CombatTextType.criticalDamage
              : CombatTextType.normalDamage,
        );
      }
    }
  }

  void onSkill1() {
    if (!player.useSkill1()) return;
    if (HeroKit.isSpecialized(player.heroId)) {
      heroCombat.skill(1);
      return;
    }

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
        _spawnDamageNumber(
          enemy.position,
          skillDmg.toInt(),
          CombatTextType.skillDamage,
        );
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
        _spawnDamageNumber(
          skeleton.position,
          skillDmg.toInt(),
          CombatTextType.skillDamage,
        );
      }
    }

    if (boss != null && boss!.isMounted && !boss!.isDefeated) {
      final distance = player.position.distanceTo(boss!.position);
      if (distance <= aoeRadius + 15.0) {
        boss!.takeDamage(skillDmg);
        _spawnDamageNumber(
          boss!.position,
          skillDmg.toInt(),
          CombatTextType.skillDamage,
        );
      }
    }
  }

  void onSkill2() {
    if (!player.useSkill2()) return;
    if (HeroKit.isSpecialized(player.heroId)) {
      heroCombat.skill(2);
      return;
    }

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
        _spawnDamageNumber(
          enemy.position,
          skillDmg.toInt(),
          CombatTextType.criticalDamage,
        );
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
        _spawnDamageNumber(
          skeleton.position,
          skillDmg.toInt(),
          CombatTextType.criticalDamage,
        );
      }
    }

    if (boss != null && boss!.isMounted && !boss!.isDefeated) {
      final distance = player.position.distanceTo(boss!.position);
      if (distance <= aoeRadius + 15.0) {
        boss!.takeDamage(skillDmg);
        _spawnDamageNumber(
          boss!.position,
          skillDmg.toInt(),
          CombatTextType.criticalDamage,
        );
      }
    }
  }

  void onSkill3() {
    if (player.useSkill3()) {
      if (HeroKit.isSpecialized(player.heroId)) {
        heroCombat.skill(3);
        return;
      }
      final hero = player.heroId;
      String ultText = 'CUỒNG NỘ!';
      switch (hero) {
        case 'kaelen':
          ultText = 'THIÊN PHẠT LÔI NGỤC!';
          break;
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
          ultText = 'PHANTOM DASH!';
          break;
        case 'ember_02':
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
        world.add(
          FloatingCombatText(
            position: player.position,
            text: ultText,
            type: CombatTextType.buff,
          ),
        );
      }
    }
  }

  /// Kích hoạt Kỹ năng Đặc biệt của Trợ thủ (Trường Trọng Lực Hoàng Kim - Aegis-X9)
  void onCompanionSkill() {
    companion ??= CompanionComponent(
      companionId: activeProfile.selectedCompanionId ?? 'aegis_x9',
      player: player,
    );
    if (!companion!.isMounted && isLoaded) {
      world.add(companion!);
    }
    if (companion!.activateSpecialSkill()) {
      if (isLoaded) {
        world.add(
          FloatingCombatText(
            position: player.position,
            text: 'TRƯỜNG TRỌNG LỰC HOÀNG KIM!',
            type: CombatTextType.buff,
          ),
        );
      }
    }
  }

  void _spawnDamageNumber(Vector2 pos, int dmg, CombatTextType type) {
    if (!isLoaded) return;
    world.add(FloatingCombatText(position: pos, text: '-$dmg', type: type));
  }
}
