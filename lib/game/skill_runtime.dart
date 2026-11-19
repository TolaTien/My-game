import 'dart:math' as math;

import '../registry/asset_registry.dart';

/// One immutable configuration and one authoritative clock per skill slot.
class SkillRuntime {
  final SkillAssetConfig config;
  final bool enabled;
  double cooldownRemaining = 0;
  double effectRemaining = 0;

  SkillRuntime(this.config, {this.enabled = true});

  bool canCast(double ki) =>
      enabled && cooldownRemaining <= 0 && ki >= config.kiCost;

  void update(double dt) {
    cooldownRemaining = math.max(0, cooldownRemaining - dt);
    effectRemaining = math.max(0, effectRemaining - dt);
  }

  void reset() {
    cooldownRemaining = 0;
    effectRemaining = 0;
  }
}
