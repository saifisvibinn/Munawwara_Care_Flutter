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

  /// Shared zoom limits for every in-app [FlutterMap] (gesture + programmatic).
  static const double mapMinZoom = 15;
  static const double mapMaxZoom = 17;

  /// Use with [MapController.move] so zoom stays within [mapMinZoom]–[mapMaxZoom].
  static double clampMapZoom(double zoom) => zoom.clamp(mapMinZoom, mapMaxZoom);

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
