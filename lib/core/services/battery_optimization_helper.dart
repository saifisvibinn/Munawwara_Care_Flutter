import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BatteryOptimizationHelper {
  
  static const _channel = MethodChannel('com.munawwaracare.android/oem_settings');
  
  static Future<void> requestDisableBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    try {
      // In MainActivity, we have openBatterySettings mapped
      await _channel.invokeMethod('openBatterySettings');
    } catch (e) {
      // Non-critical, continue anyway
      debugPrint('Error requesting disable battery optimization: $e');
    }
  }
}
