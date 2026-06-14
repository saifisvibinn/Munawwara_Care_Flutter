import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../router/app_router.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'app_selection_field.dart';
import 'standard_snackbar.dart';

class SupportDialogs {
  SupportDialogs._();

  static const String _keyHasRated = 'support_has_rated';
  static const String _keyLastPromptTime = 'support_last_rate_prompt_time';
  static const String _keyLastSubmitTime = 'support_last_submit_rating_time';

  /// Check if the contextual rating dialog should be shown.
  static Future<bool> shouldShowContextualRating() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. If user already rated, don't show contextual prompt again
      final hasRated = prefs.getBool(_keyHasRated) ?? false;
      if (hasRated) return false;
      
      // 2. Cooldown check: 7 days since last prompt
      final lastPromptMillis = prefs.getInt(_keyLastPromptTime) ?? 0;
      if (lastPromptMillis > 0) {
        final lastPrompt = DateTime.fromMillisecondsSinceEpoch(lastPromptMillis);
        final difference = DateTime.now().difference(lastPrompt);
        if (difference.inDays < 7) {
          return false;
        }
      }
      
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Check if the user is allowed to rate manually (limit to once every 24 hours).
  static Future<bool> canRateManually() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSubmitMillis = prefs.getInt(_keyLastSubmitTime) ?? 0;
      if (lastSubmitMillis > 0) {
        final lastSubmit = DateTime.fromMillisecondsSinceEpoch(lastSubmitMillis);
        final difference = DateTime.now().difference(lastSubmit);
        if (difference.inHours < 24) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Mark that a rating prompt has occurred just now (for cooldown).
  static Future<void> markRatingPrompted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastPromptTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Mark that the user has successfully rated the app.
  static Future<void> markHasRated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasRated, true);
    } catch (_) {}
  }

  /// Mark that the user has submitted a rating just now.
  static Future<void> markRatingSubmitted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastSubmitTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Shows contextual rating on a stable route after [popRoute] completes.
  static Future<void> showContextualRatingAfterPop({
    required Future<void> Function() popRoute,
    String contextualSource = 'post_call',
  }) async {
    await popRoute();
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showRating(
      ctx,
      isContextual: true,
      contextualSource: contextualSource,
    );
  }

  static Future<void> showRating(
    BuildContext context, {
    bool isContextual = false,
    String contextualSource = 'post_call',
  }) async {
    if (isContextual) {
      final shouldShow = await shouldShowContextualRating();
      if (!shouldShow) return;
      await markRatingPrompted();
    } else {
      // Manual trigger: limit to once every 24 hours
      final canRate = await canRateManually();
      if (!canRate) {
        if (context.mounted) {
          StandardSnackBar.showWarning(
            context,
            'rate_already_submitted_today'.tr(),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) => AppRatingDialog(
        source: isContextual ? contextualSource : 'settings',
      ),
    );
  }

  static void showFeedback(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AppFeedbackDialog(),
    );
  }

  static void showReport(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ReportIssueDialog(),
    );
  }
}

// ── RATING DIALOG ────────────────────────────────────────────────────────────
class AppRatingDialog extends StatefulWidget {
  final String source;
  const AppRatingDialog({super.key, this.source = 'settings'});

  @override
  State<AppRatingDialog> createState() => _AppRatingDialogState();
}

class _AppRatingDialogState extends State<AppRatingDialog> {
  int _selectedRating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _showStorePrompt = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback({String? finalComments}) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      await ApiService.dio.post('/support/feedback', data: {
        'rating': _selectedRating,
        'comments': finalComments ?? _commentController.text.trim(),
        'source': widget.source,
      });

      await SupportDialogs.markHasRated();
      await SupportDialogs.markRatingSubmitted();

