import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../helpers/moderator_navigation.dart';
import '../providers/pilgrim_provider.dart';
import '../widgets/moderator_navigate_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Group details — bottom sheet (same pattern as weather detail sheet)
// ─────────────────────────────────────────────────────────────────────────────

void showGroupDetailsBottomSheet(
  BuildContext context, {
  required List<ModeratorInfo> moderators,
  String? createdBy,
  Map<String, ModeratorBeacon> navBeacons = const {},
  LatLng? pilgrimLocation,
  String? hotelName,
  String? roomNumber,
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
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        snap: true,
        snapSizes: const [0.35, 0.78, 0.92],
        builder: (context, scrollController) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.backgroundDark
                  : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28.r),
              ),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 20.h),
              children: [
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
                          color: isDark
                              ? Colors.white70
                              : AppColors.textMutedDark,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18.h),
                _GroupDetailsBody(
                  moderators: moderators,
                  createdBy: createdBy,
                  navBeacons: navBeacons,
                  pilgrimLocation: pilgrimLocation,
                  hotelName: hotelName,
                  roomNumber: roomNumber,
                  checkIn: checkIn,
                  checkOut: checkOut,
                  daysRemaining: daysRemaining,
                ),
                SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8.h),
              ],
            ),
          );
        },
      );
    },
  );
}

class _GroupDetailsBody extends StatelessWidget {
  final List<ModeratorInfo> moderators;
  final String? createdBy;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? pilgrimLocation;
  final String? hotelName;
  final String? roomNumber;
  final String? checkIn;
  final String? checkOut;
  final int? daysRemaining;

  const _GroupDetailsBody({
    required this.moderators,
    this.createdBy,
    this.navBeacons = const {},
    this.pilgrimLocation,
    this.hotelName,
    this.roomNumber,
    this.checkIn,
    this.checkOut,
    this.daysRemaining,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noRecordsText = 'no_records_available'.tr();
    final hotelText = hotelName?.trim().isNotEmpty == true ? hotelName! : noRecordsText;
    final roomText = roomNumber?.trim().isNotEmpty == true ? roomNumber! : noRecordsText;
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
        // ── Card 1: Moderators ───────────────────────────────────────────────
        _GroupModeratorsCard(
          moderators: moderators,
          createdBy: createdBy,
          navBeacons: navBeacons,
          pilgrimLocation: pilgrimLocation,
          modBg: modBg,
          modTitle: modTitle,
          modText: modText,
          modAvatarBg: modAvatarBg,
          isDark: isDark,
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

class _GroupModeratorsCard extends StatelessWidget {
  const _GroupModeratorsCard({
    required this.moderators,
    required this.createdBy,
    required this.navBeacons,
    required this.pilgrimLocation,
    required this.modBg,
    required this.modTitle,
    required this.modText,
    required this.modAvatarBg,
    required this.isDark,
  });

  final List<ModeratorInfo> moderators;
  final String? createdBy;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? pilgrimLocation;
  final Color modBg;
  final Color modTitle;
  final Color modText;
  final Color modAvatarBg;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final noRecordsText = 'no_records_available'.tr();
    final sorted = sortedGroupModerators(moderators, createdBy: createdBy);

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: modBg,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? const Color(0xFF1B3D2B) : const Color(0xFFD0ECDA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: modAvatarBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.group,
                  size: 20.w,
                  color: modTitle,
                  fill: 1,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                'group_moderators'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: modTitle,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          if (sorted.isEmpty)
            Text(
              noRecordsText,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: isDark ? Colors.white70 : AppColors.textMutedDark,
              ),
            )
          else
            ...sorted.asMap().entries.map((entry) {
              final index = entry.key;
              final mod = entry.value;
              final isCreator = isGroupLeaderModerator(
                moderatorId: mod.id,
                createdBy: createdBy,
              );
              final beacon = navBeacons[mod.id];
              final distance = distanceToModerator(
                from: pilgrimLocation,
                moderator: mod,
                navBeacons: navBeacons,
              );
              final initial = mod.fullName.isNotEmpty
                  ? mod.fullName[0].toUpperCase()
                  : '?';

              return Column(
                children: [
                  if (index > 0)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Divider(
                        height: 1,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18.r,
                        backgroundColor: modAvatarBg,
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w800,
                            fontSize: 13.sp,
                            color: modTitle,
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mod.fullName,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w800,
                                color: modText,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                _ModeratorRoleChip(
                                  isCreator: isCreator,
                                  isDark: isDark,
                                ),
                                if (distance != null) ...[
                                  SizedBox(width: 6.w),
                                  Text(
                                    distance,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 11.sp,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (beacon != null)
                        ModeratorNavigateButton(
                          compact: true,
                          onTap: () =>
                              launchModeratorBeaconDirections(beacon),
                        ),
                    ],
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class _ModeratorRoleChip extends StatelessWidget {
  const _ModeratorRoleChip({
    required this.isCreator,
    required this.isDark,
  });

  final bool isCreator;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final label = isCreator
        ? 'group_main_moderator'.tr()
        : 'group_co_moderator'.tr();
    final bg = isCreator
        ? const Color(0xFFE8C97A).withValues(alpha: isDark ? 0.25 : 0.35)
        : AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.12);
    final fg = isCreator
        ? (isDark ? const Color(0xFFE8C97A) : const Color(0xFF92600A))
        : AppColors.primaryDark;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
