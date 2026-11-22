import 'dart:math';
import 'dart:ui';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'player.dart';
import 'dungeon_map.dart';
import 'enemy_skeleton.dart';
import 'enemy_zombie.dart';
import 'pickup_item.dart';
import '../../services/audio_service.dart';
import '../ai/astar_pathfinder.dart';
import '../big_war_game.dart';

enum BossState {
  chase,
  meleeCleave,
  chargeDash,
  groundSlamTelegraph,
  groundSlamImpact,
  radialFlameBurst,
  defeated,
}

class BossHpData {
  final double currentHp;
  final double maxHp;
  final int phase;
  final bool isEnraged;
  final bool isDefeated;
  final String title;

  const BossHpData({
    required this.currentHp,
    required this.maxHp,
    required this.phase,
    required this.isEnraged,
    required this.isDefeated,
    this.title = 'CHÚA TỂ HẦM NGỤC',
  });

  double get hpPercent => (currentHp / maxHp).clamp(0.0, 1.0);
}

class BossEnemy extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  final PlayerComponent player;

  static const double defaultMaxHp = 600.0;
  double maxHp = defaultMaxHp;
  double currentHp = defaultMaxHp;

  int phase = 1;
  bool isEnraged = false;
  bool isDefeated = false;

  static const double speedPhase1 = 55.0;
  static const double speedPhase2 = 80.0;
  double phase1Speed = speedPhase1;
  double phase2Speed = speedPhase2;
  double currentSpeed = speedPhase1;

  // Combat parameters (scale theo cấp tầng màn chơi)
  static const double meleeRange = 70.0;
  double meleeDamage = 25.0;
  static const double groundSlamRange = 220.0;
  static const double groundSlamAoERadius = 70.0; // 140px diameter AoE
  double groundSlamDamage = 40.0;
  static const double groundSlamTelegraphDuration = 1.2;
  double flameBurstDamage = 15.0;
  double flameBurstSpeed = 180.0;
  int flameBurstCount = 8;

  double meleeBaseCooldown = 2.0;
  double groundSlamBaseCooldown = 8.0;
  double flameBurstBaseCooldown = 5.0;
  int floorLevel = 1;

  /// Tăng dần độ khó của Boss theo cấp tầng (HP, sát thương, tốc độ, hồi chiêu, số cầu lửa)
  void applyFloorDifficulty(int floor) {
    final f = floor < 1 ? 1 : floor;
    floorLevel = f;
    final hpMult = 1.0 + (f - 1) * 0.35;
    final dmgMult = 1.0 + (f - 1) * 0.25;
    final speedMult = min(1.45, 1.0 + (f - 1) * 0.06);
    final cdMult = max(0.65, 1.0 - (f - 1) * 0.05);

    maxHp = defaultMaxHp * hpMult;
    currentHp = maxHp;
    meleeDamage = 25.0 * dmgMult;
    groundSlamDamage = 40.0 * dmgMult;
    flameBurstDamage = 15.0 * dmgMult;
    flameBurstSpeed = 180.0 * min(1.35, 1.0 + (f - 1) * 0.05);
    flameBurstCount = f >= 5 ? 12 : (f >= 3 ? 10 : 8);

    phase1Speed = speedPhase1 * speedMult;
    phase2Speed = speedPhase2 * speedMult;
    currentSpeed = phase == 2 ? phase2Speed : phase1Speed;

    meleeBaseCooldown = 2.0 * cdMult;
    groundSlamBaseCooldown = 8.0 * cdMult;
    flameBurstBaseCooldown = 5.0 * cdMult;
  }

  BossState state = BossState.chase;

  // Cooldowns
  double meleeCooldownTimer = 0.0;
  double groundSlamCooldownTimer = 4.5;
  double flameBurstCooldownTimer = 3.5;
  double chargeCooldownTimer = 5.5;
  double stateTimer = 0.0;
  double _spiralAngleOffset = 0.0;
  Vector2 _chargeDirection = Vector2(1, 0);
  bool _chargeHitPlayer = false;

  // Wave spawn flags
  bool summonedWave70 = false;
  bool summonedWave30 = false;

  // A* Navigation state
  List<Vector2> _waypoints = [];
  int _currentWaypointIndex = 0;
  double _pathRecalcTimer = 0.0;
  static const double _pathRecalcInterval = 0.5;

  // Visuals & Animations
  bool isFacingRight = true;
  double axeSwingAngle = 0.0;
  double auraTimer = 0.0;
  double deathFadeTimer = 1.5;
  Vector2 previousPosition = Vector2.zero();
  Vector2? groundSlamCenter;
  GroundSlamTelegraph? activeTelegraph;

  BossEnemy({required Vector2 position, required this.player})
      : super(
          position: position,
          size: Vector2(64, 64),
          anchor: Anchor.center,
        ) {
    add(RectangleHitbox(
      size: Vector2(44, 52),
      position: Vector2(10, 8),
    ));
  }

  @override
  void onMount() {
    super.onMount();
    _notifyHpChanged();
    AudioService.instance.playBgm(BgmTrack.boss);
  }

  @override
  void update(double dt) {
    super.update(dt);
    auraTimer += dt;

    if (isDefeated) {
      deathFadeTimer -= dt;
      if (deathFadeTimer <= 0) {
        removeFromParent();
      }
      return;
    }

    // Cooldown updates
    if (meleeCooldownTimer > 0) meleeCooldownTimer -= dt;
    if (groundSlamCooldownTimer > 0) groundSlamCooldownTimer -= dt;
    if (flameBurstCooldownTimer > 0) flameBurstCooldownTimer -= dt;
    if (chargeCooldownTimer > 0) chargeCooldownTimer -= dt;

    final distanceToPlayer = position.distanceTo(player.position);
    isFacingRight = player.position.x >= position.x;

    // State machine evaluation
    switch (state) {
      case BossState.chase:
        _updateChaseState(dt, distanceToPlayer);
        break;
      case BossState.meleeCleave:
        _updateMeleeCleave(dt, distanceToPlayer);
        break;
      case BossState.chargeDash:
        _updateChargeDash(dt, distanceToPlayer);
        break;
      case BossState.groundSlamTelegraph:
        _updateGroundSlamTelegraph(dt);
        break;
      case BossState.groundSlamImpact:
        _updateGroundSlamImpact(dt);
        break;
      case BossState.radialFlameBurst:
        _updateRadialFlameBurst(dt);
        break;
      case BossState.defeated:
        break;
    }
  }

  void _updateChaseState(double dt, double distanceToPlayer) {
    // 1. Flame Attack: Phase 2 bắn cầu lửa xoáy 360°, Phase 1 bắn quạt 3 cầu lửa đón đầu khi player thả diều xa
    if (flameBurstCooldownTimer <= 0 && (phase == 2 || distanceToPlayer > 155.0)) {
      state = BossState.radialFlameBurst;
      stateTimer = 0.0;
      return;
    }

    // 2. Gap-Closer Charge Dash: Lao húc áp sát khi người chơi thả diều ở tầm 145..290px
    if (chargeCooldownTimer <= 0 &&
        distanceToPlayer >= 145.0 &&
        distanceToPlayer <= 290.0 &&
        (!isMounted ||
            game.walkableGrid.isEmpty ||
            AStarPathfinder.hasLineOfSight(position, player.position, game.walkableGrid))) {
      state = BossState.chargeDash;
      stateTimer = 0.0;
      _chargeHitPlayer = false;
      final predicted = player.position + player.moveDirection * player.speed * 0.35;
      final diff = predicted - position;
      _chargeDirection = diff.length2 > 1.0 ? diff.normalized() : Vector2(isFacingRight ? 1 : -1, 0);
      axeSwingAngle = isFacingRight ? -1.5 : 1.5;
      return;
    }

    // 3. Special Attack: Predictive Ground Slam (đón đầu hướng chạy của Player)
    if (groundSlamCooldownTimer <= 0 && distanceToPlayer <= groundSlamRange) {
      state = BossState.groundSlamTelegraph;
      stateTimer = 0.0;
      final leadOffset = player.moveDirection * player.speed * 0.45;
      groundSlamCenter = player.position + leadOffset;
      activeTelegraph = GroundSlamTelegraph(
        position: groundSlamCenter!,
        duration: groundSlamTelegraphDuration,
      );
      if (isMounted) {
        game.world.add(activeTelegraph!);
      }
      return;
    }

    // 3. Melee Cleave
    if (distanceToPlayer <= meleeRange && meleeCooldownTimer <= 0) {
      state = BossState.meleeCleave;
      stateTimer = 0.0;
      axeSwingAngle = isFacingRight ? -1.2 : 1.2;
      return;
    }

    // 4. Default: Navigation towards Player
    if (distanceToPlayer > 30.0) {
      previousPosition = position.clone();

      // Check if A* pathfinding is accessible
      if (isMounted && game.walkableGrid.isNotEmpty) {
        _pathRecalcTimer -= dt;
        if (_pathRecalcTimer <= 0) {
          _pathRecalcTimer = _pathRecalcInterval;
          _waypoints = AStarPathfinder.findPath(
            position,
            player.position,
            game.walkableGrid,
          );
          _currentWaypointIndex = 0;
        }

        if (_waypoints.isNotEmpty && _currentWaypointIndex < _waypoints.length) {
          var targetPt = _waypoints[_currentWaypointIndex];
          if (_currentWaypointIndex == _waypoints.length - 1) {
            targetPt = player.position;
          }

          if (position.distanceTo(targetPt) <= 16.0) {
            _currentWaypointIndex++;
            if (_currentWaypointIndex < _waypoints.length) {
              targetPt = _waypoints[_currentWaypointIndex];
            }
          }

          final toTarget = targetPt - position;
          if (toTarget.length2 > 0.001) {
            final dir = toTarget.normalized();
            position.add(dir * currentSpeed * dt);
            return;
          }
        }
      }

      // Direct fallback
      final dir = (player.position - position).normalized();
      position.add(dir * currentSpeed * dt);
    }
  }

  void _updateMeleeCleave(double dt, double distanceToPlayer) {
    stateTimer += dt;
    // Wind up: 0.0s - 0.2s, Swing: 0.2s - 0.35s
    if (stateTimer < 0.2) {
      axeSwingAngle = isFacingRight ? -1.4 : 1.4;
    } else if (stateTimer < 0.35) {
      axeSwingAngle = isFacingRight ? 1.5 : -1.5;
      if (stateTimer - dt < 0.2) {
        // Execute damage at swing apex
        if (distanceToPlayer <= meleeRange + 10.0) {
          player.takeDamage(meleeDamage);
        }
      }
    } else {
      axeSwingAngle = 0.0;
      meleeCooldownTimer = meleeBaseCooldown;
      state = BossState.chase;
    }
  }

  void _updateGroundSlamTelegraph(double dt) {
    stateTimer += dt;
    axeSwingAngle = isFacingRight ? -1.8 : 1.8; // Axe raised overhead
    if (stateTimer >= groundSlamTelegraphDuration) {
      state = BossState.groundSlamImpact;
      stateTimer = 0.0;
    }
  }

  void _updateGroundSlamImpact(double dt) {
    stateTimer += dt;
    axeSwingAngle = isFacingRight ? 1.6 : -1.6; // Axe slammed downward

    if (groundSlamCenter != null) {
      final dist = player.position.distanceTo(groundSlamCenter!);
      if (dist <= groundSlamAoERadius) {
        player.takeDamage(groundSlamDamage);
      }
      groundSlamCenter = null;
      AudioService.instance.playSfx(SfxSound.skillSmash);
    }

    if (stateTimer >= 0.3) {
      axeSwingAngle = 0.0;
      groundSlamCooldownTimer = groundSlamBaseCooldown;
      state = BossState.chase;
    }
  }

  void _updateChargeDash(double dt, double distanceToPlayer) {
    stateTimer += dt;
    // 0.0 - 0.30s: Gồng lấy đà, 0.30 - 0.80s: Lao húc tốc độ cao 3.1x
    if (stateTimer < 0.30) {
      axeSwingAngle = isFacingRight ? -1.7 : 1.7;
    } else if (stateTimer < 0.80) {
      previousPosition = position.clone();
      position.add(_chargeDirection * (currentSpeed * 3.1) * dt);
      axeSwingAngle = isFacingRight ? 1.4 : -1.4;
      if (!_chargeHitPlayer && distanceToPlayer <= meleeRange - 12.0) {
        _chargeHitPlayer = true;
        player.takeDamage(meleeDamage * 1.15);
        AudioService.instance.playSfx(SfxSound.skillSmash);
      }
    } else {
      axeSwingAngle = 0.0;
      chargeCooldownTimer = phase == 2 ? 5.5 : 7.5;
      state = BossState.chase;
    }
  }

  void _updateRadialFlameBurst(double dt) {
    stateTimer += dt;
    if (stateTimer >= 0.25) {
      if (phase == 2) {
        // Phase 2: Bắn cầu lửa 360° xoay góc lệch liên tục để không thể đứng yên né
        final int numFireballs = flameBurstCount;
        _spiralAngleOffset += pi / numFireballs;
        for (int i = 0; i < numFireballs; i++) {
          final angle = _spiralAngleOffset + i * (2 * pi / numFireballs);
          final dir = Vector2(cos(angle), sin(angle));
          final fireball = BossFlameProjectile(
            position: position.clone(),
            direction: dir,
            speed: flameBurstSpeed,
            damage: flameBurstDamage,
          );
          if (isMounted) {
            game.world.add(fireball);
          }
        }
      } else {
        // Phase 1: Bắn quạt 3 cầu lửa đón đầu về phía Player
        final predicted = player.position + player.moveDirection * player.speed * 0.35;
        final baseAngle = atan2(predicted.y - position.y, predicted.x - position.x);
        for (final offsetDeg in [-16.0, 0.0, 16.0]) {
          final a = baseAngle + offsetDeg * pi / 180.0;
          final fireball = BossFlameProjectile(
            position: position.clone(),
            direction: Vector2(cos(a), sin(a)),
            speed: flameBurstSpeed * 1.1,
            damage: flameBurstDamage,
          );
          if (isMounted) {
            game.world.add(fireball);
          }
        }
      }
      AudioService.instance.playSfx(SfxSound.skillBerserk);
      flameBurstCooldownTimer = flameBurstBaseCooldown;
      state = BossState.chase;
    }
  }

  void takeDamage(double dmg) {
    if (isDefeated) return;

    currentHp = (currentHp - dmg).clamp(0.0, maxHp);

    // Phase transition check (< 50% HP)
    if (currentHp <= maxHp * 0.5 && phase == 1) {
      phase = 2;
      isEnraged = true;
      currentSpeed = phase2Speed;
    }

    // Minion wave trigger checks
    if (currentHp <= maxHp * 0.70 && !summonedWave70) {
      summonedWave70 = true;
      _summonMinionWave();
    }
    if (currentHp <= maxHp * 0.30 && !summonedWave30) {
      summonedWave30 = true;
      _summonMinionWave();
    }

    _notifyHpChanged();

    // Defeat check
    if (currentHp <= 0) {
      _triggerDefeat();
    }
  }

  void _summonMinionWave() {
    if (!isMounted) return;

    final offsets = [
      Vector2(-55, -45),
      Vector2(55, -45),
      Vector2(-45, 45),
      Vector2(45, 45),
    ];

    for (int i = 0; i < offsets.length; i++) {
      final spawnPos = position + offsets[i];
      spawnPos.x = spawnPos.x.clamp(48.0, 1104.0);
      spawnPos.y = spawnPos.y.clamp(48.0, 720.0);

      if (i < 2) {
        final skeleton = SkeletonEnemy(position: spawnPos, player: player);
        game.scaleSkeletonForFloor(skeleton, game.currentFloor);
        game.skeletons.add(skeleton);
        game.world.add(skeleton);
      } else {
        final zombie = ZombieEnemy(position: spawnPos, player: player);
        game.scaleZombieForFloor(zombie, game.currentFloor);
        game.enemies.add(zombie);
        game.world.add(zombie);
      }
    }
  }

  void _triggerDefeat() {
    isDefeated = true;
    state = BossState.defeated;
    children.whereType<ShapeHitbox>().toList().forEach((h) => h.removeFromParent());
    _notifyHpChanged();

    if (!isMounted) return;

    // Defeat Loot Cascade: 2-3 Xu (2,000 - 3,000 Vàng), Bình Máu và Ngọc EXP
    final drops = <PickupType>[
      PickupType.goldCoin,
      PickupType.healthPotion,
      PickupType.goldCoin,
      PickupType.expGem,
      if (isEnraged) PickupType.goldCoin,
    ];
    final totalItems = drops.length;
    const double radius = 54.0;
    for (int i = 0; i < totalItems; i++) {
      final angle = i * (2 * pi / totalItems);
      final itemPos = position + Vector2(cos(angle) * radius, sin(angle) * radius);
      final pickup = PickupItem(position: itemPos, type: drops[i]);
      game.pickups.add(pickup);
      game.world.add(pickup);
    }

    final allBossesDefeated = game.bosses.every((b) => b.isDefeated);
    if (allBossesDefeated) {
      // Victory Portal chỉ mở khi toàn bộ Boss trên tầng đã bị hạ
      final portal = BossVictoryPortal(position: position.clone());
      game.world.add(portal);

      // Audio triggers: Victory fanfare & switch back to dungeon BGM
      AudioService.instance.playSfx(SfxSound.wheelJackpot);
      AudioService.instance.playBgm(BgmTrack.dungeon);
    } else {
      AudioService.instance.playSfx(SfxSound.skillSmash);
    }
  }

  void _notifyHpChanged() {
    if (isMounted) {
      game.refreshBossHud();
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is WallBlock) {
      position = previousPosition.clone();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // 1. Ground Shadow
    final shadowPaint = Paint()..color = const Color(0x55000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 4), width: 44, height: 10),
      shadowPaint,
    );

    // 2. Phase 2 Enraged Fire Aura (vòng đồng tâm nhẹ GPU, tránh MaskFilter.blur)
    if (isEnraged) {
      final auraPulse = sin(auraTimer * 6.0) * 4.0;
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        36 + auraPulse,
        Paint()..color = const Color(0x28FF3D00),
      );
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        26 + auraPulse * 0.5,
        Paint()..color = const Color(0x3CFF9100),
      );
    }

    canvas.save();
    if (!isFacingRight) {
      canvas.scale(-1, 1);
      canvas.translate(-size.x, 0);
    }

    // 3. Legs & Greaves
    final greavePaint = Paint()..color = const Color(0xFF212121);
    final kneeGuard = Paint()..color = const Color(0xFFB71C1C);
    canvas.drawRect(const Rect.fromLTWH(18, 48, 11, 14), greavePaint);
    canvas.drawRect(const Rect.fromLTWH(35, 48, 11, 14), greavePaint);
    canvas.drawRect(const Rect.fromLTWH(19, 48, 9, 4), kneeGuard);
    canvas.drawRect(const Rect.fromLTWH(36, 48, 9, 4), kneeGuard);

    // 4. Fauld & Obsidian Plate Armor
    final fauldPaint = Paint()..color = const Color(0xFF263238);
    final goldTrim = Paint()..color = const Color(0xFFFFB300);
    canvas.drawRect(const Rect.fromLTWH(16, 42, 32, 8), fauldPaint);
    canvas.drawRect(const Rect.fromLTWH(16, 42, 32, 2.5), goldTrim);

    final armorPaint = Paint()..color = const Color(0xFF1E272C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(15, 26, 34, 18), const Radius.circular(5)),
      armorPaint,
    );

    // Skull chestplate carving
    final skullChest = Paint()..color = const Color(0xFFCFD8DC);
    canvas.drawRect(const Rect.fromLTWH(26, 28, 12, 10), skullChest);
    final chestEye = Paint()..color = const Color(0xFF101018);
    canvas.drawRect(const Rect.fromLTWH(28, 31, 2.5, 2.5), chestEye);
    canvas.drawRect(const Rect.fromLTWH(33.5, 31, 2.5, 2.5), chestEye);

    // Spiked Pauldrons (Left & Right)
    final pauldronPaint = Paint()..color = const Color(0xFF37474F);
    final leftSpike = Path()
      ..moveTo(16, 22)
      ..lineTo(6, 26)
      ..lineTo(16, 34)
      ..close();
    canvas.drawPath(leftSpike, pauldronPaint);

    final rightSpike = Path()
      ..moveTo(48, 22)
      ..lineTo(58, 26)
      ..lineTo(48, 34)
      ..close();
    canvas.drawPath(rightSpike, pauldronPaint);

    // 5. Demonic Skull Head
    final skullPaint = Paint()..color = const Color(0xFFE0E0E0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(20, 10, 24, 18), const Radius.circular(6)),
      skullPaint,
    );

    // Jaw & Fangs
    final jawPaint = Paint()..color = const Color(0xFF9E9E9E);
    canvas.drawRect(const Rect.fromLTWH(24, 24, 16, 5), jawPaint);
    final fangPaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(const Rect.fromLTWH(25, 26, 2, 3), fangPaint);
    canvas.drawRect(const Rect.fromLTWH(29, 26, 2, 3), fangPaint);
    canvas.drawRect(const Rect.fromLTWH(33, 26, 2, 3), fangPaint);
    canvas.drawRect(const Rect.fromLTWH(37, 26, 2, 3), fangPaint);

    // Hollow eye sockets & Glowing red eyes
    final socketPaint = Paint()..color = const Color(0xFF101018);
    canvas.drawRect(const Rect.fromLTWH(24, 16, 5, 4), socketPaint);
    canvas.drawRect(const Rect.fromLTWH(35, 16, 5, 4), socketPaint);

    final eyeGlow = Paint()
      ..color = isEnraged ? const Color(0xFFFF5252) : const Color(0xFFFF1744);
    canvas.drawRect(const Rect.fromLTWH(26, 17, 3, 3), eyeGlow);
    canvas.drawRect(const Rect.fromLTWH(37, 17, 3, 3), eyeGlow);

    // Golden Horns (Sweeping curves)
    final hornPaint = Paint()..color = const Color(0xFFFFD700);
    final leftHorn = Path()
      ..moveTo(22, 15)
      ..quadraticBezierTo(14, 10, 8, 2)
      ..quadraticBezierTo(16, 8, 25, 12)
      ..close();
    canvas.drawPath(leftHorn, hornPaint);

    final rightHorn = Path()
      ..moveTo(42, 15)
      ..quadraticBezierTo(50, 10, 56, 2)
      ..quadraticBezierTo(48, 8, 39, 12)
      ..close();
    canvas.drawPath(rightHorn, hornPaint);

    // 6. Colossal Battle Axe
    canvas.save();
    canvas.translate(51, 32);
    if (axeSwingAngle != 0.0) {
      canvas.rotate(axeSwingAngle);
    }

    final handlePaint = Paint()
      ..color = const Color(0xFF3E2723)
      ..strokeWidth = 3.5;
    canvas.drawLine(const Offset(0, -22), const Offset(0, 26), handlePaint);

    // Double crescent axe blades
    final bladeSteel = Paint()..color = const Color(0xFF546E7A);
    final bladePath = Path()
      ..moveTo(0, -12)
      ..lineTo(14, -20)
      ..lineTo(11, -2)
      ..lineTo(0, -2)
      ..close();
    canvas.drawPath(bladePath, bladeSteel);

    final bladePath2 = Path()
      ..moveTo(0, -2)
      ..lineTo(14, -2)
      ..lineTo(11, 16)
      ..lineTo(0, 8)
      ..close();
    canvas.drawPath(bladePath2, bladeSteel);

    // Rune channel on axe blade
    final axeRune = Paint()..color = const Color(0xFFFF1744);
    canvas.drawRect(const Rect.fromLTWH(2, -14, 2, 20), axeRune);

    canvas.restore();
    canvas.restore();
  }
}

