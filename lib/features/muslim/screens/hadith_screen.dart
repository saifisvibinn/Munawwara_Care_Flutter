import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../utils/muslim_localization.dart';
import '../widgets/muslim_widgets.dart';

class HadithScreen extends ConsumerStatefulWidget {
  const HadithScreen({super.key});

  @override
  ConsumerState<HadithScreen> createState() => _HadithScreenState();
}

class _HadithScreenState extends ConsumerState<HadithScreen> {
  bool _showSecondary = false;

  Future<void> _loadNextHadith() async {
    setState(() => _showSecondary = false);
    await ref.read(displayedHadithProvider.notifier).loadRandom();
  }

  Future<void> _loadFromCollection(HadithCollection collection) async {
    setState(() => _showSecondary = false);
    await ref
        .read(displayedHadithProvider.notifier)
        .loadRandomFromCollection(collection);
  }

  @override
  Widget build(BuildContext context) {
    final hadithAsync = ref.watch(displayedHadithProvider);

    return MuslimScreenScaffold(
      title: 'muslim_hadith'.tr(),
      onRefresh: _loadNextHadith,
      body: hadithAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: _loadNextHadith,
            child: Text('muslim_retry'.tr()),
          ),
        ),
        data: (hadith) => ListView(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
          children: [
            _HadithCard(
              hadith: hadith,
              showSecondary: _showSecondary,
              onToggleSecondary: () =>
                  setState(() => _showSecondary = !_showSecondary),
            ),
            SizedBox(height: 12.h),
            FilledButton(
              onPressed: _loadNextHadith,
              style: FilledButton.styleFrom(
                backgroundColor: context.mPrimary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'muslim_next_hadith'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Icon(
                    Symbols.navigate_next,
                    size: 22.w,
                  ),
                ],
              ),
            ),
            SizedBox(height: 10.h),
            OutlinedButton(
              onPressed: _showCollectionsSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.mPrimary,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                side: BorderSide(
                  color: context.mPrimary.withValues(alpha: 0.25),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Symbols.library_books, size: 20.w),
                  SizedBox(width: 8.w),
                  Text(
                    'muslim_browse_collections'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCollectionsSheet() async {
    final collections = await ref.read(hadithCollectionsProvider.future);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.mSurfaceContainerLowest,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.85,
            builder: (_, scrollController) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'muslim_hadith_collections'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                          color: context.mPrimary,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        'muslim_hadith_collections_hint'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          height: 1.4,
                          color: context.mOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 16.h),
                    itemCount: collections.length,
                    separatorBuilder: (_, _) => SizedBox(height: 8.h),
                    itemBuilder: (_, index) {
                      final col = collections[index];
                      return Material(
                        color: context.mSurfaceContainerLow,
                        borderRadius: BorderRadius.circular(12.r),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            _loadFromCollection(col);
                          },
                          borderRadius: BorderRadius.circular(12.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.w,
                              vertical: 12.h,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40.w,
                                  height: 40.w,
                                  decoration: BoxDecoration(
                                    color: context.mPrimaryContainer,
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Symbols.menu_book,
                                    size: 20.w,
                                    color: context.mOnPrimaryContainer,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        localizedHadithCollectionName(
                                          collectionKey: col.key,
                                          fallback: col.name,
                                        ),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w600,
                                          color: context.mOnSurface,
                                        ),
                                      ),
                                      Text(
                                        localizedHadithCollectionReliability(
                                          col.reliability,
                                        ),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.sp,
                                          color: context.mOnSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                muslimForwardChevron(
                                  size: 20.w,
                                  color: context.mPrimary
                                      .withValues(alpha: 0.45),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HadithCard extends StatelessWidget {
  const _HadithCard({
    required this.hadith,
    this.showSecondary = false,
    this.onToggleSecondary,
  });

  final HadithData hadith;
  final bool showSecondary;
  final VoidCallback? onToggleSecondary;

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final primary = hadithPrimaryText(hadith, lang);
    final secondary = hadithSecondaryText(hadith, lang);
    final prefersArabic = muslimPrefersArabicContent(lang);
    final collectionLabel = localizedHadithCollectionName(
      collectionKey: hadith.collection,
      fallback: hadith.collectionName,
    );
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: context.mSurfaceContainerLowest,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: context.mPrimary.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: context.mPrimaryContainer,
                  borderRadius: BorderRadius.circular(999.r),
                ),
                child: Text(
                  '$collectionLabel · #${hadith.hadithNumber}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: context.mOnPrimaryContainer,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const Spacer(),
              if (hadith.grade.isNotEmpty)
                Text(
                  localizedHadithGrade(hadith.grade),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: context.mSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
            ],
          ),
          SizedBox(height: 16.h),
          if (prefersArabic)
            ArabicText(
              primary,
              style: muslimArabicStyle(fontSize: 22.sp),
            )
          else
            Text(
              primary,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18.sp,
                fontStyle: FontStyle.italic,
                height: 1.55,
                color: context.mOnSurface,
                decoration: TextDecoration.none,
              ),
            ),
          if (onToggleSecondary != null && secondary != null) ...[
            SizedBox(height: 16.h),
            Divider(
              color: context.mOutlineVariant.withValues(alpha: 0.5),
              height: 1,
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggleSecondary,
                borderRadius: BorderRadius.circular(8.r),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hadithToggleSecondaryLabel(lang),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: context.mOnSurfaceVariant,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      Icon(
                        showSecondary ? Symbols.expand_less : Symbols.expand_more,
                        size: 22.w,
                        color: context.mOnSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (showSecondary && secondary != null) ...[
            if (prefersArabic)
              Text(
                secondary,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16.sp,
                  fontStyle: FontStyle.italic,
                  height: 1.55,
                  color: context.mOnSurfaceVariant,
                  decoration: TextDecoration.none,
                ),
              )
            else
              ArabicText(
                secondary,
                style: muslimArabicStyle(fontSize: 22.sp),
              ),
          ],
        ],
      ),
    );
  }
}
