import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../models/pvp_match.dart';
import '../../registry/asset_registry.dart';
import '../../registry/sprite_image_cache.dart';
import '../../services/audio_service.dart';
import '../ai/pvp_bot_ai.dart';
import 'dungeon_map.dart';
import 'floating_combat_text.dart';
import 'hero_projectile.dart';
import 'player.dart';

class PvpBotPlayerComponent extends PositionComponent with CollisionCallbacks {
  final PvpOpponentInfo opponentInfo;
  final PlayerComponent targetPlayer;
  final bool enableAi;
  late final PvpBotAi aiController;

  double maxHp = 340.0;
  double currentHp = 340.0;
  double maxKi = 100.0;
  double currentKi = 100.0;
  double damage = 25.0;
  double speed = 150.0;

  bool isFacingRight = false;
  int facingRow = 0;
  bool isAttacking = false;
  double attackTimer = 0.0;
  double attackAngle = 0.0;
  double animTime = 0.0;

  bool isBerserk = false;
  double berserkTimer = 0.0;

  Vector2 moveDirection = Vector2.zero();
  Vector2 previousPosition = Vector2.zero();
  Vector2? targetPosition;
  Vector2 targetVelocity = Vector2.zero();

  // Speech bubble
  String? speechBubbleText;
  double speechBubbleTimer = 0.0;

  // Callback & arena awareness
  Function()? onStatsChanged;
  List<PositionComponent> Function()? getHostileTargets;
  bool Function()? canAct;
  List<Rect> Function()? getObstacleRects;
  List<Rect> Function()? getInteriorObstacleRects;
  List<List<bool>> Function()? getWalkableGrid;

  // Hitbox extents relative to component center (size: 36x40, hitbox: 24x28 at (6, 10))
  static const double _hitboxLeft = -12.0;
  static const double _hitboxRight = 12.0;
  static const double _hitboxTop = -10.0;
  static const double _hitboxBottom = 18.0;

  bool get isRangedHero {
    final id = opponentInfo.heroId;
    return id == 'ranger' || id == 'ember_02' || id == 'ember' || id == 'valeria';
  }

  PvpBotPlayerComponent({
    required Vector2 position,
    required this.opponentInfo,
    required this.targetPlayer,
    this.enableAi = true,
    this.getHostileTargets,
    this.canAct,
    this.getObstacleRects,
    this.getInteriorObstacleRects,
    this.getWalkableGrid,
  }) : super(
          position: position,
          size: Vector2(36, 40),
          anchor: Anchor.center,
        ) {
    _initBotStats();
    previousPosition = position.clone();
    isFacingRight = opponentInfo.isAlly;
    add(RectangleHitbox(
      size: Vector2(24, 28),
      position: Vector2(6, 10),
    ));

    aiController = PvpBotAi(
      difficulty: opponentInfo.difficulty,
      bot: this,
      targetPlayer: targetPlayer,
    );
    if (enableAi) add(aiController);
  }

  void _initBotStats() {
    try {
      final heroCfg = GameAssetRegistry.instance.getHero(opponentInfo.heroId);
      maxHp = heroCfg.baseStats.hp;
      currentHp = maxHp;
      maxKi = heroCfg.baseStats.ki;
      currentKi = maxKi;
      damage = heroCfg.baseStats.attack;
      speed = heroCfg.baseStats.speed;
    } catch (_) {
      maxHp = 340.0;
      currentHp = 340.0;
      maxKi = 100.0;
      currentKi = 100.0;
      damage = 25.0;
      speed = 150.0;
    }
  }

