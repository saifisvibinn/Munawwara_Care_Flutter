import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Group details — bottom sheet (same pattern as weather detail sheet)
// ─────────────────────────────────────────────────────────────────────────────

void showGroupDetailsBottomSheet(
  BuildContext context, {
  required String groupName,
  required int pilgrimCount,
  required List<String> moderatorInitials,
  String? moderatorName,
  double? moderatorLat,
  double? moderatorLng,
  String? distanceStr,
  String? hotelName,
  String? roomNumber,
  String? busNumber,
  String? driverName,
  String? checkIn,
  String? checkOut,
  int? daysRemaining,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xFFFFF7ED),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 20.h),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pull indicator handle
              Center(
                child: Container(
                  width: 36.w,
                  height: 4.h,
                  margin: EdgeInsets.only(bottom: 16.h),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white30 : Colors.black12,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              // Header Row: Title and X Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'group_details_title'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? Colors.white.withValues(alpha: 0.1) 
                            : Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18.w,
                        color: isDark ? Colors.white70 : AppColors.textMutedDark,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18.h),
              _GroupDetailsBody(
                groupName: groupName,
                pilgrimCount: pilgrimCount,
                moderatorInitials: moderatorInitials,
                moderatorName: moderatorName,
                moderatorLat: moderatorLat,
                moderatorLng: moderatorLng,
                distanceStr: distanceStr,
                hotelName: hotelName,
                roomNumber: roomNumber,
                busNumber: busNumber,
                driverName: driverName,
                checkIn: checkIn,
                checkOut: checkOut,
                daysRemaining: daysRemaining,
              ),
              SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8.h),
            ],
          ),
        ),
      );
    },
  );
}

class _GroupDetailsBody extends StatelessWidget {
  final String groupName;
  final int pilgrimCount;
  final List<String> moderatorInitials;
  final String? moderatorName;
  final double? moderatorLat;
  final double? moderatorLng;
  final String? distanceStr;
  final String? hotelName;
  final String? roomNumber;
  final String? busNumber;
  final String? driverName;
  final String? checkIn;
  final String? checkOut;
  final int? daysRemaining;

  const _GroupDetailsBody({
    required this.groupName,
    required this.pilgrimCount,
    required this.moderatorInitials,
    this.moderatorName,
    this.moderatorLat,
    this.moderatorLng,
    this.distanceStr,
    this.hotelName,
    this.roomNumber,
    this.busNumber,
    this.driverName,
    this.checkIn,
    this.checkOut,
    this.daysRemaining,
  });

  bool get _hasModeratorLocation =>
      moderatorLat != null && moderatorLng != null;

