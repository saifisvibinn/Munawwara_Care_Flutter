import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../utils/muslim_localization.dart';

/// Forward navigation chevron. Uses [Symbols.chevron_right] only; the glyph
/// already has [IconData.matchTextDirection] so manual left/right swaps flip
/// twice in Arabic/Urdu and point the wrong way.
Widget muslimForwardChevron({double? size, Color? color}) {
  return Icon(
    Symbols.chevron_right,
    size: size,
    color: color,
  );
}

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
    final base = style ?? TextStyle(fontSize: 20.sp);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        style: base.copyWith(
          fontFamily: 'Amiri',
          height: 1.8,
          color: base.color ?? context.mArabicText,
        ),
      ),
    );
  }
}

TextStyle muslimArabicStyle(
  BuildContext context, {
  double? fontSize,
  Color? color,
  FontWeight fontWeight = FontWeight.w400,
}) {
  return TextStyle(
    fontFamily: 'Amiri',
    fontSize: fontSize ?? 20.sp,
    color: color ?? context.mArabicText,
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
              color: context.mPrimary.withValues(alpha: 0.04),
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
    final bg = context.mSurface;

    Widget content = IslamicPatternBackground(child: body);

    if (onRefresh != null) {
      content = RefreshIndicator(
        color: context.mPrimary,
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
                        Icons.arrow_back,
                        color: context.mPrimary,
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
                        color: context.mPrimary,
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

String formatPrayerLabel(String key) => localizedPrayerName(key);

String formatMinutesCountdown(int minutes) =>
    formatMinutesCountdownLocalized(minutes);

String formatPrayerTime12h(String time24, Locale locale) =>
    formatPrayerTimeLocalized(time24, locale);
