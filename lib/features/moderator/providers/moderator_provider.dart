import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_munawwara/core/utils/app_logger.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/caller_gender_cache.dart';
import '../../../core/services/secure_session_store.dart';
import '../../pilgrim/models/insurance_company.dart';

// ── Pilgrim Document model ───────────────────────────────────────────────────
class PilgrimDocument {
  final String name;
  final String fileUrl;
  final String fileType;
  final DateTime? uploadedAt;

  const PilgrimDocument({
    required this.name,
    required this.fileUrl,
    required this.fileType,
    this.uploadedAt,
  });

  factory PilgrimDocument.fromJson(Map<String, dynamic> j) {
    return PilgrimDocument(
      name: j['name']?.toString() ?? '',
      fileUrl: j['file_url']?.toString() ?? '',
      fileType: j['file_type']?.toString() ?? '',
      uploadedAt: j['uploaded_at'] != null
          ? DateTime.tryParse(j['uploaded_at'].toString())
          : null,
    );
  }
}

// ── Pilgrim-in-group model ────────────────────────────────────────────────────
class PilgrimInGroup {
  final String id;
  final String fullName;
  final String? nationalId;
  final String? phoneNumber;
  final int? age;
  final String? gender;
  final String? profilePicture;
  final String? medicalHistory;
  final double? lat;
  final double? lng;
  final int? batteryPercent;
  final DateTime? lastUpdated;
  final bool hasSOS;
  final bool isOnline;
  final String? hotelName;
  final String? roomNumber;
  final String? busInfo;
  final String language;
  final String ethnicity;
  final String? alternativePhoneNumber;
  final String? morafeqName;
  final String? morafeqPhone;
  final String? morafeqEmail;
  final String? tasheraNumber;
  final InsuranceCompany? insuranceCompany;
  final String? tasheraDocumentUrl;
  final String? tasheraDocumentType;
  final List<PilgrimDocument> documents;

  const PilgrimInGroup({
    required this.id,
    required this.fullName,
    this.nationalId,
    this.phoneNumber,
    this.age,
    this.gender,
    this.profilePicture,
    this.medicalHistory,
    this.lat,
    this.lng,
    this.batteryPercent,
    this.lastUpdated,
    this.hasSOS = false,
    this.isOnline = false,
    this.hotelName,
    this.roomNumber,
    this.busInfo,
    this.language = 'en',
    this.ethnicity = 'Other',
    this.alternativePhoneNumber,
    this.morafeqName,
    this.morafeqPhone,
    this.morafeqEmail,
    this.tasheraNumber,
    this.insuranceCompany,
    this.tasheraDocumentUrl,
    this.tasheraDocumentType,
    this.documents = const [],
  });

