import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../registry/sprite_image_cache.dart';
import '../../services/audio_service.dart';
import '../rendering/fox_spirit_visual.dart';
import '../rendering/dragon_spirit_visual.dart';
import '../big_war_game.dart';
import 'player.dart';
import 'enemy_zombie.dart';
import 'enemy_skeleton.dart';
import 'boss_enemy.dart';
import 'dungeon_map.dart';

/// 4 phân loại Trợ thủ AI Companion Drone (bao gồm Aegis-X9 Tinh Linh Lôi Từ)
enum CompanionType {
  attack,
  shield,
  frost,
  aegisX9,
}

extension CompanionTypeExtension on CompanionType {
  static CompanionType? fromId(String? id) {
    if (id == null) return null;
    switch (id) {
      case 'companion_attack':
      case 'comp_attack':
      case 'attack':
      case 'orbit_03':
        return CompanionType.attack;
      case 'companion_defense':
      case 'comp_defense':
      case 'defense':
      case 'shield':
      case 'cyber_drone':
        return CompanionType.shield;
      case 'companion_frost':
      case 'comp_control':
      case 'control':
      case 'frost':
      case 'pyro_frost_dragon':
      case 'luna_fox':
        return CompanionType.frost;
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
        return CompanionType.aegisX9;
      default:
        return null;
    }
  }

  String get displayName {
    switch (this) {
      case CompanionType.attack:
        return 'Trợ Thủ Công Kích';
      case CompanionType.shield:
        return 'Trợ Thủ Phòng Ngự';
      case CompanionType.frost:
        return 'Trợ Thủ Khống Chế';
      case CompanionType.aegisX9:
        return 'Aegis-X9 Lôi Từ';
    }
  }

  Color get themeColor {
    switch (this) {
      case CompanionType.attack:
        return const Color(0xFFFF1744);
      case CompanionType.shield:
        return const Color(0xFF2979FF);
      case CompanionType.frost:
        return const Color(0xFF18FFFF);
      case CompanionType.aegisX9:
        return const Color(0xFFFFD700);
    }
  }
}

