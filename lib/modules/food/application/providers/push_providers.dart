import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/push/push_service.dart';
import 'package:superapp_user/modules/food/application/providers/account_providers.dart';

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref.watch(accountRemoteDataSourceProvider));
  ref.onDispose(service.dispose);
  return service;
});
