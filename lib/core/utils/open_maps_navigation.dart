import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../navigation/navigation_app.dart';
import '../navigation/navigation_app_detector.dart';
import '../navigation/navigation_uri_builder.dart';
import '../providers/navigation_preference_provider.dart';
import '../widgets/navigation_app_picker_sheet.dart';

/// Opens turn-by-turn directions using the user's preferred navigation app.
class OpenMapsNavigation {
  OpenMapsNavigation._();

  /// Opens directions respecting saved preference or showing the picker sheet.
  static Future<bool> launch(
    BuildContext? context,
    double lat,
    double lng,
  ) async {
    if (context == null || !context.mounted) {
      return _launchApp(NavigationApp.googleMaps, lat, lng);
    }

    final preference = await readNavigationPreference();
    if (!context.mounted) return false;

    if (preference == NavigationApp.systemSelection) {
      return _launchWithPicker(context, lat, lng);
    }

    final installed = await NavigationAppDetector.isInstalled(preference);
    if (!context.mounted) return false;
    if (!installed) {
      return _launchWithPicker(context, lat, lng);
    }

    final launched = await _launchApp(preference, lat, lng);
    if (launched) return true;

    if (!context.mounted) return false;
    return _launchWithPicker(context, lat, lng);
  }

  /// Back-compat alias — launches with preference flow.
  static Future<bool> confirmAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) =>
      launch(context, lat, lng);

  /// Back-compat alias — launches with preference flow.
  static Future<void> pickTravelModeAndLaunch(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    await launch(context, lat, lng);
  }

  static Future<bool> _launchWithPicker(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    final available = await NavigationAppDetector.availableApps();
    if (!context.mounted) return false;

    if (available.isEmpty) {
      return _launchSystemFallback(context, lat, lng);
    }

    if (!context.mounted) return false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showNavigationAppPickerSheet(
      context: context,
      availableApps: available,
      isDark: isDark,
      onLaunch: (app) => _launchApp(app, lat, lng),
    );

    if (result == null) return false;

    if (result.rememberChoice && context.mounted) {
      try {
        await ProviderScope.containerOf(context)
            .read(navigationPreferenceProvider.notifier)
            .setPreference(result.app);
      } catch (_) {
        await saveNavigationPreference(result.app);
      }
    }

    return true;
  }

  static Future<bool> _launchSystemFallback(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    final uris = NavigationUriBuilder.urisFor(
      NavigationApp.systemSelection,
      lat,
      lng,
    );
    final launched = await _tryUris(uris);
    if (launched) return true;
    if (!context.mounted) return false;
    await _showLaunchFailed(context);
    return false;
  }

  static Future<bool> _launchApp(
    NavigationApp app,
    double lat,
    double lng,
  ) async {
    final uris = NavigationUriBuilder.urisFor(app, lat, lng);
    return _tryUris(uris);
  }

  static Future<bool> _tryUris(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        final didLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (didLaunch) return true;
      } catch (_) {}
    }
    return false;
  }

  static Future<void> _showLaunchFailed(BuildContext context) async {
    if (!context.mounted) return;
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

  /// Direct launch for a specific app (used by tests or explicit callers).
  static Future<bool> launchDirections(
    double lat,
    double lng, {
    BuildContext? context,
    NavigationApp app = NavigationApp.systemSelection,
  }) async {
    final launched = await _launchApp(app, lat, lng);
    if (launched) return true;

    if (app == NavigationApp.systemSelection && !kIsWeb && Platform.isAndroid) {
      final fallback = NavigationUriBuilder.urisFor(
        NavigationApp.systemSelection,
        lat,
        lng,
      );
      if (await _tryUris(fallback)) return true;
    }

    if (context?.mounted == true) {
      await _showLaunchFailed(context!);
    }
    return false;
  }
}
