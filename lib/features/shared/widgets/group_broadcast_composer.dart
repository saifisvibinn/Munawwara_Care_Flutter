import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dropdown_theme.dart';
import '../../../core/widgets/glass/app_glass.dart';
import 'group_chat_theme.dart';

/// Moderator bottom toolbar for group broadcasts (urgent + WhatsApp-style input).
class GroupBroadcastComposer extends StatelessWidget {
  const GroupBroadcastComposer({
    super.key,
    required this.isDark,
    required this.isUrgent,
    required this.onUrgentChanged,
    required this.textController,
    required this.isSending,
    required this.onSendTts,
    required this.onMicTap,
    required this.showVoiceInput,
    required this.voiceInput,
    this.replyStrip,
  });

  final bool isDark;
  final bool isUrgent;
  final ValueChanged<bool> onUrgentChanged;
  final TextEditingController textController;
  final bool isSending;
  final VoidCallback onSendTts;
  final VoidCallback onMicTap;
  final bool showVoiceInput;
  final Widget voiceInput;
  final Widget? replyStrip;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final urgentColor = GroupChatTheme.urgentAccentBar;
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardBottom > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardBottom),
      child: AppGlassSurface(
        isDark: isDark,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 0),
        child: SafeArea(
          top: false,
          bottom: !keyboardOpen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?replyStrip,
              Row(
                children: [
                  Icon(
                    Symbols.warning,
                    size: 18.sp,
                    color: isUrgent ? urgentColor : textMuted,
                  ),
                  SizedBox(width: 6.w),
                  Expanded(
                    child: Text(
                      'msg_urgent'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.sp,
                        color: isUrgent ? urgentColor : textPrimary,
                      ),
                    ),
                  ),
                  CupertinoSwitch(
                    value: isUrgent,
                    activeTrackColor: urgentColor,
                    onChanged: onUrgentChanged,
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              if (showVoiceInput)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: voiceInput,
                )
              else
                _WhatsAppInputRow(
                  isDark: isDark,
                  textController: textController,
                  isSending: isSending,
                  isUrgent: isUrgent,
                  onSend: onSendTts,
                  onMicTap: onMicTap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhatsAppInputRow extends StatelessWidget {
  const _WhatsAppInputRow({
    required this.isDark,
    required this.textController,
    required this.isSending,
    required this.isUrgent,
    required this.onSend,
    required this.onMicTap,
  });

  final bool isDark;
  final TextEditingController textController;
  final bool isSending;
  final bool isUrgent;
  final VoidCallback onSend;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final fill = AppDropdownTheme.fieldFillNested(isDark);
    final outline = AppDropdownTheme.fieldBorder(isDark);
    final sendColor = isUrgent
        ? GroupChatTheme.urgentAccentBar
        : AppColors.primary;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: outline),
              ),
              child: TextField(
                controller: textController,
                maxLines: 4,
                minLines: 1,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'msg_hint_tts'.tr(),
                  hintStyle: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    color: muted,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 10.h,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          SizedBox(
            width: 44.w,
            height: 44.w,
            child: ListenableBuilder(
              listenable: textController,
              builder: (context, _) {
                final hasText = textController.text.trim().isNotEmpty;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: hasText
                      ? _ActionButton(
                          key: const ValueKey('send'),
                          icon: Symbols.send,
                          color: isSending ? AppColors.textMutedLight : sendColor,
                          onTap: isSending ? null : onSend,
                          isLoading: isSending,
                        )
                      : _ActionButton(
                          key: const ValueKey('mic'),
                          icon: Symbols.mic,
                          color: AppColors.primary,
                          onTap: isSending ? null : onMicTap,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22.r),
        child: Ink(
          width: 44.w,
          height: 44.w,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22.r),
          ),
          child: isLoading
              ? Padding(
                  padding: EdgeInsets.all(12.w),
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(icon, size: 20.w, color: Colors.white),
        ),
      ),
    );
  }
}
