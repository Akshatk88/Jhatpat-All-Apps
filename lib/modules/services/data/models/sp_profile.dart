import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';

/// The customer's Service-Provider profile, from `GET /sp/users/profile`.
///
/// This is the **same human** as the super app's food/taxi profile — one login,
/// one phone number — but it is a different document, in `sp_users`. The
/// identity bridge in SP's `authMiddleware` links them by phone and provisions
/// this record the first time the customer opens the Services tab, so the app
/// never asks for a second registration.
///
/// Two things only this document knows, which is why the module fetches it at
/// all rather than reusing the shared profile:
///
///  * [id] — the `sp_users._id`. Every SP socket room the server emits to is
///    `user_<thisId>`, so the socket connection needs it.
///  * [addresses] — SP's address book, whose sub-schema differs from the shared
///    one (`addressLine1`/`pincode`/`landmark` vs `street`/`zipCode`). The
///    booking form reads these directly rather than translating.
class SpProfile {
  const SpProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.addresses,
    required this.walletBalancePaise,
    required this.walletPenaltyPaise,
    required this.planName,
    required this.planActive,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final List<SpBookingAddress> addresses;

  /// SP's own ledger. Deliberately **never** added to the food wallet balance:
  /// they are two ledgers on two collections, and a combined figure would show
  /// money that cannot be spent on the other side.
  final int walletBalancePaise;

  /// An unpaid cancellation penalty. The backend folds this into the next
  /// booking's total automatically, so the review screen surfaces it rather
  /// than letting the customer be surprised by a higher charge.
  final int walletPenaltyPaise;

  final String planName;
  final bool planActive;

  SpBookingAddress? get defaultAddress =>
      addresses.isEmpty ? null : addresses.first;

  factory SpProfile.fromJson(Map<String, dynamic> json) {
    final wallet = (json['wallet'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final plans = (json['plans'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    return SpProfile(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      addresses: [
        for (final a in (json['addresses'] as List? ?? const []))
          SpBookingAddress.fromJson((a as Map).cast<String, dynamic>()),
      ],
      walletBalancePaise: paiseOf(wallet['balance']),
      walletPenaltyPaise: paiseOf(wallet['penalty']),
      planName: (plans['name'] ?? '').toString(),
      planActive: plans['isActive'] == true,
    );
  }
}
