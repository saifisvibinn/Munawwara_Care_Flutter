import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/secure_session_store.dart';
import '../../../core/services/offline_retry_service.dart';

// ── Pilgrim Profile Model ─────────────────────────────────────────────────────

class PilgrimProfile {
  final String id;
  final String fullName;
  final String? nationalId;
  final String? phoneNumber;
  final String? email;
  final String? medicalHistory;
  final int? age;
  final String? gender;

  const PilgrimProfile({
    required this.id,
    required this.fullName,
    this.nationalId,
    this.phoneNumber,
    this.email,
    this.medicalHistory,
    this.age,
    this.gender,
  });

  factory PilgrimProfile.fromJson(Map<String, dynamic> j) => PilgrimProfile(
    id: j['_id']?.toString() ?? '',
    fullName: j['full_name']?.toString() ?? '',
    nationalId: j['national_id']?.toString(),
    phoneNumber: j['phone_number']?.toString(),
    email: j['email']?.toString(),
    medicalHistory: j['medical_history']?.toString(),
    age: j['age'] as int?,
    gender: j['gender']?.toString(),
  );

  String get firstName => fullName.split(' ').first;

  String get shortName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0]} ${parts[1]}';
    }
    return fullName;
  }
}

// ── Group Info Model ──────────────────────────────────────────────────────────

class GroupInfo {
  final String groupId;
  final String groupName;
  final int pilgrimCount;
  final List<ModeratorInfo> moderators;
  final String? hotelName;
  final String? roomNumber;
  final String? busNumber;
  final String? driverName;
  final String? checkIn;
  final String? checkOut;
  final int? daysRemaining;

