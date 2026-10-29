import '../data/models/delivery_partner.dart';

sealed class AuthState {
  const AuthState();
}

/// Initial state before the startup `/auth/me` check has run.
class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthNeedsRegistration extends AuthState {
  const AuthNeedsRegistration(this.phone, {this.previousApplication});
  final String phone;

  /// Set when a rejected partner chose to fix and re-apply: their last
  /// application, used to prefill the wizard. `/register` replaces a rejected
  /// record for the same phone, so re-applying is a fresh registration.
  final DeliveryPartner? previousApplication;

  bool get isReapplication => previousApplication != null;
}

/// Partner exists but `status` isn't `approved` yet.
///
/// The backend issues no token until approval, so everything known about the
/// application arrives here: from the verify-otp reply (which carries the
/// partner record only when rejected) or from the `/register` reply.
class AuthPendingApproval extends AuthState {
  const AuthPendingApproval({
    required this.isRejected,
    this.rejectionReason,
    this.phone,
    this.partner,
  });
  final bool isRejected;
  final String? rejectionReason;
  final String? phone;
  final DeliveryPartner? partner;
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final DeliveryPartner user;
}

class AuthFailure extends AuthState {
  const AuthFailure(this.message);
  final String message;
}
