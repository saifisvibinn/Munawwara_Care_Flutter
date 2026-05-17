import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../features/auth/widgets/background_location_disclosure_dialog.dart';

const _oemChannel = MethodChannel('com.munawwaracare.andriod/oem_settings');

/// Checks if both when-in-use and always-on permissions are granted.
Future<bool> hasLocationAlwaysPermission() async {
  if (kIsWeb) return false;
  final whenInUse = await Permission.locationWhenInUse.isGranted;
  final always = await Permission.locationAlways.isGranted;
  return whenInUse && always;
}

/// Opens OEM app-permission UI (MIUI editor, etc.), not generic App info only.
Future<void> openLocationPermissionSettings() async {
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
Future<bool> requestLocationPermissionsFlow(BuildContext context) async {
  if (kIsWeb) return false;

  if (!await _ensureWhenInUseLocation()) {
    return false;
  }

  if (!context.mounted) return false;
  if (!await _ensureAlwaysLocation(context)) {
    return false;
  }

  return await hasLocationAlwaysPermission();
}

/// Uses [Geolocator] first (reliable on MIUI), then [permission_handler].
Future<bool> _ensureWhenInUseLocation() async {
  var geo = await Geolocator.checkPermission();

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings();
    return false;
  }

  if (geo == LocationPermission.denied) {
    geo = await Geolocator.requestPermission();
  }

  if (geo == LocationPermission.deniedForever) {
    await openLocationPermissionSettings();
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
    await openLocationPermissionSettings();
    return false;
  }

  if (handlerStatus.isDenied) {
    handlerStatus = await Permission.locationWhenInUse.request();
  }

  if (handlerStatus.isGranted) {
    return true;
  }

  if (handlerStatus.isPermanentlyDenied) {
    await openLocationPermissionSettings();
    return false;
  }

  if (handlerStatus.isDenied) {
    geo = await Geolocator.checkPermission();
    if (geo == LocationPermission.denied) {
      geo = await Geolocator.requestPermission();
    }
    if (geo == LocationPermission.deniedForever ||
        handlerStatus.isPermanentlyDenied) {
      await openLocationPermissionSettings();
      return false;
    }
    if (geo != LocationPermission.denied &&
        geo != LocationPermission.deniedForever) {
      return true;
    }
    if (Platform.isAndroid) {
      await openLocationPermissionSettings();
    }
    return false;
  }

  return false;
}

Future<bool> _ensureAlwaysLocation(BuildContext context) async {
  if (await Permission.locationAlways.isGranted) {
    return true;
  }

  if (!context.mounted) return false;
  final proceed = await showBackgroundLocationDisclosure(context);
  if (!proceed) return false;

  final alwaysResult = await Permission.locationAlways.request();
  if (alwaysResult.isGranted) {
    return true;
  }

  if (alwaysResult.isPermanentlyDenied) {
    await openLocationPermissionSettings();
    return false;
  }

  if (Platform.isAndroid && !alwaysResult.isGranted) {
    await openLocationPermissionSettings();
    return false;
  }

  return false;
}
