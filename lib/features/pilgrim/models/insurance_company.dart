class HospitalLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;

  const HospitalLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  factory HospitalLocation.fromJson(Map<String, dynamic> j) => HospitalLocation(
    id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    latitude: (j['latitude'] as num?)?.toDouble() ?? 0.0,
    longitude: (j['longitude'] as num?)?.toDouble() ?? 0.0,
    address: j['address']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
  };
}

class InsuranceCompany {
  final String id;
  final String name;
  final List<HospitalLocation> hospitals;

  const InsuranceCompany({
    required this.id,
    required this.name,
    required this.hospitals,
  });

  factory InsuranceCompany.fromJson(Map<String, dynamic> j) => InsuranceCompany(
    id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    hospitals: (j['hospitals'] as List?)
            ?.map((h) => HospitalLocation.fromJson(Map<String, dynamic>.from(h)))
            .toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'hospitals': hospitals.map((h) => h.toJson()).toList(),
  };
}
