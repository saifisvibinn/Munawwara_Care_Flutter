import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/qr_scanner_view.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/qr_barcode_utils.dart';
import '../providers/pilgrim_provider.dart';
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
        // Force-refresh the pilgrim dashboard so attended status updates immediately
        await ref.read(pilgrimProvider.notifier).loadDashboard(force: true);
        if (mounted) {
          StandardSnackBar.showSuccess(
            context,
            'scan_trip_qr_success'.tr(),
          );
          Navigator.of(context).pop(); // Go back to Home
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _scanHandled = false;
        });
        _scannerController.start(); // Resume scanning
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
        _scannerController.start(); // Resume scanning
        StandardSnackBar.showError(
          context,
          'scan_trip_qr_unexpected_error'.tr(),
        );
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || _isLoading) return;
    final rawVal = firstBarcodeRawValue(capture);
    if (rawVal == null) return;

    // Extract session_id
    final uri = Uri.tryParse(rawVal);
    String? sessionId;
    if (uri != null) {
      sessionId = uri.queryParameters['session_id'];
    }
    // Fallback: Check if raw value itself is a 24-char hex MongoDB ObjectId
    if (sessionId == null && rawVal.length == 24 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(rawVal)) {
      sessionId = rawVal;
    }

    if (sessionId == null || sessionId.isEmpty) {
      // Invalid QR code format for trip attendance
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

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xfff1f5f3),
      appBar: AppBar(
        title: Text(
          'scan_trip_qr_appbar_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Symbols.arrow_back,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'scan_trip_qr_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'scan_trip_qr_body'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 24.h),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrScannerView(
                      controller: _scannerController,
                      onDetect: _onDetect,
                    ),
                    if (_isLoading)
                      Container(
                        color: Colors.black45,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),
              // Open Flashlight Button
              Center(
                child: FilledButton.icon(
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _isTorchOn ? Symbols.flashlight_off : Symbols.flashlight_on,
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
                    backgroundColor: const Color(0xFF8B4513), // Premium brown/bronze color
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => EnterTripCodeScreen(
                        session: widget.session,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8B4513),
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
                    Icon(
                      Symbols.arrow_forward,
                      size: 16.sp,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
