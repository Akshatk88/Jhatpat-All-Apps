import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/src/data/datasources/favorites_remote_datasource.dart';
import 'package:superapp_user/src/data/repository/favorites_repository_impl.dart';
import 'package:superapp_user/src/domain/repository/favorites_repository.dart';
import 'package:superapp_user/src/di/network_providers.dart';

final favoritesRemoteDataSourceProvider = Provider<FavoritesRemoteDataSource>((ref) {
  return FavoritesRemoteDataSource(ref.watch(apiClientProvider));
});

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  final remote = ref.watch(favoritesRemoteDataSourceProvider);
  return FavoritesRepositoryImpl(remote);
});

