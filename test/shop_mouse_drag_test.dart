import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  for (var tab = 0; tab < 3; tab++) {
    testWidgets('Mouse drags shop list in tab $tab without purchasing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await PlayerStorage.loadProfile();
      final gold = PlayerStorage.currentProfile.gold;
      final diamonds = PlayerStorage.currentProfile.diamonds;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ShopDialog(initialTab: tab))));
      await tester.pumpAndSettle();
      final list = find.byType(ListView).first;
      final scrollable = find.descendant(of: list, matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, 0);
      final center = tester.getRect(list).center;
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      await gesture.down(center);
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-180, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(PlayerStorage.currentProfile.gold, gold);
      expect(PlayerStorage.currentProfile.diamonds, diamonds);
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
