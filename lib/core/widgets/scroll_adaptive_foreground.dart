import 'package:flutter/material.dart';

/// One vertical slice of scrollable content used to estimate the backdrop
/// color behind a fixed header band.
class ScrollBackdropSegment {
  const ScrollBackdropSegment({
    required this.height,
    required this.color,
    this.gapAfter = 0,
  });

  final double height;
  final Color color;
  final double gapAfter;
}

/// Returns the fraction of [bandTop]–[bandBottom] covered by [segmentTop]–[segmentBottom].
double _verticalOverlapFraction({
  required double bandTop,
  required double bandBottom,
  required double segmentTop,
  required double segmentBottom,
}) {
  final bandHeight = bandBottom - bandTop;
  if (bandHeight <= 0) return 0;

  final overlapTop = bandTop > segmentTop ? bandTop : segmentTop;
  final overlapBottom = bandBottom < segmentBottom ? bandBottom : segmentBottom;
  final overlap = overlapBottom - overlapTop;
  if (overlap <= 0) return 0;

  return (overlap / bandHeight).clamp(0.0, 1.0);
}

/// Estimates the blended background color behind a fixed header band by walking
/// ordered [segments] and lerping each segment's color based on vertical overlap.
Color estimateBackdropColor({
  required double scrollOffset,
  required double listPaddingTop,
  required double bandTop,
  required double bandBottom,
  required Color fallbackColor,
  required List<ScrollBackdropSegment> segments,
}) {
  var backdrop = fallbackColor;

  var contentCursor = 0.0;
  for (final segment in segments) {
    final segmentTopOnScreen = listPaddingTop + contentCursor - scrollOffset;
    final segmentBottomOnScreen = segmentTopOnScreen + segment.height;

    final overlap = _verticalOverlapFraction(
      bandTop: bandTop,
      bandBottom: bandBottom,
      segmentTop: segmentTopOnScreen,
      segmentBottom: segmentBottomOnScreen,
    );

    if (overlap > 0) {
      backdrop = Color.lerp(backdrop, segment.color, overlap) ?? backdrop;
    }

    contentCursor += segment.height + segment.gapAfter;
  }

  return backdrop;
}

/// Picks a contrasting foreground color for [background] using luminance.
Color foregroundOnBackground(
  BuildContext context,
  Color background, {
  Color? preferredLight,
  Color? preferredDark,
  double luminanceThreshold = 0.45,
}) {
  final scheme = Theme.of(context).colorScheme;
  final onLight = preferredLight ?? scheme.onSurface;
  final onDark = preferredDark ?? scheme.onPrimary;

  return background.computeLuminance() > luminanceThreshold ? onLight : onDark;
}

/// Fixed header text whose color adapts to the scroll content behind it.
class ScrollAdaptiveText extends StatefulWidget {
  const ScrollAdaptiveText({
    super.key,
    required this.controller,
    required this.text,
    required this.style,
    required this.resolveBackground,
    this.textAlign,
    this.preferredLight,
    this.preferredDark,
    this.animationDuration = const Duration(milliseconds: 220),
    this.animationCurve = Curves.easeInOut,
  });

  final ScrollController controller;
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final Color Function(double scrollOffset) resolveBackground;
  final Color? preferredLight;
  final Color? preferredDark;
  final Duration animationDuration;
  final Curve animationCurve;

  @override
  State<ScrollAdaptiveText> createState() => _ScrollAdaptiveTextState();
}

class _ScrollAdaptiveTextState extends State<ScrollAdaptiveText> {
  Color? _foregroundColor;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateForegroundColor();
  }

  @override
  void didUpdateWidget(ScrollAdaptiveText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (oldWidget.resolveBackground != widget.resolveBackground ||
        oldWidget.preferredLight != widget.preferredLight ||
        oldWidget.preferredDark != widget.preferredDark) {
      _updateForegroundColor();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _updateForegroundColor();
  }

  Color _computeForegroundColor() {
    final offset =
        widget.controller.hasClients ? widget.controller.offset : 0.0;
    final background = widget.resolveBackground(offset);
    return foregroundOnBackground(
      context,
      background,
      preferredLight: widget.preferredLight,
      preferredDark: widget.preferredDark,
    );
  }

  void _updateForegroundColor() {
    if (!mounted) return;
    final next = _computeForegroundColor();
    final current = _foregroundColor;
    if (current != null && _colorsMatch(current, next)) return;
    setState(() => _foregroundColor = next);
  }

  bool _colorsMatch(Color a, Color b) {
    return a.toARGB32() == b.toARGB32();
  }

  @override
  Widget build(BuildContext context) {
    final color = _foregroundColor ??
        foregroundOnBackground(
          context,
          widget.resolveBackground(
            widget.controller.hasClients ? widget.controller.offset : 0.0,
          ),
          preferredLight: widget.preferredLight,
          preferredDark: widget.preferredDark,
        );

    return AnimatedDefaultTextStyle(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      style: widget.style.copyWith(color: color),
      child: Text(
        widget.text,
        textAlign: widget.textAlign,
      ),
    );
  }
}

/// Reports the rendered size of [child] after layout.
class MeasureSize extends StatefulWidget {
  const MeasureSize({
    super.key,
    required this.onChange,
    required this.child,
  });

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
  }

  void _reportSize() {
    if (!mounted) return;
    final size = context.size;
    if (size == null || size == _oldSize) return;
    _oldSize = size;
    widget.onChange(size);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: widget.child,
      ),
    );
  }
}
