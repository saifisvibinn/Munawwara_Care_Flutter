import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

class FaqItem {
  final String categoryKey;
  final String questionKey;
  final String answerKey;

  const FaqItem({
    required this.categoryKey,
    required this.questionKey,
    required this.answerKey,
  });
}

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';

  final List<FaqItem> _faqItems = const [
    FaqItem(
      categoryKey: 'general',
      questionKey: 'faq_q_general_app',
      answerKey: 'faq_a_general_app',
    ),
    FaqItem(
      categoryKey: 'general',
      questionKey: 'faq_q_general_offline',
      answerKey: 'faq_a_general_offline',
    ),
    FaqItem(
      categoryKey: 'sos',
      questionKey: 'faq_q_sos_trigger',
      answerKey: 'faq_a_sos_trigger',
    ),
    FaqItem(
      categoryKey: 'sos',
      questionKey: 'faq_q_sos_process',
      answerKey: 'faq_a_sos_process',
    ),
    FaqItem(
      categoryKey: 'map',
      questionKey: 'faq_q_map_location',
      answerKey: 'faq_a_map_location',
    ),
    FaqItem(
      categoryKey: 'map',
      questionKey: 'faq_q_map_pilgrims',
      answerKey: 'faq_a_map_pilgrims',
    ),
    FaqItem(
      categoryKey: 'chat',
      questionKey: 'faq_q_chat_contact',
      answerKey: 'faq_a_chat_contact',
    ),
    FaqItem(
      categoryKey: 'chat',
      questionKey: 'faq_q_chat_calls',
      answerKey: 'faq_a_chat_calls',
    ),
  ];

  final List<Map<String, String>> _categories = const [
    {'key': 'all', 'labelKey': 'faq_category_all'},
    {'key': 'general', 'labelKey': 'faq_category_general'},
    {'key': 'sos', 'labelKey': 'faq_category_sos'},
    {'key': 'map', 'labelKey': 'faq_category_map'},
    {'key': 'chat', 'labelKey': 'faq_category_chat'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    // Filter FAQs based on selected category & search query
    final filteredItems = _faqItems.where((item) {
      final matchesCategory = _selectedCategory == 'all' || item.categoryKey == _selectedCategory;
      if (!matchesCategory) return false;

      if (_searchQuery.isEmpty) return true;

      final question = item.questionKey.tr().toLowerCase();
      final answer = item.answerKey.tr().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return question.contains(query) || answer.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'faq_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
            child: Container(
              height: 48.h,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  color: textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'faq_search_hint'.tr(),
                  hintStyle: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: textMuted,
                    size: 20.sp,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: textMuted, size: 18.sp),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),
          ),

          // Categories Horizontal List
          SizedBox(
            height: 38.h,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat['key'];
                return Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat['key']!;
                      });
                    },
                    borderRadius: BorderRadius.circular(20.r),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cat['labelKey']!.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 12.sp,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.textLight : AppColors.textDark),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 12.h),

          // FAQ List
          Expanded(
            child: filteredItems.isEmpty
                ? _buildEmptyState(textMuted)
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _FaqTile(
                        item: item,
                        isDark: isDark,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textMuted) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.help_outline_rounded,
            size: 64.sp,
            color: textMuted.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            'error_general'.tr(), // Fallback descriptive text if needed or simple "No results"
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final FaqItem item;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;

  const _FaqTile({
    required this.item,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDark ? AppColors.surfaceDark : Colors.white;
    final dividerColor = widget.isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(12.r),
            child: Padding(
              padding: EdgeInsets.all(16.w),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.questionKey.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: widget.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  RotationTransition(
                    turns: Tween<double>(begin: 0, end: 0.5).animate(_controller),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: widget.textMuted,
                      size: 22.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: dividerColor,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Text(
                    widget.item.answerKey.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w400,
                      fontSize: 13.sp,
                      color: widget.textMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
