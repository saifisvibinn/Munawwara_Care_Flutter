import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/location_permission_service.dart';
import '../../../core/services/socket_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/moderator_provider.dart';

/// Keeps `mod_nav_beacon` emits alive for groups where beacon stayed ON even
/// when [GroupManagementScreen] is not open (dashboard, background stream).
class ModeratorGlobalNavBeaconController {
  ModeratorGlobalNavBeaconController(this.ref);

  final WidgetRef ref;
  StreamSubscription<Position>? _sub;

  static const _prefsKeyPrefix = 'nav_beacon_';

  Future<List<String>> _enabledGroupIds() async {
    final prefs = await SharedPreferences.getInstance();
    final groups = ref.read(moderatorProvider).groups;
    final out = <String>[];
    for (final g in groups) {
      if (prefs.getBool('$_prefsKeyPrefix${g.id}') ?? false) {
        out.add(g.id);
      }
    }
    return out;
  }

  Future<void> _emitForGroups(
    List<String> groupIds,
    double lat,
    double lng,
  ) async {
    if (groupIds.isEmpty) return;
    final auth = ref.read(authProvider);
    final modId = auth.userId;
    if (modId == null) return;
    final modName = auth.fullName ?? 'Moderator';
    for (final groupId in groupIds) {
      SocketService.emit('mod_nav_beacon', {
        'groupId': groupId,
        'enabled': true,
        'lat': lat,
        'lng': lng,
        'moderatorId': modId,
        'moderatorName': modName,
      });
    }
  }

  Future<void> _emitCurrentEnabled(double lat, double lng) async {
    final ids = await _enabledGroupIds();
    await _emitForGroups(ids, lat, lng);
  }

  /// One-shot after reconnect / resume before stream delivers.
  Future<void> emitSnapshotIfNeeded() async {
    final ids = await _enabledGroupIds();
    if (ids.isEmpty) return;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        final age = DateTime.now().difference(last.timestamp);
        final accOk = !last.accuracy.isInfinite &&
            last.accuracy >= 0 &&
            last.accuracy <= 8000;
        if (age <= const Duration(hours: 8) && accOk) {
          await _emitForGroups(ids, last.latitude, last.longitude);
        }
      }
    } catch (_) {}
  }

  /// Restarts stream; optionally requests a fresh GPS fix first.
  Future<void> sync({bool emitImmediateFix = false}) async {
    await _sub?.cancel();
    _sub = null;

    final allowed = await hasLocationAlwaysPermission();
    if (!allowed) return;

    var ids = await _enabledGroupIds();
    if (ids.isEmpty) return;

    if (emitImmediateFix) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          final age = DateTime.now().difference(last.timestamp);
          final accOk = !last.accuracy.isInfinite &&
              last.accuracy >= 0 &&
              last.accuracy <= 8000;
          if (age <= const Duration(hours: 8) && accOk) {
            await _emitCurrentEnabled(last.latitude, last.longitude);
          }
        }
      } catch (_) {}
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        );
        await _emitCurrentEnabled(pos.latitude, pos.longitude);
      } catch (_) {}
    }

    ids = await _enabledGroupIds();
    if (ids.isEmpty) return;

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 25,
      ),
    ).listen((pos) {
      unawaited(_emitCurrentEnabled(pos.latitude, pos.longitude));
    });
  }

  void dispose() {
    final s = _sub;
    _sub = null;
    unawaited(s?.cancel());
  }
}
