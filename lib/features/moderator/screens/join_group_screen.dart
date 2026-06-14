import 'package:easy_localization/easy_localization.dart';
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

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _codeController = TextEditingController();
  bool _isManualEntry = false;
  bool _isLoading = false;
  bool _scanHandled = false;

  @override
  void dispose() {
    _scannerController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin(String code) async {
    if (code.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    final (success, error) =
        await ref.read(moderatorProvider.notifier).joinGroup(code);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        StandardSnackBar.showSuccess(context, 'group_join_success'.tr());
        Navigator.of(context).pop();
      } else {
        StandardSnackBar.showError(context, error ?? 'group_join_failed'.tr());
        _scanHandled = false;
        if (!_isManualEntry) {
          _scannerController.start();
        }
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || _isLoading || _isManualEntry) return;
    final code = firstBarcodeRawValue(capture);
    if (code == null) return;

    _scanHandled = true;
    _scannerController.stop();
    _handleJoin(code);
  }

  void _setManualEntry(bool manual) {
    setState(() {
      _isManualEntry = manual;
      _scanHandled = false;
      if (manual) {
        _scannerController.stop();
      } else {
        _scannerController.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF0F0F8),
      appBar: AppBar(
        title: Text(
          'join_group'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
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
        child: _isManualEntry
            ? _buildManualBody(isDark)
            : _buildScannerBody(isDark),
      ),
    );
  }

  Widget _buildScannerBody(bool isDark) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: QrScannerView(
              controller: _scannerController,
              onDetect: _onDetect,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'scan_group_qr'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              color: isDark ? AppColors.textMutedLight : Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 16.h),
          TextButton(
            onPressed: () => _setManualEntry(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.symmetric(vertical: 12.h),
            ),
            child: Text(
              'not_working_enter_code'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualBody(bool isDark) {
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    return AppScrollFadeOverlay(
      showTop: false,
      backgroundColor: bg,
      child: SingleChildScrollView(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 16.h),
          Text(
            'enter_group_code_manual'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              color: isDark ? AppColors.textMutedLight : Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 24.h),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: 'CODE123',
              hintStyle: TextStyle(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                letterSpacing: 4,
              ),
              filled: true,
              fillColor: isDark ? AppColors.surfaceDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.r),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 20.h),
            ),
          ),
          SizedBox(height: 32.h),
          ElevatedButton(
            onPressed: _isLoading ? null : () => _handleJoin(_codeController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: Size(double.infinity, 56.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'join_group'.tr(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                    ),
                  ),
          ),
          SizedBox(height: 24.h),
          TextButton(
            onPressed: () => _setManualEntry(false),
            child: Text(
              'back_to_scan'.tr(),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.sp,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
