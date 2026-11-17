import 'dart:math';

import 'package:flame/components.dart';

import '../../models/pvp_match.dart';
import '../components/player.dart';
import '../components/pvp_bot_player.dart';

enum BotCombatState { approaching, kiting, dodging, executingCombo, retreating }

enum BotActionType { none, move, basicAttack, skill1, skill2, skill3, dodge }

/// Controller AI chiến đấu PvP thích ứng 3 bậc rank:
/// - Bronze/Silver: 0.6s độ trễ phản xạ, 50% sai số góc, tiếp cận đơn giản và đánh thường.
/// - Gold/Platinum: 0.3s độ trễ phản xạ, 15% sai số góc, né chiêu cơ bản, combo Chiêu 1 -> Đánh thường khi người chơi cạn Ki.
/// - Diamond/Challenger: 0.1s độ trễ phản xạ, 0% sai số, đón đầu quỹ đạo (predictive aiming), thả diều (kiting), combo 3 chiêu dồn sát thương.
/// - Tuyệt đối tuân thủ tài nguyên Ki (+5 Ki/s) và thời gian hồi chiêu (cooldowns).
class PvpBotAi extends Component {
  final BotDifficulty difficulty;
  PvpBotPlayerComponent? bot;
  PlayerComponent? targetPlayer;

  // Timers & Trạng thái
  double decisionTimer = 0.0;
  double dodgeTimer = 0.0;
  Vector2 dodgeDirection = Vector2.zero();
  BotCombatState currentState = BotCombatState.approaching;

  // Cooldowns
  double skill1Cooldown = 0.0;
  double skill2Cooldown = 0.0;
  double skill3Cooldown = 0.0;
  double basicAttackCooldown = 0.0;

  // Cooldown chuẩn của các chiêu
  static const double cooldownSkill1 = 4.0;
  static const double cooldownSkill2 = 7.0;
  static const double cooldownSkill3 = 12.0;
  static const double cooldownBasicAttack = 0.8;

  // Chi phí Ki chuẩn
  static const double kiCostSkill1 = 25.0;
  static const double kiCostSkill2 = 35.0;
  static const double kiCostSkill3 = 40.0;

  PvpBotAi({required this.difficulty, this.bot, this.targetPlayer});

