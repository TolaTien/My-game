import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../registry/asset_registry.dart';
import '../components/floating_combat_text.dart';
import '../components/hero_projectile.dart';
import '../components/player.dart';

class HeroSkillMeta {
  final int slot;
  final String name;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final double kiCost;
  final double cooldown;
  final double damageMultiplier;
  final double radius;

  const HeroSkillMeta({
    required this.slot,
    required this.name,
    required this.shortLabel,
    required this.icon,
    required this.color,
    required this.kiCost,
    required this.cooldown,
    required this.damageMultiplier,
    required this.radius,
  });
}

/// Đại diện một mục tiêu có thể nhận sát thương / đẩy lùi từ kỹ năng (Quái PvE, Boss, hoặc Bot PvP).
class SkillTargetAdapter {
  final Vector2 Function() getPosition;
  final bool Function() isAlive;
  final void Function(double dmg, CombatTextType textType) applyDamage;
  final void Function(Vector2 delta)? pushBy;
  final double extraHitRadius;

  const SkillTargetAdapter({
    required this.getPosition,
    required this.isAlive,
    required this.applyDamage,
    this.pushBy,
    this.extraHitRadius = 0.0,
  });
}

/// Hệ thống trung tâm định nghĩa bộ 3 kỹ năng riêng biệt + cơ chế thực thi cho toàn bộ 9 nhân vật.
/// Dùng chung cho cả PvE (`BigWarGame`), PvP (`PvpArenaGame`) và HUD (`GameHudOverlay`, `PvpArenaScreen`).
class HeroSkillSystem {
  HeroSkillSystem._();

  static String normalizeHeroId(String heroId) {
    switch (heroId) {
      case 'nova':
        return 'nova_blade';
      case 'shadow':
        return 'shadow_01';
      case 'ember':
        return 'ember_02';
      default:
        return heroId;
    }
  }

  static bool isRangedHero(String heroId) {
    final id = normalizeHeroId(heroId);
    return id == 'ranger' || id == 'ember_02' || id == 'valeria';
  }

  static HeroSkillMeta getSkillMeta(String heroId, int slot) {
    final id = normalizeHeroId(heroId);
    final defaults = _defaultSkillMeta(id, slot);
    try {
      final skills = GameAssetRegistry.instance.getSkillsForHero(id);
      for (final s in skills) {
        if (s.slot == slot) {
          return HeroSkillMeta(
            slot: slot,
            name: s.name,
            shortLabel: '${s.kiCost.toInt()} Ki',
            icon: defaults.icon,
            color: defaults.color,
            kiCost: s.kiCost,
            cooldown: s.cooldown,
            damageMultiplier: s.damageMultiplier,
            radius: s.radius,
          );
        }
      }
    } catch (_) {}
    return defaults;
  }

  static HeroSkillMeta _defaultSkillMeta(String id, int slot) {
    switch (id) {
      case 'ranger':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Tiễn Vũ Liên Châu',
            shortLabel: '20 Ki',
            icon: Icons.north_east_rounded,
            color: Color(0xFF00C853),
            kiCost: 20,
            cooldown: 4.5,
            damageMultiplier: 1.15,
            radius: 240,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Nhào Lộn Bẫy Gai',
            shortLabel: '25 Ki',
            icon: Icons.rotate_left_rounded,
            color: Color(0xFF00BFA5),
            kiCost: 25,
            cooldown: 7.5,
            damageMultiplier: 1.9,
            radius: 100,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Mưa Sao Băng',
          shortLabel: '45 Ki',
          icon: Icons.auto_awesome_rounded,
          color: Color(0xFFFFAB00),
          kiCost: 45,
          cooldown: 12.0,
          damageMultiplier: 2.8,
          radius: 240,
        );

      case 'tanker':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Húc Khiên Xung Kích',
            shortLabel: '20 Ki',
            icon: Icons.shield_rounded,
            color: Color(0xFF1E88E5),
            kiCost: 20,
            cooldown: 5.0,
            damageMultiplier: 1.9,
            radius: 95,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Pháo Đài Sắt',
            shortLabel: '30 Ki',
            icon: Icons.security_rounded,
            color: Color(0xFF00ACC1),
            kiCost: 30,
            cooldown: 9.0,
            damageMultiplier: 1.4,
            radius: 110,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Địa Chấn Phán Quyết',
          shortLabel: '45 Ki',
          icon: Icons.public_rounded,
          color: Color(0xFF3949AB),
          kiCost: 45,
          cooldown: 13.0,
          damageMultiplier: 2.8,
          radius: 175,
        );

