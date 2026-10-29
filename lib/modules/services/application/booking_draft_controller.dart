import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/storage/storage_providers.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';

/// How the customer intends to settle the bill.
///
/// These strings go to the backend verbatim as `paymentMethod` — see the
/// branches in `userBookingController.createBooking` and the `PAYMENT_STATUS`
/// transitions each one drives.
enum SpPaymentMethod {
  /// Settle at the door, cash or online, once the work is billed. This is the
  /// default: for home services the final amount usually isn't known until the
  /// professional has seen the job.
  payAtHome('pay_at_home', 'Pay after service'),

  /// Debit SP's wallet now.
  wallet('wallet', 'Services wallet'),

  /// Razorpay now.
  online('razorpay', 'Pay online now'),

  /// Covered by an active subscription. Falls back to [payAtHome] server-side
  /// if the plan is expired or doesn't cover this category.
  plan('plan_benefit', 'Use my plan');

  const SpPaymentMethod(this.wire, this.label);

  final String wire;
  final String label;
}

/// A two-hour arrival window.
@immutable
class SpTimeSlot {
  const SpTimeSlot(this.start, this.end);

  final String start;
  final String end;

  String get label => '$start - $end';

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  static SpTimeSlot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final start = json['start']?.toString() ?? '';
    final end = json['end']?.toString() ?? '';
    return start.isEmpty || end.isEmpty ? null : SpTimeSlot(start, end);
  }

  /// The windows offered on the schedule screen.
  ///
  /// Hardcoded because the backend exposes no slot-availability endpoint — it
  /// accepts whatever `timeSlot.start`/`.end` strings it is given and does the
  /// real matching by dispatching to whoever is online. If slot capacity ever
  /// becomes a server concern, this list is the one thing to replace.
  static const options = [
    SpTimeSlot('08:00 AM', '10:00 AM'),
    SpTimeSlot('10:00 AM', '12:00 PM'),
    SpTimeSlot('12:00 PM', '02:00 PM'),
    SpTimeSlot('02:00 PM', '04:00 PM'),
    SpTimeSlot('04:00 PM', '06:00 PM'),
    SpTimeSlot('06:00 PM', '08:00 PM'),
  ];

  @override
  bool operator ==(Object other) =>
      other is SpTimeSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The in-progress booking.
@immutable
class BookingDraft {
  const BookingDraft({
    this.service,
    this.quantity = 1,
    this.address,
    this.date,
    this.slot,
    this.paymentMethod = SpPaymentMethod.payAtHome,
    this.notes = '',
    this.submitting = false,
    this.error,
    this.createdBookingId,
  });

  final SpService? service;
  final int quantity;
  final SpBookingAddress? address;
  final DateTime? date;
  final SpTimeSlot? slot;
  final SpPaymentMethod paymentMethod;
  final String notes;
  final bool submitting;
  final String? error;

  /// Set once the booking exists server-side. Its presence is what stops a
  /// double submit from creating two bookings.
  final String? createdBookingId;

  /// Standard visiting charge, in paise.
  ///
  /// The backend defaults to ₹49 when the client sends no `visitingCharges`
  /// (`visitingCharges ?? 49`), so sending it explicitly is the only way the
  /// figure on the review screen is guaranteed to match what is charged.
  static const int visitingChargesPaise = 4900;

  int get itemsPaise => (service?.effectivePricePaise ?? 0) * quantity;

  int get savingsPaise => service == null || !service!.hasDiscount
      ? 0
      : (service!.basePricePaise - service!.discountPricePaise) * quantity;

  int get taxPaise {
    final gst = service?.gstPercentage ?? 0;
    if (gst <= 0) return 0;
    return (itemsPaise * gst / 100).round();
  }

  int get totalPaise => itemsPaise + taxPaise + visitingChargesPaise;

  bool get canSchedule => service != null;

  bool get canReview =>
      service != null &&
      (address?.isComplete ?? false) &&
      date != null &&
      slot != null;

