import 'delivery_partner.dart';

/// The 3-branch payload returned by `POST /food/auth/delivery/verify-otp`.
/// Always arrives with HTTP 200 — callers must branch on these fields,
/// not the status code.
class AuthVerifyResult {
  const AuthVerifyResult({
    required this.needsRegistration,
    required this.pendingApproval,
    required this.isRejected,
    this.phone,
    this.rejectionReason,
    this.accessToken,
    this.refreshToken,
    this.user,
    this.pendingPartner,
  });

  final bool needsRegistration;
  final bool pendingApproval;
  final bool isRejected;
  final String? phone;
  final String? rejectionReason;
  final String? accessToken;
  final String? refreshToken;
  final DeliveryPartner? user;

  /// `deliveryPartner` on a pending-approval reply. The backend fills it only
  /// for a REJECTED partner (null while pending) — it is what lets the app show
  /// what was submitted and prefill a re-application.
  final DeliveryPartner? pendingPartner;

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  factory AuthVerifyResult.fromJson(Map<String, dynamic> json) {
    final pending = json['deliveryPartner'];
    return AuthVerifyResult(
      needsRegistration: json['needsRegistration'] == true,
      pendingApproval: json['pendingApproval'] == true,
      isRejected: json['isRejected'] == true,
      phone: json['phone']?.toString(),
      rejectionReason: json['rejectionReason'] as String?,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      user: json['user'] != null
          ? DeliveryPartner.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      pendingPartner: pending is Map
          ? DeliveryPartner.fromJson(Map<String, dynamic>.from(pending))
          : null,
    );
  }
}
