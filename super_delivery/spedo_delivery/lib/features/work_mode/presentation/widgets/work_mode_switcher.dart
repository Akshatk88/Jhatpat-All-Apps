import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Result's `when` is a freezed extension — it only resolves where the
// declaring library is imported, even though Result itself is never named here.
import 'package:food_user_application/core/error/result.dart';
import 'dart:async';

import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/features/orders/application/incoming_order_controller.dart';
import 'package:food_user_application/features/orders/application/orders_controller.dart';
import 'package:food_user_application/features/orders/application/orders_state.dart';
import 'package:food_user_application/features/profile/application/availability_controller.dart';
import 'package:food_user_application/features/rides/application/active_ride_controller.dart';
import 'package:food_user_application/features/rides/application/incoming_ride_controller.dart';
import 'package:food_user_application/features/work_mode/application/work_mode_controller.dart';
import 'package:food_user_application/features/work_mode/data/work_mode.dart';
import 'package:food_user_application/features/work_mode/data/work_mode_repository.dart';

const _foodOrange = Color(0xFFE85B17);
const _parcelGreen = Color(0xFF0E9F6E);
const _riderBlue = Color(0xFF1B6FF3);
const _errorRed = Color(0xFFF04438);
const _multiDark = Color(0xFF1E1E1E);

/// The Food delivery / Parcel delivery / Rider selector — the app's headline
/// control. Each module is its own on/off switch; any combination the driver
/// is approved for can be on (at least one), and only those requests arrive.
///
/// Three modules over two server modes (see [WorkModeSet]):
/// - **Food delivery** on → online for food.
/// - **Parcel delivery** / **Rider** on → online on the ride dispatcher. The
///   server cannot tell parcel from passenger, so the app (Flutter and the
///   native alert) filters offers by kind.
/// - Food plus either → `workMode = all`, online on both.
///
/// The dispatcher half is [AvailabilityController.syncDispatchers]; the filter
/// half is the set stored by [WorkModeController].
///
/// A module the driver is not approved for (not chosen at onboarding, or not
/// granted by the admin) is shown greyed with the reason rather than hidden.
class WorkModeSwitcher extends ConsumerStatefulWidget {
  const WorkModeSwitcher({super.key});

  static Color colorOf(WorkMode mode) {
    switch (mode) {
      case WorkMode.food:
        return _foodOrange;
      case WorkMode.parcel:
        return _parcelGreen;
      case WorkMode.rider:
        return _riderBlue;
    }
  }

  static IconData iconOf(WorkMode mode) {
    switch (mode) {
      case WorkMode.food:
        return Icons.delivery_dining_rounded;
      case WorkMode.parcel:
        return Icons.inventory_2_rounded;
      case WorkMode.rider:
        return Icons.local_taxi_rounded;
    }
  }

  /// Colour for a set: the module's own when only one is on, else neutral.
  static Color colorOfSet(WorkModeSet set) =>
      set.modules.length == 1 ? colorOf(set.ordered.first) : _multiDark;

  static IconData iconOfSet(WorkModeSet set) => set.modules.length == 1
      ? iconOf(set.ordered.first)
      : Icons.layers_rounded;

  static String _what(WorkMode mode) {
    switch (mode) {
      case WorkMode.food:
        return 'food orders';
      case WorkMode.parcel:
        return 'parcel requests';
      case WorkMode.rider:
        return 'passenger rides';
    }
  }

  /// What the rider will receive, for the line under the selector.
  static String onlyLine(WorkModeSet set) {
    final parts = set.ordered.map(_what).toList();
    if (parts.isEmpty) return 'Turn on at least one service';
    if (parts.length == 1) return 'Only ${parts.first} will come';
    if (parts.length == WorkMode.values.length) {
      return 'Food orders, parcel requests and passenger rides will come';
    }
    return '${parts.join(' + ')} will come';
  }

  @override
  ConsumerState<WorkModeSwitcher> createState() => _WorkModeSwitcherState();
}

class _WorkModeSwitcherState extends ConsumerState<WorkModeSwitcher> {
  /// The module being switched to, while the switch is in flight.
  WorkMode? _pending;

