import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../core/hero_skin_style.dart';
import '../../core/stat_growth_formula.dart';
import '../../registry/sprite_image_cache.dart';
import '../../services/audio_service.dart';
import 'dungeon_map.dart';

class PlayerComponent extends PositionComponent with CollisionCallbacks {
  // Chỉ số nhân vật (giữ chuẩn baseline cho toàn bộ unit test)
  double maxHp = GameConstants.playerMaxHp;
  double currentHp = GameConstants.playerMaxHp;
  double maxKi = GameConstants.playerMaxKi;
  double currentKi = GameConstants.playerMaxKi;
  double damage = GameConstants.playerBaseDamage;
  double speed = GameConstants.playerBaseSpeed;

  int level = 1;
  int currentExp = 0;
  int expToNextLevel = 100;

  int coinsCollected = 0;

  // Trạng thái hành động & 60 FPS Procedural Animation
  Vector2 moveDirection = Vector2.zero();
  bool isFacingRight = true;
  int facingRow = 0; // 0: Down, 1: Down-Right, 2: Right, 3: Up-Right, 4: Up
  bool isAttacking = false;
  double attackTimer = 0.0;
  double attackAngle = 0.0;
  double animTime = 0.0;

  // Combo 3 đòn đánh thường (Đòn 1: Chém ngang -> Đòn 2: Chém chéo -> Đòn 3: Xoay 360 + Sóng kiếm)
  int comboStep = 0;
  double comboResetTimer = 0.0;
  double swordWaveTimer = 0.0;
  double swordWaveDist = 0.0;

  // Hiệu ứng Hit / Hurt flash trắng (0.08s)
  double hitFlashTimer = 0.0;

  // Lưu 3 vị trí gần nhất để vẽ Afterimage Trail khi chạy / lướt
  final List<Vector2> afterimagePositions = [];
  double _afterimageSampleTimer = 0.0;

  // Hiệu ứng Kỹ năng Visual (Thunder Flash, Storm Blade Vortex, Heaven's Judgment)
  double skill1TrailTimer = 0.0;
  Vector2? skill1StartOffset;
  double skill2VortexTimer = 0.0;
  double skill3JudgmentTimer = 0.0;

  // Bộ đếm Cooldown hiển thị quạt tròn trên HUD (drawArc)
  double skill1VisualCd = 0.0;
  double skill2VisualCd = 0.0;
  double skill3VisualCd = 0.0;
  static const double maxSkill1VisualCd = 5.0;
  static const double maxSkill2VisualCd = 8.0;
  static const double maxSkill3VisualCd = 12.0;
  static const double skill1MaxCd = maxSkill1VisualCd;
  static const double skill2MaxCd = maxSkill2VisualCd;
  static const double skill3MaxCd = maxSkill3VisualCd;

  // Báo hiệu bấm nút khi không đủ Ki (nháy viền đỏ trên HUD)
  double insufficientKiFlashTimer = 0.0;

  // Skill Buffs
  bool isBerserk = false;
  double berserkTimer = 0.0;

  // Khiên hấp thụ sát thương (từ Shield Drone, Aegis-X9 Golden Overdrive hoặc Buffs)
  double _baseDamageAbsorption = 0.0;
  double temporaryPetDamageAbsorption = 0.0;
  double get damageAbsorption => max(_baseDamageAbsorption,
      goldenShieldTimer > 0 ? temporaryPetDamageAbsorption : 0.0);
  set damageAbsorption(double value) => _baseDamageAbsorption = value;
  double goldenShieldTimer = 0.0;
  double get shieldHp => goldenShieldTimer > 0
      ? 50.0
      : (damageAbsorption > 0 ? (damageAbsorption * 100.0) : 0.0);

  // Lưu vị trí trước đó để chặn xuyên tường
  Vector2 previousPosition = Vector2.zero();

  // Speech bubble trên đầu Player
  String? speechBubbleText;
  double speechBubbleTimer = 0.0;

  // Callback báo HUD cập nhật
  Function()? onStatsChanged;

  final String heroId;
  final String? skinId;
  int userHeroLevel;

  PlayerComponent({
    required Vector2 position,
    this.heroId = 'george',
    this.skinId,
    this.userHeroLevel = 1,
  }) : super(
          position: position,
          size: Vector2(36, 40),
          anchor: Anchor.center,
        ) {
    if (userHeroLevel > 1) {
      applyUserHeroLevel(userHeroLevel);
    }
    // Hitbox va chạm với quái và tường
    add(RectangleHitbox(
      size: Vector2(24, 28),
      position: Vector2(6, 10),
    ));
  }

  /// Áp dụng chỉ số cộng thêm từ cấp độ Nhân Vật của User (Level 1 -> 100)
  void applyUserHeroLevel(int targetHeroLevel) {
    userHeroLevel = targetHeroLevel.clamp(
      StatGrowthFormula.minHeroLevel,
      StatGrowthFormula.maxHeroLevel,
    );
    if (userHeroLevel <= 1) return;
    final scaled = StatGrowthFormula.computeStatsForLevel(
      heroId: heroId,
      level: userHeroLevel,
    );
    maxHp = GameConstants.playerMaxHp + scaled.bonusHp;
    currentHp = maxHp;
    maxKi = GameConstants.playerMaxKi + scaled.bonusKi;
    currentKi = maxKi;
    damage = GameConstants.playerBaseDamage + scaled.bonusAttack;
  }

