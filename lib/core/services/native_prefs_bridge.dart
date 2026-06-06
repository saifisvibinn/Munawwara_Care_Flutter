import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativePrefsBridge {
  
  /// Saves auth token and server URL where native code can read them.
  /// Android: SharedPreferences (flutter. prefix) — WorkManager reads this.
  /// iOS: UserDefaults via MethodChannel — AppDelegate reads this.
  static Future<void> saveForNative({
    required String authToken,
    required String serverUrl,
  }) async {
    // Flutter SharedPreferences (Android WorkManager can read these)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pilgrim_auth_token', authToken);
    await prefs.setString('server_url', serverUrl);
    
    // iOS UserDefaults (AppDelegate reads these)
    if (Platform.isIOS) {
      const channel = MethodChannel('com.munawwaracare/location');
      try {
        await channel.invokeMethod('saveCredentials', {
          'token': authToken,
          'serverUrl': serverUrl,
        });
      } catch (e) {
        debugPrint('Error saving credentials to iOS: $e');
      }
    }
  }
  
  static Future<void> clearForNative() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pilgrim_auth_token');
    await prefs.remove('server_url');
  }
}
