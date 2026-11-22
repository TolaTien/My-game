import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/big_war_game.dart';
import 'package:my_game/game/components/boss_enemy.dart';
import 'package:my_game/game/components/enemy_skeleton.dart';
import 'package:my_game/game/components/enemy_zombie.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';

void main() {
  test('Boss count and extra monster counts scale progressively across floors', () {
    expect(BigWarGame.bossCountForFloor(1), 1);
    expect(BigWarGame.bossCountForFloor(2), 1);
    expect(BigWarGame.bossCountForFloor(3), 2);
    expect(BigWarGame.bossCountForFloor(5), 2);
    expect(BigWarGame.bossCountForFloor(6), 3);
    expect(BigWarGame.bossCountForFloor(9), 4);
    expect(BigWarGame.bossCountForFloor(15), 4);

    expect(BigWarGame.extraZombiesForFloor(1), 0);
    expect(BigWarGame.extraZombiesForFloor(4), 3);
    expect(BigWarGame.extraZombiesForFloor(10), 6);

    expect(BigWarGame.extraSkeletonsForFloor(1), 0);
    expect(BigWarGame.extraSkeletonsForFloor(3), 1);
    expect(BigWarGame.extraSkeletonsForFloor(9), 4);
  });

  test('Boss HP, damage, speed, cooldowns, and fireball count scale with floor', () {
    final player = PlayerComponent(position: Vector2.zero());
    final f1 = BossEnemy(position: Vector2.zero(), player: player)
      ..applyFloorDifficulty(1);
    final f3 = BossEnemy(position: Vector2.zero(), player: player)
      ..applyFloorDifficulty(3);
    final f5 = BossEnemy(position: Vector2.zero(), player: player)
      ..applyFloorDifficulty(5);

    expect(f3.maxHp, greaterThan(f1.maxHp));
    expect(f5.maxHp, greaterThan(f3.maxHp));

    expect(f3.meleeDamage, greaterThan(f1.meleeDamage));
    expect(f5.meleeDamage, greaterThan(f3.meleeDamage));
    expect(f3.groundSlamDamage, greaterThan(f1.groundSlamDamage));
    expect(f5.flameBurstDamage, greaterThan(f1.flameBurstDamage));

    expect(f3.phase1Speed, greaterThan(f1.phase1Speed));
    expect(f3.meleeBaseCooldown, lessThan(f1.meleeBaseCooldown));
    expect(f1.flameBurstCount, 8);
    expect(f3.flameBurstCount, 10);
    expect(f5.flameBurstCount, 12);
  });

  test('Zombie and Skeleton HP, damage, speed, and fire rate scale with floor', () {
    final game = BigWarGame(
      playerProfile: const PlayerProfile(),
      selectedMapConfig: GameAssetRegistry.defaultSanctumMap,
    );
    final z1 = ZombieEnemy(position: Vector2.zero(), player: game.player);
    final z5 = ZombieEnemy(position: Vector2.zero(), player: game.player);
    game.scaleZombieForFloor(z1, 1);
    game.scaleZombieForFloor(z5, 5);
    expect(z5.maxHp, greaterThan(z1.maxHp));
    expect(z5.damage, greaterThan(z1.damage));
    expect(z5.speed, greaterThan(z1.speed));

    final s1 = SkeletonEnemy(position: Vector2.zero(), player: game.player);
    final s5 = SkeletonEnemy(position: Vector2.zero(), player: game.player);
    game.scaleSkeletonForFloor(s1, 1);
    game.scaleSkeletonForFloor(s5, 5);
    expect(s5.maxHp, greaterThan(s1.maxHp));
    expect(s5.arrowDamage, greaterThan(s1.arrowDamage));
    expect(s5.arrowSpeed, greaterThan(s1.arrowSpeed));
    expect(s5.shootInterval, lessThan(s1.shootInterval));
  });

  test('Defeating all bosses clears leftover minions and triggers victory reliably', () {
    var victoryCalls = 0;
    final game = BigWarGame(
      playerProfile: const PlayerProfile(),
      selectedMapConfig: GameAssetRegistry.defaultSanctumMap,
    )..onVictory = () => victoryCalls++;

    // Simulate floor with 2 bosses + 1 stray zombie stuck far away
    final b1 = BossEnemy(position: Vector2(500, 300), player: game.player);
    final b2 = BossEnemy(position: Vector2(600, 300), player: game.player);
    final strayZombie = ZombieEnemy(position: Vector2(950, 700), player: game.player);
    game.bosses.addAll([b1, b2]);
    game.enemies.add(strayZombie);

    // Only 1 boss defeated -> victory must NOT trigger yet
    b1.takeDamage(9999);
    game.update(1.5);
    expect(victoryCalls, 0);
    expect(game.isVictoryTriggered, isFalse);

    // Both bosses defeated -> clears stray zombie and triggers victory after 1.2s grace
    b2.takeDamage(9999);
    game.update(0.6);
    expect(game.enemies, isEmpty);
    expect(victoryCalls, 0);

    game.update(0.7);
    expect(game.isVictoryTriggered, isTrue);
    expect(victoryCalls, 1);

    // Calling triggerVictory again (e.g. from portal) does not double-fire
    game.triggerVictory();
    expect(victoryCalls, 1);
  });
}
