import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sos_moderator_payload.dart';

/// Per-incident moderator engagement for SOS (persisted across restarts).
class ModeratorSosEngagementRecord {
  final String storageKey;
  final String? sosId;
  final String pilgrimId;
  final String groupId;
  final String groupName;
  final String pilgrimName;
  final String? pilgrimGender;
  final double? lat;
  final double? lng;
  final bool called;
  final bool navigated;
  final bool blockingSuppressed;
  final bool userDismissed;
  final bool active;
  final int updatedAtMs;

  const ModeratorSosEngagementRecord({
    required this.storageKey,
    required this.sosId,
    required this.pilgrimId,
    required this.groupId,
    required this.groupName,
    required this.pilgrimName,
    required this.pilgrimGender,
    required this.lat,
    required this.lng,
    required this.called,
    required this.navigated,
    required this.blockingSuppressed,
    required this.userDismissed,
    required this.active,
    required this.updatedAtMs,
  });

  bool get fullyHandled => called && navigated;

  ModeratorSosEngagementRecord copyWith({
    String? pilgrimName,
    String? groupName,
    String? pilgrimGender,
    double? lat,
    double? lng,
    bool? called,
    bool? navigated,
    bool? blockingSuppressed,
    bool? userDismissed,
    bool? active,
    int? updatedAtMs,
  }) => ModeratorSosEngagementRecord(
    storageKey: storageKey,
    sosId: sosId,
    pilgrimId: pilgrimId,
    groupId: groupId,
    groupName: groupName ?? this.groupName,
    pilgrimName: pilgrimName ?? this.pilgrimName,
    pilgrimGender: pilgrimGender ?? this.pilgrimGender,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    called: called ?? this.called,
    navigated: navigated ?? this.navigated,
    blockingSuppressed: blockingSuppressed ?? this.blockingSuppressed,
    userDismissed: userDismissed ?? this.userDismissed,
    active: active ?? this.active,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );

  Map<String, dynamic> toJson() => {
    'sos_id': sosId,
    'pilgrim_id': pilgrimId,
    'group_id': groupId,
    'group_name': groupName,
    'pilgrim_name': pilgrimName,
    'pilgrim_gender': pilgrimGender,
    'lat': lat,
    'lng': lng,
    'called': called,
    'navigated': navigated,
    'blocking_suppressed': blockingSuppressed,
    'user_dismissed': userDismissed,
    'active': active,
    'updated_at_ms': updatedAtMs,
  };

