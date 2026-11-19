import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_game/screens/shop_dialog.dart';
import 'package:my_game/services/player_storage.dart';

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('Shop lists support $kind and arrow navigation on all tabs', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await PlayerStorage.loadProfile();
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ShopDialog())),
      );
      await tester.pumpAndSettle();
      final gold = PlayerStorage.currentProfile.gold;
      final diamonds = PlayerStorage.currentProfile.diamonds;
      for (final label in ['NHÂN VẬT', 'TRỢ THỦ AI', 'TRANG PHỤC (SKIN)']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        final list = find.byType(ListView).hitTestable().first;
        final scrollable = find
            .descendant(of: list, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        final extent = tester.widget<ListView>(list).itemExtent!;
        final columns = (position.viewportDimension / extent).round();
        final start = tester.getRect(list).center;
        final gesture = await tester.createGesture(kind: kind);
        await gesture.addPointer(location: start);
        await gesture.down(start);
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(-180, 0));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(position.pixels, greaterThan(0), reason: label);
        expect(
          position.pixels / extent,
          closeTo((position.pixels / extent).round(), .01),
        );
        await gesture.removePointer();
        final beforeArrow = position.pixels;
        await tester.tap(find.byTooltip('Cuộn sang phải').hitTestable().first);
        await tester.pumpAndSettle();
        expect(
          position.pixels,
          closeTo(
            (beforeArrow + extent * columns).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            ),
            .1,
          ),
        );
        await tester.tap(find.byTooltip('Cuộn sang trái').hitTestable().first);
        await tester.pumpAndSettle();
        expect(position.pixels, lessThanOrEqualTo(beforeArrow + .1));
        expect(tester.takeException(), isNull);
      }
      expect(PlayerStorage.currentProfile.gold, gold);
      expect(PlayerStorage.currentProfile.diamonds, diamonds);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
