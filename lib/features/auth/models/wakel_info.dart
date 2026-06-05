class WakelInfo {
  final String id;
  final String name;
  final String? profilePicture;
  final String contactNumber;
  final bool active;

  const WakelInfo({
    required this.id,
    required this.name,
    this.profilePicture,
    required this.contactNumber,
    this.active = true,
  });

  factory WakelInfo.fromJson(Map<String, dynamic> j) => WakelInfo(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        profilePicture: j['profile_picture']?.toString(),
        contactNumber: j['contact_number']?.toString() ?? '',
        active: j['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'profile_picture': profilePicture,
        'contact_number': contactNumber,
        'active': active,
      };
}
