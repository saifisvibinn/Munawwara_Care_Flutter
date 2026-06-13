import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

class ModeratorAvatar extends StatelessWidget {
  const ModeratorAvatar({
    super.key,
    this.size,
    this.initials,
    this.imageUrl,
  });

  final double? size;
  final String? initials;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final s = size ?? 56.w;
    final fallbackWidget = Image.asset(
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
                fontWeight: FontWeight.w700,
                fontSize: (s * 0.36).clamp(14.0, 30.0),
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );

    return ClipOval(
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              width: s,
              height: s,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallbackWidget,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return SizedBox(
                  width: s,
                  height: s,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            )
          : fallbackWidget,
    );
  }
}

