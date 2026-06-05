import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../helpers/moderator_navigation.dart';
import '../providers/pilgrim_provider.dart';
import '../widgets/moderator_navigate_button.dart';
import '../../auth/models/wakel_info.dart';

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
  double? hotelLatitude,
  double? hotelLongitude,
  String? hotelAddress,
  WakelInfo? wakelInfo,
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
                  hotelLatitude: hotelLatitude,
                  hotelLongitude: hotelLongitude,
                  hotelAddress: hotelAddress,
                  wakelInfo: wakelInfo,
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
  final double? hotelLatitude;
  final double? hotelLongitude;
  final String? hotelAddress;
  final WakelInfo? wakelInfo;

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
    this.hotelLatitude,
    this.hotelLongitude,
    this.hotelAddress,
    this.wakelInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noRecordsText = 'no_records_available'.tr();
    final hotelText = hotelName?.trim().isNotEmpty == true ? hotelName! : noRecordsText;
    final checkInText = checkIn?.trim().isNotEmpty == true ? checkIn! : '—';
    final checkOutText = checkOut?.trim().isNotEmpty == true ? checkOut! : '—';

    // Theme values for colored cards
    final modBg = isDark ? AppColors.surfaceDark : Colors.white;
    final modTitle = isDark ? Colors.white70 : AppColors.textDark;
    final modText = isDark ? Colors.white : AppColors.textDark;
    final modAvatarBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Card 1: Moderators Section ───────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel(
              label: 'group_moderators'.tr().toUpperCase(),
              textMuted: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFEBE6FF),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                "${moderators.length + (wakelInfo != null ? 1 : 0)} ASSIGNED",
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF8C73FF) : const Color(0xFF5B3EFF),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
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
          wakelInfo: wakelInfo,
        ),
        SizedBox(height: 20.h),

        // ── Card 2: Hotel Information Section ────────────────────────────────
        _SectionLabel(
          label: 'group_hotel_info'.tr().toUpperCase(),
          textMuted: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
        ),
        SizedBox(height: 8.h),
        Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.hotel_rounded,
                      color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      size: 22.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hotelText,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          hotelAddress ?? "Madinah Central Area, Saudi Arabia",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                        if (hotelLatitude != null && hotelLongitude != null) ...[
                          SizedBox(height: 8.h),
                          ElevatedButton.icon(
                            onPressed: () => launchModeratorWalkingDirections(
                              lat: hotelLatitude!,
                              lng: hotelLongitude!,
                            ),
                            icon: Icon(
                              Icons.near_me_rounded,
                              size: 14.sp,
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            ),
                            label: Text(
                              "Navigate",
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE),
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20.r),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "CHECK IN",
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 9.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            checkInText,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "CHECK OUT",
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 9.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            checkOutText,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

            ],
          ),
        ),
        SizedBox(height: 20.h),

        // ── Card 4: Stay Duration Section ────────────────────────────────────
        _SectionLabel(
          label: 'group_stay_duration'.tr().toUpperCase(),
          textMuted: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
        ),
        SizedBox(height: 8.h),
        Builder(
          builder: (context) {
            int totalDays = 0;
            int? dynamicDaysRemaining;
            if (checkIn != null && checkOut != null) {
              try {
                final inDate = DateTime.parse(checkIn!);
                final outDate = DateTime.parse(checkOut!);
                
                final now = DateTime.now();
                final todayMidnight = DateTime(now.year, now.month, now.day);
                final inMidnight = DateTime(inDate.year, inDate.month, inDate.day);
                final outMidnight = DateTime(outDate.year, outDate.month, outDate.day);
                
                totalDays = outMidnight.difference(inMidnight).inDays;
                
                if (todayMidnight.isBefore(inMidnight)) {
                  dynamicDaysRemaining = totalDays;
                } else if (todayMidnight.isAfter(outMidnight)) {
                  dynamicDaysRemaining = 0;
                } else {
                  dynamicDaysRemaining = outMidnight.difference(todayMidnight).inDays;
                }
              } catch (_) {}
            }
            
            final finalDaysRemaining = dynamicDaysRemaining ?? daysRemaining;
            final localDaysRemainingText = finalDaysRemaining != null ? finalDaysRemaining.toString() : '—';
            
            double progressVal = 0.0;
            if (totalDays > 0 && finalDaysRemaining != null) {
              progressVal = ((totalDays - finalDaysRemaining) / totalDays).clamp(0.0, 1.0);
            }

            return Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Days left
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          localDaysRemainingText,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          "DAYS LEFT",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Progress bar
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4.r),
                        child: LinearProgressIndicator(
                          value: progressVal,
                          backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                          color: const Color(0xFF92600A),
                          minHeight: 8.h,
                        ),
                      ),
                    ),
                  ),
                  // Total days
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          totalDays > 0 ? totalDays.toString() : "—",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          "TOTAL",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white54 : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}


class _GroupModeratorsCard extends StatefulWidget {
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
    this.wakelInfo,
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
  final WakelInfo? wakelInfo;

