import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../notifications/screens/alerts_tab_v2.dart';

/// Bell icon center on the Groups tab header (matches layout constants).
Offset moderatorBellRevealOrigin(BuildContext context) {
  final media = MediaQuery.of(context);
  final isRtl = Directionality.of(context) == TextDirection.rtl;
  const bellSize = 44.0;
  final horizontalInset = 20.w + bellSize / 2;
  final centerX = isRtl
      ? horizontalInset
      : media.size.width - horizontalInset;
  final centerY = media.padding.top + 16.h + bellSize / 2;
  return Offset(centerX, centerY);
}

double _maxRevealRadius(Offset origin, Size size) {
  final corners = <Offset>[
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ];
  return corners
      .map((corner) => (corner - origin).distance)
      .reduce(math.max);
}

/// Circular reveal route for moderator alerts (bell icon, top-trailing).
Route<void> buildModeratorAlertsRevealRoute(BuildContext context) {
  final origin = moderatorBellRevealOrigin(context);

  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (ctx, _, _) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xfff1f5f3),
        body: SafeArea(
          child: AlertsTab(
            onBack: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    },
    transitionsBuilder: (ctx, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      );
      return AnimatedBuilder(
        animation: curve,
        builder: (context, _) {
          final size = MediaQuery.sizeOf(context);
          final radius = _maxRevealRadius(origin, size) * curve.value;
          return ClipPath(
            clipper: _CircleRevealClipper(
              origin: origin,
              radius: radius,
            ),
            child: child,
          );
        },
        child: child,
      );
    },
  );
}

/// Pushes moderator alerts with a circular reveal from the bell position.
void openModeratorAlertsWithReveal(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    buildModeratorAlertsRevealRoute(context),
  );
}

class _CircleRevealClipper extends CustomClipper<Path> {
  const _CircleRevealClipper({
    required this.origin,
    required this.radius,
  });

  final Offset origin;
  final double radius;

  @override
  Path getClip(Size size) {
    return Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) {
    return oldClipper.origin != origin || oldClipper.radius != radius;
  }
}
