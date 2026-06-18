import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../utils/app_logger.dart';

/// Obtains an FCM registration token.
///
/// On iOS, [FirebaseMessaging.getToken] fails with `apns-token-not-set` until
/// Apple delivers an APNS device token (after permission + registration).
Future<String?> obtainFcmRegistrationToken({
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return null;
  }

  final messaging = FirebaseMessaging.instance;
  final deadline = DateTime.now().add(timeout);

  if (Platform.isIOS) {
    var apnsReady = false;
    while (DateTime.now().isBefore(deadline)) {
      final apns = await messaging.getAPNSToken();
      if (apns != null && apns.isNotEmpty) {
        apnsReady = true;
        AppLogger.i('iOS APNS token ready');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    if (!apnsReady) {
      AppLogger.w(
        'iOS APNS token unavailable after ${timeout.inSeconds}s — '
        'allow notifications in Settings and rebuild with Push capability',
      );
      return null;
    }
  }

  while (DateTime.now().isBefore(deadline)) {
    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (e) {
      AppLogger.d('FCM getToken retry: $e');
    }
    await Future.delayed(const Duration(milliseconds: 400));
  }

  AppLogger.w('FCM getToken unavailable after ${timeout.inSeconds}s');
  return null;
}
