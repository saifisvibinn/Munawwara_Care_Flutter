import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

class ModeratorAvatar extends StatelessWidget {
  const ModeratorAvatar({
    super.key,
    this.size,
    this.initials,
  });

  final double? size;
  final String? initials;

  @override
  Widget build(BuildContext context) {
    final s = size ?? 56.w;
    return ClipOval(
      child: Image.asset(
        'assets/static/moderator_male.png',
        width: s,
        height: s,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          final i = (initials?.trim().isNotEmpty ?? false) ? initials! : '?';
          return Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                i,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: (s * 0.36).clamp(14.0, 30.0),
                  color: AppColors.primary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

