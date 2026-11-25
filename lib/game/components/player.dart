import 'dart:async';
import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/stat_growth_formula.dart';
import '../../registry/sprite_image_cache.dart';
import '../../registry/asset_registry.dart';
import '../../services/audio_service.dart';
import '../skill_runtime.dart';
import '../combat/hero_skill_system.dart';
import 'dungeon_map.dart';
import 'hero_sprite_animator.dart';

class PlayerComponent extends PositionComponent with CollisionCallbacks {
  // Chỉ số nhân vật (giữ chuẩn baseline cho toàn bộ unit test)
  double maxHp = GameConstants.playerMaxHp;
  double _currentHp = GameConstants.playerMaxHp;
  double get currentHp => _currentHp;
  set currentHp(double value) {
    _currentHp = value;
    if (value <= 0) clearBasicAttackBuffer();
  }

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
  int facingRow = 2; // 0: Down, 1: Down-Right, 2: Right, 3: Up-Right, 4: Up
  bool isAttacking = false;
  bool _actionsEnabled = true;
  bool get actionsEnabled => _actionsEnabled;
  set actionsEnabled(bool value) {
    _actionsEnabled = value;
    if (!value) clearBasicAttackBuffer();
  }

  bool get canAct => actionsEnabled && currentHp > 0;
  static const double _basicAttackDuration = .25;
  static const double _basicAttackBufferWindow = .15;
  bool _isBasicAttackSwing = false;
  void Function()? _bufferedBasicAttack;
  double _basicAttackBufferRemaining = 0;
  static const double basicAttackRange = 55;
  static const double comboFinisherRange = 80;
  static const double basicAttackHalfAngle = pi / 3;
  double attackTimer = 0.0;
  double attackAngle = 0.0;
  double animTime = 0.0;
  final HeroSpriteAnimator visualAnimator = HeroSpriteAnimator();
  double _dashTrailTimer = 0;
  Vector2? _visualPosition;

  // Basic combo: horizontal sweep, diagonal cut, circular finisher.
  int comboStep = 0;
  double comboResetTimer = 0.0;

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
  late final List<SkillRuntime> skillRuntimes;
  SkillRuntime skillRuntime(int slot) => skillRuntimes[slot - 1];
  SkillAssetConfig skillConfig(int slot) => skillRuntime(slot).config;
  double get skill1VisualCd => skillRuntime(1).cooldownRemaining;
  set skill1VisualCd(double value) => skillRuntime(1).cooldownRemaining = value;
  double get skill2VisualCd => skillRuntime(2).cooldownRemaining;
  set skill2VisualCd(double value) => skillRuntime(2).cooldownRemaining = value;
  double get skill3VisualCd => skillRuntime(3).cooldownRemaining;
  set skill3VisualCd(double value) => skillRuntime(3).cooldownRemaining = value;
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
  double get berserkTimer => skillRuntime(3).effectRemaining;
  set berserkTimer(double value) => skillRuntime(3).effectRemaining = value;
  double invulnerabilityTimer = 0;
  Color get skillEffectColor => _heroPrimaryColor;

  double stealthTimer = 0.0;
  double ironShieldTimer = 0.0;
  double ironShieldAbsorption = 0.0;
  double speedBoostTimer = 0.0;
  double speedBoostMultiplier = 1.0;
  bool get _usesCatalogSkills => heroId == 'kaelen';
  double get effectiveSpeed =>
      speed *
      (_usesCatalogSkills
          ? skillRuntimes.fold<double>(
              1,
              (m, s) =>
                  m *
                  (s.effectRemaining > 0
                      ? s.config.effects.moveSpeedMultiplier
                      : 1),
            )
          : ((isBerserk ? 1.45 : 1) *
                (stealthTimer > 0 ? 1.45 : 1) *
                (speedBoostTimer > 0 ? speedBoostMultiplier : 1)));

  double get currentSkill1MaxCd => _usesCatalogSkills
      ? skillConfig(1).cooldown
      : HeroSkillSystem.getSkillMeta(heroId, 1).cooldown;
  double get currentSkill2MaxCd => _usesCatalogSkills
      ? skillConfig(2).cooldown
      : HeroSkillSystem.getSkillMeta(heroId, 2).cooldown;
  double get currentSkill3MaxCd => _usesCatalogSkills
      ? skillConfig(3).cooldown
      : HeroSkillSystem.getSkillMeta(heroId, 3).cooldown;
  double get currentSkill1KiCost => _usesCatalogSkills
      ? skillConfig(1).kiCost
      : HeroSkillSystem.getSkillMeta(heroId, 1).kiCost;
  double get currentSkill2KiCost => _usesCatalogSkills
      ? skillConfig(2).kiCost
      : HeroSkillSystem.getSkillMeta(heroId, 2).kiCost;
  double get currentSkill3KiCost => _usesCatalogSkills
      ? skillConfig(3).kiCost
      : HeroSkillSystem.getSkillMeta(heroId, 3).kiCost;

  void activateStealthVeil({required double duration}) {
    stealthTimer = max(stealthTimer, duration);
    onStatsChanged?.call();
  }

  void activateIronShield({
    required double duration,
    required double absorption,
  }) {
    ironShieldTimer = max(ironShieldTimer, duration);
    ironShieldAbsorption = max(ironShieldAbsorption, absorption);
    onStatsChanged?.call();
  }

  void activateSpeedBoost({
    required double duration,
    required double multiplier,
  }) {
    speedBoostTimer = max(speedBoostTimer, duration);
    speedBoostMultiplier = max(speedBoostMultiplier, multiplier);
    onStatsChanged?.call();
  }

  // Khiên hấp thụ sát thương (từ Shield Drone, Aegis-X9 Golden Overdrive hoặc Kỹ năng phòng thủ)
  double _baseDamageAbsorption = 0.0;
  double _companionDamageAbsorption = 0.0;
  double temporaryPetDamageAbsorption = 0.0;
  Object? passivePetShieldOwner;
  Object? activePetShieldOwner;
  Object? activePetAttackBuffOwner;
  double get damageAbsorption => max(
    max(
      max(_baseDamageAbsorption, _companionDamageAbsorption),
      goldenShieldTimer > 0 ? temporaryPetDamageAbsorption : 0.0,
    ),
    ironShieldTimer > 0 ? ironShieldAbsorption : 0.0,
  );
  set damageAbsorption(double value) => _baseDamageAbsorption = value;
  set companionDamageAbsorption(double value) =>
      _companionDamageAbsorption = value;
  double get effectiveDamageAbsorption => damageAbsorption.clamp(0.0, .9);
  double goldenShieldTimer = 0.0;

