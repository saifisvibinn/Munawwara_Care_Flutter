import 'package:easy_localization/easy_localization.dart';

/// User's preferred navigation app for turn-by-turn directions.
enum NavigationApp {
  systemSelection,
  appleMaps,
  googleMaps,
}

extension NavigationAppStorage on NavigationApp {
  String get storageKey => switch (this) {
        NavigationApp.systemSelection => 'system',
        NavigationApp.appleMaps => 'apple',
        NavigationApp.googleMaps => 'google',
      };

  static NavigationApp fromStorage(String? value) => switch (value) {
        'apple' => NavigationApp.appleMaps,
        'google' => NavigationApp.googleMaps,
        _ => NavigationApp.systemSelection,
      };

  /// Localized label for settings disclosure row and picker sheets.
  String get displayName => switch (this) {
        NavigationApp.systemSelection => 'settings_nav_app_system'.tr(),
        NavigationApp.appleMaps => 'maps_app_apple'.tr(),
        NavigationApp.googleMaps => 'maps_app_google'.tr(),
      };

  String? get displaySubtitle => switch (this) {
        NavigationApp.systemSelection => 'settings_nav_app_system_sub'.tr(),
        NavigationApp.appleMaps => 'maps_app_apple_sub'.tr(),
        NavigationApp.googleMaps => 'maps_app_google_sub'.tr(),
      };
}
