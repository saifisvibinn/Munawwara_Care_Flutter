import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../widgets/call_history_list_view.dart';

/// Lists recent voice calls from `GET /call-history` (moderator + pilgrim).
/// Set [missedOnly] to show only missed rows and to clear unread badge when opened.
class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key, this.missedOnly = false});

  final bool missedOnly;

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    
    final title = widget.missedOnly
        ? 'missed_calls_title'.tr()
        : 'call_history_title'.tr();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 18.sp,
            color: textPrimary,
          ),
        ),
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        actions: [
          if (widget.missedOnly)
            TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const CallHistoryScreen(),
                  ),
                );
              },
              child: Text(
                'missed_calls_see_all'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: CallHistoryListView(
        key: _refreshKey,
        missedOnly: widget.missedOnly,
      ),
    );
  }
}
