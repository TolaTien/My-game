import 'dart:math' as math;

import 'package:flame/components.dart';

mixin CombatStatus on PositionComponent {
  double stunRemaining = 0, slowRemaining = 0, slowFactor = 1;
  double barrierRemaining = 0, barrierHp = 0;
  double guardRemaining = 0, guardReduction = 0;
  double hasteRemaining = 0, hasteFactor = 1;
  bool get isStunned => stunRemaining > 0;
  double get combatMoveFactor =>
      (slowRemaining > 0 ? slowFactor : 1) *
      (hasteRemaining > 0 ? hasteFactor : 1);

  void tickCombatStatus(double dt) {
    stunRemaining = math.max(0, stunRemaining - dt);
    slowRemaining = math.max(0, slowRemaining - dt);
    guardRemaining = math.max(0, guardRemaining - dt);
    hasteRemaining = math.max(0, hasteRemaining - dt);
    barrierRemaining = math.max(0, barrierRemaining - dt);
    if (barrierRemaining == 0) barrierHp = 0;
  }

  double absorbCombatDamage(double damage) {
    var result = damage * (guardRemaining > 0 ? 1 - guardReduction : 1);
    final absorbed = math.min(result, barrierHp);
    barrierHp -= absorbed;
    return math.max(0, result - absorbed);
  }

  void clearCombatStatus() {
    stunRemaining = slowRemaining = barrierRemaining = barrierHp = 0;
    guardRemaining = hasteRemaining = 0;
    slowFactor = hasteFactor = 1;
  }
}
