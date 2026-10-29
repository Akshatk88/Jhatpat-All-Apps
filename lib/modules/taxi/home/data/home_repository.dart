import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';
import 'package:superapp_user/core/network/taxi_api_client.dart';
import 'package:superapp_user/modules/taxi/home/data/models/app_module_model.dart';
import 'package:superapp_user/modules/taxi/home/data/models/set_price_model.dart';
import 'package:superapp_user/modules/taxi/home/data/models/vehicle_type_model.dart';

class HomeRepository {
  final TaxiApiClient api;

  HomeRepository(this.api);

  Future<List<AppModuleModel>> getAppModules() async {
    final data = await api.get(ApiConstants.appModules, query: {'per_page': 50});
    final List rawResults;
    if (data is List) {
      rawResults = data;
    } else if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      rawResults = (map['results'] ?? map['modules'] ?? map['data'] ?? map['docs'] ?? []) as List? ?? [];
    } else {
      rawResults = [];
    }
    final modules = rawResults
        .map((e) => AppModuleModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((m) => m.active)
        .toList();
    modules.sort((a, b) => a.orderBy.compareTo(b.orderBy));
    return modules;
  }

  /// The full vehicle catalog, every transport type.
  ///
  /// This used to filter to `taxi` here, which meant delivery vehicles never
  /// reached the app at all and the parcel flow always looked empty. Filtering
  /// now happens per-caller so ride and delivery can share one fetch.
  ///
  /// Both catalogue calls are huge on the wire — the server inlines every
  /// vehicle icon as a base64 image (set-prices ≈ 15 MB, vehicle-types ≈ 4 MB,
  /// 10–20 s on a phone) — while the app needs a few KB of it. So:
  ///  - one network fetch per app session, shared by every caller;
  ///  - a stripped copy (no base64) kept on the device, returned at once by
  ///    the `cached…` methods so prices show instantly on the next launch.
  Future<List<VehicleTypeModel>> getVehicleTypes() =>
      _vehicleTypesFuture ??= _fetchRows(
        ApiConstants.vehicleTypes,
        const {},
        _vehicleTypesKey,
      ).then((rows) => rows.map(VehicleTypeModel.fromJson).toList())
          .catchError((Object e) {
        _vehicleTypesFuture = null; // retry next time instead of caching a failure
        throw e;
      });

  Future<List<SetPriceModel>> getSetPrices() =>
      _setPricesFuture ??= _fetchRows(
        ApiConstants.setPrices,
        const {'scope': 'ride'},
        _setPricesKey,
      ).then((rows) => rows.map(SetPriceModel.fromJson).toList())
          .catchError((Object e) {
        _setPricesFuture = null;
        throw e;
      });

  /// The device copy from the last successful fetch, or null.
  Future<List<VehicleTypeModel>?> cachedVehicleTypes() async =>
      (await _readRows(_vehicleTypesKey))?.map(VehicleTypeModel.fromJson).toList();

  Future<List<SetPriceModel>?> cachedSetPrices() async =>
      (await _readRows(_setPricesKey))?.map(SetPriceModel.fromJson).toList();

  /// Starts both downloads early (from the rides home) so they are done by
  /// the time the rider reaches the vehicle list.
  void prefetchCatalog() {
    getVehicleTypes().ignore();
    getSetPrices().ignore();
  }

  static Future<List<VehicleTypeModel>>? _vehicleTypesFuture;
  static Future<List<SetPriceModel>>? _setPricesFuture;
  static const _vehicleTypesKey = 'taxi_cache_vehicle_types_v1';
  static const _setPricesKey = 'taxi_cache_set_prices_v1';

  Future<List<Map<String, dynamic>>> _fetchRows(
    String path,
    Map<String, dynamic> query,
    String cacheKey,
  ) async {
    final data = await api.get(path, query: query.isEmpty ? null : query);
    final raw = _resultsOf(data);
    if (path == ApiConstants.vehicleTypes) {
      // Keep the marker art (base64 `map_icon`) in memory before stripping:
      // the backend has no slim map-icon feed, so this is its only source.
      _mapIconRows = raw
          .whereType<Map>()
          .map((e) => <String, dynamic>{
                'id': e['id'] ?? e['_id'],
                'icon_types': e['icon_types'],
                'map_icon': e['map_icon'],
              })
          .where((e) => (e['map_icon'] ?? '').toString().isNotEmpty)
          .toList();
    }
    final rows = raw
        .whereType<Map>()
        .map((e) => _stripInlineImages(Map<String, dynamic>.from(e)))
        .toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(rows));
    } catch (_) {
      // A lost cache only means the next launch waits for the network.
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>?> _readRows(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw);
      if (list is! List || list.isEmpty) return null;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Drops base64 `data:` images (the app never shows them) so the stored
  /// copy is a few KB instead of megabytes.
  static Map<String, dynamic> _stripInlineImages(Map<String, dynamic> row) {
    row.removeWhere((_, v) => v is String && v.startsWith('data:'));
    return row;
  }

  /// Active promo banners for the home strip, newest first.
  Future<List<Map<String, dynamic>>> getBanners() async {
    final data = await api.get(ApiConstants.banners);
    final results = _resultsOf(data);
    return results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Marker art per vehicle type, as `{ id, icon_types, map_icon }`, taken from
  /// the vehicle catalog (the old `/vehicle-map-icons` feed does not exist).
  Future<List<Map<String, dynamic>>> getVehicleMapIcons() async {
    if (_mapIconRows == null) {
      try {
        await getVehicleTypes();
      } catch (_) {}
    }
    return _mapIconRows ?? const [];
  }

  static List<Map<String, dynamic>>? _mapIconRows;

  /// Accepts `[...]`, `{results}`, `{data: {results}}` and `{data: [...]}`.
  static List _resultsOf(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final r = data['results'];
      if (r is List) return r;
      final inner = data['data'];
      if (inner is List) return inner;
      if (inner is Map && inner['results'] is List) return inner['results'] as List;
    }
    return const [];
  }

  /// Returns the ETA (in minutes) of the closest available driver for a given
  /// vehicle type near [lat]/[lng], or null if none are currently available.
  Future<int?> getClosestDriverEtaMinutes({
    required double lat,
    required double lng,
    required String vehicleTypeId,
  }) async {
    final data = await api.get(ApiConstants.availableDrivers, query: {
      'lat': lat,
      'lng': lng,
      'vehicleTypeId': vehicleTypeId,
    });
    final map = Map<String, dynamic>.from(data ?? {});
    final eta = map['closestDriverEtaMinutes'];
    if (eta == null) return null;
    return int.tryParse('$eta') ?? double.tryParse('$eta')?.round();
  }

  /// Server-computed fares (`POST /rides/quote`) — the exact amount the ride
  /// will be charged: road distance, platform fee, surge and rounding
  /// included. Coordinates are `[lng, lat]`. Returns the raw quote rows.
  Future<List<Map<String, dynamic>>> getRideQuotes({
    required List<double> pickup,
    required List<double> drop,
    List<List<double>> stops = const [],
    required List<String> vehicleTypeIds,
  }) async {
    final data = await api.post('${ApiConstants.rides}/quote', data: {
      'pickup': pickup,
      'drop': drop,
      if (stops.isNotEmpty) 'stops': stops,
      'vehicleTypeIds': vehicleTypeIds,
      'transport_type': 'taxi',
    });
    final quotes = (data is Map ? data['quotes'] : null) as List? ?? const [];
    return quotes
        .whereType<Map>()
        .map((q) => Map<String, dynamic>.from(q))
        .toList();
  }
}