  /// Trả về mục tiêu sống gần nhất (hỗ trợ cả 1v1, 2v2, 4v4 cho Đồng đội & Đối thủ)
  PositionComponent? get primaryTarget {
    if (getHostileTargets != null) {
      final candidates = getHostileTargets!().where((c) {
        if (c is PlayerComponent) return c.currentHp > 0;
        if (c is PvpBotPlayerComponent) return c.currentHp > 0;
        return false;
      }).toList();
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) =>
          position.distanceToSquared(a.position).compareTo(position.distanceToSquared(b.position)));
      return candidates.first;
    }
    return targetPlayer.currentHp > 0 ? targetPlayer : null;
  }

  Rect _hitboxAt(double x, double y) => Rect.fromLTRB(
        x + _hitboxLeft,
        y + _hitboxTop,
        x + _hitboxRight,
        y + _hitboxBottom,
      );

  /// Di chuyển tách trục X/Y để bot trượt mượt dọc tường và cột trụ mà không bị kẹt góc.
  void _moveWithObstacleSliding(double dx, double dy) {
    final obstacles = getObstacleRects?.call();
    if (obstacles == null || obstacles.isEmpty) {
      position.x += dx;
      position.y += dy;
      return;
    }

    const eps = 0.05;

    // 1. Trục X
    if (dx.abs() > 1e-6) {
      final oldX = position.x;
      position.x += dx;
      final boxX = _hitboxAt(position.x, position.y);
      for (final obs in obstacles) {
        if (boxX.overlaps(obs)) {
          if (oldX + _hitboxRight <= obs.left + 1.0 || dx > 0 && oldX < obs.center.dx) {
            position.x = min(position.x, obs.left - _hitboxRight - eps);
          } else {
            position.x = max(position.x, obs.right - _hitboxLeft + eps);
          }
        }
      }
    }

    // 2. Trục Y
    if (dy.abs() > 1e-6) {
      final oldY = position.y;
      position.y += dy;
      final boxY = _hitboxAt(position.x, position.y);
      for (final obs in obstacles) {
        if (boxY.overlaps(obs)) {
          if (oldY + _hitboxBottom <= obs.top + 1.0 || dy > 0 && oldY < obs.center.dy) {
            position.y = min(position.y, obs.top - _hitboxBottom - eps);
          } else {
            position.y = max(position.y, obs.bottom - _hitboxTop + eps);
          }
        }
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (currentHp <= 0) return;

    animTime += dt;

    // Hồi Ki (+5 Ki/s)
    if (currentKi < maxKi) {
      currentKi = min(maxKi, currentKi + 5 * dt);
      onStatsChanged?.call();
    }

    // Cuồng nộ timer
    if (isBerserk) {
      berserkTimer -= dt;
      if (berserkTimer <= 0) {
        isBerserk = false;
        try {
          final heroCfg = GameAssetRegistry.instance.getHero(opponentInfo.heroId);
          speed = heroCfg.baseStats.speed;
          damage = heroCfg.baseStats.attack;
        } catch (_) {
          speed = 150.0;
          damage = 25.0;
        }
      }
    }

    // Attack animation timer
    if (isAttacking) {
      attackTimer += dt;
      attackAngle += 20 * dt;
      if (attackTimer >= 0.25) {
        isAttacking = false;
        attackTimer = 0.0;
      }
    }

    // Speech bubble timer
    if (speechBubbleTimer > 0) {
      speechBubbleTimer -= dt;
      if (speechBubbleTimer <= 0) {
        speechBubbleText = null;
      }
    }

    // Di chuyển cho bot AI cục bộ
    if (!moveDirection.isZero()) {
      previousPosition = position.clone();
      final effectiveSpeed = isBerserk ? speed * 1.5 : speed;
      final stepDir = moveDirection.length2 > 1.0001
          ? moveDirection.normalized()
          : moveDirection;
      _moveWithObstacleSliding(
        stepDir.x * effectiveSpeed * dt,
        stepDir.y * effectiveSpeed * dt,
      );

      final mx = stepDir.x;
      final my = stepDir.y;
      final absX = mx.abs();
      final absY = my.abs();

      if (absX > 0.05) isFacingRight = mx > 0;

      if (my > 0.08) {
        if (absX < 0.414 * absY) {
          facingRow = 0;
        } else if (absY < 0.414 * absX) {
          facingRow = 2;
        } else {
          facingRow = 1;
        }
      } else if (my < -0.08) {
        if (absX < 0.414 * absY) {
          facingRow = 4;
        } else if (absY < 0.414 * absX) {
          facingRow = 2;
        } else {
          facingRow = 3;
        }
      } else if (absX > 0.08) {
        facingRow = 2;
      }
    } else if (!enableAi) {
      previousPosition = position.clone();
      // 1. Dead Reckoning: tiếp tục di chuyển thời gian thực theo vận tốc đối thủ
      if (!targetVelocity.isZero()) {
        position.add(targetVelocity * dt);
        if (targetVelocity.x > 1.0) isFacingRight = true;
        if (targetVelocity.x < -1.0) isFacingRight = false;
      }

      // 2. Bù trừ sai số vị trí nhẹ nhàng (Smooth Error Blending)
      if (targetPosition != null) {
        final diff = targetPosition! - position;
        final distance = diff.length;
        if (distance > 150) {
          // Lệch quá xa (lag đột ngột) -> gán thẳng
          position.setFrom(targetPosition!);
        } else if (targetVelocity.isZero()) {
          // Khi đối thủ đã dừng -> hút nhanh về điểm dừng chính xác
          if (distance > 0.5) {
            position.add(diff * min(1.0, 25.0 * dt));
            if (diff.x > 1.5) isFacingRight = true;
            if (diff.x < -1.5) isFacingRight = false;
          } else {
            position.setFrom(targetPosition!);
          }
        } else if (distance > 2.0) {
          // Khi đối thủ đang chạy cùng nhịp -> chỉnh nhẹ góc lệch mà không giật
          position.add(diff * min(1.0, 10.0 * dt));
        }
      }
    }
  }

  void _spawnCombatText(Vector2 targetPos, double dmg, {bool isCrit = false}) {
    if (!isMounted || parent == null) return;
    parent!.add(FloatingCombatText(
      text: '-${dmg.toInt()}',
      position: targetPos.clone()..y -= 20,
      type: isCrit ? CombatTextType.criticalDamage : CombatTextType.normalDamage,
    ));
  }

  void _damageTargetsInRange(double dmg, double range, {bool isCrit = false}) {
    if (getHostileTargets != null) {
      for (final target in getHostileTargets!()) {
        if (position.distanceTo(target.position) <= range) {
          if (target is PlayerComponent && target.currentHp > 0) {
            target.takeDamage(dmg);
            _spawnCombatText(target.position, dmg, isCrit: isCrit);
          } else if (target is PvpBotPlayerComponent && target.currentHp > 0) {
            target.takeDamage(dmg);
            _spawnCombatText(target.position, dmg, isCrit: isCrit);
          }
        }
      }
      return;
    }
    if (targetPlayer.currentHp <= 0) return;
    final dist = position.distanceTo(targetPlayer.position);
    if (dist <= range) {
      targetPlayer.takeDamage(dmg);
      _spawnCombatText(targetPlayer.position, dmg, isCrit: isCrit);
    }
  }

  void performBasicAttack({bool force = false, Vector2? aimDirection}) {
    if ((!force && isAttacking) || currentHp <= 0) return;
    isAttacking = true;
    attackTimer = 0.0;
    attackAngle = isFacingRight ? -0.8 : 0.8;

    if (isRangedHero && parent != null && isMounted) {
      Vector2 dir;
      if (aimDirection != null && aimDirection.length2 > 0) {
        dir = aimDirection.normalized();
      } else if (primaryTarget != null && primaryTarget!.position != position) {
        dir = (primaryTarget!.position - position).normalized();
      } else {
        dir = Vector2(isFacingRight ? 1.0 : -1.0, 0.0);
      }

      if (dir.x.abs() > 0.01) isFacingRight = dir.x >= 0;

      final heroId = opponentInfo.heroId;
      final isRanger = heroId == 'ranger';
      final isEmber = heroId == 'ember_02' || heroId == 'ember';
      if (isRanger) {
        AudioService.instance.playSfx(SfxSound.attackArrow);
      } else {
        AudioService.instance.playSfx(SfxSound.attackHammer);
      }

      final pType = isRanger
          ? HeroProjectileType.arrow
          : (isEmber ? HeroProjectileType.fireball : HeroProjectileType.frostOrb);

      final projectile = HeroProjectile(
        position: position.clone() + Vector2(0, 2),
        direction: dir,
        damage: damage,
        type: pType,
        isFromPlayer: opponentInfo.isAlly,
        onHit: (target, hitPos) {
          _spawnCombatText(hitPos, damage);
        },
      );
      parent!.add(projectile);
      return;
    }

    _damageTargetsInRange(damage, 55);
  }

  Vector2 _resolveBotAimDirection() {
    if (primaryTarget != null && primaryTarget!.position != position) {
      final dir = (primaryTarget!.position - position).normalized();
      if (dir.x.abs() > 0.05) isFacingRight = dir.x > 0;
      return dir;
    }
    return Vector2(isFacingRight ? 1.0 : -1.0, 0.0);
  }

  Vector2 _rotateDir(Vector2 v, double radians) {
    final c = cos(radians);
    final s = sin(radians);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }

  void _spawnBotProjectile(
    Vector2 dir,
    HeroProjectileType type,
    double dmg, {
    bool piercing = false,
    double splashRadius = 0.0,
  }) {
    if (parent == null || !isMounted) return;
    parent!.add(HeroProjectile(
      position: position.clone() + dir * 10,
      direction: dir,
      damage: dmg,
      type: type,
      isFromPlayer: opponentInfo.isAlly,
      piercing: piercing,
      splashRadius: splashRadius,
      onHit: (target, hitPos) => _spawnCombatText(hitPos, dmg, isCrit: true),
    ));
  }

  void executeSkill1({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && currentKi < 20) return;
    currentKi = max(0, currentKi - 20);
    isAttacking = true;
    attackTimer = 0.0;
    final id = opponentInfo.heroId;
    final aim = _resolveBotAimDirection();

    if (id == 'ranger') {
      for (final deg in [-20.0, 0.0, 20.0]) {
        _spawnBotProjectile(_rotateDir(aim, deg * pi / 180), HeroProjectileType.arrow, damage * 1.15);
      }
    } else if (id == 'ninja') {
      for (final deg in [-15.0, 0.0, 15.0]) {
        _spawnBotProjectile(_rotateDir(aim, deg * pi / 180), HeroProjectileType.shuriken, damage * 1.25, piercing: true);
      }
    } else if (id == 'nova_blade' || id == 'nova') {
      _spawnBotProjectile(aim, HeroProjectileType.energyWave, damage * 1.65, piercing: true);
    } else if (id == 'shadow_01' || id == 'shadow') {
      for (final deg in [-12.0, 0.0, 12.0]) {
        _spawnBotProjectile(_rotateDir(aim, deg * pi / 180), HeroProjectileType.voidBlade, damage * 1.25);
      }
    } else if (id == 'ember_02' || id == 'ember') {
      for (final deg in [-16.0, 0.0, 16.0]) {
        _spawnBotProjectile(_rotateDir(aim, deg * pi / 180), HeroProjectileType.fireball, damage * 1.35, splashRadius: 40);
      }
    } else if (id == 'valeria') {
      _spawnBotProjectile(aim, HeroProjectileType.frostOrb, damage * 1.4, piercing: true);
      _spawnBotProjectile(aim, HeroProjectileType.fireball, damage * 1.4, splashRadius: 40);
    } else {
      _damageTargetsInRange(damage * 1.85, 95, isCrit: true);
    }
    onStatsChanged?.call();
  }

  void executeSkill2({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && currentKi < 30) return;
    currentKi = max(0, currentKi - 30);
    isAttacking = true;
    attackTimer = 0.0;
    final id = opponentInfo.heroId;
    if (id == 'tanker' || id == 'garrick') {
      currentHp = min(maxHp, currentHp + maxHp * 0.10);
      _damageTargetsInRange(damage * 1.6, 115, isCrit: true);
    } else {
      _damageTargetsInRange(damage * 2.2, 115, isCrit: true);
    }
    onStatsChanged?.call();
  }

  void executeSkill3({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && (currentKi < 45 || isBerserk)) return;
    currentKi = max(0, currentKi - 45);
    isAttacking = true;
    attackTimer = 0.0;
    final id = opponentInfo.heroId;
    final aim = _resolveBotAimDirection();
    if (id == 'george') {
      isBerserk = true;
      berserkTimer = 6.0;
      _damageTargetsInRange(damage * 2.1, 145, isCrit: true);
    } else if (id == 'ranger') {
      for (int i = 0; i < 6; i++) {
        final spread = (i - 2.5) * 14.0 * pi / 180.0;
        _spawnBotProjectile(_rotateDir(aim, spread), HeroProjectileType.starArrow, damage * 1.15, piercing: true);
      }
    } else if (id == 'ember_02' || id == 'ember') {
      _damageTargetsInRange(damage * 2.4, 160, isCrit: true);
      for (int i = 0; i < 6; i++) {
        final a = i * (pi / 3);
        _spawnBotProjectile(Vector2(cos(a), sin(a)), HeroProjectileType.fireball, damage * 1.15);
      }
    } else {
      _damageTargetsInRange(damage * 2.8, 165, isCrit: true);
    }
    onStatsChanged?.call();
  }

  void takeDamage(double dmg) {
    final effectiveDmg = isBerserk ? dmg * 0.6 : dmg;
    currentHp = max(0, currentHp - effectiveDmg);
    onStatsChanged?.call();

    // Phản xạ chat khi bị dính đòn đau
    if (effectiveDmg > 30 && Random().nextDouble() < 0.25 && speechBubbleText == null) {
      say(QuickChatPhrase.help.text);
    }
  }

  void say(String text) {
    speechBubbleText = text;
    speechBubbleTimer = 3.0; // 3 giây
  }

  void resetRound(Vector2 spawnPos) {
    position = spawnPos.clone();
    previousPosition = spawnPos.clone();
    currentHp = maxHp;
    currentKi = maxKi;
    try {
      final heroCfg = GameAssetRegistry.instance.getHero(opponentInfo.heroId);
      speed = heroCfg.baseStats.speed;
      damage = heroCfg.baseStats.attack;
    } catch (_) {
      speed = 150.0;
      damage = 25.0;
    }
    isBerserk = false;
    berserkTimer = 0.0;
    isAttacking = false;
    moveDirection = Vector2.zero();
    targetVelocity = Vector2.zero();
    targetPosition = null;
    speechBubbleText = null;
    aiController.resetRound();
    onStatsChanged?.call();
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (enableAi && getObstacleRects == null && other is WallBlock) {
      position = previousPosition.clone();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Vòng định danh phe dưới chân (Xanh lam/lục cho Đồng đội, Đỏ rực cho Đối thủ)
    final teamRingColor =
        opponentInfo.isAlly ? const Color(0xFF00E676) : const Color(0xFFFF1744);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 2), width: 30, height: 10),
      Paint()
        ..color = teamRingColor.withValues(alpha: currentHp > 0 ? 0.35 : 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final heroId = opponentInfo.heroId;
    final bool isNova = heroId == 'nova_blade' || heroId == 'nova';
    final bool isShadow = heroId == 'shadow_01' || heroId == 'shadow';
    final bool isEmber = heroId == 'ember_02' || heroId == 'ember';
    final bool isStripHero = SpriteImageCache.isStripAnimatedHero(heroId);
    final isMoving =
        !moveDirection.isZero() || (!enableAi && !targetVelocity.isZero());
    final bool novaMultiDirRun = isNova && isMoving && !isAttacking;
    final bool emberMultiDirRun = isEmber && isMoving && !isAttacking;
    final bool stripMultiDirRun = isStripHero && isMoving && !isAttacking;

    canvas.save();
    if (currentHp <= 0) {
      // Mờ đi khi bị hạ gục trong 2v2 / 4v4
      canvas.translate(0, 6);
    }
    if (!isFacingRight && !novaMultiDirRun && !emberMultiDirRun && !stripMultiDirRun) {
      canvas.scale(-1, 1);
      canvas.translate(-size.x, 0);
    }

    // Hiệu ứng Cuồng nộ nếu có
    if (isBerserk && currentHp > 0) {
      final aura = Paint()
        ..color = const Color(0x669C27B0)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 26, aura);
    }

    // 1. Bóng đổ
    final shadowPaint = Paint()..color = const Color(0x55000000);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.x / 2, size.y - 2), width: 24, height: 8),
      shadowPaint,
    );

    if (isStripHero) {
      final strip = isAttacking
          ? (SpriteImageCache.instance.getHeroAttackImage(heroId) ??
              SpriteImageCache.instance.getHeroIdleImage(heroId))
          : (isMoving
              ? (SpriteImageCache.instance.getHeroRunImage(heroId) ??
                  SpriteImageCache.instance.getHeroIdleImage(heroId))
              : SpriteImageCache.instance.getHeroIdleImage(heroId));
      if (strip != null && strip.width >= 512) {
        final bool is4DirRunSheet =
            !isAttacking && isMoving && strip.height >= 1000;
        final int cols = is4DirRunSheet
            ? 4
            : max(1, (strip.width / strip.height).round());
        final int row;
        if (is4DirRunSheet) {
          final mx = !moveDirection.isZero() ? moveDirection.x : targetVelocity.x;
          final my = !moveDirection.isZero() ? moveDirection.y : targetVelocity.y;
          if (my.abs() > mx.abs()) {
            row = my > 0 ? 0 : 1; // 0: Down, 1: Up
          } else {
            row = mx < 0 ? 2 : 3; // 2: Left, 3: Right
          }
        } else {
          row = 0;
        }
        final int col;
        if (isAttacking) {
          final progress =
              (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(0.0, 0.999);
          col = (progress * cols).floor().clamp(0, cols - 1);
        } else if (isMoving) {
          col = (animTime * 10.5).floor() % cols;
        } else {
          col = (animTime * 5.5).floor() % cols;
        }
        final cellW = strip.width / cols;
        final cellH = is4DirRunSheet ? strip.height / 4.0 : strip.height.toDouble();
        final srcRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);

        const dstW = 54.0;
        const dstH = 54.0;
        final dstLeft = (size.x - dstW) / 2;
        final dstTop = size.y - 2 - (236.0 / 256.0 * dstH);
        final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);

        canvas.drawImageRect(
          strip,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.none,
        );
        canvas.restore();
        if (speechBubbleText != null) {
          _renderSpeechBubble(canvas, speechBubbleText!);
        }
        return;
      }
    }

    if (isShadow) {
      final String action = isAttacking
          ? 'attack'
          : (isMoving ? 'run' : 'idle');
      final int frameIndex;
      if (isAttacking) {
        final progress =
            (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(0.0, 0.999);
        frameIndex = (progress * 16).floor().clamp(0, 15);
      } else if (isMoving) {
        frameIndex = (animTime * 14.0).floor() % 16;
      } else {
        frameIndex = (animTime * 11.0).floor() % 16;
      }

      final shadowImg = SpriteImageCache.instance
          .getHeroSequenceFrame('shadow_01', action, frameIndex);
      if (shadowImg != null) {
        const dstW = 52.0;
        const dstH = 52.0;
        final dstLeft = (size.x - dstW) / 2;
        final dstTop = size.y - 2 - dstH;
        final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
        final srcRect = Rect.fromLTWH(
          0,
          0,
          shadowImg.width.toDouble(),
          shadowImg.height.toDouble(),
        );
        canvas.drawImageRect(
          shadowImg,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.none,
        );
        canvas.restore();
        if (speechBubbleText != null) {
          _renderSpeechBubble(canvas, speechBubbleText!);
        }
        return;
      }
    } else if (isNova) {
      final heroSprite = isAttacking
          ? (SpriteImageCache.instance.getHeroAttackImage('nova_blade') ??
              SpriteImageCache.instance.getHeroImage('nova_blade'))
          : (isMoving
              ? (SpriteImageCache.instance.getHeroRunImage('nova_blade') ??
                  SpriteImageCache.instance.getHeroImage('nova_blade'))
              : (SpriteImageCache.instance.getHeroIdleImage('nova_blade') ??
                  SpriteImageCache.instance.getHeroImage('nova_blade')));
      if (heroSprite != null) {
        if (!isAttacking && isMoving && heroSprite.width >= 1500) {
          final vx = !moveDirection.isZero()
              ? moveDirection.x
              : (!enableAi ? targetVelocity.x : 0.0);
          final vy = !moveDirection.isZero()
              ? moveDirection.y
              : (!enableAi ? targetVelocity.y : 0.0);
          final absX = vx.abs();
          final absY = vy.abs();

          final int runRow;
          if (absX < 0.001 && absY < 0.001) {
            runRow = isFacingRight ? 3 : 2;
          } else if (absX < 0.414 * absY) {
            runRow = vy > 0 ? 0 : 1; // 0: Down, 1: Up
          } else if (absY < 0.414 * absX) {
            runRow = vx > 0 ? 3 : 2; // 3: Right, 2: Left
          } else {
            runRow = vx > 0 ? 5 : 4; // 5: Diagonal Right, 4: Diagonal Left
          }

          final col = (animTime * 14.0).floor() % 8;
          const cellW = 256.0;
          const cellH = 256.0;
          final srcRect =
              Rect.fromLTWH(col * cellW, runRow * cellH, cellW, cellH);

          const dstW = 48.0;
          const dstH = 48.0;
          final dstLeft = (size.x - dstW) / 2;
          final dstTop = size.y - 2 - (229.0 / 256.0 * dstH);
          final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);

          canvas.drawImageRect(
            heroSprite,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        } else {
          final row = facingRow.clamp(0, 4);
          final int col;
          if (isAttacking) {
            final progress =
                (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(0.0, 0.999);
            col = (progress * 5).floor().clamp(0, 4);
          } else if (isMoving) {
            col = (animTime * 11.0).floor() % 5;
          } else {
            col = (animTime * 4.5).floor() % 5;
          }

          final cellW = heroSprite.width / 5.0;
          final cellH = heroSprite.height / 5.0;
          final srcRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);

          final Rect dstRect;
          if (cellH >= 500) {
            const dstW = 96.0;
            const dstH = 96.0;
            final dstLeft = (size.x - dstW) / 2;
            final dstTop = size.y - 2 - (477.0 / 512.0 * dstH);
            dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          } else {
            const dstW = 48.0;
            const dstH = 48.0;
            final dstLeft = (size.x - dstW) / 2;
            final dstTop = size.y - 2 - (229.0 / 256.0 * dstH);
            dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          }

          canvas.drawImageRect(
            heroSprite,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        }
        canvas.restore();
        if (speechBubbleText != null) {
          _renderSpeechBubble(canvas, speechBubbleText!);
        }
        return;
      }
    } else if (isEmber) {
      final heroSprite = isAttacking
          ? (SpriteImageCache.instance.getHeroAttackImage('ember_02') ??
              SpriteImageCache.instance.getHeroAttackImage('ember') ??
              SpriteImageCache.instance.getHeroImage('ember_02'))
          : (isMoving
              ? (SpriteImageCache.instance.getHeroRunImage('ember_02') ??
                  SpriteImageCache.instance.getHeroRunImage('ember') ??
                  SpriteImageCache.instance.getHeroImage('ember_02'))
              : (SpriteImageCache.instance.getHeroIdleImage('ember_02') ??
                  SpriteImageCache.instance.getHeroIdleImage('ember') ??
                  SpriteImageCache.instance.getHeroImage('ember_02')));
      if (heroSprite != null) {
        if (!isAttacking && isMoving && heroSprite.width >= 1500) {
          final mx = !moveDirection.isZero() ? moveDirection.x : targetVelocity.x;
          final my = !moveDirection.isZero() ? moveDirection.y : targetVelocity.y;
          final absX = mx.abs();
          final absY = my.abs();

          final int runRow;
          if (absX < 0.001 && absY < 0.001) {
            runRow = isFacingRight ? 3 : 2;
          } else if (absX < 0.414 * absY) {
            runRow = my > 0 ? 0 : 1; // 0: Down, 1: Up
          } else if (absY < 0.414 * absX) {
            runRow = mx > 0 ? 3 : 2; // 3: Right, 2: Left
          } else {
            runRow = mx > 0 ? 5 : 4; // 5: Diag Right, 4: Diag Left
          }

          final col = (animTime * 14.0).floor() % 8;
          const cellW = 256.0;
          const cellH = 256.0;
          final srcRect =
              Rect.fromLTWH(col * cellW, runRow * cellH, cellW, cellH);

          const dstW = 48.0;
          const dstH = 48.0;
          final dstLeft = (size.x - dstW) / 2;
          final dstTop = size.y - 2 - (236.0 / 256.0 * dstH);
          final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);

          canvas.drawImageRect(
            heroSprite,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        } else {
          final row = facingRow.clamp(0, 4);
          final int col;
          if (isAttacking) {
            final progress =
                (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(0.0, 0.999);
            col = (progress * 5).floor().clamp(0, 4);
          } else if (isMoving) {
            col = (animTime * 12.0).floor() % 5;
          } else {
            col = (animTime * 4.5).floor() % 5;
          }

          final cellW = heroSprite.width / 5.0;
          final cellH = heroSprite.height / 5.0;
          final srcRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);

          final Rect dstRect;
          if (cellH >= 500) {
            const dstW = 96.0;
            const dstH = 96.0;
            final dstLeft = (size.x - dstW) / 2;
            final dstTop = size.y - 2 - (472.0 / 512.0 * dstH);
            dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          } else {
            const dstW = 48.0;
            const dstH = 48.0;
            final dstLeft = (size.x - dstW) / 2;
            final dstTop = size.y - 2 - (236.0 / 256.0 * dstH);
            dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          }

          canvas.drawImageRect(
            heroSprite,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        }
        canvas.restore();
        if (speechBubbleText != null) {
          _renderSpeechBubble(canvas, speechBubbleText!);
        }
        return;
      }
    } else {
      final botSprite = SpriteImageCache.isProceduralHero(heroId)
          ? null
          : (isAttacking
              ? (SpriteImageCache.instance.getHeroAttackImage(heroId) ??
                  SpriteImageCache.instance.getHeroImage(heroId))
              : SpriteImageCache.instance.getHeroImage(heroId));
      if (botSprite != null) {
        final srcRect = Rect.fromLTWH(
          0,
          0,
          botSprite.width.toDouble(),
          botSprite.height.toDouble(),
        );
        final dstRect = Rect.fromCenter(
          center: Offset(size.x / 2, size.y / 2 - 3),
          width: 46,
          height: 50,
        );
        canvas.drawImageRect(
          botSprite,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.none,
        );
        canvas.restore();
        if (speechBubbleText != null) {
          _renderSpeechBubble(canvas, speechBubbleText!);
        }
        return;
      }
    }

    final breathOffset = isMoving
        ? (sin(animTime * 15.0).abs() * -2.2)
        : (sin(animTime * 3.2) * 1.4);
    final legSwing = isMoving ? sin(animTime * 15.0) * 4.8 : 0.0;
    final leftLift = isMoving ? max(0.0, sin(animTime * 15.0)) * 2.5 : 0.0;
    final rightLift = isMoving ? max(0.0, -sin(animTime * 15.0)) * 2.5 : 0.0;
    final armSwing =
        isMoving ? sin(animTime * 15.0) * 0.32 : sin(animTime * 3.0) * 0.06;

    if (isMoving || isAttacking) {
      final attackLunge = isAttacking ? 3.5 : 0.0;
      canvas.translate(size.x / 2 + attackLunge, size.y / 2);
      canvas.rotate(isAttacking ? 0.18 : 0.13);
      canvas.translate(-size.x / 2, -size.y / 2);
    }

    Color bootsColor;
    Color armorColor;
    Color borderGold;
    Color helmetColor;
    Color crestColor;
    Color eyeColor;
    Color capeColor;

    switch (opponentInfo.heroId) {
      case 'valeria':
      case 'ranger':
        bootsColor = const Color(0xFF3E2723);
        armorColor = const Color(0xFF2E7D32);
        borderGold = const Color(0xFF00E676);
        helmetColor = const Color(0xFF1B5E20);
        crestColor = const Color(0xFFFFD54F);
        eyeColor = const Color(0xFFFFD600);
        capeColor = const Color(0xFF1B5E20);
        break;
      case 'garrick':
      case 'tanker':
        bootsColor = const Color(0xFF263238);
        armorColor = const Color(0xFF1565C0);
        borderGold = const Color(0xFFE0E0E0);
        helmetColor = const Color(0xFF37474F);
        crestColor = const Color(0xFF00B0FF);
        eyeColor = const Color(0xFF40C4FF);
        capeColor = const Color(0xFF0D47A1);
        break;
      case 'ninja':
        bootsColor = const Color(0xFF212121);
        armorColor = const Color(0xFF311B92);
        borderGold = const Color(0xFFE040FB);
        helmetColor = const Color(0xFF1A237E);
        crestColor = const Color(0xFF7B1FA2);
        eyeColor = const Color(0xFFE040FB);
        capeColor = const Color(0xFF4A148C);
        break;
      case 'george':
      default:
        bootsColor = const Color(0xFF37474F);
        armorColor = const Color(0xFFC62828);
        borderGold = const Color(0xFFFFD54F);
        helmetColor = const Color(0xFF78909C);
        crestColor = const Color(0xFFE53935);
        eyeColor = const Color(0xFF00E5FF);
        capeColor = const Color(0xFFB71C1C);
        break;
    }

    // 1.5 Áo choàng bay phía sau
    final capeWave = sin(animTime * 4.5) * 2.5 + (isMoving ? -5.0 : 0.0);
    final capePath = Path()
      ..moveTo(9, 15 + breathOffset)
      ..lineTo(22, 15 + breathOffset)
      ..quadraticBezierTo(9 + capeWave, 26, 3 + capeWave, 35)
      ..lineTo(16 + capeWave * 0.5, 34)
      ..close();
    canvas.drawPath(capePath, Paint()..color = capeColor.withValues(alpha: 0.85));

    // 2. Đôi chân chuyển động theo nhịp chạy
    final boots = Paint()..color = bootsColor;
    final lBoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(8 + legSwing * 0.7, 26 - leftLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    final rBoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(20.5 - legSwing * 0.7, 26 - rightLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(lBoot, boots);
    canvas.drawRRect(rBoot, boots);
    canvas.drawRect(
      Rect.fromLTWH(8 + legSwing * 0.7, 31 - leftLift, 7.5, 2.2),
      Paint()..color = borderGold,
    );
    canvas.drawRect(
      Rect.fromLTWH(20.5 - legSwing * 0.7, 31 - rightLift, 7.5, 2.2),
      Paint()..color = borderGold,
    );

    // 2.5 Tay sau
    canvas.save();
    canvas.translate(9, 17 + breathOffset);
    canvas.rotate(-armSwing);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, 0, 5.5, 10),
        const Radius.circular(2),
      ),
      Paint()..color = armorColor,
    );
    canvas.drawCircle(
      const Offset(0, 10),
      2.8,
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.restore();

    // 3. Giáp thân + Thắt lưng
    final armor = Paint()..color = armorColor;
    final torsoRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 14 + breathOffset, 20, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(torsoRRect, armor);
    canvas.drawRRect(
      torsoRRect,
      Paint()
        ..color = borderGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawRect(
      Rect.fromLTWH(8, 25 + breathOffset, 20, 3.2),
      Paint()..color = borderGold,
    );

    // 4. Cổ, Khuôn mặt & Mũ sắt
    canvas.drawRect(
      Rect.fromLTWH(14, 11 + breathOffset, 8, 4),
      Paint()..color = const Color(0xFFFBBF24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(9, 3 + breathOffset, 18, 11),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 1 + breathOffset, 20, 6),
        const Radius.circular(3),
      ),
      Paint()..color = helmetColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(15, -2 + breathOffset, 6, 5),
      Paint()..color = crestColor,
    );

    // Mắt phát sáng
    canvas.drawRect(
      Rect.fromLTWH(19, 8 + breathOffset, 5, 2.5),
      Paint()..color = eyeColor,
    );

    // 5. Tay trước & Vũ khí
    canvas.save();
    canvas.translate(size.x - 4, 19 + breathOffset);
    if (isAttacking) {
      canvas.rotate(attackAngle);
    } else {
      canvas.rotate(armSwing * 0.8);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, -2, 6, 10),
        const Radius.circular(2),
      ),
      Paint()..color = borderGold,
    );
    canvas.drawCircle(
      const Offset(-1, 7),
      3.0,
      Paint()..color = const Color(0xFFFDE68A),
    );
    if (opponentInfo.heroId == 'ranger' || opponentInfo.heroId == 'valeria') {
      final bowPaint = Paint()..color = const Color(0xFF6D4C41)..style = PaintingStyle.stroke..strokeWidth = 3;
      canvas.drawArc(const Rect.fromLTWH(-10, -22, 14, 28), -pi / 2, pi, false, bowPaint);
      canvas.drawLine(const Offset(-3, -22), const Offset(-3, 6), Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.5);
    } else if (opponentInfo.heroId == 'tanker' || opponentInfo.heroId == 'garrick') {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -22, 18, 22), const Radius.circular(5)), Paint()..color = const Color(0xFF0D47A1));
      canvas.drawLine(const Offset(-1, -20), const Offset(-1, -2), Paint()..color = const Color(0xFFFFD54F)..strokeWidth = 2);
    } else if (opponentInfo.heroId == 'ninja') {
      canvas.drawLine(const Offset(-2, 6), const Offset(-2, 0), Paint()..color = const Color(0xFFD50000)..strokeWidth = 3.5);
      canvas.drawLine(const Offset(-2, 0), const Offset(7, -24), Paint()..color = const Color(0xFFE0E0E0)..strokeWidth = 2.8);
      canvas.drawLine(const Offset(-7, 5), const Offset(-14, -18), Paint()..color = const Color(0xFFE0E0E0)..strokeWidth = 2.5);
    } else {
      final handle = Paint()..color = const Color(0xFF5D4037)..strokeWidth = 3;
      canvas.drawLine(const Offset(0, 8), const Offset(0, -18), handle);
      final head = Paint()..color = const Color(0xFF546E7A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -26, 16, 12), const Radius.circular(3)),
        head,
      );
      canvas.drawRect(const Rect.fromLTWH(-5, -23, 10, 6), Paint()..color = const Color(0xFFFFEB3B));
    }
    canvas.restore();
    canvas.restore();

    // --- THANH MÁU & TÊN BOT TRÊN ĐẦU ---
    _renderHpBarAndName(canvas);

    // --- BONG BÓNG QUICK CHAT (SPEECH BUBBLE) ---
    if (speechBubbleText != null) {
      _renderSpeechBubble(canvas, speechBubbleText!);
    }
  }

  void _renderHpBarAndName(Canvas canvas) {
    const barW = 34.0;
    const barH = 4.0;
    final bx = (size.x - barW) / 2;
    const by = -12.0;

    // Nền máu
    canvas.drawRect(Rect.fromLTWH(bx, by, barW, barH), Paint()..color = Colors.black54);
    // Vạch máu: Xanh lục cho đồng đội, Đỏ cho kẻ địch
    final hpColor = opponentInfo.isAlly
        ? const Color(0xFF00E676)
        : const Color(0xFFFF1744);
    final fillW = (currentHp / maxHp).clamp(0.0, 1.0) * barW;
    canvas.drawRect(Rect.fromLTWH(bx, by, fillW, barH), Paint()..color = hpColor);

    // Vạch Ki xanh tím nhỏ bên dưới
    const kiH = 2.0;
    final fillKi = (currentKi / maxKi).clamp(0.0, 1.0) * barW;
    canvas.drawRect(Rect.fromLTWH(bx, by + barH + 1, fillKi, kiH), Paint()..color = const Color(0xFFBA68C8));

    // Vẽ tên Bot nhỏ
    final nameColor = opponentInfo.isAlly
        ? const Color(0xFF80D8FF)
        : const Color(0xFFFFD54F);
    final textPainter = TextPainter(
      text: TextSpan(
        text: currentHp <= 0 ? '${opponentInfo.name} (K.O)' : opponentInfo.name,
        style: TextStyle(
          color: nameColor,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset((size.x - textPainter.width) / 2, by - 11));
  }

  void _renderSpeechBubble(Canvas canvas, String msg) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: msg,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bubbleW = textPainter.width + 12;
    final bubbleH = textPainter.height + 6;
    final bubbleX = (size.x - bubbleW) / 2;
    const bubbleY = -42.0;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleX, bubbleY, bubbleW, bubbleH),
      const Radius.circular(6),
    );

    // Nền trắng viền đen
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF333333)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Mũi nhọn bong bóng trỏ xuống
    final arrow = Path()
      ..moveTo(size.x / 2 - 3, bubbleY + bubbleH)
      ..lineTo(size.x / 2, bubbleY + bubbleH + 4)
      ..lineTo(size.x / 2 + 3, bubbleY + bubbleH)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);

    textPainter.paint(canvas, Offset(bubbleX + 6, bubbleY + 3));
  }
}