  static ModeratorSosEngagementRecord fromJson(
    String key,
    Map<String, dynamic> j,
  ) {
    return ModeratorSosEngagementRecord(
      storageKey: key,
      sosId: j['sos_id']?.toString(),
      pilgrimId: j['pilgrim_id']?.toString() ?? '',
      groupId: j['group_id']?.toString() ?? '',
      groupName: j['group_name']?.toString() ?? '',
      pilgrimName: j['pilgrim_name']?.toString() ?? '',
      pilgrimGender: j['pilgrim_gender']?.toString(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
      called: j['called'] == true,
      navigated: j['navigated'] == true,
      blockingSuppressed: j['blocking_suppressed'] == true,
      userDismissed: j['user_dismissed'] == true,
      active: j['active'] != false,
      updatedAtMs:
          (j['updated_at_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// SharedPreferences-backed store for moderator SOS engagement.
class ModeratorSosEngagementStore {
  ModeratorSosEngagementStore._();

  static const _prefsKey = 'moderator_sos_engagements_v1';
  static const _pruneAfter = Duration(days: 7);

  static Future<Map<String, ModeratorSosEngagementRecord>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, ModeratorSosEngagementRecord>{};
      for (final e in decoded.entries) {
        final m = Map<String, dynamic>.from(e.value as Map);
        out[e.key] = ModeratorSosEngagementRecord.fromJson(e.key, m);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveMap(
    Map<String, ModeratorSosEngagementRecord> map,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{};
    for (final e in map.entries) {
      encoded[e.key] = e.value.toJson();
    }
    await prefs.setString(_prefsKey, jsonEncode(encoded));
  }

  static Future<void> _prune(Map<String, ModeratorSosEngagementRecord> map) {
    final cutoff = DateTime.now().subtract(_pruneAfter).millisecondsSinceEpoch;
    map.removeWhere((_, r) => r.updatedAtMs < cutoff);
    return Future.value();
  }

  static Future<List<ModeratorSosEngagementRecord>> loadAll() async {
    final map = await _loadMap();
    await _prune(map);
    _collapseDuplicateActiveIncidents(map);
    await _saveMap(map);
    return map.values.toList();
  }

  /// Keeps the newest active row per pilgrim+group; deactivates duplicate keys
  /// (e.g. after hot restart / FCM replay created extra prefs entries).
  static void _collapseDuplicateActiveIncidents(
    Map<String, ModeratorSosEngagementRecord> map,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final active = map.entries
        .where((e) => e.value.active && !e.value.fullyHandled)
        .toList();
    final byPg =
        <String, List<MapEntry<String, ModeratorSosEngagementRecord>>>{};
    for (final e in active) {
      final r = e.value;
      if (r.pilgrimId.isEmpty || r.groupId.isEmpty) continue;
      final k = '${r.pilgrimId}|${r.groupId}';
      byPg.putIfAbsent(k, () => []).add(e);
    }
    for (final list in byPg.values) {
      if (list.length <= 1) continue;
      list.sort((a, b) => b.value.updatedAtMs.compareTo(a.value.updatedAtMs));
      for (var i = 1; i < list.length; i++) {
        final e = list[i];
        map[e.key] = e.value.copyWith(active: false, updatedAtMs: now);
      }
    }
  }

  /// Merge payload into store; marks incident active and refreshes coords.
  static Future<ModeratorSosEngagementRecord> upsertActiveFromPayload(
    SosModeratorPayload p,
  ) async {
    final map = await _loadMap();
    await _prune(map);
    final key = p.storageKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = map[key];
    final merged = ModeratorSosEngagementRecord(
      storageKey: key,
      sosId: p.sosId,
      pilgrimId: p.pilgrimId ?? existing?.pilgrimId ?? '',
      groupId: p.groupId ?? existing?.groupId ?? '',
      groupName: p.groupName.isNotEmpty
          ? p.groupName
          : (existing?.groupName ?? ''),
      pilgrimName: p.pilgrimName.isNotEmpty
          ? p.pilgrimName
          : (existing?.pilgrimName ?? ''),
      pilgrimGender: p.pilgrimGender ?? existing?.pilgrimGender,
      lat: p.lat ?? existing?.lat,
      lng: p.lng ?? existing?.lng,
      called: existing?.called ?? false,
      navigated: existing?.navigated ?? false,
      blockingSuppressed: existing?.blockingSuppressed ?? false,
      userDismissed: existing?.userDismissed ?? false,
      active: true,
      updatedAtMs: now,
    );
    map[key] = merged;
    _collapseDuplicateActiveIncidents(map);
    await _saveMap(map);
    return merged;
  }

  static Future<bool> shouldShowBlockingModal(String storageKey) async {
    final map = await _loadMap();
    final r = map[storageKey];
    if (r == null || !r.active) return true;
    if (r.fullyHandled) return false;
    if (r.blockingSuppressed) return false;
    return true;
  }

  static Future<void> markUserDismissed(String storageKey) async {
    final map = await _loadMap();
    final r = map[storageKey];
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    map[storageKey] = r.copyWith(
      blockingSuppressed: true,
      userDismissed: true,
      updatedAtMs: now,
    );
    await _saveMap(map);
  }

  static Future<void> markReviewSuppressed(String storageKey) async {
    final map = await _loadMap();
    final r = map[storageKey];
    if (r == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    map[storageKey] = r.copyWith(blockingSuppressed: true, updatedAtMs: now);
    await _saveMap(map);
  }

  static Future<ModeratorSosEngagementRecord?> markNavigatedSuccess(
    String storageKey,
  ) async {
    final map = await _loadMap();
    final r = map[storageKey];
    if (r == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = r.copyWith(navigated: true, updatedAtMs: now);
    map[storageKey] = next;
    await _saveMap(map);
    return next;
  }

  /// Returns the updated record if one was marked, for UI / auto-pop dialog.
  static Future<ModeratorSosEngagementRecord?> markCalledForPilgrim(
    String pilgrimId,
  ) async {
    if (pilgrimId.isEmpty) return null;
    final map = await _loadMap();
    ModeratorSosEngagementRecord? best;
    for (final r in map.values) {
      if (!r.active || r.fullyHandled) continue;
      if (r.pilgrimId != pilgrimId) continue;
      if (best == null || r.updatedAtMs > best.updatedAtMs) best = r;
    }
    if (best == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = best.copyWith(called: true, updatedAtMs: now);
    map[best.storageKey] = next;
    await _saveMap(map);
    return next;
  }

  static Future<void> deactivateForPilgrim(String pilgrimId) async {
    if (pilgrimId.isEmpty) return;
    final map = await _loadMap();
    var changed = false;
    for (final e in map.entries.toList()) {
      if (e.value.pilgrimId == pilgrimId) {
        map[e.key] = e.value.copyWith(active: false);
        changed = true;
      }
    }
    if (changed) await _saveMap(map);
  }

  /// Removes all engagement rows for [pilgrimId] (e.g. SOS resolved).
  static Future<void> removeAllEntriesForPilgrim(String pilgrimId) async {
    if (pilgrimId.isEmpty) return;
    final map = await _loadMap();
    map.removeWhere((_, r) => r.pilgrimId == pilgrimId);
    await _saveMap(map);
  }
}
