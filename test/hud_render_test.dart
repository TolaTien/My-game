import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/hud/game_hud.dart';
import 'package:my_game/game/hud/virtual_joystick.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/screens/game_play_screen.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/screens/pvp_arena_screen.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:my_game/services/friend_party_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('GamePlayScreen renders clean touch buttons on Mobile', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(const MaterialApp(home: GamePlayScreen()));
      await tester.pump(const Duration(milliseconds: 500));

      // Joystick and ATK buttons exist
      expect(find.byType(VirtualJoystick), findsOneWidget);
      expect(find.text('ATK'), findsOneWidget);

      // No desktop hotkey badges on mobile
      expect(find.text('SPACE'), findsNothing);
      expect(find.text('W A S D'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'GamePlayScreen renders joystick and action buttons with hotkeys on Desktop/Web',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(const MaterialApp(home: GamePlayScreen()));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(VirtualJoystick), findsOneWidget);
        expect(find.text('SPACE'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('W A S D'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'GamePlayScreen toggles on-screen touch controls on Desktop/Web',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(const MaterialApp(home: GamePlayScreen()));
        await tester.pump(const Duration(milliseconds: 500));

        // Initially visible
        expect(find.byType(VirtualJoystick), findsOneWidget);

        // Tap toggle button to hide touch controls
        final toggleFinder = find.byKey(
          const Key('toggle_touch_controls_button'),
        );
        expect(toggleFinder, findsOneWidget);
        await tester.tap(toggleFinder);
        await tester.pump();

        // Now touch controls are hidden, keyboard hint bar is shown
        expect(find.byType(VirtualJoystick), findsNothing);
        expect(find.textContaining('Di chuyển: WASD'), findsOneWidget);

        // Tap toggle again to restore
        await tester.tap(toggleFinder);
        await tester.pump();

        expect(find.byType(VirtualJoystick), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('PvpArenaScreen renders matchmaking view safely without crash', (
    tester,
  ) async {
    addTearDown(FriendPartyService.instance.stopPolling);
    await tester.pumpWidget(const MaterialApp(home: PvpArenaScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PvpArenaScreen), findsOneWidget);
    expect(find.textContaining('ĐANG TÌM TRẬN ĐỐI KHÁNG'), findsOneWidget);

    // Tap bot button
    final botBtn = find.text('GHÉP NGAY (AI BOT)');
    expect(botBtn, findsOneWidget);
    await tester.tap(botBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    FriendPartyService.instance.stopPolling();
  });

  testWidgets('PvE pause freezes the game until resume or confirmed exit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const GamePlayScreen()),
              ),
              child: const Text('Open PvE'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open PvE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final hud = tester.widget<GameHudOverlay>(find.byType(GameHudOverlay));

    Future<void> tapKey(String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await tapKey('pve_pause_button');
    expect(find.byType(GamePlayScreen), findsOneWidget);
    expect(hud.game.paused, isTrue);
    expect(hud.keyboardController!.isEnabled, isFalse);
    await tapKey('pause_resume_button');
    expect(hud.game.paused, isFalse);
    expect(hud.keyboardController!.isEnabled, isTrue);

    await tapKey('pve_pause_button');
    await tapKey('pause_leave_button');
    expect(hud.game.paused, isTrue);
    await tapKey('pause_leave_cancel_button');
    expect(find.byType(GamePlayScreen), findsOneWidget);
    expect(hud.game.paused, isFalse);

    await tapKey('pve_pause_button');
    await tapKey('pause_leave_button');
    await tapKey('pause_leave_confirm_button');
    await tester.pumpAndSettle();
    expect(find.byType(GamePlayScreen), findsNothing);
    expect(find.text('Open PvE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Compact PvE map label stays below the status bars without a duplicate banner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(640, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: GamePlayScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final badge = find.byKey(const Key('hud_compact_map_badge'));
      expect(badge, findsOneWidget);
      expect(tester.getTopLeft(badge).dy, greaterThanOrEqualTo(78));
      expect(tester.getSize(badge).width, lessThanOrEqualTo(320));
      expect(find.textContaining('CHIẾN TRƯỜNG:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(844, 390), const Size(640, 320)]) {
    testWidgets('Lobby and shop stay usable at $size', (tester) async {
      addTearDown(FriendPartyService.instance.stopPolling);
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: LobbyScreen()));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.byKey(const Key('lobby_start_button')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('RANKING').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('CỬA HÀNG'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final shop = find.byType(ShopDialog);
      final close = find.byKey(const Key('close_shop_button'));
      expect(close.hitTestable(), findsOneWidget);
      final heroes = find.descendant(of: shop, matching: find.byType(ListView));
      await tester.drag(heroes, const Offset(-480, 0));
      await tester.pump(const Duration(milliseconds: 350));
      final listScrollable = find.descendant(
        of: heroes,
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(listScrollable).position.pixels,
        greaterThan(0),
      );
      for (final tab in ['TRỢ THỦ AI', 'SKIN']) {
        await tester.tap(find.text(tab));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(close);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(shop, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      FriendPartyService.instance.stopPolling();
    });
  }

  testWidgets('Shop converts Xu only after a valid confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final originalProfile = PlayerStorage.currentProfile;
    addTearDown(() => PlayerStorage.profileNotifier.value = originalProfile);
    PlayerStorage.profileNotifier.value = PlayerProfile.defaultProfile()
        .copyWith(xu: 3, gold: 50);
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ShopDialog(),
              ),
              child: const Text('Open shop'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shop_xu_balance')));
    await tester.pumpAndSettle();
    final open = find.byKey(const Key('open_xu_conversion_button'));
    final amount = find.byKey(const Key('xu_conversion_amount_field'));
    final confirm = find.byKey(const Key('xu_conversion_confirm_button'));
    expect(amount, findsNothing);
    expect(PlayerStorage.currentProfile.xu, 3);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('xu_conversion_cancel_button')));
    await tester.pumpAndSettle();
    expect(PlayerStorage.currentProfile.gold, 50);

    final openConversion = tester.widget<OutlinedButton>(open).onPressed!;
    openConversion();
    openConversion();
    await tester.pumpAndSettle();
    expect(amount, findsOneWidget);
    await tester.enterText(amount, '4');
    await tester.pumpAndSettle();
    expect(find.text('Không đủ Xu để đổi.'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(amount, '2');
    await tester.pumpAndSettle();
    expect(find.text('Nhận 2000 Vàng'), findsOneWidget);
    final submit = tester.widget<FilledButton>(confirm).onPressed!;
    submit();
    submit();
    await tester.pumpAndSettle();
    expect(find.byType(ShopDialog), findsOneWidget);
    expect(PlayerStorage.currentProfile.xu, 1);
    expect(PlayerStorage.currentProfile.gold, 2050);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(amount, '0');
    await tester.pumpAndSettle();
    expect(find.text('Nhập ít nhất 1 Xu.'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const Key('xu_conversion_cancel_button')));
    await tester.pumpAndSettle();
    PlayerStorage.profileNotifier.value = PlayerStorage.currentProfile.copyWith(
      xu: 0,
    );
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa có Xu để đổi.'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const Key('xu_conversion_cancel_button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