  factory PilgrimInGroup.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    return PilgrimInGroup(
      id: j['_id']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      nationalId: j['national_id']?.toString(),
      phoneNumber: j['phone_number']?.toString(),
      age: (j['age'] as num?)?.toInt(),
      gender: j['gender']?.toString(),
      profilePicture: j['profile_picture']?.toString(),
      medicalHistory: j['medical_history']?.toString(),
      lat: (loc?['lat'] as num?)?.toDouble(),
      lng: (loc?['lng'] as num?)?.toDouble(),
      batteryPercent: (j['battery_percent'] as num?)?.toInt(),
      lastUpdated: j['last_updated'] != null
          ? DateTime.tryParse(j['last_updated'].toString())
          : null,
      isOnline: j['is_online'] == true,
      hotelName: j['hotel_name']?.toString(),
      roomNumber: j['room_number']?.toString(),
      busInfo: j['bus_info']?.toString(),
      language: j['language']?.toString() ?? 'en',
      ethnicity: j['ethnicity']?.toString() ?? 'Other',
      hasSOS:
          j['has_sos'] == true || j['sos_active'] == true || j['sos'] == true,
      alternativePhoneNumber: j['alternative_phone_number']?.toString(),
      morafeqName: j['morafeq_name']?.toString(),
      morafeqPhone: j['morafeq_phone']?.toString(),
      morafeqEmail: j['morafeq_email']?.toString(),
      tasheraNumber: j['tashera_number']?.toString(),
      insuranceCompany: j['insurance_company_id'] != null
          ? InsuranceCompany.fromJson(Map<String, dynamic>.from(j['insurance_company_id']))
          : null,
      tasheraDocumentUrl: j['tashera_document_url']?.toString(),
      tasheraDocumentType: j['tashera_document_type']?.toString(),
      documents: j['documents'] != null
          ? (j['documents'] as List)
              .map((d) => PilgrimDocument.fromJson(Map<String, dynamic>.from(d)))
              .toList()
          : const [],
    );
  }

  PilgrimInGroup copyWith({
    bool? hasSOS,
    double? lat,
    double? lng,
    int? batteryPercent,
    DateTime? lastUpdated,
    bool? isOnline,
    String? nationalId,
    String? medicalHistory,
    String? alternativePhoneNumber,
    String? morafeqName,
    String? morafeqPhone,
    String? morafeqEmail,
    String? tasheraNumber,
    InsuranceCompany? insuranceCompany,
    String? tasheraDocumentUrl,
    String? tasheraDocumentType,
    List<PilgrimDocument>? documents,
  }) => PilgrimInGroup(
    id: id,
    fullName: fullName,
    nationalId: nationalId ?? this.nationalId,
    phoneNumber: phoneNumber,
    age: age,
    gender: gender,
    profilePicture: profilePicture,
    medicalHistory: medicalHistory ?? this.medicalHistory,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    batteryPercent: batteryPercent ?? this.batteryPercent,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    hasSOS: hasSOS ?? this.hasSOS,
    isOnline: isOnline ?? this.isOnline,
    hotelName: hotelName,
    roomNumber: roomNumber,
    busInfo: busInfo,
    language: language,
    ethnicity: ethnicity,
    alternativePhoneNumber: alternativePhoneNumber ?? this.alternativePhoneNumber,
    morafeqName: morafeqName ?? this.morafeqName,
    morafeqPhone: morafeqPhone ?? this.morafeqPhone,
    morafeqEmail: morafeqEmail ?? this.morafeqEmail,
    tasheraNumber: tasheraNumber ?? this.tasheraNumber,
    insuranceCompany: insuranceCompany ?? this.insuranceCompany,
    tasheraDocumentUrl: tasheraDocumentUrl ?? this.tasheraDocumentUrl,
    tasheraDocumentType: tasheraDocumentType ?? this.tasheraDocumentType,
    documents: documents ?? this.documents,
  );

  /// Merges live map/status fields with a fresh profile fetch.
  PilgrimInGroup mergeProfileDetails(PilgrimInGroup fetched) => copyWith(
        nationalId: fetched.nationalId,
        medicalHistory: fetched.medicalHistory,
        tasheraNumber: fetched.tasheraNumber,
        tasheraDocumentUrl: fetched.tasheraDocumentUrl,
        tasheraDocumentType: fetched.tasheraDocumentType,
        documents: fetched.documents,
        insuranceCompany: fetched.insuranceCompany,
        alternativePhoneNumber: fetched.alternativePhoneNumber,
        morafeqName: fetched.morafeqName,
        morafeqPhone: fetched.morafeqPhone,
        morafeqEmail: fetched.morafeqEmail,
      );

  bool get hasLocation => lat != null && lng != null;

  String get firstName => fullName.split(' ').first;

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  /// e.g. "85" green, "45" orange, "12" red
  BatteryStatus get batteryStatus {
    if (batteryPercent == null) return BatteryStatus.unknown;
    if (batteryPercent! >= 50) return BatteryStatus.good;
    if (batteryPercent! >= 20) return BatteryStatus.medium;
    return BatteryStatus.low;
  }

  /// Human-readable "last seen" text (localized).
  String get lastSeenText {
    if (isOnline) return 'pilgrim_last_seen_active_now'.tr();
    if (lastUpdated == null) return 'profile_offline'.tr();
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inMinutes < 1) {
      return 'pilgrim_last_seen_updated_just_now'.tr();
    }
    if (diff.inMinutes < 60) {
      return 'pilgrim_last_seen_updated_minutes'
          .tr(args: ['${diff.inMinutes}']);
    }
    if (diff.inHours < 24) {
      return 'pilgrim_last_seen_updated_hours'.tr(args: ['${diff.inHours}']);
    }
    return 'pilgrim_last_seen_updated_days'.tr(args: ['${diff.inDays}']);
  }
}