  @override
  State<_GroupModeratorsCard> createState() => _GroupModeratorsCardState();
}

class _GroupModeratorsCardState extends State<_GroupModeratorsCard> {
  String? _copiedModId;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copyPhoneNumber(String modId, String phoneNumber) {
    Clipboard.setData(ClipboardData(text: phoneNumber));
    _timer?.cancel();
    setState(() {
      _copiedModId = modId;
    });
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copiedModId = null;
        });
      }
    });
  }

  Widget _buildWakelPlaceholder() {
    return Center(
      child: Icon(
        Icons.explore_rounded,
        color: const Color(0xFF0F3A5F),
        size: 20.w,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noRecordsText = 'no_records_available'.tr();
    final sorted = sortedGroupModerators(widget.moderators, createdBy: widget.createdBy);

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: widget.modBg,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: widget.isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.25 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.wakelInfo == null && sorted.isEmpty)
            Text(
              noRecordsText,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: widget.isDark ? Colors.white70 : AppColors.textMutedDark,
              ),
            )
          else ...[
            if (widget.wakelInfo != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isDark ? Colors.white24 : Colors.black12,
                        width: 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: widget.wakelInfo!.profilePicture != null &&
                            widget.wakelInfo!.profilePicture!.isNotEmpty
                        ? Image.network(
                            widget.wakelInfo!.profilePicture!,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, stack) => _buildWakelPlaceholder(),
                          )
                        : _buildWakelPlaceholder(),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.wakelInfo!.name,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w800,
                            color: widget.modText,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          "Administrative Coordinator",
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: widget.isDark ? Colors.white70 : const Color(0xFF64748B),
                          ),
                        ),
                        if (widget.wakelInfo!.contactNumber.trim().isNotEmpty) ...[
                          SizedBox(height: 6.h),
                          GestureDetector(
                            onTap: () => _copyPhoneNumber(
                              widget.wakelInfo!.id,
                              widget.wakelInfo!.contactNumber,
                            ),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Symbols.call,
                                  size: 13.w,
                                  color: widget.isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  widget.wakelInfo!.contactNumber,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                    color: widget.modText.withValues(alpha: 0.85),
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    _copiedModId == widget.wakelInfo!.id ? Icons.check_rounded : Symbols.content_copy,
                                    key: ValueKey<bool>(_copiedModId == widget.wakelInfo!.id),
                                    size: 11.w,
                                    color: _copiedModId == widget.wakelInfo!.id
                                        ? AppColors.primary
                                        : widget.modText.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF8C73FF).withValues(alpha: 0.15)
                          : const Color(0xFFEBE6FF),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      "AGENCY",
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: widget.isDark ? const Color(0xFFB3A3FF) : const Color(0xFF5B3EFF),
                      ),
                    ),
                  ),
                ],
              ),
              if (sorted.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: widget.isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
            ],
            ...sorted.asMap().entries.map((entry) {
              final index = entry.key;
              final mod = entry.value;
              final isCreator = isGroupLeaderModerator(
                moderatorId: mod.id,
                createdBy: widget.createdBy,
              );
              final beacon = widget.navBeacons[mod.id];
              final distance = distanceToModerator(
                from: widget.pilgrimLocation,
                moderator: mod,
                navBeacons: widget.navBeacons,
              );
              final initial = mod.fullName.isNotEmpty
                  ? mod.fullName[0].toUpperCase()
                  : '?';
              final isCopied = _copiedModId == mod.id;

              return Column(
                children: [
                  if (index > 0)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: widget.isDark ? Colors.white12 : Colors.black12,
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18.r,
                        backgroundColor: widget.modAvatarBg,
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w800,
                            fontSize: 13.sp,
                            color: widget.isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
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
                                color: widget.modText,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                _ModeratorRoleChip(
                                  isCreator: isCreator,
                                  isDark: widget.isDark,
                                ),
                                if (distance != null) ...[
                                  SizedBox(width: 6.w),
                                  Text(
                                    distance,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 11.sp,
                                      color: widget.isDark
                                          ? Colors.white60
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (mod.phoneNumber != null &&
                                mod.phoneNumber!.trim().isNotEmpty) ...[
                              SizedBox(height: 6.h),
                              GestureDetector(
                                onTap: () => _copyPhoneNumber(mod.id, mod.phoneNumber!),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Symbols.call,
                                      size: 13.w,
                                      color: widget.isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
                                    ),
                                    SizedBox(width: 6.w),
                                    Text(
                                      mod.phoneNumber!,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        color: widget.modText.withValues(alpha: 0.85),
                                      ),
                                    ),
                                    SizedBox(width: 6.w),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Icon(
                                        isCopied ? Icons.check_rounded : Symbols.content_copy,
                                        key: ValueKey<bool>(isCopied),
                                        size: 11.w,
                                        color: isCopied
                                            ? AppColors.primary
                                            : widget.modText.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.textMuted});
  final String label;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w600,
          fontSize: 11.sp,
          letterSpacing: 1.2,
          color: textMuted,
        ),
      ),
    );
  }
}
