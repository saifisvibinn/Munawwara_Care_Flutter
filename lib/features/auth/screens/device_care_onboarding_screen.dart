import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/oem_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../providers/auth_provider.dart';
import '../widgets/device_care_settings_guide_sheet.dart';

/// Required permissions: location, notifications, and Android OEM settings.
class DeviceCareOnboardingScreen extends ConsumerStatefulWidget {
  const DeviceCareOnboardingScreen({super.key});

  @override
  ConsumerState<DeviceCareOnboardingScreen> createState() =>
      _DeviceCareOnboardingScreenState();
}

class _DeviceCareOnboardingScreenState
    extends ConsumerState<DeviceCareOnboardingScreen>
    with WidgetsBindingObserver {
  List<DeviceCareStep> _steps = const [];
  DeviceOemProfile _oemProfile = DeviceOemProfile.standard;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final defaults = OemSettingsService.defaultContent();
    _steps = defaults.steps;
    _oemProfile = defaults.profile;
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
    final content = await OemSettingsService.loadContent(
      role: ref.read(authProvider).role,
    );
    if (!mounted) {
      _isRefreshing = false;
      return;
    }
    setState(() {
      _steps = content.steps;
      _oemProfile = content.profile;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

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
                SizedBox(height: 16.h),
                Center(
                  child: Container(
                    width: 88.w,
                    height: 88.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.phonelink_setup,
                      size: 42.w,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'device_care_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'device_care_desc'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    height: 1.5,
                    color: muted,
                  ),
                ),
                SizedBox(height: 20.h),
                Expanded(
                  child: AppScrollFadeOverlay(
                    showTop: false,
                    backgroundColor: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                    child: _steps.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _steps.length,
                          separatorBuilder: (_, _) => SizedBox(height: 12.h),
                          itemBuilder: (context, index) {
                            return _DeviceCareStepCard(
                              step: _steps[index],
                              index: index + 1,
                              isDark: isDark,
                              oemProfile: _oemProfile,
                              role: ref.read(authProvider).role,
                              onStepAcknowledged: () => _refreshSteps(),
                            );
                          },
                        ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 52.h,
                  child: TextButton(
                    onPressed: _skipForNow,
                    child: Text(
                      'device_care_skip'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceCareStepCard extends StatelessWidget {
  const _DeviceCareStepCard({
    required this.step,
    required this.index,
    required this.isDark,
    required this.oemProfile,
    required this.role,
    required this.onStepAcknowledged,
  });

  final DeviceCareStep step;
  final int index;
  final bool isDark;
  final DeviceOemProfile oemProfile;
  final String? role;
  final VoidCallback onStepAcknowledged;

  IconData get _icon => switch (step.kind) {
        DeviceCareActionKind.location => Symbols.location_on,
        DeviceCareActionKind.battery => Symbols.battery_charging_full,
        DeviceCareActionKind.autostart => Symbols.rocket_launch,
        DeviceCareActionKind.notifications => Symbols.notifications_active,
        DeviceCareActionKind.lockScreenCalls => Symbols.phonelink_lock,
      };

  bool get _usesGuideSheet =>
      step.kind == DeviceCareActionKind.autostart ||
      step.kind == DeviceCareActionKind.notifications ||
      step.kind == DeviceCareActionKind.lockScreenCalls;

  Future<void> _handlePrimaryAction(BuildContext context) async {
    if (_usesGuideSheet) {
      await showDeviceCareSettingsGuide(
        context,
        kind: step.kind,
        profile: oemProfile,
      );
      onStepAcknowledged();
      return;
    }
    if (step.kind == DeviceCareActionKind.battery ||
        step.kind == DeviceCareActionKind.lockScreenCalls) {
      await OemSettingsService.openStepAction(
        step.kind,
        context: context,
        role: role,
      );
      // Step list refreshes on resume after user returns from Settings.
      return;
    }
    await OemSettingsService.openStepAction(
      step.kind,
      context: context,
      role: role,
    );
    onStepAcknowledged();
  }

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final border = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Container(
      padding: EdgeInsets.all(16.w),
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
          Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Icon(_icon, size: 22.w, color: AppColors.primary),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  step.titleKey.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            step.descriptionKey.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              height: 1.45,
              color: muted,
            ),
          ),
          if (step.footnoteKey != null) ...[
            SizedBox(height: 8.h),
            Text(
              step.footnoteKey!.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _handlePrimaryAction(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Text(
                step.actionLabelKey.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (step.kind == DeviceCareActionKind.battery &&
              oemProfile != DeviceOemProfile.standard) ...[
            SizedBox(height: 4.h),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _handleBatteryManuallyAcknowledged(),
                child: Text(
                  'device_care_battery_already_set'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textMutedLight
                        : AppColors.textDark,
                  ),
                ),
              ),
            ),
          ],
          if (step.kind == DeviceCareActionKind.lockScreenCalls &&
              OemSettingsService.profileNeedsOemLockScreenGuidance(
                oemProfile,
              )) ...[
            SizedBox(height: 4.h),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _handleLockScreenCallManuallyAcknowledged(),
                child: Text(
                  'device_care_lock_screen_already_set'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textMutedLight
                        : AppColors.textDark,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleBatteryManuallyAcknowledged() async {
    OemSettingsService.noteOpenedSettings(DeviceCareActionKind.battery);
    await OemSettingsService.markBatteryStepManuallyAcknowledged();
    onStepAcknowledged();
  }

  Future<void> _handleLockScreenCallManuallyAcknowledged() async {
    OemSettingsService.noteOpenedSettings(DeviceCareActionKind.lockScreenCalls);
    await OemSettingsService.markLockScreenCallStepManuallyAcknowledged();
    onStepAcknowledged();
  }
}