  /// Last failed switch, shown under the selector until the next attempt.
  String? _error;

  /// Re-reads permissions when the app comes back to the front, so a module
  /// the admin just enabled unlocks without restarting the app.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(workModeControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? _errorRed : null,
      ),
    );
  }

  /// True while the rider is in the middle of a food or ride/parcel job.
  /// Switching then would take them off the dispatcher the job runs on.
  bool _onJob() {
    final orders = ref.read(ordersControllerProvider);
    if (orders is OrdersLoaded && orders.hasActiveOrder) return true;
    return ref.read(activeRideControllerProvider).value != null;
  }

  Future<void> _toggle(WorkMode mode, WorkModeStatus status) async {
    if (_pending != null) return;
    try {
      await _toggleInner(mode, status);
    } catch (e) {
      if (mounted) _snack('Could not switch service. Try again.', error: true);
    } finally {
      // Whatever happened, never leave a tile spinning.
      if (mounted && _pending != null) setState(() => _pending = null);
    }
  }

  Future<void> _toggleInner(WorkMode mode, WorkModeStatus status) async {
    if (!mode.isAllowedFor(status.capabilities)) {
      // Ask the server again before saying no: the admin may have approved
      // this module after the app loaded its permissions.
      setState(() => _pending = mode);
      final fresh =
          await ref.read(workModeControllerProvider.notifier).refresh()
              .timeout(const Duration(seconds: 25), onTimeout: () => null);
      if (!mounted) return;
      setState(() => _pending = null);
      if (fresh == null) {
        _snack('Could not check your services. Check your internet and try again.');
        return;
      }
      if (!mode.isAllowedFor(fresh.capabilities)) {
        _snack('${mode.unavailableReason()}. Ask the admin to enable it for your account.');
        return;
      }
      status = fresh;
    }
    final next = status.mode.toggled(mode);
    if (next.isEmpty) {
      _snack('Keep at least one service on');
      return;
    }
    if (_onJob()) {
      _snack('Finish your current job before changing services');
      return;
    }
    HapticService.light();
    setState(() {
      _pending = mode;
      _error = null;
    });

    final result =
        await ref.read(workModeControllerProvider.notifier).select(next);
    if (!mounted) return;
    await result.when(
      success: (_) async {
        // Anything already on screen for a module just switched off is now
        // wrong. Drop it (never reject — the offer just expires server-side)
        // rather than leaving an alert ringing for the wrong module.
        if (!next.acceptsFood) {
          ref.read(incomingOrderControllerProvider.notifier).dismiss();
        }
        final offer = ref.read(incomingRideControllerProvider);
        if (offer != null && !next.acceptsOffer(isParcel: offer.isParcel)) {
          ref.read(incomingRideControllerProvider.notifier).dismiss();
        }

        // The list is polled every 15s; refresh now so the change is visible
        // immediately (it empties outside Food).
        unawaited(
          ref.read(ordersControllerProvider.notifier).refreshAvailable(),
        );

        // Online on the new module's dispatcher, offline on the other, with a
        // fresh location — so the first request arrives straight away and the
        // old module's requests stop at the source. Also run for parcel ↔
        // rider: re-going online makes the server replay jobs still searching.
        final dispatchError = await ref
            .read(availabilityControllerProvider.notifier)
            .syncDispatchers()
            .timeout(const Duration(seconds: 30), onTimeout: () => null);
        if (dispatchError != null && mounted) {
          _snack('Some requests can\'t start yet: $dispatchError', error: true);
        }
        if (mounted) setState(() => _pending = null);
      },
      failure: (error) async {
        setState(() {
          _pending = null;
          _error = error.message;
        });
        _snack(error.message, error: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workModeControllerProvider);
    // On an error, show the food-only fallback instead of spinning forever.
    final status = async.value ??
        (async.hasError ? WorkModeStatus.fallback : null);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor =
        isDark ? const Color(0xFF20242E) : const Color(0xFFF2F4F7);
    final hintColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    // Still loading the driver's modules: hold the space so the header does
    // not jump when the selector appears.
    if (status == null) {
      return Container(
        height: 92.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(18.r),
        ),
        child: SizedBox(
          width: 18.r,
          height: 18.r,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // A module switch is in flight; every tile holds
    // still so a double tap cannot queue two opposite changes.
    final busy = _pending != null;
    // While a toggle is in flight, preview the set it will produce.
    final shown =
        _pending == null ? status.mode : status.mode.toggled(_pending!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(4.r),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(18.r),
          ),
          // Equal-height tiles even when one subtitle wraps differently under
          // a large system font; the parent scrolls, so the height is
          // intrinsic rather than fixed and can never overflow.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final mode in WorkMode.values) ...[
                  if (mode != WorkMode.values.first) SizedBox(width: 4.w),
                  Expanded(
                    child: _ModuleTile(
                      mode: mode,
                      selected: status.mode.contains(mode),
                      allowed: mode.isAllowedFor(status.capabilities),
                      loading: _pending == mode,
                      busy: busy,
                      onTap: () => _toggle(mode, status),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 6.h, left: 4.w, right: 4.w),
          child: Row(
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 12.sp,
                color: WorkModeSwitcher.colorOfSet(shown),
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  WorkModeSwitcher.onlyLine(shown),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hintColor,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(top: 4.h, left: 4.w),
            child: Text(
              "Couldn't change services: $_error",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _errorRed, fontSize: 11.sp),
            ),
          ),
      ],
    );
  }
}

/// One module in the selector: icon, title and a one-line description.
class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.mode,
    required this.selected,
    required this.allowed,
    required this.loading,
    required this.busy,
    required this.onTap,
  });

  final WorkMode mode;
  final bool selected;
  final bool allowed;
  final bool loading;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = WorkModeSwitcher.colorOf(mode);
    final highlighted = selected || loading;

    final Color titleColor;
    final Color subColor;
    if (highlighted) {
      titleColor = Colors.white;
      subColor = Colors.white.withValues(alpha: 0.85);
    } else if (!allowed) {
      titleColor = isDark ? Colors.white24 : Colors.grey.shade400;
      subColor = titleColor;
    } else {
      titleColor = isDark ? Colors.grey.shade200 : const Color(0xFF1E1E1E);
      subColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }
    final iconBg = highlighted
        ? Colors.white.withValues(alpha: 0.2)
        : allowed
            ? accent.withValues(alpha: 0.12)
            : (isDark ? Colors.white10 : Colors.grey.shade200);
    final iconColor = highlighted
        ? Colors.white
        : allowed
            ? accent
            : titleColor;

    final String subtitle;
    if (!allowed) {
      subtitle = 'Not registered';
    } else if (selected) {
      subtitle = 'ON';
    } else {
      subtitle = 'OFF';
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: allowed,
      label: '${mode.label}. '
          '${allowed ? (selected ? 'On. ${mode.description}' : mode.description) : mode.unavailableReason()}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Tapping an unavailable tile still explains why, unless busy.
        onTap: busy ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: busy && !loading ? 0.6 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(8.w, 10.h, 8.w, 10.h),
            decoration: BoxDecoration(
              color: highlighted
                  ? accent
                  : (allowed
                      ? (isDark ? const Color(0xFF2A2F3A) : Colors.white)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(14.r),
              border: !highlighted && !allowed
                  ? Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade300,
                    )
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28.r,
                      height: 28.r,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: loading
                          ? SizedBox(
                              width: 14.r,
                              height: 14.r,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              WorkModeSwitcher.iconOf(mode),
                              size: 16.sp,
                              color: iconColor,
                            ),
                    ),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle_rounded,
                          size: 14.sp, color: Colors.white)
                    else if (!allowed)
                      Icon(Icons.lock_outline_rounded,
                          size: 13.sp, color: titleColor),
                  ],
                ),
                SizedBox(height: 8.h),
                // Scaled down rather than cut off: "Parcel delivery" has to
                // stay readable on a 320dp phone with three tiles in a row.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mode.label,
                    maxLines: 1,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: subColor,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 10.sp,
                    letterSpacing: selected ? 0.6 : null,
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
