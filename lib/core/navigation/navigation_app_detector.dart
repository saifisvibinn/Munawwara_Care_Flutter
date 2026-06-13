import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'navigation_app.dart';

/// Detects which navigation apps are installed on the device.
class NavigationAppDetector {
  NavigationAppDetector._();

  static Future<bool> isInstalled(NavigationApp app) async {
    if (app == NavigationApp.systemSelection) return false;

    final probe = _probeUriFor(app);
    if (probe == null) return false;

    try {
      return await canLaunchUrl(probe);
    } catch (_) {
      return false;
    }
  }

  /// Returns launchable navigation apps for the current platform.
  static Future<List<NavigationApp>> availableApps() async {
    if (kIsWeb) {
      return const [NavigationApp.googleMaps];
    }

    final apps = <NavigationApp>[];

    if (Platform.isIOS) {
      apps.add(NavigationApp.appleMaps);
      if (await isInstalled(NavigationApp.googleMaps)) {
        apps.add(NavigationApp.googleMaps);
      }
      return apps;
    }

    if (await isInstalled(NavigationApp.googleMaps)) {
      apps.add(NavigationApp.googleMaps);
    }
    return apps;
  }

  static Uri? _probeUriFor(NavigationApp app) {
    if (kIsWeb) return null;

    switch (app) {
      case NavigationApp.appleMaps:
        if (!Platform.isIOS) return null;
        return Uri.parse('maps://');
      case NavigationApp.googleMaps:
        if (Platform.isIOS) {
          return Uri.parse('comgooglemaps://');
        }
        return Uri.parse('google.navigation:q=0,0');
      case NavigationApp.systemSelection:
        return null;
    }
  }
}
