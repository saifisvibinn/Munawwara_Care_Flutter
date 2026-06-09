import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Displays a phone number with forced LTR direction so + stays on the left.
class PhoneNumberText extends StatelessWidget {
  const PhoneNumberText(
    this.phoneNumber, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String phoneNumber;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Text(
        phoneNumber,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}
