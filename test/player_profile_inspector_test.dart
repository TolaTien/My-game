import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/database_models.dart';
import 'package:my_game/models/friend_party_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/services/database_service.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FriendPartyService.instance.stopPolling();
    FriendPartyService.instance.friendsNotifier.value = [];
    FriendPartyService.instance.incomingFriendRequestsNotifier.value = [];
    FriendPartyService.instance.partyNotifier.value = null;
    FriendPartyService.instance.soloRoomNotifier.value = null;
    FriendPartyService.instance.incomingInviteNotifier.value = null;
    DatabaseService.setInstance(MockDatabaseService());

    await PlayerStorage.saveProfile(
      const PlayerProfile(
        playerName: 'LocalHero',
        playerCode: 'GR1000',
        rankPoints: 1200,
        rankStars: 3,
      ),
      syncCloud: false,
    );
  });

  tearDown(() async {
    await FriendPartyService.instance.setOfflinePresence();
    FriendPartyService.instance.stopPolling();
    FriendPartyService.instance.friendsNotifier.value = [];
    FriendPartyService.instance.incomingFriendRequestsNotifier.value = [];
    FriendPartyService.instance.partyNotifier.value = null;
    FriendPartyService.instance.soloRoomNotifier.value = null;
  });

  Future<void> cleanupLobbyWidget(WidgetTester tester) async {
    await FriendPartyService.instance.setOfflinePresence();
    FriendPartyService.instance.stopPolling();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('Player Profile Inspector (Party Stage & Rank Leaderboard)', () {
    testWidgets(
      'Tapping a non-friend teammate in Lobby party stage shows Add Friend + View Profile and opens full public profile',
      (tester) async {
        tester.view.physicalSize = const Size(1763, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const stranger = FriendInfo(
          code: 'GR9001',
          name: 'DragonSlayer',
          rankPoints: 1930,
          rankStars: 14,
          rankTier: 'Kim Cương',
          selectedHeroId: 'nova_blade',
          heroLevel: 42,
          isOnline: true,
          statusText: 'Đang trong sảnh',
          totalMatches: 10,
          totalWins: 8,
          unlockedHeroCount: 5,
          pveHighestFloor: 12,
        );

        FriendPartyService.instance.partyNotifier.value = const PartyRoomState(
          partyCode: 'TEAM88',
          leaderCode: 'GR1000',
          leaderName: 'LocalHero',
          leaderHeroId: 'george',
          leaderHeroLevel: 10,
          mode: PvpGameMode.duo2v2,
          members: [stranger],
        );

        await tester.pumpWidget(const MaterialApp(home: LobbyScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        final teammateFinder = find.byKey(const Key('party_stage_member_GR9001'));
        expect(teammateFinder, findsOneWidget);

        await tester.tap(teammateFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Non-friend -> BOTH Add Friend and View Profile buttons appear
        expect(find.byKey(const Key('quick_action_add_friend')), findsOneWidget);
        expect(find.byKey(const Key('quick_action_view_profile')), findsOneWidget);
        expect(
          find.byKey(const Key('quick_action_already_friend_badge')),
          findsNothing,
        );

        // Tap View Profile -> opens full public profile dialog
        await tester.tap(find.byKey(const Key('quick_action_view_profile')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final profileDialogFinder = find.byKey(const Key('player_profile_dialog'));
        expect(profileDialogFinder, findsOneWidget);
        expect(find.text('HỒ SƠ NGƯỜI CHƠI'), findsOneWidget);
        expect(
          find.descendant(
            of: profileDialogFinder,
            matching: find.text('DragonSlayer'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: profileDialogFinder,
            matching: find.text('GR9001'),
          ),
          findsOneWidget,
        );
        expect(find.text('RANK KIM CƯƠNG'), findsOneWidget);
        expect(find.text('2/3 Sao'), findsOneWidget);
        expect(find.text('1930 RP'), findsOneWidget);
        expect(find.text('80%'), findsOneWidget);
        expect(find.text('8/10'), findsOneWidget);
        expect(find.text('Tầng 12'), findsOneWidget);
        expect(find.byKey(const Key('profile_dialog_add_friend')), findsOneWidget);
        // Must NOT leak private Gold / Xu labels inside PlayerProfileDialog
        expect(
          find.descendant(of: profileDialogFinder, matching: find.text('Vàng')),
          findsNothing,
        );
        expect(
          find.descendant(of: profileDialogFinder, matching: find.text('Xu')),
          findsNothing,
        );

        await cleanupLobbyWidget(tester);
      },
    );

    testWidgets(
      'Tapping an already-friend teammate in Lobby party stage hides Add Friend and shows View Profile',
      (tester) async {
        tester.view.physicalSize = const Size(1763, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const buddy = FriendInfo(
          code: 'GR2002',
          name: 'BestBuddy',
          rankPoints: 1500,
          rankStars: 7,
          rankTier: 'Vàng',
          selectedHeroId: 'ranger',
          heroLevel: 25,
          isOnline: true,
        );

        await tester.pumpWidget(const MaterialApp(home: LobbyScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Seed friend & party state after LobbyScreen.initState() finishes loading prefs
        FriendPartyService.instance.friendsNotifier.value = const [buddy];
        FriendPartyService.instance.partyNotifier.value = const PartyRoomState(
          partyCode: 'TEAM77',
          leaderCode: 'GR1000',
          leaderName: 'LocalHero',
          leaderHeroId: 'george',
          leaderHeroLevel: 10,
          mode: PvpGameMode.duo2v2,
          members: [buddy],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byKey(const Key('party_stage_member_GR2002')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(find.byKey(const Key('quick_action_add_friend')), findsNothing);
        expect(
          find.byKey(const Key('quick_action_already_friend_badge')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('quick_action_view_profile')), findsOneWidget);

        await cleanupLobbyWidget(tester);
      },
    );

    testWidgets(
      'Tapping a non-friend ranked player in Leaderboard shows Add Friend + View Profile and sends friend request',
      (tester) async {
        tester.view.physicalSize = const Size(1763, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const rankedFriendInfo = FriendInfo(
          code: 'GR8008',
          name: 'TopChallenger',
          rankPoints: 2210,
          rankStars: 22,
          rankTier: 'Thách Đấu',
          selectedHeroId: 'valeria',
          heroLevel: 88,
          isOnline: true,
          statusText: 'Đang Online',
          totalMatches: 20,
          totalWins: 17,
          unlockedHeroCount: 7,
          pveHighestFloor: 25,
          isChallengerTop10: true,
          serverRank: 1,
        );

        final rankedEntry = LeaderboardEntry(
          uid: 'uid_top_1',
          name: 'TopChallenger',
          playerCode: 'GR8008',
          rankPoints: 2210,
          rankStars: 22,
          rankTier: 'Thách Đấu',
          winRate: '85%',
          rankNumber: 1,
          lastUpdated: DateTime.now(),
          isLocalPlayer: false,
          heroId: 'valeria',
          heroLevel: 88,
          totalMatches: 20,
          totalWins: 17,
          unlockedHeroCount: 7,
          pveHighestFloor: 25,
        );

        SharedPreferences.setMockInitialValues({
          MockDatabaseService.storageKeyLeaderboard: jsonEncode([
            rankedEntry.toJson(),
          ]),
          'big_war_shared_directory_GR8008': jsonEncode(
            rankedFriendInfo.toJson(),
          ),
        });

        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'LocalHero',
            playerCode: 'GR1000',
            rankPoints: 1200,
            rankStars: 3,
          ),
          syncCloud: false,
        );

        final mockDb = MockDatabaseService();
        await mockDb.initialize();
        DatabaseService.setInstance(mockDb);

        await tester.pumpWidget(const MaterialApp(home: LobbyScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Open Rank Leaderboard from left sidebar RANKING button
        final rankBtnFinder = find.text('RANKING');
        expect(rankBtnFinder, findsOneWidget);
        await tester.tap(rankBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Tap on the ranked non-friend player row
        final entryFinder = find.byKey(const Key('leaderboard_entry_uid_top_1'));
        expect(entryFinder, findsOneWidget);
        await tester.tap(entryFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        // Verify quick action popup displays BOTH Add Friend and View Profile
        final addBtn = find.byKey(const Key('quick_action_add_friend'));
        final viewBtn = find.byKey(const Key('quick_action_view_profile'));
        expect(addBtn, findsOneWidget);
        expect(viewBtn, findsOneWidget);

        // Tap Add Friend -> sends real friend request to GR8008
        await tester.tap(addBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('ĐÃ GỬI'), findsOneWidget);

        // Verify friend request was persisted to target's inbox
        final prefs = await SharedPreferences.getInstance();
        final rawReqs = prefs.getString('big_war_shared_friend_req_GR8008');
        expect(rawReqs, isNotNull);
        expect(rawReqs, contains('GR1000'));

        // Tap View Profile -> opens full profile dialog with Challenger Top 1 badge
        await tester.tap(viewBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byKey(const Key('player_profile_dialog')), findsOneWidget);
        expect(find.text('RANK THÁCH ĐẤU'), findsOneWidget);
        expect(find.text('TOP #1'), findsOneWidget);
        expect(find.text('85%'), findsOneWidget);
        expect(find.text('17/20'), findsOneWidget);
        expect(find.text('Tầng 25'), findsOneWidget);

        await cleanupLobbyWidget(tester);
      },
    );
  });
}
