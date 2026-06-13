import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_map_controller.dart';
import '../app_map_marker_data.dart';
import '../app_map_tiles.dart';

typedef AppMapMarkerTap = void Function(AppMapMarkerData marker);
typedef AppFlutterMapLayerBuilder = List<Widget> Function(BuildContext context);
typedef AppMapPositionChanged = void Function(LatLng center, bool hasGesture);

/// Forward pan/pinch/tap to MKMapView — one factory per recognizer type only.
final Set<Factory<OneSequenceGestureRecognizer>> kIosMapGestureRecognizers = {
  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
};

/// In-app map: native Apple MapKit on iOS, [FlutterMap] elsewhere.
class AppPlatformMap extends StatefulWidget {
  const AppPlatformMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    required this.initialZoom,
    required this.isDark,
    required this.markers,
    this.onMarkerTap,
    this.onPositionChanged,
    this.showsUserLocation = false,
    this.flutterLayers,
  });

  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final bool isDark;
  final List<AppMapMarkerData> markers;
  final AppMapMarkerTap? onMarkerTap;
  final AppMapPositionChanged? onPositionChanged;
  final bool showsUserLocation;

  /// Extra flutter_map layers (cluster markers etc.) used on Android/web.
  final AppFlutterMapLayerBuilder? flutterLayers;

  @override
  State<AppPlatformMap> createState() => _AppPlatformMapState();
}

class _AppPlatformMapState extends State<AppPlatformMap> {
  MethodChannel? _iosChannel;
  MapController? _flutterMapController;
  Map<String, dynamic>? _iosCreationParams;
  Timer? _markerPushDebounce;
  int? _iosViewId;

  bool get _useMapKit => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_useMapKit) {
      _iosCreationParams = <String, dynamic>{
        'latitude': widget.initialCenter.latitude,
        'longitude': widget.initialCenter.longitude,
        'zoom': AppMapTiles.clampMapZoom(widget.initialZoom),
        'isDark': widget.isDark,
        'showsUserLocation': widget.showsUserLocation,
      };
    } else {
      _flutterMapController = MapController();
      widget.controller.attachFlutter(_flutterMapController!);
    }
  }

  @override
  void dispose() {
    _markerPushDebounce?.cancel();
    if (_iosViewId != null) {
      widget.controller.detachIosView(_iosViewId!);
    }
    _iosChannel?.setMethodCallHandler(null);
    _iosChannel = null;
    _flutterMapController?.dispose();
    super.dispose();
  }

  void _scheduleMarkerPush() {
    _markerPushDebounce?.cancel();
    _markerPushDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_pushMarkers());
    });
  }

  @override
  void didUpdateWidget(covariant AppPlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useMapKit &&
        _iosChannel != null &&
        !_markersEqual(oldWidget.markers, widget.markers)) {
      _scheduleMarkerPush();
    }
  }

  bool _markersEqual(
    List<AppMapMarkerData> a,
    List<AppMapMarkerData> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
      if (a[i].point.latitude != b[i].point.latitude ||
          a[i].point.longitude != b[i].point.longitude) {
        return false;
      }
    }
    return true;
  }

  Future<void> _pushMarkers() async {
    final payload = widget.markers.map((m) => m.toMapKitJson()).toList();
    await widget.controller.setMarkers(payload);
  }

  void _onIosCreated(int viewId) {
    _iosViewId = viewId;
    widget.controller.attachIosView(viewId);
    _iosChannel = MethodChannel('com.munawwaracare/mapkit_$viewId');
    _iosChannel!.setMethodCallHandler((call) async {
      if (call.method == 'onMarkerTap') {
        final id = (call.arguments as Map)['id'] as String?;
        if (id == null) return null;
        final marker = widget.markers.where((m) => m.id == id).firstOrNull;
        if (marker != null) {
          widget.onMarkerTap?.call(marker);
        }
      } else if (call.method == 'onRegionChanged') {
        final args = call.arguments as Map;
        final lat = args['latitude'] as double?;
        final lng = args['longitude'] as double?;
        final hasGesture = args['hasGesture'] as bool? ?? false;
        if (lat != null && lng != null) {
          final center = LatLng(lat, lng);
          widget.controller.updateCenter(center);
          if (hasGesture) {
            _markerPushDebounce?.cancel();
          }
          widget.onPositionChanged?.call(center, hasGesture);
        }
      }
      return null;
    });
    _pushMarkers();
  }

  @override
  Widget build(BuildContext context) {
    if (_useMapKit) {
      return SizedBox.expand(
        child: UiKitView(
          viewType: 'MunawwaraMapKit',
          layoutDirection: TextDirection.ltr,
          gestureRecognizers: kIosMapGestureRecognizers,
          creationParams: _iosCreationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onIosCreated,
        ),
      );
    }

    final flutterController = _flutterMapController!;
    return FlutterMap(
      mapController: flutterController,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: AppMapTiles.clampMapZoom(widget.initialZoom),
        minZoom: AppMapTiles.mapMinZoom,
        maxZoom: AppMapTiles.mapMaxZoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onPositionChanged: (pos, hasGesture) {
          widget.controller.updateCenter(pos.center);
          widget.onPositionChanged?.call(pos.center, hasGesture);
        },
      ),
      children: [
        ...AppMapTiles.baseLayers(isDark: widget.isDark),
        if (widget.flutterLayers != null) ...widget.flutterLayers!(context),
      ],
    );
  }
}
