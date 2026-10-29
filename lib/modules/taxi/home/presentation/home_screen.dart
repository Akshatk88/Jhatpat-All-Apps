import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/maps/app_map_style.dart';
import 'package:superapp_user/core/utils/haptics.dart';

import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_controller.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_state.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/modules/taxi/home/application/popular_places_provider.dart';
import 'package:superapp_user/modules/taxi/home/application/recent_searches_provider.dart';
import 'package:superapp_user/modules/taxi/home/application/saved_places_provider.dart';
import 'package:superapp_user/modules/taxi/home/data/models/app_module_model.dart';
import 'package:superapp_user/modules/taxi/home/data/models/saved_address_model.dart';
import 'package:superapp_user/modules/taxi/home/presentation/nearby_driver_markers.dart';
import 'package:superapp_user/modules/taxi/taxi_route_names.dart';

class TaxiHomeScreen extends ConsumerStatefulWidget {
  const TaxiHomeScreen({super.key});

  @override
  ConsumerState<TaxiHomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<TaxiHomeScreen> {
  late PageController _pageController;
  Timer? _bannerTimer;
  int _currentBannerIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startBannerAutoSlide();
    // The vehicle and price catalogue is a slow download (the server inlines
    // base64 icons); start it now so it is ready by the vehicle list.
    ref.read(homeRepositoryProvider).prefetchCatalog();
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(
      const Duration(seconds: 3, milliseconds: 500),
      (timer) {
        if (!mounted) return;
        final count = _bannerCount;
        if (count <= 1) return;

        final nextIndex = (_currentBannerIndex + 1) % count;
        if (_pageController.hasClients) {
          if (nextIndex == 0) {
            _pageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
            );
          } else {
            _pageController.nextPage(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pageController.dispose();
    _sheetController.dispose();
    _sheetExtent.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  List<Map<String, String>> _getBannerList() {
    final banners = ref.watch(bannersProvider).value ?? const [];
    if (banners.isNotEmpty) {
      return banners
          .map(
            (b) => {
              'image': (b['image'] ?? '').toString(),
              'link': (b['link'] ?? '').toString(),
            },
          )
          .toList();
    }
    // Default promotional banner list for infinite loop sliding
    return const [
      {'image': 'assets/images/taxi/banner.png', 'link': ''},
      {'image': 'assets/images/taxi/banner.png', 'link': ''},
      {'image': 'assets/images/taxi/banner.png', 'link': ''},
    ];
  }

  int get _bannerCount => _getBannerList().length;

  /// Promotional banner carousel with auto-sliding infinite loop
  Widget _buildPromoBanner() {
    final banners = _getBannerList();

    return SizedBox(
      height: 115,
      width: double.infinity,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentBannerIndex = index;
          });
        },
        itemCount: banners.length,
        itemBuilder: (context, index) {
          final item = banners[index];
          final img = item['image'] ?? '';
          final link = item['link'] ?? '';

          Widget imageWidget;
          if (img.startsWith('http')) {
            imageWidget = CachedNetworkImage(
              imageUrl: img,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 115,
              placeholder: (context, url) =>
                  Image.asset('assets/images/taxi/banner.png', fit: BoxFit.cover),
              errorWidget: (context, url, error) =>
                  Image.asset('assets/images/taxi/banner.png', fit: BoxFit.cover),
            );
          } else {
            imageWidget = Image.asset(
              img.isNotEmpty ? img : 'assets/images/taxi/banner.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: 115,
              errorBuilder: (context, error, stackTrace) =>
                  Image.asset('assets/images/taxi/banner.png', fit: BoxFit.cover),
            );
          }

          return GestureDetector(
            onTap: link.isEmpty ? null : () => _openBannerLink(link),
            child: imageWidget,
          );
        },
      ),
    );
  }

  Future<void> _openBannerLink(String link) async {
    // Deep links stay inside the app; anything else is a normal URL.
    if (link.startsWith('/')) {
      if (mounted) context.push(link);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleHomeWorkTap(
    String slotType,
    SavedAddressModel? saved,
  ) async {
    if (saved == null) {
      // '/home/map-picker' is the standalone taxi app's path and is not
      // registered in super_app's router, so this push never resolved: the map
      // never opened, nothing could be saved, and the shortcut could therefore
      // never book a ride either. The route lives at TaxiRoutePaths.pickOnMap.
      final result = await context.push<Map<String, dynamic>>(
        '${TaxiRoutePaths.pickOnMap}?type=drop',
      );
      if (result != null && mounted) {
        final String addr = result['address'] ?? '';
        final double lat = (result['lat'] as num?)?.toDouble() ?? 0;
        final double lng = (result['lng'] as num?)?.toDouble() ?? 0;
        if (addr.isNotEmpty && lat != 0 && lng != 0) {
          await ref
              .read(savedPlacesProvider.notifier)
              .saveHomeOrWork(
                type: slotType,
                address: addr,
                lat: lat,
                lng: lng,
              );
          if (mounted) {
            SnackbarUtils.info(
              context,
              (slotType.toLowerCase() == 'home'
                      ? 'Home location saved!'
                      : 'Work location saved!')
                  .tr,
            );
          }
        }
      }
    } else {
      await _bookTo(saved.lat, saved.lng, saved.address);
    }
  }

  /// Books a ride from the rider's current location to the given drop.
  Future<void> _bookTo(double lat, double lng, String address) async {
    // currentPositionProvider is a FutureProvider, so `.value` is null until
    // it resolves — which it usually has not on a cold open, exactly when
    // someone taps a shortcut. The old fallback quietly booked from Indore
    // city centre, sending a driver to a place the rider had never been.
    // Wait for the real fix instead, and say so rather than inventing one.
    Position? currentPos = ref.read(currentPositionProvider).value;
    if (currentPos == null) {
      try {
        currentPos = await ref.read(currentPositionProvider.future);
      } catch (_) {
        currentPos = null;
      }
    }
    if (!mounted) return;
    if (currentPos == null) {
      SnackbarUtils.info(
        context,
        'Still finding your location — try again in a moment.'.tr,
      );
      return;
    }

    final pickupAddr =
        ref.read(currentAddressProvider).value ?? 'Current Location';
    final pickupLoc = BookingLocation(
      lat: currentPos.latitude,
      lng: currentPos.longitude,
      address: pickupAddr,
    );

    final dropLoc = BookingLocation(lat: lat, lng: lng, address: address);

    ref.read(bookingControllerProvider.notifier)
      ..setPickup(pickupLoc)
      ..setDrop(dropLoc);

    if (mounted) {
      context.push('/taxi/vehicles');
    }
  }

  Widget _buildOngoingRideCard(BuildContext context) {
    final ride = ref.watch(myActiveRideProvider).value;
    if (ride == null) return const SizedBox.shrink();

    const finished = {'completed', 'cancelled', 'canceled'};
    if (finished.contains(ride.liveStatus) || finished.contains(ride.status)) {
      return const SizedBox.shrink();
    }



    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: GestureDetector(
        onTap: () async {
          await context.push('/taxi/rides/${ride.rideId}/track');
          if (context.mounted) ref.invalidate(myActiveRideProvider);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 10,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_car_rounded, color: Color(0xFF121212), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'ONGOING RIDE'.tr,
                          style: const TextStyle(
                            color: Color(0xFF121212),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        '₹${ride.fare.round()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.white.withValues(alpha: 0.1), height: 1, thickness: 1),
              const SizedBox(height: 8),
              // Addresses
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 5),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981), // Green
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 14,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444), // Red
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.pickupAddress.isNotEmpty ? ride.pickupAddress : 'Pickup Location'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ride.dropAddress.isNotEmpty ? ride.dropAddress : 'Drop Location'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Layout: live map on top, a draggable sheet over it ───────────────────

  /// Resting height of the sheet as a fraction of the body. It never goes
  /// lower, so the pickup pin (centred in the strip above it) stays put.
  static const double _sheetMin = 0.52;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final ValueNotifier<double> _sheetExtent = ValueNotifier(_sheetMin);
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final position = ref.watch(currentPositionProvider).value;
    final pickup = position == null
        ? null
        : LatLng(position.latitude, position.longitude);

    // Follow the app-wide location: picking another address re-centres the map.
    ref.listen(currentPositionProvider, (prev, next) {
      final p = next.value;
      if (p == null) return;
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)),
      );
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final sheetTop = height * (1 - _sheetMin);

          return Stack(
            children: [
              Positioned.fill(
                child: _buildMap(pickup, height * _sheetMin),
              ),

              // Pickup pin, centred in the strip of map above the sheet —
              // which is exactly where the padded map puts its camera target.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: sheetTop,
                child: const IgnorePointer(
                  child: Center(
                    child: Padding(
                      // The widget is centred; lift it so the dot (not the
                      // middle of the label + stem) sits on the target.
                      padding: EdgeInsets.only(bottom: _PickupPin.dotLift * 2),
                      child: _PickupPin(),
                    ),
                  ),
                ),
              ),

              // Current pickup address, floating just above the sheet.
              Positioned(
                left: 16,
                right: 16,
                top: (sheetTop - 66).clamp(0.0, double.infinity),
                child: ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, child) {
                    final visible = extent < _sheetMin + 0.08;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: visible ? 1 : 0,
                      child: IgnorePointer(ignoring: !visible, child: child),
                    );
                  },
                  child: _PickupAddressPill(
                    address: ref.watch(currentAddressProvider).value,
                    isDark: isDark,
                    // The header has no location card on this screen, so the
                    // pill is where the pickup location is changed.
                    onTap: () {
                      Haptics.light();
                      context.push(AppRoutePaths.addresses);
                    },
                  ),
                ),
              ),

              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  _sheetExtent.value = n.extent;
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetMin,
                  minChildSize: _sheetMin,
                  maxChildSize: 1.0,
                  builder: (context, scrollController) =>
                      _buildSheet(scrollController, isDark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMap(LatLng? pickup, double bottomPadding) {
    return GoogleMap(
      style: AppMapStyle.muted,
      initialCameraPosition: CameraPosition(
        target: pickup ?? const LatLng(22.7196, 75.8577),
        zoom: 16,
      ),
      // Keeps the camera target in the visible strip, under the pin.
      padding: EdgeInsets.only(bottom: bottomPadding),
      onMapCreated: (controller) {
        _mapController = controller;
        final p = ref.read(currentPositionProvider).value;
        if (p != null) {
          controller.moveCamera(
            CameraUpdate.newLatLng(LatLng(p.latitude, p.longitude)),
          );
        }
      },
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      // The pin is fixed to the centre, so panning would only make it lie
      // about where pickup is. Pinch-zoom still works (around the centre).
      scrollGesturesEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      markers: buildNearbyDriverMarkers(ref),
    );
  }

  Widget _buildSheet(ScrollController scrollController, bool isDark) {
    final sheetColor = isDark ? const Color(0xFF15171C) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _SheetSearchHeader(
              background: sheetColor,
              isDark: isDark,
              onTap: () => context.push('/taxi/destination'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildOngoingRideCard(context),
                _buildRecentPlaces(isDark),
                const SizedBox(height: 16),
                _buildPopularPlaces(isDark),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(child: _SectionTitle('Explore'.tr, isDark: isDark)),
                    InkWell(
                      onTap: () => context.push('/taxi/services'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View All'.tr,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE5A600),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFE5A600),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildServicesGrid(ref.watch(appModulesProvider)),
                const SizedBox(height: 28),
                _SectionTitle('Everything in minutes'.tr, isDark: isDark),
                const SizedBox(height: 14),
                _buildEverythingInMinutes(isDark),
                const SizedBox(height: 20),
                _buildBannerSection(),
              ]),
            ),
          ),
          SliverToBoxAdapter(child: _JhatpatFooter(isDark: isDark)),
        ],
      ),
    );
  }

  // ── Recent destinations ──────────────────────────────────────────────────

  Widget _buildRecentPlaces(bool isDark) {
    final recents = ref.watch(recentSearchesProvider).take(3).toList();
    final saved = ref.watch(savedPlacesProvider);

    if (recents.isEmpty) {
      // A new rider has no history yet: offer the Home / Work shortcuts.
      SavedAddressModel? homePlace;
      SavedAddressModel? workPlace;
      for (final p in saved) {
        final t = p.type.toLowerCase();
        final l = p.label.toLowerCase();
        if (t == 'home' || l == 'home') {
          homePlace = p;
        } else if (t == 'work' || l == 'work') {
          workPlace = p;
        }
      }
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _QuickLocationCard(
              icon: Icons.business_rounded,
              iconColor: const Color(0xFF3B82F6),
              title: 'Work'.tr,
              subtitle: workPlace != null
                  ? (workPlace.address.isNotEmpty
                        ? workPlace.address
                        : 'Saved location'.tr)
                  : 'Set location'.tr,
              onTap: () => _handleHomeWorkTap('work', workPlace),
            ),
            const SizedBox(width: 8),
            _QuickLocationCard(
              icon: Icons.home_rounded,
              iconColor: const Color(0xFFEF4444),
              title: 'Home'.tr,
              subtitle: homePlace != null
                  ? (homePlace.address.isNotEmpty
                        ? homePlace.address
                        : 'Saved location'.tr)
                  : 'Set location'.tr,
              onTap: () => _handleHomeWorkTap('home', homePlace),
            ),
            const SizedBox(width: 8),
            _QuickLocationCard(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Saved'.tr,
              subtitle: 'Your places'.tr,
              onTap: () => context.push('/taxi/saved-places'),
            ),
          ],
        ),
      );
    }

    SavedAddressModel? favouriteFor(SavedAddressModel place) {
      for (final s in saved) {
        if ((s.lat - place.lat).abs() < 0.00005 &&
            (s.lng - place.lng).abs() < 0.00005) {
          return s;
        }
      }
      return null;
    }

    return Column(
      children: [
        for (final place in recents)
          Builder(
            builder: (context) {
              final (title, subtitle) = _splitAddress(place.address);
              final favourite = favouriteFor(place);
              return _RecentPlaceTile(
                title: title,
                subtitle: subtitle,
                isFavourite: favourite != null,
                isDark: isDark,
                onTap: () => _bookTo(place.lat, place.lng, place.address),
                onToggleFavourite: () {
                  Haptics.light();
                  final notifier = ref.read(savedPlacesProvider.notifier);
                  if (favourite != null) {
                    notifier.remove(favourite.id);
                  } else {
                    notifier.add(
                      label: title,
                      address: place.address,
                      lat: place.lat,
                      lng: place.lng,
                    );
                    SnackbarUtils.info(context, 'Added to saved places'.tr);
                  }
                },
              );
            },
          ),
      ],
    );
  }

  static (String, String) _splitAddress(String address) {
    final i = address.indexOf(',');
    if (i < 0) return (address.trim(), '');
    return (address.substring(0, i).trim(), address.substring(i + 1).trim());
  }

  // ── Popular places nearby ────────────────────────────────────────────────

  Widget _buildPopularPlaces(bool isDark) {
    final placesAsync = ref.watch(popularPlacesProvider);
    final columns = (MediaQuery.sizeOf(context).width ~/ 130).clamp(3, 6);

    Widget grid(int count, Widget Function(int) itemBuilder) =>
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            mainAxisExtent: 152,
          ),
          itemCount: count,
          itemBuilder: (context, i) => itemBuilder(i),
        );

    return placesAsync.when(
      data: (places) {
        if (places.isEmpty) return const SizedBox.shrink();
        final shown = places.take(columns * 2).toList();
        return grid(shown.length, (i) {
          final place = shown[i];
          return _PopularPlaceTile(
            place: place,
            isDark: isDark,
            onTap: () {
              ref.read(recentSearchesProvider.notifier).add(
                address: place.address,
                lat: place.lat,
                lng: place.lng,
              );
              _bookTo(place.lat, place.lng, place.address);
            },
          );
        });
      },
      loading: () => grid(
        columns,
        (_) => Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  // ── "Everything in minutes" service cards ────────────────────────────────

  Widget _buildEverythingInMinutes(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _ServicePromoCard(
                height: 130,
                caption: 'Send anything',
                title: 'Parcel',
                image: 'assets/images/taxi/parcel.png',
                imageWidthFactor: 0.48,
                isDark: isDark,
                onTap: () => context.push('/parcel/vehicles'),
              ),
              const SizedBox(height: 12),
              _ServicePromoCard(
                height: 190,
                caption: 'Your everyday rides',
                title: 'Book now',
                image: 'assets/images/taxi/booknow.png',
                imageWidthFactor: 0.92,
                isDark: isDark,
                onTap: () => context.push('/taxi/destination'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _ServicePromoCard(
                height: 190,
                caption: 'Beat the traffic',
                title: 'Bike Taxi',
                image: 'assets/images/taxi/bike.png',
                imageWidthFactor: 0.78,
                isDark: isDark,
                onTap: () => context.push('/taxi/destination'),
              ),
              const SizedBox(height: 12),
              _ServicePromoCard(
                height: 130,
                caption: '',
                title: 'All\nServices',
                image: 'assets/images/taxi/allservice.png',
                imageWidthFactor: 0.42,
                isDark: isDark,
                onTap: () => context.push('/taxi/services'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBannerSection() {
    return Column(
      children: [
        InkWell(
          onTap: () => context.push('/taxi/destination'),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            height: 115,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildPromoBanner(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_bannerCount, (index) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: index == _currentBannerIndex ? 12 : 4.5,
              height: 4.5,
              decoration: BoxDecoration(
                color: index == _currentBannerIndex
                    ? const Color(0xFFFFB800)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2.5),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildServicesGrid(
    AsyncValue<List<AppModuleModel>> modulesAsync, {
    int? maxItems,
  }) {
    final bgColors = [
      const Color(0xFFFFF8E1),
      const Color(0xFFE6F8F0),
      const Color(0xFFF3E8FF),
      const Color(0xFFE0F2FE),
      const Color(0xFFFEF3C7),
    ];

    return modulesAsync.when(
      data: (modules) {
        final activeModules = modules.where((m) => m.active).toList();
        activeModules.sort((a, b) => a.orderBy.compareTo(b.orderBy));

        var listToRender = activeModules.isNotEmpty
            ? activeModules
            : _getFallbackModules();
        if (maxItems != null) {
          listToRender = listToRender.take(maxItems).toList();
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            // Four per row on phones; more columns (not giant tiles) on tablets.
            crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 110).clamp(4, 10),
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            // Sized to the content (48 icon + 6 gap + one label line + 20 padding).
            // A ratio of 0.85 avoids the RenderFlex vertical overflow on small screens.
            childAspectRatio: 0.72,
          ),
          itemCount: listToRender.length,
          itemBuilder: (context, index) {
            final item = listToRender[index];
            return _buildServiceItem(item, bgColors[index % bgColors.length]);
          },
        );
      },
      loading: () => _buildStaticServicesGrid(bgColors, maxItems: maxItems),
      error: (e, st) => _buildStaticServicesGrid(bgColors, maxItems: maxItems),
    );
  }

  Widget _buildStaticServicesGrid(List<Color> bgColors, {int? maxItems}) {
    final fallbackList = _getFallbackModules().take(maxItems ?? 99).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        // Four per row on phones; more columns (not giant tiles) on tablets.
        crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 110).clamp(4, 10),
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: fallbackList.length,
      itemBuilder: (context, index) {
        final item = fallbackList[index];
        return _buildServiceItem(item, bgColors[index % bgColors.length]);
      },
    );
  }

  Widget _buildServiceItem(AppModuleModel m, Color bgColor) {
    // Uploads often come back as relative paths ('/uploads/...').
    final String iconUrl = ApiConfig.resolveMedia(m.mobileMenuIcon);
    final String sName = m.name;
    final String sType = '${m.serviceType} ${m.transportType} ${m.name}'
        .toLowerCase();

    String fallbackAsset = 'assets/images/taxi/taxi_service.png';
    IconData fallbackIcon = Icons.local_taxi_rounded;

    if (sType.contains('bike') || sType.contains('moto')) {
      fallbackAsset = 'assets/images/taxi/bike_service.png';
      fallbackIcon = Icons.two_wheeler_rounded;
    } else if (sType.contains('parcel') || sType.contains('delivery')) {
      fallbackAsset = 'assets/images/taxi/parcel_service.png';
      fallbackIcon = Icons.inventory_2_rounded;
    } else if (sType.contains('outstation') || sType.contains('intercity')) {
      fallbackAsset = 'assets/images/taxi/outstation_service.png';
      fallbackIcon = Icons.directions_bus_rounded;
    }

    void onTap() {
      Haptics.light();
      if (sType.contains('parcel') || sType.contains('delivery')) {
        context.push('/parcel/vehicles');
      } else if (sType.contains('outstation')) {
        // No outstation screen exists in either source app -- the original
        // taxi router had no /outstation route either, so this tile has always
        // been a dead link. Outstation is a ride *type*, so start the normal
        // booking funnel; the intercity package picker
        // (GET /taxi/users/intercity-packages) is a separate build.
        context.push('/taxi/destination');
      } else {
        context.push('/taxi/destination');
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Soft colored icon box for the vehicle image
            Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: iconUrl.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: iconUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          Image.asset(fallbackAsset, fit: BoxFit.contain),
                      errorWidget: (context, url, error) => Image.asset(
                        fallbackAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          fallbackIcon,
                          color: const Color(0xFFE5A600),
                          size: 22,
                        ),
                      ),
                    )
                  : Image.asset(
                      fallbackAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        fallbackIcon,
                        color: const Color(0xFFE5A600),
                        size: 22,
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            // Service name text positioned right under the image box
            Text(
              sName.tr,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<AppModuleModel> _getFallbackModules() {
    return const [
      AppModuleModel(
        id: '1',
        name: 'Taxi',
        transportType: 'taxi',
        serviceType: 'daily',
        orderBy: 1,
        shortDescription: 'Ride in city',
        description: 'Taxi ride',
        mobileMenuIcon: '',
        active: true,
      ),
      AppModuleModel(
        id: '2',
        name: 'Bike',
        transportType: 'bike',
        serviceType: 'daily',
        orderBy: 2,
        shortDescription: 'Quick bike ride',
        description: 'Bike ride',
        mobileMenuIcon: '',
        active: true,
      ),
      AppModuleModel(
        id: '3',
        name: 'Parcel',
        transportType: 'parcel',
        serviceType: 'delivery',
        orderBy: 3,
        shortDescription: 'Send anything',
        description: 'Parcel delivery',
        mobileMenuIcon: '',
        active: true,
      ),
    ];
  }
}

/// Quick Location Card (Work, Home, Saved)
class _QuickLocationCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickLocationCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// "Pickup Point" label over a dot, drawn over the map's camera target.
class _PickupPin extends StatelessWidget {
  const _PickupPin();

  static const double _labelHeight = 36;
  static const double _stemHeight = 12;
  static const double _dotSize = 22;

  /// How far above its own centre the dot's centre sits; the caller lifts the
  /// pin by this much so the dot lands exactly on the target.
  static const double dotLift =
      (_labelHeight + _stemHeight + _dotSize / 2) -
      (_labelHeight + _stemHeight + _dotSize) / 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: _labelHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          // widthFactor 1: the label hugs its text instead of stretching
          // across the whole map.
          child: Center(
            widthFactor: 1,
            child: Text(
              'Pickup Point'.tr,
              style: const TextStyle(
                color: Color(0xFFFFC803),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Container(width: 2.5, height: _stemHeight, color: const Color(0xFF121212)),
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC803),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF121212), width: 5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The pickup address in a floating pill above the sheet.
class _PickupAddressPill extends StatelessWidget {
  const _PickupAddressPill({
    required this.address,
    required this.isDark,
    required this.onTap,
  });

  final String? address;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = (address == null || address!.isEmpty)
        ? 'Finding your location…'.tr
        : address!;
    return Material(
      color: isDark ? const Color(0xFF1F2229) : Colors.white,
      elevation: 6,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF16A34A), width: 4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grab handle + "Where do you want to go?" — stays pinned while the sheet's
/// content scrolls underneath it.
class _SheetSearchHeader extends SliverPersistentHeaderDelegate {
  _SheetSearchHeader({
    required this.background,
    required this.isDark,
    required this.onTap,
  });

  final Color background;
  final bool isDark;
  final VoidCallback onTap;

  // 10 top + 5 handle + 12 gap + 54 bar + 12 bottom.
  static const double _height = 93;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            // expand: the bar fills the slot, so the glow sits right under it.
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // Soft yellow glow under the bar, the brand accent.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -5,
                  height: 4,
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.45,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0x00FFC803),
                              Color(0xFFFFC803),
                              Color(0x00FFC803),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Material(
                  color: isDark ? const Color(0xFF1F2229) : Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : const Color(0xFFE8EDF5),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 26,
                            color: isDark ? Colors.white : const Color(0xFF121212),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Where do you want to go?'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF121212),
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
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SheetSearchHeader old) =>
      old.background != background || old.isDark != isDark;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.isDark});

  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: isDark ? Colors.white : const Color(0xFF334155),
      ),
    );
  }
}

/// One recent destination: history icon, name, address and a save heart.
class _RecentPlaceTile extends StatelessWidget {
  const _RecentPlaceTile({
    required this.title,
    required this.subtitle,
    required this.isFavourite,
    required this.isDark,
    required this.onTap,
    required this.onToggleFavourite,
  });

  final String title;
  final String subtitle;
  final bool isFavourite;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onToggleFavourite;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white54 : const Color(0xFF64748B);
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 26, color: muted),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onToggleFavourite,
                  icon: Icon(
                    isFavourite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavourite ? const Color(0xFFFFB800) : muted,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
          _DashedDivider(
            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 5.0;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}


/// A large service card: caption + title top-left, artwork bottom-right.
class _ServicePromoCard extends StatelessWidget {
  const _ServicePromoCard({
    required this.height,
    required this.caption,
    required this.title,
    required this.image,
    required this.imageWidthFactor,
    required this.isDark,
    required this.onTap,
  });

  final double height;
  final String caption;
  final String title;
  final String image;

  /// Width of the artwork as a share of the card's width.
  final double imageWidthFactor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Material(
        color: isDark ? const Color(0xFF1F2229) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Haptics.light();
            onTap();
          },
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: constraints.maxWidth * imageWidthFactor,
                  height: constraints.maxHeight * 0.68,
                  child: Image.asset(
                    image,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 10, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (caption.isNotEmpty)
                        Text(
                          caption.tr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white60
                                : const Color(0xFF64748B),
                          ),
                        ),
                      if (caption.isNotEmpty) const SizedBox(height: 3),
                      Text(
                        title.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand sign-off at the very bottom of the sheet.
class _JhatpatFooter extends StatelessWidget {
  const _JhatpatFooter({required this.isDark});

  final bool isDark;

  static const _doodles = <(IconData, double, double, double)>[
    (Icons.two_wheeler_rounded, -0.85, -0.75, 46),
    (Icons.location_on_outlined, -0.25, -0.9, 30),
    (Icons.local_taxi_outlined, 0.35, -0.8, 44),
    (Icons.electric_rickshaw_outlined, 0.85, -0.55, 50),
    (Icons.inventory_2_outlined, 0.6, 0.1, 36),
    (Icons.temple_hindu_outlined, 0.95, 0.55, 40),
    (Icons.traffic_outlined, 0.1, -0.2, 30),
    (Icons.directions_bus_outlined, 0.45, 0.85, 40),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? Colors.white : const Color(0xFF0F172A);
    return Container(
      margin: const EdgeInsets.only(top: 28),
      height: 260,
      width: double.infinity,
      color: isDark ? const Color(0xFF101216) : const Color(0xFFF8F8F6),
      child: Stack(
        children: [
          for (final (icon, x, y, size) in _doodles)
            Align(
              alignment: Alignment(x, y),
              child: Icon(icon, size: size, color: ink.withValues(alpha: 0.07)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '#goJhatpat',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      letterSpacing: -1,
                      color: ink.withValues(alpha: 0.28),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _footerLine('🇮🇳', 'Made for India', ink),
                const SizedBox(height: 8),
                _footerLine('💛', 'Rides, parcels & food in minutes', ink),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerLine(String emoji, String text, Color ink) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: ink.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// A nearby landmark: photo when the source has one, otherwise an icon.
class _PopularPlaceTile extends StatelessWidget {
  const _PopularPlaceTile({
    required this.place,
    required this.isDark,
    required this.onTap,
  });

  final PopularPlace place;
  final bool isDark;
  final VoidCallback onTap;

  static IconData _iconFor(String kind) {
    final k = kind.toLowerCase();
    if (k.contains('railway') || k.contains('train')) return Icons.train_rounded;
    if (k.contains('bus')) return Icons.directions_bus_rounded;
    if (k.contains('airport')) return Icons.flight_rounded;
    if (k.contains('mall') || k.contains('shop') || k.contains('store')) {
      return Icons.local_mall_rounded;
    }
    if (k.contains('hospital') || k.contains('health') || k.contains('clinic')) {
      return Icons.local_hospital_rounded;
    }
    if (k.contains('worship') || k.contains('temple') || k.contains('church') ||
        k.contains('mosque') || k.contains('hindu')) {
      return Icons.temple_hindu_rounded;
    }
    if (k.contains('park') || k.contains('garden')) return Icons.park_rounded;
    if (k.contains('university') || k.contains('college') || k.contains('school')) {
      return Icons.school_rounded;
    }
    if (k.contains('restaurant') || k.contains('cafe') || k.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (k.contains('hotel') || k.contains('lodging')) return Icons.hotel_rounded;
    if (k.contains('tourism') || k.contains('attraction') || k.contains('museum')) {
      return Icons.photo_camera_rounded;
    }
    return Icons.place_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: isDark ? const Color(0xFF2A2D35) : const Color(0xFFFFF6D6),
      alignment: Alignment.center,
      child: Icon(_iconFor(place.kind), size: 34, color: const Color(0xFFE5A600)),
    );

    return Material(
      color: isDark ? const Color(0xFF1F2229) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE8EDF5),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: place.photoUrl.isEmpty
                        ? fallback
                        : CachedNetworkImage(
                            imageUrl: place.photoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => fallback,
                            errorWidget: (_, _, _) => fallback,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: Center(
                  child: Text(
                    place.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
