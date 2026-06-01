import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/calling/calling_scope.dart';
import '../../features/moderator/providers/moderator_provider.dart';
import '../utils/app_logger.dart';

/// Maps pilgrim user id → gender for CallKit when FCM/socket omit [callerGender].
class CallerGenderCache {
  CallerGenderCache._();

  static const String prefsKey = 'pilgrim_gender_by_user_id';

  static String? normalize(String? raw) {
    final g = raw?.toLowerCase().trim() ?? '';
    if (g.isEmpty) return null;
    if (g == 'female' || g == 'f' || g.startsWith('fem')) return 'female';
    if (g == 'male' || g == 'm' || g.startsWith('mal')) return 'male';
    return null;
  }

  static Future<void> syncFromGroups(List<ModeratorGroup> groups) async {
    final map = await _readMap();
    for (final group in groups) {
      for (final p in group.pilgrims) {
        final id = p.id.trim();
        final g = normalize(p.gender);
        if (id.isNotEmpty && g != null) {
          map[id] = g;
        }
      }
    }
    await _writeMap(map);
  }

  /// Resolves pilgrim gender for incoming-call avatar (FCM / CallKit / UI).
  static Future<String?> resolve(String callerId) async {
    final id = callerId.trim();
    if (id.isEmpty) return null;

    final c = CallingScope.riverpod;
    if (c != null) {
      for (final group in c.read(moderatorProvider).groups) {
        for (final p in group.pilgrims) {
          if (p.id == id) {
            final g = normalize(p.gender);
            if (g != null) {
              AppLogger.d('[CallerGenderCache] live dashboard gender=$g id=$id');
              return g;
            }
          }
        }
      }
    }

    final map = await _readMap();
    final cached = normalize(map[id]);
    if (cached != null) {
      AppLogger.d('[CallerGenderCache] prefs gender=$cached id=$id');
    }
    return cached;
  }

  static Future<Map<String, String>> _readMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeMap(Map<String, String> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(map));
    } catch (_) {}
  }
}
