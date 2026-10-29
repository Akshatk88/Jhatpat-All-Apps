import 'package:flutter/material.dart';

import 'package:food_user_application/config/constants/app_constants.dart';

/// Which kind of seller account this app is signed in as.
///
/// The app is restaurant-only: the grocery "Quick Shop" (`/qc`) vertical was
/// removed. A stored "quick" value from an older install parses to [food].
///
/// Originally one app, two storefront products. They are **not** two views of one account:
/// a restaurant lives in `food_restaurants` on the food backend, a quick shop
/// lives in `qc_restaurants` on the master backend, and an operator may hold one
/// or both as entirely separate businesses. So the choice is made at login,
/// before any credential is entered, and it decides which backend the whole
/// session talks to.
///
/// Both verticals live on the same backend, which is what makes this cheap:
/// every seller path is identical after the module prefix
/// (`/food/restaurant/orders` ↔ `/qc/restaurant/orders`), so switching vertical
/// is a prefix rewrite in one interceptor rather than a second implementation
/// of every screen. See `core/network/dio_client.dart`.
///
/// The host comes from [AppConstants.baseUrl] rather than being written out
/// here. It used to be hardcoded to `suvio.appzeto.com` and
/// `superapp.appzeto.com`, which resolve to a different server (145.223.21.188)
/// from the one the admin panel registers restaurants on — so a freshly
/// registered restaurant did not exist in the database the app was signing in
/// against, and its login was rejected.
enum SellerVertical {
  /// Restaurants — the original product. `/food/*`.
  food(
    wire: 'food',
    label: 'Restaurant',
    tagline: 'Dine-in & food delivery',
    icon: Icons.restaurant_rounded,
    accent: Color(0xFFE85B17),
    host: AppConstants.baseUrl,
    pathPrefix: '/food',
  );

  const SellerVertical({
    required this.wire,
    required this.label,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.host,
    required this.pathPrefix,
  });

  /// Persisted value. Never rename — a stored session would fail to restore and
  /// silently drop the seller onto the wrong backend.
  final String wire;

  final String label;
  final String tagline;
  final IconData icon;
  final Color accent;

  /// API base, including `/api/v1`.
  final String host;

  /// Module prefix every path in this vertical carries.
  final String pathPrefix;

  /// Tolerant parse — an unreadable or absent stored value means "the original
  /// product", which is the safe default for every account that predates this
  /// screen.
  static SellerVertical parse(String? raw) {
    final needle = (raw ?? '').trim().toLowerCase();
    for (final value in values) {
      if (value.wire == needle) return value;
    }
    return SellerVertical.food;
  }

  /// Paths that live at the API root rather than under `/food`, but are still
  /// per-module on the backend.
  ///
  /// FCM is the whole list today. It matters because each module keeps its own
  /// token store: master serves the food/taxi tokens at `/api/v1/fcm-tokens/*`
  /// and quick-commerce's at `/api/v1/qc/fcm-tokens/*`. A quick shop that
  /// registered at the unprefixed path would save its token successfully into
  /// the store QC never reads, and no order push would ever arrive — a silent
  /// failure, since the save itself returns 200.
  static const _rootScopedPaths = ['/fcm-tokens'];

  /// Rewrites a path written for the food backend onto this vertical.
  ///
  /// Call sites throughout the app are written as `/food/restaurant/...`
  /// because that is what the app has always talked to. Rather than touch all
  /// ~40 of them (and every future one), the prefix is swapped centrally here.
  String resolvePath(String path) {
    if (pathPrefix == '/food') return path;

    if (path == '/food') return pathPrefix;
    if (path.startsWith('/food/')) {
      return '$pathPrefix${path.substring('/food'.length)}';
    }

    for (final root in _rootScopedPaths) {
      if (path == root || path.startsWith('$root/')) {
        return '$pathPrefix$path';
      }
    }

    return path;
  }
}
