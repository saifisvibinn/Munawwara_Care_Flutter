import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../env/env_check.dart';
import '../services/api_service.dart';
import '../services/secure_session_store.dart';
import '../utils/app_logger.dart';

/// Minimum work before [runApp]: Firebase, localization, env file load.
Future<void> prepareCoreRuntime() async {
  await Future.wait<void>([
    Firebase.initializeApp(),
    EasyLocalization.ensureInitialized(),
    dotenv.load(fileName: '.env'),
  ]);
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
