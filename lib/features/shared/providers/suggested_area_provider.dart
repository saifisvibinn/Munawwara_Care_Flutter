import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/secure_session_store.dart';
import '../../../core/utils/app_logger.dart';
import '../models/suggested_area_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class SuggestedAreaState {
  final List<SuggestedArea> areas;
  final bool isLoading;
  final String? error;

  const SuggestedAreaState({
    this.areas = const [],
    this.isLoading = false,
    this.error,
  });

  SuggestedAreaState copyWith({
    List<SuggestedArea>? areas,
    bool? isLoading,
    String? error,
  }) => SuggestedAreaState(
    areas: areas ?? this.areas,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );

  List<SuggestedArea> get suggestions =>
      areas.where((a) => !a.isMeetpoint).toList();

  List<SuggestedArea> get meetpoints =>
      areas.where((a) => a.isMeetpoint).toList();

  List<SuggestedArea> get expiredMeetpoints {
    final now = DateTime.now();
    return meetpoints
        .where(
          (a) =>
              a.meetpointTime != null &&
              now.isAfter(
                a.meetpointTime!.add(SuggestedArea.meetpointExpiryWindow),
              ),
        )
        .toList();
  }

  SuggestedArea? get activeMeetpoint {
    final now = DateTime.now();
    final mps = meetpoints
        .where(
          (a) =>
              a.meetpointTime == null ||
              now.isBefore(
                a.meetpointTime!.add(SuggestedArea.meetpointExpiryWindow),
              ),
        )
        .toList();
    return mps.isEmpty ? null : mps.first;
  }

  bool get hasMeetpoint => activeMeetpoint != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SuggestedAreaNotifier extends Notifier<SuggestedAreaState> {
  String? _activeGroupId;

  /// Group id currently loaded (or loading). Used to avoid showing stale areas.
  String? get activeGroupId => _activeGroupId;

  @override
  SuggestedAreaState build() => const SuggestedAreaState();

  Future<void> _hydrateFromCache(String groupId) async {
    final uid = await SecureSessionStore.getUserId();
    if (uid == null) return;
    final data = AppDataCache.jsonMap(
      await AppDataCache.readData(
        uid,
        AppDataCache.suggestedAreasFile(groupId),
      ),
    );
    if (data == null) return;
    try {
      final List<dynamic> list =
          (data['areas'] ?? data['data'] ?? []) as List<dynamic>;
      final raw = list
          .map((j) => SuggestedArea.fromJson(j as Map<String, dynamic>))
          .toList();
      if (raw.isEmpty) return;
      if (_activeGroupId != groupId) return;
      state = state.copyWith(areas: raw);
    } catch (_) {}
  }

  Future<void> _persist(String groupId, Map<String, dynamic> data) async {
    final uid = await SecureSessionStore.getUserId();
    if (uid == null) return;
    await AppDataCache.write(
      uid,
      AppDataCache.suggestedAreasFile(groupId),
      data,
    );
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> load(String groupId) async {
    _activeGroupId = groupId;
    state = const SuggestedAreaState(isLoading: true);
    await _hydrateFromCache(groupId);
    if (_activeGroupId != groupId) return;
    try {
      final res = await ApiService.dio.get('/groups/$groupId/suggested-areas');
      if (_activeGroupId != groupId) return;
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final uid = await SecureSessionStore.getUserId();
      if (uid != null) {
        await _persist(groupId, data);
      }
      if (_activeGroupId != groupId) return;
      final List<dynamic> list =
          (data['areas'] ?? data['data'] ?? []) as List<dynamic>;
      final raw = list
          .map((j) => SuggestedArea.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(areas: raw, isLoading: false);
    } on DioException catch (e) {
      if (_activeGroupId != groupId) return;
      if (state.areas.isEmpty) {
        await _hydrateFromCache(groupId);
      }
      if (_activeGroupId != groupId) return;
      if (state.areas.isNotEmpty) {
        state = state.copyWith(isLoading: false, error: null);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: ApiService.parseError(e),
        );
      }
    } catch (_) {
      if (_activeGroupId != groupId) return;
      state = state.copyWith(isLoading: false, error: 'Something went wrong');
    }
  }

  // ── Add ────────────────────────────────────────────────────────────────────

  Future<(bool, String?)> addArea({
    required String groupId,
    required String name,
    String description = '',
    required double latitude,
    required double longitude,
    String areaType = 'suggestion',
    DateTime? meetpointTime,
    int? reminderMinutes,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'area_type': areaType,
        'meetpoint_time': ?meetpointTime?.toUtc().toIso8601String(),
        'reminder_minutes': ?reminderMinutes,
      };
      await ApiService.dio.post(
        '/groups/$groupId/suggested-areas',
        data: body,
      );
      // Don't update state here - let the socket event handle it
      // to avoid duplicates and ensure consistency across all clients
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (_) {
      return (false, 'Something went wrong');
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<bool> deleteArea(String groupId, String areaId) async {
    final area = state.areas.where((a) => a.id == areaId).firstOrNull;
    final wasMeetpoint = area?.isMeetpoint ?? false;

    try {
      await ApiService.dio.delete('/groups/$groupId/suggested-areas/$areaId');
      state = state.copyWith(
        areas: state.areas.where((a) => a.id != areaId).toList(),
      );

      if (wasMeetpoint) {
        AppLogger.i('[SuggestedAreaProvider] Meetpoint deleted — backend FCM push will notify pilgrims.');
      }
      return true;
    } catch (e) {
      AppLogger.e('[SuggestedAreaProvider] deleteArea failed: $e');
      return false;
    }
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  Future<(bool, String?)> updateArea({
    required String groupId,
    required String areaId,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? meetpointTime,
    int? reminderMinutes,
  }) async {
    try {
      final body = <String, dynamic>{
        'name': ?name,
        'description': ?description,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'meetpoint_time': ?meetpointTime?.toUtc().toIso8601String(),
        'reminder_minutes': ?reminderMinutes,
      };
      await ApiService.dio.put(
        '/groups/$groupId/suggested-areas/$areaId',
        data: body,
      );
      // The backend no longer emits `area_updated`; refresh from source of truth.
      await load(groupId);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (_) {
      return (false, 'Something went wrong');
    }
  }

  // ── Socket helpers (no HTTP) ──────────────────────────────────────────────

  void appendArea(Map<String, dynamic> json) {
    try {
      final area = SuggestedArea.fromJson(json);
      if (state.areas.any((a) => a.id == area.id)) return;
      // If a new meetpoint arrives, purge any stale meetpoint that
      // may have been missed by a dropped area_deleted socket event.
      final updatedAreas = area.isMeetpoint
          ? state.areas.where((a) => !a.isMeetpoint).toList()
          : [...state.areas];
      state = state.copyWith(areas: [area, ...updatedAreas]);
    } catch (_) {}
  }

  void removeArea(String areaId) {
    state = state.copyWith(
      areas: state.areas.where((a) => a.id != areaId).toList(),
    );
  }

  // ── Clear all areas (used when pilgrim removed from group) ────────────────

  void clear() {
    _activeGroupId = null;
    state = const SuggestedAreaState();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final suggestedAreaProvider =
    NotifierProvider<SuggestedAreaNotifier, SuggestedAreaState>(
      SuggestedAreaNotifier.new,
    );
