import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// OpenStreetMap raster tiles for [flutter_map]. Turn-by-turn stays in Google
/// Maps.
///
/// https://wiki.openstreetmap.org/wiki/Tile_usage_policy
class AppMapTiles {
  AppMapTiles._();

  /// Zoom limits for Android/web [FlutterMap] + OSM tiles (keeps tile usage reasonable).
  static const double mapMinZoom = 15;
  static const double mapMaxZoom = 17;

  /// Programmatic camera zoom. OSM stays capped; MapKit (iOS) uses the requested level.
  static double clampMapZoom(double zoom) {
    if (!kIsWeb && Platform.isIOS) return zoom;
    return zoom.clamp(mapMinZoom, mapMaxZoom);
  }

  /// Kaaba / central Mecca — default when GPS is unavailable.
  static const LatLng fallbackMapCenter = LatLng(21.3891, 39.8579);

  static const userAgentPackageName = 'com.munawwaracare.app';

  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// [isDark] is kept for API stability; OSM’s public tile server serves one
  /// cartographic style for both themes.
  static TileLayer tileLayer({required bool isDark}) {
    return TileLayer(
      urlTemplate: _osmUrl,
      userAgentPackageName: userAgentPackageName,
      // Avoid IMAGE RESOURCE SERVICE crashes when offline / OSM unreachable.
      tileProvider: NetworkTileProvider(
        silenceExceptions: true,
      ),
    );
  }

  /// Tiles plus OpenStreetMap attribution.
  static List<Widget> baseLayers({required bool isDark}) {
    return [
      tileLayer(isDark: isDark),
      RichAttributionWidget(
        popupInitialDisplayDuration: const Duration(seconds: 4),
        animationConfig: const ScaleRAWA(),
        showFlutterMapAttribution: false,
        attributions: [
          TextSourceAttribution(
            '© OpenStreetMap',
            onTap: () async {
              final uri = Uri.parse(
                'https://www.openstreetmap.org/copyright',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    ];
  }
}
