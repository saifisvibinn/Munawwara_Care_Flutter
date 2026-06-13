import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../shared/models/suggested_area_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Area Marker — pill label + triangle tail + dot
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimAreaMarker extends StatelessWidget {
  final SuggestedArea area;
  const PilgrimAreaMarker({super.key, required this.area});

  @override
  Widget build(BuildContext context) {
    final color = area.isMeetpoint
        ? const Color(0xFFDC2626)
        : AppColors.primary;
    final icon = area.isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14.w, color: color, fill: 1),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  area.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 9.sp,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Triangle tail
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: _AreaTailPainter(color: color),
        ),
        // Circle dot
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AreaTailPainter extends CustomPainter {
  final Color color;
  const _AreaTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AreaTailPainter old) => old.color != color;
}
