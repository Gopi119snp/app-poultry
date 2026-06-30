import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firebase_options.dart';

/// Firebase init + offline persistence flag.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static bool _initialized = false;
  static bool _configured = false;

  static bool get isReady => _initialized && _configured;

  /// Local-only fallback jab Firebase configure nahi hua.
  static bool get isLocalOnlyMode => _initialized && !_configured;

  static Future<void> init() async {
    if (_initialized) return;

    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint(
        '[PoultryPro] Firebase not configured — local SharedPreferences mode. '
        'Run: flutterfire configure',
      );
      _initialized = true;
      _configured = false;
      return;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      _configured = true;
      debugPrint('[PoultryPro] Firebase initialized successfully.');
    } catch (e, st) {
      debugPrint('[PoultryPro] Firebase init failed: $e\n$st');
      _initialized = true;
      _configured = false;
    }
  }
}
