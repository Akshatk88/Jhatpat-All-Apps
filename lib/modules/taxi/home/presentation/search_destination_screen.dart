import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/modules/taxi/taxi_constants.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_controller.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_state.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/recent_searches_provider.dart';
import 'package:superapp_user/shared/search/presentation/widgets/voice_search_dialog.dart';

class _GeoResult {
  final String title;
  final String address;
  final double lat;
  final double lng;
  final String? placeId;

  /// True for the user's own recent searches, false for suggested nearby
  /// places; only changes the leading icon.
  final bool isRecent;

  /// Straight-line distance from the pickup, when known.
  final double? distanceKm;
  const _GeoResult({
    required this.title,
    required this.address,
    required this.lat,
    required this.lng,
    this.placeId,
    this.isRecent = false,
    this.distanceKm,
  });

  /// "Title, rest" — what gets stored on the booking and in recent searches.
  /// [address] alone may be just the secondary line under the title.
  String get fullAddress =>
      address.toLowerCase().startsWith(title.toLowerCase()) ? address : '$title, $address';

  /// Copy with [distanceKm] measured from [origin]. Results without real
  /// coordinates yet (Google predictions resolve them on tap) keep theirs.
  _GeoResult withDistanceFrom(BookingLocation? origin) {
    if (origin == null || (lat == 0 && lng == 0)) return this;
    return _GeoResult(
      title: title,
      address: address,
      lat: lat,
      lng: lng,
      placeId: placeId,
      isRecent: isRecent,
      distanceKm:
          Geolocator.distanceBetween(origin.lat, origin.lng, lat, lng) / 1000,
    );
  }
}

enum FieldTargetType { pickup, drop, stop }

class FieldTarget {
  final FieldTargetType type;
  final int? stopIndex;
  const FieldTarget.pickup() : type = FieldTargetType.pickup, stopIndex = null;
  const FieldTarget.drop() : type = FieldTargetType.drop, stopIndex = null;
  const FieldTarget.stop(int index) : type = FieldTargetType.stop, stopIndex = index;
}

class SearchDestinationScreen extends ConsumerStatefulWidget {
  const SearchDestinationScreen({super.key});

  @override
  ConsumerState<SearchDestinationScreen> createState() => _SearchDestinationScreenState();
}

