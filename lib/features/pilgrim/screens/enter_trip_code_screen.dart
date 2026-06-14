import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/services/api_service.dart';
import '../providers/pilgrim_provider.dart';
import '../widgets/trip_check_in_chrome.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enter Trip Code Screen
// ─────────────────────────────────────────────────────────────────────────────

class EnterTripCodeScreen extends ConsumerStatefulWidget {
  final ActiveBoardingSession session;

  const EnterTripCodeScreen({
    super.key,
    required this.session,
  });

  @override
  ConsumerState<EnterTripCodeScreen> createState() => _EnterTripCodeScreenState();
}

class _EnterTripCodeScreenState extends ConsumerState<EnterTripCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  String _currentCode = '';

  static const _bronze = Color(0xFF8B4513);

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      setState(() {
        _currentCode = _codeController.text.toUpperCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleCheckIn() async {
    final entered = _currentCode.trim();
    if (entered.length != 6) {
      StandardSnackBar.showWarning(context, 'enter_trip_code_warning_length'.tr());
      return;
    }

    final fullSessionId = widget.session.sessionId;
    if (fullSessionId.length < 6) {
      StandardSnackBar.showError(context, 'enter_trip_code_error_session'.tr());
      return;
    }

    final targetSuffix =
        fullSessionId.substring(fullSessionId.length - 6).toUpperCase();
    if (entered != targetSuffix) {
      StandardSnackBar.showError(
        context,
        'enter_trip_code_error_incorrect'.tr(),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.dio.post(
        '/pilgrim/bus-attendance/board',
        data: {'session_id': fullSessionId},
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
          final navigator = Navigator.of(context);
          navigator.pop();
          if (navigator.canPop()) {
            navigator.pop();
          }
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
        });
        StandardSnackBar.showError(
          context,
          'scan_trip_qr_unexpected_error'.tr(),
        );
      }
    }
  }

  Widget _buildPinRow(bool isDark) {
    final outline = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              for (var index = 0; index < 6; index++) ...[
                if (index > 0) SizedBox(width: 8.w),
                Expanded(child: _buildPinCell(index, isDark, outline)),
              ],
            ],
          ),
          Opacity(
            opacity: 0,
            child: TextField(
              controller: _codeController,
              focusNode: _focusNode,
              maxLength: 6,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(counterText: ''),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinCell(int index, bool isDark, Color outline) {
    final char =
        _currentCode.length > index ? _currentCode[index] : '';
    final isSelected = _currentCode.length == index && _focusNode.hasFocus;
    final hasChar = char.isNotEmpty;

    return Container(
      height: 56.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A2230)
            : AppColors.iconBgLight.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : hasChar
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : outline.withValues(alpha: 0.65),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Text(
        char,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 24.sp,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : AppColors.textDark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AppDashboardBackground(
      isDark: isDark,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, bottomInset + 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TripCheckInPageHeader(
                      isDark: isDark,
                      title: 'enter_trip_code_appbar_title'.tr(),
                      subtitle: 'enter_trip_code_body'.tr(),
                    ),
                    SizedBox(height: 20.h),
                    AppGlassCard(
                      isDark: isDark,
                      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 20.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 56.w,
                              height: 56.w,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.22),
                                ),
                              ),
                              child: Icon(
                                Symbols.keyboard,
                                size: 28.w,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          SizedBox(height: 24.h),
                          _buildPinRow(isDark),
                          SizedBox(height: 20.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Symbols.info,
                                color: textMuted,
                                size: 18.sp,
                              ),
                              SizedBox(width: 8.w),
                              Flexible(
                                child: Text(
                                  'enter_trip_code_validity'.tr(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w500,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24.h),
                    FilledButton(
                      onPressed: _isLoading ? null : _handleCheckIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: _bronze,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, 56.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.r),
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
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'enter_trip_code_btn'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16.sp,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Icon(Symbols.arrow_forward, size: 18.sp),
                              ],
                            ),
                    ),
                    SizedBox(height: 8.h),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _bronze,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                      ),
                      child: Text(
                        'enter_trip_code_rescan_qr'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                          letterSpacing: 0.5,
                        ),
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