enum BatteryStatus { good, medium, low, unknown }

// ── Co-moderator model ────────────────────────────────────────────────────────

class GroupModerator {
  final String id;
  final String fullName;
  final String? email;

  const GroupModerator({required this.id, required this.fullName, this.email});

  factory GroupModerator.fromJson(Map<String, dynamic> j) => GroupModerator(
    id: j['_id']?.toString() ?? '',
    fullName: j['full_name']?.toString() ?? '',
    email: j['email']?.toString(),
  );

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}

// ── Group model ───────────────────────────────────────────────────────────────

class ModeratorGroup {
  final String id;
  final String groupName;
  final String groupCode;
  final String createdBy;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final DateTime? createdAt;
  final int unreadCount;
  final List<GroupModerator> moderators;
  final List<PilgrimInGroup> pilgrims;

  const ModeratorGroup({
    required this.id,
    required this.groupName,
    required this.groupCode,
    required this.createdBy,
    this.checkInDate,
    this.checkOutDate,
    this.createdAt,
    this.unreadCount = 0,
    required this.moderators,
    required this.pilgrims,
  });

  factory ModeratorGroup.fromJson(Map<String, dynamic> j) {
    DateTime? parseDate(dynamic val) {
      if (val == null || val.toString().isEmpty) return null;
      return DateTime.tryParse(val.toString());
    }

    return ModeratorGroup(
      id: j['_id']?.toString() ?? '',
      groupName: j['group_name']?.toString() ?? '',
      groupCode: j['group_code']?.toString() ?? '',
      createdBy: j['created_by']?.toString() ?? '',
      checkInDate: parseDate(j['check_in_date']),
      checkOutDate: parseDate(j['check_out_date']),
      createdAt: parseDate(j['createdAt']),
      unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
      moderators: (j['moderator_ids'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(GroupModerator.fromJson)
          .toList(),
      pilgrims: (j['pilgrims'] as List<dynamic>? ?? [])
          .map((p) => PilgrimInGroup.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  ModeratorGroup copyWith({
    List<PilgrimInGroup>? pilgrims,
    List<GroupModerator>? moderators,
    String? groupName,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    DateTime? createdAt,
    int? unreadCount,
  }) {
    return ModeratorGroup(
      id: id,
      groupName: groupName ?? this.groupName,
      groupCode: groupCode,
      createdBy: createdBy,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      createdAt: createdAt ?? this.createdAt,
      unreadCount: unreadCount ?? this.unreadCount,
      moderators: moderators ?? this.moderators,
      pilgrims: pilgrims ?? this.pilgrims,
    );
  }

  int get totalPilgrims => pilgrims.length;
  int get moderatorCount => moderators.length;
  int get onlineCount => pilgrims.where((p) => p.isOnline).length;
  int get sosCount => pilgrims.where((p) => p.hasSOS).length;
  int get batteryLowCount =>
      pilgrims.where((p) => p.batteryStatus == BatteryStatus.low).length;
}

// ── State ─────────────────────────────────────────────────────────────────────

class ModeratorState {
  final bool isLoading;
  final String? error;
  final List<ModeratorGroup> groups;
  final int selectedGroupIndex;
  final bool showSosOnly;
  final String searchQuery;
  final bool isBroadcastingSOS;
  final bool usingOfflineSnapshot;

  const ModeratorState({
    this.isLoading = false,
    this.error,
    this.groups = const [],
    this.selectedGroupIndex = 0,
    this.showSosOnly = false,
    this.searchQuery = '',
    this.isBroadcastingSOS = false,
    this.usingOfflineSnapshot = false,
  });

  ModeratorState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<ModeratorGroup>? groups,
    int? selectedGroupIndex,
    bool? showSosOnly,
    String? searchQuery,
    bool? isBroadcastingSOS,
    bool? usingOfflineSnapshot,
    bool clearOfflineSnapshot = false,
  }) => ModeratorState(
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    groups: groups ?? this.groups,
    selectedGroupIndex: selectedGroupIndex ?? this.selectedGroupIndex,
    showSosOnly: showSosOnly ?? this.showSosOnly,
    searchQuery: searchQuery ?? this.searchQuery,
    isBroadcastingSOS: isBroadcastingSOS ?? this.isBroadcastingSOS,
    usingOfflineSnapshot: clearOfflineSnapshot
        ? false
        : (usingOfflineSnapshot ?? this.usingOfflineSnapshot),
  );

  ModeratorGroup? get currentGroup => groups.isEmpty
      ? null
      : groups[selectedGroupIndex.clamp(0, groups.length - 1)];

  List<PilgrimInGroup> get filteredPilgrims {
    var list = currentGroup?.pilgrims ?? <PilgrimInGroup>[];
    if (showSosOnly) list = list.where((p) => p.hasSOS).toList();
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((p) {
        return p.fullName.toLowerCase().contains(q) ||
            (p.nationalId?.toLowerCase().contains(q) ?? false) ||
            (p.phoneNumber?.contains(q) ?? false);
      }).toList();
    }
    return list;
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ModeratorNotifier extends Notifier<ModeratorState> {
  DateTime? _lastDashboardLoad;
  Future<void>? _dashboardLoadInFlight;
  int _dashboardLoadGeneration = 0;

  @override
  ModeratorState build() => const ModeratorState();

  Future<String?> _userId() => SecureSessionStore.getUserId();

  /// Drops a group from the offline dashboard cache after delete/leave.
  Future<void> _removeGroupFromDashboardCache(String groupId) async {
    final uid = await _userId();
    if (uid == null) return;
    final cached = AppDataCache.jsonMap(
      await AppDataCache.readData(uid, AppDataCache.moderatorDashboardFile),
    );
    if (cached == null) return;
    final list = cached['data'] as List<dynamic>? ?? [];
    final filtered = <dynamic>[];
    for (final item in list) {
      final gm = AppDataCache.jsonMap(item);
      if (gm == null) continue;
      final id = gm['_id']?.toString() ?? gm['id']?.toString();
      if (id != groupId) filtered.add(item);
    }
    await AppDataCache.write(
      uid,
      AppDataCache.moderatorDashboardFile,
      {'data': filtered},
    );
  }

  Future<void> hydrateFromCache() async {
    final uid = await _userId();
    if (uid == null) return;
    final m = AppDataCache.jsonMap(
      await AppDataCache.readData(uid, AppDataCache.moderatorDashboardFile),
    );
    if (m == null) return;
    final list = m['data'] as List<dynamic>? ?? [];
    final groups = <ModeratorGroup>[];
    for (final item in list) {
      final gm = AppDataCache.jsonMap(item);
      if (gm == null) continue;
      try {
        groups.add(ModeratorGroup.fromJson(gm));
      } catch (_) {}
    }
    if (groups.isEmpty) return;
    state = state.copyWith(groups: groups);
    await CallerGenderCache.syncFromGroups(groups);
  }

  // Load all groups + their pilgrims
  Future<void> loadDashboard({bool silently = false, bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastDashboardLoad != null &&
        now.difference(_lastDashboardLoad!).inSeconds < 10) {
      return;
    }

    final generation = ++_dashboardLoadGeneration;

    if (_dashboardLoadInFlight != null && !force) {
      await _dashboardLoadInFlight;
      return;
    }

    _lastDashboardLoad = now;
    final loadFuture = _loadDashboardImpl(silently, generation);
    _dashboardLoadInFlight = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (_dashboardLoadInFlight == loadFuture) {
        _dashboardLoadInFlight = null;
      }
    }
  }

  /// Refreshes dashboard data after writes. Always bypasses the 10s throttle.
  Future<void> syncAfterMutation({String? groupId}) async {
    if (groupId != null) {
      final ok = await refreshGroup(groupId);
      if (!ok) await loadDashboard(force: true, silently: true);
    } else {
      await loadDashboard(force: true, silently: true);
    }
  }

  Future<void> _loadDashboardImpl(bool silently, int generation) async {
    if (generation != _dashboardLoadGeneration) return;
    if (!silently) state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await ApiService.dio.get('/groups/dashboard');
      if (generation != _dashboardLoadGeneration) return;
      final respBody = resp.data;
      final body = respBody is Map
          ? Map<String, dynamic>.from(respBody)
          : <String, dynamic>{'data': respBody is List ? respBody : []};
      final uid = await _userId();
      if (uid != null) {
        await AppDataCache.write(
          uid,
          AppDataCache.moderatorDashboardFile,
          body,
        );
      }
      if (generation != _dashboardLoadGeneration) return;
      final data = body['data'] as List<dynamic>? ?? [];
      final groups = data
          .map((g) => ModeratorGroup.fromJson(g as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        isLoading: false,
        groups: groups,
        clearError: true,
        clearOfflineSnapshot: true,
      );
      await CallerGenderCache.syncFromGroups(groups);
    } on DioException catch (e) {
      if (generation != _dashboardLoadGeneration) return;
      final code = e.response?.statusCode;
      if (code == 401) {
        if (!silently) {
          state = state.copyWith(
            isLoading: false,
            error: ApiService.parseError(e),
          );
        }
        return;
      }
      final uid = await _userId();
      if (uid != null) await hydrateFromCache();
      if (generation != _dashboardLoadGeneration) return;
      final hasData = state.groups.isNotEmpty;
      if (!silently) {
        state = state.copyWith(
          isLoading: false,
          error: hasData ? null : ApiService.parseError(e),
          usingOfflineSnapshot: hasData,
        );
      } else if (hasData) {
        // Only mark offline snapshot after a confirmed failed network attempt.
        state = state.copyWith(usingOfflineSnapshot: true);
      }
    } catch (e) {
      if (generation != _dashboardLoadGeneration) return;
      if (!silently) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }

  void selectGroup(int index) {
    if (index < 0 || index >= state.groups.length) return;
    state = state.copyWith(selectedGroupIndex: index);
  }

  void toggleSosFilter() =>
      state = state.copyWith(showSosOnly: !state.showSosOnly);

  void updateSearch(String q) => state = state.copyWith(searchQuery: q);

  void incrementUnreadCount(String groupId) {
    final groups = state.groups.map((g) {
      if (g.id == groupId) {
        return g.copyWith(unreadCount: g.unreadCount + 1);
      }
      return g;
    }).toList();
    state = state.copyWith(groups: groups);
  }

  void clearUnreadCount(String groupId) {
    final groups = state.groups.map((g) {
      if (g.id == groupId) {
        return g.copyWith(unreadCount: 0);
      }
      return g;
    }).toList();
    state = state.copyWith(groups: groups);
  }

  // Mark a specific pilgrim as having active SOS (called from FCM handler)
  void markPilgrimSOS(String pilgrimId, {bool active = true}) {
    final groups = state.groups.map((g) {
      final pilgrims = g.pilgrims.map((p) {
        if (p.id == pilgrimId) return p.copyWith(hasSOS: active);
        return p;
      }).toList();
      return g.copyWith(pilgrims: pilgrims);
    }).toList();
    state = state.copyWith(groups: groups);
  }

  // Update a specific pilgrim's location internally from socket event
  void updatePilgrimLocation(
    String pilgrimId,
    double lat,
    double lng,
    int? batteryPercent,
  ) {
    final groups = state.groups.map((g) {
      final pilgrims = g.pilgrims.map((p) {
        if (p.id == pilgrimId) {
          return p.copyWith(
            lat: lat,
            lng: lng,
            batteryPercent: batteryPercent ?? p.batteryPercent,
            lastUpdated: DateTime.now(),
          );
        }
        return p;
      }).toList();
      return g.copyWith(pilgrims: pilgrims);
    }).toList();
    state = state.copyWith(groups: groups);
  }

  // Update a specific pilgrim's status internally from socket event
  void updatePilgrimStatus(
    String pilgrimId,
    bool isOnline,
    DateTime lastActiveAt,
  ) {
    final groups = state.groups.map((g) {
      final pilgrims = g.pilgrims.map((p) {
        if (p.id == pilgrimId) {
          return p.copyWith(
            isOnline: isOnline,
            lastUpdated: isOnline ? DateTime.now() : lastActiveAt,
          );
        }
        return p;
      }).toList();
      return g.copyWith(pilgrims: pilgrims);
    }).toList();
    state = state.copyWith(groups: groups);
  }

  // ── Group management ──────────────────────────────────────────────────────

  // Add a pilgrim by user_id or email / phone / national ID
  Future<(bool, String?)> addPilgrimToGroup(
    String groupId, {
    String? userId,
    String? identifier,
  }) async {
    if (userId == null && (identifier == null || identifier.trim().isEmpty)) {
      return (false, 'Invalid pilgrim identifier');
    }
    try {
      await ApiService.dio.post(
        '/groups/$groupId/add-pilgrim',
        data: userId != null
            ? {'user_id': userId}
            : {'identifier': identifier!.trim()},
      );
      await syncAfterMutation(groupId: groupId);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Remove a pilgrim from the group
  Future<(bool, String?)> removePilgrimFromGroup(
    String groupId,
    String pilgrimId,
  ) async {
    try {
      await ApiService.dio.post(
        '/groups/$groupId/remove-pilgrim',
        data: {'user_id': pilgrimId},
      );
      await syncAfterMutation(groupId: groupId);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  /// Permanently deletes a pilgrim from Manage Pilgrims (assigned or unassigned).
  Future<(bool, String?)> deleteManagedPilgrim(String pilgrimId) async {
    try {
      await ApiService.dio.delete('/auth/pilgrims/$pilgrimId');
      await loadDashboard(force: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Update a pilgrim's details (hotel, room, etc.)
  Future<(bool, String?)> updatePilgrimDetails(
    String pilgrimId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await ApiService.dio.put('/auth/pilgrims/$pilgrimId', data: updates);
      await loadDashboard(force: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Invite one or more moderators by email (sends email invites)
  Future<(bool, String?)> inviteModerators(
    String groupId,
    List<String> emails,
  ) async {
    try {
      final normalized = emails
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (normalized.isEmpty) {
        return (false, 'email_invalid');
      }

      await ApiService.dio.post(
        '/groups/$groupId/invite',
        data: normalized.length == 1
            ? {'email': normalized.first}
            : {'emails': normalized},
      );
      await syncAfterMutation(groupId: groupId);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Remove a moderator (creator only)
  Future<(bool, String?)> removeModeratorFromGroup(
    String groupId,
    String modId,
  ) async {
    try {
      await ApiService.dio.delete('/groups/$groupId/moderators/$modId');
      final groups = state.groups.map((g) {
        if (g.id != groupId) return g;
        return g.copyWith(
          moderators: g.moderators.where((m) => m.id != modId).toList(),
        );
      }).toList();
      state = state.copyWith(groups: groups);
      await loadDashboard(force: true, silently: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Re-fetch a single group and update state
  /// Fetches decrypted pilgrim profile fields (medical history, national ID, etc.).
  Future<PilgrimInGroup?> fetchPilgrimById(String pilgrimId) async {
    try {
      final resp = await ApiService.dio.get('/auth/pilgrims/$pilgrimId');
      final body = resp.data;
      if (body is! Map) return null;
      return PilgrimInGroup.fromJson(Map<String, dynamic>.from(body));
    } on DioException catch (e) {
      AppLogger.e(
        '[ModeratorProvider] fetchPilgrimById($pilgrimId) failed: '
        '${ApiService.parseError(e)}',
      );
      return null;
    } catch (e) {
      AppLogger.e('[ModeratorProvider] fetchPilgrimById($pilgrimId) failed: $e');
      return null;
    }
  }

  Future<bool> refreshGroup(String groupId) async {
    try {
      final resp = await ApiService.dio.get('/groups/$groupId');
      final updated = ModeratorGroup.fromJson(
        resp.data as Map<String, dynamic>,
      );
      final groups = state.groups
          .map((g) => g.id == groupId ? updated : g)
          .toList();
      state = state.copyWith(groups: groups);
      return true;
    } catch (e) {
      AppLogger.e('[ModeratorProvider] refreshGroup($groupId) failed: $e');
      return false;
    }
  }

  // Create a new group — returns (success, errorMessage)
  Future<(bool, String?)> createGroup(
    String groupName, {
    DateTime? checkInDate,
    DateTime? checkOutDate,
  }) async {
    try {
      final data = <String, dynamic>{'group_name': groupName.trim()};
      if (checkInDate != null) {
        data['check_in_date'] = checkInDate.toIso8601String();
      }
      if (checkOutDate != null) {
        data['check_out_date'] = checkOutDate.toIso8601String();
      }

      final resp = await ApiService.dio.post('/groups/create', data: data);
      final created = ModeratorGroup.fromJson(
        resp.data as Map<String, dynamic>,
      );
      state = state.copyWith(groups: [...state.groups, created]);
      await syncAfterMutation();
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Join a group using a code
  Future<(bool, String?)> joinGroup(String code) async {
    try {
      await ApiService.dio.post(
        '/groups/join',
        data: {'group_code': code.trim().toUpperCase()},
      );
      await loadDashboard(force: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Leave a group — returns (success, errorMessage)
  Future<(bool, String?)> leaveGroup(
    String groupId, {
    String? newCreatorId,
  }) async {
    try {
      final body = newCreatorId != null
          ? {'new_creator_id': newCreatorId}
          : null;
      await ApiService.dio.post('/groups/$groupId/leave', data: body);
      final updated = state.groups.where((g) => g.id != groupId).toList();
      state = state.copyWith(groups: updated, selectedGroupIndex: 0);
      await _removeGroupFromDashboardCache(groupId);
      await loadDashboard(force: true, silently: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Delete a group — returns (success, errorMessage)
  Future<(bool, String?)> deleteGroup(String groupId) async {
    try {
      await ApiService.dio.delete('/groups/$groupId');
      final updated = state.groups.where((g) => g.id != groupId).toList();
      state = state.copyWith(groups: updated, selectedGroupIndex: 0);
      await _removeGroupFromDashboardCache(groupId);
      await loadDashboard(force: true, silently: true);
      return (true, null);
    } on DioException catch (e) {
      return (false, ApiService.parseError(e));
    } catch (e) {
      return (false, e.toString());
    }
  }

  // Broadcast urgent SOS message to all pilgrims in the current group
  Future<bool> broadcastSOS() async {
    final group = state.currentGroup;
    if (group == null) return false;
    state = state.copyWith(isBroadcastingSOS: true);
    try {
      await ApiService.dio.post(
        '/messages',
        data: {
          'group_id': group.id,
          'type': 'text',
          'content':
              '🚨 EMERGENCY — Please follow your moderator\'s instructions immediately.',
          'is_urgent': true,
        },
      );
      state = state.copyWith(isBroadcastingSOS: false);
      return true;
    } on DioException {
      state = state.copyWith(isBroadcastingSOS: false);
      return false;
    } catch (_) {
      state = state.copyWith(isBroadcastingSOS: false);
      return false;
    }
  }
}

final moderatorProvider = NotifierProvider<ModeratorNotifier, ModeratorState>(
  ModeratorNotifier.new,
);
