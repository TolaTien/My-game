import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../models/pvp_match.dart';
import '../../registry/sprite_image_cache.dart';
import '../ai/pvp_bot_ai.dart';
import 'dungeon_map.dart';
import 'player.dart';

class PvpBotPlayerComponent extends PositionComponent with CollisionCallbacks {
  final PvpOpponentInfo opponentInfo;
  final PlayerComponent targetPlayer;
  final bool enableAi;
  late final PvpBotAi aiController;

  double maxHp = 100.0;
  double currentHp = 100.0;
  double maxKi = 100.0;
  double currentKi = 100.0;
  double damage = 20.0;
  double speed = 160.0;

  bool isFacingRight = false;
  bool isAttacking = false;
  double attackTimer = 0.0;
  double attackAngle = 0.0;

  bool isBerserk = false;
  double berserkTimer = 0.0;

  Vector2 moveDirection = Vector2.zero();
  Vector2 previousPosition = Vector2.zero();
  Vector2? targetPosition;
  Vector2 targetVelocity = Vector2.zero();

  // Speech bubble
  String? speechBubbleText;
  double speechBubbleTimer = 0.0;

  // Callback
  Function()? onStatsChanged;
  List<PositionComponent> Function()? getHostileTargets;

  PvpBotPlayerComponent({
    required Vector2 position,
    required this.opponentInfo,
    required this.targetPlayer,
    this.enableAi = true,
    this.getHostileTargets,
  }) : super(
          position: position,
          size: Vector2(36, 40),
          anchor: Anchor.center,
        ) {
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
    return targetPlayer;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (currentHp <= 0) return;

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
        speed = 160.0;
        damage = 20.0;
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
      position.add(moveDirection * effectiveSpeed * dt);

      if (moveDirection.x > 0.1) isFacingRight = true;
      if (moveDirection.x < -0.1) isFacingRight = false;
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

  void _damageTargetsInRange(double dmg, double range) {
    if (getHostileTargets != null) {
      for (final target in getHostileTargets!()) {
        if (position.distanceTo(target.position) <= range) {
          if (target is PlayerComponent && target.currentHp > 0) {
            target.takeDamage(dmg);
          } else if (target is PvpBotPlayerComponent && target.currentHp > 0) {
            target.takeDamage(dmg);
          }
        }
      }
      return;
    }
    final dist = position.distanceTo(targetPlayer.position);
    if (dist <= range) {
      targetPlayer.takeDamage(dmg);
    }
  }

  void performBasicAttack({bool force = false}) {
    if ((!force && isAttacking) || currentHp <= 0) return;
    isAttacking = true;
    attackTimer = 0.0;
    attackAngle = isFacingRight ? -0.8 : 0.8;

    _damageTargetsInRange(damage, 55);
  }

  void executeSkill1({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && currentKi < 25) return;
    currentKi = max(0, currentKi - 25);
    isAttacking = true;
    attackTimer = -0.3;
    _damageTargetsInRange(damage * 1.8, 85);
    onStatsChanged?.call();
  }

  void executeSkill2({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && currentKi < 35) return;
    currentKi = max(0, currentKi - 35);
    _damageTargetsInRange(damage * 2.5, 110);
    onStatsChanged?.call();
  }

  void executeSkill3({bool force = false}) {
    if (currentHp <= 0) return;
    if (!force && (currentKi < 40 || isBerserk)) return;
    currentKi = max(0, currentKi - 40);
    isBerserk = true;
    berserkTimer = 8.0;
    if (opponentInfo.heroId != 'george' &&
        opponentInfo.heroId != 'ranger' &&
        opponentInfo.heroId != 'tanker' &&
        opponentInfo.heroId != 'ninja') {
      _damageTargetsInRange(damage * 2.2, 140);
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
    currentHp = maxHp;
    currentKi = maxKi;
    isBerserk = false;
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
    if (enableAi && other is WallBlock) {
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

    canvas.save();
    if (currentHp <= 0) {
      // Mờ đi khi bị hạ gục trong 2v2 / 4v4
      canvas.translate(0, 6);
    }
    if (!isFacingRight) {
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

    final botSprite = isAttacking
        ? (SpriteImageCache.instance.getHeroAttackImage(opponentInfo.heroId) ??
            SpriteImageCache.instance.getHeroImage(opponentInfo.heroId))
        : SpriteImageCache.instance.getHeroImage(opponentInfo.heroId);
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

    Color bootsColor;
    Color armorColor;
    Color borderGold;
    Color helmetColor;
    Color crestColor;
    Color eyeColor;

    switch (opponentInfo.heroId) {
      case 'kaelen':
        bootsColor = const Color(0xFF1A237E);
        armorColor = const Color(0xFF1E293B);
        borderGold = const Color(0xFFFFD700);
        helmetColor = const Color(0xFFE2E8F0);
        crestColor = const Color(0xFF00E5FF);
        eyeColor = const Color(0xFF00E5FF);
        break;
      case 'valeria':
      case 'ranger':
        bootsColor = const Color(0xFF3E2723);
        armorColor = const Color(0xFF2E7D32);
        borderGold = const Color(0xFF00E676);
        helmetColor = const Color(0xFF1B5E20);
        crestColor = const Color(0xFFFFD54F);
        eyeColor = const Color(0xFFFFD600);
        break;
      case 'garrick':
      case 'tanker':
        bootsColor = const Color(0xFF263238);
        armorColor = const Color(0xFF1565C0);
        borderGold = const Color(0xFFFFD700);
        helmetColor = const Color(0xFF37474F);
        crestColor = const Color(0xFF00B0FF);
        eyeColor = const Color(0xFF40C4FF);
        break;
      case 'ninja':
        bootsColor = const Color(0xFF212121);
        armorColor = const Color(0xFF311B92);
        borderGold = const Color(0xFFD50000);
        helmetColor = const Color(0xFF1A237E);
        crestColor = const Color(0xFF7B1FA2);
        eyeColor = const Color(0xFFE040FB);
        break;
      case 'george':
      default:
        bootsColor = const Color(0xFF263238);
        armorColor = const Color(0xFF4A148C);
        borderGold = const Color(0xFFCE93D8);
        helmetColor = const Color(0xFF37474F);
        crestColor = const Color(0xFFAB47BC);
        eyeColor = const Color(0xFFE040FB);
        break;
    }

    // 2. Chân
    final boots = Paint()..color = bootsColor;
    canvas.drawRect(Rect.fromLTWH(8, size.y - 10, 7, 8), boots);
    canvas.drawRect(Rect.fromLTWH(21, size.y - 10, 7, 8), boots);

    // 3. Giáp
    final armor = Paint()..color = armorColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(8, 14, 20, 18), const Radius.circular(4)),
      armor,
    );
    final border = Paint()..color = borderGold;
    canvas.drawRect(Rect.fromLTWH(10, 16, 16, 4), border);

    // 4. Mũ sắt / Tóc bạc Kaelen
    final helmet = Paint()..color = helmetColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(9, 4, 18, 14), const Radius.circular(5)),
      helmet,
    );
    final crest = Paint()..color = crestColor;
    canvas.drawRect(Rect.fromLTWH(15, 0, 6, 6), crest);

    // Mắt phát sáng
    final eye = Paint()..color = eyeColor;
    canvas.drawRect(Rect.fromLTWH(20, 9, 6, 3), eye);

    // 5. Vũ khí
    canvas.save();
    canvas.translate(size.x - 2, 20);
    if (isAttacking) {
      canvas.rotate(attackAngle);
    }
    if (opponentInfo.heroId == 'kaelen') {
      // Song kiếm Lôi Quang Hoàng Kim
      canvas.drawLine(const Offset(0, 6), const Offset(8, -22), Paint()..color = const Color(0xFF00E5FF)..strokeWidth = 3.0);
      canvas.drawLine(const Offset(-2, 4), const Offset(5, -18), Paint()..color = const Color(0xFFFFD700)..strokeWidth = 2.0);
    } else if (opponentInfo.heroId == 'ranger' || opponentInfo.heroId == 'valeria') {
      final bowPaint = Paint()..color = const Color(0xFF6D4C41)..style = PaintingStyle.stroke..strokeWidth = 3;
      canvas.drawArc(const Rect.fromLTWH(-10, -22, 14, 28), -pi / 2, pi, false, bowPaint);
      canvas.drawLine(const Offset(-3, -22), const Offset(-3, 6), Paint()..color = const Color(0xFF00E676)..strokeWidth = 1.5);
    } else if (opponentInfo.heroId == 'tanker' || opponentInfo.heroId == 'garrick') {
      canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-10, -22, 18, 22), const Radius.circular(5)), Paint()..color = const Color(0xFF0D47A1));
      canvas.drawLine(const Offset(-1, -20), const Offset(-1, -2), Paint()..color = const Color(0xFFFFD54F)..strokeWidth = 2);
    } else if (opponentInfo.heroId == 'ninja') {
      canvas.drawLine(const Offset(-2, 6), const Offset(-2, 0), Paint()..color = const Color(0xFFD50000)..strokeWidth = 3.5);
      canvas.drawLine(const Offset(-2, 0), const Offset(6, -24), Paint()..color = const Color(0xFFE0E0E0)..strokeWidth = 2.5);
    } else {
      final handle = Paint()..color = const Color(0xFF3E2723)..strokeWidth = 3;
      canvas.drawLine(const Offset(0, 8), const Offset(0, -18), handle);
      final head = Paint()..color = const Color(0xFF311B92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(-8, -26, 16, 12), const Radius.circular(3)),
        head,
      );
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
