import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/modules/food/data/models/category_model.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';

class CategoryList extends StatefulWidget {
  final List<CategoryModel> categories;
  final ValueChanged<String>? onCategorySelected;
  final String selectedCategoryName;

  const CategoryList({
    super.key,
    required this.categories,
    this.onCategorySelected,
    this.selectedCategoryName = 'All',
  });

  @override
  State<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final seenIds = <String>{};
    final seenNames = <String>{};
    final uniqueCategories = <CategoryModel>[];

    for (final c in widget.categories) {
      final idKey = c.id.trim();
      final nameKey = c.name.trim().toLowerCase();

      final isDuplicateId = idKey.isNotEmpty && seenIds.contains(idKey);
      final isDuplicateName = nameKey.isNotEmpty && seenNames.contains(nameKey);

      if (isDuplicateId || isDuplicateName) continue;

      if (idKey.isNotEmpty) seenIds.add(idKey);
      if (nameKey.isNotEmpty) seenNames.add(nameKey);
      uniqueCategories.add(c);
    }

    // "All" and "More" are UI affordances, not backend categories — real
    // categories from widget.categories sit between them.
    final items = <Map<String, dynamic>>[
      const {'name': 'All', 'imageUrl': '', 'isAllIcon': true},
      ...uniqueCategories.map((c) => {'name': c.name, 'imageUrl': c.imageUrl}),
      const {'name': 'More', 'imageUrl': '', 'isMoreIcon': true},
    ];

    return SizedBox(
      height: 92.h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final cat = items[index];
          final name = cat['name'] as String;
          final isSelected = widget.selectedCategoryName.toLowerCase() == name.toLowerCase() ||
              (widget.selectedCategoryName == 'All' && index == 0);
          final isMore = cat['isMoreIcon'] == true;
          final isAll = cat['isAllIcon'] == true;

          return GestureDetector(
            onTap: () {
              Haptics.light();
              widget.onCategorySelected?.call(name);
            },
            child: Container(
              margin: EdgeInsets.only(right: 12.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52.w,
                    height: 52.h,
                    padding: EdgeInsets.all(2.r),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.borderDark : AppColors.borderLight),
                        width: isSelected ? 2.5 : 1.0,
                      ),
                    ),
                    child: Container(
                      padding: EdgeInsets.all(1.5.r),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: isMore || isAll
                            ? Container(
                                color: isDark ? AppColors.surfaceDark : AppColors.secondarySurfaceLight,
                                child: Icon(
                                  isMore ? Icons.grid_view_rounded : Icons.apps_rounded,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                  size: 22.sp,
                                ),
                              )
                            : SmartImage(
                                url: cat['imageUrl'] as String,
                                category: ImageCategory.category,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  // Flexible: the row is a fixed 92.h, so on short phones with
                  // large text a two-line label must not push past it.
                  Flexible(
                    child: SizedBox(
                      width: 62.w,
                      child: Text(
                        isMore || isAll ? name.tr : name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // Black on the yellow header; white only in dark mode.
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 11.sp,
                          height: 1.15,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
