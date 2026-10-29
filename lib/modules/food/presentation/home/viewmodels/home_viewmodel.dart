import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/modules/food/application/providers/restaurant_providers.dart';
import 'package:superapp_user/modules/food/data/models/category_model.dart';
import 'package:superapp_user/modules/food/data/models/restaurant_model.dart';
import 'package:superapp_user/modules/food/data/models/food_model.dart';
import 'package:superapp_user/modules/food/data/contracts/restaurant_repository.dart';

class HomeState {
  final AsyncValue<List<CategoryModel>> categories;
  final AsyncValue<List<FoodModel>> popularFoods;
  final AsyncValue<List<FoodModel>> bestOffers;
  final AsyncValue<List<RestaurantModel>> nearbyRestaurants;

  HomeState({
    required this.categories,
    required this.popularFoods,
    required this.bestOffers,
    required this.nearbyRestaurants,
  });

  HomeState copyWith({
    AsyncValue<List<CategoryModel>>? categories,
    AsyncValue<List<FoodModel>>? popularFoods,
    AsyncValue<List<FoodModel>>? bestOffers,
    AsyncValue<List<RestaurantModel>>? nearbyRestaurants,
  }) {
    return HomeState(
      categories: categories ?? this.categories,
      popularFoods: popularFoods ?? this.popularFoods,
      bestOffers: bestOffers ?? this.bestOffers,
      nearbyRestaurants: nearbyRestaurants ?? this.nearbyRestaurants,
    );
  }
}

final homeViewModelProvider = NotifierProvider<HomeViewModel, HomeState>(() {
  return HomeViewModel();
});

class HomeViewModel extends Notifier<HomeState> {
  late final RestaurantRepository _repository;

  @override
  HomeState build() {
    _repository = ref.watch(restaurantRepositoryProvider);
    Future.microtask(() => loadHomeData());
    return HomeState(
      categories: const AsyncValue.loading(),
      popularFoods: const AsyncValue.loading(),
      bestOffers: const AsyncValue.loading(),
      nearbyRestaurants: const AsyncValue.loading(),
    );
  }

  Future<void> loadHomeData({bool isRefresh = false}) async {
    developer.log('[HOME_VM] Loading home data...', name: 'HOME');
    print('[HOME_VM] Loading home data...');

    if (!isRefresh) {
      state = state.copyWith(
        categories: const AsyncValue.loading(),
        popularFoods: const AsyncValue.loading(),
        bestOffers: const AsyncValue.loading(),
        nearbyRestaurants: const AsyncValue.loading(),
      );
    }

    final responses = await Future.wait([
      _repository.getCategories(
        onCache: (c) => state = state.copyWith(categories: AsyncValue.data(c)),
      ),
      _repository.getPopularFoods(
        onCache: (f) => state = state.copyWith(popularFoods: AsyncValue.data(f)),
      ),
      _repository.getBestOffers(
        onCache: (f) => state = state.copyWith(bestOffers: AsyncValue.data(f)),
      ),
      _repository.getPopularRestaurants(
        onCache: (r) => state = state.copyWith(nearbyRestaurants: AsyncValue.data(r)),
      ),
    ]);

    final categoriesRes = responses[0] as dynamic; 
    final popularFoodsRes = responses[1] as dynamic;
    final bestOffersRes = responses[2] as dynamic;
    final nearbyRes = responses[3] as dynamic;

    print('[HOME_VM] Categories Success: ${categoriesRes.isSuccess} (${categoriesRes.isSuccess ? categoriesRes.data.length : categoriesRes.message})');
    print('[HOME_VM] Popular Foods Success: ${popularFoodsRes.isSuccess} (${popularFoodsRes.isSuccess ? popularFoodsRes.data.length : popularFoodsRes.message})');
    print('[HOME_VM] Best Offers Success: ${bestOffersRes.isSuccess} (${bestOffersRes.isSuccess ? bestOffersRes.data.length : bestOffersRes.message})');
    print('[HOME_VM] Nearby Restaurants Success: ${nearbyRes.isSuccess} (${nearbyRes.isSuccess ? nearbyRes.data.length : nearbyRes.message})');

    // `/categories/public` currently returns an empty list, which left the
    // strip with only "All" and "More". The data still exists: restaurants
    // carry cuisines and every dish carries its categoryName — so fall back
    // to those rather than show an unusable strip.
    final apiCategories = categoriesRes.isSuccess
        ? List<CategoryModel>.from(categoriesRes.data as List)
        : const <CategoryModel>[];
    final derivedCategories = apiCategories.isNotEmpty
        ? apiCategories
        : _deriveCategories(
            nearbyRes.isSuccess
                ? List<RestaurantModel>.from(nearbyRes.data as List)
                : const <RestaurantModel>[],
            popularFoodsRes.isSuccess
                ? List<FoodModel>.from(popularFoodsRes.data as List)
                : const <FoodModel>[],
          );

    state = state.copyWith(
      categories: categoriesRes.isSuccess || derivedCategories.isNotEmpty
          ? AsyncValue.data(derivedCategories)
          : AsyncValue.error(categoriesRes.message, StackTrace.current),
      popularFoods: popularFoodsRes.isSuccess 
          ? AsyncValue.data(popularFoodsRes.data) 
          : AsyncValue.error(popularFoodsRes.message, StackTrace.current),
      bestOffers: bestOffersRes.isSuccess 
          ? AsyncValue.data(bestOffersRes.data) 
          : AsyncValue.error(bestOffersRes.message, StackTrace.current),
      nearbyRestaurants: nearbyRes.isSuccess 
          ? AsyncValue.data(nearbyRes.data)
          : AsyncValue.error(nearbyRes.message, StackTrace.current),
    );
  }

  /// Builds the category strip from what restaurants and dishes actually
  /// carry: restaurant cuisines first (they cover the most restaurants), then
  /// dish categories. Each uses a matching restaurant/dish image as its icon.
  /// The id is the name itself — the home screen filters by name.
  static List<CategoryModel> _deriveCategories(
    List<RestaurantModel> restaurants,
    List<FoodModel> foods,
  ) {
    final byKey = <String, CategoryModel>{};
    final counts = <String, int>{};

    void add(String rawName, String imageUrl) {
      final name = rawName.trim();
      if (name.isEmpty) return;
      final key = name.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      final existing = byKey[key];
      if (existing == null || (existing.imageUrl.isEmpty && imageUrl.isNotEmpty)) {
        byKey[key] = CategoryModel(id: name, name: name, imageUrl: imageUrl);
      }
    }

    for (final r in restaurants) {
      for (final cuisine in r.tags) {
        add(cuisine, r.imageUrl);
      }
    }
    for (final f in foods) {
      add(f.category, f.imageUrl);
    }

    final keys = byKey.keys.toList()
      ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
    return [for (final k in keys) byKey[k]!];
  }
}
