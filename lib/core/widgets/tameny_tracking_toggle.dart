import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../providers/theme_provider.dart';
import '../services/tameny_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class TamenyTrackingToggle extends ConsumerStatefulWidget {
  const TamenyTrackingToggle({super.key});

  @override
  ConsumerState<TamenyTrackingToggle> createState() =>
      _TamenyTrackingToggleState();
}

class _TamenyTrackingToggleState extends ConsumerState<TamenyTrackingToggle> {
  bool _isEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await TamenyLocationService.isEnabled();
    if (!mounted) return;
    setState(() {
      _isEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _handleToggle(bool value) async {
    setState(() => _isLoading = true);

    if (value) {
      final success = await TamenyLocationService.enableTracking(context);
      if (!mounted) return;
      setState(() {
        _isEnabled = success;
        _isLoading = false;
      });
    } else {
      await TamenyLocationService.disableTracking();
      if (!mounted) return;
      setState(() {
        _isEnabled = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = AppTheme.isDarkEffective(themeMode, context);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: _isEnabled
              ? AppColors.success.withValues(alpha: isDark ? 0.45 : 0.35)
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: _isEnabled
                        ? AppColors.success.withValues(
                            alpha: isDark ? 0.22 : 0.12,
                          )
                        : (isDark
                            ? AppColors.iconBgDark
                            : AppColors.primary.withValues(alpha: 0.12)),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    _isEnabled ? Symbols.my_location : Symbols.location_off,
                    color: _isEnabled ? AppColors.success : AppColors.primary,
                    size: 20.sp,
                    fill: _isEnabled ? 1 : 0,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'tameny_toggle_title'.tr(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.sp,
                          color: textPrimary,
                        ),
                      ),
                      if (!_isEnabled) ...[
                        SizedBox(height: 2.h),
                        Text(
                          'tameny_toggle_desc_disabled'.tr(),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isLoading)
                  SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Switch(
                    value: _isEnabled,
                    onChanged: _handleToggle,
                    activeThumbColor: AppColors.success,
                    activeTrackColor: AppColors.success.withValues(alpha: 0.35),
                    inactiveThumbColor:
                        isDark ? AppColors.textLight : Colors.grey.shade100,
                    inactiveTrackColor: isDark
                        ? AppColors.dividerDark
                        : Colors.grey.shade300,
                  ),
              ],
            ),
            if (_isEnabled) ...[
              SizedBox(height: 12.h),
              _LocationStatusBanner(
                message: 'tameny_toggle_desc_enabled'.tr(),
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationStatusBanner extends StatelessWidget {
  final String message;
  final bool isDark;

  const _LocationStatusBanner({
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.success.withValues(alpha: isDark ? 0.35 : 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.check_circle,
            color: AppColors.success,
            size: 18.sp,
            fill: 1,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF6EE7B7)
                    : const Color(0xFF047857),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
