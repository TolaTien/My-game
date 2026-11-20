import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/models/player_profile.dart';
import 'package:my_game/screens/auth_screen.dart';
import 'package:my_game/screens/lobby_screen.dart';
import 'package:my_game/services/player_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Big-War login keeps guest entry and loads the guest profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'gold_rush_player_profile': jsonEncode(
        PlayerProfile.defaultProfile().copyWith(gold: 4321).toJson(),
      ),
    });
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var enteredGame = false;
    addTearDown(() async {
      PlayerStorage.detachUser();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    await tester.pumpWidget(
      MaterialApp(home: AuthScreen(onGameEntered: () => enteredGame = true)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('auth_play_offline')), findsOneWidget);
    await tester.tap(find.byKey(const Key('auth_play_offline')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(enteredGame, isTrue);
    expect(PlayerStorage.activeUid, isNull);
    expect(PlayerStorage.currentProfile.gold, 4321);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Big-War registration still rejects a mismatched password confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => PlayerStorage.detachUser());

      await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký ngay'));
      await tester.pump(const Duration(milliseconds: 250));
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.length, 4);
      await tester.enterText(find.byType(TextFormField).at(0), 'Chiến Binh');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'warrior@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Secret123');
      await tester.enterText(find.byType(TextFormField).at(3), 'Different123');
      expect(tester.state<FormState>(find.byType(Form)).validate(), isFalse);
      await tester.pump();
      expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
      expect(find.byType(LobbyScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
