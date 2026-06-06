import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dio/dio.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'document_viewer_screen.dart';

// ── Models for Logistics ─────────────────────────────────────────────────────

class LogisticsHotel {
  final String id;
  final String name;
  final String? city;
  final List<LogisticsRoom> rooms;

  LogisticsHotel({
    required this.id,
    required this.name,
    this.city,
    required this.rooms,
  });

  factory LogisticsHotel.fromJson(Map<String, dynamic> json) {
    final roomsRaw = json['rooms'] as List<dynamic>? ?? const [];
    return LogisticsHotel(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      city: json['city']?.toString(),
      rooms: roomsRaw
          .whereType<Map>()
          .map((r) => LogisticsRoom.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }
}

class LogisticsRoom {
  final String id;
  final String roomNumber;
  final String? floor;
  final bool active;
  final int capacity;
  final int currentOccupancy;

  LogisticsRoom({
    required this.id,
    required this.roomNumber,
    this.floor,
    this.active = true,
    required this.capacity,
    this.currentOccupancy = 0,
  });

  factory LogisticsRoom.fromJson(Map<String, dynamic> json) {
    return LogisticsRoom(
      id: json['_id']?.toString() ?? '',
      roomNumber: json['room_number']?.toString() ?? '',
      floor: json['floor']?.toString(),
      active: json['active'] != false,
      capacity: (json['capacity'] as num?)?.toInt() ?? 1,
      currentOccupancy: (json['current_occupancy'] as num?)?.toInt() ?? 0,
    );
  }
}


class LogisticsInsuranceHospital {
  final String name;
  final String? address;
  final double latitude;
  final double longitude;

  LogisticsInsuranceHospital({
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
  });

  factory LogisticsInsuranceHospital.fromJson(Map<String, dynamic> json) {
    return LogisticsInsuranceHospital(
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class LogisticsInsurance {
  final String id;
  final String name;
  final List<LogisticsInsuranceHospital> hospitals;
  final String? policyDocumentUrl;
  final String? policyDocumentName;

  LogisticsInsurance({
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

  factory LogisticsInsurance.fromJson(Map<String, dynamic> json) {
    final hospRaw = json['hospitals'] as List<dynamic>? ?? const [];
    return LogisticsInsurance(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      hospitals: hospRaw
          .whereType<Map>()
          .map((h) => LogisticsInsuranceHospital.fromJson(Map<String, dynamic>.from(h)))
          .toList(),
      policyDocumentUrl: json['policy_document_url']?.toString(),
      policyDocumentName: json['policy_document_name']?.toString(),
    );
  }
}

// ── Screen Widget ────────────────────────────────────────────────────────────

class GroupLogisticsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupLogisticsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupLogisticsScreen> createState() => _GroupLogisticsScreenState();
}

class _GroupLogisticsScreenState extends State<GroupLogisticsScreen> {
  bool _isLoading = true;
  String? _error;

  List<LogisticsHotel> _hotels = const [];
  List<LogisticsInsurance> _insurances = const [];

  @override
  void initState() {
    super.initState();
    _loadLogistics();
  }

  Future<void> _loadLogistics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final resp = await ApiService.dio.get('/groups/${widget.groupId}/resource-options');
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};

      final hotelsRaw = (payload['hotels'] as List<dynamic>? ?? const []);
      final insurancesRaw = (payload['insurances'] as List<dynamic>? ?? const []);

      if (!mounted) return;
      setState(() {
        _hotels = hotelsRaw
            .whereType<Map>()
            .map((h) => LogisticsHotel.fromJson(Map<String, dynamic>.from(h)))
            .toList();

        _insurances = insurancesRaw
            .whereType<Map>()
            .map((i) => LogisticsInsurance.fromJson(Map<String, dynamic>.from(i)))
            .toList();

        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.parseError(e);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ── Stat calculations ──────────────────────────────────────────────────────

  int get _hotelsCount => _hotels.length;

  int get _activeRoomsCount {
    return _hotels.fold<int>(0, (sum, hotel) {
      return sum + hotel.rooms.where((r) => r.active).length;
    });
  }

  int get _totalBedsPool {
    return _hotels.fold<int>(0, (sum, hotel) {
      return sum + hotel.rooms
          .where((r) => r.active)
          .fold<int>(0, (roomSum, room) => roomSum + room.capacity);
    });
  }

  int get _insurancesCount => _insurances.length;

  // ── Build Method ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'logistics_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.error, size: 48.w, color: AppColors.error),
                        SizedBox(height: 12.h),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: isDark ? Colors.white70 : AppColors.textMutedDark,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        ElevatedButton.icon(
                          onPressed: _loadLogistics,
                          icon: const Icon(Symbols.refresh),
                          label: Text('alerts_retry'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadLogistics,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
                    children: [
                      // Group Name Header
                      Text(
                        widget.groupName,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 20.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // Stats Grid (Horizontal scrollable view)
                      _buildStatsRow(isDark),
                      SizedBox(height: 24.h),

                      // Hotel Lodging Allocations
                      _buildHotelsSection(isDark),
                      SizedBox(height: 24.h),

                      // Insurance Coverage
                      _buildInsuranceSection(isDark),
                    ],
                  ),
                ),
    );
  }

  // ── Stats Row Widget ───────────────────────────────────────────────────────

  Widget _buildStatsRow(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.domain,
            iconColor: const Color(0xFF534AB7),
            iconBg: const Color(0xFFEEEDFE),
            label: 'logistics_hotels_whitelisted'.tr(),
            value: '$_hotelsCount',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.door_open,
            iconColor: const Color(0xFF0F6E56),
            iconBg: const Color(0xFFE1F5EE),
            label: 'logistics_active_room_units'.tr(),
            value: '$_activeRoomsCount',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.bed,
            iconColor: const Color(0xFF185FA5),
            iconBg: const Color(0xFFE6F1FB),
            label: 'logistics_total_bed_pool'.tr(),
            value: '$_totalBedsPool',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.shield,
            iconColor: const Color(0xFF993356),
            iconBg: const Color(0xFFFBEAF0),
            label: 'logistics_insurance_providers'.tr(),
            value: '$_insurancesCount',
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Container(
      width: 120.w,
      height: 105.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(6.r),
            ),
            child: Icon(icon, size: 16.w, color: iconColor),
          ),
          const Spacer(),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 8.sp,
              color: isDark ? Colors.white38 : AppColors.textMutedDark,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 16.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hotel Section ──────────────────────────────────────────────────────────

  Widget _buildHotelsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Symbols.domain, color: Color(0xFF534AB7)),
            SizedBox(width: 8.w),
            Text(
              'logistics_hotel_lodging_allocations'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 14.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        if (_hotels.isEmpty)
          _buildEmptyCard(
            isDark: isDark,
            icon: Symbols.domain_disabled,
            title: 'logistics_no_lodgings_title'.tr(),
            description: 'logistics_no_lodgings_desc'.tr(),
          )
        else
          ..._hotels.map((hotel) => _buildHotelCard(hotel, isDark)),
      ],
    );
  }

  Widget _buildHotelCard(LogisticsHotel hotel, bool isDark) {
    final activeRooms = hotel.rooms.where((r) => r.active).length;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hotel.name,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Icon(Symbols.pin_drop, size: 12.w, color: const Color(0xFF534AB7)),
                          SizedBox(width: 4.w),
                          Text(
                            hotel.city ?? 'logistics_no_city'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11.sp,
                              color: isDark ? Colors.white54 : AppColors.textMutedDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1F5EE),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'logistics_active_rooms_badge'.tr(args: ['$activeRooms']),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 10.sp,
                      color: const Color(0xFF0F6E56),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Divider(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              height: 1,
            ),
          ),

          // Rooms Wrap
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'logistics_room_capacities'.tr().toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 8.sp,
                    color: isDark ? Colors.white38 : AppColors.textMutedDark,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8.h),
                if (hotel.rooms.isEmpty)
                  Text(
                    'logistics_no_rooms'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : AppColors.textMutedDark,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: hotel.rooms.map((room) => _buildRoomBox(room, isDark)).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomBox(LogisticsRoom room, bool isDark) {
    return Container(
      width: 100.w,
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'logistics_room_label'.tr(args: [room.roomNumber]),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 10.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              Container(
                width: 5.w,
                height: 5.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: room.active ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Row(
            children: [
              Icon(Symbols.bed, size: 10.w, color: isDark ? Colors.white38 : AppColors.textMutedDark),
              SizedBox(width: 4.w),
              Text(
                '${room.capacity} ${'logistics_beds'.tr()}',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 9.sp,
                  color: isDark ? Colors.white60 : AppColors.textMutedDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ── Insurance Section ──────────────────────────────────────────────────────

  Widget _buildInsuranceSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Symbols.shield, color: Color(0xFF993356)),
            SizedBox(width: 8.w),
            Text(
              'logistics_insurance_coverage'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 14.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        if (_insurances.isEmpty)
          _buildEmptyCard(
            isDark: isDark,
            icon: Symbols.heart_broken,
            title: 'logistics_no_insurances_assigned'.tr(),
            description: 'logistics_no_insurances_desc'.tr(),
          )
        else
          ..._insurances.map((ins) => _buildInsuranceCard(ins, isDark)),
      ],
    );
  }

  Widget _buildInsuranceCard(LogisticsInsurance ins, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ins.name,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE8E8),
                              borderRadius: BorderRadius.circular(4.r),
                            ),
                            child: Text(
                              'Active policy'.toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 7.sp,
                                color: const Color(0xFF993356),
                              ),
                            ),
                          ),
                          if (ins.policyDocumentUrl != null && ins.policyDocumentUrl!.isNotEmpty) ...[
                            SizedBox(width: 6.w),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DocumentViewerScreen(
                                      url: ins.policyDocumentProxyUrl!,
                                      title: ins.policyDocumentName ?? 'Insurance Policy',
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(4.r),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4.r),
                                  border: Border.all(
                                    color: isDark ? Colors.white10 : const Color(0xFFBFDBFE),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Symbols.picture_as_pdf,
                                      size: 10.w,
                                      color: const Color(0xFF2563EB),
                                    ),
                                    SizedBox(width: 3.w),
                                    Text(
                                      'View Policy'.toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 7.sp,
                                        color: const Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBEAF0),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'logistics_hospitals_count'.tr(args: ['${ins.hospitals.length}']),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 10.sp,
                      color: const Color(0xFF993356),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Divider(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
              height: 1,
            ),
          ),

          // Hospitals List
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'logistics_covered_hospitals'.tr().toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 8.sp,
                    color: isDark ? Colors.white38 : AppColors.textMutedDark,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8.h),
                if (ins.hospitals.isEmpty)
                  Text(
                    'logistics_no_hospitals'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : AppColors.textMutedDark,
                    ),
                  )
                else
                  ...ins.hospitals.map((hosp) => _buildHospitalTile(hosp, isDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalTile(LogisticsInsuranceHospital hosp, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.local_hospital, size: 16.w, color: const Color(0xFF993356)),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hosp.name,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 11.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                if (hosp.address != null && hosp.address!.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(
                    hosp.address!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 9.sp,
                      color: isDark ? Colors.white54 : AppColors.textMutedDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper Empty State Widget ──────────────────────────────────────────────

  Widget _buildEmptyCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          style: BorderStyle.solid,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32.w, color: isDark ? Colors.white24 : AppColors.textMutedLight),
          SizedBox(height: 8.h),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 13.sp,
              color: isDark ? Colors.white70 : AppColors.textDark,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              color: isDark ? Colors.white38 : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}


