import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/env_config.dart';
import 'registry/asset_registry.dart';
import 'registry/sprite_image_cache.dart';
import 'screens/auth_screen.dart';
import 'screens/lobby_screen.dart';
import 'services/audio_service.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/firebase_database_service.dart';
import 'services/game_settings_service.dart';
import 'services/player_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khóa màn hình ngang Landscape cho Game Mobile
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Toàn màn hình Immersive (ẩn thanh điều hướng và status bar)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Nạp các biến bảo mật từ file .env trước khi khởi tạo Firebase và AI
  await EnvConfig.initialize();

  // Nạp hệ thống Registry từ thư mục assets/data/*.json
  await GameAssetRegistry.instance.initialize();

  // Firebase is optional during offline development. For the Chrome PvP demo,
  // provide the Web app values through --dart-define.
  await FirebaseBootstrap.initialize();

  // Khởi tạo dịch vụ cơ sở dữ liệu (Firebase Realtime Database khi online, fallback offline không mock)
  if (FirebaseBootstrap.isReady) {
    DatabaseService.setInstance(FirebaseDatabaseService());
  }
  await DatabaseService.instance.initialize();

  // Khôi phục phiên đăng nhập cũ (nếu có) và nạp hồ sơ từ Firebase,
  // nếu chưa đăng nhập thì sẽ hiển thị màn hình Đăng nhập / Đăng ký.
  final isSignedIn = await AuthService.instance.restoreSession();

  // Khởi tạo và nạp dữ liệu hồ sơ người chơi từ SharedPreferences
  if (!isSignedIn) {
    await PlayerStorage.loadProfile();
    await DatabaseService.instance.updateLeaderboard(PlayerStorage.currentProfile);
  }

  // Khởi tạo hệ thống âm thanh và cài đặt trò chơi
  await AudioService.instance.initialize();
  await GameSettingsService.instance.initialize();

  // Khởi chạy giao diện ngay lập tức để tránh lỗi ANR (Application Not Responding)
  runApp(GoldRushApp(isSignedIn: isSignedIn));

  // Tải trước tài nguyên ảnh Sprite trong nền sau khi frame đầu tiên đã vẽ xong
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SpriteImageCache.instance.preloadAll();
  });
}

class GoldRushApp extends StatelessWidget {
  final bool isSignedIn;
  const GoldRushApp({super.key, this.isSignedIn = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Big-War',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: isSignedIn ? const LobbyScreen() : const AuthScreen(),
    );
  }
}