/// AI Companion Drone bay lơ lửng quanh Player
class CompanionComponent extends PositionComponent
    with HasGameReference<BigWarGame> {
  final String companionId;
  final CompanionType type;
  final PlayerComponent player;

  // Quỹ đạo bay quanh Player
  final double orbitRadius;
  double orbitAngle = 0.0;
  final double orbitSpeed = 1.5; // rad/s
  double bobbingTimer = 0.0;
  bool _foxRunning = false;
  bool _foxFacingRight = true;
  double _foxRunTime = 0;
  final Vector2 _foxTravelDirection = Vector2(1, 0);
  bool get isFoxRunning => companionId == 'luna_fox' && _foxRunning;

  // Bộ đếm hành động đánh thường
  double actionCooldown = 0.0;
  PositionComponent? lockedTarget;

  // Kỹ năng Đặc biệt riêng của từng Trợ thủ
  static const double maxSpecialSkillCooldown = 14.0;
  static const double specialSkillMaxCooldown = maxSpecialSkillCooldown;
  double specialSkillCooldown = 0.0;
  double overdriveTimer = 0.0;
  bool _ownsActiveShield = false;
  bool _ownsAttackBuff = false;

  // Overdrive riêng cho ORBIT-03 (bắn liên thanh + tia laser quỹ đạo)
  double _rapidFireTimer = 0.0;
  Vector2? _orbitalStrikePos;
  double _orbitalStrikeTimer = 0.0;

  // Quản lý trạng thái làm chậm của Frost Drone / Aegis-X9
  final Map<PositionComponent, double> _slowedEnemies = {};
  // Quản lý hiệu ứng đóng băng / làm chậm có thời hạn từ kỹ năng kích hoạt
  final Map<PositionComponent, _TimedSpeedEffect> _timedSpeedEffects = {};

  /// Tên kỹ năng đặc biệt hiển thị khi kích hoạt (FloatingCombatText)
  String get skillName {
    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        return 'MƯA ĐẠN PLASMA!';
      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        return 'LỒNG PHẢN CHẤN!';
      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        return 'BÃO TUYẾT ĐÓNG BĂNG!';
      case 'cyber_drone':
        return 'KHIÊN SINH HỌC & HỒI MÁU!';
      case 'luna_fox':
        return 'LINH HỒN HỒ LY!';
      case 'orbit_03':
        return 'PHÁO LASER QUỸ ĐẠO!';
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
        return 'TRƯỜNG TRỌNG LỰC HOÀNG KIM!';
      case 'pyro_frost_dragon':
        return 'HƠI THỞ BÃO TỐ!';
      default:
        return 'KỸ NĂNG TRỢ THỦ!';
    }
  }

  /// Thời gian hồi chiêu riêng cho từng Trợ thủ
  double get skillCooldownDuration {
    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        return 10.0;
      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        return 13.0;
      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        return 13.0;
      case 'cyber_drone':
        return 15.0;
      case 'luna_fox':
        return 14.0;
      case 'orbit_03':
        return 13.0;
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
        return 14.0;
      case 'pyro_frost_dragon':
        return 15.0;
      default:
        return maxSpecialSkillCooldown;
    }
  }

  /// Màu chủ đạo trên nút PET HUD và vòng hiệu ứng kỹ năng
  Color get skillColor {
    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        return const Color(0xFFFF5252);
      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        return const Color(0xFF448AFF);
      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        return const Color(0xFF18FFFF);
      case 'cyber_drone':
        return const Color(0xFF00E5FF);
      case 'luna_fox':
        return const Color(0xFF80D8FF);
      case 'orbit_03':
        return const Color(0xFFFFAB00);
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
        return const Color(0xFFFFD700);
      case 'pyro_frost_dragon':
        return const Color(0xFFFF5252);
      default:
        return type.themeColor;
    }
  }

  /// Icon hiển thị trên nút PET HUD
  IconData get skillIcon {
    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        return Icons.rocket_launch_rounded;
      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        return Icons.shield_rounded;
      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        return Icons.ac_unit_rounded;
      case 'cyber_drone':
        return Icons.health_and_safety_rounded;
      case 'luna_fox':
        return Icons.auto_fix_high_rounded;
      case 'orbit_03':
        return Icons.radar_rounded;
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
        return Icons.auto_awesome_rounded;
      case 'pyro_frost_dragon':
        return Icons.whatshot_rounded;
      default:
        return Icons.auto_awesome;
    }
  }

  bool get isRapidFireActive => _rapidFireTimer > 0;

  CompanionComponent({
    required this.companionId,
    required this.player,
    this.orbitRadius = 45.0,
  })  : type = CompanionTypeExtension.fromId(companionId) ?? CompanionType.attack,
        super(
          size: Vector2(24, 24),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    position = player.position + Vector2(orbitRadius, 0);
    if (companionId == 'luna_fox') {
      _foxFacingRight = player.isFacingRight;
      _foxTravelDirection.setValues(player.isFacingRight ? 1 : -1, 0);
      position.setFrom(player.position - _foxTravelDirection * 32 + Vector2(0, 12));
    }

    // Kích hoạt khiên bảo vệ 30% cho Player nếu là Shield Drone
    if (type == CompanionType.shield) {
      player.damageAbsorption = 0.30;
    } else if (type == CompanionType.aegisX9) {
      player.damageAbsorption = 0.20;
    }
  }

  @override
  void onMount() {
    super.onMount();
    if (type == CompanionType.shield) {
      player.damageAbsorption = 0.30;
    } else if (type == CompanionType.aegisX9) {
      player.damageAbsorption = 0.20;
    }
  }

  @override
  void onRemove() {
    cleanup();
    super.onRemove();
  }

  /// Dọn dẹp trạng thái, hoàn trả tốc độ quái vật và hồi phục chỉ số khi unequip / exit
  void cleanup() {
    _clearActiveShield();
    _clearAttackBuff();
    lockedTarget = null;
    _rapidFireTimer = 0.0;
    _orbitalStrikePos = null;
    _orbitalStrikeTimer = 0.0;
    if (type == CompanionType.shield || type == CompanionType.aegisX9) {
      player.damageAbsorption = 0.0;
    }
    _restoreAllTimedSpeedEffects();
    _restoreAllSlowedEnemies();
  }

  void _clearActiveShield() {
    if (!_ownsActiveShield) return;
    player.temporaryPetDamageAbsorption = 0.0;
    player.goldenShieldTimer = 0.0;
    _ownsActiveShield = false;
  }

  void _clearAttackBuff() {
    if (!_ownsAttackBuff) return;
    player.petAttackBuffTimer = 0.0;
    player.petAttackBuffBonus = 0.0;
    _ownsAttackBuff = false;
  }

  /// No targeting/slow/shield state from a previous floor should leak into retry.
  void resetForFloor() {
    _clearActiveShield();
    _clearAttackBuff();
    _restoreAllTimedSpeedEffects();
    _restoreAllSlowedEnemies();
    lockedTarget = null;
    actionCooldown = specialSkillCooldown = overdriveTimer = 0.0;
    _rapidFireTimer = 0.0;
    _orbitalStrikePos = null;
    _orbitalStrikeTimer = 0.0;
    position = player.position + Vector2(orbitRadius, 0);
    _foxRunning = false;
    _foxRunTime = 0;
    if (companionId == 'luna_fox') {
      position.setFrom(player.position - _foxTravelDirection * 32 + Vector2(0, 12));
    }
  }

  void _restoreAllSlowedEnemies() {
    for (final entry in _slowedEnemies.entries) {
      final enemy = entry.key;
      final origSpeed = entry.value;
      if (enemy.isMounted) {
        _setEnemySpeed(enemy, origSpeed);
      }
    }
    _slowedEnemies.clear();
  }

  void _restoreAllTimedSpeedEffects() {
    for (final entry in _timedSpeedEffects.entries) {
      final enemy = entry.key;
      if (enemy.isMounted) {
        _setEnemySpeed(enemy, entry.value.originalSpeed);
      }
    }
    _timedSpeedEffects.clear();
  }

  double _getEnemySpeed(PositionComponent enemy) {
    if (enemy is ZombieEnemy) return enemy.speed;
    if (enemy is SkeletonEnemy) return enemy.speed;
    if (enemy is BossEnemy) return enemy.currentSpeed;
    return 0.0;
  }

  void _setEnemySpeed(PositionComponent enemy, double speed) {
    if (enemy is ZombieEnemy) {
      enemy.speed = speed;
    } else if (enemy is SkeletonEnemy) {
      enemy.speed = speed;
    } else if (enemy is BossEnemy) {
      enemy.currentSpeed = speed;
    }
  }

  void _damageEnemy(PositionComponent enemy, double dmg) {
    if (enemy is ZombieEnemy) {
      enemy.takeDamage(dmg);
    } else if (enemy is SkeletonEnemy) {
      enemy.takeDamage(dmg);
    } else if (enemy is BossEnemy) {
      enemy.takeDamage(dmg);
    }
  }

  void _applyTimedSpeedMultiplier(
    PositionComponent enemy, {
    required double multiplier,
    required double duration,
  }) {
    final existing = _timedSpeedEffects[enemy];
    final baseSpeed =
        existing?.originalSpeed ?? _slowedEnemies[enemy] ?? _getEnemySpeed(enemy);
    _timedSpeedEffects[enemy] = _TimedSpeedEffect(
      originalSpeed: baseSpeed,
      remaining: max(existing?.remaining ?? 0.0, duration),
    );
    _setEnemySpeed(enemy, baseSpeed * multiplier);
  }

  List<PositionComponent> _livingMonsters() {
    if (!isMounted) return const [];
    return <PositionComponent>[
      ...game.enemies.where((e) => e.isMounted && e.currentHp > 0),
      ...game.skeletons.where((e) => e.isMounted && e.currentHp > 0),
      ...game.bosses.where((b) => b.isMounted && !b.isDefeated),
    ];
  }

  void _grantTemporaryShield({required double absorption, required double duration}) {
    player.goldenShieldTimer = duration;
    player.temporaryPetDamageAbsorption = absorption;
    _ownsActiveShield = true;
  }

  /// Kích hoạt Kỹ năng Đặc biệt riêng theo từng Trợ thủ
  bool activateSpecialSkill() {
    if (specialSkillCooldown > 0 || player.currentHp <= 0) return false;
    specialSkillCooldown = skillCooldownDuration;
    overdriveTimer = 2.5;

    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        _activateAttackNova();
        break;
      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        _activateDefenseShockwave();
        break;
      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        _activateFrostFreeze();
        break;
      case 'cyber_drone':
        _activateCyberBioShield();
        break;
      case 'luna_fox':
        _activateLunaSpirit();
        break;
      case 'orbit_03':
        _activateOrbitLaserStrike();
        break;
      case 'pyro_frost_dragon':
        _activateDragonStormBreath();
        break;
      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
      default:
        _activateAegisGravityField();
        break;
    }

    player.onStatsChanged?.call();
    return true;
  }

  /// 1. Trợ Thủ Công Kích: Mưa Đạn Plasma (6 tia 360°, 24 DMG/tia)
  void _activateAttackNova() {
    AudioService.instance.playSfx(SfxSound.skillHurricane);
    if (!isMounted) return;
    const count = 6;
    for (int i = 0; i < count; i++) {
      final rad = (i * 2 * pi / count) + orbitAngle;
      final dir = Vector2(cos(rad), sin(rad));
      game.world.add(
        CompanionPlasmaProjectile(
          position: position.clone(),
          direction: dir,
          damage: 24.0,
          speed: 320.0,
          color: const Color(0xFFFF5252),
        ),
      );
    }
  }

  /// 2. Trợ Thủ Phòng Ngự: Lồng Phản Chấn (Khiên 55% trong 5s + đẩy lùi quái 150px + 18 DMG)
  void _activateDefenseShockwave() {
    AudioService.instance.playSfx(SfxSound.skillSmash);
    _grantTemporaryShield(absorption: 0.55, duration: 5.0);
    for (final m in _livingMonsters()) {
      final delta = m.position - player.position;
      final dist = delta.length;
      if (dist <= 150.0) {
        final pushDir = dist > 1 ? delta.normalized() : Vector2(1, 0);
        m.position.add(pushDir * 68.0);
        _damageEnemy(m, 18.0);
      }
    }
  }

  /// 3. Trợ Thủ Khống Chế: Bão Tuyết Đóng Băng (đóng băng 3s + 20 DMG trong 180px)
  void _activateFrostFreeze() {
    AudioService.instance.playSfx(SfxSound.skillSmash);
    for (final m in _livingMonsters()) {
      if (player.position.distanceTo(m.position) <= 180.0) {
        _applyTimedSpeedMultiplier(m, multiplier: 0.0, duration: 3.0);
        _damageEnemy(m, 20.0);
      }
    }
  }

  /// 4. Cyber Drone (PIXEL-01): Khiên Sinh Học & Hồi Máu (+25% Max HP + Khiên 45% 4.5s + 3 tia Plasma)
  void _activateCyberBioShield() {
    AudioService.instance.playSfx(SfxSound.pickupPotion);
    player.heal(player.maxHp * 0.25);
    _grantTemporaryShield(absorption: 0.45, duration: 4.5);
    if (!isMounted) return;
    final monsters = _livingMonsters();
    monsters.sort(
      (a, b) => position.distanceTo(a.position).compareTo(position.distanceTo(b.position)),
    );
    for (int i = 0; i < 3; i++) {
      final Vector2 dir;
      if (i < monsters.length) {
        final delta = monsters[i].position - position;
        dir = delta.length2 > 0 ? delta.normalized() : Vector2(1, 0);
      } else {
        final rad = (i * 2 * pi / 3);
        dir = Vector2(cos(rad), sin(rad));
      }
      game.world.add(
        CompanionPlasmaProjectile(
          position: position.clone(),
          direction: dir,
          damage: 16.0,
          speed: 300.0,
          color: const Color(0xFF00E5FF),
        ),
      );
    }
  }

  /// 5. Hồ Ly Luna: Linh Hồn Hồ Ly (+40% Ki + giảm 3s hồi chiêu Skill 1-2-3 + làm chậm 50% quái 4s)
  void _activateLunaSpirit() {
    AudioService.instance.playSfx(SfxSound.pickupGem);
    player.restoreKi(player.maxKi * 0.40);
    player.reduceSkillCooldowns(3.0);
    for (final m in _livingMonsters()) {
      if (player.position.distanceTo(m.position) <= 160.0) {
        _applyTimedSpeedMultiplier(m, multiplier: 0.50, duration: 4.0);
        _damageEnemy(m, 15.0);
      }
    }
  }

  /// 6. ORBIT-03 Drone: Pháo Laser Quỹ Đạo (giáng laser nổ 55 DMG + bắn liên thanh 4s)
  void _activateOrbitLaserStrike() {
    AudioService.instance.playSfx(SfxSound.skillBerserk);
    _rapidFireTimer = 4.0;
    actionCooldown = 0.0;
    final monsters = _livingMonsters();
    if (monsters.isEmpty) return;

    PositionComponent? nearest;
    double nearestDist = 240.0;
    for (final m in monsters) {
      final d = player.position.distanceTo(m.position);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = m;
      }
    }
    if (nearest != null) {
      _orbitalStrikePos = nearest.position.clone();
      _orbitalStrikeTimer = 0.9;
      for (final m in monsters) {
        if (m.position.distanceTo(_orbitalStrikePos!) <= 90.0) {
          _damageEnemy(m, 55.0);
        }
      }
    }
  }

  /// 7. Aegis-X9 Lôi Từ: Trường Trọng Lực Hoàng Kim (gom quái 170px + hút vật phẩm 320px + 35 DMG + Khiên 35% 4s)
  void _activateAegisGravityField() {
    AudioService.instance.playSfx(SfxSound.skillSmash);
    _grantTemporaryShield(absorption: 0.35, duration: 4.0);
    if (!isMounted) return;

    const pullRadius = 170.0;
    for (final m in _livingMonsters()) {
      final dist = player.position.distanceTo(m.position);
      if (dist <= pullRadius) {
        if (dist > 22) {
          final pullDir = (player.position - m.position).normalized();
          m.position.add(pullDir * min(55.0, dist * 0.55));
        }
        _damageEnemy(m, 35.0);
      }
    }

    // Hút toàn bộ vật phẩm (xu, ngọc, bình máu) trong 320px về gần người chơi
    for (final item in game.pickups) {
      if (!item.isMounted) continue;
      final dist = player.position.distanceTo(item.position);
      if (dist <= 320.0 && dist > 8.0) {
        final pullDir = (player.position - item.position).normalized();
        item.position.add(pullDir * (dist - 8.0));
      }
    }
  }

  /// 8. Pyro-Frost Dragon: Hơi Thở Bão Tố (65 DMG nổ 200px + đóng băng 2.5s + tăng 30% sát thương đòn đánh 5s)
  void _activateDragonStormBreath() {
    AudioService.instance.playSfx(SfxSound.skillBerserk);
    player.petAttackBuffBonus = 0.30;
    player.petAttackBuffTimer = 5.0;
    _ownsAttackBuff = true;
    for (final m in _livingMonsters()) {
      if (player.position.distanceTo(m.position) <= 200.0) {
        _damageEnemy(m, 65.0);
        _applyTimedSpeedMultiplier(m, multiplier: 0.0, duration: 2.5);
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (specialSkillCooldown > 0) {
      specialSkillCooldown = max(0.0, specialSkillCooldown - dt);
    }
    if (overdriveTimer > 0) {
      overdriveTimer = max(0.0, overdriveTimer - dt);
    }
    if (_rapidFireTimer > 0) {
      _rapidFireTimer = max(0.0, _rapidFireTimer - dt);
    }
    if (_orbitalStrikeTimer > 0) {
      _orbitalStrikeTimer = max(0.0, _orbitalStrikeTimer - dt);
      if (_orbitalStrikeTimer <= 0) {
        _orbitalStrikePos = null;
      }
    }
    _updateTimedSpeedEffects(dt);
    if (player.currentHp <= 0) {
      lockedTarget = null;
      _foxRunning = false;
      return;
    }

    // 1. Quỹ đạo bay
    orbitAngle = (orbitAngle + orbitSpeed * dt) % (2 * pi);
    bobbingTimer += dt;

    if (companionId == 'luna_fox') {
      _followFoxOnGround(dt);
    } else if (type == CompanionType.aegisX9) {
      // Aegis-X9: Bay lơ lửng lệch sau vai phải với nội suy lò xo (Spring Damping) chuẩn assets_guid.md
      final shoulderOffset = Vector2(player.isFacingRight ? -28.0 : 28.0, -22.0 + cos(bobbingTimer * 4.0) * 3.0);
      final targetPos = player.position + shoulderOffset;
      position.add((targetPos - position) * min(1.0, 8.0 * dt));
    } else {
      // Quỹ đạo tròn chuẩn cho Attack / Shield / Frost Drone
      final bobbingY = sin(bobbingTimer * 4.0) * 3.5;
      final targetX = player.position.x + cos(orbitAngle) * orbitRadius;
      final targetY = player.position.y + sin(orbitAngle) * orbitRadius + bobbingY;
      position.setValues(targetX, targetY);
    }

    // 2. Logic đặc thù theo từng Archetype
    switch (type) {
      case CompanionType.attack:
        _updateAttackDrone(dt);
        break;
      case CompanionType.shield:
        _updateShieldDrone(dt);
        break;
      case CompanionType.frost:
        _updateFrostDrone(dt);
        break;
      case CompanionType.aegisX9:
        _updateAegisX9(dt);
        break;
    }
  }

  // --- ARCHETYPE 4: AEGIS-X9 TINH LINH LÔI TỪ ---
  void _followFoxOnGround(double dt) {
    if (dt <= 0) return;
    if (!player.moveDirection.isZero()) {
      _foxTravelDirection.setFrom(player.moveDirection.normalized());
    }
    final target = player.position - _foxTravelDirection * 32 + Vector2(0, 12);
    final delta = target - position;
    final distance = delta.length;
    // Hysteresis prevents flickering between run/idle around the stop point.
    if (distance > 9) _foxRunning = true;
    if (distance <= 2) _foxRunning = false;
    if (!_foxRunning) return;
    final step = min(distance, max(100.0, player.speed * 1.25) * dt);
    final movement = delta / distance * step;
    position.add(movement);
    if (movement.x.abs() > .05) _foxFacingRight = movement.x > 0;
    _foxRunTime += dt;
    if (step >= distance) _foxRunning = false;
  }

  void _updateAegisX9(double dt) {
    if (!isMounted) return;

    // Tự động hút vàng/vật phẩm trong bán kính 120px
    for (final item in game.pickups) {
      if (!item.isMounted) continue;
      final dist = player.position.distanceTo(item.position);
      if (dist <= 120.0 && dist > 6.0) {
        final pullDir = (player.position - item.position).normalized();
        item.position.add(pullDir * 190.0 * dt);
      }
    }

    // Tự động bắn tia laser vàng mỗi 1.2s vào kẻ địch gần nhất trong tầm 200px
    if (actionCooldown > 0) actionCooldown -= dt;
    const attackRange = 200.0;
    PositionComponent? nearest;
    double nearestDist = attackRange;

    for (final z in game.enemies) {
      if (!z.isMounted || z.currentHp <= 0) continue;
      final dist = position.distanceTo(z.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = z;
      }
    }
    for (final s in game.skeletons) {
      if (!s.isMounted || s.currentHp <= 0) continue;
      final dist = position.distanceTo(s.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = s;
      }
    }
    for (final b in game.bosses) {
      if (!b.isMounted || b.isDefeated) continue;
      final dist = position.distanceTo(b.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = b;
      }
    }

    lockedTarget = nearest;
    if (lockedTarget != null && actionCooldown <= 0) {
      final toTarget = lockedTarget!.position - position;
      if (toTarget.length2 > 0) {
        final plasma = CompanionPlasmaProjectile(
          position: position.clone(),
          direction: toTarget.normalized(),
        );
        game.world.add(plasma);
        actionCooldown = 1.2;
      }
    }
  }

  // --- ARCHETYPE 1: ATTACK DRONE ---
  void _updateAttackDrone(double dt) {
    if (actionCooldown > 0) actionCooldown -= dt;

    if (!isMounted) return;

    // Tìm quái gần nhất trong bán kính 180px
    const attackRange = 180.0;
    PositionComponent? nearest;
    double nearestDist = attackRange;

    for (final z in game.enemies) {
      if (!z.isMounted || z.currentHp <= 0) continue;
      final dist = position.distanceTo(z.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = z;
      }
    }

    for (final s in game.skeletons) {
      if (!s.isMounted || s.currentHp <= 0) continue;
      final dist = position.distanceTo(s.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = s;
      }
    }

    for (final b in game.bosses) {
      if (!b.isMounted || b.isDefeated) continue;
      final dist = position.distanceTo(b.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = b;
      }
    }

    lockedTarget = nearest;

    // Bắn đạn mini plasma (ORBIT-03 bắn liên thanh 0.3s khi đang Overdrive)
    if (lockedTarget != null && actionCooldown <= 0) {
      final toTarget = lockedTarget!.position - position;
      if (toTarget.length2 > 0) {
        final dir = toTarget.normalized();
        final isOrbitRapid = companionId == 'orbit_03' && _rapidFireTimer > 0;
        final plasma = CompanionPlasmaProjectile(
          position: position.clone(),
          direction: dir,
          damage: isOrbitRapid ? 16.0 : 12.0,
          speed: isOrbitRapid ? 360.0 : 280.0,
          color: isOrbitRapid
              ? const Color(0xFFFFAB00)
              : const Color(0xFFFF1744),
        );
        game.world.add(plasma);
        actionCooldown = isOrbitRapid ? 0.3 : 1.5;
      }
    }
  }

  void _updateTimedSpeedEffects(double dt) {
    if (_timedSpeedEffects.isEmpty) return;
    final expired = <PositionComponent>[];
    for (final entry in _timedSpeedEffects.entries) {
      final enemy = entry.key;
      entry.value.remaining -= dt;
      if (!enemy.isMounted || entry.value.remaining <= 0) {
        expired.add(enemy);
      }
    }
    for (final enemy in expired) {
      final eff = _timedSpeedEffects.remove(enemy);
      if (eff != null && enemy.isMounted) {
        final auraOrig = _slowedEnemies[enemy];
        if (auraOrig != null) {
          _setEnemySpeed(enemy, auraOrig * 0.60);
        } else {
          _setEnemySpeed(enemy, eff.originalSpeed);
        }
      }
    }
  }

  // --- ARCHETYPE 2: SHIELD DRONE ---
  void _updateShieldDrone(double dt) {
    if (player.damageAbsorption != 0.30) {
      player.damageAbsorption = 0.30;
    }
  }

  // --- ARCHETYPE 3: FROST DRONE ---
  void _updateFrostDrone(double dt) {
    const frostAuraRadius = 130.0;
    final currentEnemiesInAura = <PositionComponent>{};

    if (!isMounted) return;

    final allMonsters = <PositionComponent>[
      ...game.enemies.where((e) => e.isMounted && e.currentHp > 0),
      ...game.skeletons.where((e) => e.isMounted && e.currentHp > 0),
      ...game.bosses.where((b) => b.isMounted && !b.isDefeated),
    ];

    for (final monster in allMonsters) {
      final dist = position.distanceTo(monster.position);
      if (dist <= frostAuraRadius) {
        currentEnemiesInAura.add(monster);
        if (!_slowedEnemies.containsKey(monster)) {
          if (monster is ZombieEnemy) {
            _slowedEnemies[monster] = monster.speed;
            monster.speed *= 0.60;
          } else if (monster is SkeletonEnemy) {
            _slowedEnemies[monster] = monster.speed;
            monster.speed *= 0.60;
          } else if (monster is BossEnemy) {
            _slowedEnemies[monster] = monster.currentSpeed;
            monster.currentSpeed *= 0.60;
          }
        }
      }
    }

    final exited = _slowedEnemies.keys
        .where((e) => !currentEnemiesInAura.contains(e) || !e.isMounted)
        .toList();

    for (final enemy in exited) {
      final origSpeed = _slowedEnemies.remove(enemy);
      if (origSpeed != null && enemy.isMounted) {
        if (enemy is ZombieEnemy) {
          enemy.speed = origSpeed;
        } else if (enemy is SkeletonEnemy) {
          enemy.speed = origSpeed;
        } else if (enemy is BossEnemy) {
          enemy.currentSpeed = origSpeed;
        }
      }
    }
  }

  // --- PROCEDURAL CANVAS RENDERING ---
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final droneCenter = Offset(size.x / 2, size.y / 2);
    final offsetToPlayer = Offset(
      player.position.x - position.x,
      player.position.y - position.y,
    );

    // Hiệu ứng kỹ năng đặc biệt nâng cấp (Sprite Frame Sheet + Procedural VFX riêng cho từng Trợ thủ)
    if (overdriveTimer > 0) {
      final playerCenter = droneCenter + offsetToPlayer;
      _renderSpecialSkillVfx(canvas, droneCenter, playerCenter);
    }

    // Hào quang kéo dài khi ORBIT-03 đang bắn liên thanh (4s)
    if (companionId == 'orbit_03' && _rapidFireTimer > 0) {
      final pulse = 0.55 + 0.35 * sin(bobbingTimer * 18.0);
      canvas.drawCircle(
        droneCenter,
        22.0,
        Paint()
          ..color = const Color(0xFFFFAB00).withValues(alpha: pulse * 0.25)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        droneCenter,
        22.0,
        Paint()
          ..color = const Color(0xFFFFD740).withValues(alpha: pulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // Hào quang lửa đỏ quanh người chơi suốt 5s buff +30% ATK của Pyro-Frost Dragon
    if (companionId == 'pyro_frost_dragon' && player.petAttackBuffTimer > 0) {
      final playerCenter = droneCenter + offsetToPlayer;
      final pulse = 0.5 + 0.4 * sin(bobbingTimer * 10.0);
      canvas.drawCircle(
        playerCenter,
        30.0 + sin(bobbingTimer * 8.0) * 3.0,
        Paint()
          ..color = const Color(0xFFFF5252).withValues(alpha: pulse * 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // Hiệu ứng tia Pháo Laser Quỹ Đạo từ trên trời xuống của ORBIT-03
    if (_orbitalStrikeTimer > 0 && _orbitalStrikePos != null) {
      _renderOrbitalStrikeVfx(canvas, droneCenter);
    }

    // World effects must be drawn before either sprite or procedural body.
    // A restored image must never bypass targeting lasers and defensive auras.
    if (type == CompanionType.shield) {
      _renderShieldDomeAndTether(canvas, droneCenter, offsetToPlayer);
    } else if (type == CompanionType.frost) {
      _renderFrostDecal(canvas, droneCenter, offsetToPlayer);
    } else if (_hasLivingTarget) {
      if (type == CompanionType.aegisX9) {
        _renderAegisLaser(canvas, droneCenter);
      } else if (type == CompanionType.attack) {
        _renderTargetingLaser(canvas, droneCenter);
      }
    }

    if (companionId == 'pyro_frost_dragon') {
      final sheet = SpriteImageCache.instance.getCompanionIdleSheet(companionId);
      if (sheet != null) {
        DragonSpiritVisual.draw(canvas, sheet, center: droneCenter, width: 52,
            seconds: bobbingTimer, facingRight: player.isFacingRight,
            empowered: overdriveTimer > 0);
        return;
      }
    }
    if (companionId == 'luna_fox') {
      FoxSpiritVisual.drawAura(canvas, center: droneCenter,
          seconds: bobbingTimer, empowered: overdriveTimer > 0);
      final idle = SpriteImageCache.instance.getCompanionIdleSheet(companionId);
      final run = SpriteImageCache.instance.getCompanionRunSheet(companionId);
      final sheet = _foxRunning ? (run ?? idle) : idle;
      if (sheet != null) {
        FoxSpiritVisual.drawSprite(canvas, sheet,
            center: droneCenter + Offset(0, _foxRunning && run != null ? 2 : 0),
            width: 42, seconds: _foxRunning ? _foxRunTime : bobbingTimer,
            facingRight: _foxFacingRight, running: _foxRunning && run != null);
        return;
      }
    }
    final compSprite = SpriteImageCache.instance.getCompanionImage(companionId);
    if (compSprite != null) {
      final srcRect = Rect.fromLTWH(
        0,
        0,
        compSprite.width.toDouble(),
        compSprite.height.toDouble(),
      );
      final dstRect = Rect.fromCenter(
        center: droneCenter,
        width: 30,
        height: 30,
      );
      canvas.drawImageRect(
        compSprite,
        srcRect,
        dstRect,
        Paint()..filterQuality = FilterQuality.none,
      );
      return;
    }

    if (type == CompanionType.aegisX9) {
      _renderAegisX9(canvas, droneCenter);
      return;
    }

    // 2. Bóng đổ lơ lửng trên mặt đất
    final bobbingScale =
        (1.0 - (sin(bobbingTimer * 4.0) * 0.15)).clamp(0.7, 1.3);
    final shadowPaint = Paint()..color = const Color(0x33000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(droneCenter.dx, droneCenter.dy + 16),
        width: 16 * bobbingScale,
        height: 5 * bobbingScale,
      ),
      shadowPaint,
    );

    // 3. Động cơ đẩy phản lực Ion (Thrusters & Particles)
    _renderThrusters(canvas, droneCenter);

    // 4. Thân vỏ Drone kim loại (Metallic Chassis)
    _renderChassis(canvas, droneCenter);

    // 5. Thấu kính / Lõi năng lượng phát sáng (Glowing Core / Sensor Lens)
    _renderGlowingCore(canvas, droneCenter);
  }

  void _renderSpecialSkillVfx(
    Canvas canvas,
    Offset droneCenter,
    Offset playerCenter,
  ) {
    final progress = (1.0 - (overdriveTimer / 2.5)).clamp(0.0, 0.999);
    final alpha = (overdriveTimer / 2.5).clamp(0.0, 1.0);
    final burstScale = 0.72 + progress * 0.48;
    final targetCenter =
        companionId == 'comp_attack' ? droneCenter : playerCenter;

    // 1. Sprite Frame Sheet (4-frame horizontal pixel-art VFX sinh từ Gemini)
    final sheet = SpriteImageCache.instance.getCompanionSkillSheet(companionId);
    if (sheet != null && sheet.width >= 4 && sheet.height > 0) {
      final frameIdx = (progress * 4).floor().clamp(0, 3);
      final frameW = sheet.width / 4.0;
      final srcRect = Rect.fromLTWH(
        frameIdx * frameW,
        0,
        frameW,
        sheet.height.toDouble(),
      );
      final baseSize = companionId == 'pyro_frost_dragon'
          ? 240.0
          : companionId == 'comp_control' || companionId == 'aegis_x9'
              ? 220.0
              : 185.0;
      final drawSize = baseSize * burstScale;
      final dstRect = Rect.fromCenter(
        center: targetCenter,
        width: drawSize,
        height: drawSize,
      );
      canvas.drawImageRect(
        sheet,
        srcRect,
        dstRect,
        Paint()
          ..filterQuality = FilterQuality.none
          ..blendMode = BlendMode.screen
          ..color = Colors.white.withValues(alpha: (alpha * 1.15).clamp(0.0, 1.0)),
      );
    }

    // 2. Procedural VFX lớp trên cho chuyển động 60fps mượt mà đặc trưng từng trợ thủ
    switch (companionId) {
      case 'comp_attack':
      case 'companion_attack':
      case 'attack':
        // Sóng xung kích đỏ + 6 tia năng lượng tỏa ra
        final r = 24.0 + progress * 115.0;
        canvas.drawCircle(
          droneCenter,
          r,
          Paint()
            ..color = const Color(0xFFFF5252).withValues(alpha: alpha * 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        for (int i = 0; i < 6; i++) {
          final rad = (i * pi / 3) + orbitAngle;
          final p1 = droneCenter + Offset(cos(rad) * 14, sin(rad) * 14);
          final p2 = droneCenter + Offset(cos(rad) * r, sin(rad) * r);
          canvas.drawLine(
            p1,
            p2,
            Paint()
              ..color = const Color(0xFFFFD54F).withValues(alpha: alpha * 0.7)
              ..strokeWidth = 2.0,
          );
        }
        break;

      case 'comp_defense':
      case 'companion_defense':
      case 'defense':
      case 'shield':
        // Lồng lục giác xoay + 2 đợt sóng đẩy lùi xanh dương
        final pushR = 32.0 + progress * 125.0;
        canvas.drawCircle(
          playerCenter,
          pushR,
          Paint()
            ..color = const Color(0xFF448AFF).withValues(alpha: alpha * 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.8,
        );
        final hexPath = Path();
        for (int i = 0; i < 6; i++) {
          final rad = bobbingTimer * 2.2 + i * pi / 3;
          final pt = playerCenter + Offset(cos(rad) * 42, sin(rad) * 42);
          if (i == 0) {
            hexPath.moveTo(pt.dx, pt.dy);
          } else {
            hexPath.lineTo(pt.dx, pt.dy);
          }
        }
        hexPath.close();
        canvas.drawPath(
          hexPath,
          Paint()
            ..color = const Color(0xFF00E5FF).withValues(alpha: alpha * 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        break;

      case 'comp_control':
      case 'companion_frost':
      case 'control':
      case 'frost':
        // Hoa tuyết 6 cánh xoay + tinh thể băng nhọn quanh rìa 160px
        final iceR = 40.0 + progress * 135.0;
        canvas.drawCircle(
          playerCenter,
          iceR,
          Paint()
            ..color = const Color(0xFF18FFFF).withValues(alpha: alpha * 0.14),
        );
        for (int i = 0; i < 6; i++) {
          final rad = bobbingTimer * 1.4 + i * pi / 3;
          final tip = playerCenter + Offset(cos(rad) * iceR, sin(rad) * iceR);
          canvas.drawLine(
            playerCenter,
            tip,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: alpha * 0.75)
              ..strokeWidth = 2.0,
          );
          canvas.drawCircle(
            tip,
            4.5,
            Paint()..color = Colors.white.withValues(alpha: alpha * 0.9),
          );
        }
        break;

      case 'cyber_drone':
        // Vòng hồi máu xanh ngọc + dấu '+' bay lên quanh nhân vật
        canvas.drawCircle(
          playerCenter,
          36.0 + progress * 34.0,
          Paint()
            ..color = const Color(0xFF00E676).withValues(alpha: alpha * 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        final crossPaint = Paint()
          ..color = const Color(0xFF00E676).withValues(alpha: alpha)
          ..strokeWidth = 2.2;
        for (int i = 0; i < 5; i++) {
          final rad = i * (2 * pi / 5) + bobbingTimer * 1.5;
          final cx = playerCenter.dx + cos(rad) * 32;
          final cy = playerCenter.dy + sin(rad) * 18 - progress * 28.0;
          canvas.drawLine(Offset(cx - 4, cy), Offset(cx + 4, cy), crossPaint);
          canvas.drawLine(Offset(cx, cy - 4), Offset(cx, cy + 4), crossPaint);
        }
        break;

      case 'luna_fox':
        // 5 đốm Hồ Hỏa lam ngọc xoay xoắn ốc quanh nhân vật
        canvas.drawCircle(
          playerCenter,
          44.0 + progress * 60.0,
          Paint()
            ..color = const Color(0xFF80D8FF).withValues(alpha: alpha * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        for (int i = 0; i < 5; i++) {
          final rad = bobbingTimer * 4.5 + i * (2 * pi / 5);
          final wispR = 30.0 + progress * 55.0;
          final pt = playerCenter + Offset(cos(rad) * wispR, sin(rad) * wispR);
          canvas.drawCircle(
            pt,
            6.0,
            Paint()
              ..color = const Color(0xFF80D8FF).withValues(alpha: alpha * 0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
          canvas.drawCircle(
            pt,
            3.0,
            Paint()..color = Colors.white.withValues(alpha: alpha * 0.95),
          );
        }
        break;

      case 'orbit_03':
        // Vòng ngắm khóa mục tiêu xoay quanh drone
        canvas.drawCircle(
          droneCenter,
          28.0 + progress * 24.0,
          Paint()
            ..color = const Color(0xFFFFAB00).withValues(alpha: alpha * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        break;

      case 'pyro_frost_dragon':
        // Vòng xoáy song nguyên Lửa (đỏ cam) & Băng (xanh cyan) xoay ngược chiều
        final r = 45.0 + progress * 125.0;
        canvas.drawCircle(
          playerCenter,
          r,
          Paint()
            ..color = const Color(0xFFFF5252).withValues(alpha: alpha * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        canvas.drawCircle(
          playerCenter,
          r * 0.72,
          Paint()
            ..color = const Color(0xFF18FFFF).withValues(alpha: alpha * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        for (int i = 0; i < 8; i++) {
          final isFire = i.isEven;
          final rad = (isFire ? bobbingTimer * 3.8 : -bobbingTimer * 3.8) +
              i * (pi / 4);
          final pt = playerCenter + Offset(cos(rad) * (r * 0.85), sin(rad) * (r * 0.85));
          canvas.drawCircle(
            pt,
            4.2,
            Paint()
              ..color = (isFire
                      ? const Color(0xFFFF6E40)
                      : const Color(0xFF18FFFF))
                  .withValues(alpha: alpha * 0.95),
          );
        }
        break;

      case 'aegis_x9':
      case 'comp_aegis':
      case 'aegis':
      default:
        // Vòng trọng lực hút vào tâm (implosion) + 6 tia sét vàng giật vào giữa
        final implodeR = (155.0 * (1.0 - progress * 0.65)).clamp(35.0, 155.0);
        canvas.drawCircle(
          playerCenter,
          implodeR,
          Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: alpha * 0.14),
        );
        canvas.drawCircle(
          playerCenter,
          implodeR,
          Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: alpha * 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        final arcPaint = Paint()
          ..color = const Color(0xFF00F0FF).withValues(alpha: alpha * 0.8)
          ..strokeWidth = 1.6;
        for (int i = 0; i < 6; i++) {
          final rad = bobbingTimer * 2.5 + i * (pi / 3);
          final outer =
              playerCenter + Offset(cos(rad) * implodeR, sin(rad) * implodeR);
          final mid = playerCenter +
              Offset(
                cos(rad + 0.18) * (implodeR * 0.55),
                sin(rad + 0.18) * (implodeR * 0.55),
              );
          canvas.drawLine(outer, mid, arcPaint);
          canvas.drawLine(mid, playerCenter, arcPaint);
        }
        break;
    }
  }

  void _renderOrbitalStrikeVfx(Canvas canvas, Offset droneCenter) {
    final alpha = (_orbitalStrikeTimer / 0.9).clamp(0.0, 1.0);
    final strikeOffset = Offset(
      _orbitalStrikePos!.x - position.x,
      _orbitalStrikePos!.y - position.y,
    );
    final impact = droneCenter + strikeOffset;

    // Tia laser quỹ đạo 3 lớp (cam ngoài -> vàng giữa -> trắng lõi)
    canvas.drawLine(
      Offset(impact.dx, impact.dy - 280),
      impact,
      Paint()
        ..color = const Color(0xFFFF6D00).withValues(alpha: alpha * 0.5)
        ..strokeWidth = 18.0 * alpha
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawLine(
      Offset(impact.dx, impact.dy - 280),
      impact,
      Paint()
        ..color = const Color(0xFFFFAB00).withValues(alpha: alpha * 0.9)
        ..strokeWidth = 10.0 * alpha,
    );
    canvas.drawLine(
      Offset(impact.dx, impact.dy - 280),
      impact,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 3.5 * alpha,
    );

    // Vòng nổ + tâm ngắm xoay tại điểm rơi
    final blastR = 90.0 * (1.12 - alpha * 0.32);
    canvas.drawCircle(
      impact,
      blastR,
      Paint()..color = const Color(0xFFFFAB00).withValues(alpha: alpha * 0.22),
    );
    canvas.drawCircle(
      impact,
      blastR,
      Paint()
        ..color = const Color(0xFFFFD740).withValues(alpha: alpha * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    // 4 vạch chữ thập tâm ngắm
    final reticlePaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * 0.85)
      ..strokeWidth = 1.6;
    for (int i = 0; i < 4; i++) {
      final rad = bobbingTimer * 6.0 + i * (pi / 2);
      canvas.drawLine(
        impact + Offset(cos(rad) * 14, sin(rad) * 14),
        impact + Offset(cos(rad) * 32, sin(rad) * 32),
        reticlePaint,
      );
    }
  }

  /// Vẽ Aegis-X9 - Tinh Linh Lôi Từ (Pha lê bát diện #FFD700 + 2 vòng Gyroscope bạc/cyan xoay chéo)
  void _renderAegisX9(Canvas canvas, Offset center) {
    // 1. Hào quang Aura Glow 30px
    canvas.drawCircle(
      center,
      16,
      Paint()
        ..color = const Color(0x44FFD700)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 3. Vòng Gyroscope kim loại bạc và xanh cyan xoay chéo góc nhau
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(bobbingTimer * 3.2);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 22, height: 9),
      Paint()
        ..color = const Color(0xFF00F0FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.rotate(-bobbingTimer * 6.4 + pi / 3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 20, height: 8),
      Paint()
        ..color = const Color(0xFFC0C8D8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();

    // 4. Lõi pha lê bát diện (Octahedron) màu vàng kim #FFD700
    final crystalPath = Path()
      ..moveTo(center.dx, center.dy - 7)
      ..lineTo(center.dx + 6, center.dy)
      ..lineTo(center.dx, center.dy + 7)
      ..lineTo(center.dx - 6, center.dy)
      ..close();
    canvas.drawPath(crystalPath, Paint()..color = const Color(0xFFFFD700));
    canvas.drawPath(
      crystalPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _renderThrusters(Canvas canvas, Offset center) {
    final flameH = 4.0 + sin(bobbingTimer * 14.0) * 1.8;
    final thrusterColor = type == CompanionType.attack
        ? const Color(0xFFFF9100)
        : type == CompanionType.shield
            ? const Color(0xFF00E5FF)
            : const Color(0xFF80D8FF);

    final flamePaint = Paint()..color = thrusterColor;

    for (final dx in [-5.0, 5.0]) {
      final fPath = Path()
        ..moveTo(center.dx + dx - 1.5, center.dy + 8)
        ..lineTo(center.dx + dx + 1.5, center.dy + 8)
        ..lineTo(center.dx + dx, center.dy + 8 + flameH)
        ..close();
      canvas.drawPath(fPath, flamePaint);

      final sparkY =
          center.dy + 8 + flameH + (sin(bobbingTimer * 20.0 + dx) + 1.0) * 2.0;
      final sparkPaint = Paint()..color = thrusterColor.withValues(alpha: 0.6);
      canvas.drawCircle(Offset(center.dx + dx, sparkY), 1.0, sparkPaint);
    }
  }

  void _renderChassis(Canvas canvas, Offset center) {
    final framePaint = Paint()..color = const Color(0xFF263238);
    final armorPaint = Paint()..color = const Color(0xFF546E7A);
    final highlightPaint = Paint()..color = const Color(0xFFB0BEC5);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 18, height: 16),
        const Radius.circular(4),
      ),
      framePaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy - 1), width: 14, height: 11),
        const Radius.circular(2),
      ),
      armorPaint,
    );

    canvas.drawLine(
      Offset(center.dx - 6, center.dy - 6),
      Offset(center.dx + 6, center.dy - 6),
      highlightPaint..strokeWidth = 1.0,
    );

    if (type == CompanionType.attack) {
      final cannonPaint = Paint()..color = const Color(0xFF212121);
      canvas.drawRect(
          Rect.fromLTWH(center.dx - 6, center.dy - 9, 2, 4), cannonPaint);
      canvas.drawRect(
          Rect.fromLTWH(center.dx + 4, center.dy - 9, 2, 4), cannonPaint);
    } else if (type == CompanionType.shield) {
      final nodePaint = Paint()..color = const Color(0xFF2979FF);
      canvas.drawCircle(Offset(center.dx - 8, center.dy), 1.8, nodePaint);
      canvas.drawCircle(Offset(center.dx + 8, center.dy), 1.8, nodePaint);
      canvas.drawCircle(Offset(center.dx, center.dy - 8), 1.8, nodePaint);
    } else if (type == CompanionType.frost) {
      final ringPaint = Paint()
        ..color = const Color(0xFF18FFFF).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, 10.5, ringPaint);
    }
  }

  void _renderGlowingCore(Canvas canvas, Offset center) {
    final coreColor = type.themeColor;

    final glowPaint = Paint()
      ..color = coreColor.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, 5.0, glowPaint);

    final lensPaint = Paint()..color = coreColor;
    canvas.drawCircle(center, 3.2, lensPaint);

    final pupilPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(center.dx - 0.8, center.dy - 0.8), 1.2, pupilPaint);
  }

  void _renderShieldDomeAndTether(
      Canvas canvas, Offset droneCenter, Offset toGeorge) {
    final georgeCenter = droneCenter + toGeorge;
    final pulseAlpha =
        (0.20 + sin(bobbingTimer * 3.5) * 0.08).clamp(0.12, 0.35);

    final tetherPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    canvas.drawLine(droneCenter, georgeCenter, tetherPaint);

    final domePaint = Paint()
      ..color = const Color(0xFF2979FF).withValues(alpha: pulseAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(georgeCenter, 26.0, domePaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(georgeCenter, 26.0, borderPaint);

    final rippleRadius = 26.0 + (bobbingTimer % 1.5) * 8.0;
    final rippleAlpha =
        (1.0 - ((bobbingTimer % 1.5) / 1.5)).clamp(0.0, 1.0) * 0.4;
    final ripplePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: rippleAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(georgeCenter, rippleRadius, ripplePaint);
  }

  void _renderFrostDecal(Canvas canvas, Offset droneCenter, Offset toGeorge) {
    final georgeCenter = droneCenter + toGeorge;

    final decalPaint = Paint()
      ..color = const Color(0xFF18FFFF).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(georgeCenter, 130.0, decalPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF18FFFF).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(georgeCenter, 130.0, borderPaint);

    final runeAngle = bobbingTimer * 0.5;
    final runePaint = Paint()
      ..color = const Color(0xFF80D8FF).withValues(alpha: 0.25)
      ..strokeWidth = 1.0;

    for (int i = 0; i < 6; i++) {
      final rad = runeAngle + (i * pi / 3);
      final p1 = georgeCenter + Offset(cos(rad) * 20, sin(rad) * 20);
      final p2 = georgeCenter + Offset(cos(rad) * 120, sin(rad) * 120);
      canvas.drawLine(p1, p2, runePaint);
    }
  }

  bool get _hasLivingTarget {
    final target = lockedTarget;
    if (target == null || !target.isMounted) return false;
    if (target is ZombieEnemy) return target.currentHp > 0;
    if (target is SkeletonEnemy) return target.currentHp > 0;
    if (target is BossEnemy) return !target.isDefeated && target.currentHp > 0;
    return false;
  }

  void _renderAegisLaser(Canvas canvas, Offset center) {
    final targetOffset = Offset(lockedTarget!.position.x - position.x,
        lockedTarget!.position.y - position.y);
    canvas.drawLine(center, center + targetOffset,
        Paint()..color = const Color(0x66FFD700)..strokeWidth = 1.2);
  }

  void _renderTargetingLaser(Canvas canvas, Offset droneCenter) {
    final targetOffset = Offset(
      lockedTarget!.position.x - position.x,
      lockedTarget!.position.y - position.y,
    );
    final laserPaint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    canvas.drawLine(droneCenter, droneCenter + targetOffset, laserPaint);
  }
}

class _TimedSpeedEffect {
  final double originalSpeed;
  double remaining;

  _TimedSpeedEffect({required this.originalSpeed, required this.remaining});
}

/// Tia đạn Plasma mini của Attack Drone / Cyber Drone / ORBIT-03 / Aegis-X9
class CompanionPlasmaProjectile extends PositionComponent
    with CollisionCallbacks, HasGameReference<BigWarGame> {
  final Vector2 direction;
  final double speed;
  final double damage;
  final Color color;

  double _lifeTimer = 0.0;
  bool _hasHit = false;

  CompanionPlasmaProjectile({
    required Vector2 position,
    required Vector2 direction,
    this.speed = 280.0,
    this.damage = 12.0,
    this.color = const Color(0xFFFF1744),
  })  : direction =
            direction.length2 > 0 ? direction.normalized() : Vector2(1, 0),
        super(
          position: position,
          size: Vector2(12, 12),
          anchor: Anchor.center,
        ) {
    angle = atan2(this.direction.y, this.direction.x);
    add(CircleHitbox(
      radius: 5,
      position: Vector2(1, 1),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hasHit) return;

    _lifeTimer += dt;
    if (_lifeTimer >= 1.5) {
      removeFromParent();
      return;
    }

    position.add(direction * speed * dt);
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (_hasHit) return;

    if (other is ZombieEnemy) {
      _hasHit = true;
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is SkeletonEnemy) {
      _hasHit = true;
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is BossEnemy) {
      _hasHit = true;
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is WallBlock) {
      _hasHit = true;
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final center = Offset(size.x / 2, size.y / 2);

    final haloPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(center, 5.5, haloPaint);

    final bodyPaint = Paint()..color = color;
    canvas.drawCircle(center, 3.8, bodyPaint);

    final corePaint = Paint()..color = const Color(0xFFFFF176);
    canvas.drawCircle(center, 2.0, corePaint);

    final whiteDot = Paint()..color = Colors.white;
    canvas.drawCircle(center, 1.0, whiteDot);
  }
}
