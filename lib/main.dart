import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'registry/asset_registry.dart';
import 'registry/sprite_image_cache.dart';
import 'screens/lobby_screen.dart';
import 'services/audio_service.dart';
import 'services/database_service.dart';
import 'services/firebase_bootstrap.dart';
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

  // Nạp hệ thống Registry từ thư mục assets/data/*.json và bộ đệm Sprite PNG
  await GameAssetRegistry.instance.initialize();
  await SpriteImageCache.instance.preloadAll();

  // Firebase is optional during offline development. For the Chrome PvP demo,
  // provide the Web app values through --dart-define.
  await FirebaseBootstrap.initialize();

  // Khởi tạo và nạp dữ liệu hồ sơ người chơi từ SharedPreferences
  await PlayerStorage.loadProfile();

  // Khởi tạo dịch vụ cơ sở dữ liệu và bảng xếp hạng offline fallback
  await DatabaseService.instance.initialize();
  await DatabaseService.instance.updateLeaderboard(PlayerStorage.currentProfile);

  // Khởi tạo hệ thống âm thanh
  await AudioService.instance.initialize();

  runApp(const GoldRushApp());
}

class GoldRushApp extends StatelessWidget {
  const GoldRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gold Rush Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LobbyScreen(),
    );
  }
}
