import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

class GroupDetailsScreen extends StatelessWidget {
  final String? moderatorName;
  final double? moderatorLat;
  final double? moderatorLng;

  const GroupDetailsScreen({
    super.key,
    this.moderatorName,
    this.moderatorLat,
    this.moderatorLng,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xfff1f5f3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        title: Text(
          'Group Details',
          style: TextStyle(
            fontFamily: GoogleFonts.poppins().fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
        children: [
          SizedBox(height: 6.h),
          _SectionCard(
            isDark: isDark,
            title: 'Hotel Information',
            icon: Symbols.hotel,
            tint: const Color(0xFFF3ECE0),
            iconTint: const Color(0xFFDCECF9),
            children: const [
              _SectionLine(
                label: 'Hotel Name',
                value: 'To be added by moderator',
              ),
              _SectionLine(
                label: 'Room Number',
                value: 'To be added by moderator',
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _SectionCard(
            isDark: isDark,
            title: 'Moderator Section',
            icon: Symbols.location_on,
            tint: const Color(0xFFEAF6ED),
            iconTint: const Color(0xFFCFEBD7),
            children: [
              _SectionLine(
                label: 'Moderator Name',
                value: moderatorName?.isNotEmpty == true
                    ? moderatorName!
                    : 'To be added by moderator',
              ),
              if (_hasModeratorLocation) ...[
                _SectionLine(
                  label: 'Current Location',
                  value:
                      '${moderatorLat!.toStringAsFixed(5)}, ${moderatorLng!.toStringAsFixed(5)}',
                ),
                SizedBox(height: 8.h),
                GestureDetector(
                  onTap: _openModeratorLocation,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 10.h),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7DB8E3), Color(0xFF72AFDA)],
                      ),
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Text(
                      'View on Map',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: GoogleFonts.poppins().fontFamily,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 12.h),
          _SectionCard(
            isDark: isDark,
            title: 'Transportation Details',
            icon: Symbols.directions_bus,
            tint: const Color(0xFFF8F1D9),
            iconTint: const Color(0xFFF2E4AE),
            children: const [
              _SectionLine(
                label: 'Bus Number',
                value: 'To be added by moderator',
              ),
              _SectionLine(
                label: 'Driver\'s Name',
                value: 'To be added by moderator',
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _SectionCard(
            isDark: isDark,
            title: 'Stay Duration',
            icon: Symbols.calendar_month,
            tint: const Color(0xFFE3F0FB),
            iconTint: const Color(0xFFC5E1F8),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StayColumn(
                      title: 'Check-in',
                      value: 'To be added',
                      alignStart: true,
                    ),
                  ),
                  Expanded(
                    child: _StayColumn(
                      title: 'Total Days Remaining',
                      value: '--',
                    ),
                  ),
                  Expanded(
                    child: _StayColumn(
                      title: 'Check-out',
                      value: 'To be added',
                      alignStart: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color tint;
  final Color iconTint;
  final List<Widget> children;

  const _SectionCard({
    required this.isDark,
    required this.title,
    required this.icon,
    required this.tint,
    required this.iconTint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 14.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : tint,
        borderRadius: BorderRadius.circular(22.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.iconBgDark : iconTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22.w, color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: GoogleFonts.poppins().fontFamily,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          ...children,
        ],
      ),
    );
  }
}

class _SectionLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SectionLine({
    this.icon = Symbols.circle,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: GoogleFonts.poppins().fontFamily,
            fontSize: 14.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
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
            fontFamily: GoogleFonts.poppins().fontFamily,
            fontSize: 11.sp,
            color: AppColors.textMutedLight,
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
            fontFamily: GoogleFonts.poppins().fontFamily,
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
