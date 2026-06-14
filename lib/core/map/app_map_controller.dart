import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'app_map_tiles.dart';

/// Unified camera control for FlutterMap (Android) and MapKit (iOS).
class AppMapController {
  AppMapController();

  /// Keeps [AppPlatformMap] state alive across dashboard rebuilds (iOS MapKit).
  final GlobalKey mapViewKey = GlobalKey(debugLabel: 'AppPlatformMap');

  MapController? _flutter;
  MethodChannel? _iosChannel;
  LatLng? _lastCenter;
  int? _iosViewId;

  void attachFlutter(MapController controller) {
    _flutter = controller;
    _lastCenter = controller.camera.center;
  }

  void attachIosView(int viewId) {
    _iosViewId = viewId;
    _iosChannel = MethodChannel('com.munawwaracare/mapkit_$viewId');
  }

  void detachIosView(int viewId) {
    if (_iosViewId != viewId) return;
    _iosViewId = null;
    _iosChannel = null;
  }

  /// Latest map center (works on iOS MapKit and FlutterMap).
  LatLng get center =>
      _lastCenter ?? _flutter?.camera.center ?? AppMapTiles.fallbackMapCenter;

  void updateCenter(LatLng center) => _lastCenter = center;

  void move(LatLng center, double zoom, {bool preserveZoom = false}) {
    final clamped = AppMapTiles.clampMapZoom(zoom);
    _lastCenter = center;
    if (!kIsWeb && Platform.isIOS && _iosChannel != null) {
      _iosChannel!.invokeMethod('moveCamera', {
        'latitude': center.latitude,
        'longitude': center.longitude,
        if (!preserveZoom) 'zoom': clamped,
        'preserveZoom': preserveZoom,
      });
      return;
    }
    if (preserveZoom) {
      _flutter?.move(center, _flutter!.camera.zoom);
    } else {
      _flutter?.move(center, clamped);
    }
  }

  Future<void> setMarkers(List<Map<String, dynamic>> markers) async {
    if (kIsWeb || !Platform.isIOS || _iosChannel == null) return;
    await _iosChannel!.invokeMethod('setMarkers', {'markers': markers});
  }

  /// Re-enable MKMapView pan/zoom after gesture conflicts (e.g. cancelled back-swipe).
  Future<void> restoreGestures() async {
    if (kIsWeb || !Platform.isIOS || _iosChannel == null) return;
    try {
      await _iosChannel!.invokeMethod('restoreGestures');
    } catch (_) {}
  }

  void dispose() {
    _flutter?.dispose();
    _flutter = null;
    _iosViewId = null;
    _iosChannel = null;
    _lastCenter = null;
  }
}

AppMapController createAppMapController() => AppMapController();
