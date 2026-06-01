// ─────────────────────────────────────────────────────────────────────────────
// Reminder model — matches reminder_model.js on the backend
// ─────────────────────────────────────────────────────────────────────────────

class ReminderModel {
  final String id;
  final String groupId;
  final String targetType;
  final String? pilgrimId;
  final String? pilgrimName;
  final String text;
  final DateTime scheduledAt;
  final int repeatCount;
  final int repeatIntervalMin;
  final String status; // 'pending' | 'active' | 'completed' | 'cancelled'
  final int firesSent;
  final DateTime createdAt;
  /// Number of groups in group_ids (for display).
  final int groupIdsCount;
  /// Dart weekdays 1=Mon … 7=Sun; empty = interval-based repeats only.
  final List<int> weeklyDays;

  const ReminderModel({
    required this.id,
    required this.groupId,
    required this.targetType,
    this.pilgrimId,
    this.pilgrimName,
    required this.text,
    required this.scheduledAt,
    required this.repeatCount,
    required this.repeatIntervalMin,
    required this.status,
    required this.firesSent,
    required this.createdAt,
    this.groupIdsCount = 0,
    this.weeklyDays = const [],
  });

  bool get isActive => status == 'pending' || status == 'active';

  factory ReminderModel.fromJson(Map<String, dynamic> j) {
    final pilgrimIdRaw = j['pilgrim_id'];
    String? pilgrimId;
    String? pilgrimName;
    if (pilgrimIdRaw is Map) {
      pilgrimId = pilgrimIdRaw['_id']?.toString();
      pilgrimName = pilgrimIdRaw['full_name']?.toString();
    } else if (pilgrimIdRaw is String) {
      pilgrimId = pilgrimIdRaw;
    }

    var groupId = _extractId(j['group_id']);
    var groupIdsCount = 0;
    final rawIds = j['group_ids'];
    if (rawIds is List) {
      groupIdsCount = rawIds.length;
      if (groupId.isEmpty && rawIds.isNotEmpty) {
        groupId = _extractId(rawIds.first);
      }
    }

    List<int> weeklyDays = const [];
    final wd = j['weekly_days'];
    if (wd is List) {
      weeklyDays = wd
          .map((e) => (e as num?)?.toInt())
          .whereType<int>()
          .where((d) => d >= 1 && d <= 7)
          .toList();
    }

    return ReminderModel(
      id: j['_id']?.toString() ?? '',
      groupId: groupId,
      targetType: j['target_type']?.toString() ?? 'pilgrim',
      pilgrimId: pilgrimId,
      pilgrimName: pilgrimName,
      text: j['text']?.toString() ?? '',
      scheduledAt:
          DateTime.tryParse(j['scheduled_at']?.toString() ?? '') ??
          DateTime.now(),
      repeatCount: (j['repeat_count'] as num?)?.toInt() ?? 1,
      repeatIntervalMin: (j['repeat_interval_min'] as num?)?.toInt() ?? 15,
      status: j['status']?.toString() ?? 'pending',
      firesSent: (j['fires_sent'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      groupIdsCount: groupIdsCount,
      weeklyDays: weeklyDays,
    );
  }

  static String _extractId(dynamic val) {
    if (val is Map) return val['_id']?.toString() ?? '';
    return val?.toString() ?? '';
  }
}
