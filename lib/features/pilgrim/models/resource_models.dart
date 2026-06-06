import '../../../../core/services/api_service.dart';

class HotelRoom {
  final String id;
  final String roomNumber;
  final String floor;
  final int capacity;

  const HotelRoom({
    required this.id,
    required this.roomNumber,
    required this.floor,
    required this.capacity,
  });

  factory HotelRoom.fromJson(Map<String, dynamic> j) => HotelRoom(
    id: j['_id']?.toString() ?? '',
    roomNumber: j['room_number']?.toString() ?? '',
    floor: j['floor']?.toString() ?? '',
    capacity: (j['capacity'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'room_number': roomNumber,
    'floor': floor,
    'capacity': capacity,
  };
}

class Hotel {
  final String id;
  final String name;
  final String city;
  final String address;
  final bool active;
  final String notes;
  final double latitude;
  final double longitude;
  final List<HotelRoom> rooms;

  const Hotel({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.active,
    required this.notes,
    required this.latitude,
    required this.longitude,
    required this.rooms,
  });

  factory Hotel.fromJson(Map<String, dynamic> j) => Hotel(
    id: j['_id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    city: j['city']?.toString() ?? '',
    address: j['address']?.toString() ?? '',
    active: j['active'] == true,
    notes: j['notes']?.toString() ?? '',
    latitude: (j['latitude'] as num?)?.toDouble() ?? 0.0,
    longitude: (j['longitude'] as num?)?.toDouble() ?? 0.0,
    rooms: (j['rooms'] as List<dynamic>? ?? [])
        .map((r) => HotelRoom.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'city': city,
    'address': address,
    'active': active,
    'notes': notes,
    'latitude': latitude,
    'longitude': longitude,
    'rooms': rooms.map((r) => r.toJson()).toList(),
  };
}

class InsuranceHospital {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const InsuranceHospital({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory InsuranceHospital.fromJson(Map<String, dynamic> j) =>
      InsuranceHospital(
        id: j['_id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        latitude: (j['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };
}

class Insurance {
  final String id;
  final String name;
  final bool active;
  final String? policyDocumentName;
  final String? policyDocumentUrl;
  final List<InsuranceHospital> hospitals;

  const Insurance({
    required this.id,
    required this.name,
    required this.active,
    this.policyDocumentName,
    this.policyDocumentUrl,
    required this.hospitals,
  });

  String? get policyDocumentProxyUrl {
    if (policyDocumentUrl == null || policyDocumentUrl!.isEmpty) return null;
    if (policyDocumentUrl!.startsWith('http') && policyDocumentUrl!.contains('/api/documents/')) {
      return policyDocumentUrl;
    }
    if (policyDocumentUrl!.contains('storage.googleapis.com')) {
      try {
        final uri = Uri.parse(policyDocumentUrl!);
        final segments = uri.pathSegments;
        final index = segments.indexOf('insurance-policies');
        if (index != -1 && index < segments.length - 1) {
          final filename = segments.sublist(index + 1).join('/');
          final base = ApiService.baseUrl;
          return '$base/documents/insurance-policies/$filename';
        }
      } catch (_) {}
    }
    return policyDocumentUrl;
  }

  factory Insurance.fromJson(Map<String, dynamic> j) => Insurance(
    id: j['_id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    active: j['active'] == true,
    policyDocumentName: j['policy_document_name']?.toString(),
    policyDocumentUrl: j['policy_document_url']?.toString(),
    hospitals: (j['hospitals'] as List<dynamic>? ?? [])
        .map((h) =>
            InsuranceHospital.fromJson(Map<String, dynamic>.from(h as Map)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'active': active,
    'policy_document_name': policyDocumentName,
    'policy_document_url': policyDocumentUrl,
    'hospitals': hospitals.map((h) => h.toJson()).toList(),
  };
}
