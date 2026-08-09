import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/modules/food/api/datasources/account_remote_datasource.dart';
import 'package:superapp_user/modules/food/application/providers/network_providers.dart';

final accountRemoteDataSourceProvider = Provider<AccountRemoteDataSource>((ref) {
  return AccountRemoteDataSource(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  );
});
