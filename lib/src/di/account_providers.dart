import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/data/datasources/account_remote_datasource.dart';
import 'package:superapp_user/src/di/network_providers.dart';

final accountRemoteDataSourceProvider = Provider<AccountRemoteDataSource>((ref) {
  return AccountRemoteDataSource(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});
