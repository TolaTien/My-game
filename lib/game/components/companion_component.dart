import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../registry/sprite_image_cache.dart';
import '../../services/audio_service.dart';
import '../gold_rush_game.dart';
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
      case 'gem_tumbler':
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
    with HasGameReference<GoldRushGame> {
  final String companionId;
  final CompanionType type;
  final PlayerComponent player;

  // Quỹ đạo bay quanh Player
  final double orbitRadius;
  double orbitAngle = 0.0;
  final double orbitSpeed = 1.5; // rad/s
  double bobbingTimer = 0.0;

  // Bộ đếm hành động đánh thường
  double actionCooldown = 0.0;
  PositionComponent? lockedTarget;

  // Kỹ năng Đặc biệt của Trợ thủ: Trường Trọng Lực Hoàng Kim (Golden Overdrive)
  static const double maxSpecialSkillCooldown = 14.0;
  static const double specialSkillMaxCooldown = maxSpecialSkillCooldown;
  double specialSkillCooldown = 0.0;
  double overdriveTimer = 0.0;

  // Quản lý trạng thái làm chậm của Frost Drone / Aegis-X9
  final Map<PositionComponent, double> _slowedEnemies = {};

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
    if (type == CompanionType.shield || type == CompanionType.aegisX9) {
      player.damageAbsorption = 0.0;
    }
    _restoreAllSlowedEnemies();
  }

  void _restoreAllSlowedEnemies() {
    for (final entry in _slowedEnemies.entries) {
      final enemy = entry.key;
      final origSpeed = entry.value;
      if (enemy.isMounted) {
        if (enemy is ZombieEnemy) {
          enemy.speed = origSpeed;
        } else if (enemy is SkeletonEnemy) {
          enemy.speed = origSpeed;
        } else if (enemy is BossEnemy) {
          enemy.currentSpeed = origSpeed;
        }
      }
    }
    _slowedEnemies.clear();
  }

  /// Kích hoạt Kỹ năng Đặc biệt của Trợ thủ: Trường Trọng Lực Hoàng Kim (Golden Overdrive)
  bool activateSpecialSkill() {
    if (specialSkillCooldown > 0) return false;
    specialSkillCooldown = maxSpecialSkillCooldown;
    overdriveTimer = 2.5;
    player.goldenShieldTimer = 4.0;
    if (player.damageAbsorption < 0.25) {
      player.damageAbsorption = 0.25;
    }

    AudioService.instance.playSfx(SfxSound.skillSmash);

    if (isMounted) {
      const pullRadius = 130.0;
      final allMonsters = <PositionComponent>[
        ...game.enemies.where((e) => e.isMounted && e.currentHp > 0),
        ...game.skeletons.where((e) => e.isMounted && e.currentHp > 0),
        if (game.boss != null && game.boss!.isMounted && !game.boss!.isDefeated)
          game.boss!,
      ];

      for (final m in allMonsters) {
        final dist = player.position.distanceTo(m.position);
        if (dist <= pullRadius && dist > 18) {
          final pullDir = (player.position - m.position).normalized();
          m.position.add(pullDir * min(36.0, dist * 0.45));
        }
      }
    }

    player.onStatsChanged?.call();
    return true;
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

    // 1. Quỹ đạo bay
    orbitAngle = (orbitAngle + orbitSpeed * dt) % (2 * pi);
    bobbingTimer += dt;

    if (type == CompanionType.aegisX9) {
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
    if (game.boss != null && game.boss!.isMounted && !game.boss!.isDefeated) {
      final dist = position.distanceTo(game.boss!.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = game.boss;
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

    if (game.boss != null && game.boss!.isMounted && !game.boss!.isDefeated) {
      final dist = position.distanceTo(game.boss!.position);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = game.boss;
      }
    }

    lockedTarget = nearest;

    // Bắn đạn mini plasma mỗi 1.5s vào quái gần nhất
    if (lockedTarget != null && actionCooldown <= 0) {
      final toTarget = lockedTarget!.position - position;
      if (toTarget.length2 > 0) {
        final dir = toTarget.normalized();
        final plasma = CompanionPlasmaProjectile(
          position: position.clone(),
          direction: dir,
        );
        game.world.add(plasma);
        actionCooldown = 1.5;
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
      if (game.boss != null && game.boss!.isMounted && !game.boss!.isDefeated)
        game.boss!,
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

    // Hiệu ứng Trường Trọng Lực Hoàng Kim (Golden Overdrive) khi kích hoạt
    if (overdriveTimer > 0) {
      final playerCenter = droneCenter + offsetToPlayer;
      final alpha = (overdriveTimer / 2.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        playerCenter,
        115,
        Paint()..color = const Color(0xFFFFD700).withValues(alpha: alpha * 0.14),
      );
      canvas.drawCircle(
        playerCenter,
        115,
        Paint()
          ..color = const Color(0xFFFFD700).withValues(alpha: alpha * 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    final compSprite = SpriteImageCache.instance.getCompanionImage(companionId);
    if (compSprite != null) {
      if (type == CompanionType.shield) {
        _renderShieldDomeAndTether(canvas, droneCenter, offsetToPlayer);
      } else if (type == CompanionType.frost) {
        _renderFrostDecal(canvas, droneCenter, offsetToPlayer);
      }
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

    // 1. Hiệu ứng Aura / World VFX
    if (type == CompanionType.shield) {
      _renderShieldDomeAndTether(canvas, droneCenter, offsetToPlayer);
    } else if (type == CompanionType.frost) {
      _renderFrostDecal(canvas, droneCenter, offsetToPlayer);
    } else if (type == CompanionType.attack &&
        lockedTarget != null &&
        lockedTarget!.isMounted) {
      _renderTargetingLaser(canvas, droneCenter);
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

    // 2. Tia laser vàng nhắm mục tiêu
    if (lockedTarget != null && lockedTarget!.isMounted) {
      final targetOffset = Offset(
        lockedTarget!.position.x - position.x,
        lockedTarget!.position.y - position.y,
      );
      canvas.drawLine(
        center,
        center + targetOffset,
        Paint()
          ..color = const Color(0x66FFD700)
          ..strokeWidth = 1.2,
      );
    }

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

/// Tia đạn Plasma mini của Attack Drone / Aegis-X9
class CompanionPlasmaProjectile extends PositionComponent
    with CollisionCallbacks, HasGameReference<GoldRushGame> {
  final Vector2 direction;
  final double speed = 280.0;
  final double damage = 12.0;

  double _lifeTimer = 0.0;
  bool _hasHit = false;

  CompanionPlasmaProjectile({
    required Vector2 position,
    required Vector2 direction,
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
      ..color = const Color(0x66FF1744)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(center, 5.5, haloPaint);

    final bodyPaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawCircle(center, 3.8, bodyPaint);

    final corePaint = Paint()..color = const Color(0xFFFFF176);
    canvas.drawCircle(center, 2.0, corePaint);

    final whiteDot = Paint()..color = Colors.white;
    canvas.drawCircle(center, 1.0, whiteDot);
  }
}
