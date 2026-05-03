import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mapbox raster tiles for [flutter_map] (set `MAPBOX_ACCESS_TOKEN` in `.env`).
/// Falls back to OpenStreetMap if the token is missing.
///
/// Uses Mapbox Light/Dark v11 for a minimal in-app look; turn-by-turn stays in Google Maps.
/// https://docs.mapbox.com/api/maps/raster-tiles/
class AppMapTiles {
  AppMapTiles._();

  static const userAgentPackageName = 'com.munawwaracare.app';

  static const _osmUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static String? get _accessToken {
    final t = dotenv.env['MAPBOX_ACCESS_TOKEN']?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static bool get usingMapbox => _accessToken != null;

  static String urlTemplate(bool isDark) {
    final token = _accessToken;
    if (token == null) return _osmUrl;
    final style = isDark ? 'dark-v11' : 'light-v11';
    return 'https://api.mapbox.com/styles/v1/mapbox/$style/tiles/256/{z}/{x}/{y}'
        '?access_token=$token';
  }

  static TileLayer tileLayer({required bool isDark}) {
    return TileLayer(
      urlTemplate: urlTemplate(isDark),
      userAgentPackageName: userAgentPackageName,
    );
  }

  /// Tiles plus attribution (Mapbox + OSM when using Mapbox).
  static List<Widget> baseLayers({required bool isDark}) {
    final mapbox = usingMapbox;
    return [
      tileLayer(isDark: isDark),
      RichAttributionWidget(
        popupInitialDisplayDuration: const Duration(seconds: 4),
        animationConfig: const ScaleRAWA(),
        showFlutterMapAttribution: false,
        attributions: [
          if (mapbox)
            TextSourceAttribution(
              '© Mapbox',
              onTap: () async {
                final uri = Uri.parse('https://www.mapbox.com/about/maps/');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          TextSourceAttribution(
            '© OpenStreetMap',
            onTap: () async {
              final uri = Uri.parse('https://www.openstreetmap.org/copyright');
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
