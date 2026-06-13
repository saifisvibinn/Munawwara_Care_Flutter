import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/oem_settings_service.dart';
import '../../../core/theme/app_colors.dart';

/// Shows what to tap in system settings, then opens the real settings screen.
/// Returns `true` if settings were opened.
Future<bool> showDeviceCareSettingsGuide(
  BuildContext context, {
  required DeviceCareActionKind kind,
  required DeviceOemProfile profile,
}) async {
  final guide = OemSettingsService.settingsGuideFor(
    kind: kind,
    profile: profile,
  );
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final openSettings = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DeviceCareSettingsGuideSheet(
      guide: guide,
      isDark: isDark,
    ),
  );

  if (openSettings == true && context.mounted) {
    // Let the bottom sheet finish closing before launching Settings.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!context.mounted) return false;
    await OemSettingsService.openStepAction(kind, context: context);
    return true;
  }
  return false;
}

class _DeviceCareSettingsGuideSheet extends StatefulWidget {
  const _DeviceCareSettingsGuideSheet({
    required this.guide,
    required this.isDark,
  });

  final DeviceCareSettingsGuide guide;
  final bool isDark;

  @override
  State<_DeviceCareSettingsGuideSheet> createState() =>
      _DeviceCareSettingsGuideSheetState();
}

class _DeviceCareSettingsGuideSheetState
    extends State<_DeviceCareSettingsGuideSheet>
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  widget.guide.titleKey.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  widget.guide.instructionKey.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.sp,
                    height: 1.45,
                    color: muted,
                  ),
                ),
                SizedBox(height: 18.h),
                _MockSettingsPanel(
                  guide: widget.guide,
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
                      'device_care_guide_open_settings'.tr(),
                      style: TextStyle(
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

class _MockSettingsPanel extends StatelessWidget {
  const _MockSettingsPanel({
    required this.guide,
    required this.isDark,
    required this.pulse,
  });

  final DeviceCareSettingsGuide guide;
  final bool isDark;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    final panelBg = isDark
        ? AppColors.backgroundDark
        : const Color(0xFFF3F4F6);
    final rows = <Widget>[
      for (final key in guide.decoyLabelKeys)
        _MockSettingsRow(
          label: key.tr(),
          isDark: isDark,
          highlighted: false,
          pulse: pulse,
        ),
      _MockSettingsRow(
        label: guide.highlightLabelKey.tr(),
        isDark: isDark,
        highlighted: true,
        pulse: pulse,
        appName: 'device_care_app_name'.tr(),
      ),
    ];

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
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textMutedLight
                  : AppColors.textMutedDark,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: 8.h),
          ...rows,
        ],
      ),
    );
  }
}

class _MockSettingsRow extends StatelessWidget {
  const _MockSettingsRow({
    required this.label,
    required this.isDark,
    required this.highlighted,
    required this.pulse,
    this.appName,
  });

  final String label;
  final bool isDark;
  final bool highlighted;
  final Animation<double> pulse;
  final String? appName;

  @override
  Widget build(BuildContext context) {
    final rowBg = highlighted
        ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.1)
        : (isDark ? AppColors.surfaceDark : Colors.white);
    final textColor = isDark ? Colors.white : AppColors.textDark;
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
          if (highlighted) ...[
            Icon(
              Symbols.touch_app,
              size: 22.w,
              color: AppColors.primary,
            ),
            SizedBox(width: 10.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (appName != null && highlighted) ...[
                  Text(
                    appName!,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: 2.h),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: highlighted ? 14.sp : 13.sp,
                    fontWeight:
                        highlighted ? FontWeight.w700 : FontWeight.w500,
                    color: highlighted ? AppColors.primary : muted,
                  ),
                ),
              ],
            ),
          ),
          if (highlighted)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'device_care_guide_tap_here'.tr(),
                style: TextStyle(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            )
          else
            Icon(
              Symbols.chevron_right,
              size: 20.w,
              color: muted.withValues(alpha: 0.5),
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
