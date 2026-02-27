import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Create Group Screen
// ─────────────────────────────────────────────────────────────────────────────

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  String? _fieldError;

  // Shown after success
  bool _created = false;
  String? _createdGroupCode;
  String? _createdGroupName;

  late AnimationController _successAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _successAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(
      parent: _successAnim,
      curve: Curves.elasticOut,
    );
    _nameController.addListener(() {
      if (_fieldError != null) setState(() => _fieldError = null);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _successAnim.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.length < 3) {
      setState(() => _fieldError = 'create_group_name_error'.tr());
      return;
    }
    setState(() => _isLoading = true);
    final (ok, err) = await ref
        .read(moderatorProvider.notifier)
        .createGroup(name);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      // Find the newly added group (last one)
      final groups = ref.read(moderatorProvider).groups;
      final newGroup = groups.isNotEmpty ? groups.last : null;
      setState(() {
        _created = true;
        _createdGroupCode = newGroup?.groupCode ?? '------';
        _createdGroupName = name;
      });
      _successAnim.forward();
    } else {
      setState(() => _fieldError = err ?? 'create_group_error_generic'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 42.w,
                      height: 42.w,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF272210) : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF383018)
                              : const Color(0xFFE2E2F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Symbols.arrow_back,
                        size: 20.w,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 32.h),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _created ? _buildSuccess(isDark) : _buildForm(isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Form view ──────────────────────────────────────────────────────────────

  Widget _buildForm(bool isDark) {
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: 64.w,
          height: 64.w,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Icon(Symbols.group_add, size: 32.w, color: AppColors.primary),
        ),

        SizedBox(height: 20.h),

        Text(
          'create_group_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 26.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),

        SizedBox(height: 6.h),

        Text(
          'create_group_subtitle'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13.sp,
            color: AppColors.textMutedLight,
            height: 1.5,
          ),
        ),

        SizedBox(height: 32.h),

        // ── Group name field ──
        Text(
          'create_group_name'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 13.sp,
            color: isDark ? const Color(0xFFCBD5E1) : AppColors.textDark,
          ),
        ),

        SizedBox(height: 8.h),

        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF272210) : Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: _fieldError != null
                  ? Colors.red.shade400
                  : (_focusNode.hasFocus
                        ? AppColors.primary
                        : (isDark
                              ? const Color(0xFF383018)
                              : const Color(0xFFE2E2F0))),
              width: _focusNode.hasFocus ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _focusNode.hasFocus
                    ? AppColors.primary.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _nameController,
            focusNode: _focusNode,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 15.sp,
              color: isDark ? const Color(0xFFE2E8F0) : AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: 'create_group_name_hint'.tr(),
              hintStyle: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 15.sp,
                color: AppColors.textMutedLight,
              ),
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 14.w, right: 8.w),
                child: Icon(
                  Symbols.group,
                  size: 22.w,
                  color: _focusNode.hasFocus
                      ? AppColors.primary
                      : AppColors.textMutedLight,
                ),
              ),
              prefixIconConstraints: BoxConstraints(minWidth: 46.w),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                vertical: 16.h,
                horizontal: 14.w,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),

        if (_fieldError != null) ...[
          SizedBox(height: 6.h),
          Row(
            children: [
              Icon(Symbols.error, size: 14.w, color: Colors.red.shade500),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  _fieldError!,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: Colors.red.shade500,
                  ),
                ),
              ),
            ],
          ),
        ],

        SizedBox(height: 24.h),

        // ── Info card ──
        Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Symbols.info, size: 18.w, color: AppColors.primary, fill: 1),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'create_group_qr_info'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: isDark
                        ? const Color(0xFF86EFAC)
                        : AppColors.primaryDark,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: 36.h),

        // ── Create button ──
        SizedBox(
          width: double.infinity,
          height: 54.h,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
            ),
            child: _isLoading
                ? SizedBox(
                    width: 22.w,
                    height: 22.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Symbols.add, size: 20.w),
                      SizedBox(width: 8.w),
                      Text(
                        'create_group_btn'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 15.sp,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Success view ───────────────────────────────────────────────────────────

  Widget _buildSuccess(bool isDark) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Column(
        key: const ValueKey('success'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 20.h),

          // Big success icon
          Container(
            width: 80.w,
            height: 80.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Symbols.check_circle,
              size: 40.w,
              color: AppColors.primary,
              fill: 1,
            ),
          ),

          SizedBox(height: 20.h),

          Text(
            'create_group_success_title'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 24.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),

          SizedBox(height: 8.h),

          Text(
            _createdGroupName ?? '',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 15.sp,
              color: AppColors.textMutedLight,
            ),
          ),

          SizedBox(height: 32.h),

          // Group code card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF272210) : Colors.white,
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF383018)
                    : const Color(0xFFEEEEF8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'create_group_code_label'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 11.sp,
                    color: AppColors.textMutedLight,
                    letterSpacing: 1.5,
                  ),
                ),

                SizedBox(height: 12.h),

                // Code display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _createdGroupCode ?? '',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 36.sp,
                        color: AppColors.primary,
                        letterSpacing: 8,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16.h),

                // Copy button
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _createdGroupCode ?? ''),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'create_group_code_copied'.tr(),
                          style: const TextStyle(fontFamily: 'Lexend'),
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.primaryDark,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 18.w,
                      vertical: 10.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.content_copy,
                          size: 16.w,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          'create_group_copy_code'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 13.sp,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 14.h),

                Text(
                  'create_group_code_info'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: AppColors.textMutedLight,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 32.h),

          // Done button
          SizedBox(
            width: double.infinity,
            height: 54.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
              ),
              child: Text(
                'create_group_back'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

