import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/core/stat_growth_formula.dart';
import 'package:my_game/game/components/player.dart';
import 'package:my_game/game/pvp_arena_game.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/friend_party_models.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/services/chat_ai_assistant_service.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:my_game/services/player_storage.dart';

String partyFixtureJson(PartyRoomState party) => jsonEncode({
  'partyCode': party.partyCode,
  'leaderCode': party.leaderCode,
  'leaderName': party.leaderName,
  'leaderHeroId': party.leaderHeroId,
  'leaderHeroLevel': party.leaderHeroLevel,
  'mode': party.mode.code,
  'members': party.members.map((member) => member.toJson()).toList(),
  'updatedAt': DateTime.now().millisecondsSinceEpoch,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PlayerStorage.saveProfile(PlayerProfile.defaultProfile());
    FriendPartyService.instance.leaveParty();
  });

  group('1. Data-Driven Asset Registry (assets/data/*.json)', () {
    test('Loads heroes, skills, companions, maps, and enemies from JSON (Assets 1-4)', () async {
      await GameAssetRegistry.instance.initialize();
      expect(GameAssetRegistry.instance.isInitialized, isTrue);
      expect(
        GameAssetRegistry.instance.heroes.length,
        greaterThanOrEqualTo(10),
      );
      expect(
        GameAssetRegistry.instance.getHero('nova_blade').name,
        contains('Nova Blade'),
      );
      expect(
        GameAssetRegistry.instance.getHero('shadow_01').name,
        contains('SHADOW-01'),
      );
      expect(
        GameAssetRegistry.instance.getHero('ember_02').name,
        contains('EMBER-02'),
      );
      expect(
        GameAssetRegistry.instance.getHero('valeria').name,
        contains('Valeria'),
      );
      expect(
        GameAssetRegistry.instance.getHero('garrick').name,
        contains('Garrick'),
      );
      expect(
        GameAssetRegistry.instance.getHero('kaelen').name,
        contains('Kaelen'),
      );
      expect(
        GameAssetRegistry.instance.getSkillsForHero('nova_blade').length,
        equals(3),
      );
      expect(
        GameAssetRegistry.instance.getSkillsForHero('valeria').length,
        equals(3),
      );
      expect(
        GameAssetRegistry.instance.getSkillsForHero('garrick').length,
        equals(3),
      );
      expect(
        GameAssetRegistry.instance.getCompanion('cyber_drone')?.name,
        contains('Cyber Drone'),
      );
      expect(
        GameAssetRegistry.instance.getCompanion('pyro_frost_dragon')?.name,
        contains('Pyro-Frost Dragon'),
      );
      expect(
        GameAssetRegistry.instance.getCompanion('gem_tumbler')?.name,
        contains('Gem-Tumbler'),
      );
      expect(GameAssetRegistry.instance.maps.length, greaterThanOrEqualTo(6));
    });

    test('Allows registering a custom Hero asset at runtime', () {
      const customHero = HeroAssetConfig(
        id: 'custom_paladin',
        name: 'Thánh Kỵ Sĩ Hoàng Kim',
        role: 'Đấu Sĩ / Hỗ Trợ',
        classType: 'warrior',
        priceGold: 5500,
        unlockedByDefault: false,
        baseStats: HeroBaseStatsConfig(
          hp: 130,
          ki: 110,
          attack: 28,
          speed: 155,
        ),
        growthPerLevel: HeroGrowthConfig(
          hpPerLevel: 18.0,
          kiPerLevel: 4.0,
          attackPerLevel: 2.5,
        ),
        skillIds: ['s1', 's2', 's3'],
        sprites: HeroSpriteConfig(
          idleSheet: 'assets/images/heroes/paladin_idle.png',
          runSheet: 'assets/images/heroes/paladin_run.png',
          attackSheet: 'assets/images/heroes/paladin_attack.png',
        ),
      );

      GameAssetRegistry.instance.registerCustomHero(customHero);
      expect(
        GameAssetRegistry.instance.getHero('custom_paladin').name,
        equals('Thánh Kỵ Sĩ Hoàng Kim'),
      );
    });
  });

  group('2. User Hero Level System (Level 1 -> 100 After Each Match)', () {
    test(
      'Computes different stat growth per level (1 -> 100) by hero class',
      () {
        final lv1George = StatGrowthFormula.computeStatsForLevel(
          heroId: 'george',
          level: 1,
        );
        final lv50George = StatGrowthFormula.computeStatsForLevel(
          heroId: 'george',
          level: 50,
        );
        final lv100George = StatGrowthFormula.computeStatsForLevel(
          heroId: 'george',
          level: 100,
        );

        expect(lv1George.bonusHp, equals(0));
        expect(lv50George.maxHp, greaterThan(lv1George.maxHp));
        expect(lv100George.maxHp, greaterThan(lv50George.maxHp));
        expect(lv100George.maxKi, greaterThan(lv50George.maxKi));
        expect(lv100George.attackDamage, greaterThan(lv50George.attackDamage));

        // Tanker gains more HP at Lv.100 than Ranger, while Ranger gains more Attack
        final lv100Tanker = StatGrowthFormula.computeStatsForLevel(
          heroId: 'tanker',
          level: 100,
        );
        final lv100Ranger = StatGrowthFormula.computeStatsForLevel(
          heroId: 'ranger',
          level: 100,
        );
        expect(lv100Tanker.bonusHp, greaterThan(lv100Ranger.bonusHp));
        expect(lv100Ranger.bonusAttack, greaterThan(lv100Tanker.bonusAttack));
      },
    );

    test(
      'Post-match EXP levels up hero and boosts PlayerComponent stats',
      () async {
        expect(PlayerStorage.currentProfile.getHeroLevel('george'), equals(1));

        // Grant enough EXP after match to level up George
        final result = await PlayerStorage.addHeroExpAfterMatch(
          heroId: 'george',
          isVictory: true,
          isPvp: false,
          floorOrRounds: 3,
          customExp: 500,
        );

        expect(result.didLevelUp, isTrue);
        expect(result.newLevel, greaterThan(1));
        expect(result.hpAdded, greaterThan(0));
        expect(result.kiAdded, greaterThan(0));
        expect(result.attackAdded, greaterThan(0));
        expect(
          PlayerStorage.currentProfile.getHeroLevel('george'),
          equals(result.newLevel),
        );

        // Verify PlayerComponent applies the user's hero level (1 -> 100)
        final playerLv1 = PlayerComponent(
          position: Vector2.zero(),
          heroId: 'george',
          userHeroLevel: 1,
        );
        final playerBoosted = PlayerComponent(
          position: Vector2.zero(),
          heroId: 'george',
          userHeroLevel: result.newLevel,
        );

        expect(playerBoosted.maxHp, greaterThan(playerLv1.maxHp));
        expect(playerBoosted.maxKi, greaterThan(playerLv1.maxKi));
        expect(playerBoosted.damage, greaterThan(playerLv1.damage));
      },
    );

    test('Caps Hero Level cleanly at Level 100', () async {
      final res = await PlayerStorage.addHeroExpAfterMatch(
        heroId: 'george',
        isVictory: true,
        isPvp: true,
        customExp: 9999999,
      );
      expect(res.newLevel, equals(100));
      expect(res.expToNextLevel, equals(0));
    });
  });

  group('3. Economy Exchange (1 Xu = 1000 Vàng)', () {
    test('Converts Xu <-> Gold at exact 1 Xu = 1000 Gold ratio', () async {
      final initialGold = PlayerStorage.currentProfile.gold;
      final initialXu = PlayerStorage.currentProfile.xu;

      final okXuToGold = await PlayerStorage.convertXuToGold(2);
      expect(okXuToGold, isTrue);
      expect(PlayerStorage.currentProfile.xu, equals(initialXu - 2));
      expect(PlayerStorage.currentProfile.gold, equals(initialGold + 2000));

      final okGoldToXu = await PlayerStorage.convertGoldToXu(1);
      expect(okGoldToXu, isTrue);
      expect(PlayerStorage.currentProfile.xu, equals(initialXu - 1));
      expect(PlayerStorage.currentProfile.gold, equals(initialGold + 1000));
    });
  });

  group('4. Friends, Party Invite & Team PvP (1v1 / 2v2 / 4v4)', () {
    test('Adds friends and invites them into a 2v2 / 4v4 party team', () async {
      final host = PlayerStorage.currentProfile.copyWith(playerCode: 'GR1001');
      await PlayerStorage.saveProfile(host);
      const peer = FriendInfo(
        code: 'GR7777',
        name: 'Peer fixture',
        rankPoints: 1300,
        rankTier: 'Bạc',
        selectedHeroId: 'ranger',
        isOnline: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'gold_rush_shared_directory_GR7777',
        jsonEncode(peer.toJson()),
      );
      final service = FriendPartyService.instance;
      service.friendsNotifier.value = [];
      service.incomingFriendRequestsNotifier.value = [
        FriendRequest(
          id: 'reciprocal-fixture',
          fromCode: peer.code,
          fromName: peer.name,
          fromRankPoints: peer.rankPoints,
          fromRankTier: peer.rankTier,
          fromHeroId: peer.selectedHeroId,
          toCode: host.playerCode,
          toName: host.playerName,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
      final accepted = await service.sendFriendRequest(peer.code);
      expect(accepted.status, FriendRequestSendStatus.autoAccepted);
      final added = accepted.targetFriend!;
      expect(added.code, equals('GR7777'));

      final party = FriendPartyService.instance.createOrUpdateParty(
        mode: PvpGameMode.squad4v4,
      );
      expect(party.mode, equals(PvpGameMode.squad4v4));

      final invited = FriendPartyService.instance.inviteFriendToParty(
        added,
        preferredMode: PvpGameMode.squad4v4,
      );
      expect(invited, isTrue);
      expect(
        service.partyNotifier.value!.members,
        isEmpty,
        reason: 'An invitation alone must not add a player without consent',
      );
      await prefs.setString(
        'gold_rush_shared_party_${party.partyCode}',
        partyFixtureJson(party),
      );
      await PlayerStorage.saveProfile(
        host.copyWith(playerCode: peer.code, playerName: peer.name),
      );
      service.stopPolling();
      service.partyNotifier.value = null;
      await service.joinPartyByCode(party.partyCode);
      await PlayerStorage.saveProfile(host);

      final partyAllies = FriendPartyService.instance.getPartyAlliesForMode(
        PvpGameMode.squad4v4,
      );
      expect(partyAllies.length, equals(1));
      expect(partyAllies.first.isAlly, isTrue);
      expect(partyAllies.first.isBot, isFalse);

      // Build 4v4 roster: 1 real friend ally + 2 AI bot fallback allies = 3 allies total
      final roster = PvpOpponentInfo.generateTeamRoster(
        playerRp: 1500,
        mode: PvpGameMode.squad4v4,
        onlineAllies: partyAllies,
      );
      expect(roster.allies.length, equals(3));
      expect(roster.enemies.length, equals(4));
      expect(roster.allies.first.name, contains('GR7777'));
    });

    test(
      'Joining party by code updates the host party room members list',
      () async {
        final host = PlayerStorage.currentProfile.copyWith(
          playerCode: 'GR1001',
        );
        await PlayerStorage.saveProfile(host);
        final hostParty = FriendPartyService.instance.createOrUpdateParty(
          mode: PvpGameMode.duo2v2,
        );
        expect(hostParty.members, isEmpty);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'gold_rush_shared_party_${hostParty.partyCode}',
          partyFixtureJson(hostParty),
        );
        await PlayerStorage.saveProfile(host.copyWith(playerCode: 'GR1002'));
        FriendPartyService.instance.stopPolling();
        FriendPartyService.instance.partyNotifier.value = null;

        final joinedParty = await FriendPartyService.instance.joinPartyByCode(
          hostParty.partyCode,
        );
        expect(joinedParty.partyCode, equals(hostParty.partyCode));
        expect(joinedParty.members.length, equals(1));
        expect(
          FriendPartyService.instance.partyNotifier.value?.members.length,
          equals(1),
        );
        FriendPartyService.instance.leaveParty();
        await PlayerStorage.saveProfile(host);
      },
    );

    test('Online PvP syncs Round Loss and Match Defeat modal to User 2 when User 1 wins', () {
      const oppInfo = PvpOpponentInfo(
        name: 'Opponent',
        rankPoints: 1200,
        rankTier: 'Bạc',
        heroId: 'george',
        isBot: false,
      );

      final user1Game = PvpArenaGame(
        opponentInfo: oppInfo,
        playerCurrentRp: 1200,
        isOnline: true,
        isPlayerOne: true,
      );
      final user2Game = PvpArenaGame(
        opponentInfo: oppInfo,
        playerCurrentRp: 1200,
        isOnline: true,
        isPlayerOne: false,
      );

      PvpMatchResult? user1Result;
      PvpMatchResult? user2Result;
      user1Game.onMatchFinished = (res) => user1Result = res;
      user2Game.onMatchFinished = (res) => user2Result = res;

      // Both players enter fighting state for Round 1
      user1Game.matchState = PvpMatchState.fighting;
      user2Game.matchState = PvpMatchState.fighting;

      // User 1 defeats User 2 in Round 1
      user1Game.bot.currentHp = 0;
      user1Game.update(0.016); // triggers _adjudicateRound on User 1
      expect(user1Game.matchState, equals(PvpMatchState.roundEnd));
      expect(user1Game.playerWins, equals(1));

      // User 2 receives User 1's snapshot -> User 2 immediately enters roundEnd (lost Round 1)
      user2Game.applyOpponentSnapshot(user1Game.localSnapshot);
      expect(user2Game.player.currentHp, equals(0));
      expect(user2Game.matchState, equals(PvpMatchState.roundEnd));
      expect(user2Game.opponentWins, equals(1));

      // Advance to Round 2 fighting state on both clients
      user1Game.currentRound = 2;
      user1Game.matchState = PvpMatchState.fighting;
      user1Game.bot.currentHp = 100;
      user2Game.currentRound = 2;
      user2Game.matchState = PvpMatchState.fighting;
      user2Game.player.currentHp = 100;

      // User 1 defeats User 2 in Round 2 and concludes the match
      user1Game.bot.currentHp = 0;
      user1Game.update(0.016); // roundEnd (playerWins = 2)
      user1Game.update(3.0); // concludes match -> matchFinished
      expect(user1Game.matchState, equals(PvpMatchState.matchFinished));
      expect(user1Result, isNotNull);
      expect(user1Result!.isWinner, isTrue);

      // User 2 receives User 1's snapshot -> User 2 immediately concludes match with Defeat modal!
      user2Game.applyOpponentSnapshot(user1Game.localSnapshot);
      expect(user2Game.matchState, equals(PvpMatchState.matchFinished));
      expect(user2Result, isNotNull);
      expect(user2Result!.isWinner, isFalse);
    });
  });

  group('5. Chat AI Assistant (FAQ + Keyword NLP)', () {
    test(
      'Answers Vietnamese questions about Level 100, Economy, Party & Assets',
      () {
        final replyLv = ChatAiAssistantService.instance.generateReply(
          'Làm sao để tăng level 100 cho nhân vật?',
        );
        expect(replyLv, contains('100'));

        final replyEco = ChatAiAssistantService.instance.generateReply(
          '1 xu đổi được bao nhiêu vàng?',
        );
        expect(replyEco, contains('1.000 Vàng'));

        final replyParty = ChatAiAssistantService.instance.generateReply(
          'Cách kết bạn và mời bạn bè vào team 4v4?',
        );
        expect(replyParty, contains('Kết Bạn'));

        final replyAsset = ChatAiAssistantService.instance.generateReply(
          'Làm sao thêm file nhân vật map mới vào assets?',
        );
        expect(replyAsset, contains('assets/data/'));
      },
    );
  });
}
