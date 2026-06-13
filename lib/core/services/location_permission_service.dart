import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/auth/widgets/background_location_disclosure_dialog.dart';
import '../../features/auth/widgets/ios_location_always_guide_sheet.dart';

const _oemChannel = MethodChannel('com.munawwaracare.android/oem_settings');

/// Checks if always-on location is granted (platform-appropriate check).
Future<bool> hasLocationAlwaysPermission() async {
  if (kIsWeb) return false;
  if (Platform.isIOS) {
    final geo = await Geolocator.checkPermission();
    return geo == LocationPermission.always;
  }
  final whenInUse = await Permission.locationWhenInUse.isGranted;
  final always = await Permission.locationAlways.isGranted;
  return whenInUse && always;
}

/// iOS: while-in-use granted but Always still needed for setup step.
Future<bool> hasLocationWhenInUseOnly() async {
  if (kIsWeb || !Platform.isIOS) return false;
  final geo = await Geolocator.checkPermission();
  return geo == LocationPermission.whileInUse;
}

/// Opens OEM app-permission UI (MIUI editor, etc.), not generic App info only.
Future<void> openLocationPermissionSettings({
  VoidCallback? onOpenAppSettings,
}) async {
  onOpenAppSettings?.call();
  if (kIsWeb) return;
  if (Platform.isAndroid) {
    try {
      final opened = await _oemChannel.invokeMethod<bool>(
        'openLocationPermissionSettings',
      );
      if (opened == true) return;
    } on PlatformException {
      // Fall through.
    }
  }
  await Geolocator.openAppSettings();
}

/// Requests location **while in use**, shows prominent background disclosure,
/// then **always / background** on mobile.
Future<bool> requestLocationPermissionsFlow(
  BuildContext context, {
  VoidCallback? onOpenAppSettings,
}) async {
  if (kIsWeb) return false;

  if (!await _ensureWhenInUseLocation(onOpenAppSettings: onOpenAppSettings)) {
    return false;
  }

  if (!context.mounted) return false;
  if (!await _ensureAlwaysLocation(
    context,
    onOpenAppSettings: onOpenAppSettings,
  )) {
    return false;
  }

  return await hasLocationAlwaysPermission();
}

/// Uses [Geolocator] first (reliable on MIUI), then [permission_handler].
Future<bool> _ensureWhenInUseLocation({VoidCallback? onOpenAppSettings}) async {
  if (Platform.isIOS) {
    return _ensureWhenInUseLocationIos(onOpenAppSettings: onOpenAppSettings);
  }

  var geo = await Geolocator.checkPermission();

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (geo == LocationPermission.denied) {
    geo = await Geolocator.requestPermission();
  }

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (geo == LocationPermission.denied) {
    return false;
  }

  var handlerStatus = await Permission.locationWhenInUse.status;
  if (handlerStatus.isGranted) {
    return true;
  }

  if (handlerStatus.isPermanentlyDenied) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (handlerStatus.isDenied) {
    handlerStatus = await Permission.locationWhenInUse.request();
  }

  if (handlerStatus.isGranted) {
    return true;
  }

  if (handlerStatus.isPermanentlyDenied) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (handlerStatus.isDenied) {
    geo = await Geolocator.checkPermission();
    if (geo == LocationPermission.denied) {
      geo = await Geolocator.requestPermission();
    }
    if (geo == LocationPermission.deniedForever ||
        handlerStatus.isPermanentlyDenied) {
      await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
      return false;
    }
    if (geo != LocationPermission.denied &&
        geo != LocationPermission.deniedForever) {
      return true;
    }
    if (Platform.isAndroid) {
      await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    }
    return false;
  }

  return false;
}

/// iOS: native "Allow While Using" system alert via Geolocator only.
Future<bool> _ensureWhenInUseLocationIos({VoidCallback? onOpenAppSettings}) async {
  var geo = await Geolocator.checkPermission();

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (geo == LocationPermission.denied) {
    geo = await Geolocator.requestPermission();
  }

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  return geo == LocationPermission.whileInUse || geo == LocationPermission.always;
}

Future<bool> _ensureAlwaysLocation(
  BuildContext context, {
  VoidCallback? onOpenAppSettings,
}) async {
  if (await hasLocationAlwaysPermission()) {
    return true;
  }

  if (!context.mounted) return false;

  if (Platform.isIOS) {
    return _ensureAlwaysLocationIos(
      context,
      onOpenAppSettings: onOpenAppSettings,
    );
  }

  final proceed = await showBackgroundLocationDisclosure(context);
  if (!proceed) return false;

  final alwaysResult = await Permission.locationAlways.request();
  if (alwaysResult.isGranted && await hasLocationAlwaysPermission()) {
    return true;
  }

  final geo = await Geolocator.checkPermission();
  if (geo == LocationPermission.always) {
    return true;
  }

  if (alwaysResult.isPermanentlyDenied) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  if (!alwaysResult.isGranted) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
    return false;
  }

  return false;
}

/// iOS: in-app disclosure → native Always upgrade alert → Settings only if needed.
Future<bool> _ensureAlwaysLocationIos(
  BuildContext context, {
  VoidCallback? onOpenAppSettings,
}) async {
  final proceed = await showBackgroundLocationDisclosure(context);
  if (!proceed) return false;
  if (!context.mounted) return false;

  final alwaysResult = await Permission.locationAlways.request();
  if (alwaysResult.isGranted || await hasLocationAlwaysPermission()) {
    return true;
  }

  if (!context.mounted) return false;
  final openGuide = await showIosLocationAlwaysGuide(context);
  if (openGuide && context.mounted) {
    await openLocationPermissionSettings(onOpenAppSettings: onOpenAppSettings);
  }
  return await hasLocationAlwaysPermission();
}
