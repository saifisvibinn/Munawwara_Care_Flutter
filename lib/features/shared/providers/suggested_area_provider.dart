import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
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

  SuggestedArea? get activeMeetpoint {
    final mps = meetpoints;
    return mps.isEmpty ? null : mps.first;
  }

  bool get hasMeetpoint => meetpoints.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SuggestedAreaNotifier extends Notifier<SuggestedAreaState> {
  @override
  SuggestedAreaState build() => const SuggestedAreaState();

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> load(String groupId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.dio.get('/groups/$groupId/suggested-areas');
      final raw = (res.data['areas'] as List<dynamic>)
          .map((j) => SuggestedArea.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(areas: raw, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
    } catch (_) {
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
  }) async {
    try {
      await ApiService.dio.post(
        '/groups/$groupId/suggested-areas',
        data: {
          'name': name,
          'description': description,
          'latitude': latitude,
          'longitude': longitude,
          'area_type': areaType,
        },
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
    try {
      await ApiService.dio.delete('/groups/$groupId/suggested-areas/$areaId');
      state = state.copyWith(
        areas: state.areas.where((a) => a.id != areaId).toList(),
      );
      return true;
    } catch (_) {
      return false;
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
