import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_prefs_bridge.dart';
import 'battery_optimization_helper.dart';

@pragma('vm:entry-point')
class TamenyLocationService {
  
  static const _androidWorkManagerChannel = MethodChannel('com.munawwaracare/workmanager');
  static const _iosLocationChannel = MethodChannel('com.munawwaracare/location');
  
  static const _prefToggleKey = 'tameny_tracking_enabled';
  static const _prefTokenKey = 'pilgrim_auth_token';
  static const _prefServerUrlKey = 'server_url';
  
  // ─── PUBLIC API ───────────────────────────────────────────────

  /// Call this once at app startup (main.dart)
  static Future<void> initialize({
    required String serverUrl,
    required String authToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerUrlKey, serverUrl);
    await prefs.setString(_prefTokenKey, authToken);
    
    // Save to native prefs bridge as well
    await NativePrefsBridge.saveForNative(
      authToken: authToken,
      serverUrl: serverUrl,
    );
    
    // Initialize flutter_background_service
    await _initBackgroundService();
    
    // If toggle was ON before the app was killed/restarted, resume it
    final wasEnabled = prefs.getBool(_prefToggleKey) ?? false;
    if (wasEnabled) {
      await _startKilledStateTracking();
    }
  }

  /// Enable the full tracking stack (toggle ON)
  static Future<bool> enableTracking(
    BuildContext context, {
    bool forceSkipDisclosure = false,
    bool requestBatteryOptimization = true,
  }) async {
    // 1. Show prominent disclosure dialog first
    if (!forceSkipDisclosure) {
      final confirmed = await _showProminentDisclosure(context);
      if (!confirmed) return false;
    }
    
    // 2. Request permissions
    final hasPermission = await _requestPermissions();
    if (!hasPermission) return false;
    
    // 3. Request battery optimization
    if (requestBatteryOptimization) {
      await BatteryOptimizationHelper.requestDisableBatteryOptimization();
    }
    
    // 4. Start foreground service (handles backgrounded state)
    await _startForegroundService();
    
    // 5. Start killed-state tracking
    await _startKilledStateTracking();
    
    // 6. Persist toggle state
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefToggleKey, true);
    
    return true;
  }

  /// Disable all tracking (toggle OFF)
  static Future<void> disableTracking() async {
    await _stopForegroundService();
    await _stopKilledStateTracking();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefToggleKey, false);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefToggleKey) ?? false;
  }

  // ─── FOREGROUND SERVICE (backgrounded state) ─────────────────

  static Future<void> _initBackgroundService() async {
    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _backgroundServiceEntryPoint,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'tameny_location_channel',
        initialNotificationTitle: 'Munawwara Care',
        initialNotificationContent: 'Keeping your group updated on your location',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _backgroundServiceEntryPoint,
        onBackground: _iosBackgroundHandler,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> _iosBackgroundHandler(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void _backgroundServiceEntryPoint(ServiceInstance service) async {
    // This runs in a separate isolate — keep the socket alive and send location
    // Runs every 30 seconds while app is backgrounded
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (!await service.isForegroundService()) {
          timer.cancel();
          return;
        }
      }
      
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        
        service.invoke('locationUpdate', {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('[Tameny BG Service] Location error: $e');
      }
    });
    
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  static Future<void> _startForegroundService() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  static Future<void> _stopForegroundService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  // ─── KILLED STATE TRACKING ────────────────────────────────────

  static Future<void> _startKilledStateTracking() async {
    if (Platform.isAndroid) {
      // WorkManager: fires every 60 minutes even when killed
      try {
        await _androidWorkManagerChannel.invokeMethod('startPeriodicLocation', {
          'intervalMinutes': 60,
        });
      } catch (e) {
        debugPrint('Error starting work manager: $e');
      }
    } else if (Platform.isIOS) {
      // Significant Location Changes: fires when user moves 500m+
      try {
        await _iosLocationChannel.invokeMethod('startSignificantLocationChanges');
      } catch (e) {
        debugPrint('Error starting ios significant changes: $e');
      }
    }
  }

  static Future<void> _stopKilledStateTracking() async {
    if (Platform.isAndroid) {
      try {
        await _androidWorkManagerChannel.invokeMethod('stopPeriodicLocation');
      } catch (e) {
        debugPrint('Error stopping work manager: $e');
      }
    } else if (Platform.isIOS) {
      try {
        await _iosLocationChannel.invokeMethod('stopSignificantLocationChanges');
      } catch (e) {
        debugPrint('Error stopping ios significant changes: $e');
      }
    }
  }

  // ─── PERMISSIONS ─────────────────────────────────────────────

  static Future<bool> _requestPermissions() async {
    // Location permission
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    
    // On iOS, we need "Always" permission for killed-state tracking
    if (Platform.isIOS) {
      if (permission != LocationPermission.always) {
        permission = await Geolocator.requestPermission();
      }
    }
    
    return permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
  }

  // ─── PROMINENT DISCLOSURE DIALOG ─────────────────────────────

  static Future<bool> _showProminentDisclosure(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('مشاركة الموقع في الخلفية', textDirection: TextDirection.rtl),
        content: const Text(
          'سيقوم تطبيق منوارة كير بجمع بيانات الموقع في الخلفية '
          'لتمكين تتبع السلامة في الوقت الفعلي وتنبيهات SOS '
          'حتى عند إغلاق التطبيق أو عدم استخدامه.\n\n'
          'Munawwara Care collects location data in the background '
          'to enable real-time safety tracking even when the app '
          'is closed or not in use.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا شكراً (No Thanks)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('موافق (Agree)'),
          ),
        ],
      ),
    ) ?? false;
  }
}
