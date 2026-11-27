import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';

void main() {
  group('PvP Match Start, Movement & Map Synchronization', () {
    test('getMapFromSeed returns identical map for both players in the same roomId', () {
      final registry = GameAssetRegistry.instance;
      final selectedIds = <String>{};

      for (int i = 0; i < 20; i++) {
        final roomId = 'pvp_uidA_uidB_${1700000000000 + i * 137}';
        final mapForP1 = registry.getMapFromSeed(roomId);
        final mapForP2 = registry.getMapFromSeed(roomId);

        expect(mapForP1.id, mapForP2.id);
        expect(mapForP1.imageAsset, mapForP2.imageAsset);
        selectedIds.add(mapForP1.id);
      }

      // Different roomIds should still vary across available maps
      expect(selectedIds.length, greaterThan(1));
    });

    test('Two PvpArenaGame instances with synced room map share identical map & obstacles', () {
      const opponent = PvpOpponentInfo(
        name: 'Opponent',
        rankPoints: 1200,
        rankTier: 'Bạc',
        heroId: 'george',
        isBot: false,
      );
      const roomId = 'pvp_alpha_beta_1795000000001';
      final syncedMap = GameAssetRegistry.instance.getMapFromSeed(roomId);

      final p1Game = PvpArenaGame(
        opponentInfo: opponent,
        playerCurrentRp: 1200,
        isOnline: true,
        isPlayerOne: true,
        selectedMapConfig: syncedMap,
      );
      final p2Game = PvpArenaGame(
        opponentInfo: opponent,
        playerCurrentRp: 1200,
        isOnline: true,
        isPlayerOne: false,
        selectedMapConfig: syncedMap,
      );

      expect(p1Game.currentMapConfig.id, p2Game.currentMapConfig.id);
      expect(p1Game.arenaMap.pillarRects, p2Game.arenaMap.pillarRects);
    });

    test('Held movement during roundIntro applies immediately when fighting begins', () {
      const opponent = PvpOpponentInfo(
        name: 'TestBot',
        rankPoints: 1200,
        rankTier: 'Bạc',
        heroId: 'george',
      );
      final game = PvpArenaGame(
        opponentInfo: opponent,
        playerCurrentRp: 1200,
      );

      expect(game.matchState, PvpMatchState.roundIntro);
      expect(game.stateTimer, PvpArenaGame.roundIntroDuration);

      // Player holds Right (D / Joystick) while still in roundIntro
      game.setPlayerMoveDirection(Vector2(1, 0));
      expect(game.player.moveDirection, Vector2.zero());
      expect(game.bot.canAct?.call(), isFalse);

      // Advance past roundIntroDuration
      game.update(PvpArenaGame.roundIntroDuration + 0.05);

      expect(game.matchState, PvpMatchState.fighting);
      expect(game.fightStartBannerTimer, greaterThan(0));
      // Held movement must activate immediately on first frame of fighting!
      expect(game.player.moveDirection, Vector2(1, 0));
      expect(game.bot.canAct?.call(), isTrue);
    });
  });
}
