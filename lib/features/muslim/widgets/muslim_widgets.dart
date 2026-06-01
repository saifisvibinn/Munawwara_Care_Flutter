import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/muslim_colors.dart';

class ArabicText extends StatelessWidget {
  const ArabicText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.right,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        style: (style ?? TextStyle(fontSize: 20.sp)).copyWith(
          fontFamily: 'Amiri',
          height: 1.8,
        ),
      ),
    );
  }
}

TextStyle muslimArabicStyle({
  double? fontSize,
  Color? color,
  FontWeight fontWeight = FontWeight.w400,
}) {
  return TextStyle(
    fontFamily: 'Amiri',
    fontSize: fontSize ?? 20.sp,
    color: color ?? MuslimColors.primary,
    fontWeight: fontWeight,
    height: 1.8,
  );
}

class IslamicPatternBackground extends StatelessWidget {
  const IslamicPatternBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _IslamicDotPatternPainter(
              color: MuslimColors.primary.withValues(alpha: 0.04),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}

class _IslamicDotPatternPainter extends CustomPainter {
  _IslamicDotPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 20.0;
    for (var y = 0.0; y < size.height; y += spacing) {
      for (var x = 0.0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MuslimScreenScaffold extends StatelessWidget {
  const MuslimScreenScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBack = true,
    this.onRefresh,
    this.actions,
  });

  final String title;
  final Widget body;
  final bool showBack;
  final Future<void> Function()? onRefresh;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? MuslimColors.surfaceDark : MuslimColors.surface;

    Widget content = IslamicPatternBackground(child: body);

    if (onRefresh != null) {
      content = RefreshIndicator(
        color: MuslimColors.primary,
        onRefresh: onRefresh!,
        child: content,
      );
    }

    return Material(
      color: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: Row(
                children: [
                  if (showBack) ...[
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.arrow_forward
                            : Icons.arrow_back,
                        color: isDark ? MuslimColors.onSurfaceDark : MuslimColors.primary,
                      ),
                    ),
                  ]
                  else
                    SizedBox(width: 48.w),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark ? MuslimColors.onSurfaceDark : MuslimColors.primary,
                      ),
                    ),
                  ),
                  if (actions != null && actions!.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: actions!)
                  else
                    SizedBox(width: 48.w),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

String formatPrayerLabel(String key) {
  if (key.isEmpty || key == 'none') return '';
  return key[0].toUpperCase() + key.substring(1);
}

String formatMinutesCountdown(int minutes) {
  if (minutes <= 0) return 'Now';
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String formatPrayerTime12h(String time24) {
  final parts = time24.split(':');
  if (parts.length < 2) return time24;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts[1];
  final period = hour >= 12 ? 'PM' : 'AM';
  final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$h12:$minute $period';
}
