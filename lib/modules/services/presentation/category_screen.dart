import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// Everything bookable inside one category.
///
/// The catalogue has two levels — brands ("LG", "Samsung", or a named package)
/// and the services under them — but the backend does not require a brand to be
/// chosen: `GET /sp/public/services?categoryId=…` returns every service in the
/// category, across brands, and falls back to synthesising services from the
/// brands themselves when a category has none of its own.
///
/// So this screen shows brands as an optional *filter* above a flat service
/// list, rather than forcing a brand tap first. A category with one brand, or
/// none, then costs the customer no extra step.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.categoryId, this.categoryTitle});

  final String categoryId;
  final String? categoryTitle;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  /// null = "All", otherwise the selected brand id.
  String? _brandId;

  @override
  Widget build(BuildContext context) {
    final brands = ref.watch(spBrandsProvider(widget.categoryId));
    final services = ref.watch(spServicesProvider(
      SpServiceQuery(
        // Once a brand is chosen, query by brand alone: the backend's
        // brand+category branch also matches services with no category set,
        // which is what most brand-owned services actually are.
        brandId: _brandId,
        categoryId: _brandId == null ? widget.categoryId : null,
      ),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryTitle ?? 'Services'.tr),
        backgroundColor: spSurface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        color: spAccent,
        onRefresh: () async {
          ref.invalidate(spBrandsProvider(widget.categoryId));
          ref.invalidate(spServicesProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Brand filter — hidden entirely when there is nothing to filter by,
            // so a single-brand category doesn't show a pointless one-chip row.
            if (brands.value != null && brands.value!.length > 1)
              SliverToBoxAdapter(
                child: _BrandFilter(
                  brands: brands.value!,
                  selectedId: _brandId,
                  onSelected: (id) => setState(() => _brandId = id),
                ),
              ),

            switch (services) {
              AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nothing available here yet.\nTry another category.'.tr,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              AsyncData(:final value) => SliverPadding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  sliver: SliverList.builder(
                    itemCount: value.length,
                    itemBuilder: (context, index) {
                      final service = value[index];
                      return SpServiceCard(
                        service: service,
                        onTap: () => context.push(
                          ServicesRoutePaths.serviceOf(service.id),
                          // Warm push: the detail screen renders immediately
                          // and skips a refetch it does not need.
                          extra: service,
                        ),
                      );
                    },
                  ),
                ),
              AsyncError(:final error) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: SpErrorState(
                    message: error.toString().contains('Network')
                        ? 'You appear to be offline.'.tr
                        : 'We could not load these services.'.tr,
                    onRetry: () => ref.invalidate(spServicesProvider),
                  ),
                ),
              _ => const SliverToBoxAdapter(child: SpListSkeleton()),
            },
          ],
        ),
      ),
    );
  }
}

class _BrandFilter extends StatelessWidget {
  const _BrandFilter({
    required this.brands,
    required this.selectedId,
    required this.onSelected,
  });

  final List<SpBrand> brands;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        itemCount: brands.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _Chip(
              label: 'All'.tr,
              selected: selectedId == null,
              onTap: () => onSelected(null),
            );
          }
          final brand = brands[index - 1];
          return _Chip(
            label: brand.title,
            imageUrl: brand.iconUrl,
            selected: selectedId == brand.id,
            onTap: () => onSelected(selectedId == brand.id ? null : brand.id),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.imageUrl,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: selected
                    ? spAccent.withValues(alpha: 0.12)
                    : spSurface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? spAccent : spBorder(context),
                  width: selected ? 1.6 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Icon(
                      Icons.apps_rounded,
                      size: 22,
                      color: selected ? spAccent : spTextSecondary(context),
                    )
                  : SmartImage(
                      url: imageUrl!,
                      category: ImageCategory.brand,
                      width: 52,
                      height: 52,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? spAccentText(context) : spTextSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
