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
      // SESSION persistence is tab-scoped, allowing two Chrome tabs to act as
      // two separate anonymous players during the local PvP demo.
      if (kIsWeb) {
        await auth.setPersistence(Persistence.SESSION);
        // "Nhân đôi tab" (Duplicate tab) sao chép cả sessionStorage => 2 tab
        // dùng chung 1 UID và không thể ghép với nhau. Luôn tạo phiên ẩn danh
        // mới cho mỗi lần tải trang để mỗi tab là một người chơi riêng biệt.
        if (auth.currentUser != null) await auth.signOut();
      }
      if (auth.currentUser == null) await auth.signInAnonymously();
      isReady = true;
    } catch (error) {
      lastError = error;
      debugPrint('Firebase initialization failed: $error');
    }
  }
}