  // Buff sát thương từ kỹ năng đặc biệt của Trợ thủ, Cuồng Nộ & Ẩn Thân
  double petAttackBuffTimer = 0.0;
  double petAttackBuffBonus = 0.0;
  double get effectiveDamage {
    double mult = 1.0;
    if (petAttackBuffTimer > 0) mult += petAttackBuffBonus;
    if (isBerserk) mult += 0.55;
    if (stealthTimer > 0) mult += 0.40;
    return damage *
        mult *
        (_usesCatalogSkills
            ? skillRuntimes.fold<double>(
                1,
                (m, s) =>
                    m *
                    (s.effectRemaining > 0
                        ? s.config.effects.attackMultiplier
                        : 1),
              )
            : 1);
  }

  double get shieldHp => ironShieldTimer > 0
      ? (ironShieldAbsorption * 120.0)
      : (goldenShieldTimer > 0
            ? 50.0
            : (damageAbsorption > 0 ? (damageAbsorption * 100.0) : 0.0));

  // Lưu vị trí trước đó để chặn xuyên tường
  Vector2 previousPosition = Vector2.zero();

  // Speech bubble trên đầu Player
  String? speechBubbleText;
  double speechBubbleTimer = 0.0;

  // Callback báo HUD cập nhật
  Function()? onStatsChanged;

  final String heroId;
  final bool legacyPvpSkills;
  int userHeroLevel;

  PlayerComponent({
    required Vector2 position,
    this.heroId = 'george',
    this.userHeroLevel = 1,
    this.legacyPvpSkills = false,
  }) : super(position: position, size: Vector2(36, 40), anchor: Anchor.center) {
    final registry = GameAssetRegistry.instance;
    skillRuntimes = List.generate(3, (index) {
      final slot = index + 1;
      final configured = legacyPvpSkills
          ? SkillAssetConfig.legacy(heroId, slot, pvp: true)
          : registry.getSkillForHeroSlot(heroId, slot);
      return SkillRuntime(
        configured ?? SkillAssetConfig.legacy(heroId, slot),
        enabled: configured != null || !registry.isInitialized,
      );
    }, growable: false);
    applyUserHeroLevel(userHeroLevel);
    // Hitbox va chạm với quái và tường
    add(RectangleHitbox(size: Vector2(24, 28), position: Vector2(6, 10)));
  }

  /// Áp dụng chỉ số cộng thêm từ cấp độ Nhân Vật của User (Level 1 -> 100)
  void applyUserHeroLevel(int targetHeroLevel) {
    userHeroLevel = targetHeroLevel.clamp(
      StatGrowthFormula.minHeroLevel,
      StatGrowthFormula.maxHeroLevel,
    );
    final scaled = StatGrowthFormula.computeStatsForLevel(
      heroId: heroId,
      level: userHeroLevel,
    );
    maxHp = scaled.maxHp;
    currentHp = maxHp;
    maxKi = scaled.maxKi;
    currentKi = maxKi;
    damage = scaled.attackDamage;
    speed = scaled.moveSpeed;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    unawaited(SpriteImageCache.instance.preloadHero(heroId));
  }

