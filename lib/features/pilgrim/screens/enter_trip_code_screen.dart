import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dio/dio.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/services/api_service.dart';
import '../providers/pilgrim_provider.dart';
import 'scan_trip_qr_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enter Trip Code Screen
// ─────────────────────────────────────────────────────────────────────────────

class EnterTripCodeScreen extends StatefulWidget {
  final ActiveBoardingSession session;

  const EnterTripCodeScreen({
    super.key,
    required this.session,
  });

  @override
  State<EnterTripCodeScreen> createState() => _EnterTripCodeScreenState();
}

class _EnterTripCodeScreenState extends State<EnterTripCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  String _currentCode = '';

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      setState(() {
        _currentCode = _codeController.text.toUpperCase();
      });
    });
    // Auto-focus after builds
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
      StandardSnackBar.showWarning(context, 'Please enter the full 6-digit code.');
      return;
    }

    final fullSessionId = widget.session.sessionId;
    if (fullSessionId.length < 6) {
      StandardSnackBar.showError(context, 'Invalid session state.');
      return;
    }

    final targetSuffix = fullSessionId.substring(fullSessionId.length - 6).toUpperCase();
    if (entered != targetSuffix) {
      StandardSnackBar.showError(
        context,
        'Invalid code. Please enter the code shown on the moderator\'s screen.',
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
        StandardSnackBar.showSuccess(
          context,
          'Successfully checked in to trip!',
        );
        Navigator.of(context).pop(); // Go back to Home
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        final errorMsg = ApiService.parseError(e);
        StandardSnackBar.showError(
          context,
          errorMsg.isNotEmpty ? errorMsg : 'Failed to check in. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        StandardSnackBar.showError(
          context,
          'An unexpected error occurred.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : const Color(0xfff1f5f3),
      appBar: AppBar(
        title: Text(
          'Enter Trip Code',
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
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 24.h),
                // Keyboard Icon inside circle
                Center(
                  child: Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEDD5), // Light orange background
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.keyboard_outlined,
                      color: AppColors.primary,
                      size: 44.sp,
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'Enter the 6-digit code shown on the moderator\'s screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : AppColors.textDark,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 32.h),

                // PIN fields + Invisible TextField overlay
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Alphanumeric digit boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, (index) {
                        String char = '';
                        if (_currentCode.length > index) {
                          char = _currentCode[index];
                        }
                        final isSelected = _currentCode.length == index && _focusNode.hasFocus;

                        return Container(
                          width: 44.w,
                          height: 54.h,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2D) : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : (char.isNotEmpty
                                      ? AppColors.primary.withValues(alpha: 0.5)
                                      : Colors.transparent),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            char,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        );
                      }),
                    ),
                    // Underlying invisible textfield
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
                        decoration: const InputDecoration(
                          counterText: '',
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 32.h),

                // Info card: Codes are valid for 5 minutes
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Symbols.info,
                        color: isDark ? AppColors.textMutedLight : Colors.grey.shade500,
                        size: 18.sp,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'Codes are valid for 5 minutes',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.textMutedLight : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 64.h),

                // Check In Button
                FilledButton(
                  onPressed: _isLoading ? null : _handleCheckIn,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8B4513), // Premium brown/bronze
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
                              'Check In',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w800,
                                fontSize: 16.sp,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Icon(
                              Symbols.arrow_forward,
                              size: 18.sp,
                            ),
                          ],
                        ),
                ),
                SizedBox(height: 24.h),

                // RE-SCAN QR CODE Button
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ScanTripQrScreen(
                          session: widget.session,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    'RE-SCAN QR CODE',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: isDark ? AppColors.textMutedLight : Colors.grey.shade600,
                      letterSpacing: 1.0,
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
