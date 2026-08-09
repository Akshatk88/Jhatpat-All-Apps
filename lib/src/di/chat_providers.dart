import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/data/datasources/chat_remote_datasource.dart';
import 'package:superapp_user/src/di/network_providers.dart';

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  return ChatRemoteDataSource(ref.watch(apiClientProvider));
});
