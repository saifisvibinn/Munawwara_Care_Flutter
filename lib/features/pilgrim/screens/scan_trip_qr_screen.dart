import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/qr_scanner_view.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/qr_barcode_utils.dart';
import '../providers/pilgrim_provider.dart';
import '../widgets/trip_check_in_chrome.dart';
import 'enter_trip_code_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scan Trip QR Screen
// ─────────────────────────────────────────────────────────────────────────────

class ScanTripQrScreen extends ConsumerStatefulWidget {
  final ActiveBoardingSession session;

  const ScanTripQrScreen({
    super.key,
    required this.session,
  });

  @override
  ConsumerState<ScanTripQrScreen> createState() => _ScanTripQrScreenState();
}

class _ScanTripQrScreenState extends ConsumerState<ScanTripQrScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isLoading = false;
  bool _scanHandled = false;
  bool _isTorchOn = false;
  bool _manualRouteOpen = false;

  static const _bronze = Color(0xFF8B4513);

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleCheckIn(String sessionId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.dio.post(
        '/pilgrim/bus-attendance/board',
        data: {'session_id': sessionId},
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        await ref.read(pilgrimProvider.notifier).loadDashboard(force: true);
        if (mounted) {
          StandardSnackBar.showSuccess(
            context,
            'scan_trip_qr_success'.tr(),
          );
          Navigator.of(context).pop();
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _scanHandled = false;
        });
        _scannerController.start();
        final errorMsg = ApiService.parseError(e);
        StandardSnackBar.showError(
          context,
          errorMsg.isNotEmpty ? errorMsg : 'scan_trip_qr_failed'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _scanHandled = false;
        });
        _scannerController.start();
        StandardSnackBar.showError(
          context,
          'scan_trip_qr_unexpected_error'.tr(),
        );
      }
    }
  }

  Future<void> _resumeScanner() async {
    if (_manualRouteOpen || !mounted) return;
    try {
      await _scannerController.start();
    } on MobileScannerException {
      // Scanner may already be running or still initializing.
    }
  }

  Future<void> _openManualEntry() async {
    await _scannerController.stop();
    if (!mounted) return;

    _manualRouteOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EnterTripCodeScreen(
          session: widget.session,
        ),
      ),
    );
    _manualRouteOpen = false;
    _scanHandled = false;
    await _resumeScanner();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || _isLoading || _manualRouteOpen) return;
    final rawVal = firstBarcodeRawValue(capture);
    if (rawVal == null) return;

    final uri = Uri.tryParse(rawVal);
    String? sessionId;
    if (uri != null) {
      sessionId = uri.queryParameters['session_id'];
    }
    if (sessionId == null &&
        rawVal.length == 24 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(rawVal)) {
      sessionId = rawVal;
    }

    if (sessionId == null || sessionId.isEmpty) {
      return;
    }

    _scanHandled = true;
    _scannerController.stop();
    _handleCheckIn(sessionId);
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppDashboardBackground(
      isDark: isDark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TripCheckInPageHeader(
                      isDark: isDark,
                      title: 'scan_trip_qr_subtitle'.tr(),
                      subtitle: 'scan_trip_qr_body'.tr(),
                    ),
                    SizedBox(height: 20.h),
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
                      child: FilledButton.icon(
                        onPressed: _toggleTorch,
                        icon: Icon(
                          _isTorchOn
                              ? Symbols.flashlight_off
                              : Symbols.flashlight_on,
                          size: 20.sp,
                        ),
                        label: Text(
                          _isTorchOn
                              ? 'scan_trip_qr_flashlight_close'.tr()
                              : 'scan_trip_qr_flashlight_open'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _bronze,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextButton(
                      onPressed: _openManualEntry,
                      style: TextButton.styleFrom(
                        foregroundColor: _bronze,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'scan_trip_qr_enter_code_instead'.tr(),
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
                  ],
                ),
              ),
            ),
            TripCheckInFloatingBackButton(
              isDark: isDark,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
