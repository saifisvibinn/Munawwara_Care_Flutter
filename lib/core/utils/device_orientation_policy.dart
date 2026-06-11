import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Logical width threshold for large-screen devices (tablets, foldables).
const double kLargeScreenShortestSide = 600;

/// Locks portrait on phones; allows rotation on large screens per Android 16
/// large-screen policy.
Future<void> applyDeviceOrientationPolicy() async {
  final FlutterView view =
      WidgetsBinding.instance.platformDispatcher.views.first;
  final double logicalWidth = view.physicalSize.width / view.devicePixelRatio;
  final double logicalHeight = view.physicalSize.height / view.devicePixelRatio;
  final double shortestSide = logicalWidth < logicalHeight
      ? logicalWidth
      : logicalHeight;

  if (shortestSide < kLargeScreenShortestSide) {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return;
  }

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}
