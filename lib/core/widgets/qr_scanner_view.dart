import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Shared [MobileScanner] wrapper for pilgrim login, moderator join-group, etc.
class QrScannerView extends StatelessWidget {
  const QrScannerView({
    super.key,
    required this.controller,
    required this.onDetect,
    this.height,
    this.borderRadius,
    this.showScanFrame = true,
  });

  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final double? height;
  final double? borderRadius;

  /// `false` = clip + camera only (e.g. pilgrim login). `true` = border + scan frame (e.g. join group).
  final bool showScanFrame;

  @override
  Widget build(BuildContext context) {
    final h = height ?? 300.h;

    if (!showScanFrame) {
      final r = borderRadius ?? 16.r;
      return SizedBox(
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: MobileScanner(
            controller: controller,
            onDetect: onDetect,
          ),
        ),
      );
    }

    final r = borderRadius ?? 24.r;
    final innerR = (r - 2).clamp(0.0, r);

    return Container(
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerR),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: onDetect,
            ),
            const _ScannerOverlay(),
          ],
        ),
      ),
    );
  }
}

/// Darkened frame around the scan window; avoids blend-mode hole punch that
/// renders as a solid white block on some devices (Impeller / certain GPUs).
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  static const _dimColor = Color(0x80000000);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        final size = math.min(200.w, math.min(maxW, maxH) * 0.72);
        final left = (maxW - size) / 2;
        final top = (maxH - size) / 2;
        final topBarH = top.clamp(0.0, maxH);
        final bottomBarH = math.max(0.0, maxH - top - size);
        final leftBarW = left.clamp(0.0, maxW);
        final rightBarW = math.max(0.0, maxW - left - size);

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topBarH,
              child: const ColoredBox(color: _dimColor),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomBarH,
              child: const ColoredBox(color: _dimColor),
            ),
            Positioned(
              top: top,
              left: 0,
              width: leftBarW,
              height: size,
              child: const ColoredBox(color: _dimColor),
            ),
            Positioned(
              top: top,
              right: 0,
              width: rightBarW,
              height: size,
              child: const ColoredBox(color: _dimColor),
            ),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: [
                    _buildCorner(Alignment.topLeft),
                    _buildCorner(Alignment.topRight),
                    _buildCorner(Alignment.bottomLeft),
                    _buildCorner(Alignment.bottomRight),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 30.w,
        height: 30.w,
        decoration: BoxDecoration(
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            bottom:
                alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
                    ? const BorderSide(color: AppColors.primary, width: 4)
                    : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                ? const BorderSide(color: AppColors.primary, width: 4)
                : BorderSide.none,
            right:
                alignment == Alignment.topRight || alignment == Alignment.bottomRight
                    ? const BorderSide(color: AppColors.primary, width: 4)
                    : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
