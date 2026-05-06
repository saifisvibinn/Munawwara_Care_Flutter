import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists last-known API payloads as JSON per logged-in user for offline use.
class AppDataCache {
  AppDataCache._();

  static const _dirName = 'app_data_cache';

  static const authMeFile = 'auth_me.json';
  static const pilgrimProfileFile = 'pilgrim_profile.json';
  static const pilgrimMyGroupFile = 'pilgrim_my_group.json';
  static const moderatorDashboardFile = 'moderator_dashboard.json';
  static const notificationsFile = 'notifications.json';
  static const exploreNearbyPoisFile = 'explore_nearby_pois.json';

  static String messagesFile(String groupId) => 'messages_$groupId.json';

  static String suggestedAreasFile(String groupId) =>
      'suggested_areas_$groupId.json';

  /// Decoded JSON maps are not always `Map<String, dynamic>` at runtime.
  static Map<String, dynamic>? jsonMap(Object? v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static Future<Directory> _userDir(String userId) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$_dirName/$userId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Writes [payload] under a wrapper with UTC [savedAt] for stale UI hints.
  static Future<void> write(
    String userId,
    String fileName,
    Object? payload,
  ) async {
    if (userId.isEmpty) return;
    try {
      final dir = await _userDir(userId);
      final file = File('${dir.path}/$fileName');
      final wrapper = <String, dynamic>{
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'data': payload,
      };
      await file.writeAsString(jsonEncode(wrapper));
    } catch (_) {}
  }

  /// Returns `{ savedAt, data }` or null if missing / invalid.
  static Future<Map<String, dynamic>?> readEnvelope(
    String userId,
    String fileName,
  ) async {
    if (userId.isEmpty) return null;
    try {
      final dir = await _userDir(userId);
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Object?> readData(String userId, String fileName) async {
    final env = await readEnvelope(userId, fileName);
    return env?['data'];
  }

  static Future<DateTime?> readSavedAt(String userId, String fileName) async {
    final env = await readEnvelope(userId, fileName);
    final s = env?['savedAt']?.toString();
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

  static Future<void> deleteFile(String userId, String fileName) async {
    if (userId.isEmpty) return;
    try {
      final dir = await _userDir(userId);
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Removes all cached files for [userId].
  static Future<void> clearForUser(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    try {
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}/$_dirName/$userId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
