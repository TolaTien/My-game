import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/database_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/services/database_service.dart';
import 'package:my_game/services/firebase_database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/leaderboard_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      MockDatabaseService.storageKeyLeaderboard: jsonEncode(
        leaderboardFixture().map((entry) => entry.toJson()).toList(),
      ),
    });
    DatabaseService.setInstance(MockDatabaseService());
  });

  group('Group 1: Database Models Serialization & Round-Trip', () {
    test('LeaderboardEntry toJson and fromJson round-trip', () {
      final now = DateTime.now();
      final entry = LeaderboardEntry(
        uid: 'user_123',
        name: 'ChiếnThần_VN',
        rankPoints: 2450,
        rankTier: 'Thách Đấu',
        winRate: '68%',
        rankNumber: 3,
        lastUpdated: now,
        isLocalPlayer: true,
        heroId: 'ninja',
      );

      final json = entry.toJson();
      expect(json['uid'], equals('user_123'));
      expect(json['name'], equals('ChiếnThần_VN'));
      expect(json['rankPoints'], equals(2450));
      expect(json['rankTier'], equals('Thách Đấu'));
      expect(json['winRate'], equals('68%'));
      expect(json['rankNumber'], equals(3));
      expect(json['isLocalPlayer'], isTrue);
      expect(json['heroId'], equals('ninja'));

      final restored = LeaderboardEntry.fromJson(json);
      expect(restored.uid, equals(entry.uid));
      expect(restored.name, equals(entry.name));
      expect(restored.rankPoints, equals(entry.rankPoints));
      expect(restored.rankTier, equals(entry.rankTier));
      expect(restored.winRate, equals(entry.winRate));
      expect(restored.rankNumber, equals(entry.rankNumber));
      expect(restored.isLocalPlayer, equals(entry.isLocalPlayer));
      expect(restored.heroId, equals(entry.heroId));

      // Test alias getters
      expect(restored.userId, equals(entry.uid));
      expect(restored.playerName, equals(entry.name));
      expect(restored.rank, equals(entry.rankNumber));
    });

    test('LeaderboardEntry copyWith works correctly', () {
      final entry = LeaderboardEntry(
        uid: 'user_1',
        name: 'Hero1',
        rankPoints: 1500,
        rankTier: 'Vàng',
        winRate: '50%',
        rankNumber: 10,
        lastUpdated: DateTime.now(),
      );

      final modified = entry.copyWith(
        rankPoints: 1650,
        rankTier: 'Bạch Kim',
        rankNumber: 8,
      );

      expect(modified.rankPoints, equals(1650));
      expect(modified.rankTier, equals('Bạch Kim'));
      expect(modified.rankNumber, equals(8));
      expect(modified.name, equals('Hero1'));
    });

    test('PvpQueueTicket toJson and fromJson round-trip', () {
      final now = DateTime.now();
      final ticket = PvpQueueTicket(
        ticketId: 'ticket_999',
        userId: 'usr_abc',
        playerName: 'Gamer_Pro',
        rankPoints: 1720,
        timestamp: now,
        rankTier: 'Bạch Kim',
        heroId: 'ranger',
      );

      final json = ticket.toJson();
      expect(json['ticketId'], equals('ticket_999'));
      expect(json['userId'], equals('usr_abc'));
      expect(json['playerName'], equals('Gamer_Pro'));
      expect(json['rankPoints'], equals(1720));
      expect(json['rankTier'], equals('Bạch Kim'));
      expect(json['heroId'], equals('ranger'));

      final restored = PvpQueueTicket.fromJson(json);
      expect(restored.ticketId, equals(ticket.ticketId));
      expect(restored.userId, equals(ticket.userId));
      expect(restored.playerName, equals(ticket.playerName));
      expect(restored.rankPoints, equals(ticket.rankPoints));
      expect(restored.rankTier, equals(ticket.rankTier));
      expect(restored.heroId, equals(ticket.heroId));
    });

    test('PvpMatchSession toJson and fromJson round-trip', () {
      final p1 = PvpOpponentInfo(
        name: 'PlayerOne',
        rankPoints: 1600,
        rankTier: 'Bạch Kim',
        heroId: 'george',
        isBot: false,
      );
      final p2 = PvpOpponentInfo(
        name: 'BotRanger',
        rankPoints: 1580,
        rankTier: 'Vàng',
        heroId: 'ranger',
        isBot: true,
        difficulty: BotDifficulty.goldPlatinum,
      );

      final session = PvpMatchSession(
        sessionId: 'session_777',
        player1: p1,
        player2: p2,
        state: PvpMatchSessionState.matched,
        createdAt: DateTime.now(),
        matchedAt: DateTime.now(),
      );

      final json = session.toJson();
      expect(json['sessionId'], equals('session_777'));
      expect(json['state'], equals('matched'));
      expect(json['player1']['name'], equals('PlayerOne'));
      expect(json['player2']['name'], equals('BotRanger'));

      final restored = PvpMatchSession.fromJson(json);
      expect(restored.sessionId, equals('session_777'));
      expect(restored.state, equals(PvpMatchSessionState.matched));
      expect(restored.player1.name, equals('PlayerOne'));
      expect(restored.player2?.name, equals('BotRanger'));
      expect(restored.player2?.difficulty, equals(BotDifficulty.goldPlatinum));
    });
  });

  group('Group 2: DatabaseService Singleton & Service Locator', () {
    test('Default DatabaseService instance returns MockDatabaseService', () {
      final instance = DatabaseService.instance;
      expect(instance, isA<MockDatabaseService>());
      expect(instance.isOnline, isFalse);
    });

    test('DatabaseService.setInstance properly overrides singleton', () {
      final customMock = MockDatabaseService();
      DatabaseService.setInstance(customMock);
      expect(identical(DatabaseService.instance, customMock), isTrue);
    });
  });

  group('Group 3: MockDatabaseService 20 Seeded Players & Persistence', () {
    test(
      'Production default stays empty rather than inventing ranked players',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = MockDatabaseService();
        await service.initialize();
        expect(MockDatabaseService.createDefaultLeaderboard(), isEmpty);
        expect(await service.streamTopLeaderboard().first, isEmpty);
      },
    );

    test(
      'Old auto-seeded entries are removed when loading persisted ranks',
      () async {
        final fixture = leaderboardFixture();
        final oldSeed = fixture.first.toJson()..['uid'] = 'seed_1';
        SharedPreferences.setMockInitialValues({
          MockDatabaseService.storageKeyLeaderboard: jsonEncode([
            oldSeed,
            fixture.last.toJson(),
          ]),
        });
        final service = MockDatabaseService();
        await service.initialize();
        final loaded = await service.streamTopLeaderboard().first;
        expect(loaded.length, 1);
        expect(loaded.single.uid, fixture.last.uid);
      },
    );

    test(
      'Loads exactly 20 explicitly supplied leaderboard fixture players',
      () async {
        final service = MockDatabaseService();
        await service.initialize();

        final entries = await service.streamTopLeaderboard(limit: 20).first;
        expect(entries.length, equals(20));

        // Rank #1 is BáĐạo99 with 2850 RP
        expect(entries.first.name, equals('BáĐạo99'));
        expect(entries.first.rankPoints, equals(2850));
        expect(entries.first.rankTier, equals('Thách Đấu'));
        expect(entries.first.rankNumber, equals(1));

        // Rank #20 is ĐạiHiệpBấtTử with 1290 RP
        expect(entries.last.name, equals('ĐạiHiệpBấtTử'));
        expect(entries.last.rankPoints, equals(1290));
        expect(entries.last.rankNumber, equals(20));

        // Ranks are strictly 1..20 sequential
        for (int i = 0; i < entries.length; i++) {
          expect(entries[i].rankNumber, equals(i + 1));
        }

        // Rank points are strictly descending
        for (int i = 0; i < entries.length - 1; i++) {
          expect(entries[i].rankPoints >= entries[i + 1].rankPoints, isTrue);
        }
      },
    );

    test('Leaderboard persists to SharedPreferences', () async {
      final service1 = MockDatabaseService();
      await service1.initialize();

      final prefs = await SharedPreferences.getInstance();
      final storedData = prefs.getString(
        MockDatabaseService.storageKeyLeaderboard,
      );
      expect(storedData, isNotNull);
      expect(storedData!.contains('BáĐạo99'), isTrue);

      // A new service instance restores the persisted list
      final service2 = MockDatabaseService();
      await service2.initialize();
      final entries2 = await service2.streamTopLeaderboard(limit: 20).first;
      expect(entries2.length, equals(20));
      expect(entries2.first.name, equals('BáĐạo99'));
    });
  });

  group('Group 4: Dynamic Re-ranking & Real-Time Stream Updates', () {
    test(
      'Submitting top score (2900 RP) places local player at Rank #1',
      () async {
        final service = MockDatabaseService();
        await service.initialize();

        final profile = PlayerProfile(
          playerName: 'VuaChiếnBinh',
          rankPoints: 2900,
        );

        await service.updateLeaderboard(profile);

        final topEntries = await service.streamTopLeaderboard(limit: 20).first;
        expect(topEntries.first.name, equals('VuaChiếnBinh'));
        expect(topEntries.first.rankPoints, equals(2900));
        expect(topEntries.first.rankNumber, equals(1));
        expect(topEntries.first.isLocalPlayer, isTrue);

        // Previous #1 BáĐạo99 is pushed to Rank #2
        expect(topEntries[1].name, equals('BáĐạo99'));
        expect(topEntries[1].rankNumber, equals(2));
      },
    );

    test('Submitting mid-tier score (1750 RP) dynamically inserts between Rank 13 and 14', () async {
      final service = MockDatabaseService();
      await service.initialize();

      final profile = PlayerProfile(
        playerName: 'ChiếnBinhTânBinh',
        rankPoints: 1750,
      );

      await service.updateLeaderboard(profile);

      final entries = await service.streamTopLeaderboard(limit: 20).first;
      final playerEntry = entries.firstWhere(
        (e) => e.name == 'ChiếnBinhTânBinh',
      );

      // 1760 (HắcBạchCôngTử) > 1750 > 1710 (TiểuLongNữ)
      expect(playerEntry.rankNumber, equals(14));
      expect(playerEntry.isLocalPlayer, isTrue);

      // Sequentiality check
      for (int i = 0; i < entries.length; i++) {
        expect(entries[i].rankNumber, equals(i + 1));
      }
    });

    test(
      'Updating profile again updates existing entry without duplication',
      () async {
        final service = MockDatabaseService();
        await service.initialize();

        final profile1 = PlayerProfile(
          playerName: 'LocalHero',
          rankPoints: 1600,
        );
        await service.updateLeaderboard(profile1);

        final profile2 = PlayerProfile(
          playerName: 'LocalHero',
          rankPoints: 2250,
        );
        await service.updateLeaderboard(profile2);

        final entries = await service.streamTopLeaderboard(limit: 25).first;
        final matching = entries.where((e) => e.name == 'LocalHero').toList();
        expect(matching.length, equals(1));
        expect(matching.first.rankPoints, equals(2250));
      },
    );
  });

  group('Group 5: Matchmaking Queue Simulation Lifecycle', () {
    test(
      'joinMatchmakingQueue creates searching session then pairs with bot',
      () async {
        final service = MockDatabaseService(
          matchSimulatedDelay: const Duration(milliseconds: 50),
        );
        await service.initialize();

        final ticket = PvpQueueTicket(
          ticketId: 'test_ticket_01',
          userId: 'player_user_1',
          playerName: 'Knight_Tester',
          rankPoints: 1650,
          timestamp: DateTime.now(),
          rankTier: 'Bạch Kim',
          heroId: 'tanker',
        );

        await service.joinMatchmakingQueue(ticket);

        final sessionId = 'session_test_ticket_01';
        final stream = service.streamMatchSession(sessionId);

        // Verify immediate session state is searching
        final initialSession = await stream.first;
        expect(initialSession, isNotNull);
        expect(initialSession!.state, equals(PvpMatchSessionState.searching));
        expect(initialSession.player1.name, equals('Knight_Tester'));
        expect(initialSession.player2, isNull);

        // Wait for simulated bot matching
        await Future.delayed(const Duration(milliseconds: 100));

        final matchedSession = await service
            .streamMatchSession(sessionId)
            .first;
        expect(matchedSession!.state, equals(PvpMatchSessionState.matched));
        expect(matchedSession.player2, isNotNull);
        expect(matchedSession.player2!.isBot, isTrue);
        expect(matchedSession.matchedAt, isNotNull);
      },
    );

    test('leaveMatchmakingQueue cancels searching queue session', () async {
      final service = MockDatabaseService(
        matchSimulatedDelay: const Duration(milliseconds: 500),
      );
      await service.initialize();

      final ticket = PvpQueueTicket(
        ticketId: 'cancel_ticket_02',
        userId: 'player_user_2',
        playerName: 'CautiousPlayer',
        rankPoints: 1300,
        timestamp: DateTime.now(),
      );

      await service.joinMatchmakingQueue(ticket);
      final sessionId = 'session_cancel_ticket_02';

      // Cancel before match delay completes
      await service.leaveMatchmakingQueue('player_user_2');

      final session = await service.streamMatchSession(sessionId).first;
      expect(session!.state, equals(PvpMatchSessionState.cancelled));
    });
  });

  group('Group 6: Profile Loading, Saving & Backward Compatibility', () {
    test('saveProfile and loadProfile round-trip cleanly', () async {
      final service = MockDatabaseService();
      await service.initialize();

      final profile = PlayerProfile(
        playerName: 'SavedHero',
        gold: 8888,
        diamonds: 99,
        rankPoints: 2100,
        selectedHeroId: 'ranger',
      );

      await service.saveProfile(profile);

      final loaded = await service.loadProfile('SavedHero');
      expect(loaded, isNotNull);
      expect(loaded!.playerName, equals('SavedHero'));
      expect(loaded.gold, equals(8888));
      expect(loaded.diamonds, equals(99));
      expect(loaded.rankPoints, equals(2100));

      final loadedByLocal = await service.loadProfile('local_player');
      expect(loadedByLocal, isNotNull);
      expect(loadedByLocal!.playerName, equals('SavedHero'));
    });

    test('loadProfile returns null for non-existent player', () async {
      final service = MockDatabaseService();
      await service.initialize();

      final nonExistent = await service.loadProfile('GhostPlayer999');
      expect(nonExistent, isNull);
    });

    test('Backward compatibility methods operate as expected', () async {
      final service = MockDatabaseService();
      await service.initialize();

      // syncPlayerProfile
      final profile = PlayerProfile(playerName: 'LegacyHero', rankPoints: 1400);
      await service.syncPlayerProfile(profile);

      // fetchLeaderboard
      final legacyList = await service.fetchLeaderboard();
      expect(legacyList, isNotEmpty);
      expect(legacyList.length, inInclusiveRange(10, 20));
      expect(legacyList.first.containsKey('name'), isTrue);
      expect(legacyList.first.containsKey('rankPoints'), isTrue);
      expect(legacyList.first.containsKey('rankTier'), isTrue);

      // listenToMatch
      final matchStream = service.listenToMatch('match_legacy');
      expect(matchStream, isNotNull);

      // submitMatchAction
      await service.submitMatchAction('match_1', 'cast_spell', {'skill': 1});
    });
  });

  group('Group 7: FirebaseDatabaseService Shielding & Fallback', () {
    test('FirebaseDatabaseService isOnline defaults to false and initializes mock safely', () async {
      final firebaseService = FirebaseDatabaseService();
      expect(firebaseService.isOnline, isFalse);

      await firebaseService.initialize();
      expect(firebaseService.isOnline, isFalse);

      final topEntries = await firebaseService
          .streamTopLeaderboard(limit: 5)
          .first;
      expect(topEntries.length, equals(5));
      expect(topEntries.first.name, equals('BáĐạo99'));
    });

    test('FirebaseDatabaseService delegates operations safely without throwing exceptions', () async {
      final firebaseService = FirebaseDatabaseService(
        fallback: MockDatabaseService(
          matchSimulatedDelay: const Duration(milliseconds: 50),
        ),
      );
      await firebaseService.initialize();

      final profile = PlayerProfile(playerName: 'CloudHero', rankPoints: 2300);
      await firebaseService.saveProfile(profile);

      final loaded = await firebaseService.loadProfile('CloudHero');
      expect(loaded, isNotNull);
      expect(loaded!.playerName, equals('CloudHero'));

      final ticket = PvpQueueTicket(
        ticketId: 'fb_ticket_1',
        userId: 'fb_user_1',
        playerName: 'CloudHero',
        rankPoints: 2300,
        timestamp: DateTime.now(),
      );
      await firebaseService.joinMatchmakingQueue(ticket);
      await firebaseService.leaveMatchmakingQueue('fb_user_1');

      final session = await firebaseService
          .streamMatchSession('session_fb_ticket_1')
          .first;
      expect(session!.state, equals(PvpMatchSessionState.cancelled));

      final legacyLeaderboard = await firebaseService.fetchLeaderboard();
      expect(legacyLeaderboard, isNotEmpty);
    });
  });
}