  BookingDraft copyWith({
    SpService? service,
    int? quantity,
    SpBookingAddress? address,
    DateTime? date,
    SpTimeSlot? slot,
    SpPaymentMethod? paymentMethod,
    String? notes,
    bool? submitting,
    String? error,
    String? createdBookingId,
    bool clearError = false,
  }) =>
      BookingDraft(
        service: service ?? this.service,
        quantity: quantity ?? this.quantity,
        address: address ?? this.address,
        date: date ?? this.date,
        slot: slot ?? this.slot,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        notes: notes ?? this.notes,
        submitting: submitting ?? this.submitting,
        error: clearError ? null : (error ?? this.error),
        createdBookingId: createdBookingId ?? this.createdBookingId,
      );

  /// Persisted so leaving the module mid-funnel — or the OS killing the app —
  /// doesn't lose what the customer already entered.
  ///
  /// Only the answers are stored, never [submitting]/[error]/[createdBookingId]:
  /// restoring a stale "submitting" would deadlock the button, and restoring a
  /// booking id would make the next Confirm silently do nothing.
  Map<String, dynamic> toJson() => {
        'serviceId': service?.id,
        'serviceTitle': service?.title,
        'serviceIcon': service?.iconUrl,
        'serviceBase': service?.basePricePaise,
        'serviceDiscount': service?.discountPricePaise,
        'serviceGst': service?.gstPercentage,
        'serviceBrandId': service?.brandId,
        'serviceBrandName': service?.brandName,
        'serviceCategoryId': service?.categoryId,
        'quantity': quantity,
        'address': address?.toJson(),
        'date': date?.toIso8601String(),
        'slot': slot?.toJson(),
        'paymentMethod': paymentMethod.wire,
        'notes': notes,
      };

  static BookingDraft fromJson(Map<String, dynamic> json) {
    final serviceId = json['serviceId']?.toString() ?? '';
    final address = (json['address'] as Map?)?.cast<String, dynamic>();
    return BookingDraft(
      service: serviceId.isEmpty
          ? null
          : SpService(
              id: serviceId,
              title: json['serviceTitle']?.toString() ?? '',
              iconUrl: json['serviceIcon']?.toString() ?? '',
              description: '',
              basePricePaise: (json['serviceBase'] as num?)?.toInt() ?? 0,
              discountPricePaise: (json['serviceDiscount'] as num?)?.toInt() ?? 0,
              gstPercentage: (json['serviceGst'] as num?)?.toDouble() ?? 0,
              pricingUnit: '',
              categoryId: json['serviceCategoryId']?.toString() ?? '',
              brandId: json['serviceBrandId']?.toString() ?? '',
              brandName: json['serviceBrandName']?.toString() ?? '',
              brandIconUrl: '',
            ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      address: address == null ? null : SpBookingAddress.fromJson(address),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      slot: SpTimeSlot.fromJson((json['slot'] as Map?)?.cast<String, dynamic>()),
      paymentMethod: SpPaymentMethod.values.firstWhere(
        (m) => m.wire == json['paymentMethod'],
        orElse: () => SpPaymentMethod.payAtHome,
      ),
      notes: json['notes']?.toString() ?? '',
    );
  }
}

/// Drives the booking funnel: service -> address & slot -> review -> create.
///
/// The draft is persisted to Hive on every change rather than held only in
/// memory, because this provider lives in the module's scope and is disposed
/// the moment the customer leaves `/services/*`.
class BookingDraftController extends Notifier<BookingDraft> {
  static const _storageKey = 'sp_booking_draft_v1';

  @override
  BookingDraft build() {
    // build() re-runs on every dependency invalidation — it is not a
    // constructor. Restoring from storage is idempotent, so it is safe here.
    final box = ref.read(localStorageServiceProvider).settings;
    final raw = box.get(_storageKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        return BookingDraft.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      } catch (_) {
        // Draft written by an older build — discard rather than crash on entry.
      }
    }
    return const BookingDraft();
  }

  void _set(BookingDraft next, {bool persist = true}) {
    state = next;
    if (persist) _persist(next);
  }

  void _persist(BookingDraft draft) {
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(_storageKey, jsonEncode(draft.toJson()));
  }

