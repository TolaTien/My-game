import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/friend_party_models.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/models/pvp_match.dart';
import 'package:my_game/registry/asset_registry.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/screens/pvp_arena_screen.dart';
import 'package:my_game/screens/solo_room_dialog.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FriendPartyService.instance.stopPolling();
    FriendPartyService.instance.partyNotifier.value = null;
    FriendPartyService.instance.soloRoomNotifier.value = null;
    FriendPartyService.instance.soloRoomNoticeNotifier.value = null;
    FriendPartyService.instance.incomingInviteNotifier.value = null;
    await PlayerStorage.saveProfile(
      const PlayerProfile(
        playerName: 'HostPlayer',
        playerCode: 'GR1111',
        gold: 500,
        rankPoints: 1000,
        rankStars: 0,
      ),
      syncCloud: false,
    );
  });

  tearDown(() async {
    FriendPartyService.instance.stopPolling();
    FriendPartyService.instance.soloRoomNotifier.value = null;
    FriendPartyService.instance.partyNotifier.value = null;
  });

  group('Custom 4v4 2-Team Room (Invite, Team Arrange, Ready & Start)', () {
    test(
      'Default 4v4 room has 4 slots per team, supports free team arrangement & requires all guests Ready before Host starts',
      () async {
        final service = FriendPartyService.instance;

        // 1. Host creates default 4v4 room (4 Blue slots + 4 Red slots)
        final created = await service.createSoloRoom(
          betGold: 100,
          selectedMapId: 'sunken_golden_sanctum',
        );
        expect(created.blueSlots.length, 4);
        expect(created.redSlots.length, 4);
        expect(created.blueCount, 1);
        expect(created.redCount, 0);
        expect(created.canHostStart, isFalse); // Red team empty!

        final roomCode = created.roomCode;

        // 2. Player 2 joins -> auto-balanced into Red Slot 0 (1v1)
        service.stopPolling();
        service.soloRoomNotifier.value = null;
        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'FriendTwo',
            playerCode: 'GR2222',
            gold: 400,
          ),
          syncCloud: false,
        );
        final afterP2 = await service.joinSoloRoomByCode(roomCode);
        expect(afterP2.blueCount, 1);
        expect(afterP2.redCount, 1);
        expect(afterP2.teamOf('GR2222'), 'red');
        expect(afterP2.canHostStart, isFalse); // P2 not ready yet!

        // 3. Player 2 invites Player 3 directly into Blue Team
        const friendThree = FriendInfo(
          code: 'GR3333',
          name: 'FriendThree',
          rankPoints: 1200,
          rankTier: 'Bạc',
          selectedHeroId: 'ranger',
          isOnline: true,
        );
        final inviteSent = await service.inviteFriendToSoloRoom(
          friendThree,
          preferredTeam: 'blue',
        );
        expect(inviteSent, isTrue);

        // Player 3 accepts invitation -> lands in Blue Team (now 2v1!)
        service.stopPolling();
        service.soloRoomNotifier.value = null;
        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'FriendThree',
            playerCode: 'GR3333',
            gold: 400,
          ),
          syncCloud: false,
        );
        await service.respondToInvitation(
          PartyInvitation(
            id: 'SINV_TEST',
            partyCode: roomCode,
            fromCode: 'GR2222',
            fromName: 'FriendTwo',
            toCode: 'GR3333',
            toName: 'FriendThree',
            mode: PvpGameMode.squad4v4,
            timestamp: 1000,
            isCustomRoom: true,
            preferredTeam: 'blue',
          ),
          accept: true,
        );
        expect(service.soloRoomNotifier.value!.teamOf('GR3333'), 'blue');
        expect(service.soloRoomNotifier.value!.matchupLabel, '2v1');

        // 4. Player 3 switches freely to Red Slot #2 -> now 1v2!
        final movedOk = await service.switchSoloTeamSlot(
          targetTeam: 'red',
          targetSlot: 2,
        );
        expect(movedOk, isTrue);
        expect(service.soloRoomNotifier.value!.teamOf('GR3333'), 'red');
        expect(service.soloRoomNotifier.value!.slotIndexOf('GR3333'), 2);
        expect(service.soloRoomNotifier.value!.matchupLabel, '1v2');

        // 5. Player 3 marks Ready, but Player 2 is NOT Ready yet -> Host still cannot start
        expect(await service.toggleSoloGuestReady(), isTrue);
        expect(service.soloRoomNotifier.value!.canHostStart, isFalse);

        // 6. Player 2 marks Ready -> ALL non-host players are Ready -> Host CAN start!
        final stateAfterP3Ready = service.soloRoomNotifier.value!;
        service.stopPolling();
        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'FriendTwo',
            playerCode: 'GR2222',
            gold: 400,
          ),
          syncCloud: false,
        );
        service.soloRoomNotifier.value = stateAfterP3Ready;
        expect(await service.toggleSoloGuestReady(), isTrue);
        expect(service.soloRoomNotifier.value!.areAllGuestsReady, isTrue);
        expect(service.soloRoomNotifier.value!.canHostStart, isTrue);

        // 7. Host presses Start Game -> matchStatus becomes 'in_match'
        final stateAllReady = service.soloRoomNotifier.value!;
        service.stopPolling();
        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'HostPlayer',
            playerCode: 'GR1111',
            gold: 500,
          ),
          syncCloud: false,
        );
        service.soloRoomNotifier.value = stateAllReady;
        final started = await service.startSoloDuelMatch();
        expect(started, isNotNull);
        expect(started!.matchStatus, 'in_match');
        expect(started.activeMatchRoomId, isNotEmpty);
      },
    );

    testWidgets(
      'SoloRoomDialog renders 4 Blue slots vs 4 Red slots and allows switching teams',
      (tester) async {
        tester.view.physicalSize = const Size(1763, 892);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(const MaterialApp(home: LobbyScreen()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byKey(const Key('sidebar_open_solo_room_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(SoloRoomDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('solo_create_room_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Verify 4v4 2-team headers
        expect(find.text('ĐỘI XANH (1/4)'), findsOneWidget);
        expect(find.text('ĐỘI ĐỎ (0/4)'), findsOneWidget);

        // Host clicks empty slot 0 on Red Team -> switches from Blue to Red!
        await tester.tap(find.byKey(const Key('solo_slot_red_0')));
        await tester.pump();

        expect(find.text('ĐỘI XANH (0/4)'), findsOneWidget);
        expect(find.text('ĐỘI ĐỎ (1/4)'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        FriendPartyService.instance.stopPolling();
      },
    );

    testWidgets(
      'PvpArenaScreen runs 2v2 Custom Room without extra AI bots, splits 800G pot fairly, and preserves Rank Stars',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await PlayerStorage.saveProfile(
          const PlayerProfile(
            playerName: 'HostPlayer',
            playerCode: 'GR1111',
            gold: 500,
            rankPoints: 1265,
            rankStars: 4,
          ),
          syncCloud: false,
        );

        final mapId = GameAssetRegistry.instance.availableMatchMaps.first.id;
        const matchRoomId = 'solo_SOLO4444_2002';
        final room2v2 = SoloDuelRoomState(
          roomCode: 'SOLO4444',
          hostCode: 'GR1111',
          hostName: 'HostPlayer',
          blueSlots: const [
            FriendInfo(
              code: 'GR1111',
              name: 'HostPlayer',
              rankPoints: 1265,
              rankTier: 'Bạc',
              selectedHeroId: 'george',
              heroLevel: 5,
              isOnline: true,
            ),
            FriendInfo(
              code: 'GR2222',
              name: 'BlueMate',
              rankPoints: 1300,
              rankTier: 'Bạc',
              selectedHeroId: 'ranger',
              heroLevel: 5,
              isOnline: true,
            ),
            null,
            null,
          ],
          redSlots: const [
            FriendInfo(
              code: 'GR3333',
              name: 'RedOne',
              rankPoints: 1400,
              rankTier: 'Vàng',
              selectedHeroId: 'ninja',
              heroLevel: 5,
              isOnline: true,
            ),
            FriendInfo(
              code: 'GR4444',
              name: 'RedTwo',
              rankPoints: 1400,
              rankTier: 'Vàng',
              selectedHeroId: 'tanker',
              heroLevel: 5,
              isOnline: true,
            ),
            null,
            null,
          ],
          readyCodes: const ['GR2222', 'GR3333', 'GR4444'],
          betGold: 200, // 4 players * 200G = 800G total pot
          selectedMapId: mapId,
          resolvedMapId: mapId,
          matchStatus: 'in_match',
          activeMatchRoomId: matchRoomId,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: PvpArenaScreen(
              initialMode: PvpGameMode.solo1v1,
              soloRoom: room2v2,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // 1. 200G escrowed immediately (500 -> 300), and HUD shows exact 2/2 vs 2/2 (no extra 4v4 bots!)
        expect(PlayerStorage.currentProfile.gold, 300);
        expect(find.text('2/2'), findsNWidgets(2));
        expect(find.text('ĐANG CHỜ ĐỐI THỦ VÀO TRẬN...'), findsOneWidget);

        // 2. All 3 other human players connect & mark ready
        for (final peer in ['GR2222', 'GR3333', 'GR4444']) {
          await FriendPartyService.instance.writePartyPlayerState(
            matchRoomId,
            peer,
            {
              'x': 760.0,
              'y': 320.0,
              'hp': 300.0,
              'maxHp': 300.0,
              'ready': true,
              'connected': true,
            },
          );
        }
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('ĐANG CHỜ ĐỐI THỦ VÀO TRẬN...'), findsNothing);
        expect(find.textContaining('PHÒNG 2v2 • QUỸ 800G'), findsOneWidget);

        // 3. Both Red team players disconnect -> Blue team wins by forfeit!
        await FriendPartyService.instance
            .leaveSoloMatchRoom(matchRoomId, 'GR3333');
        await FriendPartyService.instance
            .leaveSoloMatchRoom(matchRoomId, 'GR4444');
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 100));

        // 4. 800G pot split across 2 Blue winners = 400G each -> 300 + 400 = 700G (+200G profit), Rank Stars = 4
        expect(PlayerStorage.currentProfile.gold, 700);
        expect(PlayerStorage.currentProfile.rankStars, 4);
        expect(find.text('KẾT QUẢ PHÒNG ĐẤU CƯỢC VÀNG'), findsOneWidget);
        expect(find.text('+200 VÀNG LỜI (NHẬN 400G)'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        FriendPartyService.instance.stopPolling();
      },
    );
  });
}
