import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

class MeccaHotspotsScreen extends StatefulWidget {
  const MeccaHotspotsScreen({super.key});

  @override
  State<MeccaHotspotsScreen> createState() => _MeccaHotspotsScreenState();
}

class _MeccaHotspotsScreenState extends State<MeccaHotspotsScreen> {
  int _selectedCategory = 0;

  static const _categories = [
    'All',
    'Food',
    'Pharmacy',
    'Landmarks',
    'Shopping',
  ];

  static const _hotspots = [
    _Hotspot(
      name: 'Al Baik - Ajyad',
      category: 'Food',
      distanceKm: 0.3,
      rating: 4.9,
      reviewCountLabel: '3.5k',
      icon: Symbols.restaurant,
      color: Color(0xFFE27D60),
    ),
    _Hotspot(
      name: 'McDonald\'s - Haram',
      category: 'Food',
      distanceKm: 0.5,
      rating: 4.7,
      reviewCountLabel: '2.1k',
      icon: Symbols.lunch_dining,
      color: Color(0xFFC44536),
    ),
    _Hotspot(
      name: 'Nahdi Pharmacy',
      category: 'Pharmacy',
      distanceKm: 0.2,
      rating: 4.5,
      reviewCountLabel: '980',
      icon: Symbols.local_pharmacy,
      color: Color(0xFF4F8A8B),
    ),
    _Hotspot(
      name: 'Abraj Al Bait Mall',
      category: 'Shopping',
      distanceKm: 0.4,
      rating: 4.6,
      reviewCountLabel: '1.8k',
      icon: Symbols.shopping_bag,
      color: Color(0xFF8D7A66),
    ),
    _Hotspot(
      name: 'Zamzam Well',
      category: 'Landmarks',
      distanceKm: 0.7,
      rating: 4.9,
      reviewCountLabel: '4.2k',
      icon: Symbols.mosque,
      color: Color(0xFF7DA0CA),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _categories[_selectedCategory];
    final filtered = selected == 'All'
        ? _hotspots
        : _hotspots.where((h) => h.category == selected).toList();

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF1F5F3),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        title: Text(
          'Mecca Hotspots',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 22.sp,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 20.h),
          child: Column(
            children: [
              Container(
                height: 52.h,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: const Color(0xFFE3E6E8)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 14.w),
                    Icon(
                      Symbols.search,
                      size: 28.w,
                      color: AppColors.textMutedLight,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        'Search hotspots...',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                    ),
                    Container(
                      height: 26.h,
                      width: 1,
                      color: const Color(0xFFE5E5E5),
                    ),
                    SizedBox(width: 12.w),
                    Icon(
                      Symbols.mic,
                      size: 24.w,
                      color: const Color(0xFFC88A44),
                    ),
                    SizedBox(width: 14.w),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              SizedBox(
                height: 42.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => SizedBox(width: 8.w),
                  itemBuilder: (context, index) {
                    final selectedChip = _selectedCategory == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        decoration: BoxDecoration(
                          color: selectedChip
                              ? const Color(0xFFE8EDF7)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(22.r),
                          border: Border.all(
                            color: selectedChip
                                ? const Color(0xFF2A2F5B)
                                : const Color(0xFFD9DFE5),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _categories[index],
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1D2244),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 14.h),
              Expanded(
                child: GridView.builder(
                  itemCount: filtered.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12.w,
                    mainAxisSpacing: 12.h,
                    childAspectRatio: 0.68,
                  ),
                  itemBuilder: (context, index) {
                    final hotspot = filtered[index];
                    return _HotspotCard(hotspot: hotspot, isDark: isDark);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hotspot {
  final String name;
  final String category;
  final double distanceKm;
  final double rating;
  final String reviewCountLabel;
  final IconData icon;
  final Color color;

  const _Hotspot({
    required this.name,
    required this.category,
    required this.distanceKm,
    required this.rating,
    required this.reviewCountLabel,
    required this.icon,
    required this.color,
  });
}

class _HotspotCard extends StatelessWidget {
  final _Hotspot hotspot;
  final bool isDark;

  const _HotspotCard({required this.hotspot, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 88.h,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.r),
                gradient: LinearGradient(
                  colors: [hotspot.color.withOpacity(0.85), hotspot.color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Icon(hotspot.icon, size: 40.w, color: Colors.white),
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              hotspot.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F132B),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              hotspot.category,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: AppColors.textMutedLight,
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${hotspot.distanceKm.toStringAsFixed(1)} km away',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF202545),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.star,
                      size: 16.w,
                      color: const Color(0xFFFFB638),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      '${hotspot.rating.toStringAsFixed(1)} (${hotspot.reviewCountLabel})',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF202545),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
