/// Route names and paths for the taxi module.
///
/// Every path starts with `/taxi`. Before namespacing, taxi and food collided
/// on `/home`, `/search`, `/profile`, `/wallet`, `/notifications` and `/` —
/// whichever registered first would silently win.
class TaxiRoutePaths {
  const TaxiRoutePaths._();

  static const String home = '/taxi';
  static const String destination = '/taxi/destination';
  static const String pickOnMap = '/taxi/pick-on-map';
  static const String savedPlaces = '/taxi/saved-places';
  static const String vehicles = '/taxi/vehicles';
  static const String confirm = '/taxi/confirm';
  static const String searching = '/taxi/searching';
  static const String noDriver = '/taxi/no-driver';
  static const String promo = '/taxi/promo';
  static const String allServices = '/taxi/services';

  static const String rides = '/taxi/rides';
  static const String rideDetail = '/taxi/rides/:rideId';
  static const String rideTracking = '/taxi/rides/:rideId/track';
  static const String rideRating = '/taxi/rides/:rideId/rate';
  static const String rideChat = '/taxi/rides/:rideId/chat';

  static String rideOf(String id) => '/taxi/rides/$id';
  static String trackRide(String id) => '/taxi/rides/$id/track';
  static String rateRide(String id) => '/taxi/rides/$id/rate';
  static String chatForRide(String id) => '/taxi/rides/$id/chat';
}

class TaxiRouteNames {
  const TaxiRouteNames._();

  static const String home = 'taxi.home';
  static const String destination = 'taxi.destination';
  static const String pickOnMap = 'taxi.pickOnMap';
  static const String savedPlaces = 'taxi.savedPlaces';
  static const String vehicles = 'taxi.vehicles';
  static const String confirm = 'taxi.confirm';
  static const String searching = 'taxi.searching';
  static const String noDriver = 'taxi.noDriver';
  static const String promo = 'taxi.promo';
  static const String allServices = 'taxi.services';

  static const String rides = 'taxi.rides';
  static const String rideDetail = 'taxi.ride.detail';
  static const String rideTracking = 'taxi.ride.track';
  static const String rideRating = 'taxi.ride.rate';
  static const String rideChat = 'taxi.ride.chat';
}
