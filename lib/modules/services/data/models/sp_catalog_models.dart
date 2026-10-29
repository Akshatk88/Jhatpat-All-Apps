/// Catalogue shapes returned by `/sp/public/*`.
///
/// Two house rules apply to every model in this file:
///
///  * **Money is `int` paise, never `double`.** The SP backend sends rupees as
///    JSON numbers (`basePrice: 499`, sometimes `499.5`); binary floating point
///    turns arithmetic on those into `₹349.99999`. Parse once at the boundary,
///    keep integers everywhere inside, convert back only when posting.
///  * **Tolerant `fromJson`.** SP mixes `_id` and `id` across endpoints (the
///    public controllers map to `id`, the booking controllers return raw
///    mongoose docs with `_id`), and a field typed `String` on one route can
///    arrive as an `int` on another. Never `as String` on something that might
///    not be.
library;

import 'package:superapp_user/core/config/api_config.dart';

/// Rupees (num or numeric string) -> paise.
int paiseOf(dynamic value) {
  if (value == null) return 0;
  if (value is num) return (value * 100).round();
  return ((num.tryParse(value.toString()) ?? 0) * 100).round();
}

/// Paise -> the rupee number the SP API expects in a request body.
///
/// Returns an `int` when the amount is whole rupees, which is the overwhelming
/// common case, so bodies read `499` rather than `499.0`.
num rupeesOf(int paise) => paise % 100 == 0 ? paise ~/ 100 : paise / 100;

/// `₹1,299` / `₹1,299.50`.
String formatPaise(int paise) {
  final rupees = paise / 100;
  final whole = rupees.truncate();
  final grouped = whole.abs().toString().replaceAllMapped(
        // Indian grouping: last 3 digits, then pairs (12,34,567).
        RegExp(r'(\d)(?=(\d\d)+\d$)'),
        (m) => '${m[1]},',
      );
  final sign = whole < 0 ? '-' : '';
  final paisePart = paise.abs() % 100;
  return paisePart == 0
      ? '₹$sign$grouped'
      : '₹$sign$grouped.${paisePart.toString().padLeft(2, '0')}';
}

String _id(Map<String, dynamic> json) =>
    (json['id'] ?? json['_id'] ?? '').toString();

String _str(dynamic value) => value?.toString().trim() ?? '';

/// A top-level service taxonomy entry — "AC Repair", "Cleaning", "Plumbing".
///
/// From `GET /sp/public/categories` and the `categories` array of
/// `GET /sp/public/home-data`.
class SpCategory {
  const SpCategory({
    required this.id,
    required this.title,
    required this.slug,
    required this.iconUrl,
    required this.badge,
    required this.hasSaleBadge,
    required this.showOnHome,
  });

  final String id;
  final String title;
  final String slug;
  final String iconUrl;
  final String badge;
  final bool hasSaleBadge;
  final bool showOnHome;

  factory SpCategory.fromJson(Map<String, dynamic> json) => SpCategory(
        id: _id(json),
        title: _str(json['title']),
        slug: _str(json['slug']),
        // The API mixes absolute Cloudinary URLs with relative /uploads paths.
        iconUrl: ApiConfig.resolveMedia(_str(json['icon'] ?? json['homeIconUrl'])),
        badge: _str(json['badge'] ?? json['homeBadge']),
        hasSaleBadge: json['hasSaleBadge'] == true,
        // Defaults to true: the backend only sets this false explicitly, and a
        // missing field hiding every category would empty the home screen.
        showOnHome: json['showOnHome'] != false,
      );
}

/// A brand within a category — "LG", "Samsung", or a named service package.
///
/// From `GET /sp/public/brands`.
class SpBrand {
  const SpBrand({
    required this.id,
    required this.title,
    required this.slug,
    required this.iconUrl,
    required this.imageUrl,
    required this.badge,
    required this.pricePaise,
    required this.originalPricePaise,
    required this.categoryIds,
  });

