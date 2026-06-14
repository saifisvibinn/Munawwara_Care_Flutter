import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/bootstrap/app_startup.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/api_service.dart';
import 'core/services/callkit_service.dart';
import 'core/services/locale_prefs.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'core/widgets/standard_snackbar.dart';
import 'core/utils/device_orientation_policy.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/calling/calling_scope.dart';
import 'features/calling/native_call_coordinator.dart';
import 'features/calling/providers/call_provider.dart';
import 'features/moderator/services/sos_alert_coordinator.dart';
import 'core/config/app_locales.dart';
import 'core/services/tameny_location_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  NativeCallCoordinator.registerEarlyListeners();

  await Future.wait<void>([
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    applyDeviceOrientationPolicy(),
    prepareCoreRuntime(),
  ]);
  AppLogger.i('Core runtime ready');

  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    AppLogger.i('Background message handler registered');
  } catch (e, st) {
    AppLogger.w('[Startup] FCM background handler skipped: $e\n$st');
  }

  final container = ProviderContainer();
  CallingScope.riverpod = container;

  ApiService.setUnauthorizedCallback(() async {
    AppLogger.w('🛑 Unauthorized (401) detected — forcing logout');
    await container.read(authProvider.notifier).logout();
    AppRouter.router.go('/login');
  });

  runApp(
    EasyLocalization(
      supportedLocales: AppLocales.supportedLocales,
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AuthState>(authProvider, (previous, next) {
      final wasRestoringOrUnauthenticated =
          previous == null ||
          previous.isRestoringSession ||
          !previous.isAuthenticated;
      if (next.isAuthenticated && wasRestoringOrUnauthenticated) {
        unawaited(ref.read(authProvider.notifier).ensureFcmTokenRegistered());
        if (next.token != null) {
          unawaited(
            TamenyLocationService.initialize(
              serverUrl: ApiService.baseUrl,
              authToken: next.token!,
            ),
          );
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = context.locale.languageCode;
      unawaited(LocalePrefs.saveLanguageCode(lang));
      unawaited(
        CallKitService.refreshCachedSupportDisplayName(languageCode: lang),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref.read(callProvider.notifier).reconcileCallStateAfterProcessDeath(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      ensureScreenSize: false,
      builder: (context, child) {
        final bool isDarkUi = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system =>
            View.of(context).platformDispatcher.platformBrightness ==
                Brightness.dark,
        };

        return MaterialApp.router(
          title: 'Munawwara Care',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          themeAnimationDuration: AppTheme.themeSwitchDuration,
          themeAnimationCurve: AppTheme.themeSwitchCurve,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: AppRouter.router,
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDarkUi
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: isDarkUi
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: isDarkUi
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                child: StandardSnackBarHost(
                  child: _HotReloadSosAlertSuppressor(child: child!),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HotReloadSosAlertSuppressor extends StatefulWidget {
  const _HotReloadSosAlertSuppressor({required this.child});

  final Widget child;

  @override
  State<_HotReloadSosAlertSuppressor> createState() =>
      _HotReloadSosAlertSuppressorState();
}

class _HotReloadSosAlertSuppressorState
    extends State<_HotReloadSosAlertSuppressor> {
  @override
  void reassemble() {
    super.reassemble();
    if (!kReleaseMode) {
      SosAlertCoordinator.suppressInAppSosAlertsFor(const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
