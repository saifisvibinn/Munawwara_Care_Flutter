import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/travel_mode_picker_dialog.dart';

/// Opens walking navigation to [lat],[lng] in an external maps app.
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

  /// Shows confirm dialog, then tries google.navigation / geo / https.
  /// Returns true if an app handled a launch URL successfully.
  static Future<bool> confirmAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    if (!context.mounted) return false;
    final ok = await _confirm(context);
    if (!ok || !context.mounted) return false;

    final uris = <Uri>[
      Uri.parse('google.navigation:q=$lat,$lng&mode=w'),
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
      Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      ),
    ];

    for (final uri in uris) {
      try {
        final didLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (didLaunch) return true;
      } catch (_) {}
    }

    if (!context.mounted) return false;
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
    return false;
  }

  /// Asks walking vs car, then opens Google Maps directions to [lat],[lng].
  static Future<void> pickTravelModeAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    if (!context.mounted) return;
    final mode = await showTravelModePickerDialog(context);
    if (mode == null || !context.mounted) return;
    await launchDirections(lat, lng, mode, context: context);
  }

  /// Tries google.navigation then https Google Maps directions URL.
  static Future<bool> launchDirections(
    double lat,
    double lng,
    MapsTravelMode mode, {
    BuildContext? context,
  }) async {
    final navMode = mode == MapsTravelMode.walking ? 'w' : 'd';
    final travelMode = mode == MapsTravelMode.walking ? 'walking' : 'driving';
    final uris = <Uri>[
      Uri.parse('google.navigation:q=$lat,$lng&mode=$navMode'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$lat,$lng&travelmode=$travelMode',
      ),
    ];
    for (final uri in uris) {
      try {
        final didLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (didLaunch) return true;
      } catch (_) {}
    }
    if (context == null || !context.mounted) return false;
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
    return false;
  }
}
