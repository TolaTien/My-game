import 'package:flutter/foundation.dart';

/// Quản lý tập trung cấu hình runtime qua `--dart-define` / `--dart-define-from-file=.env`.
///
/// LƯU Ý BẢO MẬT:
/// - File `.env` KHÔNG được khai báo trong `pubspec.yaml` (`assets:`) nên sẽ KHÔNG bao giờ
///   bị đóng gói vào APK/IPA/Web bundle và không gây lỗi 404 fetch `assets/.env` trên Web.
/// - Khóa `GEMINI_API_KEY` chỉ nằm trên máy chủ proxy (`server/ai_proxy/.env`);
///   ứng dụng Flutter chỉ giữ `AI_PROXY_URL` (hoặc để trống để chạy Chế độ Demo offline).
class EnvConfig {
  EnvConfig._();

  static Map<String, String> _testOverrides = const {};

  /// Khởi tạo cấu hình (no-op an toàn; toàn bộ cấu hình đọc từ compile-time `--dart-define`).
  static Future<void> initialize() async {}

  /// Chỉ dùng trong unit test để giả lập biến cấu hình.
  @visibleForTesting
  static void setTestOverrides(Map<String, String> overrides) {
    _testOverrides = Map<String, String>.from(overrides);
  }

  @visibleForTesting
  static void clearTestOverrides() {
    _testOverrides = const {};
  }

  static String _read(String key, String compileTimeValue, [String fallback = '']) {
    final override = _testOverrides[key]?.trim();
    if (override != null) return override;
    final val = compileTimeValue.trim();
    if (val.isNotEmpty) return val;
    return fallback;
  }

  // --- AI Proxy Server (khóa Gemini chỉ nằm ở server) ---
  static String get aiProxyUrl => _read(
        'AI_PROXY_URL',
        const String.fromEnvironment('AI_PROXY_URL'),
      );

  // --- Firebase Configuration ---
  static String get firebaseApiKey => _read(
        'FIREBASE_API_KEY',
        const String.fromEnvironment('FIREBASE_API_KEY'),
        'AIzaSyCwSFGtB6oYr1hbPU51WF5YngM5nwlzpdw',
      );

  static String get firebaseAuthDomain => _read(
        'FIREBASE_AUTH_DOMAIN',
        const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        'my-game-ec4fa.firebaseapp.com',
      );

  static String get firebaseAppIdWeb {
    const primary = String.fromEnvironment('FIREBASE_APP_ID_WEB');
    const legacy = String.fromEnvironment('FIREBASE_APP_ID');
    return _read(
      'FIREBASE_APP_ID_WEB',
      primary.isNotEmpty ? primary : legacy,
      '1:419437402803:web:b473a96092ad7cd3e72ec6',
    );
  }

  static String get firebaseAppIdAndroid => _read(
        'FIREBASE_APP_ID_ANDROID',
        const String.fromEnvironment('FIREBASE_APP_ID_ANDROID'),
        '1:419437402803:android:20575160792c1660e72ec6',
      );

  static String get firebaseDatabaseUrl => _read(
        'FIREBASE_DATABASE_URL',
        const String.fromEnvironment('FIREBASE_DATABASE_URL'),
        'https://my-game-ec4fa-default-rtdb.asia-southeast1.firebasedatabase.app',
      );

  static String get firebaseProjectId => _read(
        'FIREBASE_PROJECT_ID',
        const String.fromEnvironment('FIREBASE_PROJECT_ID'),
        'my-game-ec4fa',
      );

  static String get firebaseMessagingSenderId => _read(
        'FIREBASE_MESSAGING_SENDER_ID',
        const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        '419437402803',
      );
}