  Future<void> _openModeratorLocation() async {
    if (!_hasModeratorLocation) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$moderatorLat,$moderatorLng&travelmode=walking',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildAvatarCircles(List<String> initials, int totalCount) {
    final List<Widget> list = [];
    // Draw first 2 moderator initials
    for (int i = 0; i < initials.length && i < 2; i++) {
      list.add(
        Container(
          width: 26.w,
          height: 26.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFF97316), // Premium Orange
            shape: BoxShape.circle,
          ),
          child: Text(
            initials[i],
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    // Draw +N remaining members circle
    final remaining = totalCount - initials.length;
    if (remaining > 0) {
      if (initials.isNotEmpty) {
        list.add(SizedBox(width: 2.w));
      }
      list.add(
        Container(
          width: 26.w,
          height: 26.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF2E3E5C), // Premium Deep Blue
            shape: BoxShape.circle,
          ),
          child: Text(
            '+$remaining',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noRecordsText = 'no_records_available'.tr();
    final hotelText = hotelName?.trim().isNotEmpty == true ? hotelName! : noRecordsText;
    final roomText = roomNumber?.trim().isNotEmpty == true ? roomNumber! : noRecordsText;
    final busText = busNumber?.trim().isNotEmpty == true ? busNumber! : noRecordsText;
    final driverText = driverName?.trim().isNotEmpty == true ? driverName! : noRecordsText;
    final checkInText = checkIn?.trim().isNotEmpty == true ? checkIn! : '—';
    final checkOutText = checkOut?.trim().isNotEmpty == true ? checkOut! : '—';
    final daysRemainingText = daysRemaining != null ? daysRemaining.toString() : '—';

    // Theme values for colored cards
    final modBg = isDark ? const Color(0xFF13251A) : const Color(0xFFEAF6ED);
    final modTitle = isDark ? const Color(0xFF8CE3A3) : const Color(0xFF2D6A4F);
    final modText = isDark ? Colors.white : const Color(0xFF1B4332);
    final modAvatarBg = isDark ? const Color(0xFF1B3B2B) : const Color(0xFFD8F3DC);

    final hotelBg = isDark ? const Color(0xFF112233) : const Color(0xFFE5F2FF);
    final hotelTitle = isDark ? const Color(0xFF8CC5FF) : const Color(0xFF1A5F7A);
    final hotelTextCol = isDark ? Colors.white : const Color(0xFF1A365D);
    final hotelAvatarBg = isDark ? const Color(0xFF1A3355) : const Color(0xFFCCE4FF);

    final transportBg = isDark ? const Color(0xFF2D2214) : const Color(0xFFFFF2E5);
    final transportTitle = isDark ? const Color(0xFFFFD1A9) : const Color(0xFFB05C1A);
    final transportTextCol = isDark ? Colors.white : const Color(0xFF5C2D12);
    final transportAvatarBg = isDark ? const Color(0xFF402E1D) : const Color(0xFFFFE6D5);

    final stayBg = isDark ? const Color(0xFF2E1719) : const Color(0xFFFFEBEA);
    final stayTitle = isDark ? const Color(0xFFFF9EA6) : const Color(0xFFC0392B);
    final stayAvatarBg = isDark ? const Color(0xFF4A2326) : const Color(0xFFFFD1CF);

    final labelStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 12.sp,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white60 : Colors.black45,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Active Group Header Card ─────────────────────────────────────────
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1D2641), // Matching mockup dark blue
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE GROUP',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFF97316),
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    groupName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              _buildAvatarCircles(moderatorInitials, pilgrimCount),
            ],
          ),
        ),
        SizedBox(height: 14.h),

        // ── Card 1: Moderator Card ───────────────────────────────────────────
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: modBg,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isDark ? const Color(0xFF1B3D2B) : const Color(0xFFD0ECDA),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: modAvatarBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.person,
                  size: 22.w,
                  color: modTitle,
                  fill: 1,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'group_moderator_section'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: modTitle,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      moderatorName?.isNotEmpty == true ? moderatorName! : noRecordsText,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: modText,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      distanceStr?.isNotEmpty == true
                          ? '$distanceStr · Group leader'
                          : 'Group leader',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasModeratorLocation)
                GestureDetector(
                  onTap: _openModeratorLocation,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316),
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF97316).withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Symbols.navigation,
                          color: Colors.white,
                          size: 14,
                          fill: 1,
                        ),
                        SizedBox(width: 4.w),
                        Text(
                          'nav_go'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 12.h),

        // ── Card 2: Hotel Information Card ───────────────────────────────────
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: hotelBg,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isDark ? const Color(0xFF1E354F) : const Color(0xFFD6E9FF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: hotelAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.hotel,
                      size: 20.w,
                      color: hotelTitle,
                      fill: 1,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    'group_hotel_info'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: hotelTitle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('group_hotel_name'.tr(), style: labelStyle),
                  Text(
                    hotelText,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: hotelTextCol,
                      fontStyle: hotelName?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('group_room_number'.tr(), style: labelStyle),
                  Text(
                    roomText,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: hotelTextCol,
                      fontStyle: roomNumber?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),

        // ── Card 3: Transportation Card ──────────────────────────────────────
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: transportBg,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isDark ? const Color(0xFF3F3221) : const Color(0xFFFFECCE),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: transportAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.directions_bus,
                      size: 20.w,
                      color: transportTitle,
                      fill: 1,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    'group_transport_details'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: transportTitle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('group_bus_number'.tr(), style: labelStyle),
                  Text(
                    busText,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: transportTextCol,
                      fontStyle: busNumber?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('group_driver_name'.tr(), style: labelStyle),
                  Text(
                    driverText,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: transportTextCol,
                      fontStyle: driverName?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),

        // ── Card 4: Stay Duration Card ───────────────────────────────────────
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: stayBg,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isDark ? const Color(0xFF432224) : const Color(0xFFFFDBDA),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: stayAvatarBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.calendar_today,
                      size: 20.w,
                      color: stayTitle,
                      fill: 1,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    'group_stay_duration'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: stayTitle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              // Horizontal stay columns grid
              Row(
                children: [
                  Expanded(
                    child: _StayColumn(
                      title: 'group_checkin'.tr(),
                      value: checkInText,
                      alignStart: true,
                    ),
                  ),
                  Expanded(
                    child: _StayColumn(
                      title: 'group_days_remaining'.tr(),
                      value: daysRemainingText,
                    ),
                  ),
                  Expanded(
                    child: _StayColumn(
                      title: 'group_checkout'.tr(),
                      value: checkOutText,
                      alignStart: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StayColumn extends StatelessWidget {
  final String title;
  final String value;
  final bool? alignStart;

  const _StayColumn({
    required this.title,
    required this.value,
    this.alignStart,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alignment = alignStart == null
        ? CrossAxisAlignment.center
        : (alignStart! ? CrossAxisAlignment.start : CrossAxisAlignment.end);
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11.sp,
            color: isDark ? Colors.white54 : Colors.black45,
            fontWeight: FontWeight.w600,
          ),
          textAlign: alignStart == null
              ? TextAlign.center
              : (alignStart! ? TextAlign.left : TextAlign.right),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 15.sp,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          textAlign: alignStart == null
              ? TextAlign.center
              : (alignStart! ? TextAlign.left : TextAlign.right),
        ),
      ],
    );
  }
}
