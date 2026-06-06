import '../../../../core/services/api_service.dart';

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
  final String? policyDocumentUrl;
  final String? policyDocumentName;

  const InsuranceCompany({
    required this.id,
    required this.name,
    required this.hospitals,
    this.policyDocumentUrl,
    this.policyDocumentName,
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

  factory InsuranceCompany.fromJson(Map<String, dynamic> j) => InsuranceCompany(
    id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    hospitals: (j['hospitals'] as List?)
            ?.map((h) => HospitalLocation.fromJson(Map<String, dynamic>.from(h)))
            .toList() ??
        const [],
    policyDocumentUrl: j['policy_document_url']?.toString(),
    policyDocumentName: j['policy_document_name']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'hospitals': hospitals.map((h) => h.toJson()).toList(),
    'policy_document_url': policyDocumentUrl,
    'policy_document_name': policyDocumentName,
  };
}

