import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/app/shell/module_home_shell.dart';
import 'package:superapp_user/core/config/backend_ids.dart';
import 'package:superapp_user/design_system/tokens/module_accent.dart';
import 'package:superapp_user/modules/app_module.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/services/presentation/booking_detail_screen.dart';
import 'package:superapp_user/modules/services/presentation/booking_review_screen.dart';
import 'package:superapp_user/modules/services/presentation/booking_schedule_screen.dart';
import 'package:superapp_user/modules/services/presentation/booking_searching_screen.dart';
import 'package:superapp_user/modules/services/presentation/category_screen.dart';
import 'package:superapp_user/modules/services/presentation/my_bookings_screen.dart';
import 'package:superapp_user/modules/services/presentation/service_detail_screen.dart';
import 'package:superapp_user/modules/services/presentation/services_home_screen.dart';
import 'package:superapp_user/modules/services/presentation/widgets/services_bottom_nav.dart';

/// Every path this module owns. All of them start with `/services` — that is
/// what makes ownership readable from any URL and guarantees no collision with
/// the other four modules (nine paths already collided before namespacing).
class ServicesRoutePaths {
  const ServicesRoutePaths._();

  static const String home = '/services';
  static const String category = '/services/categories/:categoryId';
  static const String service = '/services/items/:serviceId';
  static const String schedule = '/services/book/schedule';
  static const String review = '/services/book/review';
  static const String bookings = '/services/bookings';
  static const String searching = '/services/bookings/:bookingId/searching';
  static const String booking = '/services/bookings/:bookingId';

  static String categoryOf(String id) => '/services/categories/$id';
  static String serviceOf(String id) => '/services/items/$id';
  static String bookingOf(String id) => '/services/bookings/$id';
  static String searchingFor(String id) => '/services/bookings/$id/searching';
}

class ServicesRouteNames {
  const ServicesRouteNames._();

  static const String home = 'services.home';
  static const String category = 'services.category';
  static const String service = 'services.service';
  static const String schedule = 'services.book.schedule';
  static const String review = 'services.book.review';
  static const String bookings = 'services.bookings';
  static const String searching = 'services.searching';
  static const String booking = 'services.booking';
}

/// Home services — plumbing, appliance repair, cleaning, electrical.
///
/// Talks to the Service-Provider module of the k9 backend (`/api/v1/sp/*`),
/// which was ported in whole from the standalone Homster app. Two consequences
/// worth knowing about, both handled rather than worked around:
///
///  * **Its customers live in `sp_users`, not the shared `users` collection.**
///    The Phase-2 identity merge in `SERVICE_PROVIDER_INTEGRATION_PLAN.md §4.2`
///    has not run. SP's `authMiddleware` therefore carries an identity bridge
///    that resolves this app's one master-issued token to the matching SP user
///    (creating it on first use), so the customer still has one login and one
///    profile. Nothing in this module ever asks for a second sign-in.
///
///  * **Its realtime lives on the `/sp` Socket.IO namespace**, with its own
///    event vocabulary. `SpSocketService` owns that connection; it is opened on
///    entry into this module, never at app boot.
class ServicesModule extends AppModule {
  const ServicesModule();

  @override
  ModuleId get id => ModuleId.services;

  @override
  String get label => 'Services';

  /// Kept short: the tagline renders under the label in the service switcher,
  /// which is four tabs wide now. Anything longer ellipsises to nothing.
  @override
  String get tagline => 'Home repairs';

  @override
  IconData get icon => Icons.handyman_rounded;

  @override
  ModuleAccent get accent => ModuleAccent.services;

  @override
  String get endpointId => BackendIds.k9;

  @override
  String get entryRoute => ServicesRoutePaths.home;

  @override
  int get order => 4;

  @override
  List<RouteBase> routes(GlobalKey<NavigatorState> rootNavigatorKey) => [
        GoRoute(
          name: ServicesRouteNames.home,
          path: ServicesRoutePaths.home,
          builder: (context, state) => const ModuleHomeShell(
            moduleId: ModuleId.services,
            bottomNavigationBar: ServicesBottomNav(current: ServicesTab.home),
            child: ServicesHomeScreen(),
          ),
        ),
        GoRoute(
          name: ServicesRouteNames.category,
          path: ServicesRoutePaths.category,
          builder: (context, state) => CategoryScreen(
            categoryId: state.pathParameters['categoryId']!,
            // Only a nicety for the app bar while the list loads — a cold deep
            // link simply shows "Services" until the data lands.
            categoryTitle: state.uri.queryParameters['title'],
          ),
        ),
        GoRoute(
          name: ServicesRouteNames.service,
          path: ServicesRoutePaths.service,
          builder: (context, state) => ServiceDetailScreen(
            serviceId: state.pathParameters['serviceId']!,
            // Warm push carries the model and skips a refetch; a cold entry
            // (push notification, shared link, process restart) carries only
            // the id, and the screen loads from that. Never cast `extra`
            // unconditionally — that is a guaranteed crash on cold start.
            preloaded: state.extra,
          ),
        ),
        GoRoute(
          name: ServicesRouteNames.schedule,
          path: ServicesRoutePaths.schedule,
          builder: (context, state) => const BookingScheduleScreen(),
        ),
        GoRoute(
          name: ServicesRouteNames.review,
          path: ServicesRoutePaths.review,
          builder: (context, state) => const BookingReviewScreen(),
        ),
        GoRoute(
          name: ServicesRouteNames.bookings,
          path: ServicesRoutePaths.bookings,
          builder: (context, state) => const MyBookingsScreen(),
        ),
        // Declared before the `:bookingId` route it would otherwise be
        // swallowed by — go_router matches in registration order and gives no
        // warning when a broader pattern shadows a narrower one.
        GoRoute(
          name: ServicesRouteNames.searching,
          path: ServicesRoutePaths.searching,
          builder: (context, state) => BookingSearchingScreen(
            bookingId: state.pathParameters['bookingId']!,
          ),
        ),
        GoRoute(
          name: ServicesRouteNames.booking,
          path: ServicesRoutePaths.booking,
          builder: (context, state) => BookingDetailScreen(
            bookingId: state.pathParameters['bookingId']!,
          ),
        ),
      ];

  @override
  PushRoute? resolvePush(PushMessage message) {
    // Decline anything explicitly addressed elsewhere.
    if (message.module != null && message.module != ModuleId.services) {
      return null;
    }

    final bookingId = message.string('bookingId') ??
        message.string('relatedId') ??
        message.string('jobId');

    // The k9 push payload has no `module` field yet, so without an explicit
    // address this has to match on type. SP's notification types are listed in
    // `createNotification` call sites across its controllers. Matching loosely
    // here would steal food's `order_*` notifications, so the list is exact and
    // anything unrecognised is declined.
    const ownTypes = {
      'booking_accepted',
      'booking_assigned',
      'booking_started',
      'booking_reached',
      'booking_completed',
      'booking_cancelled',
      'booking_rejected',
      'worker_assigned',
      'payment_collected',
      'service_reminder',
    };

    if (message.module != ModuleId.services && !ownTypes.contains(message.type)) {
      return null;
    }

    if (bookingId == null || bookingId.isEmpty) {
      return const PushRoute(ServicesRoutePaths.bookings);
    }
    return PushRoute(ServicesRoutePaths.bookingOf(bookingId));
  }
}