  @override
  void update(double dt) {
    super.update(dt);
    animTime += dt;

    // Hồi phục Ki theo thời gian
    if (currentKi < maxKi) {
      currentKi = min(maxKi, currentKi + 5 * dt);
      onStatsChanged?.call();
    }

    // Giảm các timer hiệu ứng visual & HUD cooldown
    if (hitFlashTimer > 0) hitFlashTimer = max(0.0, hitFlashTimer - dt);
    if (comboResetTimer > 0) {
      comboResetTimer -= dt;
      if (comboResetTimer <= 0) comboStep = 0;
    }
    if (swordWaveTimer > 0) {
      swordWaveTimer = max(0.0, swordWaveTimer - dt);
      swordWaveDist += 280.0 * dt;
    }
    if (skill1TrailTimer > 0) skill1TrailTimer = max(0.0, skill1TrailTimer - dt);
    if (skill2VortexTimer > 0) skill2VortexTimer = max(0.0, skill2VortexTimer - dt);
    if (skill3JudgmentTimer > 0) skill3JudgmentTimer = max(0.0, skill3JudgmentTimer - dt);
    if (insufficientKiFlashTimer > 0) {
      insufficientKiFlashTimer = max(0.0, insufficientKiFlashTimer - dt);
    }

    if (skill1VisualCd > 0) skill1VisualCd = max(0.0, skill1VisualCd - dt);
    if (skill2VisualCd > 0) skill2VisualCd = max(0.0, skill2VisualCd - dt);
    if (skill3VisualCd > 0) skill3VisualCd = max(0.0, skill3VisualCd - dt);

    if (goldenShieldTimer > 0) {
      goldenShieldTimer -= dt;
      if (goldenShieldTimer <= 0) {
        goldenShieldTimer = 0.0;
        temporaryPetDamageAbsorption = 0.0;
      }
    }

    // Xử lý speech bubble timer
    if (speechBubbleTimer > 0) {
      speechBubbleTimer -= dt;
      if (speechBubbleTimer <= 0) {
        speechBubbleText = null;
      }
    }

    // Xử lý Buff Cuồng Nộ
    if (isBerserk) {
      berserkTimer -= dt;
      if (berserkTimer <= 0) {
        isBerserk = false;
        speed = GameConstants.playerBaseSpeed;
        damage = GameConstants.playerBaseDamage;
        onStatsChanged?.call();
      }
    }

    // Xử lý hoạt ảnh vung vũ khí đánh thường
    if (isAttacking) {
      attackTimer += dt;
      attackAngle += 20 * dt;
      if (attackTimer >= 0.25) {
        isAttacking = false;
        attackTimer = 0.0;
      }
    }

    // Di chuyển & lấy mẫu Afterimage Trail
    if (!moveDirection.isZero()) {
      previousPosition = position.clone();
      final effectiveSpeed = isBerserk ? speed * 1.5 : speed;
      position.add(moveDirection * effectiveSpeed * dt);

      final mx = moveDirection.x;
      final my = moveDirection.y;
      final absX = mx.abs();
      final absY = my.abs();

      if (absX > 0.05) isFacingRight = mx > 0;

      if (my > 0.08) {
        if (absX < 0.414 * absY) {
          facingRow = 0; // Down (Nam / Trước mặt)
        } else if (absY < 0.414 * absX) {
          facingRow = 2; // Side (Ngang)
        } else {
          facingRow = 1; // Down-Diagonal (Chéo trước)
        }
      } else if (my < -0.08) {
        if (absX < 0.414 * absY) {
          facingRow = 4; // Up (Bắc / Sau lưng)
        } else if (absY < 0.414 * absX) {
          facingRow = 2; // Side (Ngang)
        } else {
          facingRow = 3; // Up-Diagonal (Chéo sau)
        }
      } else if (absX > 0.08) {
        facingRow = 2; // Side (Ngang)
      }

      _afterimageSampleTimer += dt;
      if (_afterimageSampleTimer >= 0.04) {
        _afterimageSampleTimer = 0.0;
        afterimagePositions.insert(0, previousPosition.clone());
        if (afterimagePositions.length > 3) {
          afterimagePositions.removeLast();
        }
      }
    } else if (afterimagePositions.isNotEmpty) {
      _afterimageSampleTimer += dt;
      if (_afterimageSampleTimer >= 0.05) {
        _afterimageSampleTimer = 0.0;
        afterimagePositions.removeLast();
      }
    }
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);
    if (other is WallBlock) {
      // Khi đâm vào tường, đẩy lùi về vị trí an toàn trước đó
      position = previousPosition.clone();
    }
  }

  // --- ACTIONS & SKILLS ---

  void performBasicAttack() {
    if (isAttacking) return;
    isAttacking = true;
    attackTimer = 0.0;
    comboStep = (comboStep % 3) + 1;
    comboResetTimer = 1.2;

    if (comboStep == 3) {
      swordWaveTimer = 0.28;
      swordWaveDist = 14.0;
    }

    attackAngle = isFacingRight ? -0.8 : 0.8;
    AudioService.instance.playSfx(SfxSound.attackHammer);
  }

  bool useSkill1() {
    // Búa Cuồng Phong / Lôi Ảnh Trảm - Tốn 25 Ki
    const kiCost = 25.0;
    if (currentKi < kiCost) {
      insufficientKiFlashTimer = 0.45;
      onStatsChanged?.call();
      return false;
    }
    currentKi -= kiCost;
    isAttacking = true;
    attackTimer = -0.3; // Kéo dài đòn xoay
    skill1TrailTimer = 0.35;
    skill1StartOffset = Vector2(isFacingRight ? -55 : 55, 0);
    skill1VisualCd = maxSkill1VisualCd;
    onStatsChanged?.call();
    AudioService.instance.playSfx(SfxSound.skillHurricane);
    return true;
  }

  bool useSkill2() {
    // Nện Đất / Lôi Điện Hộ Thể - Tốn 35 Ki
    const kiCost = 35.0;
    if (currentKi < kiCost) {
      insufficientKiFlashTimer = 0.45;
      onStatsChanged?.call();
      return false;
    }
    currentKi -= kiCost;
    skill2VortexTimer = 4.0;
    skill2VisualCd = maxSkill2VisualCd;
    onStatsChanged?.call();
    AudioService.instance.playSfx(SfxSound.skillSmash);
    return true;
  }

  bool useSkill3() {
    // Cơn Cuồng Nộ / Thiên Phạt Lôi Ngục - Tốn 40 Ki
    const kiCost = 40.0;
    if (currentKi < kiCost || isBerserk) {
      if (currentKi < kiCost) {
        insufficientKiFlashTimer = 0.45;
        onStatsChanged?.call();
      }
      return false;
    }
    currentKi -= kiCost;
    isBerserk = true;
    berserkTimer = 8.0; // 8 giây cuồng nộ
    skill3JudgmentTimer = 3.0;
    skill3VisualCd = maxSkill3VisualCd;
    onStatsChanged?.call();
    AudioService.instance.playSfx(SfxSound.skillBerserk);
    return true;
  }

  void gainExp(int exp) {
    currentExp += exp;
    while (currentExp >= expToNextLevel && level < 15) {
      currentExp -= expToNextLevel;
      level++;
      expToNextLevel = (expToNextLevel * 1.3).toInt();

      // Cộng chỉ số khi lên level (theo mục 2.2 của tài liệu)
      maxHp += 15;
      currentHp = maxHp; // Hồi đầy máu khi lên cấp
      maxKi += 10;
      currentKi = maxKi;
      damage += 5;
    }
    onStatsChanged?.call();
  }

  void heal(double amount) {
    currentHp = min(maxHp, currentHp + amount);
    onStatsChanged?.call();
  }

  void say(String text) {
    speechBubbleText = text;
    speechBubbleTimer = 3.0;
  }

  void takeDamage(double dmg) {
    final barrierFactor = (1.0 - damageAbsorption.clamp(0.0, 0.9));
    final effectiveDmg = isBerserk
        ? (dmg * barrierFactor * 0.6)
        : (dmg * barrierFactor); // Giảm sát thương khi cuồng nộ và khiên
    currentHp = max(0, currentHp - effectiveDmg);
    hitFlashTimer = 0.08;
    onStatsChanged?.call();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final skin = HeroSkinStyle.resolve(heroId, skinId);
    if (skin != null) canvas.saveLayer(null, Paint()..colorFilter = skin.filter);
    try {
      _renderAppearance(canvas);
    } finally {
      if (skin != null) canvas.restore();
    }
  }

  void _renderAppearance(Canvas canvas) {

    final center = Offset(size.x / 2, size.y / 2);

    // 0. Vẽ hiệu ứng Kỹ năng trên mặt đất (Skill 2 Vortex / Skill 3 Heaven's Judgment / Skill 1 Lightning Trail)
    _renderSkillEffectsUnderneath(canvas, center);

    // 0.5 Vẽ bóng mờ Afterimage Trail khi di chuyển (0.4 -> 0.2 -> 0.05)
    if (!moveDirection.isZero() && afterimagePositions.isNotEmpty) {
      const opacities = [0.35, 0.18, 0.07];
      for (int i = 0; i < afterimagePositions.length; i++) {
        final trailPos = afterimagePositions[i] - position;
        final alpha = i < opacities.length ? opacities[i] : 0.05;
        final ghostPaint = Paint()
          ..color = (heroId == 'kaelen'
                  ? const Color(0xFF00F0FF)
                  : const Color(0xFFFFD700))
              .withValues(alpha: alpha);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(center.dx + trailPos.x, center.dy + trailPos.y),
              width: 20,
              height: 28,
            ),
            const Radius.circular(6),
          ),
          ghostPaint,
        );
      }
    }

    final bool isNova = heroId == 'nova_blade' || heroId == 'nova';
    final bool isShadow = heroId == 'shadow_01' || heroId == 'shadow';
    final bool isKale = heroId == 'kaelen' || heroId == 'kale';
    final bool isEmber = heroId == 'ember_02' || heroId == 'ember';
    final bool isCustomAnimated = isNova || isShadow || isKale || isEmber;

    // Hiệu ứng nghiêng thân khi chạy, nhún bước chân và lao người khi tấn công
    final isMoving = !moveDirection.isZero();
    final bool novaMultiDirRun = isNova && isMoving && !isAttacking;
    final bool emberMultiDirRun = isEmber && isMoving && !isAttacking;

    canvas.save();
    if (!isFacingRight && !novaMultiDirRun && !emberMultiDirRun) {
      canvas.scale(-1, 1);
      canvas.translate(-size.x, 0);
    }
    final runBounce = isMoving
        ? (sin(animTime * 15.0).abs() * -2.2)
        : (sin(animTime * 3.2) * 1.4);
    final breathOffset = isCustomAnimated ? 0.0 : runBounce;
    final legSwing = isMoving ? sin(animTime * 15.0) * 4.8 : 0.0;
    final attackLunge = isAttacking ? 3.5 : 0.0;

    if (!isCustomAnimated && (isMoving || isAttacking)) {
      canvas.translate(size.x / 2 + attackLunge, size.y / 2);
      canvas.rotate(isAttacking ? 0.18 : 0.13);
      canvas.translate(-size.x / 2, -size.y / 2);
    }

    // Hiệu ứng hào quang Cuồng Nộ / Ultimate Aura theo hệ nhân vật
    if (isBerserk) {
      final auraColor = _heroPrimaryColor.withValues(alpha: 0.42);
      final auraPaint = Paint()
        ..color = auraColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 26, auraPaint);
    }

    // Khiên Hoàng Kim từ Aegis-X9
    if (goldenShieldTimer > 0) {
      final shieldPaint = Paint()
        ..color = const Color(0x55FFD700)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.x / 2, size.y / 2), 24, shieldPaint);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        24,
        Paint()
          ..color = const Color(0xFFFFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }

    // 1. Bóng đổ dưới chân co giãn theo nhịp nhún
    final shadowPaint = Paint()..color = const Color(0x55000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x / 2, size.y - 2),
        width: isMoving ? 26 : 24,
        height: 8,
      ),
      shadowPaint,
    );

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
      } else {
        _renderClassicHero(canvas, breathOffset, legSwing);
      }
    } else if (isKale) {
      if (isAttacking) {
        final atkSheet =
            SpriteImageCache.instance.getHeroAttackImage('kaelen');
        if (atkSheet != null && atkSheet.width >= 2000) {
          final row = facingRow.clamp(0, 4);
          final progress =
              (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(0.0, 0.999);
          final col = (progress * 5).floor().clamp(0, 4);
          const cellW = 512.0;
          const cellH = 512.0;
          const dstW = 96.0;
          const dstH = 96.0;
          final dstLeft = (size.x - dstW) / 2;
          final dstTop = size.y - 2 - (478.0 / 512.0 * dstH);
          final srcRect =
              Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);
          final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          canvas.drawImageRect(
            atkSheet,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        } else {
          _renderClassicHero(canvas, breathOffset, legSwing);
        }
      } else if (isMoving) {
        final frameIndex = (animTime * 14.0).floor() % 16;
        final runImg = SpriteImageCache.instance
            .getHeroSequenceFrame('kaelen', 'run', frameIndex);
        if (runImg != null) {
          const dstW = 52.0;
          const dstH = 52.0;
          final dstLeft = (size.x - dstW) / 2;
          final dstTop = size.y - 2 - dstH;
          final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          final srcRect = Rect.fromLTWH(
            0,
            0,
            runImg.width.toDouble(),
            runImg.height.toDouble(),
          );
          canvas.drawImageRect(
            runImg,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        } else {
          _renderClassicHero(canvas, breathOffset, legSwing);
        }
      } else {
        // Kale đứng yên: Chạy đầy đủ chu kỳ 16 frames IDLE
        final frameIndex = (animTime * 11.0).floor() % 16;
        final idleImg = SpriteImageCache.instance
            .getHeroSequenceFrame('kaelen', 'idle', frameIndex);
        if (idleImg != null) {
          const dstW = 52.0;
          const dstH = 52.0;
          final dstLeft = (size.x - dstW) / 2;
          final dstTop = size.y - 2 - dstH;
          final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);
          final srcRect = Rect.fromLTWH(
            0,
            0,
            idleImg.width.toDouble(),
            idleImg.height.toDouble(),
          );
          canvas.drawImageRect(
            idleImg,
            srcRect,
            dstRect,
            Paint()..filterQuality = FilterQuality.none,
          );
        } else {
          _renderClassicHero(canvas, breathOffset, legSwing);
        }
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
          final mx = moveDirection.x;
          final my = moveDirection.y;
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
            runRow = mx > 0 ? 5 : 4; // 5: Diagonal Right, 4: Diagonal Left
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
      } else {
        _renderClassicHero(canvas, breathOffset, legSwing);
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
          final mx = moveDirection.x;
          final my = moveDirection.y;
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
      } else {
        _renderClassicHero(canvas, breathOffset, legSwing);
      }
    } else {
      final heroSprite = isAttacking
          ? (SpriteImageCache.instance.getHeroAttackImage(heroId) ??
              SpriteImageCache.instance.getHeroImage(heroId))
          : SpriteImageCache.instance.getHeroImage(heroId);
      if (heroSprite != null) {
        canvas.save();
        final pivotX = size.x / 2;
        final pivotY = size.y - 2;
        final strideTilt = isMoving ? sin(animTime * 16.0) * 0.12 : 0.0;
        final scaleX = isMoving
            ? (1.0 + sin(animTime * 16.0).abs() * 0.05)
            : (1.0 - sin(animTime * 3.2) * 0.02);
        final scaleY = isMoving
            ? (1.0 - sin(animTime * 16.0).abs() * 0.05)
            : (1.0 + sin(animTime * 3.2) * 0.025);

        canvas.translate(pivotX, pivotY);
        canvas.rotate(isAttacking ? 0.16 : strideTilt);
        canvas.scale(scaleX, scaleY);
        canvas.translate(-pivotX, -pivotY);

        final srcRect = Rect.fromLTWH(
          0,
          0,
          heroSprite.width.toDouble(),
          heroSprite.height.toDouble(),
        );
        final dstRect = Rect.fromCenter(
          center: Offset(size.x / 2, size.y / 2 - 3 + breathOffset),
          width: 46,
          height: 50,
        );
        canvas.drawImageRect(
          heroSprite,
          srcRect,
          dstRect,
          Paint()..filterQuality = FilterQuality.none,
        );
        canvas.restore();
      } else {
        _renderClassicHero(canvas, breathOffset, legSwing);
      }
    }

    // Vệt chém lưỡi liềm & Sóng kiếm đồng bộ theo đòn đánh của từng nhân vật (Combo 1-2-3)
    if (isAttacking) {
      final slashColor = _heroPrimaryColor;
      final secondarySlash = _heroSecondaryColor;
      final sweepStart = comboStep == 2 ? -pi / 1.4 : -pi / 2.2;
      final sweepAngle = comboStep == 3 ? pi * 1.45 : pi * 0.95;

      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.x / 2 + 10, size.y / 2),
          width: 46,
          height: 40,
        ),
        sweepStart,
        sweepAngle,
        false,
        Paint()
          ..color = slashColor.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = comboStep == 3 ? 5.0 : 3.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.x / 2 + 10, size.y / 2),
          width: 38,
          height: 32,
        ),
        sweepStart + 0.1,
        sweepAngle * 0.8,
        false,
        Paint()
          ..color = secondarySlash.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }

    if (swordWaveTimer > 0) {
      final wavePaint = Paint()
        ..color = _heroPrimaryColor.withValues(
          alpha: (swordWaveTimer / 0.28).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.8;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.x / 2 + swordWaveDist, size.y / 2),
          width: 26,
          height: 38,
        ),
        -pi / 2.5,
        pi * 0.85,
        false,
        wavePaint,
      );
    }

    // Nháy trắng khi trúng đòn (Hit Flash 0.08s)
    if (hitFlashTimer > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(6, 4, 24, 34),
          const Radius.circular(6),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }

    canvas.restore();

    // --- BONG BÓNG QUICK CHAT (SPEECH BUBBLE) ---
    if (speechBubbleText != null) {
      _renderSpeechBubble(canvas, speechBubbleText!);
    }
  }

  /// Vẽ Kaelen & Nova Blade với đầy đủ Cổ, Khuôn mặt sáng rõ, Vai, 2 Tay cầm Song Đao, Thắt lưng, Đùi & Giày
  void _renderKaelenThunderblade(Canvas canvas, double breathOffset, double legSwing) {
    final isNova = heroId == 'nova_blade';
    final isMoving = !moveDirection.isZero();
    final leftLift = isMoving ? max(0.0, sin(animTime * 15.0)) * 2.5 : 0.0;
    final rightLift = isMoving ? max(0.0, -sin(animTime * 15.0)) * 2.5 : 0.0;
    final armSwing = isMoving ? sin(animTime * 15.0) * 0.30 : sin(animTime * 3.0) * 0.08;

    // 1. CapeLayer (Áo choàng bay phía sau)
    final capeWave = sin(animTime * 4.0 - 0.5) * 2.8 + (isMoving ? -5.5 : 0.0);
    final capePath = Path()
      ..moveTo(9, 14 + breathOffset)
      ..lineTo(25, 14 + breathOffset)
      ..quadraticBezierTo(9 + capeWave, 27, 2 + capeWave, 37)
      ..lineTo(19 + capeWave * 0.5, 36)
      ..close();
    final capeShader = LinearGradient(
      colors: isNova
          ? const [Color(0xFF7E22CE), Color(0xFF3B0764)]
          : const [Color(0xFFFFD700), Color(0xFFFF8C00)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(const Rect.fromLTWH(0, 12, 30, 26));
    canvas.drawPath(capePath, Paint()..shader = capeShader);

    // 2. Đùi & Giày giáp nối liền hông (FootLeft & FootRight có viền sáng rõ)
    final legPaint = Paint()..color = const Color(0xFF334155);
    final trimColor = isNova ? const Color(0xFF00E5FF) : const Color(0xFFFFD700);
    final lLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(9 + legSwing * 0.7, 26 - leftLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    final rLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(19.5 - legSwing * 0.7, 26 - rightLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(lLeg, legPaint);
    canvas.drawRRect(rLeg, legPaint);
    canvas.drawRect(
      Rect.fromLTWH(9 + legSwing * 0.7, 31 - leftLift, 7.5, 2.5),
      Paint()..color = trimColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(19.5 - legSwing * 0.7, 31 - rightLift, 7.5, 2.5),
      Paint()..color = trimColor,
    );

    // 3. Tay trái (LeftArm + Hand + Đao trái) nối từ vai trái
    canvas.save();
    canvas.translate(9, 17 + breathOffset);
    canvas.rotate(isAttacking && comboStep == 2 ? attackAngle : -armSwing);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, 0, 5.5, 10),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF475569),
    );
    canvas.drawCircle(
      const Offset(0, 10),
      3.0,
      Paint()..color = const Color(0xFFFDE68A),
    );
    canvas.drawLine(
      const Offset(0, 10),
      const Offset(-11, -10),
      Paint()
        ..color = isNova ? const Color(0xFFE040FB) : const Color(0xFFFFD700)
        ..strokeWidth = 3.0,
    );
    canvas.restore();

    // 4. BodyLayer (Thân giáp + Thắt lưng + Lõi năng lượng ngực)
    final bodyRect = Rect.fromLTWH(8, 14 + breathOffset, 20, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)),
      Paint()..color = isNova ? const Color(0xFF3730A3) : const Color(0xFF1E3A8A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(4)),
      Paint()
        ..color = trimColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Thắt lưng nối liền thân và đùi
    canvas.drawRect(
      Rect.fromLTWH(8, 25 + breathOffset, 20, 3.5),
      Paint()..color = trimColor,
    );
    // Lõi tinh thể trước ngực
    canvas.drawCircle(
      Offset(18, 20 + breathOffset),
      3.2,
      Paint()..color = const Color(0xFF00F0FF),
    );

    // 5. Cổ, Khuôn mặt da người sáng rõ & Tóc trắng bạc dựng ngược
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
    final hairPath = Path()
      ..moveTo(7, 7 + breathOffset)
      ..lineTo(5, 0 + breathOffset)
      ..lineTo(13, 3 + breathOffset)
      ..lineTo(18, -3 + breathOffset)
      ..lineTo(22, 3 + breathOffset)
      ..lineTo(29, 0 + breathOffset)
      ..lineTo(27, 7 + breathOffset)
      ..close();
    canvas.drawPath(hairPath, Paint()..color = const Color(0xFFF8FAFC));
    canvas.drawRect(
      Rect.fromLTWH(9, 5 + breathOffset, 18, 2.2),
      Paint()..color = trimColor,
    );
    // Đôi mắt xanh điện quang
    canvas.drawRect(
      Rect.fromLTWH(19, 8.5 + breathOffset, 5, 2.5),
      Paint()..color = const Color(0xFF0284C7),
    );

    // 6. Tay phải (RightArm + Hand + Đao phải) nối từ vai phải
    canvas.save();
    canvas.translate(27, 18 + breathOffset);
    if (isAttacking) {
      final comboRot = comboStep == 2 ? -attackAngle * 1.1 : attackAngle * 1.25;
      canvas.rotate(comboRot);
    } else {
      canvas.rotate(armSwing);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3, -2, 6, 10),
        const Radius.circular(2),
      ),
      Paint()..color = trimColor,
    );
    canvas.drawCircle(
      const Offset(0, 7),
      3.2,
      Paint()..color = const Color(0xFFFDE68A),
    );

    final hiltPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 3.2;
    final bladeGlow = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 3.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final bladeCore = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6;

    canvas.drawLine(const Offset(0, 8), const Offset(0, 2), hiltPaint);
    canvas.drawLine(const Offset(0, 2), const Offset(11, -22), bladeGlow);
    canvas.drawLine(const Offset(0, 2), const Offset(11, -22), bladeCore);
    canvas.restore();
  }

  Color get _heroPrimaryColor {
    switch (heroId) {
      case 'kaelen':
        return const Color(0xFF00F0FF);
      case 'nova_blade':
        return const Color(0xFF18FFFF);
      case 'shadow_01':
      case 'ninja':
        return const Color(0xFFE040FB);
      case 'ember_02':
      case 'ember':
        return const Color(0xFFFF6D00);
      case 'valeria':
        return const Color(0xFF38BDF8);
      case 'garrick':
        return const Color(0xFFFFB300);
      case 'ranger':
        return const Color(0xFF00E676);
      case 'tanker':
        return const Color(0xFF00B0FF);
      case 'george':
      default:
        return const Color(0xFFFFD700);
    }
  }

  Color get _heroSecondaryColor {
    switch (heroId) {
      case 'kaelen':
        return const Color(0xFFFFD700);
      case 'nova_blade':
        return const Color(0xFFE040FB);
      case 'shadow_01':
      case 'ninja':
        return const Color(0xFF00E5FF);
      case 'ember_02':
      case 'ember':
        return const Color(0xFFFFEA00);
      case 'valeria':
        return const Color(0xFFFF5252);
      case 'garrick':
        return const Color(0xFFD97706);
      default:
        return Colors.white;
    }
  }

  /// Vẽ các tướng cổ điển và mở rộng với chuyển động khớp nối Chân, Tay, Áo choàng & Vũ khí đồng bộ
  void _renderClassicHero(Canvas canvas, double breathOffset, double legSwing) {
    final isMoving = !moveDirection.isZero();
    final leftLift = isMoving ? max(0.0, sin(animTime * 15.0)) * 2.5 : 0.0;
    final rightLift = isMoving ? max(0.0, -sin(animTime * 15.0)) * 2.5 : 0.0;
    final armSwing = isMoving ? sin(animTime * 15.0) * 0.32 : sin(animTime * 3.0) * 0.06;

    Color bootsColor;
    Color armorColor;
    Color borderGold;
    Color helmetColor;
    Color crestColor;
    Color eyeColor;
    Color capeColor;

    switch (heroId) {
      case 'ranger':
        bootsColor = const Color(0xFF3E2723);
        armorColor = const Color(0xFF2E7D32);
        borderGold = const Color(0xFF00E676);
        helmetColor = const Color(0xFF1B5E20);
        crestColor = const Color(0xFFFFD54F);
        eyeColor = const Color(0xFFFFD600);
        capeColor = const Color(0xFF1B5E20);
        break;
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
      case 'shadow_01':
        bootsColor = const Color(0xFF212121);
        armorColor = const Color(0xFF311B92);
        borderGold = const Color(0xFFE040FB);
        helmetColor = const Color(0xFF1A237E);
        crestColor = const Color(0xFF7B1FA2);
        eyeColor = const Color(0xFFE040FB);
        capeColor = const Color(0xFF4A148C);
        break;
      case 'ember_02':
      case 'ember':
        bootsColor = const Color(0xFF3E2723);
        armorColor = const Color(0xFF4A148C);
        borderGold = const Color(0xFFFF6D00);
        helmetColor = const Color(0xFF212121);
        crestColor = const Color(0xFFFFAB00);
        eyeColor = const Color(0xFFFF6D00);
        capeColor = const Color(0xFFB71C1C);
        break;
      case 'valeria':
        bootsColor = const Color(0xFF1A237E);
        armorColor = const Color(0xFF0288D1);
        borderGold = const Color(0xFFFF5252);
        helmetColor = const Color(0xFF80DEEA);
        crestColor = const Color(0xFF00E5FF);
        eyeColor = const Color(0xFF18FFFF);
        capeColor = const Color(0xFF0284C7);
        break;
      case 'garrick':
        bootsColor = const Color(0xFF3E2723);
        armorColor = const Color(0xFF5D4037);
        borderGold = const Color(0xFFFFB300);
        helmetColor = const Color(0xFFB71C1C);
        crestColor = const Color(0xFFFFD700);
        eyeColor = const Color(0xFFFFAB00);
        capeColor = const Color(0xFF991B1B);
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

    // 1. Áo choàng / Khăn bay phía sau theo chuyển động
    final capeWave = sin(animTime * 4.5) * 2.5 + (isMoving ? -5.0 : 0.0);
    final capePath = Path()
      ..moveTo(9, 15 + breathOffset)
      ..lineTo(22, 15 + breathOffset)
      ..quadraticBezierTo(9 + capeWave, 26, 3 + capeWave, 35)
      ..lineTo(16 + capeWave * 0.5, 34)
      ..close();
    canvas.drawPath(capePath, Paint()..color = capeColor.withValues(alpha: 0.85));

    // 2. Đùi & Giày nối liền hông có viền sáng
    final bootsPaint = Paint()..color = bootsColor;
    final lBoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(8 + legSwing * 0.7, 26 - leftLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    final rBoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(20.5 - legSwing * 0.7, 26 - rightLift, 7.5, 12),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(lBoot, bootsPaint);
    canvas.drawRRect(rBoot, bootsPaint);
    canvas.drawRect(
      Rect.fromLTWH(8 + legSwing * 0.7, 31 - leftLift, 7.5, 2.2),
      Paint()..color = borderGold,
    );
    canvas.drawRect(
      Rect.fromLTWH(20.5 - legSwing * 0.7, 31 - rightLift, 7.5, 2.2),
      Paint()..color = borderGold,
    );

    // 3. Tay sau (LeftArm + Bàn tay) đánh theo nhịp bước chạy
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

    // 4. Thân / Áo giáp + Đai lưng nối liền đùi
    final armorPaint = Paint()..color = armorColor;
    final torsoRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 14 + breathOffset, 20, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(torsoRRect, armorPaint);
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

    // 5. Cổ, Khuôn mặt da người sáng rõ & Mũ/Tóc đặc trưng
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
    // Mũ / Mái tóc phía trên trán
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 1 + breathOffset, 20, 6),
        const Radius.circular(3),
      ),
      Paint()..color = helmetColor,
    );
    if (heroId == 'ember_02' || heroId == 'ember') {
      final hatPath = Path()
        ..moveTo(4, 6 + breathOffset)
        ..lineTo(32, 6 + breathOffset)
        ..lineTo(19, -7 + breathOffset)
        ..close();
      canvas.drawPath(hatPath, Paint()..color = const Color(0xFF31102F));
    } else {
      final crestPaint = Paint()..color = crestColor;
      canvas.drawRect(Rect.fromLTWH(15, -2 + breathOffset, 6, 5), crestPaint);
    }
    if (heroId == 'garrick') {
      final beard = Path()
        ..moveTo(12, 11 + breathOffset)
        ..lineTo(25, 11 + breathOffset)
        ..lineTo(19, 20 + breathOffset)
        ..close();
      canvas.drawPath(beard, Paint()..color = const Color(0xFFDC2626));
    }

    // Đôi mắt rõ nét trên khuôn mặt
    canvas.drawRect(
      Rect.fromLTWH(19, 8 + breathOffset, 5, 2.5),
      Paint()..color = eyeColor,
    );

    // 6. Tay trước (RightArm + Bàn tay) + Vũ khí đặc trưng xoay đồng bộ khi chạy & tấn công
    canvas.save();
    canvas.translate(size.x - 4, 19 + breathOffset);
    if (isAttacking) {
      final swingRot = comboStep == 2 ? -attackAngle * 1.15 : attackAngle * 1.25;
      canvas.rotate(swingRot);
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

    if (heroId == 'ranger') {
      final bowPaint = Paint()
        ..color = const Color(0xFF6D4C41)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      const arcRect = Rect.fromLTWH(-10, -22, 14, 28);
      canvas.drawArc(arcRect, -pi / 2, pi, false, bowPaint);
      final stringPaint = Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.5;
      canvas.drawLine(const Offset(-3, -22), const Offset(-3, 6), stringPaint);
      final arrowPaint = Paint()..color = const Color(0xFFFFEB3B)..strokeWidth = 2;
      canvas.drawLine(const Offset(-10, -8), const Offset(12, -8), arrowPaint);
    } else if (heroId == 'tanker') {
      final shieldPaint = Paint()..color = const Color(0xFF0D47A1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -22, 18, 22), const Radius.circular(5)),
        shieldPaint,
      );
      final crossPaint = Paint()..color = const Color(0xFFFFD54F)..strokeWidth = 2;
      canvas.drawLine(const Offset(-1, -20), const Offset(-1, -2), crossPaint);
      canvas.drawLine(const Offset(-8, -11), const Offset(6, -11), crossPaint);
    } else if (heroId == 'ninja' || heroId == 'shadow_01') {
      final bladePaint = Paint()
        ..color = heroId == 'shadow_01' ? const Color(0xFFE040FB) : const Color(0xFFE0E0E0)
        ..strokeWidth = 2.8;
      final hiltPaint = Paint()..color = const Color(0xFFD50000)..strokeWidth = 3.5;
      canvas.drawLine(const Offset(-2, 6), const Offset(-2, 0), hiltPaint);
      canvas.drawLine(const Offset(-2, 0), const Offset(7, -24), bladePaint);
      canvas.drawLine(const Offset(-7, 5), const Offset(-14, -18), bladePaint);
    } else if (heroId == 'valeria') {
      // Trượng Băng Tinh & 2 cầu Băng-Hỏa xoay quanh của Valeria
      canvas.drawLine(
        const Offset(0, 8),
        const Offset(0, -22),
        Paint()..color = const Color(0xFF90CAF9)..strokeWidth = 2.8,
      );
      canvas.drawCircle(
        const Offset(0, -24),
        5.5,
        Paint()..color = const Color(0xFF00E5FF),
      );
      canvas.drawCircle(
        Offset(-12 + cos(animTime * 5) * 4, -8 + sin(animTime * 5) * 4),
        3.8,
        Paint()..color = const Color(0xFFFF5252),
      );
    } else if (heroId == 'ember_02' || heroId == 'ember') {
      // Trượng Hỏa Ngọc & Cầu Lửa của Phù Thủy Ember-02
      canvas.drawLine(
        const Offset(0, 8),
        const Offset(0, -20),
        Paint()..color = const Color(0xFF78350F)..strokeWidth = 2.8,
      );
      canvas.drawCircle(
        Offset(2, -24 + sin(animTime * 6) * 2),
        6.0,
        Paint()..color = const Color(0xFFFF6D00),
      );
      canvas.drawCircle(
        Offset(2, -24 + sin(animTime * 6) * 2),
        3.0,
        Paint()..color = const Color(0xFFFFEA00),
      );
    } else if (heroId == 'garrick') {
      // Đại Đao Đá Cổ Đại khổng lồ của Garrick
      canvas.drawRect(
        const Rect.fromLTWH(-2, 0, 4, 8),
        Paint()..color = const Color(0xFFFFB300),
      );
      final greatBlade = Path()
        ..moveTo(-5, 0)
        ..lineTo(5, 0)
        ..lineTo(6, -24)
        ..lineTo(0, -30)
        ..lineTo(-6, -24)
        ..close();
      canvas.drawPath(greatBlade, Paint()..color = const Color(0xFF78716C));
      canvas.drawPath(
        greatBlade,
        Paint()
          ..color = const Color(0xFFFFD700)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    } else {
      // Warhammer khổng lồ của George
      final handlePaint = Paint()..color = const Color(0xFF5D4037)..strokeWidth = 3;
      canvas.drawLine(const Offset(0, 8), const Offset(0, -18), handlePaint);
      final hammerHeadPaint = Paint()..color = const Color(0xFF546E7A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -26, 16, 12), const Radius.circular(3)),
        hammerHeadPaint,
      );
      final runePaint = Paint()..color = const Color(0xFFFFEB3B);
      canvas.drawRect(const Rect.fromLTWH(-5, -23, 10, 6), runePaint);
    }

    canvas.restore();
  }

  /// Vẽ hiệu ứng 3 Kỹ năng riêng biệt chuẩn theo từng nhân vật trong Asset 1 -> Asset 4
  void _renderSkillEffectsUnderneath(Canvas canvas, Offset center) {
    final primary = _heroPrimaryColor;
    final secondary = _heroSecondaryColor;
    final dirSign = isFacingRight ? 1.0 : -1.0;

    // =========================================================================
    // SKILL 1: CHIÊU THỨC ĐẶC TRƯNG TỪNG NHÂN VẬT
    // =========================================================================
    if (skill1TrailTimer > 0) {
      final alpha = (skill1TrailTimer / 0.35).clamp(0.0, 1.0);
      final progress = 1.0 - alpha;

      if (heroId == 'valeria') {
        // Valeria Skill 1: Băng Hỏa Trảm (Tia băng xanh & Cầu lửa đỏ xoắn kép bắn về trước)
        final reach = 25.0 + progress * 75.0;
        for (int i = 0; i < 6; i++) {
          final t = i / 5.0;
          final px = center.dx + dirSign * (reach * t);
          final wave = sin(t * pi * 3 + animTime * 18) * 10;
          canvas.drawCircle(
            Offset(px, center.dy + wave),
            5.5 - t * 2,
            Paint()..color = const Color(0xFF00E5FF).withValues(alpha: alpha),
          );
          canvas.drawCircle(
            Offset(px, center.dy - wave),
            5.5 - t * 2,
            Paint()..color = const Color(0xFFFF3D00).withValues(alpha: alpha),
          );
        }
      } else if (heroId == 'garrick') {
        // Garrick Skill 1: Đất Lở (Hàng gai đá vàng thổ trồi lên theo đường thẳng)
        for (int i = 1; i <= 4; i++) {
          final sx = center.dx + dirSign * (i * 20.0);
          final spikeH = (12.0 + i * 3.0) * alpha;
          final spike = Path()
            ..moveTo(sx - 6, center.dy + 14)
            ..lineTo(sx, center.dy + 14 - spikeH)
            ..lineTo(sx + 6, center.dy + 14)
            ..close();
          canvas.drawPath(
            spike,
            Paint()..color = const Color(0xFFD97706).withValues(alpha: alpha),
          );
          canvas.drawPath(
            spike,
            Paint()
              ..color = const Color(0xFFFFD700).withValues(alpha: alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
      } else if (heroId == 'nova_blade') {
        // Nova Blade Skill 1: Energy Slash (3 sóng kiếm lưỡi liềm Cyan phát sáng)
        for (int i = 0; i < 3; i++) {
          final dist = 18.0 + i * 16.0 + progress * 25.0;
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(center.dx + dirSign * dist, center.dy),
              width: 32,
              height: 48,
            ),
            isFacingRight ? -pi / 2.2 : pi / 1.8,
            pi * 0.9,
            false,
            Paint()
              ..color = const Color(0xFF00E5FF).withValues(alpha: alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.8 - i * 0.8
              ..strokeCap = StrokeCap.round,
          );
        }
      } else if (heroId == 'ember_02' || heroId == 'ember') {
        // Ember-02 Skill 1: Hỏa Cầu Liên Hoàn (3 quả cầu lửa bắn tỏa phía trước)
        for (final spreadY in [-14.0, 0.0, 14.0]) {
          final fx = center.dx + dirSign * (24.0 + progress * 70.0);
          final fy = center.dy + spreadY * (0.5 + progress);
          canvas.drawCircle(
            Offset(fx, fy),
            7.5 * alpha,
            Paint()..color = const Color(0xFFFF3D00).withValues(alpha: alpha),
          );
          canvas.drawCircle(
            Offset(fx, fy),
            4.0 * alpha,
            Paint()..color = const Color(0xFFFFEA00).withValues(alpha: alpha),
          );
        }
      } else if (heroId == 'shadow_01' || heroId == 'ninja') {
        // Shadow-01 / Ninja Skill 1: Plasma Shot / Phi tiêu 3 hướng
        for (final spreadY in [-16.0, 0.0, 16.0]) {
          final px = center.dx + dirSign * (22.0 + progress * 75.0);
          final py = center.dy + spreadY * (0.4 + progress);
          canvas.drawArc(
            Rect.fromCenter(center: Offset(px, py), width: 18, height: 18),
            0,
            pi * 1.4,
            false,
            Paint()
              ..color = const Color(0xFFE040FB).withValues(alpha: alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0,
          );
        }
      } else if (skill1StartOffset != null) {
        // Kaelen Lôi Ảnh Trảm / George Búa Cuồng Phong
        final start =
            center + Offset(skill1StartOffset!.x, skill1StartOffset!.y);
        final mid1 = Offset.lerp(start, center, 0.33)! + const Offset(0, -10);
        final mid2 = Offset.lerp(start, center, 0.66)! + const Offset(0, 10);

        final boltPath = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(mid1.dx, mid1.dy)
          ..lineTo(mid2.dx, mid2.dy)
          ..lineTo(center.dx, center.dy);

        canvas.drawPath(
          boltPath,
          Paint()
            ..color = primary.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.0,
        );
        canvas.drawPath(
          boltPath,
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawCircle(
          center,
          36 * (1.0 - alpha * 0.5),
          Paint()
            ..color = secondary.withValues(alpha: alpha * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }

    // =========================================================================
    // SKILL 2: VÒNG XOÁY KỸ NĂNG QUANH THÂN (4 GIÂY)
    // =========================================================================
    if (skill2VortexTimer > 0) {
      if (heroId == 'valeria') {
        // Valeria Skill 2: Vòng Xoáy Nguyên Tố (Bão tuyết xanh kết hợp Lửa đỏ xoay quanh thân)
        canvas.drawCircle(
          center,
          44,
          Paint()
            ..color = const Color(0x8800E5FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );
        canvas.drawCircle(
          center,
          50,
          Paint()
            ..color = const Color(0x88FF3D00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5,
        );
        for (int i = 0; i < 6; i++) {
          final a = animTime * 6.0 + i * (pi / 3);
          final orbColor =
              i.isEven ? const Color(0xFF00E5FF) : const Color(0xFFFF3D00);
          canvas.drawCircle(
            Offset(center.dx + cos(a) * 47, center.dy + sin(a) * 47),
            5.5,
            Paint()..color = orbColor,
          );
        }
      } else if (heroId == 'garrick' || heroId == 'tanker') {
        // Garrick Skill 2: Hộ Thể Hoàng Kim (Giáp đá vàng kim rực rỡ + 6 khiên đá xoay)
        canvas.drawCircle(
          center,
          42,
          Paint()..color = const Color(0x33FFD700),
        );
        canvas.drawCircle(
          center,
          42,
          Paint()
            ..color = const Color(0xFFFFB300)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
        for (int i = 0; i < 6; i++) {
          final a = animTime * 4.5 + i * (pi / 3);
          final rx = center.dx + cos(a) * 42;
          final ry = center.dy + sin(a) * 42;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(rx, ry), width: 10, height: 12),
              const Radius.circular(2),
            ),
            Paint()..color = const Color(0xFFFFD700),
          );
        }
      } else if (heroId == 'ember_02' || heroId == 'ember') {
        // Ember-02 Skill 2: Cột Lửa Địa Ngục (4 cột lửa rực cháy xoay quanh vòng ma pháp)
        canvas.drawCircle(
          center,
          46,
          Paint()
            ..color = const Color(0xFFFF6D00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        for (int i = 0; i < 4; i++) {
          final a = animTime * 5.5 + i * (pi / 2);
          final fx = center.dx + cos(a) * 46;
          final fy = center.dy + sin(a) * 46;
          canvas.drawCircle(
            Offset(fx, fy),
            8,
            Paint()..color = const Color(0xFFFF3D00),
          );
          canvas.drawCircle(
            Offset(fx, fy - 4),
            4.5,
            Paint()..color = const Color(0xFFFFEA00),
          );
        }
      } else {
        // Kaelen / Nova Blade / Shadow-01 / George: 4 Thanh Kiếm Ánh Sáng xoay 360 độ + Đuôi sáng
        canvas.drawCircle(
          center,
          45,
          Paint()
            ..color = secondary.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );

        for (int i = 0; i < 4; i++) {
          final angle = animTime * 6.5 + i * (pi / 2);
          final bx = center.dx + cos(angle) * 45;
          final by = center.dy + sin(angle) * 45;

          canvas.save();
          canvas.translate(bx, by);
          canvas.rotate(angle + pi / 2);
          // Chuôi kiếm
          canvas.drawRect(
            const Rect.fromLTWH(-12, -1.5, 5, 3),
            Paint()..color = const Color(0xFFFFD700),
          );
          // Lưỡi kiếm phát sáng
          final swordPath = Path()
            ..moveTo(-7, -3)
            ..lineTo(14, 0)
            ..lineTo(-7, 3)
            ..close();
          canvas.drawPath(
            swordPath,
            Paint()..color = i.isEven ? primary : secondary,
          );
          canvas.restore();
        }
      }
    }

    // =========================================================================
    // SKILL 3 (ULTIMATE): CHIÊU CUỐI HỦY DIỆT DIỆN RỘNG
    // =========================================================================
    if (skill3JudgmentTimer > 0) {
      final progress = (skill3JudgmentTimer / 3.0).clamp(0.0, 1.0);

      if (heroId == 'valeria') {
        // Valeria Skill 3: Mưa Thiên Thạch Băng Hỏa (6 tảng đá Băng & Lửa rơi từ trời)
        canvas.drawCircle(
          center,
          62,
          Paint()..color = const Color(0x2200E5FF),
        );
        for (int i = 0; i < 6; i++) {
          final angle = i * (pi / 3) + animTime * 2.0;
          final dist = 22.0 + (i % 2) * 26.0;
          final mx = center.dx + cos(angle) * dist;
          final my = center.dy + sin(angle) * dist;
          final isIce = i.isEven;
          canvas.drawCircle(
            Offset(mx, my),
            9.0 * progress,
            Paint()
              ..color = isIce
                  ? const Color(0xFF00E5FF).withValues(alpha: progress)
                  : const Color(0xFFFF3D00).withValues(alpha: progress),
          );
          canvas.drawCircle(
            Offset(mx, my),
            4.5 * progress,
            Paint()..color = Colors.white.withValues(alpha: progress),
          );
        }
      } else if (heroId == 'garrick') {
        // Garrick Skill 3: Nội Địa Chấn (Mặt đất nứt toác 8 hướng màu vàng thổ)
        canvas.drawCircle(
          center,
          64,
          Paint()..color = const Color(0x33FFB300),
        );
        for (int i = 0; i < 8; i++) {
          final a = i * (pi / 4);
          canvas.drawLine(
            center,
            Offset(center.dx + cos(a) * 64, center.dy + sin(a) * 64),
            Paint()
              ..color = const Color(0xFFFFD700).withValues(alpha: progress)
              ..strokeWidth = 3.2,
          );
        }
      } else if (heroId == 'nova_blade') {
        // Nova Blade Skill 3: Quantum Burst (Trường lượng tử tím 3 vòng đồng tâm + Cột sáng)
        for (final r in [24.0, 44.0, 64.0]) {
          canvas.drawOval(
            Rect.fromCenter(center: center, width: r * 2, height: r * 1.15),
            Paint()
              ..color = const Color(0xFFE040FB).withValues(alpha: progress * 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.4,
          );
        }
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy - 55),
            width: 14 * progress,
            height: 120,
          ),
          Paint()..color = const Color(0xFFE040FB).withValues(alpha: progress * 0.8),
        );
      } else {
        // Kaelen Thiên Phạt Lôi Ngục / Ember-02 Thái Dương Bộc Phá / George Cuồng Nộ
        canvas.drawCircle(
          center,
          60,
          Paint()..color = primary.withValues(alpha: 0.18),
        );
        canvas.drawCircle(
          center,
          60,
          Paint()
            ..color = secondary.withValues(alpha: progress * 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );

        if (skill3JudgmentTimer > 2.2) {
          final beamAlpha = ((skill3JudgmentTimer - 2.2) / 0.8).clamp(0.0, 1.0);
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(center.dx, center.dy - 65),
              width: 22 * beamAlpha,
              height: 145,
            ),
            Paint()..color = primary.withValues(alpha: beamAlpha * 0.75),
          );
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(center.dx, center.dy - 65),
              width: 9 * beamAlpha,
              height: 145,
            ),
            Paint()..color = Colors.white.withValues(alpha: beamAlpha),
          );
        }
      }
    }
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

    // Nền trắng viền xanh cyan
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF00B0FF)
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
