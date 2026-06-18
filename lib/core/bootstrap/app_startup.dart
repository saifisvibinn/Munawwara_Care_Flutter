import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../env/env_check.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/secure_session_store.dart';
import '../utils/app_logger.dart';

/// Minimum work before [runApp]: Firebase, localization.
/// Env keys come from `--dart-define` / `--dart-define-from-file=.env`
/// (see [lib/core/env/app_env.dart]); `.env` is not bundled as an asset.
Future<void> prepareCoreRuntime() async {
  await EasyLocalization.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    AppLogger.e('[Startup] Firebase.initializeApp failed: $e\n$st');
    // Continue without FCM — login/map/chat still work for smoke testing.
  }

  await SecureSessionStore.migrateFromSharedPreferencesIfNeeded();

  final prefs = await SharedPreferences.getInstance();
  ThemeNotifier.prepareBootTheme(prefs);
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
