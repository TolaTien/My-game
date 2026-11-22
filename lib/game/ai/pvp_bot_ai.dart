import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import '../../models/pvp_match.dart';
import '../components/hero_projectile.dart';
import '../components/player.dart';
import '../components/pvp_bot_player.dart';
import 'astar_pathfinder.dart';

enum BotCombatState {
  approaching,
  kiting,
  dodging,
  executingCombo,
  retreating,
}

enum BotActionType {
  none,
  move,
  basicAttack,
  skill1,
  skill2,
  skill3,
  dodge,
}

/// Controller AI chiến đấu PvP thích ứng 3 bậc rank:
/// - Bronze/Silver: 0.6s độ trễ phản xạ, 50% sai số góc, tiếp cận đơn giản và đánh thường.
/// - Gold/Platinum: 0.3s độ trễ phản xạ, 15% sai số góc, né chiêu cơ bản, combo Chiêu 1 -> Đánh thường khi người chơi cạn Ki.
/// - Diamond/Challenger: 0.1s độ trễ phản xạ, 0% sai số, đón đầu quỹ đạo (predictive aiming), thả diều (kiting), combo 3 chiêu dồn sát thương.
/// - Tự động tìm đường A* vượt chướng ngại vật, tránh kẹt tường/trụ, và tuân thủ tài nguyên Ki (+5 Ki/s) & cooldown.
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

  // A* Pathfinding & Obstacle Navigation state
  List<Vector2> _waypoints = [];
  int _waypointIndex = 0;
  double _pathRecalcTimer = 0.0;
  Vector2 _lastPathTargetPos = Vector2.zero();

  // Stuck detection & recovery
  double _stuckTimer = 0.0;
  Vector2 _lastStuckCheckPos = Vector2.zero();
  double _unstuckTimer = 0.0;
  Vector2 _unstuckDirection = Vector2.zero();

  // Strafe rhythm for natural orb-walking / circle-strafing
  double _strafeSwitchTimer = 0.0;
  double _strafeSign = 1.0;

  // Cooldown chuẩn của các chiêu
  static const double cooldownSkill1 = 4.0;
  static const double cooldownSkill2 = 7.0;
  static const double cooldownSkill3 = 12.0;
  static const double cooldownBasicAttack = 0.68;

  // Chi phí Ki chuẩn
  static const double kiCostSkill1 = 20.0;
  static const double kiCostSkill2 = 30.0;
  static const double kiCostSkill3 = 45.0;

  static const double _pathRecalcInterval = 0.22;
  static const double _waypointReachRadius = 14.0;
  static const double _agentClearanceRadius = 12.5;
  static const double _rangedAttackRange = 240.0;

  PvpBotAi({
    required this.difficulty,
    this.bot,
    this.targetPlayer,
  });

  /// Độ trễ phản xạ (Reflex Latency) theo bậc rank
  double get decisionInterval {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.35;
      case BotDifficulty.goldPlatinum:
        return 0.20;
      case BotDifficulty.diamondChallenger:
        return 0.08;
    }
  }

  /// Tỉ lệ sai lệch nhắm bắn (Aim Error Rate)
  double get aimErrorRate {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.24; // 24% error
      case BotDifficulty.goldPlatinum:
        return 0.10; // 10% error
      case BotDifficulty.diamondChallenger:
        return 0.0; // 0% error (khóa mục tiêu chính xác)
    }
  }

  /// Góc lệch nhắm bắn tối đa (radians)
  double get maxAimErrorAngle {
    return aimErrorRate * (pi / 2);
  }

  /// Xác suất né chiêu / đạn bay tới
  double get dodgeChance {
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        return 0.25;
      case BotDifficulty.goldPlatinum:
        return 0.72;
      case BotDifficulty.diamondChallenger:
        return 0.92;
    }
  }

  double _skill1RangeFor(PvpBotPlayerComponent b) {
    final id = b.opponentInfo.heroId;
    if (b.isRangedHero ||
        id == 'ninja' ||
        id == 'nova_blade' ||
        id == 'nova' ||
        id == 'shadow_01' ||
        id == 'shadow') {
      return 215.0;
    }
    return 95.0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (bot == null || targetPlayer == null) return;
    if (bot!.currentHp <= 0) {
      bot!.moveDirection = Vector2.zero();
      return;
    }

    // Chờ đến khi hiệp đấu thực sự bắt đầu (không đánh sớm trong 3s đếm ngược)
    if (bot!.canAct != null && !bot!.canAct!()) {
      bot!.moveDirection = Vector2.zero();
      _waypoints.clear();
      _waypointIndex = 0;
      _stuckTimer = 0.0;
      _unstuckTimer = 0.0;
      return;
    }

    tick(dt);

    final target = _resolveActiveTarget();
    if (target == null) {
      bot!.moveDirection = Vector2.zero();
      _waypoints.clear();
      _waypointIndex = 0;
      return;
    }

    // Xử lý thoát kẹt khẩn cấp nếu vừa chạm góc chướng ngại vật
    if (_unstuckTimer > 0) {
      _unstuckTimer = max(0.0, _unstuckTimer - dt);
      bot!.moveDirection = _unstuckDirection;
      return;
    }

    // Xử lý đang né đòn (Dodge state)
    if (dodgeTimer > 0) {
      bot!.moveDirection = dodgeDirection;
      return;
    }

    // Kiểm tra chống kẹt (Stuck Detection) khi bot đang di chuyển
    if (!bot!.moveDirection.isZero()) {
      _stuckTimer += dt;
      if (_stuckTimer >= 0.35) {
        final movedDist = bot!.position.distanceTo(_lastStuckCheckPos);
        _stuckTimer = 0.0;
        _lastStuckCheckPos = bot!.position.clone();
        if (movedDist < 6.0) {
          _triggerUnstuck(bot!.position, target.position);
          return;
        }
      }
    } else {
      _stuckTimer = 0.0;
      _lastStuckCheckPos = bot!.position.clone();
    }

    // Bám theo đường dẫn A* từng frame để vượt chướng ngại vật mượt, không lố góc
    if (currentState == BotCombatState.approaching) {
      _pathRecalcTimer -= dt;
      _updateApproachingSteering(bot!, target.position);
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
    _strafeSwitchTimer += dt;
    if (_strafeSwitchTimer >= 1.35) {
      _strafeSwitchTimer = 0.0;
      _strafeSign = -_strafeSign;
    }
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

  PositionComponent? _resolveActiveTarget() {
    final b = bot;
    if (b == null) return null;
    // Trong 2v2/4v4, ưu tiên dứt điểm kẻ địch yếu máu (< 35% HP) trong tầm gần
    if (b.getHostileTargets != null) {
      final alive = b.getHostileTargets!().where((c) {
        if (c is PlayerComponent) return c.currentHp > 0;
        if (c is PvpBotPlayerComponent) return c.currentHp > 0;
        return false;
      }).toList();
      if (alive.isNotEmpty) {
        alive.sort((a, c) {
          double score(PositionComponent comp) {
            final dist = b.position.distanceTo(comp.position);
            double hpRatio = 1.0;
            if (comp is PlayerComponent && comp.maxHp > 0) {
              hpRatio = comp.currentHp / comp.maxHp;
            } else if (comp is PvpBotPlayerComponent && comp.maxHp > 0) {
              hpRatio = comp.currentHp / comp.maxHp;
            }
            final lowHpBonus = hpRatio < 0.35 ? -110.0 : (hpRatio < 0.6 ? -35.0 : 0.0);
            return dist + lowHpBonus;
          }
          return score(a).compareTo(score(c));
        });
        return alive.first;
      }
    }
    final candidate = b.primaryTarget ?? targetPlayer;
    if (candidate == null) return null;
    if (candidate is PlayerComponent && candidate.currentHp <= 0) return null;
    if (candidate is PvpBotPlayerComponent && candidate.currentHp <= 0) return null;
    return candidate;
  }

  /// Quét đạn địch đang lao thẳng về phía Bot để né ngang (Projectile Sidestep).
  HeroProjectile? _findIncomingThreatProjectile(PvpBotPlayerComponent b) {
    final parent = b.parent;
    if (parent == null) return null;
    for (final proj in parent.children.whereType<HeroProjectile>()) {
      if (!proj.isMounted) continue;
      // Bot địch né đạn của phe người chơi; đồng minh né đạn của phe địch
      final isHostileProj = b.opponentInfo.isAlly ? !proj.isFromPlayer : proj.isFromPlayer;
      if (!isHostileProj) continue;
      final toBot = b.position - proj.position;
      final dist = toBot.length;
      if (dist > 145.0 || dist < 4.0) continue;
      final forwardDot = toBot.normalized().dot(proj.direction);
      if (forwardDot < 0.72) continue;
      final perpDist = (toBot - proj.direction * toBot.dot(proj.direction)).length;
      if (perpDist <= 34.0) {
        return proj;
      }
    }
    return null;
  }

  bool _hasClearPath(Vector2 from, Vector2 to) {
    final b = bot;
    if (b == null) return true;
    final grid = b.getWalkableGrid?.call();
    final interiorObstacles =
        b.getInteriorObstacleRects?.call() ?? b.getObstacleRects?.call();
    if (grid != null && grid.isNotEmpty) {
      return AStarPathfinder.hasClearCorridor(
        from,
        to,
        grid,
        obstacleRects: interiorObstacles,
        clearanceRadius: _agentClearanceRadius,
      );
    }
    if (interiorObstacles != null && interiorObstacles.isNotEmpty) {
      for (final rect in interiorObstacles) {
        if (AStarPathfinder.segmentIntersectsRect(
          from,
          to,
          rect.inflate(_agentClearanceRadius),
        )) {
          return false;
        }
      }
    }
    return true;
  }

  bool _isPointSafe(Vector2 point) {
    final b = bot;
    if (b == null) return true;
    final grid = b.getWalkableGrid?.call();
    if (grid != null && grid.isNotEmpty) {
      final (col, row) = AStarPathfinder.worldToGrid(point);
      if (col < 0 || col >= grid.length || row < 0 || row >= grid[0].length) {
        return false;
      }
      if (!grid[col][row]) return false;
    }
    final obstacles = b.getObstacleRects?.call();
    if (obstacles != null) {
      final padded = Rect.fromLTRB(
        point.x - 12,
        point.y - 10,
        point.x + 12,
        point.y + 18,
      );
      for (final obs in obstacles) {
        if (padded.overlaps(obs)) return false;
      }
    }
    return true;
  }

  /// Chọn hướng di chuyển an toàn gần với [preferredDir] nhất mà không đâm vào tường/trụ.
  Vector2 _pickSafeDirection(Vector2 botPos, Vector2 preferredDir) {
    if (preferredDir.length2 == 0) return Vector2.zero();
    final base = preferredDir.normalized();
    const anglesDeg = [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0];
    const probeDist = 34.0;

    for (final deg in anglesDeg) {
      final rad = deg * pi / 180.0;
      final cosA = cos(rad);
      final sinA = sin(rad);
      final candidate = Vector2(
        base.x * cosA - base.y * sinA,
        base.x * sinA + base.y * cosA,
      ).normalized();
      final probePoint = botPos + candidate * probeDist;
      if (_isPointSafe(probePoint) && _hasClearPath(botPos, probePoint)) {
        return candidate;
      }
    }
    return base;
  }

  void _recalculatePath(Vector2 botPos, Vector2 targetPos) {
    final grid = bot?.getWalkableGrid?.call();
    if (grid == null || grid.isEmpty) {
      _waypoints = [targetPos.clone()];
      _waypointIndex = 0;
      _lastPathTargetPos = targetPos.clone();
      return;
    }

    if (_hasClearPath(botPos, targetPos)) {
      _waypoints.clear();
      _waypointIndex = 0;
      _lastPathTargetPos = targetPos.clone();
      return;
    }

    _waypoints = AStarPathfinder.findPath(
      botPos,
      targetPos,
      grid,
      allowDirectLineOfSight: false,
    );
    _waypointIndex = 0;
    _lastPathTargetPos = targetPos.clone();
  }

  /// Trả về vector di chuyển tiếp cận [targetPos] có né chướng ngại vật bằng A*.
  Vector2 _steerTowardTarget(
    PvpBotPlayerComponent b,
    Vector2 targetPos,
    Vector2 fallbackAimDir,
  ) {
    final grid = b.getWalkableGrid?.call();
    final obstacles = b.getObstacleRects?.call();
    final hasArenaObstacles =
        (grid != null && grid.isNotEmpty) || (obstacles != null && obstacles.isNotEmpty);
    if (!hasArenaObstacles) {
      return fallbackAimDir;
    }

    if (_hasClearPath(b.position, targetPos)) {
      _waypoints.clear();
      _waypointIndex = 0;
      return fallbackAimDir;
    }

    if (_waypoints.isEmpty ||
        _waypointIndex >= _waypoints.length ||
        _lastPathTargetPos.distanceTo(targetPos) > 36.0) {
      _recalculatePath(b.position, targetPos);
    }

    while (_waypointIndex < _waypoints.length &&
        b.position.distanceTo(_waypoints[_waypointIndex]) <= _waypointReachRadius) {
      _waypointIndex++;
    }

    if (_waypointIndex < _waypoints.length) {
      final wp = _waypoints[_waypointIndex];
      final toWp = wp - b.position;
      if (toWp.length2 > 0.001) {
        return toWp.normalized();
      }
    }

    return _pickSafeDirection(b.position, (targetPos - b.position).normalized());
  }

  void _updateApproachingSteering(PvpBotPlayerComponent b, Vector2 targetPos) {
    if (_hasClearPath(b.position, targetPos)) {
      _waypoints.clear();
      _waypointIndex = 0;
      // Giữ nguyên hướng tiếp cận hiện tại nếu đã rất gần tầm đánh
      if (b.moveDirection.isZero()) return;
      final direct = targetPos - b.position;
      if (direct.length2 > 1.0) {
        b.moveDirection = direct.normalized();
      }
      return;
    }

    if (_pathRecalcTimer <= 0 ||
        _waypoints.isEmpty ||
        _waypointIndex >= _waypoints.length ||
        _lastPathTargetPos.distanceTo(targetPos) > 36.0) {
      _pathRecalcTimer = _pathRecalcInterval;
      _recalculatePath(b.position, targetPos);
    }

    while (_waypointIndex < _waypoints.length &&
        b.position.distanceTo(_waypoints[_waypointIndex]) <= _waypointReachRadius) {
      _waypointIndex++;
    }

    if (_waypointIndex < _waypoints.length) {
      final toWp = _waypoints[_waypointIndex] - b.position;
      if (toWp.length2 > 0.001) {
        b.moveDirection = toWp.normalized();
      }
    }
  }

  void _triggerUnstuck(Vector2 botPos, Vector2 targetPos) {
    _waypoints.clear();
    _waypointIndex = 0;
    _recalculatePath(botPos, targetPos);

    if (_waypoints.isNotEmpty) {
      final dir = (_waypoints.first - botPos);
      if (dir.length2 > 0.001) {
        _unstuckDirection = _pickSafeDirection(botPos, dir.normalized());
        _unstuckTimer = 0.25;
        bot?.moveDirection = _unstuckDirection;
        return;
      }
    }

    final toTarget = targetPos - botPos;
    final base = toTarget.length2 > 0.001 ? toTarget.normalized() : Vector2(1, 0);
    final perp = Vector2(-base.y, base.x);
    _unstuckDirection = _pickSafeDirection(botPos, perp);
    _unstuckTimer = 0.25;
    bot?.moveDirection = _unstuckDirection;
  }

  /// Đánh giá tình huống chiến thuật và ra lệnh cho Bot
  void evaluateTactics() {
    final b = bot;
    if (b == null) return;

    final target = _resolveActiveTarget();
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
    final clearSight = _hasClearPath(b.position, targetPos);
    final aimDir = calculateAimDirection(
      botPosition: b.position,
      targetPosition: targetPos,
      targetVelocity: targetVel,
      projectileSpeed: b.isRangedHero ? 330.0 : b.speed,
    );

    final rng = Random();

    // 1. KIỂM TRA NÉ ĐẠN ĐANG BAY TỚI (PROJECTILE SIDESTEP)
    final threatProj = _findIncomingThreatProjectile(b);
    if (threatProj != null && rng.nextDouble() < dodgeChance) {
      final perpA = Vector2(-threatProj.direction.y, threatProj.direction.x);
      final perpB = -perpA;
      final sideDir = _isPointSafe(b.position + perpA * 38) ? perpA : perpB;
      currentState = BotCombatState.dodging;
      dodgeTimer = 0.34;
      dodgeDirection = _pickSafeDirection(b.position, sideDir);
      b.moveDirection = dodgeDirection;
      return;
    }

    // 1.5 KIỂM TRA NÉ CHIÊU CẬN CHIẾN / CUỒNG NỘ
    if (clearSight && ((targetAttacking && dist < 95) || (targetBerserk && dist < 120))) {
      if (rng.nextDouble() < dodgeChance * 0.75) {
        _performDodge(b.position, targetPos);
        return;
      }
    }

    // 2. PHÂN NHÁNH HÀNH VI THEO CẤP ĐỘ RANK
    switch (difficulty) {
      case BotDifficulty.bronzeSilver:
        _evaluateBronzeTactics(b, targetPos, dist, clearSight, aimDir);
        break;

      case BotDifficulty.goldPlatinum:
        _evaluateGoldTactics(
          b,
          targetPos,
          targetKi,
          targetBerserk,
          dist,
          clearSight,
          aimDir,
        );
        break;

      case BotDifficulty.diamondChallenger:
        _evaluateDiamondTactics(
          b,
          targetPos,
          targetBerserk,
          dist,
          clearSight,
          aimDir,
        );
        break;
    }
  }

  void _performDodge(Vector2 botPos, Vector2 threatPos) {
    currentState = BotCombatState.dodging;
    dodgeTimer = 0.45; // Né đòn trong 0.45 giây

    final threatVector = botPos - threatPos;
    if (threatVector.length2 == 0) {
      dodgeDirection = _pickSafeDirection(botPos, Vector2(0, 1));
      return;
    }
    final perpendicular = Vector2(-threatVector.y, threatVector.x).normalized();
    // Kết hợp lùi và dạt ngang, đồng thời đảm bảo không né đâm vào tường/cột trụ
    final desired = (threatVector.normalized() * 0.5 + perpendicular * 0.8)
        .normalized();
    dodgeDirection = _pickSafeDirection(botPos, desired);
  }

  void _faceTarget(PvpBotPlayerComponent b, Vector2 targetPos) {
    final dx = targetPos.x - b.position.x;
    if (dx.abs() > 0.5) {
      b.isFacingRight = dx > 0;
    }
  }

  void _evaluateBronzeTactics(
    PvpBotPlayerComponent b,
    Vector2 targetPos,
    double dist,
    bool clearSight,
    Vector2 aimDir,
  ) {
    final attackRange = b.isRangedHero ? _rangedAttackRange : 48.0;
    final skill1Range = _skill1RangeFor(b);
    final canHitNow = dist <= attackRange && (!b.isRangedHero || clearSight);

    if (!canHitNow || !clearSight) {
      currentState = BotCombatState.approaching;
      b.moveDirection = _steerTowardTarget(b, targetPos, aimDir);
    } else {
      _faceTarget(b, targetPos);
      // Di chuyển lách nhẹ thay vì đứng chết 1 chỗ
      if (b.isRangedHero && dist < 105) {
        b.moveDirection = _pickSafeDirection(b.position, -aimDir);
      } else {
        final strafe = Vector2(-aimDir.y * _strafeSign, aimDir.x * _strafeSign);
        b.moveDirection = _pickSafeDirection(b.position, strafe * 0.55);
      }
      if (canCastSkill1(b.currentKi) && dist <= skill1Range) {
        currentState = BotCombatState.executingCombo;
        skill1Cooldown = cooldownSkill1;
        b.executeSkill1();
      } else if (canBasicAttack()) {
        currentState = BotCombatState.approaching;
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack(aimDirection: aimDir);
      }
    }
  }

  void _evaluateGoldTactics(
    PvpBotPlayerComponent b,
    Vector2 targetPos,
    double targetKi,
    bool targetBerserk,
    double dist,
    bool clearSight,
    Vector2 aimDir,
  ) {
    final skill1Range = _skill1RangeFor(b);

    // Kích hoạt Skill 3 khi máu dưới 70% hoặc áp sát tốt
    if (clearSight && canCastSkill3(b.currentKi) && dist <= 185 && (b.currentHp < b.maxHp * 0.72 || targetKi < 25)) {
      currentState = BotCombatState.executingCombo;
      _faceTarget(b, targetPos);
      skill3Cooldown = cooldownSkill3;
      b.executeSkill3();
    }

    // Nếu mục tiêu cạn Ki (< 20): Combo Chiêu 1 -> Đánh thường
    if (clearSight && targetKi < 20 && canCastSkill1(b.currentKi) && dist <= skill1Range) {
      currentState = BotCombatState.executingCombo;
      _faceTarget(b, targetPos);
      skill1Cooldown = cooldownSkill1;
      b.executeSkill1();
      if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack(aimDirection: aimDir);
      }
      return;
    }

    // Nếu mục tiêu bật cuồng nộ và bot không cuồng nộ: tạm lùi theo hướng an toàn
    if (clearSight && targetBerserk && !b.isBerserk && dist < 130) {
      currentState = BotCombatState.retreating;
      b.moveDirection = _pickSafeDirection(b.position, -aimDir);
      return;
    }

    final attackRange = b.isRangedHero ? _rangedAttackRange : 50.0;
    final canHitNow = dist <= attackRange && (!b.isRangedHero || clearSight);

    if (!canHitNow || !clearSight) {
      currentState = BotCombatState.approaching;
      b.moveDirection = _steerTowardTarget(b, targetPos, aimDir);
    } else {
      _faceTarget(b, targetPos);
      // Vừa đánh vừa lách ngang / thả diều
      if (b.isRangedHero && dist < 120) {
        currentState = BotCombatState.kiting;
        b.moveDirection = _pickSafeDirection(b.position, -aimDir);
      } else {
        final strafe = Vector2(-aimDir.y * _strafeSign, aimDir.x * _strafeSign);
        b.moveDirection = _pickSafeDirection(b.position, strafe);
      }
      // Ưu tiên dùng skill đúng tầm (cả cận chiến lẫn tầm xa)
      if (canCastSkill2(b.currentKi) && dist <= 115) {
        currentState = BotCombatState.executingCombo;
        skill2Cooldown = cooldownSkill2;
        b.executeSkill2();
      } else if (canCastSkill1(b.currentKi) && dist <= skill1Range) {
        currentState = BotCombatState.executingCombo;
        skill1Cooldown = cooldownSkill1;
        b.executeSkill1();
      } else if (canBasicAttack()) {
        currentState = BotCombatState.executingCombo;
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack(aimDirection: aimDir);
      }
    }
  }

  void _evaluateDiamondTactics(
    PvpBotPlayerComponent b,
    Vector2 targetPos,
    bool targetBerserk,
    double dist,
    bool clearSight,
    Vector2 aimDir,
  ) {
    final skill1Range = _skill1RangeFor(b);

    // 1. Quản lý khoảng cách Thả diều (Kiting Distance Management)
    if (clearSight &&
        ((b.currentKi < 30 && b.currentHp < b.maxHp * 0.30) || (targetBerserk && !b.isBerserk))) {
      currentState = BotCombatState.kiting;
      if (dist < 135) {
        b.moveDirection = _pickSafeDirection(b.position, -aimDir);
      } else if (dist > 195) {
        b.moveDirection = _steerTowardTarget(b, targetPos, aimDir);
      } else {
        b.moveDirection = _pickSafeDirection(
          b.position,
          Vector2(-aimDir.y * _strafeSign, aimDir.x * _strafeSign),
        );
      }
      if (b.isRangedHero && dist <= _rangedAttackRange && canBasicAttack()) {
        _faceTarget(b, targetPos);
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack(aimDirection: aimDir);
      }
      return;
    }

    // 2. Combo 3 chiêu dồn sát thương cực hạn (3-skill burst):
    if (clearSight &&
        canCastSkill3(b.currentKi) &&
        dist <= (b.isRangedHero ? 235.0 : 185.0)) {
      _faceTarget(b, targetPos);
      skill3Cooldown = cooldownSkill3;
      b.executeSkill3();
    }

    final attackRange = b.isRangedHero ? _rangedAttackRange : 48.0;
    final canHitNow = dist <= attackRange && (!b.isRangedHero || clearSight);

    if (!canHitNow || !clearSight) {
      currentState = BotCombatState.approaching;
      b.moveDirection = _steerTowardTarget(b, targetPos, aimDir);
    } else {
      _faceTarget(b, targetPos);
      // Luôn giữ chuyển động linh hoạt: tướng đánh xa thả diều 130-210px, cận chiến lách vòng cung
      if (b.isRangedHero && dist < 130) {
        currentState = BotCombatState.kiting;
        final kiteVec = (-aimDir * 0.75 + Vector2(-aimDir.y * _strafeSign, aimDir.x * _strafeSign) * 0.65).normalized();
        b.moveDirection = _pickSafeDirection(b.position, kiteVec);
      } else {
        currentState = BotCombatState.executingCombo;
        final strafe = Vector2(-aimDir.y * _strafeSign, aimDir.x * _strafeSign);
        b.moveDirection = _pickSafeDirection(b.position, strafe);
      }

      if (canCastSkill2(b.currentKi) && dist <= 115) {
        skill2Cooldown = cooldownSkill2;
        b.executeSkill2();
      } else if (canCastSkill1(b.currentKi) && dist <= skill1Range) {
        skill1Cooldown = cooldownSkill1;
        b.executeSkill1();
      } else if (canBasicAttack()) {
        basicAttackCooldown = cooldownBasicAttack;
        b.performBasicAttack(aimDirection: aimDir);
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
    _waypoints.clear();
    _waypointIndex = 0;
    _pathRecalcTimer = 0.0;
    _lastPathTargetPos = Vector2.zero();
    _stuckTimer = 0.0;
    _lastStuckCheckPos = Vector2.zero();
    _unstuckTimer = 0.0;
    _unstuckDirection = Vector2.zero();
  }
}
