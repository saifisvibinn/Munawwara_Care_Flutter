// ─────────────────────────────────────────────────────────────────────────────
// Reminder model — matches reminder_model.js on the backend
// ─────────────────────────────────────────────────────────────────────────────

class ReminderModel {
  final String id;
  final String groupId;
  final String targetType; // 'pilgrim' | 'group'
  final String? pilgrimId;
  final String? pilgrimName;
  final String text;
  final DateTime scheduledAt;
  final int repeatCount;
  final int repeatIntervalMin;
  final String status; // 'pending' | 'active' | 'completed' | 'cancelled'
  final int firesSent;
  final DateTime createdAt;

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

    return ReminderModel(
      id: j['_id']?.toString() ?? '',
      groupId: _extractId(j['group_id']),
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
    );
  }

  static String _extractId(dynamic val) {
    if (val is Map) return val['_id']?.toString() ?? '';
    return val?.toString() ?? '';
  }
}
