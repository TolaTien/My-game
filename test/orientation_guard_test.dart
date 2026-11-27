import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/screens/widgets/orientation_guard.dart';

void main() {
  group('OrientationGuard & Landscape Enforcer Tests', () {
    testWidgets('Shows rotate device prompt when phone is in portrait mode',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // Portrait iPhone
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrientationGuard(
              child: Text('GAME_CONTENT_LOADED'),
            ),
          ),
        ),
      );
      await tester.pump();

      // Phải xuất hiện thông báo xoay màn hình
      expect(find.text('VUI LÒNG XOAY NGANG MÀN HÌNH'), findsOneWidget);
      expect(
        find.textContaining('Tự động xoay'),
        findsOneWidget,
      );
    });

    testWidgets('Hides rotate prompt and shows game content in landscape mode',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390); // Landscape iPhone
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrientationGuard(
              child: Text('GAME_CONTENT_LOADED'),
            ),
          ),
        ),
      );
      await tester.pump();

      // Không hiển thị màn hình khóa xoay, nội dung game hiển thị bình thường
      expect(find.text('VUI LÒNG XOAY NGANG MÀN HÌNH'), findsNothing);
      expect(find.text('GAME_CONTENT_LOADED'), findsOneWidget);
    });
  });
}
