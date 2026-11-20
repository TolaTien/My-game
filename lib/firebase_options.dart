import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'core/env_config.dart';

/// Firebase configuration loaded from `.env` (via [EnvConfig]) or `--dart-define`.
/// Keeps API keys and project credentials out of the source tree.
class DefaultFirebaseOptions {
  static String get apiKey => EnvConfig.firebaseApiKey;
  static String get authDomain => EnvConfig.firebaseAuthDomain;
  static String get appIdWeb => EnvConfig.firebaseAppIdWeb;
  static String get appIdAndroid => EnvConfig.firebaseAppIdAndroid;
  static String get databaseUrl => EnvConfig.firebaseDatabaseUrl;
  static String get projectId => EnvConfig.firebaseProjectId;
  static String get messagingSenderId => EnvConfig.firebaseMessagingSenderId;

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      databaseUrl.isNotEmpty &&
      (kIsWeb ? appIdWeb.isNotEmpty : appIdAndroid.isNotEmpty);

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase config is missing. Please configure FIREBASE_* variables in .env '
        'or pass them with --dart-define.',
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
          appId: appIdAndroid,
          databaseURL: databaseUrl,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
        );
      default:
        throw UnsupportedError(
          'Firebase options are only configured for Android and Web.',
        );
    }
  }
}
