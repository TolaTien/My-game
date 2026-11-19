import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/astar_pathfinder.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/pvp_arena_map.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/models/friend_party_models.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/screens/pvp_arena_screen.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestArenaGame extends FlameGame with HasCollisionDetection {}

void main() {
  group('PvP Bot Pathfinding & Obstacle Avoidance', () {
    test('buildPvpArenaWalkableGrid marks walls and 4 pillars as blocked', () {
      final map = PvpArenaMapComponent();
      final grid = map.walkableGrid;

      expect(grid.length, PvpArenaMapComponent.mapWidthTiles);
      expect(grid[0].length, PvpArenaMapComponent.mapHeightTiles);

      // Perimeter blocked
      expect(grid[0][10], isFalse);
      expect(grid[29][10], isFalse);
      expect(grid[15][0], isFalse);
      expect(grid[15][19], isFalse);

      // Spawn points walkable
      final (blueCol, blueRow) = AStarPathfinder.worldToGrid(Vector2(200, 320));
      final (redCol, redRow) = AStarPathfinder.worldToGrid(Vector2(760, 320));
      expect(grid[blueCol][blueRow], isTrue);
      expect(grid[redCol][redRow], isTrue);

      // Pillar centers blocked
      for (final pillar in PvpArenaMapComponent.defaultPillarRects) {
        final (col, row) = AStarPathfinder.worldToGrid(
          Vector2(pillar.center.dx, pillar.center.dy),
        );
        expect(grid[col][row], isFalse);
      }
    });

    test('AStarPathfinder routes around pillars between (790, 205) and (170, 205)', () {
      final map = PvpArenaMapComponent();
      final start = Vector2(790, 205);
      final target = Vector2(170, 205);

      expect(
        AStarPathfinder.hasClearCorridor(
          start,
          target,
          map.walkableGrid,
          obstacleRects: map.pillarRects,
          clearanceRadius: 12.5,
        ),
        isFalse,
      );

      final path = AStarPathfinder.findPath(
        start,
        target,
        map.walkableGrid,
        allowDirectLineOfSight: false,
      );

      expect(path, isNotEmpty);
      // Must route around the pillar row instead of staying on y = 205
      final hasDetour = path.any((wp) => (wp.y - 205).abs() > 24.0);
      expect(hasDetour, isTrue);

      for (final wp in path) {
        for (final pillar in map.pillarRects) {
          expect(pillar.contains(Offset(wp.x, wp.y)), isFalse);
        }
      }
    });

    test('Bot waits during roundIntro, navigates around pillar, and attacks enemy', () async {
      final game = _TestArenaGame();
      game.onGameResize(Vector2(960, 640));
      await game.onLoad();

      final map = PvpArenaMapComponent();
      final player = PlayerComponent(position: Vector2(580, 200), heroId: 'george');
      var fighting = false;

      final bot = PvpBotPlayerComponent(
        position: Vector2(760, 200),
        opponentInfo: const PvpOpponentInfo(
          name: 'TestBot',
          rankPoints: 1850,
          rankTier: 'Kim Cương',
          heroId: 'george',
          difficulty: BotDifficulty.diamondChallenger,
        ),
        targetPlayer: player,
        enableAi: true,
        canAct: () => fighting,
        getObstacleRects: () => map.obstacleRects,
        getInteriorObstacleRects: () => map.pillarRects,
        getWalkableGrid: () => map.walkableGrid,
      );

      await game.world.addAll([player, bot]);
      game.update(0.0);

      // 1. During roundIntro (fighting == false), bot must not move or deal damage
      for (int i = 0; i < 60; i++) {
        game.update(1 / 60);
      }
      expect(bot.position.distanceTo(Vector2(760, 200)), lessThan(0.01));
      expect(player.currentHp, player.maxHp);

      // 2. Start fighting: pillar at (656..704, 176..224) is directly in between!
      fighting = true;
      for (int i = 0; i < 240; i++) {
        game.update(1 / 60);
        final botHitbox = Rect.fromLTRB(
          bot.position.x - 12,
          bot.position.y - 10,
          bot.position.x + 12,
          bot.position.y + 18,
        );
        for (final obs in map.obstacleRects) {
          expect(botHitbox.overlaps(obs), isFalse,
              reason: 'Bot overlapped obstacle $obs at ${bot.position}');
        }
      }

      // Bot should have navigated around the pillar to reach and damage the player
      expect(bot.position.x, lessThan(656));
      expect(player.currentHp, lessThan(player.maxHp));
    });

    test('Bot switches to next alive enemy when current target is defeated', () async {
      final game = _TestArenaGame();
      game.onGameResize(Vector2(960, 640));
      await game.onLoad();

      final map = PvpArenaMapComponent();
      final player = PlayerComponent(position: Vector2(200, 320), heroId: 'george');
      player.currentHp = 0; // Player is already K.O.

      final allyBot = PvpBotPlayerComponent(
        position: Vector2(220, 440),
        opponentInfo: const PvpOpponentInfo(
          name: 'AllyAlive',
          rankPoints: 1200,
          rankTier: 'Bạc',
          heroId: 'tanker',
          isAlly: true,
        ),
        targetPlayer: player,
        enableAi: false,
      );

      final enemyBot = PvpBotPlayerComponent(
        position: Vector2(460, 440),
        opponentInfo: const PvpOpponentInfo(
          name: 'HunterBot',
          rankPoints: 1500,
          rankTier: 'Vàng',
          heroId: 'ninja',
          difficulty: BotDifficulty.goldPlatinum,
        ),
        targetPlayer: player,
        enableAi: true,
        getHostileTargets: () => <PositionComponent>[player, allyBot],
        canAct: () => true,
        getObstacleRects: () => map.obstacleRects,
        getInteriorObstacleRects: () => map.pillarRects,
        getWalkableGrid: () => map.walkableGrid,
      );

      expect(enemyBot.primaryTarget, equals(allyBot));

      await game.world.addAll([player, allyBot, enemyBot]);
      game.update(0.0);

      for (int i = 0; i < 180; i++) {
        game.update(1 / 60);
      }

      expect(enemyBot.position.distanceTo(allyBot.position), lessThan(90));
      expect(allyBot.currentHp, lessThan(allyBot.maxHp));
    });
  });

  group('Lobby & Ranked Matchmaking UI', () {
    testWidgets('Lobby left sidebar renames "TỔ ĐỘI" button to "BẠN BÈ"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1763, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(FriendPartyService.instance.stopPolling);

      await tester.pumpWidget(
        const MaterialApp(
          home: LobbyScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('BẠN BÈ'), findsAtLeastNWidgets(1));
      expect(find.text('TỔ ĐỘI'), findsNothing);

      FriendPartyService.instance.stopPolling();
    });

    testWidgets('PvpArenaScreen auto-matches with Bot when offline/no players', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: PvpArenaScreen(initialMode: PvpGameMode.solo1v1),
        ),
      );

      // Initially matchmaking radar is visible
      expect(find.text('HỦY TÌM'), findsOneWidget);

      // Advance past the 1.8s offline bot fallback delay
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump();

      // Matchmaking view is gone and arena HUD is active
      expect(find.text('HỦY TÌM'), findsNothing);
      expect(find.textContaining('HIỆP 1 / 3'), findsOneWidget);
    });

    test('Deterministic seed generates identical enemy rosters for Leader and Guest', () {
      final rosterA = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1450,
        mode: PvpGameMode.duo2v2,
        playerHeroId: 'george',
        seed: 424242,
      );
      final rosterB = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1450,
        mode: PvpGameMode.duo2v2,
        playerHeroId: 'george',
        seed: 424242,
      );

      expect(rosterA.enemies.length, rosterB.enemies.length);
      for (int i = 0; i < rosterA.enemies.length; i++) {
        expect(rosterA.enemies[i].name, rosterB.enemies[i].name);
        expect(rosterA.enemies[i].heroId, rosterB.enemies[i].heroId);
      }
    });

    testWidgets(
      'Party Guest sees "SẴN SÀNG" at Find Match button and joins match when Leader starts',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1763, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: LobbyScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final myCode = FriendPartyService.instance.effectivePlayerCode.toUpperCase();

        // Simulate Guest joining Leader's 2v2 party room
        final partyAsGuest = PartyRoomState(
          partyCode: 'TEAM777',
          leaderCode: 'LEADER99',
          leaderName: 'Chủ Phòng Test',
          mode: PvpGameMode.duo2v2,
          members: [
            FriendInfo(
              code: myCode,
              name: 'Khách Test',
              rankPoints: 1200,
              rankTier: 'Bạc',
              selectedHeroId: 'george',
              isOnline: true,
            ),
          ],
          readyMemberCodes: [myCode],
        );
        FriendPartyService.instance.partyNotifier.value = partyAsGuest;
        await tester.pump();

        // Guest sees "SẴN SÀNG" instead of "TÌM TRẬN RANK"
        expect(find.text('SẴN SÀNG'), findsAtLeastNWidgets(1));
        expect(find.text('TÌM TRẬN RANK'), findsNothing);
        expect(find.text('CHỜ CHỦ PHÒNG TÌM TRẬN'), findsOneWidget);

        // Tapping the button toggles ready state and does NOT start solo matchmaking
        await tester.tap(find.byKey(const Key('lobby_main_action_button')));
        await tester.pump();
        expect(find.text('CHƯA SẴN SÀNG'), findsAtLeastNWidgets(1));
        expect(find.text('HỦY TÌM'), findsNothing);

        // Tap again to return to SẴN SÀNG
        await tester.tap(find.byKey(const Key('lobby_main_action_button')));
        await tester.pump();
        expect(find.text('SẴN SÀNG'), findsAtLeastNWidgets(1));

        // Now Leader starts matchmaking -> Guest automatically enters PvpArenaScreen!
        FriendPartyService.instance.partyNotifier.value = partyAsGuest.copyWith(
          readyMemberCodes: [myCode],
          matchStatus: 'searching',
          activeMatchRoomId: 'party_TEAM777_1001',
          activeMapId: 'sunken_golden_sanctum',
          matchSeed: 98765,
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        // Guest is now in PvpArenaScreen waiting for Leader to enter match
        expect(find.text('RỜI PHÒNG'), findsOneWidget);
        expect(find.text('GHÉP NGAY (AI BOT)'), findsNothing);

        // Leader triggers in_match -> Guest enters the SAME arena match!
        FriendPartyService.instance.partyNotifier.value =
            FriendPartyService.instance.partyNotifier.value!.copyWith(
          matchStatus: 'in_match',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('RỜI PHÒNG'), findsNothing);
        expect(find.textContaining('HIỆP 1 / 3'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        FriendPartyService.instance.partyNotifier.value = null;
        FriendPartyService.instance.stopPolling();
      },
    );
  });
}
