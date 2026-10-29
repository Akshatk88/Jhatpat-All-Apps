import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_user_application/core/providers/core_providers.dart';
import 'package:food_user_application/features/auth/domain/seller_vertical.dart';

/// Holds which seller product the app is currently acting as.
///
/// Read by `dioProvider`, so changing it repoints **every** subsequent request
/// — host and module prefix — at the other backend. That is why it is set only
/// at login and cleared on logout: flipping it mid-session would leave screens
/// holding data from one backend while talking to the other.
///
/// Kept synchronous so `dioProvider` can read it without an async gap on the
/// very first request. The stored value is loaded once at startup by
/// [restore], which the splash screen awaits before any authenticated call.
class SellerVerticalController extends Notifier<SellerVertical> {
  @override
  SellerVertical build() => SellerVertical.food;

  /// Re-reads the persisted vertical. Called from the splash screen before the
  /// session check, so a restored session talks to the backend that issued it.
  Future<void> restore() async {
    final stored = await ref.read(tokenStorageProvider).sellerVertical;
    state = SellerVertical.parse(stored);
  }

  /// Chooses the vertical for the sign-in about to happen.
  ///
  /// Persisted immediately rather than on successful login, because the OTP
  /// request itself already has to go to the right backend.
  Future<void> select(SellerVertical next) async {
    if (state == next) return;
    await ref.read(tokenStorageProvider).saveSellerVertical(next.wire);
    // `dioProvider` watches this, so assigning here is what repoints the client
    // at the other host — no explicit invalidation, and no import of the
    // network layer from the domain layer.
    state = next;
  }

  /// Returns to the default after logout, so the picker opens unbiased.
  void reset() => state = SellerVertical.food;
}

final sellerVerticalControllerProvider =
    NotifierProvider<SellerVerticalController, SellerVertical>(
  SellerVerticalController.new,
);
