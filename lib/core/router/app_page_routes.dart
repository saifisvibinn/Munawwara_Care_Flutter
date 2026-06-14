import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Push route for full-bleed map screens (MapKit on iOS).
///
/// Interactive back-swipe is disabled on iOS: MapKit platform views and
/// [CupertinoPageRoute] edge gestures conflict and freeze mid-transition.
/// Use the screen back button instead; map pan/zoom stays responsive.
Route<T> appMapPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  if (!kIsWeb && Platform.isIOS) {
    return _AppMapPageRoute<T>(
      settings: settings,
      builder: builder,
    );
  }
  return MaterialPageRoute<T>(
    settings: settings,
    builder: builder,
  );
}

class _AppMapPageRoute<T> extends CupertinoPageRoute<T> {
  _AppMapPageRoute({
    required super.builder,
    super.settings,
  });

  @override
  bool get popGestureEnabled => false;
}
