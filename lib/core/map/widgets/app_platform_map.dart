import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../widgets/glass/app_glass_theme.dart';
import '../app_map_controller.dart';
import '../app_map_marker_data.dart';
import '../app_map_tiles.dart';

typedef AppMapMarkerTap = void Function(AppMapMarkerData marker);
typedef AppFlutterMapLayerBuilder = List<Widget> Function(BuildContext context);
typedef AppMapPositionChanged = void Function(LatLng center, bool hasGesture);

/// Forward pan/pinch/tap to MKMapView. [EagerGestureRecognizer] is safe here
/// because map routes disable iOS interactive back-swipe ([appMapPageRoute]).
final Set<Factory<OneSequenceGestureRecognizer>> kIosMapGestureRecognizers = {
  Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
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
    this.iosNativeScrollEdges = false,
    this.iosDashboardBottomEdge = false,
    this.iosScrollEdgeTopHeight,
    this.iosScrollEdgeBottomHeight,
  });

  final AppMapController controller;
  final LatLng initialCenter;
  final double initialZoom;
  final bool isDark;
  final List<AppMapMarkerData> markers;
  final AppMapMarkerTap? onMarkerTap;
  final AppMapPositionChanged? onPositionChanged;
  final bool showsUserLocation;
  final AppFlutterMapLayerBuilder? flutterLayers;

  /// When true on iOS, native [UIVisualEffectView] edge bands are drawn inside
  /// MapKit (Flutter scroll overlays should be omitted on the map screen).
  final bool iosNativeScrollEdges;

  /// Uses [AppGlassTheme.mapScrollEdgeBottomExtent] for the bottom band.
  final bool iosDashboardBottomEdge;

  /// Optional fixed heights (logical px). When null, derived from [BuildContext].
  final double? iosScrollEdgeTopHeight;
  final double? iosScrollEdgeBottomHeight;

  @override
  State<AppPlatformMap> createState() => _AppPlatformMapState();
}

class _AppPlatformMapState extends State<AppPlatformMap> {
  MethodChannel? _iosChannel;
  MapController? _flutterMapController;
  Timer? _markerPushDebounce;
  int? _iosViewId;
  bool _iosChannelReady = false;
  double? _lastSyncedTop;
  double? _lastSyncedBottom;

  bool get _useMapKit => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_useMapKit) {
      // Heights synced after platform view is created.
    } else {
      _flutterMapController = MapController();
      widget.controller.attachFlutter(_flutterMapController!);
    }
  }

  Map<String, dynamic> _buildIosCreationParams({
    required double top,
    required double bottom,
  }) {
    return <String, dynamic>{
      'latitude': widget.initialCenter.latitude,
      'longitude': widget.initialCenter.longitude,
      'zoom': AppMapTiles.clampMapZoom(widget.initialZoom),
      'isDark': widget.isDark,
      'showsUserLocation': widget.showsUserLocation,
      'edgeBlurEnabled': widget.iosNativeScrollEdges,
      'edgeBlurTopHeight': top,
      'edgeBlurBottomHeight': bottom,
    };
  }

  (double top, double bottom) _resolveScrollEdgeHeights(BuildContext context) {
    if (!widget.iosNativeScrollEdges) return (0, 0);
    final top = widget.iosScrollEdgeTopHeight ??
        AppGlassTheme.scrollFadeTopExtent(context);
    final bottom = widget.iosScrollEdgeBottomHeight ??
        (widget.iosDashboardBottomEdge
            ? AppGlassTheme.mapScrollEdgeBottomExtent(context)
            : AppGlassTheme.scrollFadeBottomExtentStandalone(context));
    return (top, bottom);
  }

  void _syncIosScrollEdges(BuildContext context) {
    if (!_useMapKit || !_iosChannelReady) return;

    if (!widget.iosNativeScrollEdges) {
      if (_lastSyncedTop == -1 && _lastSyncedBottom == -1) return;
      _lastSyncedTop = -1;
      _lastSyncedBottom = -1;
      unawaited(widget.controller.setIosScrollEdges(enabled: false));
      return;
    }

    final (top, bottom) = _resolveScrollEdgeHeights(context);
    if (top == _lastSyncedTop && bottom == _lastSyncedBottom) {
      return;
    }
    _lastSyncedTop = top;
    _lastSyncedBottom = bottom;
    unawaited(
      widget.controller.setIosScrollEdges(
        topHeight: top,
        bottomHeight: bottom,
        enabled: true,
      ),
    );
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
    if (_useMapKit) {
      if (oldWidget.isDark != widget.isDark && _iosChannelReady) {
        unawaited(widget.controller.setIosMapAppearance(isDark: widget.isDark));
      }
      if (_iosChannel != null &&
          !_markersEqual(oldWidget.markers, widget.markers)) {
        _scheduleMarkerPush();
      }
      if (oldWidget.iosNativeScrollEdges != widget.iosNativeScrollEdges ||
          oldWidget.iosDashboardBottomEdge != widget.iosDashboardBottomEdge ||
          oldWidget.iosScrollEdgeTopHeight != widget.iosScrollEdgeTopHeight ||
          oldWidget.iosScrollEdgeBottomHeight !=
              widget.iosScrollEdgeBottomHeight) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncIosScrollEdges(context);
        });
      }
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
    _iosChannelReady = true;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncIosScrollEdges(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_useMapKit) {
      final (top, bottom) = _resolveScrollEdgeHeights(context);
      final creationParams = _buildIosCreationParams(top: top, bottom: bottom);

      return RepaintBoundary(
        child: SizedBox.expand(
          child: UiKitView(
            viewType: 'MunawwaraMapKit',
            layoutDirection: TextDirection.ltr,
            gestureRecognizers: kIosMapGestureRecognizers,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onIosCreated,
          ),
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
