import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/realtime/sp_socket_service.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// Shown while the backend hunts for a professional.
///
/// How the search actually works, because the screen's behaviour follows from
/// it: `createBooking` responds immediately and then, in a `setImmediate`
/// block, sorts nearby partners by distance and alerts them in **waves**. The
/// wave scheduler (`services/bookingScheduler.js`) promotes to the next wave on
/// a timer until someone accepts or the list is exhausted, at which point the
/// booking goes to `no_vendors` and the customer gets `booking_search_failed`.
///
/// Two independent ways out, and both are needed:
///
///  * the socket (`booking_accepted` / `booking_search_failed`) — instant, but
///    a backgrounded socket is paused and misses events entirely;
///  * a poll every 5 seconds — slower, but it cannot miss anything.
///
/// Whichever fires first wins. This is the "sockets are an accelerator, REST is
/// the contract" rule; relying on the socket alone strands anyone who locked
/// their phone while waiting.
class BookingSearchingScreen extends ConsumerStatefulWidget {
  const BookingSearchingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingSearchingScreen> createState() =>
      _BookingSearchingScreenState();
}

class _BookingSearchingScreenState extends ConsumerState<BookingSearchingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _poll;
  Duration _elapsed = Duration.zero;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 5));
      ref.invalidate(spBookingProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Leaves for the tracking screen exactly once.
  ///
  /// The socket and the poll both detect acceptance, and without this guard the
  /// two race and push two copies of the tracking screen onto the stack.
  void _goToTracking() {
    if (_navigated || !mounted) return;
    _navigated = true;
    unawaited(ref.read(myBookingsProvider.notifier).refresh());
    context.pushReplacement(ServicesRoutePaths.bookingOf(widget.bookingId));
  }

  Future<void> _cancel() async {
    final reason = await askCancelReason(
      context,
      title: 'Cancel booking?',
      reasons: CancelReasons.service,
      confirmLabel: 'Cancel booking',
      keepLabel: 'Keep waiting',
    );
    if (reason == null || !mounted) return;

    final error = await ref
        .read(myBookingsProvider.notifier)
        .cancel(widget.bookingId, reason: reason);

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    context.go(ServicesRoutePaths.home);
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(spBookingProvider(widget.bookingId));

    // Socket path. Fires the instant a vendor accepts.
    ref.listen(spBookingEventsProvider(widget.bookingId), (_, next) {
      final event = next.value;
      if (event == null || !mounted) return;
      if (event.event == SpSocketEvents.bookingAccepted) {
        _goToTracking();
      } else if (event.event == SpSocketEvents.searchFailed) {
        ref.invalidate(spBookingProvider(widget.bookingId));
      }
    });

    // Poll path. Same conclusions, drawn from the document itself.
    final current = booking.value;
    if (current != null && !current.status.isSearching && !current.status.isDead) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToTracking());
    }

    final failed = current != null &&
        (current.status == SpBookingStatus.noVendors ||
            current.status == SpBookingStatus.cancelled);

    return PopScope(
      // Backing out of the search must not silently abandon a live booking —
      // it stays in `searching` server-side either way, so send the customer
      // somewhere that still shows it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) context.go(ServicesRoutePaths.bookings);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                if (failed)
                  _Failed(
                    reason: current.status == SpBookingStatus.cancelled
                        ? 'This booking was cancelled.'.tr
                        : 'No professionals were available for this slot.'.tr,
                  )
                else
                  _Searching(pulse: _pulse, elapsed: _elapsed),
                const Spacer(),
                if (failed)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => context.go(ServicesRoutePaths.home),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: spAccent,
                        foregroundColor: spOnAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text('Try another time'.tr,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  )
                else
                  TextButton(
                    onPressed: _cancel,
                    child: Text(
                      'Cancel booking'.tr,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.pulse, required this.elapsed});

  final AnimationController pulse;
  final Duration elapsed;

  /// Sets expectations as the wait grows, instead of showing one static line
  /// for what can legitimately be a couple of minutes across several waves.
  String get _reassurance {
    if (elapsed.inSeconds < 20) return 'Alerting professionals near you…'.tr;
    if (elapsed.inSeconds < 60) return 'Checking a wider area…'.tr;
    return 'Still looking. Some slots take a little longer.'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          width: 180,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (var ring = 0; ring < 3; ring++)
                    Builder(builder: (context) {
                      // Three rings, evenly offset in phase, each fading as it
                      // expands.
                      final t = (pulse.value + ring / 3) % 1.0;
                      return Container(
                        width: 70 + t * 110,
                        height: 70 + t * 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: spAccent.withValues(alpha: (1 - t) * 0.5),
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      color: spAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.handyman_rounded,
                        color: spOnAccent, size: 30),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Finding a professional'.tr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: spTextPrimary(context),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _reassurance,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: spTextSecondary(context)),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_search_rounded,
              color: AppColors.error, size: 34),
        ),
        const SizedBox(height: 22),
        Text(
          'No one available'.tr,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: spTextPrimary(context),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$reason\n${'You have not been charged.'.tr}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: spTextSecondary(context),
          ),
        ),
      ],
    );
  }
}
