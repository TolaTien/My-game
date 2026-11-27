import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/screens/auth_screen.dart';

void main() {
  group('AuthScreen Modern Card Layout Tests', () {
    testWidgets(
        'AuthScreen renders two-column modern card cleanly with chibi dragon and form',
        (tester) async {
      tester.view.physicalSize = const Size(800, 380); // Landscape mobile
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: AuthScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Kiểm tra tiêu đề Welcome 👋 và mô tả
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('👋'), findsOneWidget);
      expect(find.text('Please enter your email and password'), findsOneWidget);

      // Kiểm tra các trường Gmail & Password
      expect(find.textContaining('Gmail'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Kiểm tra nút Login cam và liên kết Register now!
      expect(find.text('Login'), findsOneWidget);
      expect(find.textContaining('Register now!'), findsOneWidget);

      // Xác nhận không có nút fb, google, forgot password
      expect(find.textContaining('Forgot password'), findsNothing);
      expect(find.textContaining('google'), findsNothing);
      expect(find.textContaining('facebook'), findsNothing);

      // Đảm bảo không có ngoại lệ RenderFlex overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('AuthScreen switches to registration mode smoothly',
        (tester) async {
      tester.view.physicalSize = const Size(850, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: AuthScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Bấm vào Register now!
      await tester.tap(find.textContaining('Register now!'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Kiểm tra trường Tên nhân vật duy nhất xuất hiện và nút đổi thành Register
      expect(find.textContaining('Tên nhân vật duy nhất'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
      expect(find.textContaining('Login now!'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
