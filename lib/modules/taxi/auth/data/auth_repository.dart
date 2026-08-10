import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';
import 'package:superapp_user/core/network/taxi_api_client.dart';
import 'package:superapp_user/modules/taxi/auth/data/models/user_model.dart';

class OtpSendResult {
  final bool exists;
  final String? debugOtp;

  OtpSendResult({required this.exists, this.debugOtp});
}

class OtpVerifyResult {
  final bool exists;
  final String? token;
  final TaxiUserModel? user;

  OtpVerifyResult({required this.exists, this.token, this.user});
}

class TaxiAuthSession {
  final String token;
  final TaxiUserModel user;

  TaxiAuthSession({required this.token, required this.user});
}

class TaxiAuthRepository {
  final TaxiApiClient api;

  TaxiAuthRepository(this.api);

  Future<OtpSendResult> sendOtp(String phone) async {
    final data = await api.post(ApiConstants.sendOtp, data: {'phone': phone});
    final session = data['session'] as Map<String, dynamic>?;
    return OtpSendResult(
      exists: data['exists'] == true,
      debugOtp: session?['debugOtp']?.toString(),
    );
  }

  Future<OtpVerifyResult> verifyOtp({required String phone, required String otp}) async {
    final data = await api.post(
      ApiConstants.verifyOtp,
      data: {'phone': phone, 'otp': otp},
    );
    final exists = data['exists'] == true;
    if (exists) {
      return OtpVerifyResult(
        exists: true,
        token: data['token']?.toString(),
        user: TaxiUserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? {})),
      );
    }
    return OtpVerifyResult(exists: false);
  }

  Future<TaxiAuthSession> signup({
    required String phone,
    required String name,
    String? email,
    String? gender,
    String? referralCode,
  }) async {
    final data = await api.post(ApiConstants.signup, data: {
      'phone': phone,
      'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      if (referralCode != null && referralCode.isNotEmpty) 'referralCode': referralCode,
    });
    return TaxiAuthSession(
      token: data['token'].toString(),
      user: TaxiUserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? {})),
    );
  }

  Future<TaxiUserModel> getCurrentUser() async {
    final data = await api.get(ApiConstants.me);
    return TaxiUserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? data));
  }

  Future<TaxiUserModel> updateProfile(Map<String, dynamic> fields) async {
    final data = await api.patch(ApiConstants.me, data: fields);
    return TaxiUserModel.fromJson(Map<String, dynamic>.from(data['user'] ?? data));
  }

  Future<String> uploadProfileImage(String dataUrl) async {
    final data = await api.post(ApiConstants.profileImage, data: {'dataUrl': dataUrl});
    return (data['secureUrl'] ?? '').toString();
  }

  Future<void> saveFcmToken(String token, {required String platform}) {
    return api.post(ApiConstants.fcmToken, data: {'token': token, 'platform': platform});
  }

  Future<void> requestAccountDeletion(String reason) {
    return api.post(ApiConstants.deleteRequest, data: {'reason': reason});
  }
}
