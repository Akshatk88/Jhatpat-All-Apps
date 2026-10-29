import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/realtime/sp_socket_service.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';

/// Which bookings the list is showing.
enum BookingsFilter {
  active('Active'),
  completed('Completed'),
  cancelled('Cancelled');

  const BookingsFilter(this.label);

  final String label;

  bool matches(SpBooking booking) => switch (this) {
        active => !booking.status.isFinished,
        completed =>
          booking.status == SpBookingStatus.completed || booking.status == SpBookingStatus.workDone,
        cancelled => booking.status.isDead,
      };
}

class MyBookingsState {
  const MyBookingsState({
    this.bookings = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  final List<SpBooking> bookings;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;

  List<SpBooking> forFilter(BookingsFilter filter) =>
      bookings.where(filter.matches).toList();

  MyBookingsState copyWith({
    List<SpBooking>? bookings,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) =>
      MyBookingsState(
        bookings: bookings ?? this.bookings,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// The customer's booking history, paginated.
///
/// Filtering is done client-side across the loaded pages rather than by
/// refetching per tab. The endpoint's `status` parameter takes one exact status
/// string, but "Active" spans nine of them — one request per tab would mean
/// nine requests, or a filter that quietly misses statuses added later.
class MyBookingsController extends Notifier<MyBookingsState> {
  static const _pageSize = 20;

  int _page = 1;

  @override
  MyBookingsState build() {
    // A booking that changes underneath us — accepted, completed, cancelled by
    // the vendor — must move between tabs without the customer pulling to
    // refresh. The socket is the trigger; the refetch is the source of truth.
    final socket = ref.watch(spRealtimeProvider);
    final subscription = socket?.bookingEvents.listen((_) => refresh());
    ref.onDispose(() => subscription?.cancel());

    Future.microtask(refresh);
    return const MyBookingsState();
  }

  Future<void> refresh() async {
    _page = 1;
    state = state.copyWith(loading: state.bookings.isEmpty, clearError: true);
    try {
      final page = await ref
          .read(servicesDataSourceProvider)
          .bookings(page: 1, limit: _pageSize);
      state = state.copyWith(
        bookings: page,
        loading: false,
        // A short page means there is nothing after it. Safe because the sort
        // is a stable `createdAt: -1`.
        hasMore: page.length >= _pageSize,
        clearError: true,
      );
    } on Failure catch (failure) {
      state = state.copyWith(loading: false, error: failure.message);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    try {
      final next = await ref
          .read(servicesDataSourceProvider)
          .bookings(page: _page + 1, limit: _pageSize);
      _page += 1;
      state = state.copyWith(
        bookings: [...state.bookings, ...next],
        loadingMore: false,
        hasMore: next.length >= _pageSize,
      );
    } on Failure catch (failure) {
      state = state.copyWith(loadingMore: false, error: failure.message);
    }
  }

  /// Cancels [bookingId] and refreshes.
  ///
  /// Returns an error message on failure, null on success. The backend applies
  /// its own cancellation-penalty rules and may refuse outright (a completed
  /// booking, one already cancelled), so its message is worth surfacing rather
  /// than replacing with a generic one.
  Future<String?> cancel(String bookingId, {String? reason}) async {
    try {
      await ref
          .read(servicesDataSourceProvider)
          .cancelBooking(bookingId, reason: reason);
      await refresh();
      // The detail screen may be showing this booking; make it re-read.
      ref.invalidate(spBookingProvider(bookingId));
      return null;
    } on Failure catch (failure) {
      return failure.message;
    }
  }
}

final myBookingsProvider =
    NotifierProvider<MyBookingsController, MyBookingsState>(
  MyBookingsController.new,
);

/// The booking the customer should be nudged about on the module home screen.
///
/// Picks the most recent one that is still going, so the home screen can float
/// a "professional on the way" card without every screen re-deriving it.
final spActiveBookingProvider = Provider<SpBooking?>((ref) {
  final bookings = ref.watch(myBookingsProvider).bookings;
  for (final booking in bookings) {
    if (!booking.status.isFinished) return booking;
  }
  return null;
});

/// Booking-scoped realtime, for the searching and tracking screens.
///
/// Emits only events belonging to [bookingId], so a screen does not have to
/// filter the firehose itself.
final spBookingEventsProvider =
    StreamProvider.autoDispose.family<SpBookingEvent, String>((ref, bookingId) {
  final socket = ref.watch(spRealtimeProvider);
  if (socket == null) return const Stream.empty();
  return socket.bookingEvents.where((event) => event.bookingId == bookingId);
});

/// Live position of whoever is travelling to this booking.
///
/// Frames only arrive while the professional's app is emitting `update_location`
/// and this client has joined `booking_<id>` (the tracking screen does that on
/// entry). A booking nobody is currently travelling to simply never emits,
/// which is why the UI treats "no value" as "not moving" rather than as an
/// error.
final spLiveLocationProvider =
    StreamProvider.autoDispose.family<SpLiveLocation, String>((ref, bookingId) {
  final socket = ref.watch(spRealtimeProvider);
  if (socket == null) return const Stream.empty();
  return socket.locationFor(bookingId);
});
