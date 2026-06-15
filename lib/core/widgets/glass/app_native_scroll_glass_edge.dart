import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native iOS scroll-edge band using [UIVisualEffectView] — same material as MapKit.
class AppNativeScrollGlassEdge extends StatelessWidget {
  const AppNativeScrollGlassEdge({
    super.key,
    required this.height,
    required this.fadesFromTop,
    required this.isDark,
  });

  static const String viewType = 'MunawwaraScrollEdgeBlur';

  final double height;
  final bool fadesFromTop;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: UiKitView(
        key: ValueKey('${fadesFromTop ? 'top' : 'bottom'}-$isDark'),
        viewType: viewType,
        creationParams: <String, dynamic>{
          'isDark': isDark,
          'fadesFromTop': fadesFromTop,
        },
        creationParamsCodec: const StandardMessageCodec(),
        layoutDirection: Directionality.of(context),
      ),
    );
  }
}
