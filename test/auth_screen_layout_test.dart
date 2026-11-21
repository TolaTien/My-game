import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_game/screens/auth_screen.dart';

void main() {
  group('AuthScreen Responsive Layout Tests', () {
    testWidgets('AuthScreen renders cleanly on mobile landscape without text clipping or overflow',
        (tester) async {
      tester.view.physicalSize = const Size(800, 380); // Typical mobile landscape
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

      // Kiểm tra các thành phần thương hiệu và nhãn nhập liệu đều hiện đầy đủ
      expect(find.text('BIG-WAR'), findsNWidgets(3)); // 3 text layer hiệu ứng 3D
      expect(find.text('ĐẤU TRƯỜNG SINH TỬ'), findsOneWidget);
      expect(find.text('ĐĂNG NHẬP CHIẾN TRƯỜNG'), findsOneWidget);
      expect(find.text('Tài khoản'), findsNWidgets(2)); // Stroke + Fill
      expect(find.text('Mật khẩu'), findsNWidgets(2));
      expect(find.text('ĐĂNG NHẬP'), findsNWidgets(2)); // Nút hành động dập nổi
      expect(find.text('Chưa có tài khoản? Đăng ký ngay'), findsOneWidget);

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

      // Bấm vào nút chuyển sang Đăng ký
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký ngay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Kiểm tra trường Chiến danh xuất hiện
      expect(find.text('TẠO TÀI KHOẢN CHIẾN BINH'), findsOneWidget);
      expect(find.text('Chiến danh'), findsNWidgets(2));
      expect(find.text('Đã có tài khoản? Đăng nhập'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
