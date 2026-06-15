import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dio/dio.dart';

import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass/app_glass.dart';
import '../../shared/widgets/area_ui_widgets.dart';
import '../../shared/widgets/group_chat_theme.dart';
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

  static double _navOverlayHeight(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 10.h + 42.w + 6.h;

  Widget _buildFloatingNav(bool isDark) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final navHeight = _navOverlayHeight(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: navHeight,
          child: AppScrollGlassEdge(
            height: navHeight,
            edge: AppScrollGlassEdgeSide.top,
            isDark: isDark,
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 6.h),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppGlassIconButton(
                    isDark: isDark,
                    icon: Symbols.arrow_back,
                    onTap: () => Navigator.pop(context),
                    size: 42.w,
                  ),
                ),
                AppGlassSurface(
                  isDark: isDark,
                  borderRadius: BorderRadius.circular(14.r),
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  glassTheme: AppGlassTheme.groupBroadcastNavPillOf(isDark),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 220.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'logistics_title'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          widget.groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(width: 42.w, height: 42.w),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = GroupChatTheme.scaffoldBackground(isDark);
    final topPad = _navOverlayHeight(context) + 8.h;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _error != null
                    ? Padding(
                        padding:
                            EdgeInsets.fromLTRB(24.w, topPad, 24.w, 24.h),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.error,
                                  size: 48.w, color: AppColors.error),
                              SizedBox(height: 12.h),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  color: AreaUiTheme.sectionLabel(isDark),
                                ),
                              ),
                              SizedBox(height: 16.h),
                              AreaPrimaryButton(
                                label: 'alerts_retry'.tr(),
                                accentColor: AppColors.primary,
                                icon: Symbols.refresh,
                                onPressed: _loadLogistics,
                              ),
                            ],
                          ),
                        ),
                      )
                    : AppScrollFadeOverlay(
                        showTop: false,
                        backgroundColor: bg,
                        topExtent: topPad,
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadLogistics,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                                16.w, topPad, 16.w, 40.h),
                            children: [
                              _buildStatsRow(isDark),
                              SizedBox(height: 20.h),
                              _buildHotelsSection(isDark),
                              SizedBox(height: 20.h),
                              _buildInsuranceSection(isDark),
                            ],
                          ),
                        ),
                      ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildFloatingNav(isDark),
          ),
        ],
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
            label: 'logistics_hotels_whitelisted'.tr(),
            value: '$_hotelsCount',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.door_open,
            label: 'logistics_active_room_units'.tr(),
            value: '$_activeRoomsCount',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.bed,
            label: 'logistics_total_bed_pool'.tr(),
            value: '$_totalBedsPool',
          ),
          SizedBox(width: 8.w),
          _buildStatCard(
            isDark: isDark,
            icon: Symbols.shield,
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
    required String label,
    required String value,
  }) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return Container(
      width: 112.w,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AreaUiTheme.groupedBg(isDark),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AreaUiTheme.divider(isDark), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32.w,
            height: 32.w,
            decoration: BoxDecoration(
              color: AreaUiTheme.typeTint(isDark, AppColors.primary),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 18.w, color: AppColors.primary),
          ),
          SizedBox(height: 10.h),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w500,
              fontSize: 11.sp,
              height: 1.2,
              color: AreaUiTheme.sectionLabel(isDark),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: textPrimary,
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
        AreaSectionLabel(
          isDark: isDark,
          label: 'logistics_hotel_lodging_allocations'.tr(),
        ),
        if (_hotels.isEmpty)
          _buildEmptyCard(
            isDark: isDark,
            icon: Symbols.domain_disabled,
            title: 'logistics_no_lodgings_title'.tr(),
            description: 'logistics_no_lodgings_desc'.tr(),
          )
        else
          ..._hotels.map((hotel) => Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: _buildHotelCard(hotel, isDark),
              )),
      ],
    );
  }

  Widget _buildHotelCard(LogisticsHotel hotel, bool isDark) {
    final activeRooms = hotel.rooms.where((r) => r.active).length;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);

    return AreaInsetGroup(
      isDark: isDark,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 10.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.domain, size: 20.w, color: AppColors.primary),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotel.name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Row(
                      children: [
                        Icon(Symbols.pin_drop, size: 14.w, color: muted),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            hotel.city ?? 'logistics_no_city'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AreaUiTheme.typeTint(isDark, AppColors.primary),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  'logistics_active_rooms_badge'.tr(args: ['$activeRooms']),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 11.sp,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hotel.rooms.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
            child: Text(
              'logistics_no_rooms'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          )
        else
          ...hotel.rooms.map((room) => _buildRoomRow(room, isDark)),
      ],
    );
  }

  Widget _buildRoomRow(LogisticsRoom room, bool isDark) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);
    final statusColor =
        room.active ? AppColors.success : AppColors.warning;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      child: Row(
        children: [
          Icon(Symbols.bed, size: 18.w, color: AppColors.primary),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'logistics_room_label'.tr(args: [room.roomNumber]),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w500,
                fontSize: 14.sp,
                color: textPrimary,
              ),
            ),
          ),
          Container(
            width: 7.w,
            height: 7.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            '${room.capacity} ${'logistics_beds'.tr()}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: muted,
            ),
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
        AreaSectionLabel(
          isDark: isDark,
          label: 'logistics_insurance_coverage'.tr(),
        ),
        if (_insurances.isEmpty)
          _buildEmptyCard(
            isDark: isDark,
            icon: Symbols.heart_broken,
            title: 'logistics_no_insurances_assigned'.tr(),
            description: 'logistics_no_insurances_desc'.tr(),
          )
        else
          ..._insurances.map((ins) => Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: _buildInsuranceCard(ins, isDark),
              )),
      ],
    );
  }

  Widget _buildInsuranceCard(LogisticsInsurance ins, bool isDark) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);
    final hasPolicy =
        ins.policyDocumentUrl != null && ins.policyDocumentUrl!.isNotEmpty;

    return AreaInsetGroup(
      isDark: isDark,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 10.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.shield, size: 20.w, color: AppColors.primary),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ins.name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: AreaUiTheme.typeTint(isDark, AppColors.primary),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        'active_policy'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: AreaUiTheme.typeTint(isDark, AppColors.primary),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  'logistics_hospitals_count'
                      .tr(args: ['${ins.hospitals.length}']),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 11.sp,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasPolicy)
          AreaInsetValueRow(
            isDark: isDark,
            icon: Symbols.picture_as_pdf,
            iconColor: AppColors.primary,
            label: 'view_policy'.tr(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentViewerScreen(
                    url: ins.policyDocumentProxyUrl!,
                    title: ins.name,
                  ),
                ),
              );
            },
          ),
        if (ins.hospitals.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
            child: Text(
              'logistics_no_hospitals'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          )
        else
          ...ins.hospitals.map((hosp) => _buildHospitalRow(hosp, isDark)),
      ],
    );
  }

  Widget _buildHospitalRow(LogisticsInsuranceHospital hosp, bool isDark) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.local_hospital, size: 18.w, color: AppColors.primary),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hosp.name,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w500,
                    fontSize: 14.sp,
                    color: textPrimary,
                  ),
                ),
                if (hosp.address != null && hosp.address!.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(
                    hosp.address!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: muted,
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
    final muted = AreaUiTheme.sectionLabel(isDark);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return AreaInsetGroup(
      isDark: isDark,
      children: [
        Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32.w, color: muted),
              SizedBox(height: 10.h),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 15.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


