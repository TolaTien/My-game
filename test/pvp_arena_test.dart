import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/ai/pvp_bot_ai.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/components/player_skill_effect.dart';
import 'package:my_game/game/components/pvp_bot_player.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/audio_service.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameAssetRegistry.instance.initialize();
  });

  group('Group 1: Bot Generator & Polish', () {
    test('Generates Vietnamese gamer tag from authentic pool', () {
      for (int i = 0; i < 20; i++) {
        final bot = PvpOpponentInfo.generateBot(1000);
        expect(PvpOpponentInfo.gamerTags, contains(bot.name));
        expect(bot.isBot, isTrue);
      }
    });

    test('Generates bot RP within +/- 150 bracket of player RP', () {
      const playerRp = 1500;
      for (int i = 0; i < 50; i++) {
        final bot = PvpOpponentInfo.generateBot(playerRp);
        expect(bot.rankPoints, greaterThanOrEqualTo(playerRp - 150));
        expect(bot.rankPoints, lessThanOrEqualTo(playerRp + 150));
      }
    });

    test('Bot RP never falls below 0 when player RP is low', () {
      const lowRp = 50;
      for (int i = 0; i < 50; i++) {
        final bot = PvpOpponentInfo.generateBot(lowRp);
        expect(bot.rankPoints, greaterThanOrEqualTo(0));
      }
    });

    test('Bot hero selection is valid roster member', () {
      const validHeroes = ['george', 'ranger', 'tanker', 'ninja'];
      for (int i = 0; i < 30; i++) {
        final bot = PvpOpponentInfo.generateBot(1200, playerHeroId: 'ranger');
        expect(validHeroes, contains(bot.heroId));
      }
    });

    test('Bot difficulty scales accurately with player rank rating', () {
      final bronzeBot = PvpOpponentInfo.generateBot(1100);
      expect(bronzeBot.difficulty, equals(BotDifficulty.bronzeSilver));

      final goldBot = PvpOpponentInfo.generateBot(1600);
      expect(goldBot.difficulty, equals(BotDifficulty.goldPlatinum));

      final challengerBot = PvpOpponentInfo.generateBot(2100);
      expect(challengerBot.difficulty, equals(BotDifficulty.diamondChallenger));
    });
  });

  group('Group 2: Elo Scoring, Sweep Bonus & Bronze Mitigation', () {
    test('Standard 1v1 win awards +30 RP and 200 Gold', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1300,
        playerRoundsWon: 2,
        opponentRoundsWon: 1,
        matchDuration: const Duration(seconds: 120),
      );

      expect(result.isWinner, isTrue);
      expect(result.rpDelta, equals(30));
      expect(result.newRankPoints, equals(1330));
      expect(result.goldReward, equals(200));
      expect(result.isPromotion, isFalse);
    });

    test('2-0 1v1 sweep awards +35 RP (30 + 5) and 200 Gold', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1300,
        playerRoundsWon: 2,
        opponentRoundsWon: 0,
        matchDuration: const Duration(seconds: 90),
      );

      expect(result.isWinner, isTrue);
      expect(result.rpDelta, equals(35));
      expect(result.newRankPoints, equals(1335));
      expect(result.goldReward, equals(200));
    });

    test('Silver+ defeat deducts -20 RP and 0 Gold', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1500, // Gold tier
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 80),
      );

      expect(result.isWinner, isFalse);
      expect(result.rpDelta, equals(-20));
      expect(result.newRankPoints, equals(1480));
      expect(result.goldReward, equals(0));
    });

    test('Bronze defeat (RP < 1200) mitigated to -5 RP max', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1050, // Bronze
        playerRoundsWon: 1,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 150),
      );

      expect(result.isWinner, isFalse);
      expect(result.rpDelta, equals(-5)); // Mitigated from -20 to -5
      expect(result.newRankPoints, equals(1045));
      expect(result.goldReward, equals(0));
    });

    test('Floor rule guarantees RP never falls below 0', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 3,
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 60),
      );

      expect(result.newRankPoints, equals(0));
      expect(result.newRankPoints, greaterThanOrEqualTo(0));
    });

    test('Crossing tier threshold triggers isPromotion flag', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1190, // Bronze
        playerRoundsWon: 2,
        opponentRoundsWon: 1,
        matchDuration: const Duration(seconds: 110),
      );

      expect(result.newRankPoints, equals(1220)); // Silver (>= 1200)
      expect(result.oldRankTier, equals('Đồng'));
      expect(result.newRankTier, equals('Bạc'));
      expect(result.isPromotion, isTrue);
    });

    test('Losing does not trigger isPromotion even if tier changes', () {
      final result = PvpEloCalculator.calculateResult(
        playerCurrentRp: 1205, // Silver
        playerRoundsWon: 0,
        opponentRoundsWon: 2,
        matchDuration: const Duration(seconds: 70),
      );

      expect(result.newRankPoints, equals(1185)); // Bronze
      expect(result.isWinner, isFalse);
      expect(result.isPromotion, isFalse);
    });
  });

  group('Group 3: Match State Machine & Bo3 Logic', () {
    test(
      'Initial state is roundIntro and transitions to fighting after 1.5s',
      () {
        final opponent = PvpOpponentInfo.generateBot(1300);
        final game = PvpArenaGame(
          opponentInfo: opponent,
          playerCurrentRp: 1300,
        );

        expect(game.matchState, equals(PvpMatchState.roundIntro));
        expect(game.currentRound, equals(1));
        expect(game.stateTimer, equals(1.5));

        game.update(1.6);
        expect(game.matchState, equals(PvpMatchState.fighting));
        expect(game.roundTimeRemaining, equals(90.0));
      },
    );

    test('2-0 match completes in 2 rounds with winner declared', () {
      final opponent = PvpOpponentInfo.generateBot(1300);
      final game = PvpArenaGame(opponentInfo: opponent, playerCurrentRp: 1300);

      // Start round 1
      game.player = PlayerComponent(position: Vector2(200, 320));
      game.bot = PvpBotPlayerComponent(
        position: Vector2(760, 320),
        opponentInfo: opponent,
        targetPlayer: game.player,
      );

      // Round 1 Intro -> Fighting
      game.update(3.0);
      expect(game.matchState, equals(PvpMatchState.fighting));

      // Player K.O. Bot in round 1
      game.bot.currentHp = 0;
      game.update(0.1);
      expect(game.matchState, equals(PvpMatchState.roundEnd));
      expect(game.playerWins, equals(1));
      expect(game.opponentWins, equals(0));

      // Round 1 End -> Round 2 Intro (intermission 2.5s)
      game.update(2.5);
      expect(game.matchState, equals(PvpMatchState.roundIntro));
      expect(game.currentRound, equals(2));

      // Round 2 Intro -> Fighting
      game.update(3.0);
      expect(game.matchState, equals(PvpMatchState.fighting));

      // Player K.O. Bot in round 2
      game.bot.currentHp = 0;
      game.update(0.1);
      expect(game.matchState, equals(PvpMatchState.roundEnd));
      expect(game.playerWins, equals(2));

      // Round 2 End -> Match Finished
      PvpMatchResult? finalResult;
      game.onMatchFinished = (res) => finalResult = res;

      game.update(2.5);
      expect(game.matchState, equals(PvpMatchState.matchFinished));
      expect(finalResult, isNotNull);
      expect(finalResult!.isWinner, isTrue);
      expect(finalResult!.playerRoundsWon, equals(2));
      expect(finalResult!.opponentRoundsWon, equals(0));
      expect(finalResult!.rpDelta, equals(35)); // Clean sweep bonus
    });

    test('2-1 match completes in 3 rounds with winner declared', () {
      final opponent = PvpOpponentInfo.generateBot(1300);
      final game = PvpArenaGame(opponentInfo: opponent, playerCurrentRp: 1300);

      game.player = PlayerComponent(position: Vector2(200, 320));
      game.bot = PvpBotPlayerComponent(
        position: Vector2(760, 320),
        opponentInfo: opponent,
        targetPlayer: game.player,
      );

      // Round 1: Player wins
      game.update(3.0);
      game.bot.currentHp = 0;
      game.update(0.1);
      expect(game.playerWins, equals(1));
      game.update(2.5);

      // Round 2: Bot wins
      game.update(3.0);
      game.player.currentHp = 0;
      game.update(0.1);
      expect(game.opponentWins, equals(1));
      game.update(2.5);

      // Round 3: Player wins
      game.update(3.0);
      expect(game.currentRound, equals(3));
      game.bot.currentHp = 0;
      game.update(0.1);
      expect(game.playerWins, equals(2));

      PvpMatchResult? finalResult;
      game.onMatchFinished = (res) => finalResult = res;

      game.update(2.5);
      expect(game.matchState, equals(PvpMatchState.matchFinished));
      expect(finalResult, isNotNull);
      expect(finalResult!.isWinner, isTrue);
      expect(finalResult!.playerRoundsWon, equals(2));
      expect(finalResult!.opponentRoundsWon, equals(1));
      expect(finalResult!.rpDelta, equals(30)); // Standard win (no sweep)
    });

    test('90s timeout awards round to higher HP percentage', () {
      final opponent = PvpOpponentInfo.generateBot(1300);
      final game = PvpArenaGame(opponentInfo: opponent, playerCurrentRp: 1300);

      game.player = PlayerComponent(position: Vector2(200, 320));
      game.bot = PvpBotPlayerComponent(
        position: Vector2(760, 320),
        opponentInfo: opponent,
        targetPlayer: game.player,
      );

      game.update(1.5); // Enter fighting
      game.player.currentHp = game.player.maxHp * .8;
      game.bot.currentHp = game.bot.maxHp * .4;

      // Elapse 90 seconds
      game.update(90.1);
      expect(game.matchState, equals(PvpMatchState.roundEnd));
      expect(game.playerWins, equals(1));
    });
  });

  group('Group 4: Bot AI Difficulty Adaptation & Discipline', () {
    test('Reflex latency and aim error rates match difficulty matrix', () {
      final bronzeAi = PvpBotAi(difficulty: BotDifficulty.bronzeSilver);
      expect(bronzeAi.decisionInterval, equals(0.35));
      expect(bronzeAi.aimErrorRate, equals(0.24));
      expect(bronzeAi.dodgeChance, equals(0.25));

      final goldAi = PvpBotAi(difficulty: BotDifficulty.goldPlatinum);
      expect(goldAi.decisionInterval, equals(0.20));
      expect(goldAi.aimErrorRate, equals(0.10));
      expect(goldAi.dodgeChance, equals(0.72));

      final challengerAi = PvpBotAi(
        difficulty: BotDifficulty.diamondChallenger,
      );
      expect(challengerAi.decisionInterval, equals(0.08));
      expect(challengerAi.aimErrorRate, equals(0.0));
      expect(challengerAi.dodgeChance, equals(0.92));
    });

    test('Diamond AI uses predictive lead vector based on target velocity', () {
      final challengerAi = PvpBotAi(
        difficulty: BotDifficulty.diamondChallenger,
      );
      final botPos = Vector2(0, 0);
      final targetPos = Vector2(100, 0);
      final targetVel = Vector2(0, 50); // Moving vertically up

      final aimVector = challengerAi.calculateAimDirection(
        botPosition: botPos,
        targetPosition: targetPos,
        targetVelocity: targetVel,
        projectileSpeed: 100.0,
      );

      // Since target is moving along Y axis, predictive aim MUST have a positive Y component
      expect(aimVector.y, greaterThan(0));
      expect(aimVector.x, greaterThan(0));
    });

    test(
      'Bronze AI aims directly at target position without predictive leading',
      () {
        final bronzeAi = PvpBotAi(difficulty: BotDifficulty.bronzeSilver);
        final botPos = Vector2(0, 0);
        final targetPos = Vector2(100, 0);
        final targetVel = Vector2(0, 100);

        // Bronze does not lead: predicted position remains targetPos (100, 0)
        final directAim = bronzeAi.calculateAimDirection(
          botPosition: botPos,
          targetPosition: targetPos,
          targetVelocity: targetVel,
          projectileSpeed: 100.0,
          random: Random(42), // Deterministic RNG
        );

        // Base vector is (1, 0) with wobble
        expect(directAim.x, greaterThan(0.5));
      },
    );

    test('Bot strictly obeys Ki costs and skill cooldowns', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.goldPlatinum);

      // Main's bot skill costs are 20 / 30 / 45 Ki.
      expect(ai.canCastSkill1(19.99), isFalse);
      expect(ai.canCastSkill1(20.0), isTrue);

      expect(ai.canCastSkill2(29.99), isFalse);
      expect(ai.canCastSkill2(30.0), isTrue);

      expect(ai.canCastSkill3(44.99), isFalse);
      expect(ai.canCastSkill3(45.0), isTrue);

      // Cooldown enforcement
      ai.skill1Cooldown = 3.0;
      expect(ai.canCastSkill1(100.0), isFalse);

      ai.tick(3.1);
      expect(ai.skill1Cooldown, equals(0.0));
      expect(ai.canCastSkill1(100.0), isTrue);
    });

    test('Cooldowns tick down accurately with delta time', () {
      final ai = PvpBotAi(difficulty: BotDifficulty.diamondChallenger);
      ai.skill1Cooldown = 4.0;
      ai.skill2Cooldown = 7.0;
      ai.skill3Cooldown = 12.0;
      ai.basicAttackCooldown = 0.8;

      ai.tick(1.0);
      expect(ai.skill1Cooldown, closeTo(3.0, 0.001));
      expect(ai.skill2Cooldown, closeTo(6.0, 0.001));
      expect(ai.skill3Cooldown, closeTo(11.0, 0.001));
      expect(ai.basicAttackCooldown, equals(0.0));
    });
  });

  group('Group 5: Quick Chat System', () {
    test('QuickChat preset contains all 6 required phrases', () {
      expect(QuickChatPhrase.values.length, equals(6));
      expect(QuickChatPhrase.attack.text, equals('Tấn công!'));
      expect(QuickChatPhrase.retreat.text, equals('Rút lui!'));
      expect(QuickChatPhrase.help.text, equals('Cứu tôi!'));
      expect(QuickChatPhrase.awesome.text, equals('Tuyệt vời!'));
      expect(QuickChatPhrase.wait.text, equals('Chờ tí!'));
      expect(QuickChatPhrase.noob.text, equals('Gà quá!'));
    });

    test(
      'QuickChat bubble triggers 3.0s lifespan and auto-clears on player',
      () {
        final player = PlayerComponent(position: Vector2(200, 320));
        expect(player.speechBubbleText, isNull);

        player.say(QuickChatPhrase.attack.text);
        expect(player.speechBubbleText, equals('Tấn công!'));
        expect(player.speechBubbleTimer, equals(3.0));

        player.update(1.5);
        expect(player.speechBubbleText, equals('Tấn công!'));
        expect(player.speechBubbleTimer, closeTo(1.5, 0.001));

        player.update(1.6);
        expect(player.speechBubbleText, isNull);
      },
    );

    test('QuickChat bubble triggers 3.0s lifespan and auto-clears on bot', () {
      final opponent = PvpOpponentInfo.generateBot(1200);
      final player = PlayerComponent(position: Vector2(200, 320));
      final bot = PvpBotPlayerComponent(
        position: Vector2(760, 320),
        opponentInfo: opponent,
        targetPlayer: player,
      );

      bot.say('Nhào vô!');
      expect(bot.speechBubbleText, equals('Nhào vô!'));
      expect(bot.speechBubbleTimer, equals(3.0));

      bot.update(3.1);
      expect(bot.speechBubbleText, isNull);
    });

    test('New quick chat overrides previous active bubble', () {
      final player = PlayerComponent(position: Vector2(200, 320));
      player.say('Chờ tí!');
      player.update(1.0);
      expect(player.speechBubbleText, equals('Chờ tí!'));

      player.say('Tuyệt vời!');
      expect(player.speechBubbleText, equals('Tuyệt vời!'));
      expect(player.speechBubbleTimer, equals(3.0));
    });
  });

  group('Group 6: Matchmaking Timeout Fallback & Arena Geometry', () {
    test('60.0s matchmaking timeout produces valid bot fallback', () {
      final playerProfileRp = 1450;
      final opponent = PvpOpponentInfo.generateBot(playerProfileRp);

      expect(opponent.isBot, isTrue);
      expect(opponent.rankPoints, inInclusiveRange(1300, 1600));
      expect(opponent.rankTier, isNotEmpty);
    });

    test('Arena geometry enforces symmetrical spawns at X=200 and X=760', () {
      expect(PvpArenaGame.playerSpawnPos, equals(Vector2(200, 320)));
      expect(PvpArenaGame.botSpawnPos, equals(Vector2(760, 320)));

      // Center is exactly at X=480
      final centerX =
          (PvpArenaGame.playerSpawnPos.x + PvpArenaGame.botSpawnPos.x) / 2;
      expect(centerX, equals(480.0));
    });
  });

  group('Group 7: Realtime Online Replication & Multi-Hero Support', () {
    test('PvpBotPlayerComponent smoothly interpolates towards targetPosition when enableAi is false', () {
      final player = PlayerComponent(
        position: Vector2(200, 320),
        heroId: 'ranger',
      );
      final bot = PvpBotPlayerComponent(
        position: Vector2(760, 320),
        opponentInfo: PvpOpponentInfo.generateBot(1000, playerHeroId: 'tanker'),
        targetPlayer: player,
        enableAi: false,
      );

      expect(player.heroId, equals('ranger'));
      expect(bot.enableAi, isFalse);

      // Simulate opponent moved to (700, 320)
      bot.targetPosition = Vector2(700, 320);
      bot.update(0.016); // One 60 FPS frame

      // Bot should have moved towards 700
      expect(bot.position.x, lessThan(760));
      expect(bot.position.x, greaterThan(700));
      expect(bot.isFacingRight, isFalse);
    });

    test('PlayerComponent supports all 4 distinct hero archetypes', () {
      const heroes = ['george', 'ranger', 'tanker', 'ninja'];
      for (final h in heroes) {
        final p = PlayerComponent(position: Vector2(400, 300), heroId: h);
        expect(p.heroId, equals(h));
      }
    });
  });

  group('Group 6: Online PvP sync handshake', () {
    PvpOpponentInfo human() => PvpOpponentInfo(
      name: 'Tab 2',
      rankPoints: 1000,
      rankTier: 'Đồng',
      heroId: 'george',
      isBot: false,
    );

    test(
      'Online match waits for opponent and only starts after startOnlineMatch',
      () {
        final game = PvpArenaGame(
          opponentInfo: human(),
          playerCurrentRp: 1000,
          isOnline: true,
        );
        expect(game.matchState, PvpMatchState.waiting);
        game.update(10);
        expect(game.matchState, PvpMatchState.waiting);
        game.setPlayerMoveDirection(Vector2(1, 0));
        expect(game.player.moveDirection.isZero(), isTrue);

        game.startOnlineMatch();
        expect(game.matchState, PvpMatchState.roundIntro);
        game.update(3.1);
        expect(game.matchState, PvpMatchState.fighting);
      },
    );

    test(
      'Opponent snapshot moves remote player and stale-round HP is ignored',
      () {
        final game = PvpArenaGame(
          opponentInfo: human(),
          playerCurrentRp: 1000,
          isOnline: true,
        );
        game.startOnlineMatch();
        game.currentRound = 2;
        game.bot.currentHp = 100;

        game.applyOpponentSnapshot({
          'x': 500.0,
          'y': 300.0,
          'hp': 5.0,
          'round': 1,
        });
        expect(game.bot.targetPosition, Vector2(500, 300));
        expect(
          game.bot.currentHp,
          100,
          reason: 'HP của hiệp cũ không được ghi đè hiệp mới',
        );

        game.applyOpponentSnapshot({
          'x': 520.0,
          'y': 300.0,
          'hp': 60.0,
          'round': 2,
        });
        expect(game.bot.currentHp, 60);
      },
    );

    test('Opponent forfeit concludes match as a win', () {
      final game = PvpArenaGame(
        opponentInfo: human(),
        playerCurrentRp: 1000,
        isOnline: true,
      );
      PvpMatchResult? result;
      game.onMatchFinished = (r) => result = r;
      game.startOnlineMatch();
      game.opponentForfeit();
      expect(game.matchState, PvpMatchState.matchFinished);
      expect(result?.isWinner, isTrue);
    });

    test(
      'Dead Reckoning applies velocity and extrapolates movement in real-time',
      () {
        final game = PvpArenaGame(
          opponentInfo: human(),
          playerCurrentRp: 1000,
          isOnline: true,
        );
        game.startOnlineMatch();
        game.matchState = PvpMatchState.fighting;

        // Giả lập nhận snapshot có vx = 160.0 (đối thủ đang chạy sang phải)
        game.applyOpponentSnapshot({
          'x': 500.0,
          'y': 320.0,
          'vx': 160.0,
          'vy': 0.0,
          'round': 1,
        });

        expect(game.bot.targetVelocity, Vector2(160, 0));
        game.bot.position = Vector2(500, 320);

        // Cập nhật 1 frame (1/60s = 0.016s)
        game.bot.update(0.016);

        // Nhân vật đối thủ phải tự động di chuyển về phía trước theo vận tốc thời gian thực (500 + 160 * 0.016 = 502.56)
        expect(game.bot.position.x, greaterThan(501.0));
        expect(game.bot.isFacingRight, isTrue);
      },
    );
  });

  group('Kaelen PvP catalog integration', () {
    setUp(() {
      final originalProfile = PlayerStorage.currentProfile;
      final originalAudio = AudioService.instance;
      addTearDown(() {
        PlayerStorage.profileNotifier.value = originalProfile;
        AudioService.setInstance(originalAudio);
      });
      PlayerStorage.profileNotifier.value = PlayerProfile.defaultProfile()
          .copyWith(selectedHeroId: 'kaelen');
      AudioService.setInstance(MockAudioService());
    });

    PvpArenaGame arena() => PvpArenaGame(
      opponentInfo: const PvpOpponentInfo(
        name: 'Kaelen opponent',
        rankPoints: 2000,
        rankTier: 'Diamond',
        heroId: 'kaelen',
        difficulty: BotDifficulty.diamondChallenger,
        isBot: false,
      ),
      playerCurrentRp: 2000,
      isOnline: true,
      selectedMapConfig: GameAssetRegistry.defaultSanctumMap,
    );

    testWidgets('Constructed Kaelen arena casts catalog skills exactly once', (
      tester,
    ) async {
      final game = arena();
      final player = game.player;
      final bot = game.bot;
      final actions = <String>[];
      game.onLocalAction = (action, {text}) => actions.add(action);
      expect(player.heroId, 'kaelen');
      expect(player.legacyPvpSkills, isFalse);
      for (var slot = 1; slot <= 3; slot++) {
        expect(
          player.skillConfig(slot),
          same(GameAssetRegistry.instance.getSkillForHeroSlot('kaelen', slot)),
        );
      }
      expect(player.skillRuntimes.map((s) => s.config.kiCost), [30, 55, 90]);
      expect(player.skillRuntimes.map((s) => s.config.cooldown), [5, 10, 18]);

      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() async {
        await game.toBeLoaded();
        await game.ready();
      });
      expect(player.isMounted && bot.isMounted, isTrue);
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      expect(actions, isEmpty, reason: 'Waiting rejects every local cast');
      game.startOnlineMatch();
      game.update(PvpArenaGame.roundIntroDuration);
      bot.maxHp = bot.currentHp = 10000;
      player.maxHp = player.currentHp = 1000;
      player.position = Vector2(200, 320);
      player.faceDirection(Vector2(1, 0));
      bot.position = Vector2(290, 320);

      player.currentKi = 29.99;
      game.onSkill1();
      expect(player.skill1VisualCd, 0);
      expect(actions, isEmpty);
      player.currentKi = 100;
      game.onSkill1();
      expect(player.currentKi, 70);
      expect(player.skill1VisualCd, 5);
      expect(player.position, Vector2(380, 320));
      expect(player.afterimagePositions, hasLength(3));
      expect(bot.currentHp, closeTo(10000 - player.damage * 1.8, .00001));
      expect(bot.stunTimer, .5);
      final dashHp = bot.currentHp;
      final frozen = bot.position.clone();
      bot.moveDirection = Vector2(1, 0);
      bot.update(.1);
      expect(bot.position, frozen);
      player.currentKi = 100;
      game.onSkill1();
      expect(player.currentKi, 100);
      expect(bot.currentHp, dashHp);
      expect(actions, ['skill1']);

      // The dash stops before the real pillar and cannot hit through it.
      player.resetCombatState();
      player.position = Vector2(200, 200);
      player.faceDirection(Vector2(1, 0));
      bot.position = Vector2(330, 200);
      game.onSkill1();
      expect(player.position.x, inInclusiveRange(200, 244));
      expect(bot.currentHp, dashHp);
      expect(actions, ['skill1', 'skill1']);

      player.resetCombatState();
      player.position = Vector2(400, 320);
      bot.position = Vector2(485, 320);
      bot.moveDirection = Vector2.zero();
      bot.stunTimer = 0;
      player.currentKi = 54.99;
      game.onSkill2();
      expect(player.currentKi, 54.99);
      expect(player.skill2VisualCd, 0);
      player.currentKi = 100;
      final vortexHp = bot.currentHp;
      game.onSkill2();
      expect(player.currentKi, 45);
      expect(player.skill2VisualCd, 10);
      expect(player.skillRuntime(2).effectRemaining, 4);
      expect(player.effectiveSpeed, player.speed * 1.25);
      expect(bot.currentHp, vortexHp, reason: 'Vortex has no up-front hit');
      player.takeDamage(100);
      expect(player.currentHp, closeTo(930, .00001));
      player.currentKi = 100;
      game.onSkill2();
      expect(player.currentKi, 100);
      expect(actions, ['skill1', 'skill1', 'skill2']);
      await tester.runAsync(game.ready);
      final vortex = game.world.children.whereType<PlayerSkillArea>().single;
      expect(vortex.radius, 85);
      expect(vortex.duration, 4);
      expect(vortex.tickInterval, .5);
      expect(vortex.follow, same(player));
      final pulseDamage = player.damage * 4.5 / 8;
      game.update(.49);
      expect(bot.currentHp, vortexHp);
      game.update(.01);
      expect(bot.currentHp, closeTo(vortexHp - pulseDamage, .00001));
      player.position = Vector2(450, 320);
      bot.position = Vector2(535, 320);
      game.update(.5);
      expect(vortex.position, player.position);
      expect(bot.currentHp, closeTo(vortexHp - pulseDamage * 2, .00001));
      game.update(3);
      expect(bot.currentHp, closeTo(vortexHp - player.damage * 4.5, .00001));
      game.update(1);
      expect(bot.currentHp, closeTo(vortexHp - player.damage * 4.5, .00001));
      expect(player.skillRuntime(2).effectRemaining, 0);
      expect(player.skill2VisualCd, closeTo(5, .00001));
      expect(player.effectiveSpeed, player.speed);
      player.takeDamage(100);
      expect(player.currentHp, closeTo(830, .00001));

      player.resetCombatState();
      player.currentKi = 89.99;
      game.onSkill3();
      expect(player.currentKi, 89.99);
      expect(player.skill3VisualCd, 0);
      player.currentKi = 100;
      bot.position = player.position + Vector2(160, 0);
      final judgmentHp = bot.currentHp;
      game.onSkill3();
      expect(player.currentKi, 10);
      expect(player.skill3VisualCd, 18);
      expect(bot.currentHp, closeTo(judgmentHp - player.damage * 3.5, .00001));
      expect(bot.stunTimer, 1.5);
      expect(player.isBerserk, isFalse);
      expect(player.invulnerabilityTimer, .6);
      expect(player.skillRuntime(3).effectRemaining, 8);
      expect(player.effectiveSpeed, player.speed * 1.5);
      final protectedHp = player.currentHp;
      player.takeDamage(100);
      expect(player.currentHp, protectedHp);
      player.update(.2);
      player.currentKi = 100;
      game.onSkill3();
      expect(player.currentKi, 100);
      expect(player.skill3VisualCd, closeTo(17.8, .00001));
      expect(player.invulnerabilityTimer, closeTo(.4, .00001));
      expect(bot.currentHp, closeTo(judgmentHp - player.damage * 3.5, .00001));
      player.update(.4);
      player.takeDamage(100);
      expect(player.currentHp, closeTo(protectedHp - 60, .00001));
      player.moveDirection = Vector2(1, 0);
      expect(game.localSnapshot['vx'], closeTo(player.effectiveSpeed, .05));
      player.moveDirection = Vector2.zero();
      player.update(7.41);
      expect(player.effectiveSpeed, player.speed);

      player.resetCombatState();
      player.currentKi = 100;
      bot.position = player.position + Vector2(161, 0);
      bot.stunTimer = 0;
      final outsideJudgmentHp = bot.currentHp;
      game.onSkill3();
      expect(bot.currentHp, outsideJudgmentHp);
      expect(bot.stunTimer, 0);
      expect(player.currentKi, 10);

      player.resetCombatState();
      player.currentKi = 100;
      game.pauseEngine();
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      game.resumeEngine();
      player.actionsEnabled = false;
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      player.actionsEnabled = true;
      game.matchState = PvpMatchState.roundEnd;
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      game.matchState = PvpMatchState.fighting;
      player.currentHp = 0;
      game.onSkill1();
      game.onSkill2();
      game.onSkill3();
      expect(player.currentKi, 100);
      expect(player.skillRuntimes.every((s) => s.cooldownRemaining == 0), isTrue);
      expect(actions, ['skill1', 'skill1', 'skill2', 'skill3', 'skill3']);
    });

    testWidgets('Kaelen forced opponent replay mirrors costs and timed effects', (
      tester,
    ) async {
      final game = arena();
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();
      await tester.runAsync(() async {
        await game.toBeLoaded();
        await game.ready();
      });
      game.startOnlineMatch();
      game.update(PvpArenaGame.roundIntroDuration);
      final bot = game.bot;
      final player = game.player;
      player.maxHp = player.currentHp = 10000;
      bot.maxHp = bot.currentHp = 1000;
      final actions = <String>[];
      game.onLocalAction = (action, {text}) => actions.add(action);
      bot.position = Vector2(500, 320);
      player.position = Vector2(410, 320);
      bot.actionsEnabled = false;
      bot.currentKi = 100;
      bot.executeSkill1();
      expect(bot.currentKi, 100);
      game.applyOpponentAction('skill1');
      expect(bot.currentKi, 70);
      expect(bot.position, Vector2(320, 320));
      expect(player.currentHp, closeTo(10000 - bot.damage * 1.8, .00001));
      expect(player.canAct, isFalse);
      expect(bot.kaelenPlayerStunTimer, .5);
      game.update(.25);
      expect(player.canAct, isFalse);
      game.update(.26);
      expect(player.canAct, isTrue);

      bot.resetRound(Vector2(400, 320));
      player.position = Vector2(485, 320);
      bot.currentKi = 54.99;
      bot.executeSkill2();
      expect(bot.currentKi, 54.99);
      bot.currentKi = 100;
      game.applyOpponentAction('skill2');
      expect(bot.currentKi, 45);
      expect(bot.effectiveSpeed, bot.speed * 1.25);
      bot.takeDamage(100);
      expect(bot.currentHp, closeTo(930, .00001));
      final vortexHp = player.currentHp;
      await tester.runAsync(game.ready);
      final vortex = game.world.children.whereType<PlayerSkillArea>().single;
      expect(vortex.follow, same(bot));
      game.update(.49);
      expect(player.currentHp, vortexHp);
      game.update(.01);
      expect(player.currentHp, closeTo(vortexHp - bot.damage * 4.5 / 8, .00001));
      player.position = Vector2(486, 320);
      game.update(3.5);
      expect(player.currentHp, closeTo(vortexHp - bot.damage * 4.5 / 8, .00001));
      bot.actionsEnabled = false;
      bot.update(4);
      expect(bot.effectiveSpeed, bot.speed);
      bot.takeDamage(100);
      expect(bot.currentHp, closeTo(830, .00001));

      bot.resetRound(Vector2(400, 320));
      player.position = Vector2(560, 320);
      bot.currentKi = 89.99;
      bot.executeSkill3();
      expect(bot.currentKi, 89.99);
      bot.currentKi = 100;
      bot.actionsEnabled = false;
      final judgmentHp = player.currentHp;
      game.applyOpponentAction('skill3');
      expect(bot.currentKi, 10);
      expect(bot.isBerserk, isFalse);
      expect(bot.effectiveSpeed, bot.speed * 1.5);
      expect(player.currentHp, closeTo(judgmentHp - bot.damage * 3.5, .00001));
      expect(bot.kaelenPlayerStunTimer, 1.5);
      bot.takeDamage(100);
      expect(bot.currentHp, 1000);
      bot.update(.61);
      bot.takeDamage(100);
      expect(bot.currentHp, closeTo(940, .00001));
      bot.update(7.4);
      expect(bot.effectiveSpeed, bot.speed);
      bot.resetRound(Vector2(400, 320));
      expect(bot.kaelenPlayerStunTimer, 0);
      bot.currentKi = 0;
      final forcedHp = player.currentHp;
      game.applyOpponentAction('skill3');
      expect(bot.currentKi, 0, reason: 'Force accepts a post-spend snapshot');
      expect(player.currentHp, closeTo(forcedHp - bot.damage * 3.5, .00001));
      bot.currentHp = 0;
      bot.currentKi = 100;
      game.applyOpponentAction('skill3');
      expect(bot.currentKi, 100, reason: 'Force never revives a dead actor');
      expect(actions, isEmpty, reason: 'Remote replay emits no local action');
    });

    test('Only Kaelen AI uses catalog resource thresholds and cooldowns', () {
      final game = arena()..matchState = PvpMatchState.fighting;
      final bot = game.bot;
      final ai = bot.aiController;
      expect(ai.canCastSkill1(29.99), isFalse);
      expect(ai.canCastSkill1(30), isTrue);
      expect(ai.canCastSkill2(54.99), isFalse);
      expect(ai.canCastSkill2(55), isTrue);
      expect(ai.canCastSkill3(89.99), isFalse);
      expect(ai.canCastSkill3(90), isTrue);
      game.player.currentHp = 10000;
      for (final slot in [1, 2, 3]) {
        bot.resetRound(Vector2(400, 320));
        game.player.position = Vector2(440, 320);
        final config = bot.kaelenSkillConfig(slot)!;
        bot.currentKi = config.kiCost;
        ai.evaluateTactics();
        expect(bot.currentKi, 0);
        final cooldown = switch (slot) {
          1 => ai.skill1Cooldown,
          2 => ai.skill2Cooldown,
          _ => ai.skill3Cooldown,
        };
        expect(cooldown, config.cooldown);
        expect(
          switch (slot) {
            1 => ai.canCastSkill1(100),
            2 => ai.canCastSkill2(100),
            _ => ai.canCastSkill3(100),
          },
          isFalse,
        );
        ai.tick(config.cooldown);
        expect(
          switch (slot) {
            1 => ai.canCastSkill1(config.kiCost),
            2 => ai.canCastSkill2(config.kiCost),
            _ => ai.canCastSkill3(config.kiCost),
          },
          isTrue,
        );
      }
      for (final hero in [
        'george',
        'ranger',
        'tanker',
        'ninja',
        'nova_blade',
        'shadow_01',
        'ember_02',
        'valeria',
        'garrick',
      ]) {
        final legacyBot = PvpBotPlayerComponent(
          position: Vector2(400, 320),
          opponentInfo: PvpOpponentInfo(
            name: 'Existing hero',
            rankPoints: 2000,
            rankTier: 'Diamond',
            heroId: hero,
            difficulty: BotDifficulty.diamondChallenger,
          ),
          targetPlayer: game.player,
          enableAi: false,
        );
        final legacyAi = legacyBot.aiController;
        expect(legacyBot.kaelenSkillConfig(1), isNull);
        expect(legacyAi.canCastSkill1(19.99), isFalse);
        expect(legacyAi.canCastSkill1(20), isTrue);
        expect(legacyAi.canCastSkill2(29.99), isFalse);
        expect(legacyAi.canCastSkill2(30), isTrue);
        expect(legacyAi.canCastSkill3(44.99), isFalse);
        expect(legacyAi.canCastSkill3(45), isTrue);
        game.player.position = Vector2(560, 320);
        legacyBot.currentKi = 45;
        legacyAi.evaluateTactics();
        expect(legacyBot.currentKi, 0);
        expect(legacyAi.skill3Cooldown, PvpBotAi.cooldownSkill3);
      }
    });
  });

  group('Group 8: 2v2 & 4v4 Team Matchmaking & Kaelen Thunderblade', () {
    test('generateTeamRoster creates 1 ally + 2 enemies for 2v2 and 3 allies + 4 enemies for 4v4', () {
      final roster2v2 = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1300,
        mode: PvpGameMode.duo2v2,
        playerHeroId: 'kaelen',
      );
      expect(roster2v2.mode, equals(PvpGameMode.duo2v2));
      expect(roster2v2.allies.length, equals(1));
      expect(roster2v2.allies.first.isAlly, isTrue);
      expect(roster2v2.enemies.length, equals(2));
      expect(roster2v2.enemies.every((e) => !e.isAlly), isTrue);

      final roster4v4 = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1500,
        mode: PvpGameMode.squad4v4,
        playerHeroId: 'kaelen',
      );
      expect(roster4v4.mode, equals(PvpGameMode.squad4v4));
      expect(roster4v4.allies.length, equals(3));
      expect(roster4v4.enemies.length, equals(4));
    });

    test('PvpArenaGame in 2v2 and 4v4 requires entire team elimination to end round', () {
      final roster2v2 = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1300,
        mode: PvpGameMode.duo2v2,
      );
      final game2v2 = PvpArenaGame(
        opponentInfo: roster2v2.primaryOpponent,
        playerCurrentRp: 1300,
        gameMode: PvpGameMode.duo2v2,
        roster: roster2v2,
      );

      expect(game2v2.allies.length, equals(1));
      expect(game2v2.allEnemies.length, equals(2));

      // Enter fighting state
      game2v2.update(3.0);
      expect(game2v2.matchState, equals(PvpMatchState.fighting));

      // Knock out only primary enemy bot -> round should NOT end yet because 2nd enemy is alive
      game2v2.bot.currentHp = 0;
      game2v2.update(0.1);
      expect(game2v2.matchState, equals(PvpMatchState.fighting));
      expect(game2v2.redTeamAliveCount, equals(1));

      // Knock out 2nd enemy -> Red team wiped -> Blue team wins round!
      game2v2.extraEnemies.first.currentHp = 0;
      game2v2.update(0.1);
      expect(game2v2.matchState, equals(PvpMatchState.roundEnd));
      expect(game2v2.playerWins, equals(1));
    });

    test('Kaelen uses catalog skills and its configured Judgment buffs', () {
      final kaelen = PlayerComponent(
        position: Vector2(200, 320),
        heroId: 'kaelen',
      );
      expect(kaelen.heroId, equals('kaelen'));
      expect(kaelen.skillConfig(1).id, 'kaelen_thunder_flash');
      expect(kaelen.skillConfig(2).id, 'kaelen_storm_vortex');
      expect(kaelen.skillConfig(3).id, 'kaelen_heaven_judgment');

      // 3-hit normal attack combo
      kaelen.performBasicAttack();
      expect(kaelen.comboStep, equals(1));
      kaelen.isAttacking = false;
      kaelen.performBasicAttack();
      expect(kaelen.comboStep, equals(2));
      kaelen.isAttacking = false;
      kaelen.performBasicAttack();
      expect(kaelen.comboStep, equals(3));
      expect(kaelen.isAttacking, isTrue);
      expect(kaelen.attackTimer, isZero);

      // Skill 1: Thunder Flash trail & visual CD
      expect(kaelen.useSkill1(), isTrue);
      expect(kaelen.skill1TrailTimer, greaterThan(0));
      expect(kaelen.skill1StartOffset, isNotNull);
      expect(kaelen.skill1VisualCd, equals(PlayerComponent.maxSkill1VisualCd));

      // Skill 2: Storm Blade Vortex
      expect(kaelen.useSkill2(), isTrue);
      expect(kaelen.skill2VortexTimer, greaterThan(0));
      expect(kaelen.skill2VisualCd, equals(kaelen.skillConfig(2).cooldown));

      // Refill Ki & cast Skill 3: Heaven's Judgment
      kaelen.resetCombatState();
      kaelen.currentKi = 100;
      final speed = kaelen.speed;
      final hp = kaelen.currentHp;
      expect(kaelen.useSkill3(), isTrue);
      expect(kaelen.currentKi, 10);
      expect(kaelen.isBerserk, isFalse);
      expect(kaelen.skill3JudgmentTimer, greaterThan(0));
      expect(kaelen.skill3VisualCd, 18);
      expect(kaelen.skillRuntime(3).effectRemaining, 8);
      expect(kaelen.invulnerabilityTimer, closeTo(0.6, 0.00001));
      expect(kaelen.effectiveSpeed, closeTo(speed * 1.5, 0.00001));

      kaelen.currentKi = 100;
      expect(kaelen.useSkill3(), isFalse);
      expect(kaelen.currentKi, 100);
      expect(kaelen.skill3VisualCd, 18);

      kaelen.invulnerabilityTimer = 0;
      kaelen.takeDamage(100);
      expect(kaelen.currentHp, closeTo(hp - 60, 0.00001));
    });
  });
}
