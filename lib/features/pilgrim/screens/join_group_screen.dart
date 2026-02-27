import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/pilgrim_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Join Group Screen  (QR scan + manual code entry)
// ─────────────────────────────────────────────────────────────────────────────

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _isLoading = false;
  bool _torchOn = false;
  bool _qrHandled = false;
  bool? _cameraGranted; // null = checking

  // Scan line animation
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraGranted = status.isGranted);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    _scanLineController.dispose();
    super.dispose();
  }

  // ── Join via code ─────────────────────────────────────────────────────────

  Future<void> _joinWithCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('join_group_enter_code'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    final (ok, nameOrError) = await ref
        .read(pilgrimProvider.notifier)
        .joinGroup(trimmed);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'join_group_success'.tr(namedArgs: {'name': nameOrError ?? ''}),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true); // signal success to caller
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nameOrError ?? 'Error'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── QR detected ──────────────────────────────────────────────────────────

  void _onQrDetected(BarcodeCapture capture) {
    if (_qrHandled || _isLoading) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _qrHandled = true;
    _scannerController.stop();
    _joinWithCode(code);
  }

  // ── "Where do I find my code?" dialog ────────────────────────────────────

  void _showWhereDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'join_group_where'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
          ),
        ),
        content: Text(
          'join_group_where_body'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: AppColors.textMutedLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: TextStyle(fontFamily: 'Lexend', color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Permission gate ──────────────────────────────────────────────────
    if (_cameraGranted == null) {
      // Still checking
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_cameraGranted == false) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(32.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.photo_camera, color: Colors.white54, size: 72.sp),
                SizedBox(height: 24.h),
                Text(
                  'Camera permission required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Please grant camera access so we can scan your group QR code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: Colors.white60,
                  ),
                ),
                SizedBox(height: 32.h),
                ElevatedButton(
                  onPressed: () async {
                    final status = await Permission.camera.request();
                    if (!mounted) return;
                    if (status.isGranted) {
                      setState(() => _cameraGranted = true);
                    } else if (status.isPermanentlyDenied) {
                      await openAppSettings();
                    } else {
                      _requestCameraPermission();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: 32.w,
                      vertical: 14.h,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'Grant Permission',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Back',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: Colors.white54,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // ── Camera / QR scanner ──────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // Camera feed
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onQrDetected,
                ),

                // Dark gradient overlay at very top (for back btn readability)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 120.h,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Top bar: back + title + torch
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 8.h,
                    ),
                    child: Row(
                      children: [
                        _CircleBtn(
                          icon: Symbols.arrow_back,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        Text(
                          'join_group_title'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 18.sp,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        _CircleBtn(
                          icon: _torchOn
                              ? Symbols.flashlight_off
                              : Symbols.bolt,
                          onTap: () {
                            setState(() => _torchOn = !_torchOn);
                            _scannerController.toggleTorch();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Scanning frame corners + animated scan line
                Center(
                  child: SizedBox(
                    width: 260.w,
                    height: 260.w,
                    child: Stack(
                      children: [
                        // Corners
                        CustomPaint(
                          size: Size(260.w, 260.w),
                          painter: _CornerPainter(),
                        ),

                        // Animated scan line
                        AnimatedBuilder(
                          animation: _scanLineAnimation,
                          builder: (_, _) {
                            final top = _scanLineAnimation.value * (260.w - 4);
                            return Positioned(
                              top: top,
                              left: 10.w,
                              right: 10.w,
                              child: Container(
                                height: 2.5,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.6),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Instruction text at bottom of camera area
                Positioned(
                  bottom: 28.h,
                  left: 24.w,
                  right: 24.w,
                  child: Text(
                    'join_group_align'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 6),
                      ],
                    ),
                  ),
                ),

                // Loading overlay
                if (_isLoading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // ── Manual code entry bottom sheet ───────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            ),
            padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 32.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 20.h),

                // Title
                Text(
                  'join_group_trouble'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: const Color(0xff1a1a2e),
                  ),
                ),
                SizedBox(height: 8.h),

                // Subtitle
                Text(
                  'join_group_trouble_sub'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: AppColors.textMutedLight,
                  ),
                ),
                SizedBox(height: 20.h),

                // Code text field
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'join_group_code_hint'.tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Lexend',
                      color: Colors.grey.shade400,
                      letterSpacing: 0.5,
                    ),
                    prefixIcon: Icon(
                      Symbols.group,
                      color: Colors.grey.shade400,
                      size: 22.sp,
                    ),
                    filled: true,
                    fillColor: const Color(0xfff8f9fa),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20.w,
                      vertical: 16.h,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onSubmitted: _joinWithCode,
                ),
                SizedBox(height: 16.h),

                // Join Group button
                SizedBox(
                  width: double.infinity,
                  height: 54.h,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _joinWithCode(_codeController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28.r),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22.w,
                            height: 22.w,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'join_group_btn'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16.sp,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Icon(Symbols.arrow_forward, size: 20.sp),
                            ],
                          ),
                  ),
                ),
                SizedBox(height: 12.h),

                // "Where do I find my code?" link
                GestureDetector(
                  onTap: _showWhereDialog,
                  child: Text(
                    'join_group_where'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small circular icon button used in the top bar
// ─────────────────────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20.sp),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Green corner brackets painter
// ─────────────────────────────────────────────────────────────────────────────

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const len = 30.0;
    final r = 12.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, len + r)
        ..arcToPoint(Offset(r, r), radius: Radius.circular(r))
        ..lineTo(len + r, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len - r, 0)
        ..lineTo(size.width - r, 0)
        ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
        ..lineTo(size.width, len + r),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - len - r)
        ..lineTo(0, size.height - r)
        ..arcToPoint(Offset(r, size.height), radius: Radius.circular(r))
        ..lineTo(len + r, size.height),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - len - r, size.height)
        ..lineTo(size.width - r, size.height)
        ..arcToPoint(
          Offset(size.width, size.height - r),
          radius: Radius.circular(r),
        )
        ..lineTo(size.width, size.height - len - r),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