class _SearchDestinationScreenState extends ConsumerState<SearchDestinationScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  final List<TextEditingController> _stopControllers = [];
  final List<BookingLocation?> _stops = [];

  Timer? _debounce;
  List<_GeoResult> _results = [];

  /// The query the visible results belong to; a slower, older search must
  /// not overwrite results for what the user has typed since.
  String _latestQuery = '';

  /// Prominent places around the pickup, shown under recent searches so the
  /// list is never near-empty for a new user.
  List<_GeoResult> _nearby = [];

  /// The empty-query list always aims to show at least this many entries.
  static const _minSuggestions = 7;
  bool _searching = false;
  FieldTarget _activeTarget = const FieldTarget.drop();

  BookingLocation? _pickup;
  BookingLocation? _drop;
  String _sessionToken = '';

  void _ensureSessionToken() {
    if (_sessionToken.isEmpty) {
      _sessionToken =
          '${DateTime.now().millisecondsSinceEpoch}_${1000 + (DateTime.now().microsecondsSinceEpoch % 9000)}';
    }
  }

  @override
  void initState() {
    super.initState();
    _prefillCurrentLocation();
  }

  Future<void> _prefillCurrentLocation() async {
    final address = await ref.read(currentAddressProvider.future);
    final position = await ref.read(currentPositionProvider.future);
    if (!mounted) return;
    final lat = position?.latitude ?? 22.7196;
    final lng = position?.longitude ?? 75.8577;
    final finalAddress = address.isNotEmpty ? address : 'Current Location';
    setState(() {
      _pickup = BookingLocation(lat: lat, lng: lng, address: finalAddress);
      _pickupController.text = finalAddress;
    });
    _loadNearbyPlaces(lat, lng);
  }

  /// Fetches prominent places near the pickup (Places Nearby Search). Widens
  /// the radius once if the first pass is too sparse to fill the list.
  Future<void> _loadNearbyPlaces(double lat, double lng) async {
    final key = TaxiConstants.mapKey;
    if (key.isEmpty) return;

    final dio = Dio();
    final found = <_GeoResult>[];
    final seen = <String>{};
    for (final radius in const [5000, 20000]) {
      try {
        final response = await dio.get(
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
          queryParameters: {
            'location': '$lat,$lng',
            'radius': radius,
            'key': key,
          },
        );
        final data = response.data;
        if (data == null || data['status'] != 'OK') continue;
        for (final raw in (data['results'] as List? ?? const [])) {
          final item = raw as Map;
          final types = (item['types'] as List?)?.cast<String>() ?? const [];
          // Cities and regions are not somewhere a rider gets dropped.
          if (types.contains('locality') || types.contains('political')) continue;
          final name = (item['name'] ?? '').toString().trim();
          final loc = (item['geometry'] as Map?)?['location'] as Map?;
          final pLat = (loc?['lat'] as num?)?.toDouble();
          final pLng = (loc?['lng'] as num?)?.toDouble();
          if (name.isEmpty || pLat == null || pLng == null) continue;
          if (!seen.add(name.toLowerCase())) continue;
          final vicinity = (item['vicinity'] ?? '').toString().trim();
          found.add(_GeoResult(
            title: name,
            address: vicinity.isNotEmpty ? '$name, $vicinity' : name,
            lat: pLat,
            lng: pLng,
          ));
        }
      } catch (e) {
        debugPrint('Nearby places error: $e');
      }
      if (found.length >= _minSuggestions + 3) break;
    }

    // Google returns REQUEST_DENIED when the Cloud project has no billing, so
    // fall back to OpenStreetMap (Photon) rather than leave the list bare.
    if (found.length < _minSuggestions) {
      try {
        final response = await dio.get(
          'https://photon.komoot.io/reverse',
          queryParameters: {
            'lat': lat,
            'lon': lng,
            'radius': 5,
            'limit': 25,
            'osm_tag': [
              'amenity',
              'shop:mall',
              'leisure:park',
              'tourism',
              'railway:station',
            ],
          },
          options: Options(
            headers: {'User-Agent': 'SuperAppUser/1.0'},
            listFormat: ListFormat.multi,
          ),
        );
        final features = (response.data?['features'] as List?) ?? const [];
        for (final raw in features) {
          final feature = raw as Map;
          final props = (feature['properties'] as Map?) ?? const {};
          final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
          final name = (props['name'] ?? '').toString().trim();
          if (name.isEmpty || coords == null || coords.length < 2) continue;
          if (!seen.add(name.toLowerCase())) continue;
          final detail = [props['street'], props['district'], props['city']]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          found.add(_GeoResult(
            title: name,
            address: detail.isNotEmpty ? '$name, $detail' : name,
            lat: (coords[1] as num).toDouble(),
            lng: (coords[0] as num).toDouble(),
          ));
          if (found.length >= _minSuggestions + 3) break;
        }
      } catch (e) {
        debugPrint('OSM nearby places error: $e');
      }
    }

    if (mounted) setState(() => _nearby = found);
  }

  int? _findFirstEmptyStopIndex() {
    for (int i = 0; i < _stopControllers.length; i++) {
      if (i >= _stops.length || _stops[i] == null || _stopControllers[i].text.trim().isEmpty) {
        return i;
      }
    }
    return null;
  }

  void _addStop() {
    setState(() {
      final controller = TextEditingController();
      _stopControllers.add(controller);
      _stops.add(null);
      _activeTarget = FieldTarget.stop(_stopControllers.length - 1);
    });
    SnackbarUtils.info(context, 'Stop added after drop location'.tr);
  }

  void _removeStop(int index) {
    final removedController = _stopControllers[index];
    setState(() {
      _stopControllers.removeAt(index);
      _stops.removeAt(index);
      if (_activeTarget.type == FieldTargetType.stop && _activeTarget.stopIndex == index) {
        _activeTarget = const FieldTarget.drop();
      } else if (_activeTarget.type == FieldTargetType.stop &&
          _activeTarget.stopIndex != null &&
          _activeTarget.stopIndex! > index) {
        _activeTarget = FieldTarget.stop(_activeTarget.stopIndex! - 1);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      removedController.dispose();
    });
  }

  void _reorderDestinations(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      if (oldIndex == newIndex) return;

      final allLocations = <BookingLocation?>[_drop, ..._stops];
      final movedLocation = allLocations.removeAt(oldIndex);
      allLocations.insert(newIndex, movedLocation);

      _drop = allLocations[0];
      _dropController.text = _drop?.address ?? '';

      for (int i = 0; i < _stops.length; i++) {
        _stops[i] = allLocations[i + 1];
        _stopControllers[i].text = _stops[i]?.address ?? '';
      }
    });

    if (_pickup != null && _drop != null) {
      final validStops = _stops.whereType<BookingLocation>().toList();
      ref.read(bookingControllerProvider.notifier)
        ..setPickup(_pickup!)
        ..setStops(validStops)
        ..setDrop(_drop!);
    }
  }

  void _swapLocations(int indexA, int indexB) {
    if (indexA == indexB) return;
    _reorderDestinations(indexA, indexB > indexA ? indexB : indexB + 1);
  }

  Widget _buildTimelineDot({
    required Color color,
    required bool showTopLine,
    required bool showBottomLine,
    required bool isDark,
  }) {
    final lineColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    return SizedBox(
      width: 24,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              width: 2,
              color: showTopLine ? lineColor : Colors.transparent,
            ),
          ),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
            ),
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: 2,
              color: showBottomLine ? lineColor : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  /// Voice input for the drop field: the spoken place goes into the field and
  /// is searched exactly as if it had been typed.
  Future<void> _dictateDrop() async {
    final spoken = await VoiceSearchDialog.show(
      context,
      hint: 'Say where you want to go, e.g. "Vijay Nagar"'.tr,
      quickTerms: const [],
    );
    final text = spoken?.trim() ?? '';
    if (!mounted || text.isEmpty) return;
    setState(() {
      _activeTarget = const FieldTarget.drop();
      _drop = null;
      _dropController.text = text;
      _dropController.selection = TextSelection.collapsed(offset: text.length);
    });
    _onQueryChanged(text);
  }

  /// One client for every search: a new Dio per keystroke paid a fresh TLS
  /// handshake each time. Short timeouts so a slow provider can't stall it.
  static final Dio _http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 6),
  ));

  /// Google Places answers REQUEST_DENIED while the Cloud project has no
  /// billing. Once seen, skip Google for the rest of the session instead of
  /// waiting on that refusal before every single OpenStreetMap search.
  static bool _googlePlacesDenied = false;

  /// Results already fetched this session, by query — retyping or deleting a
  /// letter shows them instantly.
  static final Map<String, List<_GeoResult>> _searchCache = {};

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() => _results = []);
      return;
    }
    final cached = _searchCache[trimmed.toLowerCase()];
    if (cached != null) {
      _latestQuery = trimmed;
      setState(() {
        _results = cached;
        _searching = false;
      });
      return;
    }
    // Instant matches from recent searches and nearby places while the
    // network search runs, so the list never sits empty.
    final local = _localMatches(trimmed);
    setState(() {
      if (local.isNotEmpty) _results = local;
      _searching = true;
    });
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  List<_GeoResult> _localMatches(String query) {
    final q = query.toLowerCase();
    final recents = ref.read(recentSearchesProvider).map((p) {
      final parts = p.address.split(',');
      return _GeoResult(
        title: parts.first.trim(),
        address: p.address,
        lat: p.lat,
        lng: p.lng,
        isRecent: true,
      ).withDistanceFrom(_pickup);
    });
    final seen = <String>{};
    return [...recents, ..._nearby]
        .where((r) =>
            r.title.toLowerCase().contains(q) ||
            r.address.toLowerCase().contains(q))
        .where((r) => seen.add(r.title.toLowerCase()))
        .take(5)
        .toList();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    _ensureSessionToken();
    _latestQuery = trimmed;
    final origin = _pickup;

    // OpenStreetMap starts at once, in parallel with Google, so a Google
    // refusal costs no extra round trip.
    final osmFuture = _searchOsm(trimmed, origin);

    if (_googlePlacesDenied || TaxiConstants.mapKey.isEmpty) {
      final osmResults = await osmFuture;
      if (!mounted || _latestQuery != trimmed) return;
      if (osmResults.isNotEmpty) {
        _searchCache[trimmed.toLowerCase()] = osmResults;
        setState(() {
          _results = osmResults;
          _searching = false;
        });
        return;
      }
      await _searchNativeOrEmpty(trimmed);
      return;
    }

    try {
      final dio = _http;
      final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': trimmed,
          'key': TaxiConstants.mapKey,
          'sessiontoken': _sessionToken,
          'components': 'country:in',
          // Rank places near the pickup first and get each one's distance.
          if (origin != null) ...{
            'location': '${origin.lat},${origin.lng}',
            'radius': 50000,
            'origin': '${origin.lat},${origin.lng}',
          },
        },
      );

      if (response.data != null && response.data['status'] == 'OK') {
        final predictions = response.data['predictions'] as List;
        final geoResults = predictions.map((item) {
          final description = (item['description'] ?? '') as String;
          final mainText =
              (item['structured_formatting']?['main_text'] ?? description.split(',').first) as String;
          final secondary =
              (item['structured_formatting']?['secondary_text'] ?? description) as String;
          final placeId = (item['place_id'] ?? '') as String;
          final meters = item['distance_meters'] as num?;
          return _GeoResult(
            title: mainText,
            address: secondary,
            placeId: placeId,
            lat: 0,
            lng: 0,
            distanceKm: meters == null ? null : meters / 1000,
          );
        }).toList();

        _searchCache[trimmed.toLowerCase()] = geoResults;
        if (mounted && _latestQuery == trimmed) {
          setState(() {
            _results = geoResults;
            _searching = false;
          });
        }
        return;
      }
      final status = response.data?['status']?.toString();
      if (status == 'REQUEST_DENIED' || status == 'OVER_DAILY_LIMIT') {
        _googlePlacesDenied = true;
      }
    } catch (e) {
      debugPrint('Google Places Autocomplete REST error: $e');
    }

    // Google refuses while the Cloud project has no billing; OpenStreetMap
    // (Photon) — already in flight — still gives named places near pickup.
    final osmResults = await osmFuture;
    if (!mounted || _latestQuery != trimmed) return;
    if (osmResults.isNotEmpty) {
      _searchCache[trimmed.toLowerCase()] = osmResults;
      setState(() {
        _results = osmResults;
        _searching = false;
      });
      return;
    }

    await _searchNativeOrEmpty(trimmed);
  }

  /// Last resort: the device geocoder, else an empty list with a message.
  Future<void> _searchNativeOrEmpty(String trimmed) async {
    try {
      final locations = await locationFromAddress(trimmed);
      if (mounted && locations.isNotEmpty) {
        setState(() {
          _results = locations
              .take(6)
              .map((l) => _GeoResult(
                    title: trimmed.split(',').first,
                    address: trimmed,
                    lat: l.latitude,
                    lng: l.longitude,
                  ))
              .toList();
          _searching = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Native geocoding error: $e');
    }

    if (mounted) {
      setState(() {
        _results = [];
        _searching = false;
      });
      SnackbarUtils.info(context, 'No matching places found'.tr);
    }
  }

  /// Place search over OpenStreetMap via Photon, biased to [origin] and
  /// limited to India, nearest first.
  Future<List<_GeoResult>> _searchOsm(String query, BookingLocation? origin) async {
    try {
      final response = await _http.get(
        'https://photon.komoot.io/api/',
        queryParameters: {
          'q': query,
          'limit': 15,
          // India's bounding box: without it most matches are from abroad.
          'bbox': '68.1,6.5,97.5,35.7',
          if (origin != null) ...{'lat': origin.lat, 'lon': origin.lng},
        },
        options: Options(headers: {'User-Agent': 'SuperAppUser/1.0'}),
      );
      final features = (response.data?['features'] as List?) ?? const [];
      final seen = <String>{};
      final results = <_GeoResult>[];
      for (final raw in features) {
        final feature = raw as Map;
        final props = (feature['properties'] as Map?) ?? const {};
        if ((props['countrycode'] ?? '').toString().toUpperCase() != 'IN') continue;
        final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;
        final name = (props['name'] ?? props['street'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final detail = [
          props['street'],
          props['district'],
          props['city'],
          props['state'],
        ]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && s != name)
            .toSet()
            .join(', ');
        if (!seen.add('${name.toLowerCase()}|$detail')) continue;
        results.add(_GeoResult(
          title: name,
          address: detail.isNotEmpty ? detail : name,
          lat: (coords[1] as num).toDouble(),
          lng: (coords[0] as num).toDouble(),
        ).withDistanceFrom(origin));
      }
      results.sort((a, b) =>
          (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity));
      return results.take(10).toList();
    } catch (e) {
      debugPrint('OSM place search error: $e');
      return const [];
    }
  }

  Future<void> _selectResult(_GeoResult result) async {
    double lat = result.lat;
    double lng = result.lng;

    if (result.placeId != null && result.placeId!.isNotEmpty) {
      try {
        final dio = Dio();
        final response = await dio.get(
          'https://maps.googleapis.com/maps/api/place/details/json',
          queryParameters: {
            'place_id': result.placeId,
            'key': TaxiConstants.mapKey,
            'sessiontoken': _sessionToken,
            'fields': 'formatted_address,geometry',
          },
        );

        if (response.data != null && response.data['status'] == 'OK') {
          final loc = response.data['result']['geometry']['location'];
          lat = (loc['lat'] as num).toDouble();
          lng = (loc['lng'] as num).toDouble();
        }
      } catch (e) {
        debugPrint('Place Details fetch error: $e');
      } finally {
        _sessionToken = '';
      }
    }

    if (lat == 0 && lng == 0) {
      if (mounted) {
        SnackbarUtils.info(context, 'Could not locate that place. Please pick another.'.tr);
      }
      return;
    }

    final location = BookingLocation(lat: lat, lng: lng, address: result.fullAddress);
    ref.read(recentSearchesProvider.notifier).add(address: result.fullAddress, lat: lat, lng: lng);

    setState(() {
      if (_activeTarget.type == FieldTargetType.pickup) {
        _pickup = location;
        _pickupController.text = result.fullAddress;
        if (_drop == null) {
          _activeTarget = const FieldTarget.drop();
        }
      } else if (_activeTarget.type == FieldTargetType.drop) {
        _drop = location;
        _dropController.text = result.fullAddress;
        final nextEmpty = _findFirstEmptyStopIndex();
        if (nextEmpty != null) {
          _activeTarget = FieldTarget.stop(nextEmpty);
        }
      } else if (_activeTarget.type == FieldTargetType.stop &&
          _activeTarget.stopIndex != null &&
          _activeTarget.stopIndex! < _stops.length) {
        final idx = _activeTarget.stopIndex!;
        _stops[idx] = location;
        _stopControllers[idx].text = result.fullAddress;
        final nextEmpty = _findFirstEmptyStopIndex();
        if (nextEmpty != null) {
          _activeTarget = FieldTarget.stop(nextEmpty);
        }
      }
      _results = [];
    });

    _tryProceedToRideTypes();
  }

  void _tryProceedToRideTypes({bool isExplicitContinue = false}) {
    if (_pickup == null || _drop == null) {
      if (isExplicitContinue) {
        if (_pickup == null) {
          SnackbarUtils.info(context, 'Please enter pickup location'.tr);
        } else {
          SnackbarUtils.info(context, 'Please enter drop location'.tr);
        }
      }
      return;
    }

    final firstEmptyStopIdx = _findFirstEmptyStopIndex();
    final allStopsFilled = firstEmptyStopIdx == null;

    if (!allStopsFilled) {
      if (isExplicitContinue) {
        setState(() {
          _activeTarget = FieldTarget.stop(firstEmptyStopIdx);
        });
        if (mounted) {
          SnackbarUtils.info(
              context,
              'Please enter location for Stop {n}'.trArgs({'n': firstEmptyStopIdx + 1}),
            );
        }
      }
      return;
    }

    final validStops = _stops.whereType<BookingLocation>().toList();
    ref.read(bookingControllerProvider.notifier)
      ..setPickup(_pickup!)
      ..setStops(validStops)
      ..setDrop(_drop!)
      ..goToStep(BookingStep.selectingVehicle);

    if (mounted) {
      // Close the keyboard first, otherwise it stays open over the vehicle
      // screen and squeezes its bottom sheet.
      FocusManager.instance.primaryFocus?.unfocus();
      context.push('/taxi/vehicles');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    for (final c in _stopControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    final recentSearches = ref.watch(recentSearchesProvider);
    final displayPlaces = recentSearches
        .map((place) => _GeoResult(
              title: place.address.split(',').first,
              address: place.address,
              lat: place.lat,
              lng: place.lng,
              isRecent: true,
            ))
        .toList();
    // Recent searches first, then nearby suggestions, so a new user with one
    // or no recent search still gets at least [_minSuggestions] to pick from.
    final recentTitles = displayPlaces.map((p) => p.title.toLowerCase()).toSet();
    displayPlaces.addAll(
      _nearby.where((p) => !recentTitles.contains(p.title.toLowerCase())),
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        // Tablets / desktop: keep the search column phone-width and centred.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
          children: [
            // --- TOP HEADER BAR ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => context.pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.arrow_back_rounded, color: textPrimary, size: 24),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Drop'.tr,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // --- ROUTE INPUT CARD: Pickup -> Drop -> Stops (After Drop) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Pickup Row
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          _buildTimelineDot(
                            color: const Color(0xFF10B981),
                            showTopLine: false,
                            showBottomLine: true,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _pickupController,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: textPrimary,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                fillColor: Colors.transparent,
                                hintText: 'Pickup location'.tr,
                                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                              ),
                              onTap: () => setState(() {
                                _activeTarget = const FieldTarget.pickup();
                              }),
                              onChanged: (v) {
                                setState(() {
                                  _activeTarget = const FieldTarget.pickup();
                                });
                                _onQueryChanged(v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, thickness: 1, color: dividerColor),

                    // 2. Reorderable Destinations List (Drop + Stops)
                    // With the keyboard up, drop + several stops pushed the
                    // results list and Continue button off the bottom
                    // (RenderFlex overflow). Cap the rows and let them scroll.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.viewInsetsOf(context).bottom > 0
                            ? 90
                            : double.infinity,
                      ),
                      child:
                    // ignore: deprecated_member_use
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      buildDefaultDragHandles: false,
                      // ignore: deprecated_member_use
                    onReorder: _reorderDestinations,
                      itemCount: 1 + _stopControllers.length,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // Drop Location Row
                          return Column(
                            key: const ValueKey('drop_location_row'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 44,
                                child: Row(
                                  children: [
                                    _buildTimelineDot(
                                      color: const Color(0xFFE5A600),
                                      showTopLine: true,
                                      showBottomLine: _stopControllers.isNotEmpty,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: _dropController,
                                        autofocus: _stopControllers.isEmpty,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          fillColor: Colors.transparent,
                                          hintText: 'Drop location'.tr,
                                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                                          // Speak the destination instead of typing it.
                                          suffixIcon: IconButton(
                                            tooltip: 'Say where to go'.tr,
                                            visualDensity: VisualDensity.compact,
                                            icon: const Icon(Icons.mic_rounded, size: 20, color: Color(0xFFE5A600)),
                                            onPressed: () => _dictateDrop(),
                                          ),
                                          suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                                        ),
                                        onTap: () => setState(() {
                                          _activeTarget = const FieldTarget.drop();
                                        }),
                                        onChanged: (v) {
                                          setState(() {
                                            _activeTarget = const FieldTarget.drop();
                                          });
                                          _onQueryChanged(v);
                                        },
                                      ),
                                    ),
                                    if (_stopControllers.isNotEmpty)
                                      ReorderableDragStartListener(
                                        index: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          child: const Icon(
                                            Icons.swap_vert_rounded,
                                            color: Color(0xFFE5A600),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Stop Row (index - 1)
                          final i = index - 1;
                          return Column(
                            key: ValueKey('stop_row_$i'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Divider(height: 1, thickness: 1, color: dividerColor),
                              SizedBox(
                                height: 44,
                                child: Row(
                                  children: [
                                    _buildTimelineDot(
                                      color: const Color(0xFF3B82F6),
                                      showTopLine: true,
                                      showBottomLine: i < _stopControllers.length - 1,
                                      isDark: isDark,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: _stopControllers[i],
                                        autofocus: i == _stopControllers.length - 1,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: textPrimary,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          fillColor: Colors.transparent,
                                          hintText: 'Stop {n} location'.trArgs({'n': i + 1}),
                                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                                        ),
                                        onTap: () => setState(() {
                                          _activeTarget = FieldTarget.stop(i);
                                        }),
                                        onChanged: (v) {
                                          setState(() {
                                            _activeTarget = FieldTarget.stop(i);
                                          });
                                          _onQueryChanged(v);
                                        },
                                      ),
                                    ),
                                    // Swap / Drag & Drop Handle
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: InkWell(
                                        onTap: () => _swapLocations(0, index),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          child: const Icon(
                                            Icons.swap_vert_rounded,
                                            color: Color(0xFFEF4444),
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Close Button
                                    GestureDetector(
                                      onTap: () => _removeStop(i),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // --- ACTION SHORTCUT CHIPS (Select on map / Add stops) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // "Select on map" Chip (Left)
                  Flexible(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => context.push('/taxi/pick-on-map?type=drop').then(_handleMapPickerResult),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_outlined, color: textPrimary, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Select on map'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // "Add stops" Chip (Right Side)
                  Flexible(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _addStop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor, width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle, color: textPrimary, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Add stops'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: dividerColor),

            if (_searching) const LinearProgressIndicator(minHeight: 2, color: TaxiColors.primaryOrange),

            // --- RECENT SEARCHES & LIVE RESULTS LIST ---
            Expanded(
              child: _results.isNotEmpty
                  ? ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _results.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: dividerColor),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return _DestinationListItem(
                          item: item,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () => _selectResult(item),
                        );
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: displayPlaces.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: dividerColor),
                      itemBuilder: (context, index) {
                        final item = displayPlaces[index].withDistanceFrom(_pickup);
                        return _DestinationListItem(
                          item: item,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTap: () => _selectResult(item),
                        );
                      },
                    ),
            ),

            // --- BOTTOM CONTINUE BUTTON BAR ---
            // Hidden while typing: with the keyboard up, the header, route card,
            // chips and this bar left almost no height for the results and the
            // column overflowed on smaller phones. Picking a result proceeds
            // on its own, so the button is not needed mid-typing.
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: const Color(0xFF121212),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => _tryProceedToRideTypes(isExplicitContinue: true),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue'.tr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
        ),
      ),
    );
  }

  void _handleMapPickerResult(dynamic result) {
    if (result is! Map) return;
    final location = BookingLocation(
      lat: result['lat'] as double,
      lng: result['lng'] as double,
      address: result['address'] as String,
    );
    setState(() {
      if (result['type'] == 'pickup') {
        _pickup = location;
        _pickupController.text = location.address;
      } else {
        _drop = location;
        _dropController.text = location.address;
      }
    });

    _tryProceedToRideTypes();
  }
}

class _DestinationListItem extends StatelessWidget {
  final _GeoResult item;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _DestinationListItem({
    required this.item,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  static String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              // Leading icon with the distance from pickup underneath.
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isRecent ? Icons.history_rounded : Icons.location_on_rounded,
                      color: textSecondary,
                      size: 22,
                    ),
                    if (item.distanceKm != null) ...[
                      const SizedBox(height: 2),
                      // Shrinks rather than clipping "9.9 km" to "9.9 k…"
                      // at large text sizes.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatDistance(item.distanceKm!),
                          maxLines: 1,
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Title & Address Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Favorite Heart Icon
              GestureDetector(
                onTap: () {
                  SnackbarUtils.info(context, 'Saved to favorite places'.tr);
                },
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.favorite_border_rounded, color: Color(0xFF94A3B8), size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