  /// Starts a fresh funnel for [service], discarding anything half-entered for
  /// a different one. Address, date and slot are deliberately carried over —
  /// they are almost always the same and re-entering them is pure friction.
  void startWith(SpService service) {
    final previous = state;
    _set(BookingDraft(
      service: service,
      quantity: previous.service?.id == service.id ? previous.quantity : 1,
      address: previous.address,
      date: previous.date,
      slot: previous.slot,
      paymentMethod: previous.paymentMethod,
    ));
  }

  void setQuantity(int quantity) =>
      _set(state.copyWith(quantity: quantity.clamp(1, 10)));

  void setAddress(SpBookingAddress address) =>
      _set(state.copyWith(address: address, clearError: true));

  void setSchedule({required DateTime date, required SpTimeSlot slot}) =>
      _set(state.copyWith(date: date, slot: slot, clearError: true));

  void setPaymentMethod(SpPaymentMethod method) =>
      _set(state.copyWith(paymentMethod: method, clearError: true));

  void setNotes(String notes) => _set(state.copyWith(notes: notes));

  /// Clears the funnel. Called once the booking is safely created.
  void clear() {
    ref.read(localStorageServiceProvider).settings.delete(_storageKey);
    state = const BookingDraft();
  }

  /// Creates the booking.
  ///
  /// Returns the new booking id, or null if it failed — in which case
  /// `state.error` carries a message worth showing.
  ///
  /// The server responds as soon as the row is written and then searches for
  /// partners in the background, so the booking comes back in `searching` with
  /// no vendor attached. The caller's job is to route to the searching screen,
  /// not to wait for a partner here.
  Future<String?> submit() async {
    final draft = state;
    if (!draft.canReview || draft.submitting) return null;

    // Guard against a double-tap creating two bookings.
    if (draft.createdBookingId != null) return draft.createdBookingId;

    _set(draft.copyWith(submitting: true, clearError: true), persist: false);

    try {
      final service = draft.service!;
      final date = draft.date!;
      final slot = draft.slot!;

      final booking = await ref.read(servicesDataSourceProvider).createBooking({
        'serviceId': service.id,
        if (service.categoryId.isNotEmpty) 'categoryId': service.categoryId,

        // Send the breakdown, not just a total. The controller takes this
        // branch only when `basePrice` AND `tax` are both present, and that is
        // the branch where the figures the customer just approved are the ones
        // actually stored. Send a bare `amount` and it silently reverse-derives
        // a different breakdown.
        'amount': rupeesOf(draft.totalPaise),
        'basePrice': rupeesOf(draft.itemsPaise),
        'discount': 0,
        'tax': rupeesOf(draft.taxPaise),
        'visitingCharges': rupeesOf(BookingDraft.visitingChargesPaise),

        'address': draft.address!.toJson(),

        // Dates go up in UTC; the backend stores a Date and every consumer
        // formats it locally.
        'scheduledDate': date.toUtc().toIso8601String(),
        'scheduledTime': slot.start,
        'timeSlot': slot.toJson(),

        'paymentMethod': draft.paymentMethod.wire,
        'bookingType': 'scheduled',

        // Denormalised display fields. The backend falls back to looking these
        // up, but sending them keeps the vendor's alert card and the customer's
        // booking card showing the same brand and icon.
        if (service.brandName.isNotEmpty) 'brandName': service.brandName,
        if (service.brandIconUrl.isNotEmpty) 'brandIcon': service.brandIconUrl,

        if (draft.notes.isNotEmpty) 'requirementText': draft.notes,
      });

      _set(state.copyWith(submitting: false, createdBookingId: booking.id),
          persist: false);

      // The funnel is done — drop the draft so the next visit starts clean.
      clear();
      return booking.id;
    } on Failure catch (failure) {
      _set(state.copyWith(submitting: false, error: failure.message),
          persist: false);
      return null;
    } catch (error) {
      _set(
        state.copyWith(
          submitting: false,
          error: 'Could not create the booking. Please try again.'.tr,
        ),
        persist: false,
      );
      if (kDebugMode) debugPrint('[services] booking submit failed: $error');
      return null;
    }
  }
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftController, BookingDraft>(
  BookingDraftController.new,
);
