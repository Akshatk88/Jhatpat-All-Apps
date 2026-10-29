import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/food/application/providers/catalog_providers.dart';
import 'package:superapp_user/design_system/components/skeletons/skeleton_loading.dart';
import 'package:superapp_user/app/routing/route_names.dart';
import 'package:superapp_user/modules/food/presentation/restaurant/screens/restaurant_screen.dart';

/// Resolves a restaurant from an id and shows its page.
///
/// In-app navigation passes the already-loaded [RestaurantModel] via `extra`,
/// but a shared link carries nothing but an id — and the restaurant route used
/// to cast `extra` unconditionally, so arriving without one threw. This is the
/// same loader pattern the dish route already uses.
class RestaurantDetailLoaderScreen extends ConsumerWidget {
  final String restaurantId;

  const RestaurantDetailLoaderScreen({super.key, required this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (restaurantId.isEmpty) {
      return _buildErrorState(context, isDark, 'Invalid restaurant link.'.tr);
    }

    final restaurantAsync = ref.watch(restaurantByIdProvider(restaurantId));

    return restaurantAsync.when(
      loading: () => Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : const Color(0xFFFAFAFA),
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonRestaurantList(count: 3),
          ),
        ),
      ),
      error: (err, stack) => _buildErrorState(
        context,
        isDark,
        'Unable to load restaurant. Link may be expired.'.tr,
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return _buildErrorState(
            context,
            isDark,
            'This restaurant is currently unavailable.'.tr,
          );
        }
        return RestaurantScreen(restaurant: restaurant);
      },
    );
  }

  Widget _buildErrorState(BuildContext context, bool isDark, String message) {
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondaryTextColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.home);
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Restaurant Not Found'.tr,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: secondaryTextColor),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: const Color(0xFF121212),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => context.go(RouteNames.home),
                icon: const Icon(Icons.home_rounded, size: 18),
                label: Text(
                  'GO TO HOME'.tr,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
