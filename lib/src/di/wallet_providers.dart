import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/data/repository/wallet_repository_impl.dart';
import 'package:superapp_user/src/domain/repository/wallet_repository.dart';
import 'package:superapp_user/src/domain/service/wallet_service.dart';
import 'package:superapp_user/src/di/account_providers.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final remote = ref.watch(accountRemoteDataSourceProvider);
  return WalletRepositoryImpl(remote);
});

final walletServiceProvider = Provider<WalletService>((ref) {
  final repository = ref.watch(walletRepositoryProvider);
  return WalletService(repository);
});
