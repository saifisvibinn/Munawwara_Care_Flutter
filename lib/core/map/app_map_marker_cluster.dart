import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import 'app_map_tiles.dart';

/// Shared marker clustering (zoom-to-bounds + spiderfy) for [FlutterMap].
///
/// Keeps dense pins readable; use a separate [MarkerLayer] for “You” / pick pin
/// so they are never merged into a cluster.
class AppMapMarkerCluster {
  AppMapMarkerCluster._();

  static Widget _clusterBubble(List<Marker> markers) {
    final n = markers.length;
    final label = n > 99 ? '99+' : '$n';
    return Container(
      width: 44.w,
      height: 44.w,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w800,
            fontSize: 14.sp,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// [markerChildBehavior]: pass [true] when marker children use their own
  /// taps (e.g. [GestureDetector]); avoids the cluster wrapper stealing taps.
  static MarkerClusterLayerOptions options({
    required List<Marker> markers,
    bool markerChildBehavior = true,
    int maxClusterRadius = 72,
  }) {
    return MarkerClusterLayerOptions(
      markers: markers,
      markerChildBehavior: markerChildBehavior,
      rotate: true,
      size: Size(44.w, 44.w),
      alignment: Alignment.center,
      maxClusterRadius: maxClusterRadius,
      spiderfyCluster: true,
      zoomToBoundsOnClick: true,
      showPolygon: false,
      spiderfyCircleRadius: 48,
      spiderfySpiralDistanceMultiplier: 2,
      circleSpiralSwitchover: 10,
      padding: EdgeInsets.all(28.w),
      maxZoom: AppMapTiles.mapMaxZoom,
      centerMarkerOnClick: false,
      animationsOptions: const AnimationsOptions(
        zoom: Duration(milliseconds: 380),
        fitBound: Duration(milliseconds: 380),
        spiderfy: Duration(milliseconds: 420),
      ),
      builder: (ctx, m) => _clusterBubble(m),
    );
  }

  static Widget layer({
    required List<Marker> markers,
    bool markerChildBehavior = true,
    int maxClusterRadius = 72,
  }) {
    if (markers.isEmpty) {
      return const SizedBox.shrink();
    }
    return MarkerClusterLayerWidget(
      options: options(
        markers: markers,
        markerChildBehavior: markerChildBehavior,
        maxClusterRadius: maxClusterRadius,
      ),
    );
  }
}
