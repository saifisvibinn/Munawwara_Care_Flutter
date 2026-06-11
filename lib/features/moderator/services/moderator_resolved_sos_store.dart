import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One moderator-marked resolved SOS incident (local history).
class ModeratorResolvedSosRecord {
  final String resolveKey;
  final String pilgrimId;
  final String groupId;
  final String pilgrimName;
  final String groupName;
  final String? pilgrimGender;
  final String? pilgrimProfilePicture;
  final String? sosId;
  final double? lat;
  final double? lng;
  final int resolvedAtMs;

  const ModeratorResolvedSosRecord({
    required this.resolveKey,
    required this.pilgrimId,
    required this.groupId,
    required this.pilgrimName,
    required this.groupName,
    this.pilgrimGender,
    this.pilgrimProfilePicture,
    this.sosId,
    this.lat,
    this.lng,
    required this.resolvedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'resolve_key': resolveKey,
        'pilgrim_id': pilgrimId,
        'group_id': groupId,
        'pilgrim_name': pilgrimName,
        'group_name': groupName,
        'pilgrim_gender': pilgrimGender,
        'pilgrim_profile_picture': pilgrimProfilePicture,
        'sos_id': sosId,
        'lat': lat,
        'lng': lng,
        'resolved_at_ms': resolvedAtMs,
      };

  static ModeratorResolvedSosRecord fromJson(Map<String, dynamic> j) {
    return ModeratorResolvedSosRecord(
      resolveKey: j['resolve_key']?.toString() ?? '',
      pilgrimId: j['pilgrim_id']?.toString() ?? '',
      groupId: j['group_id']?.toString() ?? '',
      pilgrimName: j['pilgrim_name']?.toString() ?? '',
      groupName: j['group_name']?.toString() ?? '',
      pilgrimGender: j['pilgrim_gender']?.toString(),
      pilgrimProfilePicture: j['pilgrim_profile_picture']?.toString(),
      sosId: j['sos_id']?.toString(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      resolvedAtMs:
          (j['resolved_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// SharedPreferences list of resolved SOS rows (newest first).
class ModeratorResolvedSosStore {
  ModeratorResolvedSosStore._();

  static const _prefsKey = 'moderator_resolved_sos_v1';
  static const _maxItems = 80;

  static Future<List<ModeratorResolvedSosRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => ModeratorResolvedSosRecord.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),)
          .where((r) => r.resolveKey.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<ModeratorResolvedSosRecord> list) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = list.map((r) => r.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(encoded));
  }

  /// Inserts [record] at the front; trims to [_maxItems].
  static Future<void> prepend(ModeratorResolvedSosRecord record) async {
    final existing = await loadAll();
    final next = [
      record,
      ...existing.where((r) => r.resolveKey != record.resolveKey),
    ].take(_maxItems).toList();
    await _saveAll(next);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
