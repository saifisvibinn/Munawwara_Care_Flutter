// Normalized SOS payload from socket, FCM, or deep link (moderator side).
class SosModeratorPayload {
  final String? sosId;
  final String pilgrimName;
  final String? pilgrimId;
  final String? groupId;
  final String groupName;
  final String? pilgrimGender;
  final double? lat;
  final double? lng;

  const SosModeratorPayload({
    required this.sosId,
    required this.pilgrimName,
    required this.pilgrimId,
    required this.groupId,
    required this.groupName,
    required this.pilgrimGender,
    required this.lat,
    required this.lng,
  });

  bool get hasCoords => lat != null && lng != null;

  /// Stable key for SharedPreferences (prefer server sos_id).
  String get storageKey {
    if (sosId != null && sosId!.isNotEmpty) return sosId!;
    final p = pilgrimId ?? '';
    final g = groupId ?? '';
    return 'c_${p}_$g';
  }

  static SosModeratorPayload fromMap(Map<String, dynamic> raw) {
    String? socketStringId(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      if (v is Map) {
        final id = v['_id'] ?? v['id'];
        return id?.toString();
      }
      return v.toString();
    }

    final name = raw['pilgrim_name']?.toString() ??
        raw['pilgrimName']?.toString() ??
        'A pilgrim';
    final pid =
        socketStringId(raw['pilgrim_id']) ?? socketStringId(raw['pilgrimId']);
    final gid =
        socketStringId(raw['group_id']) ?? socketStringId(raw['groupId']);
    final gname = raw['group_name']?.toString() ?? '';
    final sid = raw['sos_id']?.toString();

    double? lat;
    double? lng;
    final loc = raw['location'];
    if (loc is Map) {
      lat = _readCoord(loc['lat']) ?? _readCoord(loc['latitude']);
      lng = _readCoord(loc['lng']) ?? _readCoord(loc['longitude']);
    }
    lat ??= _readCoord(raw['lat']);
    lng ??= _readCoord(raw['lng']);

    String? genderStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    String? pilgrimGender =
        genderStr(raw['gender']) ?? genderStr(raw['pilgrim_gender']);
    final pilgrimObj = raw['pilgrim'];
    if (pilgrimGender == null && pilgrimObj is Map) {
      final pm = Map<String, dynamic>.from(pilgrimObj);
      pilgrimGender =
          genderStr(pm['gender']) ?? genderStr(pm['pilgrim_gender']);
    }

    return SosModeratorPayload(
      sosId: sid,
      pilgrimName: name,
      pilgrimId: pid,
      groupId: gid,
      groupName: gname,
      pilgrimGender: pilgrimGender,
      lat: lat,
      lng: lng,
    );
  }

  static double? _readCoord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
