import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';

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

  /// Display ID like "#7821-KSA" derived from national_id or object id tail
  String get displayId {
    if (nationalId != null && nationalId!.length >= 4) {
      return '#${nationalId!.substring(nationalId!.length - 4)}-KSA';
    }
    if (id.length >= 4) {
      return '#${id.substring(id.length - 4).toUpperCase()}';
    }
    return '#----';
  }
}

// ── Group Info Model ──────────────────────────────────────────────────────────

class GroupInfo {
  final String groupId;
  final String groupName;
  final int pilgrimCount;
  final List<ModeratorInfo> moderators;

  const GroupInfo({
    required this.groupId,
    required this.groupName,
    required this.pilgrimCount,
    required this.moderators,
  });

  factory GroupInfo.fromJson(Map<String, dynamic> j) => GroupInfo(
    groupId: j['group_id']?.toString() ?? '',
    groupName: j['group_name']?.toString() ?? '',
    pilgrimCount: j['pilgrim_count'] as int? ?? 0,
    moderators: (j['moderators'] as List<dynamic>? ?? [])
        .map((m) => ModeratorInfo.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
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
  // key = moderatorId, value = active beacon info
  final Map<String, ModeratorBeacon> navBeacons;

  const PilgrimState({
    this.isLoading = false,
    this.isSosLoading = false,
    this.error,
    this.profile,
    this.groupInfo,
    this.isSharingLocation = true,
    this.batteryLevel,
    this.sosActive = false,
    this.navBeacons = const {},
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
    bool clearError = false,
    bool clearGroup = false,
  }) => PilgrimState(
    isLoading: isLoading ?? this.isLoading,
    isSosLoading: isSosLoading ?? this.isSosLoading,
    error: clearError ? null : (error ?? this.error),
    profile: profile ?? this.profile,
    groupInfo: clearGroup ? null : (groupInfo ?? this.groupInfo),
    isSharingLocation: isSharingLocation ?? this.isSharingLocation,
    batteryLevel: batteryLevel ?? this.batteryLevel,
    sosActive: sosActive ?? this.sosActive,
    navBeacons: navBeacons ?? this.navBeacons,
  );
}

// ── Pilgrim Notifier ──────────────────────────────────────────────────────────

class PilgrimNotifier extends Notifier<PilgrimState> {
  @override
  PilgrimState build() {
    return const PilgrimState();
  }

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, clearError: true);
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

      state = state.copyWith(
        isLoading: false,
        profile: profileData != null
            ? PilgrimProfile.fromJson(profileData)
            : null,
        groupInfo: (groupData != null && groupData.containsKey('group_id'))
            ? GroupInfo.fromJson(groupData)
            : null,
        clearGroup: !(groupData != null && groupData.containsKey('group_id')),
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
    }
  }

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    int? batteryPercent,
  }) async {
    if (!state.isSharingLocation) return;
    try {
      await ApiService.dio.put(
        '/pilgrim/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'battery_percent': ?batteryPercent,
        },
      );
      if (batteryPercent != null) {
        state = state.copyWith(batteryLevel: batteryPercent);
      }
    } catch (_) {
      // Silent — location updates should not disrupt UX
    }
  }

  Future<bool> triggerSOS() async {
    state = state.copyWith(isSosLoading: true);
    try {
      await ApiService.dio.post('/pilgrim/sos');
      state = state.copyWith(isSosLoading: false, sosActive: true);
      // Auto clear SOS status after 10 s
      Future.delayed(const Duration(seconds: 10), () {
        if (state.sosActive) {
          state = state.copyWith(sosActive: false);
        }
      });
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
    if (enabled && lat != null && lng != null) {
      updated[modId] = ModeratorBeacon(
        id: modId,
        name: modName,
        lat: lat,
        lng: lng,
      );
    } else {
      updated.remove(modId);
    }
    state = state.copyWith(navBeacons: updated);
  }

  void cancelSOS() {
    state = state.copyWith(sosActive: false);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final pilgrimProvider = NotifierProvider<PilgrimNotifier, PilgrimState>(
  PilgrimNotifier.new,
);