  /// Độ trễ phản xạ (Reflex Latency) theo bậc rank
  double get decisionInterval {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.6;
      case BotDifficulty.goldPlatinum:
        return 0.3;
      case BotDifficulty.diamondChallenger:
        return 0.1;
    }
  }

  /// Tỉ lệ sai lệch nhắm bắn (Aim Error Rate)
  double get aimErrorRate {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.50; // 50% error
      case BotDifficulty.goldPlatinum:
        return 0.15; // 15% error
      case BotDifficulty.diamondChallenger:
        return 0.0; // 0% error (khóa mục tiêu chính xác)
    }
  }

  /// Góc lệch nhắm bắn tối đa (radians)
  double get maxAimErrorAngle {
    // 50% -> pi/4 (~45 độ), 15% -> ~13.5 độ, 0% -> 0 độ
    return aimErrorRate * (pi / 2);
  }

  /// Xác suất né chiêu telegraphed skills
  double get dodgeChance {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.0; // Không bao giờ né
      case BotDifficulty.goldPlatinum:
        return 0.70; // 70% né đòn telegraphed
      case BotDifficulty.diamondChallenger:
        return 0.90; // 90% né hoàn hảo
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    tick(dt);

    if (bot == null || targetPlayer == null) return;
    if (!(bot!.combatEnabled?.call() ?? true) || bot!.isStunned) {
      bot!.moveDirection = Vector2.zero();
      return;
    }
    if (bot!.currentHp <= 0) return;

    // Xử lý đang né đòn (Dodge state)
    if (dodgeTimer > 0) {
      bot!.moveDirection = dodgeDirection;
      return;
    }

    // Đánh giá quyết định chiến thuật khi hết chu kỳ phản xạ
    if (decisionTimer >= decisionInterval) {
      decisionTimer = 0.0;
      evaluateTactics();
    }
  }

  /// Cập nhật thời gian hồi chiêu và timers
  void tick(double dt) {
    if (skill1Cooldown > 0) skill1Cooldown = max(0, skill1Cooldown - dt);
    if (skill2Cooldown > 0) skill2Cooldown = max(0, skill2Cooldown - dt);
    if (skill3Cooldown > 0) skill3Cooldown = max(0, skill3Cooldown - dt);
    if (basicAttackCooldown > 0) {
      basicAttackCooldown = max(0, basicAttackCooldown - dt);
    }
    if (dodgeTimer > 0) dodgeTimer = max(0, dodgeTimer - dt);
    decisionTimer += dt;
  }

  /// Tính toán vector ngắm / di chuyển đón đầu (Predictive Aiming Vector)
  Vector2 calculateAimDirection({
    required Vector2 botPosition,
    required Vector2 targetPosition,
    required Vector2 targetVelocity,
    double projectileSpeed = 160.0,
    Random? random,
  }) {
    Vector2 predictedTarget = targetPosition.clone();

    if (difficulty == BotDifficulty.diamondChallenger) {
      // Đón đầu toàn diện: t_intercept = dist / speed, P_pred = P_tgt + V_tgt * t
      final dist = botPosition.distanceTo(targetPosition);
      final tIntercept = projectileSpeed > 0 ? (dist / projectileSpeed) : 0.0;
      predictedTarget = targetPosition + (targetVelocity * tIntercept);
    } else if (difficulty == BotDifficulty.goldPlatinum) {
      // Đón đầu cự ly ngắn (0.2s)
      predictedTarget = targetPosition + (targetVelocity * 0.2);
    }
    // Bronze: Nhắm thẳng vào vị trí hiện tại (predictedTarget = targetPosition)

    Vector2 dir = predictedTarget - botPosition;
    if (dir.length2 == 0) return Vector2(1, 0);
    dir.normalize();

    // Áp dụng sai số góc (Aim Error Wobble)
    final errAngle = maxAimErrorAngle;
    if (errAngle > 0) {
      final rng = random ?? Random();
      final offset = (rng.nextDouble() * 2 - 1) * errAngle;
      final cosA = cos(offset);
      final sinA = sin(offset);
      final rotX = dir.x * cosA - dir.y * sinA;
      final rotY = dir.x * sinA + dir.y * cosA;
      dir = Vector2(rotX, rotY).normalized();
    }

    return dir;
  }

  /// Kiểm tra có thể tung chiêu hay không dựa trên Ki và Cooldown
  bool canCastSkill1(double currentKi) =>
      currentKi >= kiCostSkill1 && skill1Cooldown <= 0;

  bool canCastSkill2(double currentKi) =>
      currentKi >= kiCostSkill2 && skill2Cooldown <= 0;

  bool canCastSkill3(double currentKi) =>
      currentKi >= kiCostSkill3 && skill3Cooldown <= 0;

  bool canBasicAttack() => basicAttackCooldown <= 0;

  /// Đánh giá tình huống chiến thuật và ra lệnh cho Bot
  void evaluateTactics() {
    final b = bot;
    if (b == null) return;

    final target = b.primaryTarget ?? targetPlayer;
    if (target == null) {
      b.moveDirection = Vector2.zero();
      return;
    }

    Vector2 targetPos = target.position;
    Vector2 targetVel = Vector2.zero();
    double targetKi = 50.0;
    bool targetAttacking = false;
    bool targetBerserk = false;

    if (target is PlayerComponent) {
      targetPos = target.position;
      targetVel = target.moveDirection * target.speed;
      targetKi = target.currentKi;
      targetAttacking = target.isAttacking;
      targetBerserk = target.isBerserk;
    } else if (target is PvpBotPlayerComponent) {
      targetPos = target.position;
      targetVel = target.moveDirection * target.speed;
      targetKi = target.currentKi;
      targetAttacking = target.isAttacking;
      targetBerserk = target.isBerserk;
    }

    final dist = b.position.distanceTo(targetPos);
    final aimDir = calculateAimDirection(
      botPosition: b.position,
      targetPosition: targetPos,
      targetVelocity: targetVel,
      projectileSpeed: b.speed,
    );

    if (b.isStunned) {
      b.moveDirection = Vector2.zero();
      return;
    }
    if (b.kit.ranged) {
      currentState = BotCombatState.kiting;
      b.moveDirection = dist < 150
          ? -aimDir
          : (dist > 280 ? aimDir : Vector2.zero());
      if (dist <= b.kit.attackRange && canBasicAttack()) {
        basicAttackCooldown = b.kit.attackInterval;
        b.performBasicAttack();
      }
      if (dist <= 330 && b.kitCooldowns[0] <= 0) b.executeSkill1();
      if (dist < 110 && b.kitCooldowns[1] <= 0) b.executeSkill2();
      if (dist <= 360 && b.kitCooldowns[2] <= 0) b.executeSkill3();
      return;
    }
    final rng = Random();

    // 1. KIỂM TRA NÉ CHIÊU (DODGE TELEGRAPHED SKILLS)
    if (targetAttacking || (targetBerserk && dist < 120)) {
      if (rng.nextDouble() < dodgeChance) {
        _performDodge(b.position, targetPos);
        return;
      }
    }

    // 2. PHÂN NHÁNH HÀNH VI THEO CẤP ĐỘ RANK
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        _evaluateBronzeTactics(b, dist, aimDir);
        break;

      case BotDifficulty.goldPlatinum:
        _evaluateGoldTactics(b, targetKi, targetBerserk, dist, aimDir);
        break;

      case BotDifficulty.diamondChallenger:
        _evaluateDiamondTactics(b, targetBerserk, dist, aimDir);
        break;
    }
  }

  void _performDodge(Vector2 botPos, Vector2 threatPos) {
    currentState = BotCombatState.dodging;
    dodgeTimer = 0.45; // Né đòn trong 0.45 giây

    final threatVector = botPos - threatPos;
    final perpendicular = Vector2(-threatVector.y, threatVector.x).normalized();
    // Kết hợp lùi và dạt ngang
    dodgeDirection = (threatVector.normalized() * 0.5 + perpendicular * 0.8)
        .normalized();
  }

  void _evaluateBronzeTactics(
    PvpBotPlayerComponent b,
    double dist,
    Vector2 aimDir,
  ) {
    currentState = BotCombatState.approaching;
    // Đơn giản: tiến thẳng vào mục tiêu và đánh thường khi tới tầm
    if (dist > 45) {
      b.moveDirection = aimDir;
    } else {
      b.moveDirection = Vector2.zero();
      if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack();
      }
    }
  }

  void _evaluateGoldTactics(
    PvpBotPlayerComponent b,
    double targetKi,
    bool targetBerserk,
    double dist,
    Vector2 aimDir,
  ) {
    // Nếu mục tiêu cạn Ki (< 20): Combo Chiêu 1 -> Đánh thường
    if (targetKi < 20 && canCastSkill1(b.currentKi) && dist <= 85) {
      currentState = BotCombatState.executingCombo;
      b.moveDirection = Vector2.zero();
      skill1Cooldown = cooldownSkill1;
      b.executeSkill1();
      // Nối tiếp đánh thường ngay sau đó
      if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack();
      }
      return;
    }

    // Nếu mục tiêu bật cuồng nộ và bot không cuồng nộ: tạm lùi
    if (targetBerserk && dist < 130) {
      currentState = BotCombatState.retreating;
      b.moveDirection = -aimDir;
      return;
    }

    if (dist > 50) {
      currentState = BotCombatState.approaching;
      b.moveDirection = aimDir;
    } else {
      b.moveDirection = Vector2.zero();
      // Ưu tiên dùng skill nếu đủ Ki và hết cooldown
      if (canCastSkill2(b.currentKi) && dist <= 110) {
        skill2Cooldown = cooldownSkill2;
        b.executeSkill2();
      } else if (canCastSkill1(b.currentKi) && dist <= 85) {
        skill1Cooldown = cooldownSkill1;
        b.executeSkill1();
      } else if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack();
      }
    }
  }

  void _evaluateDiamondTactics(
    PvpBotPlayerComponent b,
    bool targetBerserk,
    double dist,
    Vector2 aimDir,
  ) {
    // 1. Quản lý khoảng cách Thả diều (Kiting Distance Management)
    // Nếu Bot cạn Ki (< 40) hoặc mục tiêu đang Berserk: thả diều ở cự ly an toàn 130-180px
    if ((b.currentKi < 40 && b.currentHp < 70) ||
        (targetBerserk && !b.isBerserk)) {
      currentState = BotCombatState.kiting;
      if (dist < 130) {
        b.moveDirection = -aimDir; // Lùi lại
      } else if (dist > 180) {
        b.moveDirection = aimDir; // Giữ cự ly
      } else {
        // Dạt ngang vòng cung
        b.moveDirection = Vector2(-aimDir.y, aimDir.x);
      }
      return;
    }

    // 2. Combo 3 chiêu dồn sát thương cực hạn (3-skill burst):
    // Chiêu 3 (Berserk) -> Chiêu 2 (Nện Đất) -> Chiêu 1 (Búa Cuồng Phong) -> Đánh thường
    if (b.currentKi >= 40 && !b.isBerserk && canCastSkill3(b.currentKi)) {
      skill3Cooldown = cooldownSkill3;
      b.executeSkill3();
    }

    if (dist > 45) {
      currentState = BotCombatState.approaching;
      b.moveDirection = aimDir;
    } else {
      b.moveDirection = Vector2.zero();
      currentState = BotCombatState.executingCombo;

      if (canCastSkill2(b.currentKi) && dist <= 110) {
        skill2Cooldown = cooldownSkill2;
        b.executeSkill2();
      } else if (canCastSkill1(b.currentKi) && dist <= 85) {
        skill1Cooldown = cooldownSkill1;
        b.executeSkill1();
      } else if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack();
      }
    }
  }

  /// Đặt lại toàn bộ trạng thái AI cho hiệp mới
  void resetRound() {
    decisionTimer = 0.0;
    dodgeTimer = 0.0;
    dodgeDirection = Vector2.zero();
    skill1Cooldown = 0.0;
    skill2Cooldown = 0.0;
    skill3Cooldown = 0.0;
    basicAttackCooldown = 0.0;
    currentState = BotCombatState.approaching;
  }
}
