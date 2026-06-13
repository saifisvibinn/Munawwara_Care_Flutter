import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../env/env_check.dart';
import '../services/api_service.dart';
import '../services/secure_session_store.dart';
import '../utils/app_logger.dart';

/// Minimum work before [runApp]: Firebase, localization, env file load.
Future<void> prepareCoreRuntime() async {
  await EasyLocalization.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e, st) {
    AppLogger.e('[Startup] dotenv.load failed: $e\n$st');
  }

  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    AppLogger.e('[Startup] Firebase.initializeApp failed: $e\n$st');
    // Continue without FCM — login/map/chat still work for smoke testing.
  }

  await SecureSessionStore.migrateFromSharedPreferencesIfNeeded();
}

/// Env validation + native prefs — deferred until after first frame.
Future<void> runDeferredStartupTasks() async {
  await verifyEnv();
  await ApiService.cacheNativeBridgePrefs();
  AppLogger.w(
    '[Startup] api_base_url=${ApiService.baseUrl} '
    'socketOrigin=${ApiService.socketOrigin}',
  );
}
