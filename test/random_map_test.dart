import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/components/dungeon_map.dart';
import 'package:my_game/game/components/pvp_arena_map.dart';
import 'package:my_game/game/gold_rush_game.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/registry/sprite_image_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Random Map System & Asset Registry', () {
    test('GameAssetRegistry contains all 3 maps (1 current + 2 new from assets/images/maps)', () {
      final registry = GameAssetRegistry.instance;
      final maps = registry.availableMatchMaps;

      expect(maps.length, 3);

      final mapIds = maps.map((m) => m.id).toSet();
      expect(mapIds.contains('sunken_golden_sanctum'), isTrue);
      expect(mapIds.contains('map_bang'), isTrue);
      expect(mapIds.contains('map_dao_bang_gia'), isTrue);

      final mapBang = registry.getMap('map_bang')!;
      expect(mapBang.name, 'Đấu Trường Băng Giá');
      expect(mapBang.imageAsset, 'assets/images/maps/map-bang.png');
      expect(mapBang.theme, 'ice_arena');

      final mapDaoBang = registry.getMap('map_dao_bang_gia')!;
      expect(mapDaoBang.name, 'Đảo Băng Tuyết');
      expect(mapDaoBang.imageAsset, 'assets/images/maps/map-dao-bang-gia.png');
      expect(mapDaoBang.theme, 'frost_island');

      final sanctum = registry.getMap('sunken_golden_sanctum')!;
      expect(sanctum.name, 'Phế Tích Thần Điện Hoàng Kim');
      expect(sanctum.theme, 'golden_sanctum');
    });

    test('getRandomMap picks randomly from the 3 available maps', () {
      final registry = GameAssetRegistry.instance;
      final pickedIds = <String>{};

      for (int i = 0; i < 50; i++) {
        final map = registry.getRandomMap();
        pickedIds.add(map.id);
        expect(
          map.id == 'sunken_golden_sanctum' ||
              map.id == 'map_bang' ||
              map.id == 'map_dao_bang_gia',
          isTrue,
        );
      }

      // With 50 trials across 3 maps, all 3 maps should have been selected at least once
      expect(pickedIds.contains('sunken_golden_sanctum'), isTrue);
      expect(pickedIds.contains('map_bang'), isTrue);
      expect(pickedIds.contains('map_dao_bang_gia'), isTrue);
    });

    test('SpriteImageCache registers map image paths for fast caching', () {
      expect(SpriteImageCache.mapImagePaths.containsKey('map_bang'), isTrue);
      expect(SpriteImageCache.mapImagePaths['map_bang'], 'assets/images/maps/map-bang.png');
      expect(SpriteImageCache.mapImagePaths.containsKey('map_dao_bang_gia'), isTrue);
      expect(SpriteImageCache.mapImagePaths['map_dao_bang_gia'], 'assets/images/maps/map-dao-bang-gia.png');
    });

    test('GoldRushGame initializes with random map and sets currentMapConfig', () {
      final game = GoldRushGame();
      expect(game.currentMapConfig, isNotNull);
      expect(
        game.currentMapConfig.id == 'sunken_golden_sanctum' ||
            game.currentMapConfig.id == 'map_bang' ||
            game.currentMapConfig.id == 'map_dao_bang_gia',
        isTrue,
      );
    });

    test('GoldRushGame accepts explicit map configuration', () {
      final mapBang = GameAssetRegistry.instance.getMap('map_bang')!;
      final game = GoldRushGame(selectedMapConfig: mapBang);
      expect(game.currentMapConfig.id, 'map_bang');
      expect(game.currentMapConfig.name, 'Đấu Trường Băng Giá');
    });

    test('DungeonMapComponent mounts and renders all 3 map themes cleanly', () async {
      final registry = GameAssetRegistry.instance;
      final configs = [
        registry.getMap('sunken_golden_sanctum')!,
        registry.getMap('map_bang')!,
        registry.getMap('map_dao_bang_gia')!,
      ];

      for (final cfg in configs) {
        final dungeonMap = DungeonMapComponent(config: cfg);
        await dungeonMap.onLoad();

        expect(dungeonMap.walkableGrid.length, DungeonMapComponent.mapWidthTiles);
        expect(dungeonMap.walkableGrid[0].length, DungeonMapComponent.mapHeightTiles);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        dungeonMap.render(canvas);

        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }
    });

    test('PvpArenaGame initializes with random map and PvpArenaMapComponent renders all 3 themes', () async {
      final registry = GameAssetRegistry.instance;
      final configs = [
        registry.getMap('sunken_golden_sanctum')!,
        registry.getMap('map_bang')!,
        registry.getMap('map_dao_bang_gia')!,
      ];

      for (final cfg in configs) {
        final arenaMap = PvpArenaMapComponent(
          gameMode: PvpGameMode.solo1v1,
          mapConfig: cfg,
        );
        await arenaMap.onLoad();

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        arenaMap.render(canvas);

        final picture = recorder.endRecording();
        expect(picture, isNotNull);
      }

      final pvpGame = PvpArenaGame(
        opponentInfo: PvpOpponentInfo.generateBot(1200),
        playerCurrentRp: 1200,
      );
      expect(pvpGame.currentMapConfig, isNotNull);
      expect(
        pvpGame.currentMapConfig.id == 'sunken_golden_sanctum' ||
            pvpGame.currentMapConfig.id == 'map_bang' ||
            pvpGame.currentMapConfig.id == 'map_dao_bang_gia',
        isTrue,
      );
    });

    test('GoldRushGame advanceToNextFloor switches to a new random map without repeating', () async {
      final initialMap = GameAssetRegistry.instance.getMap('sunken_golden_sanctum')!;
      final game = GoldRushGame(selectedMapConfig: initialMap);
      await game.onLoad();

      expect(game.currentMapConfig.id, 'sunken_golden_sanctum');
      final firstMapComponent = game.dungeonMap;

      bool mapChangedNotified = false;
      game.onMapChanged = () {
        mapChangedNotified = true;
      };

      game.advanceToNextFloor();

      expect(mapChangedNotified, isTrue);
      expect(game.currentMapConfig.id, isNot('sunken_golden_sanctum'));
      expect(game.dungeonMap, isNot(firstMapComponent));
      expect(
        game.currentMapConfig.id == 'map_bang' ||
            game.currentMapConfig.id == 'map_dao_bang_gia',
        isTrue,
      );
    });
  });
}
