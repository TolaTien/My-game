import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  static bool isReady = false;
  static Object? lastError;

  static Future<void> initialize() async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    try {
      final app = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      // SESSION persistence là theo từng tab: mỗi tab Chrome có thể đăng nhập
      // một tài khoản khác nhau (tiện test PvP), và F5 vẫn giữ phiên đăng nhập.
      // Người chơi đăng nhập bằng Email/Mật khẩu tại AuthScreen.
      if (kIsWeb) {
        await auth.setPersistence(Persistence.SESSION);
      }
      isReady = true;
    } catch (error) {
      lastError = error;
      debugPrint('Firebase initialization failed: $error');
    }
  }
}