      if (mounted) {
        Navigator.pop(context);
        StandardSnackBar.showSuccess(
          context,
          'feedback_submit_success'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'error_general'.tr(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  /// Records that the user opened the store listing — suppress future prompts.
  Future<void> _openStoreListing() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    await SupportDialogs.markHasRated();
    await SupportDialogs.markRatingSubmitted();

    final storeLabel = Platform.isIOS ? 'App Store' : 'Play Store';
    unawaited(() async {
      try {
        await ApiService.dio.post('/support/feedback', data: {
          'rating': _selectedRating,
          'comments': 'User opened $storeLabel listing.',
          'source': widget.source,
        });
      } catch (_) {}
    }());

    if (!mounted) return;
    Navigator.pop(context);

    try {
      if (Platform.isIOS) {
        final inAppReview = InAppReview.instance;
        if (await inAppReview.isAvailable()) {
          await inAppReview.requestReview();
        }
      } else {
        final packageName = (await PackageInfo.fromPlatform()).packageName;
        final marketUri = Uri.parse('market://details?id=$packageName');
        final webUri = Uri.parse(
          'https://play.google.com/store/apps/details?id=$packageName',
        );
        if (await canLaunchUrl(marketUri)) {
          await launchUrl(marketUri);
        } else {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {
      // Store opened or not — user already marked as rated.
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return AlertDialog(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      contentPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
      content: SizedBox(
        width: 320.w,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _showStorePrompt ? Icons.thumb_up_alt_rounded : Icons.star_rate_rounded,
                  color: AppColors.primary,
                  size: 24.sp,
                ),
              ),
              SizedBox(height: 16.h),

              if (!_showStorePrompt) ...[
                // Initial Rating Screen
                Text(
                  'rate_app_title'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'rate_app_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: 16.h),

                // Star Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starIndex = index + 1;
                    final isSelected = starIndex <= _selectedRating;
                    return IconButton(
                      icon: Icon(
                        isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isSelected ? Colors.amber : textMuted,
                        size: 36.sp,
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedRating = starIndex;
                          // If 4-5 stars, directly show App Store prompt
                          if (starIndex >= 4) {
                            _showStorePrompt = true;
                          }
                        });
                      },
                    );
                  }),
                ),

                // If 1-3 stars selected, show comment field
                if (_selectedRating > 0 && _selectedRating <= 3) ...[
                  SizedBox(height: 16.h),
                  TextField(
                    controller: _commentController,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'rate_improve_feedback_hint'.tr(),
                      hintStyle: TextStyle(
                        fontSize: 13.sp,
                        color: textMuted,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: EdgeInsets.all(12.w),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                          ),
                          child: Text(
                            'dialog_cancel'.tr(),
                            style: TextStyle( color: textPrimary),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : () => _submitFeedback(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                          ),
                          child: _isSubmitting
                              ? SizedBox(
                                  width: 16.w,
                                  height: 16.w,
                                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'btn_submit'.tr(),
                                  style: TextStyle( color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // If rating not chosen yet, just show skippable option
                  SizedBox(height: 16.h),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'rate_skip'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                  ),
                ],
              ] else ...[
                // Store Review Prompt Screen
                Text(
                  'rate_app_store_title'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'rate_app_store_body'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: 20.h),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        child: Text(
                          'rate_skip'.tr(),
                          style: TextStyle( color: textPrimary),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _openStoreListing,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                        ),
                        child: _isSubmitting
                            ? SizedBox(
                                width: 16.w,
                                height: 16.w,
                                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                'rate_store_action'.tr(),
                                style: TextStyle( color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── GENERAL FEEDBACK DIALOG ──────────────────────────────────────────────────
class AppFeedbackDialog extends StatefulWidget {
  const AppFeedbackDialog({super.key});

  @override
  State<AppFeedbackDialog> createState() => _AppFeedbackDialogState();
}

class _AppFeedbackDialogState extends State<AppFeedbackDialog> {
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ApiService.dio.post('/support/feedback', data: {
        'comments': text,
        'source': 'settings',
      });

      if (mounted) {
        Navigator.pop(context);
        StandardSnackBar.showSuccess(
          context,
          'feedback_submit_success'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'error_general'.tr(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return AlertDialog(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      contentPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
      content: SizedBox(
        width: 320.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 48.w,
              height: 48.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.rate_review_outlined, color: AppColors.primary, size: 24.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              'feedback_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18.sp,
                color: textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'feedback_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: textMuted,
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: _commentController,
              maxLines: 4,
              style: TextStyle(
                fontSize: 14.sp,
                color: textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'feedback_hint'.tr(),
                hintStyle: TextStyle(
                  fontSize: 13.sp,
                  color: textMuted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.r),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                contentPadding: EdgeInsets.all(12.w),
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: Text(
                      'dialog_cancel'.tr(),
                      style: TextStyle( color: textPrimary),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : () => _submitFeedback(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            width: 16.w,
                            height: 16.w,
                            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'btn_submit'.tr(),
                            style: TextStyle( color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── REPORT INCIDENT DIALOG ───────────────────────────────────────────────────
class ReportIssueDialog extends StatefulWidget {
  const ReportIssueDialog({super.key});

  @override
  State<ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends State<ReportIssueDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'medical';
  bool _isSubmitting = false;

  final _categories = const [
    {'value': 'medical', 'labelKey': 'report_cat_medical'},
    {'value': 'security', 'labelKey': 'report_cat_security'},
    {'value': 'transportation', 'labelKey': 'report_cat_transportation'},
    {'value': 'hotel', 'labelKey': 'report_cat_hotel'},
    {'value': 'technical', 'labelKey': 'report_cat_technical'},
    {'value': 'other', 'labelKey': 'report_cat_other'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    if (title.isEmpty || description.isEmpty) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await ApiService.dio.post('/support/report', data: {
        'category': _selectedCategory,
        'title': title,
        'description': description,
      });

      if (mounted) {
        Navigator.pop(context);
        StandardSnackBar.showSuccess(
          context,
          'report_submit_success'.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'error_general'.tr(),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return AlertDialog(
      backgroundColor: cardBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      contentPadding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
      content: SizedBox(
        width: 320.w,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 48.w,
                height: 48.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.report_problem_outlined, color: AppColors.primary, size: 24.sp),
              ),
              SizedBox(height: 16.h),
              Text(
                'report_title'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 16.h),

              // Category dropdown
              AppSelectionFormField<String>(
                initialValue: _selectedCategory,
                isDark: Theme.of(context).brightness == Brightness.dark,
                label: 'report_category'.tr(),
                sheetTitle: 'report_category'.tr(),
                decoration: InputDecoration(
                  labelText: 'report_category'.tr(),
                  labelStyle: TextStyle(color: textMuted, fontSize: 13.sp),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                ),
                options: _categories
                    .map(
                      (cat) => AppSelectionOption(
                        value: cat['value']!,
                        label: cat['labelKey']!.tr(),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCategory = val);
                  }
                },
              ),
              SizedBox(height: 14.h),

              // Title field
              TextField(
                controller: _titleController,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'report_subject'.tr(),
                  labelStyle: TextStyle( color: textMuted, fontSize: 13.sp),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                  contentPadding: EdgeInsets.all(12.w),
                ),
              ),
              SizedBox(height: 14.h),

              // Description field
              TextField(
                controller: _descController,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'report_description'.tr(),
                  labelStyle: TextStyle( color: textMuted, fontSize: 13.sp),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                  contentPadding: EdgeInsets.all(12.w),
                ),
              ),
              SizedBox(height: 20.h),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                      child: Text(
                        'dialog_cancel'.tr(),
                        style: TextStyle( color: textPrimary),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : () => _submitReport(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'btn_submit'.tr(),
                              style: TextStyle( color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