  final String id;
  final String title;
  final String slug;
  final String iconUrl;
  final String imageUrl;
  final String badge;
  final int pricePaise;
  final int originalPricePaise;
  final List<String> categoryIds;

  /// True when the struck-through price is genuinely higher — guards against
  /// showing "₹499 ~~₹499~~", which the backend's `originalPrice` fallback
  /// produces whenever `discountPrice` is unset.
  bool get hasDiscount => originalPricePaise > pricePaise;

  factory SpBrand.fromJson(Map<String, dynamic> json) => SpBrand(
        id: _id(json),
        title: _str(json['title']),
        slug: _str(json['slug']),
        iconUrl: ApiConfig.resolveMedia(_str(json['icon'] ?? json['logo'])),
        imageUrl: ApiConfig.resolveMedia(
            _str(json['imageUrl'] ?? json['logo'] ?? json['icon'])),
        badge: _str(json['badge']),
        pricePaise: paiseOf(json['price'] ?? json['basePrice']),
        originalPricePaise: paiseOf(json['originalPrice'] ?? json['price']),
        categoryIds: [
          for (final id in (json['categoryIds'] as List? ?? const [])) id.toString(),
          if (json['categoryId'] != null) json['categoryId'].toString(),
        ],
      );
}

/// A bookable service — the thing a booking's `serviceId` points at.
///
/// From `GET /sp/public/services?brandId=…` / `?categoryId=…`.
class SpService {
  const SpService({
    required this.id,
    required this.title,
    required this.iconUrl,
    required this.description,
    required this.basePricePaise,
    required this.discountPricePaise,
    required this.gstPercentage,
    required this.pricingUnit,
    required this.categoryId,
    required this.brandId,
    required this.brandName,
    required this.brandIconUrl,
  });

  final String id;
  final String title;
  final String iconUrl;
  final String description;
  final int basePricePaise;

  /// The sale price. `0` means "no discount", not "free".
  final int discountPricePaise;
  final double gstPercentage;
  final String pricingUnit;
  final String categoryId;
  final String brandId;
  final String brandName;
  final String brandIconUrl;

  bool get hasDiscount =>
      discountPricePaise > 0 && discountPricePaise < basePricePaise;

  /// What the customer actually pays for one unit, before tax and visiting fee.
  int get effectivePricePaise => hasDiscount ? discountPricePaise : basePricePaise;

  factory SpService.fromJson(Map<String, dynamic> json) => SpService(
        id: _id(json),
        title: _str(json['title']),
        iconUrl: ApiConfig.resolveMedia(_str(json['icon'] ?? json['iconUrl'])),
        description: _str(json['description']),
        basePricePaise: paiseOf(json['basePrice']),
        discountPricePaise: paiseOf(json['discountPrice']),
        gstPercentage: (json['gstPercentage'] as num?)?.toDouble() ?? 0,
        pricingUnit: _str(json['pricingUnit']),
        categoryId: _str(json['categoryId']),
        brandId: _str(json['brandId']),
        brandName: _str(json['brandName']),
        brandIconUrl: ApiConfig.resolveMedia(_str(json['brandIcon'])),
      );
}

/// One promotional tile from `home-data.homeContent`.
///
/// The backend ships six differently-named arrays (`banners`, `promos`,
/// `curated`, `noteworthy`, `booked`, `categorySections[].cards`) whose shapes
/// overlap almost entirely. Rather than six near-identical classes, they all
/// parse into this one and the screen decides how to render each list.
class SpHomeTile {
  const SpHomeTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.targetCategoryId,
    required this.pricePaise,
    required this.rating,
    required this.order,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final String targetCategoryId;
  final int pricePaise;
  final String rating;
  final int order;

