import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/platform/notifications/push_service.dart';
import 'package:superapp_user/src/di/account_providers.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(accountRemoteDataSourceProvider));
  ref.onDispose(service.dispose);
  return service;
});
