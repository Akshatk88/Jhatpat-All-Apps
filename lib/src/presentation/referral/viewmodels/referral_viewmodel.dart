import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/core/constants/app_constants.dart';
import 'package:superapp_user/src/data/models/wallet_model.dart';
import 'package:superapp_user/src/di/account_providers.dart';
import 'package:superapp_user/src/presentation/auth/viewmodels/auth_viewmodel.dart';

/// Referral stats and invite history from `GET /food/user/referrals/details`.
final referralDetailsProvider = FutureProvider.autoDispose<ReferralDetails>((ref) async {
  final account = ref.watch(accountRemoteDataSourceProvider);
  return account.getReferralDetails();
});

/// The share link carries the user's referralCode as `ref`, which
/// verify-otp credits on brand-new accounts only.
final referralShareLinkProvider = Provider<String>((ref) {
  final code = ref.watch(authViewModelProvider).value?.referralCode ?? '';
  if (code.isEmpty) return '';
  return '${AppConstants.hostUrl}/invite?ref=$code';
});
