import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../navigation/navigation_app.dart';

const _kNavigationAppPreferenceKey = 'navigation_app_preference';

class NavigationPreferenceNotifier extends Notifier<NavigationApp> {
  @override
  NavigationApp build() {
    _load();
    return NavigationApp.systemSelection;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kNavigationAppPreferenceKey);
    state = NavigationAppStorage.fromStorage(stored);
  }

  Future<void> setPreference(NavigationApp app) async {
    state = app;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_kNavigationAppPreferenceKey, app.storageKey),
    );
  }
}

final navigationPreferenceProvider =
    NotifierProvider<NavigationPreferenceNotifier, NavigationApp>(
  NavigationPreferenceNotifier.new,
);

/// Reads the stored preference without requiring a [WidgetRef].
Future<NavigationApp> readNavigationPreference() async {
  final prefs = await SharedPreferences.getInstance();
  return NavigationAppStorage.fromStorage(
    prefs.getString(_kNavigationAppPreferenceKey),
  );
}

/// Persists a navigation app preference.
Future<void> saveNavigationPreference(NavigationApp app) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kNavigationAppPreferenceKey, app.storageKey);
}
