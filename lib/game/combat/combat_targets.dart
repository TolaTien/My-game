import 'package:flame/components.dart';

import '../components/player.dart';
import '../components/enemy_zombie.dart';
import '../components/enemy_skeleton.dart';
import '../components/boss_enemy.dart';
import '../components/pvp_bot_player.dart';
import '../components/dungeon_map.dart';
import 'hero_combat.dart';

CombatTarget combatTarget(
  PositionComponent body, {
  void Function(double)? onHit,
}) {
  late double Function() hp;
  late double maxHp;
  late void Function(double) damage;
  if (body is PlayerComponent) {
    hp = () => body.currentHp;
    maxHp = body.maxHp;
    damage = body.takeDamage;
  } else if (body is ZombieEnemy) {
    hp = () => body.currentHp;
    maxHp = body.maxHp;
    damage = body.takeDamage;
  } else if (body is SkeletonEnemy) {
    hp = () => body.currentHp;
    maxHp = body.maxHp;
    damage = body.takeDamage;
  } else if (body is BossEnemy) {
    hp = () => body.currentHp;
    maxHp = body.maxHp;
    damage = body.takeDamage;
  } else if (body is PvpBotPlayerComponent) {
    hp = () => body.currentHp;
    maxHp = body.maxHp;
    damage = body.takeDamage;
  } else {
    throw ArgumentError('Unsupported combat body');
  }
  return CombatTarget(body, hp, maxHp, (amount) {
    damage(amount);
    onHit?.call(amount);
  });
}

bool pointInMap(Vector2 point, Component map, double width, double height) {
  if (point.x < 0 || point.y < 0 || point.x >= width || point.y >= height) {
    return false;
  }
  for (final wall in map.children.whereType<WallBlock>()) {
    if (point.x >= wall.position.x &&
        point.x <= wall.position.x + wall.size.x &&
        point.y >= wall.position.y &&
        point.y <= wall.position.y + wall.size.y) {
      return false;
    }
  }
  return true;
}
