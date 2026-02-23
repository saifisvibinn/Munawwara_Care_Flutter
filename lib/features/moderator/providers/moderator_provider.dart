import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';

// ── Pilgrim-in-group model ────────────────────────────────────────────────────

class PilgrimInGroup {
  final String id;
  final String fullName;
  final String? nationalId;
  final String? phoneNumber;
  final double? lat;
  final double? lng;
  final int? batteryPercent;
  final DateTime? lastUpdated;
  // Set to true when an SOS notification is received via push (FCM)
  final bool hasSOS;

  const PilgrimInGroup({
    required this.id,
    required this.fullName,
    this.nationalId,
    this.phoneNumber,
    this.lat,
    this.lng,
    this.batteryPercent,
    this.lastUpdated,
    this.hasSOS = false,
  });

  factory PilgrimInGroup.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    return PilgrimInGroup(
      id: j['_id']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      nationalId: j['national_id']?.toString(),
      phoneNumber: j['phone_number']?.toString(),
      lat: (loc?['lat'] as num?)?.toDouble(),
      lng: (loc?['lng'] as num?)?.toDouble(),
      batteryPercent: j['battery_percent'] as int?,
      lastUpdated: j['last_updated'] != null
          ? DateTime.tryParse(j['last_updated'].toString())
          : null,
    );
  }

  PilgrimInGroup copyWith({bool? hasSOS}) => PilgrimInGroup(
    id: id,
    fullName: fullName,
    nationalId: nationalId,
    phoneNumber: phoneNumber,
    lat: lat,
    lng: lng,
    batteryPercent: batteryPercent,
    lastUpdated: lastUpdated,
    hasSOS: hasSOS ?? this.hasSOS,
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

  /// Human-readable "last seen" text
  String get lastSeenText {
    if (lastUpdated == null) return '';
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }
}

enum BatteryStatus { good, medium, low, unknown }

// ── Group model ───────────────────────────────────────────────────────────────

class ModeratorGroup {
  final String id;
  final String groupName;
  final String groupCode;
  final List<PilgrimInGroup> pilgrims;

  const ModeratorGroup({
    required this.id,
    required this.groupName,
    required this.groupCode,
    required this.pilgrims,
  });

  factory ModeratorGroup.fromJson(Map<String, dynamic> j) => ModeratorGroup(
    id: j['_id']?.toString() ?? '',
    groupName: j['group_name']?.toString() ?? '',
    groupCode: j['group_code']?.toString() ?? '',
    pilgrims: (j['pilgrims'] as List<dynamic>? ?? [])
        .map((p) => PilgrimInGroup.fromJson(p as Map<String, dynamic>))
        .toList(),
  );

  int get totalPilgrims => pilgrims.length;
  int get onlineCount => pilgrims.where((p) => p.hasLocation).length;
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

  const ModeratorState({
    this.isLoading = false,
    this.error,
    this.groups = const [],
    this.selectedGroupIndex = 0,
    this.showSosOnly = false,
    this.searchQuery = '',
    this.isBroadcastingSOS = false,
  });

  ModeratorState copyWith({
    bool? isLoading,
    String? error,
    List<ModeratorGroup>? groups,
    int? selectedGroupIndex,
    bool? showSosOnly,
    String? searchQuery,
    bool? isBroadcastingSOS,
  }) => ModeratorState(
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
    groups: groups ?? this.groups,
    selectedGroupIndex: selectedGroupIndex ?? this.selectedGroupIndex,
    showSosOnly: showSosOnly ?? this.showSosOnly,
    searchQuery: searchQuery ?? this.searchQuery,
    isBroadcastingSOS: isBroadcastingSOS ?? this.isBroadcastingSOS,
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
  @override
  ModeratorState build() => const ModeratorState();

  // Load all groups + their pilgrims
  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await ApiService.dio.get('/groups/dashboard');
      final data = resp.data['data'] as List<dynamic>? ?? [];
      final groups = data
          .map((g) => ModeratorGroup.fromJson(g as Map<String, dynamic>))
          .toList();
      state = state.copyWith(isLoading: false, groups: groups);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectGroup(int index) {
    if (index < 0 || index >= state.groups.length) return;
    state = state.copyWith(selectedGroupIndex: index);
  }

  void toggleSosFilter() =>
      state = state.copyWith(showSosOnly: !state.showSosOnly);

  void updateSearch(String q) => state = state.copyWith(searchQuery: q);

  // Mark a specific pilgrim as having active SOS (called from FCM handler)
  void markPilgrimSOS(String pilgrimId, {bool active = true}) {
    final groups = state.groups.map((g) {
      final pilgrims = g.pilgrims.map((p) {
        if (p.id == pilgrimId) return p.copyWith(hasSOS: active);
        return p;
      }).toList();
      return ModeratorGroup(
        id: g.id,
        groupName: g.groupName,
        groupCode: g.groupCode,
        pilgrims: pilgrims,
      );
    }).toList();
    state = state.copyWith(groups: groups);
  }

  // Create a new group — returns (success, errorMessage)
  Future<(bool, String?)> createGroup(String groupName) async {
    try {
      final resp = await ApiService.dio.post(
        '/groups/create',
        data: {'group_name': groupName.trim()},
      );
      final created = ModeratorGroup.fromJson(resp.data as Map<String, dynamic>);
      state = state.copyWith(groups: [...state.groups, created]);
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
