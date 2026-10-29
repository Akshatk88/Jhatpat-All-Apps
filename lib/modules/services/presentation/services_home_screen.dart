import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// The module's entry screen matching the exact design screenshot.
class ServicesHomeScreen extends ConsumerWidget {
  const ServicesHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(spHomeDataProvider);

    ref.watch(spRealtimeProvider);

    return RefreshIndicator(
      color: const Color(0xFFFFB800),
      onRefresh: () async {
        ref.invalidate(spHomeDataProvider);
        await ref.read(myBookingsProvider.notifier).refresh();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _SearchBarRow()),
          const SliverToBoxAdapter(child: _ActiveBookingCard()),
          SliverToBoxAdapter(
            child: _DynamicBannerSection(
              banners: home.value?.banners ?? const [],
            ),
          ),
          ..._buildCategorySection(context, home),
          ..._buildRemainingSections(context, ref, home),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _buildCategorySection(BuildContext context, AsyncValue<SpHomeData> home) {
    final categories = home.value?.categories ?? const [];
    if (categories.isEmpty) {
      if (home.isLoading) {
        return [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFB800)),
              ),
            ),
          ),
        ];
      }
      return const [];
    }

    return [
      SliverToBoxAdapter(
        child: SpSectionHeader(
          title: 'What do you need?'.tr,
          onSeeAll: categories.isEmpty
              ? null
              : () => context.push(
                    ServicesRoutePaths.categoryOf(categories.first.id),
                  ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverGrid(
          // Four per row on phones; more columns (not wider tiles) on
          // tablets / desktop.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ((MediaQuery.sizeOf(context).width - 28) ~/ 110)
                .clamp(4, 10),
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            mainAxisExtent: 120,
          ),
          delegate: SliverChildBuilderDelegate(
            childCount: categories.length,
            (context, index) {
              final category = categories[index];
              return SpCategoryTile(
                category: category,
                onTap: () => context.push(
                  '${ServicesRoutePaths.categoryOf(category.id)}'
                  '?title=${Uri.encodeComponent(category.title)}',
                ),
              );
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildRemainingSections(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SpHomeData> home,
  ) {
    final data = home.value;
    if (data == null) return const [];

    return [
      if (data.promos.isNotEmpty) ...[
        SliverToBoxAdapter(child: SpSectionHeader(title: 'Offers for you'.tr)),
        SliverToBoxAdapter(child: _TileStrip(tiles: data.promos, height: 130)),
      ],
      if (data.popular.isNotEmpty) ...[
        SliverToBoxAdapter(child: SpSectionHeader(title: 'Most booked'.tr)),
        SliverToBoxAdapter(child: _TileStrip(tiles: data.popular, height: 175, showPrice: true)),
      ],
      for (final section in data.sections)
        if (section.cards.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SpSectionHeader(
              title: section.title,
              onSeeAll: section.seeAllCategoryId.isEmpty
                  ? null
                  : () => context.push(
                        ServicesRoutePaths.categoryOf(section.seeAllCategoryId),
                      ),
            ),
          ),
          SliverToBoxAdapter(
            child: _TileStrip(tiles: section.cards, height: 175, showPrice: true),
          ),
        ],
      if (data.noteworthy.isNotEmpty) ...[
        SliverToBoxAdapter(child: SpSectionHeader(title: 'Worth a look'.tr)),
        SliverToBoxAdapter(child: _TileStrip(tiles: data.noteworthy, height: 130)),
      ],
    ];
  }
}



class _SearchBarRow extends StatelessWidget {
  const _SearchBarRow();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Search input field
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                ],
                border: Border.all(
                  color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF9CA3AF),
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search for services or professionals...'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.mic_none_rounded,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Near me button
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
              ],
              border: Border.all(
                color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.my_location_rounded,
                      color: Color(0xFFFFB800),
                      size: 18,
                    ),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Text(
                  'Near me'.tr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF111827),
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

/// Floating active booking bar
class _ActiveBookingCard extends ConsumerWidget {
  const _ActiveBookingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(spActiveBookingProvider);
    if (booking == null || booking.status.isFinished) return const SizedBox.shrink();

    final target = booking.status.isSearching
        ? ServicesRoutePaths.searchingFor(booking.id)
        : ServicesRoutePaths.bookingOf(booking.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.push(target),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.handyman_rounded, color: Color(0xFFFFB800), size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.serviceName.isEmpty ? 'Your booking'.tr : booking.serviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SpStatusChip(status: booking.status, compact: true),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF6B7280)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dynamic hero banner carousel reading directly from backend `banners` array
class _DynamicBannerSection extends StatefulWidget {
  const _DynamicBannerSection({required this.banners});

  final List<SpHomeTile> banners;

  @override
  State<_DynamicBannerSection> createState() => _DynamicBannerSectionState();
}

class _DynamicBannerSectionState extends State<_DynamicBannerSection> {
  int _currentIndex = 0;
  late final PageController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || widget.banners.isEmpty) return;
      final nextIndex = (_currentIndex + 1) % widget.banners.length;
      if (_controller.hasClients) {
        _controller.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DynamicBannerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _startAutoSlide();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;

    if (banners.isEmpty) {
      return const _SpecialOfferBannerCard();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SizedBox(
            height: 165,
            child: PageView.builder(
              controller: _controller,
              itemCount: banners.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final banner = banners[index];
                return GestureDetector(
                  onTap: banner.targetCategoryId.isEmpty
                      ? null
                      : () => context.push(
                            ServicesRoutePaths.categoryOf(banner.targetCategoryId),
                          ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: banner.imageUrl.isNotEmpty && banner.title.isEmpty
                          ? SmartImage(
                              url: banner.imageUrl,
                              category: ImageCategory.brand,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 165,
                            )
                          : _SpecialOfferBannerCard(banner: banner),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                banners.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: _currentIndex == i ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentIndex == i
                        ? const Color(0xFFFFB800)
                        : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Hero Special Offer Card matching reference UI banner EXACTLY, supporting dynamic backend content
class _SpecialOfferBannerCard extends StatelessWidget {
  const _SpecialOfferBannerCard({this.banner});

  final SpHomeTile? banner;

  @override
  Widget build(BuildContext context) {
    final titleText = banner?.title.isNotEmpty == true ? banner!.title : 'Flat ₹100 OFF'.tr;
    final subtitleText = banner?.subtitle.isNotEmpty == true
        ? banner!.subtitle
        : 'On minimum order value\non any service, big or small!'.tr;
    final imageUrl = banner?.imageUrl.isNotEmpty == true
        ? banner!.imageUrl
        : 'https://images.unsplash.com/photo-1542744173-8e7e53415bb0?auto=format&fit=crop&q=80&w=600';

    return Padding(
      padding: banner == null ? const EdgeInsets.fromLTRB(16, 12, 16, 8) : EdgeInsets.zero,
      child: Container(
        height: 165,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF8E1), // Warm cream light yellow
              Color(0xFFFFECB3), // Soft yellow
            ],
          ),
          border: Border.all(
            color: const Color(0xFFFFE082),
            width: 1,
          ),
          boxShadow: [
            if (banner == null)
              BoxShadow(
                color: const Color(0xFFFFB800).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Right artwork illustration
              Positioned(
                right: -10,
                bottom: -10,
                top: -10,
                width: 190,
                child: SmartImage(
                  url: imageUrl,
                  category: ImageCategory.brand,
                  fit: BoxFit.cover,
                  width: 190,
                ),
              ),
              // Gradient mask overlay over image left side
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFFF8E1),
                        Color(0xFFFFF8E1),
                        Color(0xCCFFF8E1),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.55, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
              // Left text content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // SPECIAL OFFER tag
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFECB3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SPECIAL OFFER'.tr,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: Color(0xFF121212),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Inter',
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Flexible(
                            child: Text(
                              subtitleText,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CTA button
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB800),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFB800).withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'EXPLORE'.tr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '*T&C Apply'.tr,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal strip of promo tiles.
class _TileStrip extends StatelessWidget {
  const _TileStrip({
    required this.tiles,
    required this.height,
    this.showPrice = false,
  });

  final List<SpHomeTile> tiles;
  final double height;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final tile = tiles[index];
          return GestureDetector(
            onTap: tile.targetCategoryId.isEmpty
                ? null
                : () => context
                    .push(ServicesRoutePaths.categoryOf(tile.targetCategoryId)),
            child: SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SmartImage(
                      url: tile.imageUrl,
                      category: ImageCategory.category,
                      width: 150,
                      height: showPrice ? 108 : height - 34,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    tile.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: spTextPrimary(context),
                    ),
                  ),
                  if (showPrice && tile.pricePaise > 0)
                    Text(
                      'from {price}'.trArgs({'price': formatPaise(tile.pricePaise)}),
                      style: TextStyle(fontSize: 12, color: spTextSecondary(context)),
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
