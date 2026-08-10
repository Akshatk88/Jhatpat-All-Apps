import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/modules/taxi/home/presentation/all_services_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/confirm_booking_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/finding_driver_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/home_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/map_picker_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/no_driver_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/promo_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/ride_type_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/saved_places_screen.dart';
import 'package:superapp_user/modules/taxi/home/presentation/search_destination_screen.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/rating_review_screen.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/ride_chat_screen.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/ride_detail_screen.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/ride_history_screen.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/ride_tracking_screen.dart';
import 'package:superapp_user/modules/taxi/taxi_route_names.dart';

/// The taxi module's route subtree.
///
/// No bottom-nav shell, deliberately. Booking is a linear funnel over a map
/// (home → destination → vehicle → confirm → searching → tracking); a tab bar
/// mid-funnel is how a half-built booking gets lost. The stock taxi app put
/// `AppBottomNavigationBar` on these screens — that is not carried over.
List<RouteBase> taxiRoutes(GlobalKey<NavigatorState> rootNavigatorKey) => [
      GoRoute(
        name: TaxiRouteNames.home,
        path: TaxiRoutePaths.home,
        builder: (context, state) => const TaxiHomeScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.destination,
        path: TaxiRoutePaths.destination,
        builder: (context, state) => const SearchDestinationScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.pickOnMap,
        path: TaxiRoutePaths.pickOnMap,
        builder: (context, state) => MapPickerScreen(
          type: state.uri.queryParameters['type'] ?? 'pickup',
        ),
      ),
      GoRoute(
        name: TaxiRouteNames.savedPlaces,
        path: TaxiRoutePaths.savedPlaces,
        builder: (context, state) => const SavedPlacesScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.vehicles,
        path: TaxiRoutePaths.vehicles,
        builder: (context, state) => const RideTypeScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.confirm,
        path: TaxiRoutePaths.confirm,
        builder: (context, state) => const ConfirmBookingScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.searching,
        path: TaxiRoutePaths.searching,
        builder: (context, state) => const FindingDriverScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.noDriver,
        path: TaxiRoutePaths.noDriver,
        builder: (context, state) => const NoDriverScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.promo,
        path: TaxiRoutePaths.promo,
        builder: (context, state) => const PromoScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.allServices,
        path: TaxiRoutePaths.allServices,
        builder: (context, state) => const AllServicesScreen(),
      ),
      GoRoute(
        name: TaxiRouteNames.rides,
        path: TaxiRoutePaths.rides,
        builder: (context, state) => const RideHistoryScreen(),
        routes: [
          // More specific children first so ':rideId' does not swallow them.
          GoRoute(
            name: TaxiRouteNames.rideTracking,
            path: ':rideId/track',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) =>
                RideTrackingScreen(rideId: state.pathParameters['rideId']!),
          ),
          GoRoute(
            name: TaxiRouteNames.rideRating,
            path: ':rideId/rate',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) =>
                RatingReviewScreen(rideId: state.pathParameters['rideId']!),
          ),
          GoRoute(
            name: TaxiRouteNames.rideChat,
            path: ':rideId/chat',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) =>
                RideChatScreen(rideId: state.pathParameters['rideId']!),
          ),
          GoRoute(
            name: TaxiRouteNames.rideDetail,
            path: ':rideId',
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) =>
                RideDetailScreen(rideId: state.pathParameters['rideId']!),
          ),
        ],
      ),
    ];
