

class GroupOption {
  final String id;
  final String name;

  const GroupOption({required this.id, required this.name});
}

class ProvisioningSummary {
  final int totalProvisioned;
  final int pendingCount;
  final int activatedCount;

  const ProvisioningSummary({
    this.totalProvisioned = 0,
    this.pendingCount = 0,
    this.activatedCount = 0,
  });

  factory ProvisioningSummary.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ProvisioningSummary(
      totalProvisioned: toInt(map['total_provisioned']),
      pendingCount: toInt(map['pending_count']),
      activatedCount: toInt(map['activated_count']),
    );
  }
}

class ProvisioningItem {
  final String pilgrimId;
  final String fullName;
  final String phoneNumber;
  final String status;
  final String? token;
  final String? expiresAt;
  final String? qrDataUrl;
  final String? hotelName;
  final String? roomNumber;
  final String? busInfo;
  final String? visaNumber;
  final String? visaStatus;

  const ProvisioningItem({
    required this.pilgrimId,
    required this.fullName,
    required this.phoneNumber,
    required this.status,
    this.token,
    this.expiresAt,
    this.qrDataUrl,
    this.hotelName,
    this.roomNumber,
    this.busInfo,
    this.visaNumber,
    this.visaStatus,
  });

  ProvisioningItem copyWith({
    String? pilgrimId,
    String? fullName,
    String? phoneNumber,
    String? status,
    String? token,
    String? expiresAt,
    String? qrDataUrl,
    String? hotelName,
    String? roomNumber,
    String? busInfo,
    String? visaNumber,
    String? visaStatus,
  }) {
    return ProvisioningItem(
      pilgrimId: pilgrimId ?? this.pilgrimId,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      status: status ?? this.status,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
      qrDataUrl: qrDataUrl ?? this.qrDataUrl,
      hotelName: hotelName ?? this.hotelName,
      roomNumber: roomNumber ?? this.roomNumber,
      busInfo: busInfo ?? this.busInfo,
      visaNumber: visaNumber ?? this.visaNumber,
      visaStatus: visaStatus ?? this.visaStatus,
    );
  }

  factory ProvisioningItem.fromJson(Map<String, dynamic> map) {
    final pilgrim =
        (map['pilgrim'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final login =
        (map['one_time_login'] as Map<String, dynamic>? ?? <String, dynamic>{});

    return ProvisioningItem(
      pilgrimId: pilgrim['_id']?.toString() ?? '',
      fullName: pilgrim['full_name']?.toString() ?? 'Unknown Pilgrim',
      phoneNumber: pilgrim['phone_number']?.toString() ?? '-',
      status: map['status']?.toString() ?? 'pending',
      token: login['token']?.toString(),
      expiresAt: login['expires_at']?.toString(),
      qrDataUrl: login['qr_code_data_url']?.toString(),
      hotelName: pilgrim['hotel_name']?.toString(),
      roomNumber: pilgrim['room_number']?.toString(),
      busInfo: pilgrim['bus_info']?.toString(),
      visaNumber: pilgrim['visa']?['visa_number']?.toString(),
      visaStatus: pilgrim['visa']?['status']?.toString(),
    );
  }
}

class HotelOption {
  final String id;
  final String name;
  final List<RoomOption> rooms;

  const HotelOption({
    required this.id,
    required this.name,
    required this.rooms,
  });
}

class RoomOption {
  final String id;
  final String roomNumber;
  final String? floor;
  final bool active;

  const RoomOption({
    required this.id,
    required this.roomNumber,
    this.floor,
    this.active = true,
  });
}

class BusOption {
  final String id;
  final String busNumber;
  final String destination;

  const BusOption({
    required this.id,
    required this.busNumber,
    required this.destination,
  });
}
