import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/core/pve_balance.dart';
import 'package:my_game/core/stat_growth_formula.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/gameplay_balance.dart' as report;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await GameAssetRegistry.instance.initialize(bundle: rootBundle);
    expect(GameAssetRegistry.instance.isInitialized, isTrue);
    expect(GameAssetRegistry.instance.heroes, hasLength(10));
    expect(GameAssetRegistry.instance.skills, hasLength(30));
  });

  test('spawn formulas retain original floor boundaries', () {
    // Explicit historical values catch an accidental rebase of floor-one boss
    // HP or use of the boss scale for ordinary enemies.
    const rows = [
      [1, 1.0, 60.0, 10.0, 45.0, 600.0, 50],
      [2, 1.2, 72.0, 12.0, 54.0, 625.0, 100],
      [5, 1.8, 108.0, 18.0, 81.0, 1000.0, 250],
      [10, 2.8, 168.0, 28.0, 126.0, 1625.0, 500],
    ];
    for (final row in rows) {
      final floor = row[0].toInt();
      expect(PveBalance.enemyScale(floor), closeTo(row[1], 1e-9));
      expect(PveBalance.zombieMaxHp(floor), closeTo(row[2], 1e-9));
      expect(PveBalance.zombieDamage(floor), closeTo(row[3], 1e-9));
      expect(PveBalance.skeletonMaxHp(floor), closeTo(row[4], 1e-9));
      expect(PveBalance.bossMaxHp(floor), closeTo(row[5], 1e-9));
      expect(PveBalance.floorCompletionGold(floor), row[6]);
    }
  });

  test('every shared formula rejects a floor below one', () {
    final formulas = <num Function(int)>[
      PveBalance.enemyScale,
      PveBalance.zombieMaxHp,
      PveBalance.zombieDamage,
      PveBalance.skeletonMaxHp,
      PveBalance.bossMaxHp,
      PveBalance.floorCompletionGold,
    ];
    for (final formula in formulas) {
      for (final floor in [0, -1, -100]) {
        expect(() => formula(floor), throwsRangeError);
      }
    }
  });

  for (final floor in [1, 5, 10]) {
    testWidgets('production floor $floor spawns use shared balance values', (
      tester,
    ) async {
      final previousAudio = AudioService.instance;
      AudioService.setInstance(MockAudioService());
      addTearDown(() => AudioService.setInstance(previousAudio));
      final game = GoldRushGame(playerProfile: const PlayerProfile())
        ..currentFloor = floor;
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() async {
        await game.toBeLoaded();
        await game.ready();
      });
      await tester.pump();
      game.pauseEngine();
      expect(game.player.isMounted, isTrue);
      expect(game.enemies, hasLength(5));
      expect(game.skeletons, hasLength(3));
      for (final zombie in game.enemies) {
        expect(zombie.isMounted, isTrue);
        expect(zombie.maxHp, PveBalance.zombieMaxHp(floor));
        expect(zombie.currentHp, zombie.maxHp);
        expect(zombie.damage, PveBalance.zombieDamage(floor));
      }
      for (final skeleton in game.skeletons) {
        expect(skeleton.isMounted, isTrue);
        expect(skeleton.maxHp, PveBalance.skeletonMaxHp(floor));
        expect(skeleton.currentHp, skeleton.maxHp);
      }
      expect(game.boss!.isMounted, isTrue);
      expect(game.boss!.maxHp, PveBalance.bossMaxHp(floor));
      expect(game.boss!.currentHp, game.boss!.maxHp);

      final gold = PlayerStorage.currentProfile.gold;
      final coins = game.player.coinsCollected;
      game.advanceToNextFloor();
      await tester.runAsync(game.ready);
      final destination = floor + 1;
      expect(game.currentFloor, destination);
      expect(
        game.player.coinsCollected - coins,
        PveBalance.floorCompletionGold(destination),
      );
      expect(
        PlayerStorage.currentProfile.gold - gold,
        PveBalance.floorCompletionGold(destination),
      );
      expect(game.enemies.first.maxHp, PveBalance.zombieMaxHp(destination));
      expect(game.enemies.first.damage, PveBalance.zombieDamage(destination));
      expect(game.skeletons.first.maxHp, PveBalance.skeletonMaxHp(destination));
      expect(game.boss!.maxHp, PveBalance.bossMaxHp(destination));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  test(
    'report uses actual initial and mastered player stats for all heroes',
    () {
      for (final hero in GameAssetRegistry.instance.heroes) {
        for (final level in [1, 10, 50, 100]) {
          final scaled = StatGrowthFormula.computeStatsForLevel(
            heroId: hero.id,
            level: level,
          );
          final player = PlayerComponent(
            position: Vector2.zero(),
            heroId: hero.id,
            userHeroLevel: level,
          );
          expect(player.maxHp, scaled.maxHp, reason: '${hero.id} level $level');
          expect(player.maxKi, scaled.maxKi, reason: '${hero.id} level $level');
          expect(player.effectiveDamage, scaled.attackDamage, reason: '${hero.id} level $level');
          expect(player.effectiveSpeed, scaled.moveSpeed, reason: '${hero.id} level $level');
        }
      }
      final markdown = report.buildGameplayBalanceReport();
      expect(
        markdown,
        contains(
           '| george | 1 | 1 | 340 | 100 | 25 | '
           '3 / 2 / 24 | 34 | 34 |',
        ),
      );
      expect(
        markdown,
        contains(
           '| george | 1 | 10 | 340 | 100 | 25 | '
           '7 / 6 / 65 | 12 | 13 |',
        ),
      );
      for (final hero in GameAssetRegistry.instance.heroes) {
        expect(markdown, contains('| ${hero.id} | 1 | 5 |'));
        expect(markdown, contains('| ${hero.id} | 100 | 10 |'));
      }
      expect(markdown, contains('not a pacing target or autoplay result'));
    },
  );
}