  const GroupInfo({
    required this.groupId,
    required this.groupName,
    required this.pilgrimCount,
    required this.moderators,
    this.hotelName,
    this.roomNumber,
    this.busNumber,
    this.driverName,
    this.checkIn,
    this.checkOut,
    this.daysRemaining,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> j) {
    String? firstString(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
      return null;
    }

    int? firstInt(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return GroupInfo(
      groupId: j['group_id']?.toString() ?? '',
      groupName: j['group_name']?.toString() ?? '',
      pilgrimCount: j['pilgrim_count'] as int? ?? 0,
      moderators: (j['moderators'] as List<dynamic>? ?? [])
          .map((m) => ModeratorInfo.fromJson(m as Map<String, dynamic>))
          .toList(),
      hotelName: firstString(['hotel_name', 'hotelName']),
      roomNumber: firstString(['room_number', 'room_no', 'roomNumber']),
      busNumber: firstString(['bus_number', 'bus_no', 'busNumber']),
      driverName: firstString(['driver_name', 'driverName']),
      checkIn: firstString(['checkin_date', 'check_in', 'checkIn']),
      checkOut: firstString(['checkout_date', 'check_out', 'checkOut']),
      daysRemaining: firstInt(['days_remaining', 'stay_days', 'daysRemaining']),
    );
  }
}

class ModeratorInfo {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final double? lat;
  final double? lng;

  const ModeratorInfo({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.lat,
    this.lng,
  });

  factory ModeratorInfo.fromJson(Map<String, dynamic> j) => ModeratorInfo(
    id: j['_id']?.toString() ?? '',
    fullName: j['full_name']?.toString() ?? '',
    phoneNumber: j['phone_number']?.toString(),
    lat: (j['current_latitude'] as num?)?.toDouble(),
    lng: (j['current_longitude'] as num?)?.toDouble(),
  );
}

// ── Moderator Beacon Model ──────────────────────────────────────────────────

class ModeratorBeacon {
  final String id;
  final String name;
  final double lat;
  final double lng;

  const ModeratorBeacon({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });
}

// ── Pilgrim State ─────────────────────────────────────────────────────────────

class PilgrimState {
  final bool isLoading;
  final bool isSosLoading;
  final String? error;
  final PilgrimProfile? profile;
  final GroupInfo? groupInfo;
  final bool isSharingLocation;
  final int? batteryLevel;
  final bool sosActive;
  final String? activeSosId;
  // key = moderatorId, value = active beacon info
  final Map<String, ModeratorBeacon> navBeacons;

  /// True when dashboard data comes from disk (offline or pre-hydrate).
  final bool usingOfflineSnapshot;

  const PilgrimState({
    this.isLoading = false,
    this.isSosLoading = false,
    this.error,
    this.profile,
    this.groupInfo,
    this.isSharingLocation = true,
    this.batteryLevel,
    this.sosActive = false,
    this.activeSosId,
    this.navBeacons = const {},
    this.usingOfflineSnapshot = false,
  });

  PilgrimState copyWith({
    bool? isLoading,
    bool? isSosLoading,
    String? error,
    PilgrimProfile? profile,
    GroupInfo? groupInfo,
    bool? isSharingLocation,
    int? batteryLevel,
    bool? sosActive,
    Map<String, ModeratorBeacon>? navBeacons,
    String? activeSosId,
    bool clearError = false,
    bool clearGroup = false,
    bool clearSosId = false,
    bool? usingOfflineSnapshot,
    bool clearOfflineSnapshot = false,
  }) => PilgrimState(
    isLoading: isLoading ?? this.isLoading,
    isSosLoading: isSosLoading ?? this.isSosLoading,
    error: clearError ? null : (error ?? this.error),
    profile: profile ?? this.profile,
    groupInfo: clearGroup ? null : (groupInfo ?? this.groupInfo),
    isSharingLocation: isSharingLocation ?? this.isSharingLocation,
    batteryLevel: batteryLevel ?? this.batteryLevel,
    sosActive: sosActive ?? this.sosActive,
    activeSosId: clearSosId ? null : (activeSosId ?? this.activeSosId),
    navBeacons: navBeacons ?? this.navBeacons,
    usingOfflineSnapshot: clearOfflineSnapshot
        ? false
        : (usingOfflineSnapshot ?? this.usingOfflineSnapshot),
  );
}

// ── Pilgrim Notifier ──────────────────────────────────────────────────────────

class PilgrimNotifier extends Notifier<PilgrimState> {
  static DateTime? _lastDashboardLoad;
  static DateTime? _lastLocationUpdate;

  @override
  PilgrimState build() {
    return const PilgrimState();
  }

  Future<String?> _userId() => SecureSessionStore.getUserId();

  /// Load last-known dashboard from disk (call before network refresh).
  Future<void> hydrateFromCache() async {
    final uid = await _userId();
    if (uid == null) return;

    PilgrimProfile? profile;
    final pMap = AppDataCache.jsonMap(
      await AppDataCache.readData(uid, AppDataCache.pilgrimProfileFile),
    );
    if (pMap != null) {
      try {
        profile = PilgrimProfile.fromJson(pMap);
      } catch (_) {}
    }

    GroupInfo? groupInfo;
    bool clearGroup = false;
    final gMap = AppDataCache.jsonMap(
      await AppDataCache.readData(uid, AppDataCache.pilgrimMyGroupFile),
    );
    if (gMap != null) {
      final gid = gMap['group_id']?.toString() ?? '';
      if (gid.isNotEmpty) {
        try {
          groupInfo = GroupInfo.fromJson(gMap);
        } catch (_) {}
      } else {
        clearGroup = true;
      }
    }

    if (profile == null && groupInfo == null && !clearGroup) return;

    state = state.copyWith(
      profile: profile ?? state.profile,
      groupInfo: clearGroup ? null : (groupInfo ?? state.groupInfo),
      clearGroup: clearGroup,
      navBeacons: clearGroup ? const {} : null,
    );
  }

  Future<void> _writePilgrimCache(
    String uid,
    Map<String, dynamic>? profileData,
    Map<String, dynamic>? groupData,
  ) async {
    if (profileData != null) {
      await AppDataCache.write(
        uid,
        AppDataCache.pilgrimProfileFile,
        profileData,
      );
    }
    if (groupData != null &&
        (groupData['group_id']?.toString() ?? '').isNotEmpty) {
      await AppDataCache.write(uid, AppDataCache.pilgrimMyGroupFile, groupData);
    } else {
      await AppDataCache.write(
        uid,
        AppDataCache.pilgrimMyGroupFile,
        <String, dynamic>{'group_id': ''},
      );
    }
  }

  Future<void> loadDashboard({bool force = false, bool silently = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastDashboardLoad != null &&
        now.difference(_lastDashboardLoad!).inSeconds < 10) {
      return; // Throttle to prevent 429 errors
    }
    _lastDashboardLoad = now;

    if (!silently) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      // Parallel fetch: profile + group
      final results = await Future.wait([
        ApiService.dio.get('/pilgrim/profile'),
        ApiService.dio
            .get('/pilgrim/my-group')
            .catchError(
              (_) => Response(
                data: null,
                statusCode: 404,
                requestOptions: RequestOptions(path: '/pilgrim/my-group'),
              ),
            ),
      ]);

      final profileData = results[0].data as Map<String, dynamic>?;
      final groupData = results[1].data as Map<String, dynamic>?;

      final uid = await _userId();
      if (uid != null && profileData != null) {
        await _writePilgrimCache(uid, profileData, groupData);
      }

      final activeSosRaw = profileData?['active_sos_id'];
      final activeSosStr = activeSosRaw != null &&
              activeSosRaw.toString().trim().isNotEmpty
          ? activeSosRaw.toString()
          : null;
      final hasActiveSos = activeSosStr != null;

      state = state.copyWith(
        isLoading: false,
        profile: profileData != null
            ? PilgrimProfile.fromJson(profileData)
            : null,
        groupInfo: (groupData != null && groupData.containsKey('group_id'))
            ? GroupInfo.fromJson(groupData)
            : null,
        clearGroup: !(groupData != null && groupData.containsKey('group_id')),
        navBeacons: !(groupData != null && groupData.containsKey('group_id'))
            ? const {}
            : null,
        clearOfflineSnapshot: true,
        sosActive: hasActiveSos,
        activeSosId: activeSosStr,
        clearSosId: !hasActiveSos,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        state = state.copyWith(
          isLoading: false,
          error: ApiService.parseError(e),
        );
        return;
      }
      final uid = await _userId();
      if (uid != null) await hydrateFromCache();
      final hasData = state.profile != null || state.groupInfo != null;
      state = state.copyWith(
        isLoading: false,
        error: hasData ? null : ApiService.parseError(e),
        // Only mark offline snapshot after a confirmed failed network attempt.
        usingOfflineSnapshot: hasData,
      );
    }
  }

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    int? batteryPercent,
  }) async {
    if (!state.isSharingLocation) return;

    final now = DateTime.now();
    // Update battery locally immediately, but throttle network calls
    if (batteryPercent != null) {
      state = state.copyWith(batteryLevel: batteryPercent);
    }

    if (_lastLocationUpdate != null &&
        now.difference(_lastLocationUpdate!).inSeconds < 15) {
      return; // Throttle location updates to at most once every 15 seconds
    }
    _lastLocationUpdate = now;

    try {
      await ApiService.dio.put(
        '/pilgrim/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'battery_percent': batteryPercent,
        },
      );
    } on DioException catch (e) {
      if (ApiService.isOfflineFailure(e)) {
        if (state.sosActive) {
          unawaited(ref.read(offlineRetryServiceProvider).enqueueAction(
            type: 'update_location',
            payload: {
              'latitude': latitude,
              'longitude': longitude,
              'battery_percent': batteryPercent,
            },
          ));
        }
      }
    } catch (_) {
      // Silent — location updates should not disrupt UX
    }
  }

  Future<bool> triggerSOS() async {
    state = state.copyWith(isSosLoading: true, clearError: true);
    final tempId = const Uuid().v4();
    try {
      final response = await ApiService.dio.post('/pilgrim/sos');
      final body = response.data as Map<String, dynamic>?;
      final activeSosId = body?['sos_id']?.toString() ??
          body?['data']?['sos_id']?.toString();

      state = state.copyWith(
        isSosLoading: false,
        sosActive: true,
        activeSosId: activeSosId,
      );
      return true;
    } on DioException catch (e) {
      if (ApiService.isOfflineFailure(e)) {
        state = state.copyWith(
          isSosLoading: false,
          sosActive: true,
          activeSosId: tempId,
        );
        unawaited(ref.read(offlineRetryServiceProvider).enqueueAction(
          actionId: tempId,
          type: 'trigger_sos',
          payload: {
            'temp_sos_id': tempId,
          },
        ));
        return true;
      }
      state = state.copyWith(
        isSosLoading: false,
        error: ApiService.parseError(e),
      );
      return false;
    }
  }

  void toggleLocationSharing(bool value) {
    state = state.copyWith(isSharingLocation: value);
  }

  void setBattery(int percent) {
    state = state.copyWith(batteryLevel: percent);
  }

  void updateModeratorBeacon(
    String modId,
    String modName,
    bool enabled,
    double? lat,
    double? lng,
  ) {
    final updated = Map<String, ModeratorBeacon>.from(state.navBeacons);
    if (!enabled) {
      updated.remove(modId);
    } else if (lat != null && lng != null) {
      updated[modId] = ModeratorBeacon(
        id: modId,
        name: modName,
        lat: lat,
        lng: lng,
      );
    }
    // If enabled but lat/lng is null, we just keep the previous beacon if it exists
    // rather than removing it, to avoid flicker while moderator is getting GPS fix.

    state = state.copyWith(navBeacons: updated);
  }

  void cancelSOS() {
    state = state.copyWith(sosActive: false, clearSosId: true);
  }

  void updateActiveSosId(String realSosId) {
    if (state.sosActive && state.activeSosId != realSosId) {
      state = state.copyWith(activeSosId: realSosId);
    }
  }

  /// Notifies the server that the active SOS was cancelled (socket or HTTP).
  Future<bool> cancelSosRemote({String? sosId}) async {
    final payload = <String, dynamic>{};
    if (sosId != null && sosId.isNotEmpty) {
      payload['sos_id'] = sosId;
    }
    try {
      await ApiService.dio.post('/pilgrim/sos/cancel', data: payload);
      return true;
    } on DioException catch (e) {
      if (ApiService.isOfflineFailure(e)) {
        final removed = await ref.read(offlineRetryServiceProvider).cancelPendingSos(sosId);
        if (removed) {
          return true;
        }
        unawaited(ref.read(offlineRetryServiceProvider).enqueueAction(
          type: 'cancel_sos',
          payload: {
            'sos_id': sosId,
          },
        ));
        return true;
      }
      state = state.copyWith(error: ApiService.parseError(e));
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Clear all group-related state when pilgrim is removed from group
  void clearGroupState() {
    state = state.copyWith(
      clearGroup: true,
      navBeacons: const {},
      sosActive: false,
      clearSosId: true,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final pilgrimProvider = NotifierProvider<PilgrimNotifier, PilgrimState>(
  PilgrimNotifier.new,
);
