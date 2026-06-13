import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/location_permission_service.dart';
import '../../../core/services/oem_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

/// iPhone-first setup wizard: location, notifications, Background App Refresh.
class IosDeviceSetupScreen extends ConsumerStatefulWidget {
  const IosDeviceSetupScreen({super.key});

  @override
  ConsumerState<IosDeviceSetupScreen> createState() =>
      _IosDeviceSetupScreenState();
}

class _IosDeviceSetupScreenState extends ConsumerState<IosDeviceSetupScreen>
    with WidgetsBindingObserver {
  List<DeviceCareStep> _steps = const [];
  int _currentIndex = 0;
  bool _isRefreshing = false;
  bool _locationWhileInUseOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _steps = OemSettingsService.defaultContent().steps;
    unawaited(_refreshSteps());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSteps());
    }
  }

  Future<void> _refreshSteps() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    await OemSettingsService.onAppResumed();
    final content = await OemSettingsService.loadContent();
    final whileInUseOnly = await hasLocationWhenInUseOnly();
    if (!mounted) {
      _isRefreshing = false;
      return;
    }
    setState(() {
      final previousLength = _steps.length;
      _steps = content.steps;
      _locationWhileInUseOnly = whileInUseOnly;
      if (_steps.length < previousLength) {
        _currentIndex = 0;
      } else if (_currentIndex >= _steps.length && _steps.isNotEmpty) {
        _currentIndex = _steps.length - 1;
      }
    });
    _isRefreshing = false;
    if (_steps.isEmpty) {
      await _goToDashboard();
    }
  }

  Future<void> _skipForNow() async {
    await OemSettingsService.markOnboardingSkippedForSession();
    if (!mounted) return;
    await _goToDashboard();
  }

  Future<void> _goToDashboard() async {
    if (!mounted) return;
    final role = ref.read(authProvider).role;
    if (role == 'moderator') {
      context.go('/moderator-dashboard');
    } else {
      context.go('/pilgrim-dashboard');
    }
  }

  Future<void> _handlePrimaryAction(DeviceCareStep step) async {
    await OemSettingsService.openStepAction(step.kind, context: context);
    await _refreshSteps();
  }

  Future<void> _handleManualAck(DeviceCareStep step) async {
    if (step.kind == DeviceCareActionKind.backgroundAppRefresh) {
      await OemSettingsService.markBackgroundRefreshManuallyAcknowledged();
    }
    await _refreshSteps();
  }

  IconData _iconFor(DeviceCareActionKind kind) => switch (kind) {
        DeviceCareActionKind.location => Symbols.location_on,
        DeviceCareActionKind.notifications => Symbols.notifications_active,
        DeviceCareActionKind.backgroundAppRefresh => Symbols.refresh,
        _ => Symbols.settings,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    if (_steps.isEmpty) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    final totalSteps = _steps.length;
    final safeIndex = _currentIndex.clamp(0, totalSteps - 1);
    final step = _steps[safeIndex];
    final progress = (safeIndex + 1) / totalSteps;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Icon(Symbols.phone_iphone, size: 20.w, color: muted),
                    SizedBox(width: 8.w),
                    Text(
                      'ios_setup_badge'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6.h,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'ios_setup_step_of'.tr(
                    namedArgs: {
                      'current': '${safeIndex + 1}',
                      'total': '$totalSteps',
                    },
                  ),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    color: muted,
                  ),
                ),
                SizedBox(height: 28.h),
                Center(
                  child: Container(
                    width: 96.w,
                    height: 96.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(step.kind),
                      size: 44.w,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'ios_setup_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'ios_setup_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    height: 1.45,
                    color: muted,
                  ),
                ),
                SizedBox(height: 24.h),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20.w),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: border),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.titleKey.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          Text(
                            step.descriptionKey.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              height: 1.5,
                              color: muted,
                            ),
                          ),
                          if (step.footnoteKey != null) ...[
                            SizedBox(height: 16.h),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Symbols.info,
                                    size: 18.w,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      step.footnoteKey!.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12.sp,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (step.kind == DeviceCareActionKind.location &&
                              _locationWhileInUseOnly) ...[
                            SizedBox(height: 16.h),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10.r),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Symbols.warning,
                                    size: 18.w,
                                    color: Colors.orange.shade800,
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      'ios_setup_location_while_in_use_hint'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12.sp,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  height: 52.h,
                  child: FilledButton(
                    onPressed: () => _handlePrimaryAction(step),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      step.actionLabelKey.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (step.kind == DeviceCareActionKind.backgroundAppRefresh) ...[
                  SizedBox(height: 4.h),
                  TextButton(
                    onPressed: () => _handleManualAck(step),
                    child: Text(
                      'ios_setup_already_set'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ],
                if (safeIndex > 0)
                  TextButton(
                    onPressed: () => setState(() => _currentIndex--),
                    child: Text(
                      'ios_setup_back'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14.sp,
                        color: muted,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _skipForNow,
                  child: Text(
                    'ios_setup_skip'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
