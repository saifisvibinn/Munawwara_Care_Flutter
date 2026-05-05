// ─────────────────────────────────────────────────────────────────────────────
// Suggested Area / Meetpoint model
// ─────────────────────────────────────────────────────────────────────────────

class SuggestedArea {
  /// Meetpoints are considered expired after this window past [meetpointTime].
  static const Duration meetpointExpiryWindow = Duration(minutes: 10);

  final String id;
  final String groupId;
  final String? createdByName;
  final String name;
  final String description;
  final String areaType; // 'suggestion' | 'meetpoint'
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime? meetpointTime;
  final int? reminderMinutes;

  const SuggestedArea({
    required this.id,
    required this.groupId,
    this.createdByName,
    required this.name,
    this.description = '',
    this.areaType = 'suggestion',
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.meetpointTime,
    this.reminderMinutes,
  });

  bool get isMeetpoint => areaType == 'meetpoint';

  factory SuggestedArea.fromJson(Map<String, dynamic> j) {
    // created_by can be a populated object or a plain string id
    String? creatorName;
    final cb = j['created_by'];
    if (cb is Map<String, dynamic>) {
      creatorName = cb['full_name']?.toString();
    }

    return SuggestedArea(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      groupId: (j['group_id'] ?? '').toString(),
      createdByName: creatorName,
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      areaType: j['area_type']?.toString() ?? 'suggestion',
      latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse(
            (j['createdAt'] ?? j['created_at'] ?? '').toString(),
          )?.toLocal() ??
          DateTime.now(),
      meetpointTime: j['meetpoint_time'] != null
          ? DateTime.tryParse(j['meetpoint_time'].toString())?.toLocal()
          : null,
      reminderMinutes: (j['reminder_minutes'] as num?)?.toInt(),
    );
  }
}
