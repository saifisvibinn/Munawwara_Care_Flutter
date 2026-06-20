import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/utils/qr_barcode_utils.dart';
import '../../../core/widgets/qr_scanner_view.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../providers/moderator_provider.dart';
import '../widgets/moderator_map_widgets.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _codeController = TextEditingController();
  final ValueNotifier<bool> _loading = ValueNotifier(false);
  bool _isLoading = false;
  bool _scanHandled = false;
  bool _manualRouteOpen = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _codeController.dispose();
    _loading.dispose();
    super.dispose();
  }

  Future<void> _resumeScanner() async {
    if (_manualRouteOpen || !mounted) return;
    try {
      await _scannerController.start();
    } on MobileScannerException {
      // Scanner may already be running or still initializing.
    }
  }

  Future<void> _handleJoin(String code) async {
    if (code.trim().isEmpty) return;

    _loading.value = true;
    setState(() => _isLoading = true);

    final (success, error) =
        await ref.read(moderatorProvider.notifier).joinGroup(code);

    if (!mounted) return;

    _loading.value = false;
    setState(() => _isLoading = false);

    if (success) {
      StandardSnackBar.showSuccess(context, 'group_join_success'.tr());
      final navigator = Navigator.of(context);
      if (_manualRouteOpen) {
        navigator.pop();
      }
      navigator.pop();
    } else {
      StandardSnackBar.showError(context, error ?? 'group_join_failed'.tr());
      _scanHandled = false;
      if (!_manualRouteOpen) {
        await _resumeScanner();
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || _isLoading || _manualRouteOpen) return;
    final code = firstBarcodeRawValue(capture);
    if (code == null) return;

    _scanHandled = true;
    _scannerController.stop();
    _handleJoin(code);
  }

  Future<void> _openManualEntry() async {
    await _scannerController.stop();
    if (!mounted) return;

    _manualRouteOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _JoinGroupManualEntryScreen(
          codeController: _codeController,
          isLoading: _loading,
          onJoin: _handleJoin,
        ),
      ),
    );
    _manualRouteOpen = false;
    _scanHandled = false;
    await _resumeScanner();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fadeBg = AppGlassTheme.dashboardBackgroundColor(isDark);

    return AppDashboardBackground(
      isDark: isDark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              bottom: false,
              child: AppScrollFadeOverlay(
                showTop: false,
                useDashboardBottomExtent: false,
                backgroundColor: fadeBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _JoinGroupPageHeader(
                      isDark: isDark,
                      subtitle: 'scan_group_qr'.tr(),
                    ),
                    SizedBox(height: 20.h),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                        child: _buildScannerBody(isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _JoinGroupBackButton(
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerBody(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AppGlassCard(
            isDark: isDark,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(24.r),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24.r),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      QrScannerView(
                        controller: _scannerController,
                        onDetect: _onDetect,
                        height: constraints.maxHeight,
                        borderRadius: 24.r,
                      ),
                      if (_isLoading)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox(height: 20.h),
        SizedBox(
          width: double.infinity,
          height: 50.h,
          child: TextButton(
            onPressed: _openManualEntry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'not_working_enter_code'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(Symbols.arrow_forward, size: 16.sp),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _JoinGroupManualEntryScreen extends StatelessWidget {
  const _JoinGroupManualEntryScreen({
    required this.codeController,
    required this.isLoading,
    required this.onJoin,
  });

  final TextEditingController codeController;
  final ValueListenable<bool> isLoading;
  final Future<void> Function(String code) onJoin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fadeBg = AppGlassTheme.dashboardBackgroundColor(isDark);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final outline = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return AppDashboardBackground(
      isDark: isDark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              bottom: false,
              child: AppScrollFadeOverlay(
                showTop: false,
                useDashboardBottomExtent: false,
                backgroundColor: fadeBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _JoinGroupPageHeader(
                      isDark: isDark,
                      subtitle: 'enter_group_code_manual'.tr(),
                    ),
                    SizedBox(height: 20.h),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppGlassCard(
                                isDark: isDark,
                                padding: EdgeInsets.fromLTRB(
                                  20.w,
                                  24.h,
                                  20.w,
                                  24.h,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      width: 56.w,
                                      height: 56.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.22),
                                        ),
                                      ),
                                      child: Icon(
                                        Symbols.pin,
                                        size: 28.w,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    SizedBox(height: 20.h),
                                    TextField(
                                      controller: codeController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      textAlign: TextAlign.center,
                                      autofocus: true,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 24.sp,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 4,
                                        color: textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'CODE123',
                                        hintStyle: TextStyle(
                                          fontFamily: 'Lexend',
                                          color: textMuted.withValues(
                                            alpha: 0.45,
                                          ),
                                          letterSpacing: 4,
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF1A2230)
                                            : AppColors.iconBgLight
                                                .withValues(alpha: 0.65),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14.r),
                                          borderSide: BorderSide(
                                            color: outline.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14.r),
                                          borderSide: BorderSide(
                                            color: outline.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(14.r),
                                          borderSide: BorderSide(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.55),
                                            width: 1.5,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 18.h,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20.h),
                              ValueListenableBuilder<bool>(
                                valueListenable: isLoading,
                                builder: (context, loading, _) {
                                  return SizedBox(
                                    width: double.infinity,
                                    height: 52.h,
                                    child: FilledButton(
                                      onPressed: loading
                                          ? null
                                          : () => onJoin(codeController.text),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14.r),
                                        ),
                                      ),
                                      child: loading
                                          ? SizedBox(
                                              width: 22.w,
                                              height: 22.w,
                                              child:
                                                  const CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(
                                              'join_group'.tr(),
                                              style: TextStyle(
                                                fontFamily: 'Lexend',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15.sp,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: 12.h),
                              SizedBox(
                                width: double.infinity,
                                height: 48.h,
                                child: TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                  ),
                                  child: Text(
                                    'back_to_scan'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15.sp,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _JoinGroupBackButton(
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinGroupPageHeader extends StatelessWidget {
  const _JoinGroupPageHeader({
    required this.isDark,
    required this.subtitle,
  });

  final bool isDark;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'join_group'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w800,
              fontSize: 20.sp,
              color: textPrimary,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              height: 1.4,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinGroupBackButton extends StatelessWidget {
  const _JoinGroupBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingGlassBackButton(onTap: onTap);
  }
}
