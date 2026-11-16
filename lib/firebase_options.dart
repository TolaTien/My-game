import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Values are supplied with --dart-define for the Firebase Web app.
/// This keeps Firebase credentials/config out of the source tree while the
/// project is being configured for the first time.
class DefaultFirebaseOptions {
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyCwSFGtB6oYr1hbPU51WF5YngM5nwlzpdw',
  );
  static const authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'my-game-ec4fa.firebaseapp.com',
  );
  static const appIdWeb = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:419437402803:web:b473a96092ad7cd3e72ec6',
  );
  static const databaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
    defaultValue: 'https://my-game-ec4fa-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'my-game-ec4fa',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '419437402803',
  );

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      databaseUrl.isNotEmpty &&
      (kIsWeb ? appIdWeb.isNotEmpty : true);

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase Web config is missing. Pass FIREBASE_API_KEY, '
        'FIREBASE_APP_ID and FIREBASE_DATABASE_URL with --dart-define.',
      );
    }

    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: apiKey,
        appId: appIdWeb,
        authDomain: authDomain.isEmpty ? '$projectId.firebaseapp.com' : authDomain,
        databaseURL: databaseUrl,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: apiKey,
          appId: '1:419437402803:android:20575160792c1660e72ec6',
          databaseURL: databaseUrl,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
        );
      default:
        throw UnsupportedError('Firebase options are only configured for Android and Web.');
    }
  }
}
