import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/calling/calling_scope.dart';
import '../../features/moderator/providers/moderator_provider.dart';
import '../utils/app_logger.dart';

/// Maps pilgrim user id → gender / profile picture for CallKit when FCM omits them.
class CallerGenderCache {
  CallerGenderCache._();

  static const String prefsKey = 'pilgrim_gender_by_user_id';
  static const String profilePicturePrefsKey =
      'pilgrim_profile_picture_by_user_id';

  static String? normalize(String? raw) {
    final g = raw?.toLowerCase().trim() ?? '';
    if (g.isEmpty) return null;
    if (g == 'female' || g == 'f' || g.startsWith('fem')) return 'female';
    if (g == 'male' || g == 'm' || g.startsWith('mal')) return 'male';
    return null;
  }

  static Future<void> syncFromGroups(List<ModeratorGroup> groups) async {
    final genderMap = await _readGenderMap();
    final pictureMap = await _readProfilePictureMap();
    for (final group in groups) {
      for (final p in group.pilgrims) {
        final id = p.id.trim();
        if (id.isEmpty) continue;
        final g = normalize(p.gender);
        if (g != null) {
          genderMap[id] = g;
        }
        final pic = p.profilePicture?.trim();
        if (pic != null && pic.isNotEmpty) {
          pictureMap[id] = pic;
        }
      }
    }
    await _writeGenderMap(genderMap);
    await _writeProfilePictureMap(pictureMap);
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

    final map = await _readGenderMap();
    final cached = normalize(map[id]);
    if (cached != null) {
      AppLogger.d('[CallerGenderCache] prefs gender=$cached id=$id');
    }
    return cached;
  }

  /// Resolves pilgrim [profile_picture] for CallKit when FCM/socket omit it.
  static Future<String?> resolveProfilePicture(String callerId) async {
    final id = callerId.trim();
    if (id.isEmpty) return null;

    final c = CallingScope.riverpod;
    if (c != null) {
      for (final group in c.read(moderatorProvider).groups) {
        for (final p in group.pilgrims) {
          if (p.id == id) {
            final pic = p.profilePicture?.trim();
            if (pic != null && pic.isNotEmpty) {
              AppLogger.d(
                '[CallerGenderCache] live dashboard profile_picture id=$id',
              );
              return pic;
            }
          }
        }
      }
    }

    final map = await _readProfilePictureMap();
    final cached = map[id]?.trim();
    if (cached != null && cached.isNotEmpty) {
      AppLogger.d('[CallerGenderCache] prefs profile_picture id=$id');
      return cached;
    }
    return null;
  }

  static Future<Map<String, String>> _readGenderMap() async {
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

  static Future<void> _writeGenderMap(Map<String, String> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(map));
    } catch (_) {}
  }

  static Future<Map<String, String>> _readProfilePictureMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(profilePicturePrefsKey);
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

  static Future<void> _writeProfilePictureMap(Map<String, String> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(profilePicturePrefsKey, jsonEncode(map));
    } catch (_) {}
  }
}
