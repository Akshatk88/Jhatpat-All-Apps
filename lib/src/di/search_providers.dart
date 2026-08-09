import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/src/data/datasources/search_local_datasource.dart';
import 'package:superapp_user/src/data/datasources/search_remote_datasource.dart';
import 'package:superapp_user/src/data/repository/search_repository_impl.dart';
import 'package:superapp_user/src/domain/repository/search_repository.dart';
import 'package:superapp_user/src/domain/service/search_service.dart';
import 'package:superapp_user/src/platform/speech/speech_service.dart';
import 'package:superapp_user/src/di/catalog_providers.dart';
import 'package:superapp_user/src/presentation/home/viewmodels/zone_viewmodel.dart';

final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService();
});

final searchLocalDataSourceProvider = Provider<SearchLocalDataSource>((ref) {
  return SearchLocalDataSourceImpl();
});

final searchRemoteDataSourceProvider = Provider<SearchRemoteDataSource>((ref) {
  return SearchRemoteDataSourceImpl(
    ref.watch(catalogRemoteDataSourceProvider),
    () => ref.read(currentZoneIdProvider),
  );
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final remote = ref.watch(searchRemoteDataSourceProvider);
  final local = ref.watch(searchLocalDataSourceProvider);
  return SearchRepositoryImpl(
    remoteDataSource: remote,
    localDataSource: local,
  );
});

final searchServiceProvider = Provider<SearchService>((ref) {
  final repository = ref.watch(searchRepositoryProvider);
  return SearchService(repository);
});
