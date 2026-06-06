/// Models for the Bus/Trip Attendance feature.
///
/// Maps directly to the backend API responses from
/// `mc_backend_app/controllers/bus_attendance_controller.js`.

library;

class BoardedPilgrimEntry {
  final String pilgrimId;
  final DateTime boardedAt;
  final String method; // 'qr_scan' | 'manual_check'

  const BoardedPilgrimEntry({
    required this.pilgrimId,
    required this.boardedAt,
    required this.method,
  });

  factory BoardedPilgrimEntry.fromJson(Map<String, dynamic> j) =>
      BoardedPilgrimEntry(
        pilgrimId: j['pilgrim_id']?.toString() ?? '',
        boardedAt: DateTime.tryParse(j['boarded_at']?.toString() ?? '') ??
            DateTime.now(),
        method: j['method']?.toString() ?? 'qr_scan',
      );
}

// ── Active Session ────────────────────────────────────────────────────────────

class BoardingSession {
  final String id;
  final String groupId;
  final String moderatorId;
  final String busIdentifier;
  final String status; // 'created' | 'active' | 'completed'
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<BoardedPilgrimEntry> boardedPilgrims;

  const BoardingSession({
    required this.id,
    required this.groupId,
    required this.moderatorId,
    required this.busIdentifier,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.boardedPilgrims = const [],
  });

  factory BoardingSession.fromJson(Map<String, dynamic> j) {
    final boarded = (j['boarded_pilgrims'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BoardedPilgrimEntry.fromJson)
        .toList();
    return BoardingSession(
      id: j['_id']?.toString() ?? '',
      groupId: j['group_id']?.toString() ?? '',
      moderatorId: j['moderator_id']?.toString() ?? '',
      busIdentifier: j['bus_identifier']?.toString() ?? '',
      status: j['status']?.toString() ?? 'created',
      startedAt: j['started_at'] != null
          ? DateTime.tryParse(j['started_at'].toString())
          : null,
      completedAt: j['completed_at'] != null
          ? DateTime.tryParse(j['completed_at'].toString())
          : null,
      boardedPilgrims: boarded,
    );
  }

  bool get isActive => status == 'active';
  bool get isCreated => status == 'created';
}

// ── Boarded Pilgrim (enriched, from /status endpoint) ─────────────────────────

class BoardedPilgrim {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? roomNumber;
  final String? hotelName;
  final String? profilePicture;
  final String? gender;
  final int? age;
  final DateTime boardedAt;
  final String method;

  const BoardedPilgrim({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.roomNumber,
    this.hotelName,
    this.profilePicture,
    this.gender,
    this.age,
    required this.boardedAt,
    required this.method,
  });

  factory BoardedPilgrim.fromJson(Map<String, dynamic> j) => BoardedPilgrim(
        id: j['_id']?.toString() ?? '',
        fullName: j['full_name']?.toString() ?? '',
        phoneNumber: j['phone_number']?.toString(),
        roomNumber: j['room_number']?.toString(),
        hotelName: j['hotel_name']?.toString(),
        profilePicture: j['profile_picture']?.toString(),
        gender: j['gender']?.toString(),
        age: (j['age'] as num?)?.toInt(),
        boardedAt: DateTime.tryParse(j['boarded_at']?.toString() ?? '') ??
            DateTime.now(),
        method: j['method']?.toString() ?? 'qr_scan',
      );

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}

// ── Missing Pilgrim (enriched, from /status endpoint) ─────────────────────────

class MissingPilgrim {
  final String id;
  final String fullName;
  final String? phoneNumber;
  final String? roomNumber;
  final String? hotelName;
  final String? profilePicture;
  final String? gender;
  final int? age;
  final int? batteryPercent;
  final DateTime? lastActiveAt;
  final double? lat;
  final double? lng;
  final DateTime? lastUpdated;

  const MissingPilgrim({
    required this.id,
    required this.fullName,
    this.phoneNumber,
    this.roomNumber,
    this.hotelName,
    this.profilePicture,
    this.gender,
    this.age,
    this.batteryPercent,
    this.lastActiveAt,
    this.lat,
    this.lng,
    this.lastUpdated,
  });

  factory MissingPilgrim.fromJson(Map<String, dynamic> j) {
    final loc = j['location'] as Map<String, dynamic>?;
    return MissingPilgrim(
      id: j['_id']?.toString() ?? '',
      fullName: j['full_name']?.toString() ?? '',
      phoneNumber: j['phone_number']?.toString(),
      roomNumber: j['room_number']?.toString(),
      hotelName: j['hotel_name']?.toString(),
      profilePicture: j['profile_picture']?.toString(),
      gender: j['gender']?.toString(),
      age: (j['age'] as num?)?.toInt(),
      batteryPercent: (j['battery_percent'] as num?)?.toInt(),
      lastActiveAt: j['last_active_at'] != null
          ? DateTime.tryParse(j['last_active_at'].toString())
          : null,
      lat: (loc?['lat'] as num?)?.toDouble(),
      lng: (loc?['lng'] as num?)?.toDouble(),
      lastUpdated: j['last_updated'] != null
          ? DateTime.tryParse(j['last_updated'].toString())
          : null,
    );
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  bool get hasLocation => lat != null && lng != null;
}
