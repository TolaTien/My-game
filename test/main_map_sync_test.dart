import 'dart:convert';

import 'package:flame/collisions.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/registry/asset_registry.dart';

class _MapGame extends FlameGame with HasCollisionDetection {}

MapAssetConfig _generatedMap() => MapAssetConfig.fromJson({
  'id': 'generated_map',
  'stage': 10,
  'name': 'Generated map',
  'mode': 'all',
  'cols': 12,
  'rows': 9,
  'tileSize': 32,
  'playerSpawn': [2, 2],
  'bossSpawn': [10, 7],
  'monsterPortals': [
    [10, 2],
  ],
  'buffNodes': [
    [2, 7],
  ],
  'theme': 'forest',
  'obstacles': [
    [3, 3],
    [7, 2, 3, 5],
    ['bad', 2],
    [2, 2, 1],
    [2.5, 2],
    [-1, 5, 2, 2],
    [10, 1, 3, 2],
    [1, 1, 0, 2],
    [1, 7, 2, 1000000000],
    [11, 5],
    null,
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fallback hero balance matches production while JSON remains primary',
    () async {
      final registry = GameAssetRegistry.forTesting();
      final fallback = {for (final hero in registry.heroes) hero.id: hero};
      expect(fallback, hasLength(10));
      expect(registry.getHero('nova'), same(fallback['nova_blade']));
      expect(registry.getHero('shadow'), same(fallback['shadow_01']));
      expect(registry.getHero('ember'), same(fallback['ember_02']));
      expect(registry.skills, isEmpty);
      await registry.initialize();
      expect(registry.isInitialized, isTrue);
      expect(registry.skills, hasLength(30));
      for (final hero in registry.heroes) {
        final before = fallback[hero.id]!;
        expect(identical(before, hero), isFalse);
        expect(
          [
            before.baseStats.hp,
            before.baseStats.ki,
            before.baseStats.attack,
            before.baseStats.speed,
            before.growthPerLevel.hpPerLevel,
            before.growthPerLevel.kiPerLevel,
            before.growthPerLevel.attackPerLevel,
          ],
          [
            hero.baseStats.hp,
            hero.baseStats.ki,
            hero.baseStats.attack,
            hero.baseStats.speed,
            hero.growthPerLevel.hpPerLevel,
            hero.growthPerLevel.kiPerLevel,
            hero.growthPerLevel.attackPerLevel,
          ],
          reason: hero.id,
        );
        expect(registry.getSkillsForHero(hero.id), hasLength(3));
      }
    },
  );

  test('main map data exposes both new maps and their native cells', () async {
    final registry = GameAssetRegistry.forTesting();
    await registry.initialize();
    expect(registry.isInitialized, isTrue);
    expect(
      registry.availableMatchMaps.map((map) => map.id),
      unorderedEquals([
        'sunken_golden_sanctum',
        'map_bang',
        'map_dao_bang_gia',
        'map_rung_cay',
        'dien_tho_co_long',
        'hoa_nguc_dung_nham',
      ]),
    );
    expect(registry.getMapForStage(1).id, 'map_bang');
    expect(registry.getMapForStage(4).id, 'dien_tho_co_long');
    expect(registry.getMapForStage(5).id, 'hoa_nguc_dung_nham');

    final dragon = DungeonMapComponent(config: registry.getMapForStage(4));
    final lava = DungeonMapComponent(config: registry.getMapForStage(5));
    expect(dragon.mapConfig.obstacles, hasLength(6));
    expect(lava.mapConfig.theme, 'volcanic');
    expect(dragon.walkableGrid[14][11], isFalse);
    expect(lava.walkableGrid[14][11], isTrue);
    expect(lava.walkableGrid[8][6], isFalse);
    for (final dungeon in [dragon, lava]) {
      expect(
        (await rootBundle.load(dungeon.mapConfig.imageAsset)).lengthInBytes,
        greaterThan(0),
      );
      final spawn = dungeon.mapConfig.playerSpawn;
      for (final target in [
        dungeon.mapConfig.bossSpawn,
        ...dungeon.mapConfig.monsterPortals,
        ...dungeon.mapConfig.buffNodes,
      ]) {
        expect(dungeon.walkableGrid[target[0]][target[1]], isTrue);
        expect(
          AStarPathfinder.findPath(
            AStarPathfinder.gridToWorld(spawn[0], spawn[1]),
            AStarPathfinder.gridToWorld(target[0], target[1]),
            dungeon.walkableGrid,
          ),
          isNotEmpty,
        );
      }
    }
  });

  test(
    'map JSON round-trips both accepted shapes but discards invalid input',
    () {
      final config = _generatedMap();
      expect(config.obstacles, [
        [3, 3],
        [7, 2, 3, 5],
      ]);
      final decoded =
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      expect(MapAssetConfig.fromJson(decoded).toJson(), config.toJson());

      final grid = AStarPathfinder.buildDungeonWalkableGrid(
        width: 12,
        height: 9,
        mapId: config.id,
        obstacles: const [
          [3, 3],
          [7, 2, 3, 5],
          [1, 7, 2, 1000000000],
          [11, 5],
        ],
      );
      expect(grid, DungeonMapComponent(config: config).walkableGrid);
      expect(grid[10][3], isTrue);
      expect(grid[1][7], isTrue);
    },
  );

  test('legacy Sanctum has exactly five 2x2 pillars', () {
    final grid = DungeonMapComponent(
      config: GameAssetRegistry.defaultSanctumMap,
    ).walkableGrid;
    final blocked = <(int, int)>{};
    for (var x = 1; x < grid.length - 1; x++) {
      for (var y = 1; y < grid[x].length - 1; y++) {
        if (!grid[x][y]) blocked.add((x, y));
      }
    }
    expect(blocked, {
      for (final (col, row) in [(8, 6), (8, 16), (26, 6), (26, 16), (17, 10)])
        for (var dx = 0; dx < 2; dx++)
          for (var dy = 0; dy < 2; dy++) (col + dx, row + dy),
    });
  });

  testWidgets('mounted wall hitboxes match every cell of a nonstandard map', (
    tester,
  ) async {
    final map = DungeonMapComponent(config: _generatedMap());
    final game = _MapGame();
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() async {
      await game.toBeLoaded();
      await game.ready();
    });
    await game.world.add(map);
    await tester.runAsync(game.ready);
    game.pauseEngine();
    expect(map.isMounted, isTrue);
    expect((map.widthTiles, map.heightTiles), (12, 9));
    final colliders = <Rect>[];
    for (final wall in map.children.whereType<WallBlock>()) {
      final hitbox = wall.children.whereType<RectangleHitbox>().single;
      expect(hitbox.isMounted, isTrue);
      expect(hitbox.collisionType, CollisionType.passive);
      final origin = wall.position + hitbox.position;
      colliders.add(
        Rect.fromLTWH(origin.x, origin.y, hitbox.size.x, hitbox.size.y),
      );
    }
    expect(colliders, hasLength(40));
    for (var x = 0; x < map.widthTiles; x++) {
      for (var y = 0; y < map.heightTiles; y++) {
        final center = AStarPathfinder.gridToWorld(x, y);
        final hits = colliders.where(
          (rect) => rect.contains(Offset(center.x, center.y)),
        );
        expect(
          hits.length,
          map.walkableGrid[x][y] ? 0 : 1,
          reason: 'cell ($x, $y)',
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
