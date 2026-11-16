import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/game/hud/virtual_joystick.dart';
import 'package:my_game/screens/game_play_screen.dart';
import 'package:my_game/screens/pvp_arena_screen.dart';

void main() {
  testWidgets('GamePlayScreen renders clean touch buttons on Mobile', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: GamePlayScreen(),
        ),
      );
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

  testWidgets('GamePlayScreen renders joystick and action buttons with hotkeys on Desktop/Web', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: GamePlayScreen(),
        ),
      );
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
  });

  testWidgets('GamePlayScreen toggles on-screen touch controls on Desktop/Web', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: GamePlayScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Initially visible
      expect(find.byType(VirtualJoystick), findsOneWidget);

      // Tap toggle button to hide touch controls
      final toggleFinder = find.byKey(const Key('toggle_touch_controls_button'));
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
  });

  testWidgets('PvpArenaScreen renders matchmaking view safely without crash', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PvpArenaScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PvpArenaScreen), findsOneWidget);
    expect(find.textContaining('ĐANG TÌM TRẬN ĐỐI KHÁNG'), findsOneWidget);

    // Tap bot button
    final botBtn = find.text('GHÉP NGAY (AI BOT)');
    expect(botBtn, findsOneWidget);
    await tester.tap(botBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  });
}