class BossFlameProjectile extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  final Vector2 direction;
  final double speed;
  final double damage;
  double lifeTimer = 0.0;
  bool hasHit = false;

  BossFlameProjectile({
    required Vector2 position,
    required Vector2 direction,
    this.speed = 180.0,
    this.damage = 15.0,
  })  : direction = direction.length2 > 0 ? direction.normalized() : Vector2(1, 0),
        super(position: position, size: Vector2(16, 16), anchor: Anchor.center) {
    add(CircleHitbox(radius: 6, position: Vector2(2, 2)));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (hasHit) return;
    lifeTimer += dt;
    if (lifeTimer >= 4.0) {
      removeFromParent();
      return;
    }
    position.add(direction * speed * dt);
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (hasHit) return;
    if (other is PlayerComponent) {
      hasHit = true;
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is WallBlock) {
      hasHit = true;
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final center = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(center, 8.5, Paint()..color = const Color(0x44FF3D00));

    final flamePaint = Paint()..color = const Color(0xFFFF5722);
    canvas.drawCircle(center, 5.5, flamePaint);

    final corePaint = Paint()..color = const Color(0xFFFFEB3B);
    canvas.drawCircle(center, 3.0, corePaint);

    final whiteCore = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(center, 1.2, whiteCore);
  }
}

