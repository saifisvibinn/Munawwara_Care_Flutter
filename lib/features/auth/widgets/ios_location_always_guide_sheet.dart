import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

/// In-app preview of Settings → Location → **Always** (Apple does not allow
/// highlighting controls inside the real Settings app).
Future<bool> showIosLocationAlwaysGuide(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final openSettings = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _IosLocationAlwaysGuideSheet(isDark: isDark),
  );
  return openSettings == true;
}

class _IosLocationAlwaysGuideSheet extends StatefulWidget {
  const _IosLocationAlwaysGuideSheet({required this.isDark});

  final bool isDark;

  @override
  State<_IosLocationAlwaysGuideSheet> createState() =>
      _IosLocationAlwaysGuideSheetState();
}

class _IosLocationAlwaysGuideSheetState extends State<_IosLocationAlwaysGuideSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.isDark ? AppColors.surfaceDark : Colors.white;
    final titleColor = widget.isDark ? Colors.white : AppColors.textDark;
    final muted = widget.isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: muted.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Text(
                  'ios_setup_location_guide_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'ios_setup_location_guide_instruction'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    height: 1.45,
                    color: muted,
                  ),
                ),
                SizedBox(height: 18.h),
                _MockLocationSettingsPanel(
                  isDark: widget.isDark,
                  pulse: _pulseController,
                ),
                SizedBox(height: 20.h),
                SizedBox(
                  height: 50.h,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icon(Symbols.open_in_new, size: 20.sp),
                    label: Text(
                      'ios_setup_location_guide_open'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'device_care_guide_cancel'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MockLocationSettingsPanel extends StatelessWidget {
  const _MockLocationSettingsPanel({
    required this.isDark,
    required this.pulse,
  });

  final bool isDark;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final panelBg =
        isDark ? AppColors.backgroundDark : const Color(0xFFF3F4F6);
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'device_care_guide_preview_header'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: muted,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 8.h),
          _LocationOptionRow(
            label: 'ios_setup_location_option_never'.tr(),
            isDark: isDark,
            highlighted: false,
            pulse: pulse,
          ),
          _LocationOptionRow(
            label: 'ios_setup_location_option_while_using'.tr(),
            isDark: isDark,
            highlighted: false,
            pulse: pulse,
          ),
          _LocationOptionRow(
            label: 'ios_setup_location_option_always'.tr(),
            isDark: isDark,
            highlighted: true,
            pulse: pulse,
            showTapBadge: true,
          ),
        ],
      ),
    );
  }
}

class _LocationOptionRow extends StatelessWidget {
  const _LocationOptionRow({
    required this.label,
    required this.isDark,
    required this.highlighted,
    required this.pulse,
    this.showTapBadge = false,
  });

  final String label;
  final bool isDark;
  final bool highlighted;
  final Animation<double> pulse;
  final bool showTapBadge;

  @override
  Widget build(BuildContext context) {
    final rowBg = highlighted
        ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.1)
        : (isDark ? AppColors.surfaceDark : Colors.white);
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    Widget row = Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: rowBg,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: highlighted
              ? AppColors.primary
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            highlighted ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
            size: 22.w,
            color: highlighted ? AppColors.primary : muted,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: highlighted ? 14.sp : 13.sp,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                color: highlighted ? AppColors.primary : muted,
              ),
            ),
          ),
          if (showTapBadge)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'device_care_guide_tap_here'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );

    if (!highlighted) return row;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final glow = 0.25 + (pulse.value * 0.2);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: glow),
                blurRadius: 14 + pulse.value * 6,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: row,
    );
  }
}
