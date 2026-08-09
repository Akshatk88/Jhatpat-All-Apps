import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/modules/food/api/datasources/chat_remote_datasource.dart';
import 'package:superapp_user/modules/food/application/providers/network_providers.dart';

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  return ChatRemoteDataSource(ref.watch(apiClientProvider));
});
