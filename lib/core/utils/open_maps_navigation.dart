import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/maps_app_picker_dialog.dart';
import '../widgets/travel_mode_picker_dialog.dart';

export '../widgets/travel_mode_picker_dialog.dart' show MapsTravelMode;

/// Opens walking/driving navigation in Google Maps or Apple Maps.
class OpenMapsNavigation {
  OpenMapsNavigation._();

  static Future<bool> _confirm(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('explore_open_maps_title'.tr()),
        content: Text('explore_open_maps_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('dialog_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('explore_open_maps_open'.tr()),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  static Future<void> _showLaunchFailed(BuildContext? context) async {
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('explore_open_maps_failed_title'.tr()),
        content: SelectableText.rich(
          TextSpan(
            text: 'explore_open_maps_failed_body'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              color: Colors.red.shade700,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog_ok'.tr()),
          ),
        ],
      ),
    );
  }

  /// Shows confirm dialog, then maps-app picker (iOS), then launches directions.
  static Future<bool> confirmAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    if (!context.mounted) return false;
    final ok = await _confirm(context);
    if (!ok || !context.mounted) return false;

    final app = await showMapsAppPickerDialog(context);
    if (app == null || !context.mounted) return false;

    return launchDirections(
      lat,
      lng,
      MapsTravelMode.walking,
      mapsApp: app,
      context: context,
    );
  }

  /// Asks walking vs car, then maps app (iOS), then opens directions.
  static Future<void> pickTravelModeAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    if (!context.mounted) return;
    final mode = await showTravelModePickerDialog(context);
    if (mode == null || !context.mounted) return;

    final app = await showMapsAppPickerDialog(context);
    if (app == null || !context.mounted) return;

    await launchDirections(lat, lng, mode, mapsApp: app, context: context);
  }

  static List<Uri> _urisFor(
    double lat,
    double lng,
    MapsTravelMode mode,
    ExternalMapsApp mapsApp,
  ) {
    if (mapsApp == ExternalMapsApp.appleMaps) {
      final dirflg = mode == MapsTravelMode.walking ? 'w' : 'd';
      return [
        Uri.parse('maps://?daddr=$lat,$lng&dirflg=$dirflg'),
        Uri.parse('http://maps.apple.com/?daddr=$lat,$lng&dirflg=$dirflg'),
      ];
    }

    final navMode = mode == MapsTravelMode.walking ? 'w' : 'd';
    final travelMode = mode == MapsTravelMode.walking ? 'walking' : 'driving';
    return [
      Uri.parse('google.navigation:q=$lat,$lng&mode=$navMode'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng&travelmode=$travelMode',
      ),
    ];
  }

  /// Launches directions in the chosen external maps app.
  static Future<bool> launchDirections(
    double lat,
    double lng,
    MapsTravelMode mode, {
    ExternalMapsApp? mapsApp,
    BuildContext? context,
  }) async {
    final resolvedApp = mapsApp ??
        (kIsWeb || !Platform.isIOS
            ? ExternalMapsApp.googleMaps
            : ExternalMapsApp.appleMaps);

    for (final uri in _urisFor(lat, lng, mode, resolvedApp)) {
      try {
        final didLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (didLaunch) return true;
      } catch (_) {}
    }

    await _showLaunchFailed(context?.mounted == true ? context : null);
    return false;
  }
}
