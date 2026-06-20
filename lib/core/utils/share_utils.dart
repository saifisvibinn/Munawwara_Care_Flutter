import 'package:flutter/material.dart';

/// Anchor rect for [Share.share] / [Share.shareXFiles] on iOS (required on iPad).
///
/// Pass the [BuildContext] of the share button (or another visible anchor widget).
Rect sharePositionOriginFor(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    final size = renderObject.size;
    if (size.width > 0 && size.height > 0) {
      return renderObject.localToGlobal(Offset.zero) & size;
    }
  }

  final mediaSize = MediaQuery.sizeOf(context);
  return Rect.fromCenter(
    center: Offset(mediaSize.width / 2, mediaSize.height / 2),
    width: 1,
    height: 1,
  );
}
