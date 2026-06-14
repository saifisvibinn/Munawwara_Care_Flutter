import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/secure_session_store.dart';
import '../models/insurance_company.dart';
import '../helpers/user_ref.dart';
import '../../auth/models/wakel_info.dart';

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
  final String? alternativePhoneNumber;
  final String? morafeqName;
  final String? morafeqPhone;
  final String? morafeqEmail;
  final String? tasheraNumber;
  final InsuranceCompany? insuranceCompany;

  const PilgrimProfile({
    required this.id,
    required this.fullName,
    this.nationalId,
    this.phoneNumber,
    this.email,
    this.medicalHistory,
    this.age,
    this.gender,
    this.alternativePhoneNumber,
    this.morafeqName,
    this.morafeqPhone,
    this.morafeqEmail,
    this.tasheraNumber,
    this.insuranceCompany,
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
    alternativePhoneNumber: j['alternative_phone_number']?.toString(),
    morafeqName: j['morafeq_name']?.toString(),
    morafeqPhone: j['morafeq_phone']?.toString(),
    morafeqEmail: j['morafeq_email']?.toString(),
    tasheraNumber: j['tashera_number']?.toString(),
    insuranceCompany: j['insurance_company_id'] != null
        ? InsuranceCompany.fromJson(
            Map<String, dynamic>.from(j['insurance_company_id']),
          )
        : null,
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

// ── Active Boarding Session Model ───────────────────────────────────────────

class ActiveBoardingSession {
  final String sessionId;
  final String busIdentifier;
  final String status;
  final DateTime? startedAt;
  final bool attended;

  const ActiveBoardingSession({
    required this.sessionId,
    required this.busIdentifier,
    required this.status,
    this.startedAt,
    this.attended = false,
  });

  factory ActiveBoardingSession.fromJson(Map<String, dynamic> j) => ActiveBoardingSession(
    sessionId: j['_id']?.toString() ?? j['session_id']?.toString() ?? '',
    busIdentifier: j['bus_identifier']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    startedAt: j['started_at'] != null ? DateTime.tryParse(j['started_at'].toString()) : null,
    attended: j['attended'] == true,
  );
}

// ── Group Info Model ──────────────────────────────────────────────────────────

class GroupInfo {
  final String groupId;
  final String groupName;
  final int pilgrimCount;
  final List<ModeratorInfo> moderators;
  final String? createdBy;
  final String? hotelName;
  final String? hotelAddress;
  final String? roomNumber;
  final String? checkIn;
  final String? checkOut;
  final int? daysRemaining;
  final double? hotelLatitude;
  final double? hotelLongitude;
  final WakelInfo? wakelInfo;
  final ActiveBoardingSession? activeBoardingSession;

  const GroupInfo({
    required this.groupId,
    required this.groupName,
    required this.pilgrimCount,
    required this.moderators,
    this.createdBy,
    this.hotelName,
    this.hotelAddress,
    this.roomNumber,
    this.checkIn,
    this.checkOut,
    this.daysRemaining,
    this.hotelLatitude,
    this.hotelLongitude,
    this.wakelInfo,
    this.activeBoardingSession,
  });

  GroupInfo copyWith({
    String? groupId,
    String? groupName,
    int? pilgrimCount,
    List<ModeratorInfo>? moderators,
    String? createdBy,
    String? hotelName,
    String? hotelAddress,
    String? roomNumber,
    String? checkIn,
    String? checkOut,
    int? daysRemaining,
    double? hotelLatitude,
    double? hotelLongitude,
    WakelInfo? wakelInfo,
    ActiveBoardingSession? activeBoardingSession,
    bool clearActiveBoardingSession = false,
  }) =>
      GroupInfo(
        groupId: groupId ?? this.groupId,
        groupName: groupName ?? this.groupName,
        pilgrimCount: pilgrimCount ?? this.pilgrimCount,
        moderators: moderators ?? this.moderators,
        createdBy: createdBy ?? this.createdBy,
        hotelName: hotelName ?? this.hotelName,
        hotelAddress: hotelAddress ?? this.hotelAddress,
        roomNumber: roomNumber ?? this.roomNumber,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
        daysRemaining: daysRemaining ?? this.daysRemaining,
        hotelLatitude: hotelLatitude ?? this.hotelLatitude,
        hotelLongitude: hotelLongitude ?? this.hotelLongitude,
        wakelInfo: wakelInfo ?? this.wakelInfo,
        activeBoardingSession: clearActiveBoardingSession
            ? null
            : (activeBoardingSession ?? this.activeBoardingSession),
      );

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

    double? firstDouble(List<String> keys) {
      for (final key in keys) {
        final value = j[key];
        if (value is double) return value;
        if (value is num) return value.toDouble();
        if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final createdById = parseUserRefId(j['created_by']);
    var moderators = (j['moderators'] as List<dynamic>? ?? [])
        .map((m) => ModeratorInfo.fromJson(m as Map<String, dynamic>))
        .toList();
    if (createdById != null &&
        !moderators.any((m) => m.id == createdById) &&
        j['created_by'] is Map<String, dynamic>) {
      moderators = [
        ModeratorInfo.fromJson(j['created_by'] as Map<String, dynamic>),
        ...moderators,
      ];
    }

    return GroupInfo(
      groupId: j['group_id']?.toString() ?? '',
      groupName: j['group_name']?.toString() ?? '',
      pilgrimCount: j['pilgrim_count'] as int? ?? 0,
      moderators: moderators,
      createdBy: createdById,
      hotelName: firstString(['hotel_name', 'hotelName']),
      hotelAddress: firstString(['hotel_address', 'hotelAddress']),
      roomNumber: firstString(['room_number', 'room_no', 'roomNumber']),
      checkIn: firstString(['checkin_date', 'check_in', 'checkIn']),
      checkOut: firstString(['checkout_date', 'check_out', 'checkOut']),
      daysRemaining: firstInt(['days_remaining', 'stay_days', 'daysRemaining']),
      hotelLatitude: firstDouble(['hotel_latitude', 'hotelLatitude']),
      hotelLongitude: firstDouble(['hotel_longitude', 'hotelLongitude']),
      wakelInfo: j['wakel'] != null ? WakelInfo.fromJson(j['wakel'] as Map<String, dynamic>) : null,
      activeBoardingSession: j['active_boarding_session'] != null
          ? ActiveBoardingSession.fromJson(j['active_boarding_session'] as Map<String, dynamic>)
          : null,
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

  /// Back-compat alias — map keys and socket payloads use moderator id.
  String get moderatorId => id;
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
    } catch (_) {
      // Silent — location updates should not disrupt UX
    }
  }

  Future<bool> triggerSOS() async {
    state = state.copyWith(isSosLoading: true, clearError: true);
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

  /// Applies a live boarding session from a `bus_boarding_started` socket event.
  void applyBoardingSessionStarted(Map<String, dynamic> data) {
    final GroupInfo? group = state.groupInfo;
    if (group == null) return;
    final ActiveBoardingSession session = ActiveBoardingSession.fromJson({
      'session_id': data['session_id'],
      'bus_identifier': data['bus_identifier'],
      'status': data['status'] ?? 'active',
      'started_at': data['started_at'],
      'attended': group.activeBoardingSession?.attended ?? false,
    });
    state = state.copyWith(
      groupInfo: group.copyWith(activeBoardingSession: session),
    );
  }

  /// Clears the active boarding card when a session ends over the socket.
  void clearActiveBoardingSession() {
    final GroupInfo? group = state.groupInfo;
    if (group == null || group.activeBoardingSession == null) return;
    state = state.copyWith(
      groupInfo: group.copyWith(clearActiveBoardingSession: true),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final pilgrimProvider = NotifierProvider<PilgrimNotifier, PilgrimState>(
  PilgrimNotifier.new,
);
