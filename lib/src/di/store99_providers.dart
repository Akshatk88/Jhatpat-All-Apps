import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/data/repository/store99_repository_impl.dart';
import 'package:superapp_user/src/domain/repository/store99_repository.dart';
import 'package:superapp_user/src/domain/service/store99_service.dart';
import 'package:superapp_user/src/presentation/home/viewmodels/zone_viewmodel.dart';
import 'package:superapp_user/src/di/catalog_providers.dart';

final store99RepositoryProvider = Provider<Store99Repository>((ref) {
  return Store99RepositoryImpl(
    ref.watch(catalogRemoteDataSourceProvider),
    () => ref.read(currentZoneIdProvider),
  );
});

final store99ServiceProvider = Provider<Store99Service>((ref) {
  return Store99Service(ref.watch(store99RepositoryProvider));
});