  factory SpHomeTile.fromJson(Map<String, dynamic> json) => SpHomeTile(
        title: _str(json['title']),
        subtitle: _str(json['subtitle']),
        imageUrl:
            ApiConfig.resolveMedia(_str(json['imageUrl'] ?? json['gifUrl'])),
        targetCategoryId: _str(json['targetCategoryId']),
        pricePaise: paiseOf(json['price']),
        rating: _str(json['rating']),
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}

/// A titled row of [SpHomeTile]s.
class SpHomeSection {
  const SpHomeSection({
    required this.title,
    required this.seeAllCategoryId,
    required this.cards,
    required this.order,
  });

  final String title;
  final String seeAllCategoryId;
  final List<SpHomeTile> cards;
  final int order;

  factory SpHomeSection.fromJson(Map<String, dynamic> json) => SpHomeSection(
        title: _str(json['title']),
        seeAllCategoryId: _str(json['seeAllTargetCategoryId']),
        cards: [
          for (final card in (json['cards'] as List? ?? const []))
            SpHomeTile.fromJson((card as Map).cast<String, dynamic>()),
        ],
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}

/// The whole `GET /sp/public/home-data` payload.
///
/// Every section carries its own admin-controlled visibility flag; a section
/// whose flag is false is dropped here rather than in the widget tree, so the
/// screen never has to reason about it.
class SpHomeData {
  const SpHomeData({
    required this.categories,
    required this.banners,
    required this.promos,
    required this.noteworthy,
    required this.popular,
    required this.sections,
    required this.showCategories,
  });

  final List<SpCategory> categories;
  final List<SpHomeTile> banners;
  final List<SpHomeTile> promos;
  final List<SpHomeTile> noteworthy;
  final List<SpHomeTile> popular;
  final List<SpHomeSection> sections;
  final bool showCategories;

  bool get isEmpty =>
      categories.isEmpty &&
      banners.isEmpty &&
      promos.isEmpty &&
      noteworthy.isEmpty &&
      popular.isEmpty &&
      sections.isEmpty;

  static const empty = SpHomeData(
    categories: [],
    banners: [],
    promos: [],
    noteworthy: [],
    popular: [],
    sections: [],
    showCategories: true,
  );

  factory SpHomeData.fromJson(Map<String, dynamic> json) {
    final content = (json['homeContent'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    List<SpHomeTile> tiles(String key, String visibilityFlag) {
      if (content[visibilityFlag] == false) return const [];
      final raw = content[key] as List? ?? const [];
      final list = [
        for (final item in raw)
          SpHomeTile.fromJson((item as Map).cast<String, dynamic>()),
      ]..sort((a, b) => a.order.compareTo(b.order));
      return list;
    }

    final sections = content['isCategorySectionsVisible'] == false
        ? const <SpHomeSection>[]
        : ([
            for (final s in (content['categorySections'] as List? ?? const []))
              SpHomeSection.fromJson((s as Map).cast<String, dynamic>()),
          ]..sort((a, b) => a.order.compareTo(b.order)));

    final categories = [
      for (final c in (json['categories'] as List? ?? const []))
        SpCategory.fromJson((c as Map).cast<String, dynamic>()),
    ];

    return SpHomeData(
      // The backend already applies `showOnHome` as a per-category flag; honour
      // it here so the home grid and the "all categories" list can share a model.
      categories: categories.where((c) => c.showOnHome).toList(),
      banners: tiles('banners', 'isBannersVisible'),
      promos: tiles('promos', 'isPromosVisible'),
      noteworthy: tiles('noteworthy', 'isNoteworthyVisible'),
      popular: tiles('booked', 'isBookedVisible'),
      sections: sections,
      showCategories: content['isCategoriesVisible'] != false,
    );
  }
}

/// A serviceable city from `GET /sp/public/cities`.
///
/// Catalogue calls are city-scoped: passing `cityId` filters categories,
/// brands and home content to what that city actually sells.
class SpCity {
  const SpCity({required this.id, required this.name, required this.state});

  final String id;
  final String name;
  final String state;

  factory SpCity.fromJson(Map<String, dynamic> json) => SpCity(
        id: _id(json),
        name: _str(json['name'] ?? json['title']),
        state: _str(json['state']),
      );
}
