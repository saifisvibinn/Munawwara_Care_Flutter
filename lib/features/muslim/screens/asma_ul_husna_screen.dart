import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../widgets/muslim_widgets.dart';

class AsmaUlHusnaScreen extends ConsumerStatefulWidget {
  const AsmaUlHusnaScreen({super.key});

  @override
  ConsumerState<AsmaUlHusnaScreen> createState() => _AsmaUlHusnaScreenState();
}

class _AsmaUlHusnaScreenState extends ConsumerState<AsmaUlHusnaScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(asmaSearchResultsProvider);

    return MuslimScreenScaffold(
      title: 'muslim_99_names'.tr(),
      onRefresh: () async {
        ref.invalidate(asmaUlHusnaProvider);
        ref.invalidate(asmaSearchResultsProvider);
        await ref.read(asmaUlHusnaProvider.future);
      },
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
            child: TextField(
              controller: _searchController,
              onChanged: (v) =>
                  ref.read(asmaSearchQueryProvider.notifier).setQuery(v),
              decoration: InputDecoration(
                hintText: 'muslim_search_names'.tr(),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: context.mSurfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(asmaSearchResultsProvider),
                  child: Text('muslim_retry'.tr()),
                ),
              ),
              data: (names) => GridView.builder(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12.w,
                  mainAxisSpacing: 12.h,
                  childAspectRatio: 0.92,
                ),
                itemCount: names.length,
                itemBuilder: (_, index) => _NameCard(name: names[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({required this.name});

  final AsmaName name;

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final isAr = lang == 'ar';

    return Material(
      color: context.mSurfaceContainerLowest,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: () => _showDetail(context, name),
        borderRadius: BorderRadius.circular(14.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: context.mOutlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${name.number}',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: context.mOnSurfaceVariant,
                ),
              ),
              SizedBox(height: 6.h),
              ArabicText(
                name.nameArabic,
                style: muslimArabicStyle(
                  fontSize: isAr ? 26.sp : 24.sp,
                  fontWeight: isAr ? FontWeight.bold : FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 6.h),
              Text(
                name.transliteration,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: isAr ? 12.sp : 13.sp,
                  fontWeight: isAr ? FontWeight.w500 : FontWeight.w600,
                  color: isAr ? context.mOnSurfaceVariant : context.mPrimary,
                ),
              ),
              const Spacer(),
              Text(
                name.localizedMeaning(lang),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: isAr ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontFamily: isAr ? 'Amiri' : 'Lexend',
                  fontSize: isAr ? 12.sp : 11.sp,
                  height: isAr ? 1.4 : 1.35,
                  color: context.mOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, AsmaName name) {
    final lang = context.locale.languageCode;
    final isAr = lang == 'ar';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.mSurfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArabicText(
              name.nameArabic,
              style: muslimArabicStyle(
                fontSize: isAr ? 44.sp : 36.sp,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              name.transliteration,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: context.mPrimary,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              name.localizedMeaning(lang),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: isAr ? 'Amiri' : 'Lexend',
                fontSize: isAr ? 16.sp : 14.sp,
                height: 1.5,
                color: context.mOnSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
