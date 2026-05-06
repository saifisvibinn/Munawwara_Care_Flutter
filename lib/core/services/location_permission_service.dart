import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks if both when-in-use and always-on permissions are granted.
Future<bool> hasLocationAlwaysPermission() async {
  if (kIsWeb) return false;
  final whenInUse = await Permission.locationWhenInUse.isGranted;
  final always = await Permission.locationAlways.isGranted;
  return whenInUse && always;
}

/// Requests location **while in use**, then **always / background** on mobile so
/// updates can continue when the app is not in the foreground (within OS limits;
/// Android may still require a foreground service for uninterrupted tracking).
Future<bool> requestLocationPermissionsFlow() async {
  if (kIsWeb) return false;

  final whenInUse = await Permission.locationWhenInUse.request();
  if (!whenInUse.isGranted) return false;

  // Align Geolocator with OS state so [getCurrentPosition] / streams work
  // immediately after login (some builds lag behind permission_handler alone).
  var geo = await Geolocator.checkPermission();
  if (geo == LocationPermission.denied) {
    geo = await Geolocator.requestPermission();
  }
  if (geo == LocationPermission.denied ||
      geo == LocationPermission.deniedForever) {
    return false;
  }

  final always = await Permission.locationAlways.status;
  if (!always.isGranted) {
    await Permission.locationAlways.request();
  }

  return await hasLocationAlwaysPermission();
}
