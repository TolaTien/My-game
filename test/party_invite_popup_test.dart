import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/friend_party_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FriendPartyService.instance.partyNotifier.value = null;
    FriendPartyService.instance.incomingInviteNotifier.value = null;
    FriendPartyService.instance.inviteResponseNotifier.value = null;
    PlayerStorage.profileNotifier.value = const PlayerProfile(
      playerName: 'LeaderOne',
      playerCode: 'GR1001',
    );
  });

  group('Party Invite Flow & 5s Popup', () {
    test('inviteFriendToParty sends invite WITHOUT prematurely adding friend to party', () async {
      final service = FriendPartyService.instance;
      const friend = FriendInfo(
        code: 'GR2002',
        name: 'FriendTwo',
        rankPoints: 1200,
        rankTier: 'Bạc',
        selectedHeroId: 'george',
        heroLevel: 5,
        isOnline: true,
      );

      final ok = service.inviteFriendToParty(
        friend,
        preferredMode: PvpGameMode.duo2v2,
      );
      expect(ok, isTrue);

      // Party is created in 2v2 mode, but friend MUST NOT be in members yet!
      final party = service.partyNotifier.value;
      expect(party, isNotNull);
      expect(party!.mode, PvpGameMode.duo2v2);
      expect(party.members, isEmpty);

      // Allow async _syncPartyEverywhere + _saveInviteEverywhere to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      final rawInvite = prefs.getString('gold_rush_shared_invite_GR2002');
      expect(rawInvite, isNotNull);
      final parsed = PartyInvitation.fromJson(
        jsonDecode(rawInvite!) as Map<String, dynamic>,
      );
      expect(parsed.fromCode, 'GR1001');
      expect(parsed.toCode, 'GR2002');
      expect(parsed.partyCode, party.partyCode);
      expect(parsed.status, 'pending');
    });

    testWidgets('LobbyScreen shows 5s top popup for incoming party invitation and auto-dismisses',
        (tester) async {
      tester.view.physicalSize = const Size(1763, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LobbyScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Simulate incoming party invitation
      FriendPartyService.instance.incomingInviteNotifier.value = PartyInvitation(
        id: 'INV_TEST_5S',
        partyCode: 'TEAM777',
        fromCode: 'GR8888',
        fromName: 'BossLeader',
        toCode: 'GR1001',
        toName: 'LeaderOne',
        mode: PvpGameMode.duo2v2,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify 5s popup banner appears with Accept/Decline buttons
      expect(find.text('LỜI MỜI VÀO TỔ ĐỘI'), findsOneWidget);
      expect(find.text('THAM GIA'), findsOneWidget);
      expect(find.text('TỪ CHỐI'), findsOneWidget);

      // Wait past 5 seconds -> popup auto-dismisses
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('LỜI MỜI VÀO TỔ ĐỘI'), findsNothing);

      // Clean up background timers started by LobbyScreen -> FriendPartyService
      await FriendPartyService.instance.setOfflinePresence();
      FriendPartyService.instance.stopPolling();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
