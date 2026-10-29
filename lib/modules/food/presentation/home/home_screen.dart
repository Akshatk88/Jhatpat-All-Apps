import 'dart:developer' as developer;
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/layout/app_refresh_indicator.dart';
import 'package:superapp_user/design_system/components/skeletons/skeleton_loading.dart';
import 'package:superapp_user/design_system/components/feedback/exit_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/food/presentation/cart/widgets/floating_view_cart_bar.dart';
import 'package:superapp_user/app/routing/route_names.dart';
import 'package:superapp_user/shared/search/presentation/widgets/voice_search_dialog.dart';
import 'package:superapp_user/modules/food/data/models/restaurant_model.dart';
import 'package:superapp_user/modules/food/data/models/food_model.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/active_order_viewmodel.dart';
import 'package:superapp_user/design_system/components/layout/collapsing_header_delegate.dart';
import 'package:superapp_user/modules/food/presentation/home/viewmodels/banners_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/home/viewmodels/home_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/home/viewmodels/veg_filter_provider.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/category_list.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/home_header_banner.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/nearby_restaurants_list.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/popular_brands_list.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/promo_banner_carousel.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/popular_items_list.dart';
import 'package:superapp_user/modules/food/presentation/home/widgets/restaurant_card.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<FloatingViewCartBarState> _cartBarKey =
      GlobalKey<FloatingViewCartBarState>();
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'All';
  // Flips once the sticky header has mostly collapsed, so the status bar
  // icon color can switch from light (over the banner) to dark (over the
  // plain background) — only triggers a rebuild on the threshold crossing,
  // not on every scroll frame.
  bool _headerCollapsed = false;

  // One consistent rhythm for the whole feed instead of a different gap
  // between every pair of sections: a tight gap under each section's own
  // title, and a slightly larger one separating one section from the next.
  double get _headerGap => 8.h;
  double get _sectionGap => 16.h;

  // Sticky header geometry: the search bar + categories row travel together
  // as one fixed-height block from their original (floating-over-the-banner)
  // position up to a pinned spot below the status bar.
  double get _stickyBlockHeight =>
      50.h + 4.h + 92.h; // search + gap + categories
  double get _bannerToBlockOverlap =>
      26.h; // preserves the original floating-overlap look
  double get _collapsedTopPadding =>
      8.h; // breathing room below the status bar once pinned
  double get _shadowRoom =>
      8.h; // clip-safe room for the sticky block's elevation shadow
  double get _headerRange =>
      315.h - _bannerToBlockOverlap - _collapsedTopPadding;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(activeOrderViewModelProvider.notifier).fetchActiveOrder();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final collapsed = _scrollController.offset > _headerRange * 0.7;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeViewModelProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Matches HomeHeaderBanner's own height calc exactly, so the sticky
    // header's expanded size is pixel-identical to the old static layout.
    // Breathing room between the Rides/Parcel/Food tabs and the search bar.
    final expandedBlockTop = 12.h;
    final collapsedBlockTop = 12.h;
    final expandedHeaderExtent =
        expandedBlockTop + _stickyBlockHeight + _shadowRoom;
    final collapsedHeaderExtent =
        collapsedBlockTop + _stickyBlockHeight + _shadowRoom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showExitConfirmationDialog(context);
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: !isDark
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              AppRefreshIndicator(
                onRefresh: () async {
                  await ref.read(homeViewModelProvider.notifier).loadHomeData(isRefresh: true);
                  await ref.read(activeOrderViewModelProvider.notifier).fetchActiveOrder(isRefresh: true);
                  // Banners are their own provider, so loadHomeData does not
                  // touch them — without this a banner the admin just published
                  // would not appear until the app was restarted.
                  ref.invalidate(promoBannersProvider);
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1. Hero Header Banner + sticky Search Bar & Categories —
                    // the banner fades/collapses on scroll-up, and the search
                    // bar + categories block sticks to the top once pinned.
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: CollapsingHeaderDelegate(
                        expandedExtent: expandedHeaderExtent,
                        collapsedExtent: collapsedHeaderExtent,
                        expandedBlockTop: expandedBlockTop,
                        collapsedBlockTop: collapsedBlockTop,
                        blockHeight: _stickyBlockHeight,
                        backdropColor: isDark
                            ? AppColors.backgroundDark
                            : const Color(0xFFFFB800),
                        bannerDriftUp: 30.h,
                        banner: const HomeHeaderBanner(),
                        stickyBlock: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSearchBar(context, isDark),
                            SizedBox(height: 4.h),
                            CategoryList(
                              categories:
                                  homeState.categories.asData?.value ??
                                  const [],
                              selectedCategoryName: _selectedCategory,
                              onCategorySelected: (catName) {
                                setState(() {
                                  _selectedCategory = catName;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      // Tablets / desktop: the feed stays a readable column
                      // rather than stretching cards across the full width.
                      child: Center(
                      child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 6.h),
                          // 2. JHATPAT 50% OFF Promo Banner matching screenshot
                          _buildJhatpatPromoBanner(isDark),

                          SizedBox(height: 10.h),

                          // 3. "Popular near you" section matching screenshot
                          _buildPopularNearYouSection(context, homeState, isDark),

                          SizedBox(height: _sectionGap),

                          // 4. 99 STORE Section
                          homeState.popularFoods.when(
                            data: (foods) => PopularItemsList(
                              foods: _filterFoods(
                                foods,
                                ref.watch(vegFilterProvider),
                              ),
                              restaurants:
                                  homeState.nearbyRestaurants.asData?.value ??
                                  const [],
                              cartBarKey: _cartBarKey,
                              onAddToCartAnimationComplete: () {
                                _cartBarKey.currentState?.bump();
                              },
                            ),
                            loading: () => const SkeletonBanner(height: 140),
                            error: (err, stack) => const SizedBox.shrink(),
                          ),

                          SizedBox(height: _sectionGap),

                          // 5. RESTAURANTS NEAR YOU Section
                          _buildSectionHeader(
                            title: 'RESTAURANTS NEAR YOU'.tr,
                            onViewAll: () => context.push(RouteNames.search),
                            isDark: isDark,
                          ),
                          SizedBox(height: _headerGap),
                          homeState.nearbyRestaurants.when(
                            data: (restaurants) => NearbyRestaurantsList(
                              restaurants: _filterRestaurants(restaurants),
                            ),
                            loading: () => const SkeletonBanner(height: 180),
                            error: (err, stack) => const SizedBox.shrink(),
                          ),

                          SizedBox(height: _sectionGap),

                          // 5b. Promotional banners (admin-uploaded carousel).
                          // No section header: these are full-bleed creatives
                          // that carry their own artwork and title, and a label
                          // above them would compete with it.
                          ref.watch(promoBannersProvider).when(
                                data: (banners) => banners.isEmpty
                                    // Collapses entirely when the admin has
                                    // uploaded none, so the surrounding gaps do
                                    // not leave a hole in the scroll.
                                    ? const SizedBox.shrink()
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          PromoBannerCarousel(banners: banners),
                                          SizedBox(height: _sectionGap),
                                        ],
                                      ),
                                loading: () => const SizedBox.shrink(),
                                error: (err, stack) => const SizedBox.shrink(),
                              ),

                          // 6. POPULAR BRANDS Section
                          _buildSectionHeader(
                            title: 'POPULAR BRANDS'.tr,
                            onViewAll: () => context.push(RouteNames.search),
                            isDark: isDark,
                          ),
                          SizedBox(height: _headerGap),
                          homeState.nearbyRestaurants.when(
                            data: (restaurants) => PopularBrandsList(
                              restaurants: _filterRestaurants(restaurants),
                            ),
                            loading: () => const SkeletonBanner(height: 80),
                            error: (err, stack) => const SizedBox.shrink(),
                          ),

                          SizedBox(height: _sectionGap),

                          // 8. RESTAURANTS DELIVERING TO YOU Vertical List Section
                          homeState.nearbyRestaurants.when(
                            data: (allRestaurants) {
                              final restaurants = _filterRestaurants(
                                allRestaurants,
                              );
                              if (restaurants.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              final totalCount = restaurants.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(
                                    title:
                                        '{count} RESTAURANTS DELIVERING TO YOU'.trArgs({'count': totalCount}),
                                    onViewAll: null,
                                    isDark: isDark,
                                  ),
                                  SizedBox(height: _headerGap),
                                  ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: restaurants.length,
                                    itemBuilder: (context, index) {
                                      return RestaurantCard(
                                        restaurant: restaurants[index],
                                        index: index,
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                            loading: () => const SkeletonRestaurantList(count: 3),
                            error: (err, stack) => const SizedBox.shrink(),
                          ),

                          SizedBox(height: 100.h),
                        ],
                      ),
                      ),
                      ),
                    ),
                  ],
                ),
              ),

              // Floating View Cart Bar
              FloatingViewCartBar(
                key: _cartBarKey,
                onTap: () {
                  Haptics.light();
                  context.go(RouteNames.cart);
                },
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// 2. Search Bar + Voice Search (Container 1) & VEG Toggle Pill (Container 2)
  Widget _buildSearchBar(BuildContext context, bool isDark) {
    final isVegOnly = ref.watch(vegFilterProvider);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0.w),
      child: Row(
        children: [
          // Container 1: Search Bar + Voice Search Mic
          Expanded(
            child: Container(
              height: 50.h,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.borderDark
                      : const Color(0xFFEEEEEE),
                  width: 1,
                ),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: AppColors.shadow1,
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Haptics.light();
                        context.push(RouteNames.search);
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                            size: 20.sp,
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'Search for restaurants, dishes, combos...'.tr,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                                fontSize: 11.5.sp,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      Haptics.light();
                      final query = await VoiceSearchDialog.show(context);
                      if (query != null && query.trim().isNotEmpty && context.mounted) {
                        developer.log('[VOICE] Navigation started to SearchScreen with query: "$query"', name: 'VOICE');
                        developer.log('[VOICE] Search query passed: "$query"', name: 'VOICE');
                        context.push(RouteNames.search, extra: query.trim());
                        developer.log('[VOICE] Navigation completed', name: 'VOICE');
                      }
                    },
                    child: Icon(
                      Icons.mic,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                      size: 20.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 10.w),

          // Container 2: Separate VEG Toggle Pill Button
          InkWell(
            onTap: () {
              Haptics.light();
              ref.read(vegFilterProvider.notifier).toggle();
            },
            borderRadius: BorderRadius.circular(20.r),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50.h,
              width: 64.w,
              padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 4.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: isVegOnly
                      ? AppColors.success
                      : (isDark
                            ? AppColors.borderDark
                            : const Color(0xFFEEEEEE)),
                  width: 1.2,
                ),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: isVegOnly
                              ? AppColors.success.withValues(alpha: 0.15)
                              : AppColors.shadow1,
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 4.sp,
                        height: 4.sp,
                        decoration: BoxDecoration(
                          color: isVegOnly
                              ? AppColors.success
                              : (isDark
                                    ? AppColors.textSecondaryDark
                                    : const Color(0xFF008A45)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 3.w),
                      Text(
                        'VEG'.tr,
                        style: TextStyle(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w700,
                          color: isVegOnly
                              ? AppColors.success
                              : (isDark
                                    ? AppColors.textSecondaryDark
                                    : const Color(0xFF008A45)),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 34.w,
                    height: 18.h,
                    padding: EdgeInsets.all(2.r),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.r),
                      color: isVegOnly
                          ? AppColors.success
                          : (isDark
                                ? const Color(0xFF3B3B3B)
                                : const Color(0xFFE0E0E0)),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: isVegOnly
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 14.h,
                        height: 14.h,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJhatpatPromoBanner(bool isDark) {
    return InkWell(
      onTap: () {
        Haptics.light();
        context.push(RouteNames.allOffers);
      },
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD54F),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.black, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '50% OFF '.tr,
                          style: TextStyle(
                            fontSize: 14.5.sp,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                          ),
                        ),
                        TextSpan(
                          text: 'up to ₹100'.tr,
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'on your first food order • Use code JHAT50'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      color: Colors.black.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all'.tr,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16.sp,
                  color: Colors.black,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularNearYouSection(
    BuildContext context,
    HomeState homeState,
    bool isDark,
  ) {
    // Real restaurants from the backend, best-rated open ones first. This was a
    // hardcoded mockup list (Biryani House, Burger King, …) that did not exist,
    // so every tap could only fall through to search.
    final restaurants = [
      ..._filterRestaurants(homeState.nearbyRestaurants.value ?? const []),
    ]..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        return b.rating.compareTo(a.rating);
      });
    final popular = restaurants.take(3).toList();
    if (popular.isEmpty) return const SizedBox.shrink();

    void openRestaurant(RestaurantModel restaurant) {
      Haptics.light();
      context.push(RouteNames.restaurantDetail, extra: restaurant);
    }

    String reviewsLabel(int count) {
      if (count <= 0) return '';
      if (count >= 1000) {
        return '(${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}k+) ';
      }
      return '($count) ';
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                'Popular near you'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              ),
              InkWell(
                onTap: () {
                  Haptics.light();
                  context.push(RouteNames.search);
                },
                child: Row(
                  children: [
                    Text(
                      'See all'.tr,
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16.sp,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // 3 Food / Restaurant Cards matching screenshot
          ...popular.map((restaurant) {
            final tags = restaurant.tags.take(2).join(' • ');
            return GestureDetector(
              onTap: () => openRestaurant(restaurant),
              behavior: HitTestBehavior.opaque,
              child: Container(
              margin: EdgeInsets.only(bottom: 10.h),
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE),
                ),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14.r),
                    child: SmartImage(
                      url: restaurant.imageUrl,
                      category: ImageCategory.food,
                      width: 64.w,
                      height: 64.h,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 14.sp,
                              color: const Color(0xFFFFB800),
                            ),
                            SizedBox(width: 2.w),
                            Flexible(
                              child: Text(
                              '${restaurant.rating.toStringAsFixed(1)} ${reviewsLabel(restaurant.reviewCount)}• ${restaurant.deliveryTime}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          tags.isNotEmpty ? tags : restaurant.area,
                          style: TextStyle(
                            fontSize: 10.5.sp,
                            color: isDark ? Colors.white38 : Colors.black45,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // Yellow + ADD Button matching screenshot
                  InkWell(
                    onTap: () => openRestaurant(restaurant),
                    borderRadius: BorderRadius.circular(16.r),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 7.h,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC700),
                        borderRadius: BorderRadius.circular(16.r),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFC700).withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '+ ADD'.tr,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            );
          }),
        ],
      ),
    );
  }

  /// Section Header (Title + Jhatpat Primary View All >)
  Widget _buildSectionHeader({
    required String title,
    required VoidCallback? onViewAll,
    required bool isDark,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimaryLight,
              ),
            ),
          ),
          if (onViewAll != null)
            InkWell(
              onTap: () {
                Haptics.light();
                onViewAll();
              },
              child: Row(
                children: [
                  Text(
                    'View All'.tr,
                    style: TextStyle(
                      color: const Color(0xFFE5A600),
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.primary,
                    size: 16.sp,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// No backend field links a [FoodModel] to a category, so — same approach
  /// already used for restaurant-menu categories in [RestaurantService] —
  /// a selected category name is matched against the item's own name/
  /// description instead of a fabricated id.
  List<FoodModel> _filterFoods(List<FoodModel> foods, bool isVegOnly) {
    var result = foods;
    if (_selectedCategory != 'All' && _selectedCategory != 'More') {
      final query = _selectedCategory.toLowerCase().trim();
      final singular = query.endsWith('s')
          ? query.substring(0, query.length - 1)
          : query;
      result = result.where((f) {
        final haystack =
            '${f.name} ${f.description} ${f.category}'.toLowerCase();
        return haystack.contains(query) || haystack.contains(singular);
      }).toList();
    }
    if (isVegOnly) {
      result = result.where((f) => f.isVeg).toList();
    }
    return result;
  }

  List<RestaurantModel> _filterRestaurants(List<RestaurantModel> restaurants) {
    final isVegOnly = ref.watch(vegFilterProvider);
    var list = restaurants;
    if (isVegOnly) {
      list = list.where((r) => r.isPureVeg).toList();
    }
    if (_selectedCategory == 'All' || _selectedCategory == 'More') {
      return list;
    }
    final query = _selectedCategory.toLowerCase().trim();
    final singular = query.endsWith('s')
        ? query.substring(0, query.length - 1)
        : query;
    // A restaurant also matches when one of its dishes is in the category
    // (dish categories like "Beverages" are not restaurant cuisines).
    final foods = ref.watch(homeViewModelProvider).popularFoods.value ?? const [];
    final restaurantsWithDish = {
      for (final f in foods)
        if (f.category.toLowerCase().contains(singular)) f.restaurantId,
    };
    return list.where((r) {
      if (restaurantsWithDish.contains(r.id)) return true;
      final haystack =
          '${r.name} ${r.tags.join(' ')} ${r.restaurantTags.join(' ')}'
              .toLowerCase();
      return haystack.contains(query) || haystack.contains(singular);
    }).toList();
  }
}