class GroundSlamTelegraph extends PositionComponent {
  final double duration;
  double timer = 0.0;

  GroundSlamTelegraph({
    required Vector2 position,
    this.duration = 1.2,
  }) : super(position: position, size: Vector2(140, 140), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    timer += dt;
    if (timer >= duration + 0.3) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final center = Offset(size.x / 2, size.y / 2);
    const radius = 70.0;
    final progress = (timer / duration).clamp(0.0, 1.0);

    // Outer warning ring
    final ringPaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, ringPaint);

    // Expanding fill
    final fillPaint = Paint()
      ..color = Color.fromRGBO(255, 23, 68, 0.25 + 0.3 * progress);
    canvas.drawCircle(center, radius * progress, fillPaint);

    if (timer >= duration) {
      final flashPaint = Paint()
        ..color = const Color(0xAAFFEB3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawCircle(center, radius * 1.05, flashPaint);
    }
  }
}

class BossVictoryPortal extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  double timer = 0.0;
  bool hasTriggered = false;

  BossVictoryPortal({required Vector2 position})
      : super(position: position, size: Vector2(50, 50), anchor: Anchor.center) {
    add(CircleHitbox(radius: 20, position: Vector2(5, 5)));
  }

  @override
  void update(double dt) {
    super.update(dt);
    timer += dt;
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (hasTriggered) return;
    if (other is PlayerComponent) {
      hasTriggered = true;
      if (isMounted) {
        game.triggerVictory();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final center = Offset(size.x / 2, size.y / 2);
    final rot = timer * 2.0;

    final glowPaint = Paint()
      ..color = const Color(0x6600E5FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, 22, glowPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rot);

    final ring1 = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 36, height: 20), ring1);

    final ring2 = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 20, height: 36), ring2);

    canvas.restore();

    final corePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(center, 6, corePaint);
  }
}
