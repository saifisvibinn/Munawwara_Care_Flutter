import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/theme/app_colors.dart';
import '../../shared/models/suggested_area_model.dart';
import '../../shared/widgets/area_ui_widgets.dart';

class ActiveMeetpointCard extends StatelessWidget {
  const ActiveMeetpointCard({
    super.key,
    required this.activeMp,
    required this.isDark,
    required this.onDelete,
    this.onTap,
  });

  final SuggestedArea activeMp;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isExpired =
        activeMp.meetpointTime != null &&
        DateTime.now().isAfter(
          activeMp.meetpointTime!.add(SuggestedArea.meetpointExpiryWindow),
        );
    final accent = AreaUiTheme.accent(isDark, isMeetpoint: true);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return AreaInsetGroup(
      isDark: isDark,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
              child: Row(
                children: [
                  Icon(Symbols.crisis_alert, color: accent, size: 22.w, fill: 1),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (isExpired ? 'status_expired' : 'area_meetpoint').tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                            color: accent,
                          ),
                        ),
                        Text(
                          activeMp.name,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 15.sp,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (activeMp.meetpointTime != null)
                          Text(
                            '${DateFormat('MMM dd').format(activeMp.meetpointTime!)} @ ${DateFormat('hh:mm a').format(activeMp.meetpointTime!)}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: AreaUiTheme.sectionLabel(isDark),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Symbols.delete, color: accent, size: 20.w),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