      case 'ninja':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Phi Tiêu Lướt Ảnh',
            shortLabel: '20 Ki',
            icon: Icons.star_rounded,
            color: Color(0xFFE91E63),
            kiCost: 20,
            cooldown: 4.5,
            damageMultiplier: 1.35,
            radius: 150,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Khói Ẩn Thân',
            shortLabel: '30 Ki',
            icon: Icons.visibility_off_rounded,
            color: Color(0xFF8E24AA),
            kiCost: 30,
            cooldown: 8.5,
            damageMultiplier: 1.7,
            radius: 100,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Ảnh Sát Liên Hoàn',
          shortLabel: '45 Ki',
          icon: Icons.close_rounded,
          color: Color(0xFFD50000),
          kiCost: 45,
          cooldown: 12.0,
          damageMultiplier: 3.2,
          radius: 130,
        );

      case 'valeria':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Băng Hỏa Trảm',
            shortLabel: '25 Ki',
            icon: Icons.ac_unit_rounded,
            color: Color(0xFF00B0FF),
            kiCost: 25,
            cooldown: 4.5,
            damageMultiplier: 1.5,
            radius: 160,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Vòng Xoáy Nguyên Tố',
            shortLabel: '35 Ki',
            icon: Icons.cyclone_rounded,
            color: Color(0xFF2979FF),
            kiCost: 35,
            cooldown: 9.0,
            damageMultiplier: 2.1,
            radius: 110,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Mưa Thiên Thạch Băng Hỏa',
          shortLabel: '55 Ki',
          icon: Icons.blur_on_rounded,
          color: Color(0xFFFF3D00),
          kiCost: 55,
          cooldown: 13.5,
          damageMultiplier: 3.1,
          radius: 185,
        );

      case 'garrick':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Đất Lở',
            shortLabel: '20 Ki',
            icon: Icons.landscape_rounded,
            color: Color(0xFFD97706),
            kiCost: 20,
            cooldown: 5.0,
            damageMultiplier: 2.0,
            radius: 170,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Hộ Thể Hoàng Kim',
            shortLabel: '35 Ki',
            icon: Icons.verified_user_rounded,
            color: Color(0xFFFFB300),
            kiCost: 35,
            cooldown: 9.0,
            damageMultiplier: 1.8,
            radius: 115,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Nội Địa Chấn',
          shortLabel: '50 Ki',
          icon: Icons.terrain_rounded,
          color: Color(0xFFBF360C),
          kiCost: 50,
          cooldown: 13.5,
          damageMultiplier: 3.3,
          radius: 175,
        );

      case 'nova_blade':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Energy Slash',
            shortLabel: '20 Ki',
            icon: Icons.waves_rounded,
            color: Color(0xFF00E5FF),
            kiCost: 20,
            cooldown: 4.0,
            damageMultiplier: 1.7,
            radius: 160,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Shadow Dash',
            shortLabel: '30 Ki',
            icon: Icons.double_arrow_rounded,
            color: Color(0xFF7C4DFF),
            kiCost: 30,
            cooldown: 7.5,
            damageMultiplier: 2.1,
            radius: 125,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Quantum Burst',
          shortLabel: '50 Ki',
          icon: Icons.flare_rounded,
          color: Color(0xFFD500F9),
          kiCost: 50,
          cooldown: 12.0,
          damageMultiplier: 3.0,
          radius: 200,
        );

      case 'shadow_01':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Plasma Shot',
            shortLabel: '20 Ki',
            icon: Icons.bolt_rounded,
            color: Color(0xFFAA00FF),
            kiCost: 20,
            cooldown: 4.0,
            damageMultiplier: 1.35,
            radius: 160,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Cyber Spin',
            shortLabel: '30 Ki',
            icon: Icons.cyclone_rounded,
            color: Color(0xFF7B1FA2),
            kiCost: 30,
            cooldown: 7.5,
            damageMultiplier: 2.2,
            radius: 115,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Phantom Dash',
          shortLabel: '50 Ki',
          icon: Icons.flash_auto_rounded,
          color: Color(0xFFE040FB),
          kiCost: 50,
          cooldown: 12.0,
          damageMultiplier: 3.1,
          radius: 165,
        );

      case 'ember_02':
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Hỏa Cầu Liên Hoàn',
            shortLabel: '20 Ki',
            icon: Icons.local_fire_department_rounded,
            color: Color(0xFFFF6D00),
            kiCost: 20,
            cooldown: 4.0,
            damageMultiplier: 1.45,
            radius: 150,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Cột Lửa Địa Ngục',
            shortLabel: '35 Ki',
            icon: Icons.fireplace_rounded,
            color: Color(0xFFFF3D00),
            kiCost: 35,
            cooldown: 8.0,
            damageMultiplier: 2.3,
            radius: 125,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Thái Dương Bộc Phá',
          shortLabel: '50 Ki',
          icon: Icons.wb_sunny_rounded,
          color: Color(0xFFD50000),
          kiCost: 50,
          cooldown: 12.5,
          damageMultiplier: 2.8,
          radius: 180,
        );

      case 'george':
      default:
        if (slot == 1) {
          return const HeroSkillMeta(
            slot: 1,
            name: 'Búa Cuồng Phong',
            shortLabel: '20 Ki',
            icon: Icons.cyclone,
            color: Color(0xFFFF9800),
            kiCost: 20,
            cooldown: 5.0,
            damageMultiplier: 1.8,
            radius: 95,
          );
        }
        if (slot == 2) {
          return const HeroSkillMeta(
            slot: 2,
            name: 'Nện Đất Chấn Động',
            shortLabel: '30 Ki',
            icon: Icons.landslide,
            color: Color(0xFFE65100),
            kiCost: 30,
            cooldown: 8.0,
            damageMultiplier: 2.4,
            radius: 120,
          );
        }
        return const HeroSkillMeta(
          slot: 3,
          name: 'Cơn Cuồng Nộ',
          shortLabel: '45 Ki',
          icon: Icons.whatshot,
          color: Color(0xFFC62828),
          kiCost: 45,
          cooldown: 13.0,
          damageMultiplier: 2.2,
          radius: 150,
        );
    }
  }

  /// Tìm hướng ngắm chuẩn về phía mục tiêu sống gần nhất (ưu tiên trong tầm 360px).
  static Vector2 resolveAimDirection(
    PlayerComponent player,
    List<SkillTargetAdapter> targets, {
    double maxRange = 360.0,
  }) {
    Vector2? dir;
    double bestDist = maxRange;
    for (final t in targets) {
      if (!t.isAlive()) continue;
      final d = player.position.distanceTo(t.getPosition());
      if (d < bestDist && d > 1.0) {
        bestDist = d;
        dir = (t.getPosition() - player.position).normalized();
      }
    }
    if (dir != null) {
      if (dir.x.abs() > 0.05) player.isFacingRight = dir.x > 0;
      return dir;
    }
    if (player.moveDirection.length2 > 0.01) {
      return player.moveDirection.normalized();
    }
    return Vector2(player.isFacingRight ? 1.0 : -1.0, 0.0);
  }

  static Vector2 _rotateVec(Vector2 v, double radians) {
    final c = cos(radians);
    final s = sin(radians);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  static void _damageCircle({
    required Vector2 origin,
    required double radius,
    required double damage,
    required List<SkillTargetAdapter> targets,
    required CombatTextType textType,
    double knockback = 0.0,
    bool pullInward = false,
  }) {
    for (final t in targets) {
      if (!t.isAlive()) continue;
      final pos = t.getPosition();
      final dist = origin.distanceTo(pos);
      if (dist <= radius + t.extraHitRadius) {
        t.applyDamage(damage, textType);
        if (knockback > 0 && t.pushBy != null && dist > 1.0) {
          final dir = (pos - origin).normalized();
          t.pushBy!(dir * (pullInward ? -knockback : knockback));
        }
      }
    }
  }

  static void _damageLine({
    required Vector2 start,
    required Vector2 end,
    required double halfWidth,
    required double damage,
    required List<SkillTargetAdapter> targets,
    required CombatTextType textType,
    double knockback = 0.0,
  }) {
    final seg = end - start;
    final len2 = seg.length2;
    if (len2 < 1.0) return;
    final dir = seg.normalized();
    for (final t in targets) {
      if (!t.isAlive()) continue;
      final pos = t.getPosition();
      final proj = ((pos - start).dot(seg) / len2).clamp(0.0, 1.0);
      final closest = start + seg * proj;
      if (pos.distanceTo(closest) <= halfWidth + t.extraHitRadius) {
        t.applyDamage(damage, textType);
        if (knockback > 0 && t.pushBy != null) {
          t.pushBy!(dir * knockback);
        }
      }
    }
  }

  static void _spawnProjectile({
    required Component world,
    required Vector2 position,
    required Vector2 direction,
    required double damage,
    required HeroProjectileType type,
    bool piercing = false,
    double splashRadius = 0.0,
    double? speedOverride,
    double maxLifetime = 1.35,
    required void Function(Vector2 hitPos, int dmg, CombatTextType type) onDamageText,
    CombatTextType textType = CombatTextType.skillDamage,
    void Function(HeroProjectile)? onProjectileSpawned,
  }) {
    final projectile = HeroProjectile(
      position: position,
      direction: direction,
      damage: damage,
      type: type,
      isFromPlayer: true,
      piercing: piercing,
      splashRadius: splashRadius,
      speedOverride: speedOverride,
      maxLifetime: maxLifetime,
      onHit: (target, hitPos) {
        onDamageText(hitPos, damage.toInt(), textType);
      },
    );
    onProjectileSpawned?.call(projectile);
    world.add(projectile);
  }

  /// Thực thi kỹ năng riêng biệt cho từng nhân vật (slot = 1, 2, 3).
  static void executeSkill({
    required int slot,
    required PlayerComponent player,
    required Component world,
    required List<SkillTargetAdapter> targets,
    required void Function(Vector2 pos, int dmg, CombatTextType type) onDamageText,
    required void Function(Vector2 pos, String text) onBannerText,
    void Function(Vector2 targetPos)? clampPlayerPos,
    void Function(HeroProjectile)? onProjectileSpawned,
  }) {
    final id = normalizeHeroId(player.heroId);
    final meta = getSkillMeta(id, slot);
    final baseDmg = player.effectiveDamage;
    final aim = resolveAimDirection(player, targets);

    void safeMoveTo(Vector2 nextPos) {
      player.previousPosition = player.position.clone();
      player.position.setFrom(nextPos);
      clampPlayerPos?.call(player.position);
    }

    if (slot == 1) {
      switch (id) {
        case 'ranger':
          // 5 mũi tên phong linh hình quạt
          for (final deg in [-24.0, -12.0, 0.0, 12.0, 24.0]) {
            _spawnProjectile(
              world: world,
              position: player.position.clone() + aim * 12,
              direction: _rotateVec(aim, deg * pi / 180.0),
              damage: baseDmg * meta.damageMultiplier,
              type: HeroProjectileType.arrow,
              onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            );
          }
          break;

        case 'tanker':
          // Húc Khiên Xung Kích: lao 95px về phía trước, húc văng mục tiêu
          final start = player.position.clone();
          final end = start + aim * 95.0;
          safeMoveTo(end);
          player.skill1StartOffset = start - player.position;
          _damageLine(
            start: start,
            end: player.position,
            halfWidth: 34.0,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.skillDamage,
            knockback: 38.0,
          );
          break;

        case 'ninja':
          // Phi Tiêu Lướt Ảnh: phóng 3 phi tiêu xuyên thấu + lướt 85px
          final start = player.position.clone();
          for (final deg in [-16.0, 0.0, 16.0]) {
            _spawnProjectile(
              world: world,
              position: start + aim * 10,
              direction: _rotateVec(aim, deg * pi / 180.0),
              damage: baseDmg * meta.damageMultiplier,
              type: HeroProjectileType.shuriken,
              piercing: true,
              maxLifetime: 0.9,
              onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            );
          }
          safeMoveTo(start + aim * 85.0);
          player.skill1StartOffset = start - player.position;
          break;

        case 'valeria':
          // Băng Hỏa Trảm: bắn cặp Cầu Băng + Cầu Lửa song hành
          final perp = Vector2(-aim.y, aim.x) * 10.0;
          _spawnProjectile(
            world: world,
            position: player.position.clone() + aim * 12 + perp,
            direction: aim,
            damage: baseDmg * meta.damageMultiplier,
            type: HeroProjectileType.frostOrb,
            piercing: true,
            onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
          );
          _spawnProjectile(
            world: world,
            position: player.position.clone() + aim * 12 - perp,
            direction: aim,
            damage: baseDmg * meta.damageMultiplier,
            type: HeroProjectileType.fireball,
            splashRadius: 48.0,
            onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
          );
          break;

        case 'garrick':
          // Đất Lở: hàng gai đá vàng thổ dài 170px theo đường thẳng
          final start = player.position.clone();
          final end = start + aim * meta.radius;
          _damageLine(
            start: start,
            end: end,
            halfWidth: 32.0,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.skillDamage,
            knockback: 26.0,
          );
          break;

        case 'nova_blade':
          // Energy Slash: sóng kiếm năng lượng Cyan xuyên thấu
          _spawnProjectile(
            world: world,
            position: player.position.clone() + aim * 16,
            direction: aim,
            damage: baseDmg * meta.damageMultiplier,
            type: HeroProjectileType.energyWave,
            piercing: true,
            maxLifetime: 0.75,
            onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
          );
          break;

        case 'shadow_01':
          // Plasma Shot: 3 lưỡi dao hư không tốc độ cao
          for (final deg in [-12.0, 0.0, 12.0]) {
            _spawnProjectile(
              world: world,
              position: player.position.clone() + aim * 12,
              direction: _rotateVec(aim, deg * pi / 180.0),
              damage: baseDmg * meta.damageMultiplier,
              type: HeroProjectileType.voidBlade,
              onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            );
          }
          break;

        case 'ember_02':
          // Hỏa Cầu Liên Hoàn: 3 cầu lửa nổ lan hình quạt
          for (final deg in [-18.0, 0.0, 18.0]) {
            _spawnProjectile(
              world: world,
              position: player.position.clone() + aim * 12,
              direction: _rotateVec(aim, deg * pi / 180.0),
              damage: baseDmg * meta.damageMultiplier,
              type: HeroProjectileType.fireball,
              splashRadius: 45.0,
              onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            );
          }
          break;

        case 'george':
        default:
          // Búa Cuồng Phong: xoay búa 360° hút nhẹ và chém diện rộng
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.skillDamage,
            knockback: 14.0,
            pullInward: true,
          );
          break;
      }
      return;
    }

    if (slot == 2) {
      switch (id) {
        case 'ranger':
          // Nhào Lộn Bẫy Gai: đặt bẫy nổ tại chỗ cũ + lộn né 85px + tăng tốc 2.5s
          final trapOrigin = player.position.clone();
          _damageCircle(
            origin: trapOrigin,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 36.0,
          );
          final escapeDir = player.moveDirection.length2 > 0.05
              ? player.moveDirection.normalized()
              : -aim;
          safeMoveTo(trapOrigin + escapeDir * 85.0);
          player.activateSpeedBoost(duration: 2.5, multiplier: 1.35);
          onBannerText(player.position, 'BẪY GAI!');
          break;

        case 'tanker':
          // Pháo Đài Sắt: giáp giảm 65% dmg 4.5s + hồi 12% HP + phản xung kích
          player.activateIronShield(duration: 4.5, absorption: 0.65);
          player.heal(player.maxHp * 0.12);
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.skillDamage,
            knockback: 32.0,
          );
          onBannerText(player.position, 'PHÁO ĐÀI SẮT!');
          break;

        case 'ninja':
          // Khói Ẩn Thân: bom khói nổ + tàng hình 3.5s (+45% tốc, +40% dmg)
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.skillDamage,
            knockback: 22.0,
          );
          player.activateStealthVeil(duration: 3.5);
          onBannerText(player.position, 'KHÓI ẨN THÂN!');
          break;

        case 'valeria':
          // Vòng Xoáy Nguyên Tố: bão băng hỏa quanh thân + giáp 30%
          player.activateIronShield(duration: 4.0, absorption: 0.30);
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 18.0,
          );
          break;

        case 'garrick':
          // Hộ Thể Hoàng Kim: giáp đá 55% + hồi 8% HP + đẩy lùi
          player.activateIronShield(duration: 4.5, absorption: 0.55);
          player.heal(player.maxHp * 0.08);
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 38.0,
          );
          onBannerText(player.position, 'HỘ THỂ HOÀNG KIM!');
          break;

        case 'nova_blade':
          // Shadow Dash: lướt 125px xuyên qua kẻ địch chém vệt tím Neon
          final start = player.position.clone();
          safeMoveTo(start + aim * 125.0);
          player.skill1StartOffset = start - player.position;
          player.skill1TrailTimer = 0.4;
          _damageLine(
            start: start,
            end: player.position,
            halfWidth: 36.0,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 20.0,
          );
          break;

        case 'shadow_01':
          // Cyber Spin: xoay lưỡi hái 360° + tăng tốc 2s
          player.activateSpeedBoost(duration: 2.0, multiplier: 1.3);
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 16.0,
          );
          break;

        case 'ember_02':
          // Cột Lửa Địa Ngục: 4 cột lửa bùng nổ diện rộng
          _damageCircle(
            origin: player.position,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 24.0,
          );
          break;

        case 'george':
        default:
          // Nện Đất Chấn Động: chấn động mạnh phía trước + đẩy lùi
          final slamCenter = player.position + aim * 36.0;
          _damageCircle(
            origin: slamCenter,
            radius: meta.radius,
            damage: baseDmg * meta.damageMultiplier,
            targets: targets,
            textType: CombatTextType.criticalDamage,
            knockback: 42.0,
          );
          break;
      }
      return;
    }

    // SLOT 3 — ULTIMATE
    onBannerText(player.position, '${meta.name.toUpperCase()}!');
    switch (id) {
      case 'ranger':
        // Mưa Sao Băng: 8 mũi tên sao băng tỏa tròn + tập trung về phía mục tiêu
        for (int i = 0; i < 8; i++) {
          final spread = (i - 3.5) * 14.0 * pi / 180.0;
          _spawnProjectile(
            world: world,
            position: player.position.clone() + _rotateVec(aim, spread) * 10,
            direction: _rotateVec(aim, spread),
            damage: baseDmg * 1.15,
            type: HeroProjectileType.starArrow,
            piercing: true,
            onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            textType: CombatTextType.criticalDamage,
          );
        }
        _damageCircle(
          origin: player.position + aim * 70.0,
          radius: 130.0,
          damage: baseDmg * 1.8,
          targets: targets,
          textType: CombatTextType.criticalDamage,
        );
        break;

      case 'tanker':
        // Địa Chấn Phán Quyết: 3 vòng địa chấn hất văng diện rộng
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 55.0,
        );
        break;

      case 'ninja':
        // Ảnh Sát Liên Hoàn: dịch chuyển ra sau mục tiêu gần nhất và chém X chí mạng
        SkillTargetAdapter? nearest;
        double best = 240.0;
        for (final t in targets) {
          if (!t.isAlive()) continue;
          final d = player.position.distanceTo(t.getPosition());
          if (d < best) {
            best = d;
            nearest = t;
          }
        }
        if (nearest != null) {
          final tPos = nearest.getPosition();
          final dir = (tPos - player.position);
          final behind = dir.length2 > 1.0 ? dir.normalized() : aim;
          safeMoveTo(tPos + behind * 26.0);
          player.isFacingRight = behind.x < 0;
        } else {
          safeMoveTo(player.position + aim * 110.0);
        }
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
        );
        break;

      case 'valeria':
        // Mưa Thiên Thạch Băng Hỏa: 6 thiên thạch băng lửa nổ diện rộng
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 28.0,
        );
        break;

      case 'garrick':
        // Nội Địa Chấn: nhảy lao 60px nện nứt mặt đất 8 hướng
        safeMoveTo(player.position + aim * 60.0);
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 52.0,
        );
        break;

      case 'nova_blade':
        // Quantum Burst: hút vào tâm lượng tử rồi nổ 300%
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 35.0,
          pullInward: true,
        );
        break;

      case 'shadow_01':
        // Phantom Dash: lướt 140px xuyên chiến trường + kích nổ ấn chú hư không
        final start = player.position.clone();
        safeMoveTo(start + aim * 140.0);
        player.skill1StartOffset = start - player.position;
        player.skill1TrailTimer = 0.45;
        _damageLine(
          start: start,
          end: player.position,
          halfWidth: 42.0,
          damage: baseDmg * (meta.damageMultiplier * 0.6),
          targets: targets,
          textType: CombatTextType.criticalDamage,
        );
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * (meta.damageMultiplier * 0.65),
          targets: targets,
          textType: CombatTextType.criticalDamage,
        );
        break;

      case 'ember_02':
        // Thái Dương Bộc Phá: nổ 180px + bắn 8 cầu lửa 8 hướng
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 35.0,
        );
        for (int i = 0; i < 8; i++) {
          final a = i * (pi / 4);
          _spawnProjectile(
            world: world,
            position: player.position.clone(),
            direction: Vector2(cos(a), sin(a)),
            damage: baseDmg * 1.25,
            type: HeroProjectileType.fireball,
            splashRadius: 42.0,
            onDamageText: onDamageText,
              onProjectileSpawned: onProjectileSpawned,
            textType: CombatTextType.criticalDamage,
          );
        }
        break;

      case 'george':
      default:
        // Cơn Cuồng Nộ: nổ gầm xung kích + trạng thái cuồng nộ
        _damageCircle(
          origin: player.position,
          radius: meta.radius,
          damage: baseDmg * meta.damageMultiplier,
          targets: targets,
          textType: CombatTextType.criticalDamage,
          knockback: 36.0,
        );
        break;
    }
  }
}
