import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
import 'moderator_provider.dart';
import '../../pilgrim/models/insurance_company.dart';

/// Pilgrim row for Manage Pilgrims (`GET /groups/my-pilgrims`).
class ManagedPilgrimItem {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? nationalId;
  final int? age;
  final String? gender;
  final String? profilePicture;
  final String language;
  final String ethnicity;
  final bool isOnline;
  final String? currentGroupId;
  final String? currentGroupName;
  final String? limboReason;
  final String? limboGroupName;
  final String? hotelName;
  final String? roomNumber;
  final String? busInfo;
  final String? medicalHistory;
  final String? alternativePhoneNumber;
  final String? morafeqName;
  final String? morafeqPhone;
  final String? morafeqEmail;
  final String? tasheraNumber;
  final InsuranceCompany? insuranceCompany;

  const ManagedPilgrimItem({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.nationalId,
    this.age,
    this.gender,
    this.profilePicture,
    required this.language,
    required this.ethnicity,
    required this.isOnline,
    this.currentGroupId,
    this.currentGroupName,
    this.limboReason,
    this.limboGroupName,
    this.hotelName,
    this.roomNumber,
    this.busInfo,
    this.medicalHistory,
    this.alternativePhoneNumber,
    this.morafeqName,
    this.morafeqPhone,
    this.morafeqEmail,
    this.tasheraNumber,
    this.insuranceCompany,
  });

  factory ManagedPilgrimItem.fromMap(Map<String, dynamic> m) {
    final g = m['current_group'] as Map<String, dynamic>?;
    return ManagedPilgrimItem(
      id: m['_id']?.toString() ?? '',
      fullName: m['full_name']?.toString() ?? '',
      phoneNumber: m['phone_number']?.toString() ?? '',
      nationalId: m['national_id']?.toString(),
      age: m['age'] as int?,
      gender: m['gender']?.toString(),
      profilePicture: m['profile_picture']?.toString(),
      language: m['language']?.toString() ?? 'en',
      ethnicity: m['ethnicity']?.toString() ?? 'Other',
      isOnline: m['is_online'] == true,
      currentGroupId: g?['group_id']?.toString(),
      currentGroupName: g?['group_name']?.toString(),
      limboReason: m['limbo_reason']?.toString(),
      limboGroupName: m['limbo_group_name']?.toString(),
      hotelName: m['hotel_name']?.toString(),
      roomNumber: m['room_number']?.toString(),
      busInfo: m['bus_info']?.toString(),
      medicalHistory: m['medical_history']?.toString(),
      alternativePhoneNumber: m['alternative_phone_number']?.toString(),
      morafeqName: m['morafeq_name']?.toString(),
      morafeqPhone: m['morafeq_phone']?.toString(),
      morafeqEmail: m['morafeq_email']?.toString(),
      tasheraNumber: m['tashera_number']?.toString(),
      insuranceCompany: m['insurance_company_id'] != null
          ? InsuranceCompany.fromJson(Map<String, dynamic>.from(m['insurance_company_id']))
          : null,
    );
  }

  bool get isAssigned => currentGroupId != null;

  PilgrimInGroup toPilgrimInGroup() => PilgrimInGroup(
        id: id,
        fullName: fullName,
        phoneNumber: phoneNumber,
        nationalId: nationalId,
        isOnline: isOnline,
        lastUpdated: DateTime.now(),
        hotelName: hotelName,
        roomNumber: roomNumber,
        busInfo: busInfo,
        language: language,
        ethnicity: ethnicity,
        medicalHistory: medicalHistory,
        age: age,
        gender: gender,
        profilePicture: profilePicture,
        alternativePhoneNumber: alternativePhoneNumber,
        morafeqName: morafeqName,
        morafeqPhone: morafeqPhone,
        morafeqEmail: morafeqEmail,
        tasheraNumber: tasheraNumber,
        insuranceCompany: insuranceCompany,
      );
}

class ManagePilgrimsState {
  final List<ManagedPilgrimItem> pilgrims;
  final bool isLoading;
  final String? error;

  const ManagePilgrimsState({
    this.pilgrims = const [],
    this.isLoading = false,
    this.error,
  });

  ManagePilgrimsState copyWith({
    List<ManagedPilgrimItem>? pilgrims,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ManagePilgrimsState(
      pilgrims: pilgrims ?? this.pilgrims,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ManagePilgrimsNotifier extends Notifier<ManagePilgrimsState> {
  @override
  ManagePilgrimsState build() => const ManagePilgrimsState();

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await ApiService.dio.get('/groups/my-pilgrims');
      final raw = resp.data['data'] as List<dynamic>? ?? [];
      final pilgrims = raw
          .whereType<Map<String, dynamic>>()
          .map(ManagedPilgrimItem.fromMap)
          .where((p) => p.id.isNotEmpty)
          .toList();
      state = state.copyWith(pilgrims: pilgrims, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiService.parseError(e),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final managePilgrimsProvider =
    NotifierProvider<ManagePilgrimsNotifier, ManagePilgrimsState>(
  ManagePilgrimsNotifier.new,
);
