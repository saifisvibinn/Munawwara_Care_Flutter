import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass_surface.dart';
import '../../shared/models/suggested_area_model.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/moderator_provider.dart';

/// Marker tail painter for the map markers.
class MarkerTailPainter extends CustomPainter {
  final Color color;
  const MarkerTailPainter({required this.color});

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
  bool shouldRepaint(MarkerTailPainter old) => old.color != color;
}

/// A circular button with an icon, used for map controls.
class CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const CircleButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.textDark;
    final sz = 42.w;
    return GestureDetector(
      onTap: onTap,
      child: AppGlassSurface(
        isDark: isDark,
        borderRadius: BorderRadius.circular(sz / 2),
        width: sz,
        height: sz,
        child: Center(
          child: Icon(icon, size: sz * 0.48, color: fg),
        ),
      ),
    );
  }
}

/// A map marker for a pilgrim (name chip + pin body + tail + ground dot).
///
/// Pair with flutter_map [Marker.alignment] `Alignment.topCenter` so the
/// geographic [Marker.point] sits on the ground dot (v7 places [point] at the
/// top edge when using `bottomCenter`, which wrongly pins the name label).
class PilgrimMapMarker extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  final bool isSelected;
  final bool isSOS;

  const PilgrimMapMarker({
    super.key,
    required this.pilgrim,
    this.isSelected = false,
    this.isSOS = false,
  });

  /// Room for chip/circle shadows without shifting the ground dot anchor.
  static double get _mapPadH => 3.w;

  static double get _mapPadTop => 6.h;

  /// Exact [Marker] size for flutter_map: must match padded [PilgrimMapMarker] or
  /// the geographic point drifts by empty space inside the box (worse at some
  /// zoom levels).
  static Size mapMarkerSize(
    BuildContext context, {
    required bool isSelected,
  }) {
    final diameter = isSelected ? 40.w : 36.w;
    final chipPadV = 8.h;
    final fontSize = 10.sp;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(fontSize) * 1.35;
    final chipHeight = chipPadV + lineHeight;
    // Add a generous buffer (8.h) for borders, rounding, and shadow room.
    final innerH = chipHeight + 5.h + diameter + 7.h + 9.w + 8.h;
    final innerW = 108.w;
    return Size(
      innerW + 2 * _mapPadH,
      innerH + _mapPadTop,
    );
  }

  static EdgeInsets mapMarkerPadding() => EdgeInsets.only(
        left: _mapPadH,
        right: _mapPadH,
        top: _mapPadTop,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sos = isSOS;
    final color = sos ? const Color(0xFFDC2626) : AppColors.primary;
    final borderColor = sos
        ? Colors.white
        : isSelected
            ? AppColors.accentGold
            : Colors.white;
    final borderW = isSelected ? 3.5 : 2.5;
    final diameter = isSelected ? 40.w : 36.w;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 108.w),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(
              pilgrim.firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
          ),
        ),
        SizedBox(height: 5.h),
        Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: borderW),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isSelected ? 0.55 : 0.42),
                blurRadius: isSelected ? 14 : 10,
                spreadRadius: isSelected ? 2 : 1,
              ),
            ],
          ),
          child: sos
              ? Icon(
                  Symbols.warning,
                  color: Colors.white,
                  size: 19.w,
                  fill: 1,
                )
              : Center(
                  child: PilgrimGenderAvatar(
                    gender: pilgrim.gender,
                    size: diameter * 0.92,
                    imageUrl: pilgrim.profilePicture,
                  ),
                ),
        ),
        CustomPaint(
          size: Size(12.w, 7.h),
          painter: MarkerTailPainter(color: color),
        ),
        Container(
          width: 9.w,
          height: 9.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 5,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A map marker for a suggested area or meetpoint.
class AreaMapMarker extends StatelessWidget {
  final SuggestedArea area;

  const AreaMapMarker({super.key, required this.area});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = area.isMeetpoint ? const Color(0xFFDC2626) : AppColors.primary;
    final icon = area.isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
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
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: MarkerTailPainter(color: color),
        ),
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
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