  @override
  void update(double dt) {
    super.update(dt);
    animTime += dt;
    final travelled = _visualPosition == null
        ? 0.0
        : position.distanceTo(_visualPosition!);
    (_visualPosition ??= position.clone()).setFrom(position);
    visualAnimator.update(
      dt,
      moving: canAct && !moveDirection.isZero(),
      distanceTravelled: travelled,
    );
    _dashTrailTimer = max(0, _dashTrailTimer - dt);

    // Hồi phục Ki theo thời gian (throttle cập nhật HUD ~8Hz thay vì 60Hz để tránh lag trên máy yếu)
    if (currentKi < maxKi) {
      final prevIntKi = currentKi.toInt();
      currentKi = min(maxKi, currentKi + 5 * dt);
      if (currentKi.toInt() != prevIntKi || currentKi >= maxKi) {
        onStatsChanged?.call();
      }
    }

    // Giảm các timer hiệu ứng visual & HUD cooldown
    if (hitFlashTimer > 0) hitFlashTimer = max(0.0, hitFlashTimer - dt);
    if (comboResetTimer > 0) {
      comboResetTimer -= dt;
      if (comboResetTimer <= 0) comboStep = 0;
    }
    if (skill1TrailTimer > 0) {
      skill1TrailTimer = max(0.0, skill1TrailTimer - dt);
    }
    if (skill2VortexTimer > 0) {
      skill2VortexTimer = max(0.0, skill2VortexTimer - dt);
    }
    if (skill3JudgmentTimer > 0) {
      skill3JudgmentTimer = max(0.0, skill3JudgmentTimer - dt);
    }
    if (insufficientKiFlashTimer > 0) {
      insufficientKiFlashTimer = max(0.0, insufficientKiFlashTimer - dt);
    }

    for (final skill in skillRuntimes) {
      skill.update(dt);
    }
    invulnerabilityTimer = max(0, invulnerabilityTimer - dt);

    if (goldenShieldTimer > 0) {
      goldenShieldTimer -= dt;
      if (goldenShieldTimer <= 0) {
        goldenShieldTimer = 0.0;
        temporaryPetDamageAbsorption = 0.0;
        activePetShieldOwner = null;
      }
    }

    if (petAttackBuffTimer > 0) {
      petAttackBuffTimer -= dt;
      if (petAttackBuffTimer <= 0) {
        petAttackBuffTimer = 0.0;
        petAttackBuffBonus = 0.0;
      }
    }

    if (stealthTimer > 0) {
      stealthTimer = max(0.0, stealthTimer - dt);
    }
    if (ironShieldTimer > 0) {
      ironShieldTimer = max(0.0, ironShieldTimer - dt);
      if (ironShieldTimer <= 0) ironShieldAbsorption = 0.0;
    }
    if (speedBoostTimer > 0) {
      speedBoostTimer = max(0.0, speedBoostTimer - dt);
      if (speedBoostTimer <= 0) speedBoostMultiplier = 1.0;
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
      if (berserkTimer <= 0) {
        isBerserk = false;
        onStatsChanged?.call();
      }
    }

    // Xử lý hoạt ảnh vung vũ khí đánh thường
    if (_bufferedBasicAttack != null) {
      _basicAttackBufferRemaining -= dt;
      // Keep the exact boundary inclusive despite floating-point frame deltas.
      if (!isAttacking || _basicAttackBufferRemaining < -1e-9) {
        clearBasicAttackBuffer();
      }
    }
    if (isAttacking) {
      attackTimer += dt;
      final swing = ((visualAnimator.actionProgress - .12) / .58).clamp(
        0.0,
        1.0,
      );
      attackAngle = -.9 + (1 - pow(1 - swing, 3)) * 2.1;
      if (attackTimer >= _basicAttackDuration) {
        isAttacking = false;
        _isBasicAttackSwing = false;
        attackTimer = 0.0;
        if (canAct) _bufferedBasicAttack?.call();
      }
    }

    // Di chuyển & lấy mẫu Afterimage Trail
    if (canAct && !moveDirection.isZero()) {
      previousPosition = position.clone();
      position.add(moveDirection * effectiveSpeed * dt);

      faceDirection(moveDirection);

      if (travelled > .001 &&
          SpriteImageCache.instance.getHeroAnimations(heroId) == null) {
        _afterimageSampleTimer += dt;
        if (_afterimageSampleTimer >= 0.04) {
          _afterimageSampleTimer = 0.0;
          afterimagePositions.insert(0, previousPosition.clone());
          if (afterimagePositions.length > 3) {
            afterimagePositions.removeLast();
          }
        }
      }
    } else if (afterimagePositions.isNotEmpty && _dashTrailTimer <= 0) {
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

  void faceDirection(Vector2 direction) {
    final mx = direction.x;
    final my = direction.y;
    final absX = mx.abs();
    final absY = my.abs();
    if (absX > .05) isFacingRight = mx > 0;
    if (my.abs() > .08) {
      facingRow = absX < .414 * absY
          ? (my > 0 ? 0 : 4)
          : absY < .414 * absX
          ? 2
          : (my > 0 ? 1 : 3);
    } else if (absX > .08) {
      facingRow = 2;
    }
  }

  Vector2 get attackDirection => switch (facingRow) {
    0 => Vector2(0, 1),
    1 => Vector2(isFacingRight ? 1 : -1, 1).normalized(),
    3 => Vector2(isFacingRight ? 1 : -1, -1).normalized(),
    4 => Vector2(0, -1),
    _ => Vector2(isFacingRight ? 1 : -1, 0),
  };

  /// Returns true if the swing starts now. A queued press calls [onStarted]
  /// only when its swing starts.
  bool performBasicAttack({void Function()? onStarted}) {
    if (!canAct) return false;
    if (isAttacking) {
      if (_isBasicAttackSwing &&
          attackTimer >= _basicAttackDuration - _basicAttackBufferWindow &&
          _bufferedBasicAttack == null) {
        _basicAttackBufferRemaining = _basicAttackBufferWindow;
        _bufferedBasicAttack = () => _startBasicAttack(onStarted);
      }
      return false;
    }

    _startBasicAttack(onStarted);
    return true;
  }

  void clearBasicAttackBuffer() {
    _bufferedBasicAttack = null;
    _basicAttackBufferRemaining = 0;
  }

  void _startBasicAttack(void Function()? onStarted) {
    clearBasicAttackBuffer();
    _isBasicAttackSwing = true;
    isAttacking = true;
    attackTimer = 0.0;
    visualAnimator.playAction(_basicAttackDuration);
    comboStep = (comboStep % 3) + 1;
    comboResetTimer = 1.2;

    attackAngle = isFacingRight ? -0.8 : 0.8;
    AudioService.instance.playSfx(
      heroId == 'ranger' ? SfxSound.attackArrow : SfxSound.attackHammer,
    );
    onStarted?.call();
  }

  bool canHitBasicAttack(
    Vector2 target, {
    double? range,
    double targetPadding = 0,
  }) {
    final offset = target - position;
    final reach =
        (range ?? (comboStep == 3 ? comboFinisherRange : basicAttackRange)) +
        targetPadding;
    if (offset.length2 > reach * reach) return false;
    if (comboStep == 3 || offset.isZero()) return true;
    final forwardDistance = attackDirection.dot(offset);
    return forwardDistance / offset.length >= cos(basicAttackHalfAngle);
  }

  bool useSkill1() {
    if (!_tryCastSkill(1)) return false;
    clearBasicAttackBuffer();
    _isBasicAttackSwing = false;
    isAttacking = true;
    attackTimer = 0.0;
    skill1TrailTimer = 0.42;
    skill1StartOffset = Vector2(isFacingRight ? -55 : 55, 0);
    return true;
  }

  bool useSkill2() {
    if (!_tryCastSkill(2)) return false;
    clearBasicAttackBuffer();
    skill2VortexTimer = _usesCatalogSkills
        ? max(0.4, skillConfig(2).effects.duration)
        : 3.5;
    _isBasicAttackSwing = false;
    isAttacking = true;
    attackTimer = 0;
    return true;
  }

  bool useSkill3() {
    if ((isBerserk && HeroSkillSystem.normalizeHeroId(heroId) == "george") ||
        !_tryCastSkill(3)) {
      return false;
    }
    clearBasicAttackBuffer();
    isBerserk = HeroSkillSystem.normalizeHeroId(heroId) == 'george';
    if (isBerserk) berserkTimer = 6;
    _isBasicAttackSwing = false;
    isAttacking = true;
    attackTimer = 0;
    skill3JudgmentTimer = _usesCatalogSkills ? 3.0 : 2.6;
    return true;
  }

  bool _tryCastSkill(int slot) {
    final runtime = skillRuntime(slot);
    if (!canAct ||
        (_usesCatalogSkills && !runtime.enabled) ||
        runtime.cooldownRemaining > .05) {
      return false;
    }
    final config = runtime.config;
    final meta = HeroSkillSystem.getSkillMeta(heroId, slot);
    final cost = _usesCatalogSkills ? config.kiCost : meta.kiCost;
    if (currentKi < cost) {
      insufficientKiFlashTimer = 0.45;
      onStatsChanged?.call();
      return false;
    }
    currentKi -= cost;
    runtime.cooldownRemaining = _usesCatalogSkills
        ? config.cooldown
        : meta.cooldown;
    runtime.effectRemaining = _usesCatalogSkills ? config.effects.duration : 0;
    visualAnimator.playAction(slot == 1 ? .55 : .45);
    invulnerabilityTimer = max(
      invulnerabilityTimer,
      _usesCatalogSkills ? config.effects.invulnerabilityDuration : 0,
    );
    onStatsChanged?.call();
    final sound = _usesCatalogSkills
        ? config.sfxAsset
        : switch (slot) {
            1 =>
              HeroSkillSystem.isRangedHero(heroId)
                  ? SfxSound.attackArrow
                  : SfxSound.skillHurricane,
            2 => SfxSound.skillSmash,
            _ => SfxSound.skillBerserk,
          };
    if (!_usesCatalogSkills || config.sfxAsset.isNotEmpty) {
      AudioService.instance.playSfx(sound);
    }
    return true;
  }

  void resetCombatState() {
    clearBasicAttackBuffer();
    _isBasicAttackSwing = false;
    visualAnimator.reset();
    _visualPosition = null;
    afterimagePositions.clear();
    _dashTrailTimer = 0;
    for (final skill in skillRuntimes) {
      skill.reset();
    }
    isAttacking = false;
    attackTimer = 0;
    comboStep = 0;
    comboResetTimer = 0;
    isBerserk = false;
    invulnerabilityTimer = 0;
    stealthTimer = ironShieldTimer = ironShieldAbsorption = speedBoostTimer = 0;
    speedBoostMultiplier = 1;
    skill1TrailTimer = 0;
    skill2VortexTimer = 0;
    skill3JudgmentTimer = 0;
    moveDirection = Vector2.zero();
  }

  void recordDashTrail(Vector2 from, Vector2 to) {
    afterimagePositions.clear();
    for (var i = 1; i <= 3; i++) {
      afterimagePositions.add(from + (to - from) * (1 - i / 4));
    }
    _dashTrailTimer = .2;
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

  void restoreKi(double amount) {
    currentKi = min(maxKi, currentKi + amount);
    onStatsChanged?.call();
  }

  void reduceSkillCooldowns(double seconds) {
    skill1VisualCd = max(0.0, skill1VisualCd - seconds);
    skill2VisualCd = max(0.0, skill2VisualCd - seconds);
    skill3VisualCd = max(0.0, skill3VisualCd - seconds);
    onStatsChanged?.call();
  }

  void say(String text) {
    speechBubbleText = text;
    speechBubbleTimer = 3.0;
  }

  void takeDamage(double dmg) {
    if (currentHp <= 0 || invulnerabilityTimer > 0 || dmg <= 0) return;
    final barrierFactor = 1.0 - effectiveDamageAbsorption;
    var skillFactor = 1.0;
    for (final skill in skillRuntimes) {
      if (_usesCatalogSkills && skill.effectRemaining > 0) {
        skillFactor *= 1 - skill.config.effects.damageReduction;
      }
    }
    if (isBerserk) skillFactor *= 0.6;
    final effectiveDmg = dmg * barrierFactor * skillFactor;
    currentHp = max(0, currentHp - effectiveDmg);
    hitFlashTimer = 0.08;
    onStatsChanged?.call();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final center = Offset(size.x / 2, size.y / 2);
    final sprites = SpriteImageCache.instance.getHeroAnimations(
      heroId,
      facingRow: facingRow,
    );

    // 0. Vẽ hiệu ứng Kỹ năng trên mặt đất (Skill 2 Vortex / Skill 3 Heaven's Judgment / Skill 1 Lightning Trail)
    _renderSkillEffectsUnderneath(canvas, center);
    if (legacyPvpSkills) {
      _renderStandaloneSkillAssets(canvas, center);
    }

    // 0.5 Vẽ bóng mờ Afterimage Trail khi di chuyển (0.4 -> 0.2 -> 0.05)
    if (sprites != null && _dashTrailTimer > 0) {
      final frame = sprites.attack.frameAt(
        visualAnimator.actionElapsed,
        normalizedProgress: visualAnimator.actionProgress,
      );
      for (var i = 0; i < afterimagePositions.length; i++) {
        final offset = afterimagePositions[i] - position;
        canvas.save();
        canvas.translate(center.dx + offset.x, size.y - 2 + offset.y);
        if (!isFacingRight) canvas.scale(-1, 1);
        visualAnimator.painter.draw(
          canvas,
          frame,
          Offset.zero,
          opacity: (.22 - i * .05) * (_dashTrailTimer / .2),
        );
        canvas.restore();
      }
    } else if (sprites == null &&
        !moveDirection.isZero() &&
        afterimagePositions.isNotEmpty) {
      const opacities = [0.35, 0.18, 0.07];
      for (int i = 0; i < afterimagePositions.length; i++) {
        final trailPos = afterimagePositions[i] - position;
        final alpha = i < opacities.length ? opacities[i] : 0.05;
        final ghostPaint = Paint()
          ..color =
              (heroId == 'kaelen'
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
    final bool isEmber = heroId == 'ember_02' || heroId == 'ember';
    final bool isStripHero = SpriteImageCache.isStripAnimatedHero(heroId);
    final bool isCustomAnimated = isNova || isShadow || isEmber || isStripHero;

    // Hiệu ứng nghiêng thân khi chạy, nhún bước chân và lao người khi tấn công
    final isMoving = canAct && visualAnimator.movementWeight > .02;
    final bool novaMultiDirRun = isNova && isMoving && !isAttacking;
    final bool emberMultiDirRun = isEmber && isMoving && !isAttacking;
    final bool stripMultiDirRun = isStripHero && isMoving && !isAttacking;

    canvas.save();
    if (!isFacingRight &&
        !novaMultiDirRun &&
        !emberMultiDirRun &&
        !stripMultiDirRun) {
      canvas.scale(-1, 1);
      canvas.translate(-size.x, 0);
    }

    // Hiệu ứng nghiêng thân khi chạy, nhún bước chân và lao người khi tấn công

    final movementWeight = visualAnimator.movementWeight;
    final gaitAngle = visualAnimator.stridePhase * 2 * pi;
    final runBounce =
        sin(gaitAngle).abs() * -.5 * movementWeight +
        sin(animTime * 3.2) * 1.4 * (1 - movementWeight);
    final breathOffset = runBounce;
    final legSwing = sin(gaitAngle) * 4.8 * movementWeight;
    final attackLunge = visualAnimator.isPlayingAction
        ? sin(visualAnimator.actionProgress * pi) * 3.5
        : 0.0;

    if (sprites == null &&
        (movementWeight > .001 || visualAnimator.isPlayingAction)) {
      canvas.translate(size.x / 2 + attackLunge, size.y / 2);
      canvas.rotate(
        sin(visualAnimator.actionProgress * pi) *
                (visualAnimator.isPlayingAction ? .18 : 0) +
            .08 * movementWeight,
      );
      canvas.translate(-size.x / 2, -size.y / 2);
    }

    // Hiệu ứng hào quang Cuồng Nộ / Pháo Đài Sắt / Ẩn Thân (vẽ 2 vòng bán trong suốt nhẹ GPU thay cho MaskFilter.blur)
    if (isBerserk) {
      final centerPt = Offset(size.x / 2, size.y / 2);
      canvas.drawCircle(
        centerPt,
        30,
        Paint()..color = _heroPrimaryColor.withValues(alpha: 0.16),
      );
      canvas.drawCircle(
        centerPt,
        24,
        Paint()..color = _heroPrimaryColor.withValues(alpha: 0.30),
      );
    }
    if (ironShieldTimer > 0) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        25,
        Paint()..color = _heroPrimaryColor.withValues(alpha: 0.22),
      );
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        25,
        Paint()
          ..color = _heroPrimaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
    }
    if (stealthTimer > 0) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        24,
        Paint()..color = const Color(0xFF8E24AA).withValues(alpha: 0.22),
      );
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

    if (sprites != null && !isCustomAnimated) {
      canvas.save();
      final pivotX = size.x / 2;
      final pivotY = size.y - 2;
      final weight = visualAnimator.movementWeight;
      final strideTilt = sin(gaitAngle) * .008 * weight;
      final bob =
          -sin(gaitAngle).abs() * .35 * weight +
          sin(animTime * 2.6) * .4 * (1 - weight);
      canvas.translate(pivotX + attackLunge, pivotY + bob);
      canvas.rotate(strideTilt);
      visualAnimator.render(canvas, sprites, Offset.zero);
      canvas.restore();
    } else if (heroId == 'kaelen') {
      _renderKaelenThunderblade(canvas, breathOffset, legSwing);
    } else if (isStripHero) {
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
          final mx = moveDirection.x;
          final my = moveDirection.y;
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
          final progress = (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(
            0.0,
            0.999,
          );
          col = (progress * cols).floor().clamp(0, cols - 1);
        } else if (isMoving) {
          col = (animTime * 10.5).floor() % cols;
        } else {
          col = (animTime * 5.5).floor() % cols;
        }
        final cellW = strip.width / cols;
        final cellH = is4DirRunSheet
            ? strip.height / 4.0
            : strip.height.toDouble();
        final srcRect = Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);

        const dstW = 54.0;
        const dstH = 54.0;
        final dstLeft = (size.x - dstW) / 2;
        final dstTop = size.y - 2 - (236.0 / 256.0 * dstH);
        final dstRect = Rect.fromLTWH(dstLeft, dstTop, dstW, dstH);

        final spritePaint = Paint()..filterQuality = FilterQuality.none;
        if (stealthTimer > 0) {
          spritePaint.color = const Color(0x88FFFFFF);
        }
        canvas.drawImageRect(strip, srcRect, dstRect, spritePaint);
      } else {
        _renderClassicHero(canvas, breathOffset, legSwing);
      }
    } else if (isShadow) {
      final String action = isAttacking
          ? 'attack'
          : (isMoving ? 'run' : 'idle');
      final int frameIndex;
      if (isAttacking) {
        final progress = (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(
          0.0,
          0.999,
        );
        frameIndex = (progress * 16).floor().clamp(0, 15);
      } else if (isMoving) {
        frameIndex = (animTime * 14.0).floor() % 16;
      } else {
        frameIndex = (animTime * 11.0).floor() % 16;
      }

      final shadowImg = SpriteImageCache.instance.getHeroSequenceFrame(
        'shadow_01',
        action,
        frameIndex,
      );
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
          final srcRect = Rect.fromLTWH(
            col * cellW,
            runRow * cellH,
            cellW,
            cellH,
          );

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
          final int row;
          final int col;
          if (isAttacking) {
            final progress = (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(
              0.0,
              0.999,
            );
            final comboRow = comboStep == 2 ? 2 : (comboStep == 3 ? 3 : 1);
            row = comboRow.clamp(0, 4);
            col = (progress * 5).floor().clamp(0, 4);
          } else if (isMoving) {
            final idx = (animTime * 12.0).floor() % 25;
            row = idx ~/ 5;
            col = idx % 5;
          } else {
            final idx = (animTime * 8.0).floor() % 25;
            row = idx ~/ 5;
            col = idx % 5;
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
          final srcRect = Rect.fromLTWH(
            col * cellW,
            runRow * cellH,
            cellW,
            cellH,
          );

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
          final int row;
          final int col;
          if (isAttacking) {
            final progress = (attackTimer.clamp(0.0, 0.25) / 0.25).clamp(
              0.0,
              0.999,
            );
            final comboRow = comboStep == 2 ? 2 : (comboStep == 3 ? 3 : 1);
            row = comboRow.clamp(0, 4);
            col = (progress * 5).floor().clamp(0, 4);
          } else if (isMoving) {
            final idx = (animTime * 12.0).floor() % 25;
            row = idx ~/ 5;
            col = idx % 5;
          } else {
            final idx = (animTime * 8.0).floor() % 25;
            row = idx ~/ 5;
            col = idx % 5;
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
      final heroSprite = SpriteImageCache.isProceduralHero(heroId)
          ? null
          : (isAttacking
                ? (SpriteImageCache.instance.getHeroAttackImage(heroId) ??
                      SpriteImageCache.instance.getHeroImage(heroId))
                : SpriteImageCache.instance.getHeroImage(heroId));
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

    // Preserve the legacy slash for non-basic actions such as skill 1.
    if (isAttacking && !_isBasicAttackSwing && sprites == null) {
      final slashColor = _heroPrimaryColor;
      final secondarySlash = _heroSecondaryColor;
      if (HeroSkillSystem.isRangedHero(heroId)) {
        final castAlpha = (1.0 - (attackTimer.clamp(0.0, 0.25) / 0.25)).clamp(
          0.0,
          1.0,
        );
        canvas.drawCircle(
          Offset(size.x / 2 + 16, size.y / 2 - 2),
          11 * (1.2 - castAlpha * 0.4),
          Paint()..color = slashColor.withValues(alpha: castAlpha * 0.35),
        );
        canvas.drawCircle(
          Offset(size.x / 2 + 16, size.y / 2 - 2),
          5 * castAlpha,
          Paint()..color = secondarySlash.withValues(alpha: castAlpha * 0.9),
        );
      } else if (!isStripHero) {
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
    _renderBasicAttackImpact(canvas, center);

    // --- BONG BÓNG QUICK CHAT (SPEECH BUBBLE) ---
    if (speechBubbleText != null) {
      _renderSpeechBubble(canvas, speechBubbleText!);
    }
  }

  void _renderBasicAttackImpact(Canvas canvas, Offset center) {
    if (!canAct || !isAttacking || !_isBasicAttackSwing || comboStep == 0) {
      return;
    }

    final finisher = comboStep == 3;
    final diagonal = comboStep == 2;
    // Swing start is also melee impact / projectile release, even if buffered.
    final duration = finisher ? .18 : (diagonal ? .14 : .12);
    final remaining = 1 - attackTimer / duration;
    if (remaining <= 0) return;
    final fade = remaining * remaining * (3 - 2 * remaining);
    final spread = 4 * (1 - remaining * remaining);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = finisher ? 3.6 : (diagonal ? 2.8 : 2.4)
      ..color = _heroPrimaryColor.withValues(
        alpha: fade * (finisher ? .66 : (diagonal ? .56 : .50)),
      );

    final direction = attackDirection;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(atan2(direction.y, direction.x));
    if (finisher) {
      final ring = Rect.fromCircle(center: Offset.zero, radius: 29 + spread);
      canvas.drawArc(ring, .12, pi - .24, false, paint);
      canvas.drawArc(ring, pi + .12, pi - .24, false, paint);
      paint
        ..strokeWidth = 1.6
        ..color = _heroSecondaryColor.withValues(alpha: fade * .38);
      final rim = ring.inflate(4);
      canvas.drawArc(rim, -.4, .8, false, paint);
      canvas.drawArc(rim, pi - .4, .8, false, paint);
    } else {
      canvas.translate(11, 0);
      if (diagonal) canvas.rotate(isFacingRight ? -.48 : .48);
      final sweep = Rect.fromCenter(
        center: Offset.zero,
        width: (diagonal ? 46 : 52) + spread,
        height: (diagonal ? 54 : 36) + spread,
      );
      final halfSweep = diagonal ? 1.04 : 1.16;
      canvas.drawArc(sweep, -halfSweep, 2 * halfSweep, false, paint);
    }
    canvas.restore();
  }

  /// Vẽ Kaelen & Nova Blade với đầy đủ Cổ, Khuôn mặt sáng rõ, Vai, 2 Tay cầm Song Đao, Thắt lưng, Đùi & Giày
  void _renderKaelenThunderblade(
    Canvas canvas,
    double breathOffset,
    double legSwing,
  ) {
    final isNova = heroId == 'nova_blade';
    final isMoving = !moveDirection.isZero();
    final leftLift = isMoving ? max(0.0, sin(animTime * 15.0)) * 2.5 : 0.0;
    final rightLift = isMoving ? max(0.0, -sin(animTime * 15.0)) * 2.5 : 0.0;
    final armSwing = isMoving
        ? sin(animTime * 15.0) * 0.30
        : sin(animTime * 3.0) * 0.08;

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
    final trimColor = isNova
        ? const Color(0xFF00E5FF)
        : const Color(0xFFFFD700);
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
      Paint()
        ..color = isNova ? const Color(0xFF3730A3) : const Color(0xFF1E3A8A),
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
      ..lineTo(5, breathOffset)
      ..lineTo(13, 3 + breathOffset)
      ..lineTo(18, -3 + breathOffset)
      ..lineTo(22, 3 + breathOffset)
      ..lineTo(29, breathOffset)
      ..lineTo(27, 7 + breathOffset)
      ..close();
    canvas.drawPath(hairPath, Paint()..color = const Color(0xFFF8FAFC));
    canvas.drawRect(
      Rect.fromLTWH(9, 5 + breathOffset, 18, 2.2),
      Paint()..color = trimColor,
    );
    canvas.drawRect(
      Rect.fromLTWH(19, 8.5 + breathOffset, 5, 2.5),
      Paint()..color = const Color(0xFF0284C7),
    );
    canvas.save();
    canvas.translate(27, 18 + breathOffset);
    canvas.rotate(
      isAttacking
          ? (comboStep == 2 ? -attackAngle * 1.1 : attackAngle * 1.25)
          : armSwing,
    );
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
    canvas.drawLine(
      const Offset(0, 8),
      const Offset(0, 2),
      Paint()
        ..color = const Color(0xFFFFD700)
        ..strokeWidth = 3.2,
    );
    canvas.drawLine(
      const Offset(0, 2),
      const Offset(11, -22),
      Paint()
        ..color = const Color(0xFF00E5FF)
        ..strokeWidth = 3.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawLine(
      const Offset(0, 2),
      const Offset(11, -22),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.6,
    );
    canvas.restore();
  }

  Color get _heroPrimaryColor {
    switch (heroId) {
      case 'kaelen':
        return const Color(0xFF00F0FF);
      case 'nova_blade':
      case 'nova':
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
      case 'nova':
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
    final armSwing = isMoving
        ? sin(animTime * 15.0) * 0.32
        : sin(animTime * 3.0) * 0.06;

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
    canvas.drawPath(
      capePath,
      Paint()..color = capeColor.withValues(alpha: 0.85),
    );

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
      final swingRot = comboStep == 2
          ? -attackAngle * 1.15
          : attackAngle * 1.25;
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
      final stringPaint = Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 1.5;
      canvas.drawLine(const Offset(-3, -22), const Offset(-3, 6), stringPaint);
      final arrowPaint = Paint()
        ..color = const Color(0xFFFFEB3B)
        ..strokeWidth = 2;
      canvas.drawLine(const Offset(-10, -8), const Offset(12, -8), arrowPaint);
    } else if (heroId == 'tanker') {
      final shieldPaint = Paint()..color = const Color(0xFF0D47A1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-10, -22, 18, 22),
          const Radius.circular(5),
        ),
        shieldPaint,
      );
      final crossPaint = Paint()
        ..color = const Color(0xFFFFD54F)
        ..strokeWidth = 2;
      canvas.drawLine(const Offset(-1, -20), const Offset(-1, -2), crossPaint);
      canvas.drawLine(const Offset(-8, -11), const Offset(6, -11), crossPaint);
    } else if (heroId == 'ninja' || heroId == 'shadow_01') {
      final bladePaint = Paint()
        ..color = heroId == 'shadow_01'
            ? const Color(0xFFE040FB)
            : const Color(0xFFE0E0E0)
        ..strokeWidth = 2.8;
      final hiltPaint = Paint()
        ..color = const Color(0xFFD50000)
        ..strokeWidth = 3.5;
      canvas.drawLine(const Offset(-2, 6), const Offset(-2, 0), hiltPaint);
      canvas.drawLine(const Offset(-2, 0), const Offset(7, -24), bladePaint);
      canvas.drawLine(const Offset(-7, 5), const Offset(-14, -18), bladePaint);
    } else if (heroId == 'valeria') {
      // Trượng Băng Tinh & 2 cầu Băng-Hỏa xoay quanh của Valeria
      canvas.drawLine(
        const Offset(0, 8),
        const Offset(0, -22),
        Paint()
          ..color = const Color(0xFF90CAF9)
          ..strokeWidth = 2.8,
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
        Paint()
          ..color = const Color(0xFF78350F)
          ..strokeWidth = 2.8,
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
      final handlePaint = Paint()
        ..color = const Color(0xFF5D4037)
        ..strokeWidth = 3;
      canvas.drawLine(const Offset(0, 8), const Offset(0, -18), handlePaint);
      final hammerHeadPaint = Paint()..color = const Color(0xFF546E7A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-8, -26, 16, 12),
          const Radius.circular(3),
        ),
        hammerHeadPaint,
      );
      final runePaint = Paint()..color = const Color(0xFFFFEB3B);
      canvas.drawRect(const Rect.fromLTWH(-5, -23, 10, 6), runePaint);
    }

    canvas.restore();
  }

  /// Vẽ hiệu ứng 3 Kỹ năng riêng biệt chuẩn theo từng nhân vật trong Asset 1 -> Asset 4
  void _renderStandaloneSkillAssets(Canvas canvas, Offset center) {
    for (var slot = 1; slot <= 3; slot++) {
      final remaining = switch (slot) {
        1 => skill1TrailTimer,
        2 => skill2VortexTimer,
        _ => skill3JudgmentTimer,
      };
      if (remaining <= 0) continue;
      final clip = SpriteImageCache.instance.getSkillAnimation(heroId, slot);
      if (clip == null) continue;
      final total = switch (slot) {
        1 => .35,
        2 => max(.4, skillConfig(2).effects.duration),
        _ => 3.0,
      };
      final elapsed = total - remaining;
      final fade = (remaining / .15).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(center.dx, center.dy + 12);
      if (!isFacingRight) canvas.scale(-1, 1);
      visualAnimator.painter.draw(
        canvas,
        clip.frameAt(elapsed),
        Offset.zero,
        height: min(clip.frames.first.worldHeight, slot == 3 ? 150 : 100),
        opacity: fade * .85,
      );
      canvas.restore();
    }
  }

  void _renderSkillEffectsUnderneath(Canvas canvas, Offset center) {
    final primary = _heroPrimaryColor;
    final secondary = _heroSecondaryColor;
    final dirSign = isFacingRight ? 1.0 : -1.0;

    // =========================================================================
    // SKILL 1: CHIÊU THỨC ĐẶC TRƯNG TỪNG NHÂN VẬT
    // =========================================================================
    if (skill1TrailTimer > 0 &&
        SpriteImageCache.instance.getSkillAnimation(heroId, 1) == null) {
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
      } else if (heroId == 'ranger') {
        // Lyra Skill 1: Tiễn Vũ Liên Châu (Cung năng lượng lục bảo tỏa 5 vệt gió)
        for (int i = -2; i <= 2; i++) {
          final a = (isFacingRight ? 0.0 : pi) + i * 0.22;
          canvas.drawLine(
            center + Offset(cos(a) * 10, sin(a) * 10),
            center +
                Offset(
                  cos(a) * (34 + progress * 42),
                  sin(a) * (34 + progress * 42),
                ),
            Paint()
              ..color = const Color(0xFF00E676).withValues(alpha: alpha)
              ..strokeWidth = 2.6
              ..strokeCap = StrokeCap.round,
          );
        }
      } else if (heroId == 'tanker') {
        // Braum Skill 1: Húc Khiên Xung Kích (Vệt xung kích xanh lam thép)
        if (skill1StartOffset != null) {
          final start =
              center + Offset(skill1StartOffset!.x, skill1StartOffset!.y);
          canvas.drawLine(
            start,
            center,
            Paint()
              ..color = const Color(0xFF00B0FF).withValues(alpha: alpha * 0.7)
              ..strokeWidth = 14.0
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawArc(
          Rect.fromCenter(
            center: center + Offset(dirSign * 14, 0),
            width: 32,
            height: 48,
          ),
          isFacingRight ? -pi / 2.2 : pi / 1.8,
          pi * 0.9,
          false,
          Paint()
            ..color = const Color(0xFF80D8FF).withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.5,
        );
      } else if (heroId == 'ninja') {
        // Hayate Skill 1: Phi Tiêu Lướt Ảnh (Vệt lướt huyết ảnh + 3 vệt phi tiêu)
        if (skill1StartOffset != null) {
          final start =
              center + Offset(skill1StartOffset!.x, skill1StartOffset!.y);
          canvas.drawLine(
            start,
            center,
            Paint()
              ..color = const Color(0xFFE91E63).withValues(alpha: alpha * 0.85)
              ..strokeWidth = 6.0
              ..strokeCap = StrokeCap.round,
          );
        }
        for (final spreadY in [-14.0, 0.0, 14.0]) {
          final px = center.dx + dirSign * (20.0 + progress * 65.0);
          final py = center.dy + spreadY * (0.4 + progress);
          canvas.drawCircle(
            Offset(px, py),
            5.0 * alpha,
            Paint()..color = const Color(0xFFFF1744).withValues(alpha: alpha),
          );
        }
      } else if (heroId == 'shadow_01' || heroId == 'shadow') {
        // Shadow-01 Skill 1: Plasma Shot (3 lưỡi dao năng lượng tím)
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
      } else {
        // George Skill 1: Búa Cuồng Phong (Vòng xoáy búa vàng rực 360°)
        for (int i = 0; i < 3; i++) {
          final r = 24.0 + i * 16.0;
          canvas.drawArc(
            Rect.fromCenter(center: center, width: r * 2, height: r * 2),
            animTime * 14.0 + i * 2.0,
            pi * 1.15,
            false,
            Paint()
              ..color =
                  (i.isEven ? const Color(0xFFFFD700) : const Color(0xFFFF6D00))
                      .withValues(alpha: alpha * 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.0 - i * 0.8
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    // =========================================================================
    // SKILL 2: VÒNG XOÁY KỸ NĂNG QUANH THÂN (4 GIÂY)
    // =========================================================================
    if (skill2VortexTimer > 0 &&
        SpriteImageCache.instance.getSkillAnimation(heroId, 2) == null) {
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
          final orbColor = i.isEven
              ? const Color(0xFF00E5FF)
              : const Color(0xFFFF3D00);
          canvas.drawCircle(
            Offset(center.dx + cos(a) * 47, center.dy + sin(a) * 47),
            5.5,
            Paint()..color = orbColor,
          );
        }
      } else if (heroId == 'garrick') {
        // Garrick Skill 2: Hộ Thể Hoàng Kim (Giáp đá vàng kim rực rỡ + 6 khiên đá xoay)
        canvas.drawCircle(center, 42, Paint()..color = const Color(0x33FFD700));
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
      } else if (heroId == 'ranger') {
        // Lyra Skill 2: Nhào Lộn Bẫy Gai (Vòng gai lục bảo & 6 gai nhọn phát sáng)
        final alpha = (skill2VortexTimer / 3.5).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          44,
          Paint()
            ..color = const Color(0xFF00E676).withValues(alpha: alpha * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
        for (int i = 0; i < 6; i++) {
          final a = i * (pi / 3) + animTime * 3.0;
          final p1 = Offset(center.dx + cos(a) * 34, center.dy + sin(a) * 34);
          final p2 = Offset(center.dx + cos(a) * 52, center.dy + sin(a) * 52);
          canvas.drawLine(
            p1,
            p2,
            Paint()
              ..color = const Color(0xFFEEFF41).withValues(alpha: alpha)
              ..strokeWidth = 3.2
              ..strokeCap = StrokeCap.round,
          );
        }
      } else if (heroId == 'tanker') {
        // Braum Skill 2: Pháo Đài Sắt (Mái vòm thép xanh lam + 4 khiên thép xoay)
        canvas.drawCircle(center, 44, Paint()..color = const Color(0x2A00B0FF));
        canvas.drawCircle(
          center,
          44,
          Paint()
            ..color = const Color(0xFF40C4FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2,
        );
        for (int i = 0; i < 4; i++) {
          final a = animTime * 4.0 + i * (pi / 2);
          final sx = center.dx + cos(a) * 44;
          final sy = center.dy + sin(a) * 44;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(sx, sy), width: 10, height: 14),
              const Radius.circular(3),
            ),
            Paint()..color = const Color(0xFF00B0FF),
          );
        }
      } else if (heroId == 'ninja') {
        // Hayate Skill 2: Khói Ẩn Thân (Vòng khói tím-đỏ huyền ảo xoay quanh)
        final alpha = (skill2VortexTimer / 3.5).clamp(0.0, 1.0);
        for (int i = 0; i < 6; i++) {
          final a = animTime * 4.5 + i * (pi / 3);
          final cx = center.dx + cos(a) * 36;
          final cy = center.dy + sin(a) * 36;
          canvas.drawCircle(
            Offset(cx, cy),
            9.0,
            Paint()
              ..color =
                  (i.isEven ? const Color(0xFF8E24AA) : const Color(0xFFE91E63))
                      .withValues(alpha: alpha * 0.45),
          );
        }
      } else if (heroId == 'nova_blade' || heroId == 'nova') {
        // Nova Blade Skill 2: Shadow Dash (Dải plasma tím-cyan cao tốc)
        final alpha = (skill2VortexTimer / 3.5).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          42,
          Paint()
            ..color = const Color(0xFF18FFFF).withValues(alpha: alpha * 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        for (int i = 0; i < 3; i++) {
          final a = animTime * 9.0 + i * (2 * pi / 3);
          canvas.drawArc(
            Rect.fromCenter(center: center, width: 76, height: 76),
            a,
            0.85,
            false,
            Paint()
              ..color = const Color(0xFFE040FB).withValues(alpha: alpha * 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round,
          );
        }
      } else if (heroId == 'shadow_01' || heroId == 'shadow') {
        // Shadow-01 Skill 2: Cyber Spin (Lốc xoáy lưỡi hái hư không 360°)
        canvas.drawCircle(
          center,
          46,
          Paint()
            ..color = const Color(0xFFE040FB).withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
        for (int i = 0; i < 4; i++) {
          final a = animTime * 8.5 + i * (pi / 2);
          canvas.drawArc(
            Rect.fromCenter(center: center, width: 88, height: 88),
            a,
            0.95,
            false,
            Paint()
              ..color = i.isEven
                  ? const Color(0xFFE040FB)
                  : const Color(0xFF00E5FF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4.2
              ..strokeCap = StrokeCap.round,
          );
        }
      } else {
        // George Skill 2: Nện Đất Chấn Động (Sóng chấn động nứt đất vàng-cam)
        final alpha = (skill2VortexTimer / 3.5).clamp(0.0, 1.0);
        canvas.drawCircle(
          center,
          48 * (1.15 - alpha * 0.2),
          Paint()
            ..color = const Color(0xFFFF9800).withValues(alpha: alpha * 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );
        for (int i = 0; i < 6; i++) {
          final a = i * (pi / 3);
          canvas.drawLine(
            center + Offset(cos(a) * 14, sin(a) * 14),
            center + Offset(cos(a) * 46, sin(a) * 46),
            Paint()
              ..color = const Color(0xFFFFD700).withValues(alpha: alpha * 0.85)
              ..strokeWidth = 2.5,
          );
        }
      }
    }

    // =========================================================================
    // SKILL 3 (ULTIMATE): CHIÊU CUỐI HỦY DIỆT DIỆN RỘNG
    // =========================================================================
    if (skill3JudgmentTimer > 0 &&
        SpriteImageCache.instance.getSkillAnimation(heroId, 3) == null) {
      final progress = (skill3JudgmentTimer / 3.0).clamp(0.0, 1.0);

      if (heroId == 'valeria') {
        // Valeria Skill 3: Mưa Thiên Thạch Băng Hỏa (6 tảng đá Băng & Lửa rơi từ trời)
        canvas.drawCircle(center, 62, Paint()..color = const Color(0x2200E5FF));
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
        canvas.drawCircle(center, 64, Paint()..color = const Color(0x33FFB300));
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
              ..color = const Color(0xFFE040FB)
                  .withValues(alpha: progress * 0.85)
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
          Paint()
            ..color = const Color(0xFFE040FB).withValues(alpha: progress * 0.8),
        );
      } else if (heroId == 'ranger') {
        // Lyra Skill 3: Mưa Sao Băng (Vòng sao vàng lục bảo rực sáng)
        canvas.drawCircle(center, 64, Paint()..color = const Color(0x2200E676));
        for (int i = 0; i < 8; i++) {
          final a = i * (pi / 4) + animTime * 3.0;
          final sx = center.dx + cos(a) * 46;
          final sy = center.dy + sin(a) * 46;
          canvas.drawCircle(
            Offset(sx, sy),
            6.5 * progress,
            Paint()
              ..color = const Color(0xFFFFD700).withValues(alpha: progress),
          );
          canvas.drawCircle(
            Offset(sx, sy),
            3.0 * progress,
            Paint()..color = Colors.white.withValues(alpha: progress),
          );
        }
      } else if (heroId == 'tanker') {
        // Braum Skill 3: Địa Chấn Phán Quyết (3 vòng địa chấn xanh lam lan tỏa)
        for (int i = 0; i < 3; i++) {
          final r = (24.0 + i * 24.0) * (1.25 - progress * 0.25);
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..color = const Color(0xFF00B0FF)
                  .withValues(alpha: progress * 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          );
        }
      } else if (heroId == 'ninja') {
        // Hayate Skill 3: Ảnh Sát Liên Hoàn (Chém chữ X huyết ảnh khổng lồ)
        final slashLen = 52.0 * (1.15 - progress * 0.15);
        final xPaint = Paint()
          ..color = const Color(0xFFFF1744).withValues(alpha: progress)
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round;
        final corePaint = Paint()
          ..color = Colors.white.withValues(alpha: progress)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - slashLen, center.dy - slashLen),
          Offset(center.dx + slashLen, center.dy + slashLen),
          xPaint,
        );
        canvas.drawLine(
          Offset(center.dx + slashLen, center.dy - slashLen),
          Offset(center.dx - slashLen, center.dy + slashLen),
          xPaint,
        );
        canvas.drawLine(
          Offset(center.dx - slashLen * 0.8, center.dy - slashLen * 0.8),
          Offset(center.dx + slashLen * 0.8, center.dy + slashLen * 0.8),
          corePaint,
        );
        canvas.drawLine(
          Offset(center.dx + slashLen * 0.8, center.dy - slashLen * 0.8),
          Offset(center.dx - slashLen * 0.8, center.dy + slashLen * 0.8),
          corePaint,
        );
      } else {
        // Ember-02 Thái Dương Bộc Phá / George Cuồng Nộ
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
