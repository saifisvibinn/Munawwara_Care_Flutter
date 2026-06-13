import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_munawwara/core/utils/app_logger.dart';

import '../../../core/services/api_service.dart';
import '../models/bus_attendance_models.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class BusAttendanceState {
  final bool isLoading;
  final bool isStarting;
  final String? error;

  /// Active boarding session (null if none started / after completion).
  final BoardingSession? session;

  /// QR image as a raw base64 string (without the data URI prefix).
  final String? qrImageBase64;

  /// Short code shown to pilgrims for manual entry (last 6 chars of session ID).
  final String? attendanceCode;

  /// Enriched lists from the /status endpoint.
  final List<BoardedPilgrim> boarded;
  final List<MissingPilgrim> missing;

  /// Boarding session history list for the group
  final List<BoardingSession> history;

  /// Whether status has been fetched at least once.
  final bool hasFetched;

  const BusAttendanceState({
    this.isLoading = false,
    this.isStarting = false,
    this.error,
    this.session,
    this.qrImageBase64,
    this.attendanceCode,
    this.boarded = const [],
    this.missing = const [],
    this.history = const [],
    this.hasFetched = false,
  });

  BusAttendanceState copyWith({
    bool? isLoading,
    bool? isStarting,
    String? error,
    bool clearError = false,
    BoardingSession? session,
    bool clearSession = false,
    String? qrImageBase64,
    String? attendanceCode,
    List<BoardedPilgrim>? boarded,
    List<MissingPilgrim>? missing,
    List<BoardingSession>? history,
    bool? hasFetched,
  }) =>
      BusAttendanceState(
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        error: clearError ? null : (error ?? this.error),
        session: clearSession ? null : (session ?? this.session),
        qrImageBase64: clearSession ? null : (qrImageBase64 ?? this.qrImageBase64),
        attendanceCode: clearSession ? null : (attendanceCode ?? this.attendanceCode),
        boarded: boarded ?? this.boarded,
        missing: missing ?? this.missing,
        history: history ?? this.history,
        hasFetched: hasFetched ?? this.hasFetched,
      );

  int get totalPilgrims => boarded.length + missing.length;
  bool get hasActiveSession => session != null && session!.isActive;
  bool get hasCreatedSession => session != null && session!.isCreated;
  bool get hasAnySession => session != null && (session!.isActive || session!.isCreated);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BusAttendanceNotifier extends Notifier<BusAttendanceState> {
  @override
  BusAttendanceState build() => const BusAttendanceState();

  void _commit(BusAttendanceState next) {
    if (!ref.mounted) return;
    state = next;
  }

  // ── Create a boarding session ─────────────────────────────────────────────

  Future<bool> createSession(String groupId, {String? busIdentifier}) async {
    _commit(state.copyWith(isStarting: true, clearError: true));
    try {
      final resp = await ApiService.dio.post(
        '/groups/$groupId/bus-attendance/create',
        data: busIdentifier != null && busIdentifier.trim().isNotEmpty
            ? {'bus_identifier': busIdentifier.trim()}
            : null,
      );

      final body = _extractData(resp.data);
      final sessionJson = body['session'] as Map<String, dynamic>? ?? {};
      final session = BoardingSession.fromJson(sessionJson);

      final qrRaw = body['qr_code']?.toString() ?? '';
      final qrBase64 = qrRaw.contains(',') ? qrRaw.split(',').last : qrRaw;

      final code = session.id.length >= 6
          ? session.id.substring(session.id.length - 6).toUpperCase()
          : session.id.toUpperCase();

      _commit(state.copyWith(
        isStarting: false,
        session: session,
        qrImageBase64: qrBase64,
        attendanceCode: code,
      ));

      await fetchStatus(groupId);
      return true;
    } on DioException catch (e) {
      _commit(state.copyWith(
        isStarting: false,
        error: ApiService.parseError(e),
      ));
      return false;
    } catch (e) {
      _commit(state.copyWith(isStarting: false, error: e.toString()));
      return false;
    }
  }

  // ── Start (or resume) a boarding session ──────────────────────────────────

  Future<bool> startSession(String groupId, {String? busIdentifier}) async {
    _commit(state.copyWith(isStarting: true, clearError: true));
    try {
      final resp = await ApiService.dio.post(
        '/groups/$groupId/bus-attendance/start',
        data: busIdentifier != null && busIdentifier.trim().isNotEmpty
            ? {'bus_identifier': busIdentifier.trim()}
            : null,
      );

      final body = _extractData(resp.data);
      final sessionJson = body['session'] as Map<String, dynamic>? ?? {};
      final session = BoardingSession.fromJson(sessionJson);

      final qrRaw = body['qr_code']?.toString() ?? '';
      final qrBase64 = qrRaw.contains(',') ? qrRaw.split(',').last : qrRaw;

      final code = session.id.length >= 6
          ? session.id.substring(session.id.length - 6).toUpperCase()
          : session.id.toUpperCase();

      _commit(state.copyWith(
        isStarting: false,
        session: session,
        qrImageBase64: qrBase64,
        attendanceCode: code,
      ));

      await fetchStatus(groupId);
      return true;
    } on DioException catch (e) {
      _commit(state.copyWith(
        isStarting: false,
        error: ApiService.parseError(e),
      ));
      return false;
    } catch (e) {
      _commit(state.copyWith(isStarting: false, error: e.toString()));
      return false;
    }
  }

  // ── Fetch live boarding status ────────────────────────────────────────────

  Future<void> fetchStatus(String groupId) async {
    _commit(state.copyWith(isLoading: true, clearError: true));
    try {
      final resp = await ApiService.dio.get(
        '/groups/$groupId/bus-attendance/status',
      );
      final body = _extractData(resp.data);

      final activeRaw = body['active_session'] as Map<String, dynamic>?;
      BoardingSession? session;
      if (activeRaw != null && activeRaw.isNotEmpty) {
        session = BoardingSession.fromJson(activeRaw);

        // If we don't have a QR yet (e.g. screen re-opened for existing session),
        // derive the attendance code from the session ID.
        final code = session.id.length >= 6
            ? session.id.substring(session.id.length - 6).toUpperCase()
            : session.id.toUpperCase();
        if (state.attendanceCode == null || state.attendanceCode != code) {
          _commit(state.copyWith(attendanceCode: code));
        }
      }

      final boardedRaw = body['boarded'] as List<dynamic>? ?? [];
      final missingRaw = body['missing'] as List<dynamic>? ?? [];

      _commit(state.copyWith(
        isLoading: false,
        hasFetched: true,
        session: session,
        clearSession: session == null,
        boarded: boardedRaw
            .whereType<Map<String, dynamic>>()
            .map(BoardedPilgrim.fromJson)
            .toList(),
        missing: missingRaw
            .whereType<Map<String, dynamic>>()
            .map(MissingPilgrim.fromJson)
            .toList(),
      ));
    } on DioException catch (e) {
      _commit(state.copyWith(
        isLoading: false,
        hasFetched: true,
        error: ApiService.parseError(e),
      ));
    } catch (e) {
      _commit(state.copyWith(
        isLoading: false,
        hasFetched: true,
        error: e.toString(),
      ));
    }
  }

  // ── Manual check-in / undo ────────────────────────────────────────────────

  Future<bool> manualToggle({
    required String groupId,
    required String sessionId,
    required String pilgrimId,
    required bool boarded,
  }) async {
    try {
      await ApiService.dio.post(
        '/groups/$groupId/bus-attendance/manual',
        data: {
          'session_id': sessionId,
          'pilgrim_id': pilgrimId,
          'boarded': boarded,
        },
      );
      // Refresh status to get accurate lists
      await fetchStatus(groupId);
      return true;
    } on DioException catch (e) {
      AppLogger.e('[BusAttendance] manualToggle error: ${ApiService.parseError(e)}');
      return false;
    } catch (e) {
      AppLogger.e('[BusAttendance] manualToggle error: $e');
      return false;
    }
  }

  // ── Complete session ──────────────────────────────────────────────────────

  Future<bool> completeSession(String groupId) async {
    final sessionId = state.session?.id;
    if (sessionId == null) return false;

    _commit(state.copyWith(isLoading: true, clearError: true));
    try {
      await ApiService.dio.post(
        '/groups/$groupId/bus-attendance/complete',
        data: {'session_id': sessionId},
      );
      _commit(state.copyWith(
        isLoading: false,
        clearSession: true,
        boarded: const [],
        missing: const [],
      ));
      return true;
    } on DioException catch (e) {
      _commit(state.copyWith(isLoading: false, error: ApiService.parseError(e)));
      return false;
    } catch (e) {
      _commit(state.copyWith(isLoading: false, error: e.toString()));
      return false;
    }
  }

  // ── Handle real-time bus_boarding_update socket event ──────────────────────

  void handleBoardingUpdate(Map<String, dynamic> data, String groupId) {
    final pilgrimId = data['pilgrim_id']?.toString() ?? '';
    final isBoarded = data['boarded'] != false;

    if (pilgrimId.isEmpty) return;

    if (isBoarded) {
      // Move pilgrim from missing → boarded
      final missingIdx = state.missing.indexWhere((m) => m.id == pilgrimId);
      if (missingIdx == -1) {
        // Pilgrim not in our missing list — just refresh
        fetchStatus(groupId);
        return;
      }
      final mp = state.missing[missingIdx];
      final boardedAt = data['boarded_at'] != null
          ? DateTime.tryParse(data['boarded_at'].toString()) ?? DateTime.now()
          : DateTime.now();
      final method = data['method']?.toString() ?? 'qr_scan';

      final newBoarded = BoardedPilgrim(
        id: mp.id,
        fullName: mp.fullName,
        phoneNumber: mp.phoneNumber,
        roomNumber: mp.roomNumber,
        hotelName: mp.hotelName,
        profilePicture: mp.profilePicture,
        gender: mp.gender,
        age: mp.age,
        boardedAt: boardedAt,
        method: method,
      );

      final updatedMissing = [...state.missing]..removeAt(missingIdx);
      final updatedBoarded = [newBoarded, ...state.boarded];
      _commit(state.copyWith(boarded: updatedBoarded, missing: updatedMissing));
    } else {
      // Move pilgrim from boarded → missing
      final boardedIdx = state.boarded.indexWhere((b) => b.id == pilgrimId);
      if (boardedIdx == -1) {
        fetchStatus(groupId);
        return;
      }
      final bp = state.boarded[boardedIdx];
      final newMissing = MissingPilgrim(
        id: bp.id,
        fullName: bp.fullName,
        phoneNumber: bp.phoneNumber,
        roomNumber: bp.roomNumber,
        hotelName: bp.hotelName,
        profilePicture: bp.profilePicture,
        gender: bp.gender,
        age: bp.age,
      );

      final updatedBoarded = [...state.boarded]..removeAt(boardedIdx);
      final updatedMissing = [newMissing, ...state.missing];
      _commit(state.copyWith(boarded: updatedBoarded, missing: updatedMissing));
    }
  }

  // ── Fetch history sessions ─────────────────────────────────────────────

  Future<void> fetchHistory(String groupId) async {
    _commit(state.copyWith(isLoading: true, clearError: true));
    try {
      final resp = await ApiService.dio.get(
        '/groups/$groupId/bus-attendance/history',
      );
      final body = _extractData(resp.data);
      final listRaw = body['sessions'] as List<dynamic>? ?? [];
      final list = listRaw
          .whereType<Map<String, dynamic>>()
          .map(BoardingSession.fromJson)
          .toList();

      _commit(state.copyWith(
        isLoading: false,
        history: list,
      ));
    } on DioException catch (e) {
      _commit(state.copyWith(isLoading: false, error: ApiService.parseError(e)));
    } catch (e) {
      _commit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  // ── Fetch specific past session details ──────────────────────────────────

  Future<void> fetchSessionDetails(String groupId, String sessionId) async {
    _commit(state.copyWith(
      isLoading: true,
      clearError: true,
      clearSession: true,
      boarded: const [],
      missing: const [],
    ));
    try {
      final resp = await ApiService.dio.get(
        '/groups/$groupId/bus-attendance/session/$sessionId',
      );
      final body = _extractData(resp.data);

      final sessionRaw = body['session'] as Map<String, dynamic>?;
      final session = sessionRaw != null ? BoardingSession.fromJson(sessionRaw) : null;

      final boardedRaw = body['boarded'] as List<dynamic>? ?? [];
      final missingRaw = body['missing'] as List<dynamic>? ?? [];

      _commit(state.copyWith(
        isLoading: false,
        session: session,
        boarded: boardedRaw
            .whereType<Map<String, dynamic>>()
            .map(BoardedPilgrim.fromJson)
            .toList(),
        missing: missingRaw
            .whereType<Map<String, dynamic>>()
            .map(MissingPilgrim.fromJson)
            .toList(),
      ));
    } on DioException catch (e) {
      _commit(state.copyWith(isLoading: false, error: ApiService.parseError(e)));
    } catch (e) {
      _commit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  // ── Reset (when leaving the screen) ───────────────────────────────────────

  void reset() {
    _commit(const BusAttendanceState());
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _extractData(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw['data'] as Map<String, dynamic>? ?? raw;
    }
    return <String, dynamic>{};
  }
}

// ── Provider declaration ────────────────────────────────────────────────────

final busAttendanceProvider =
    NotifierProvider.autoDispose<BusAttendanceNotifier, BusAttendanceState>(
  BusAttendanceNotifier.new,
);
