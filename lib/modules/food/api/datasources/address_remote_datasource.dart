import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/core/network/api_client.dart';
import 'package:superapp_user/shared/address/data/address_model.dart';

/// `/food/user/addresses` (Bearer).
class AddressRemoteDataSource {
  final ApiClient _client;

  const AddressRemoteDataSource(this._client);

  /// `{ address }` normally; tolerates the bare object, and throws a
  /// catchable error (not a cast TypeError) when the server sent neither.
  static AddressModel _parseAddress(Map<String, dynamic>? data) {
    final a = data?['address'] ??
        ((data != null && (data.containsKey('_id') || data.containsKey('id'))) ? data : null);
    if (a is Map) return AddressModel.fromApi(a.cast<String, dynamic>());
    throw StateError('Address response had no address');
  }

  Future<List<AddressModel>> getAddresses() async {
    final data = await _client.get<Map<String, dynamic>>(ApiPaths.addresses);
    final raw = data['addresses'] ?? data['results'] ?? data['data'];
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => AddressModel.fromApi(e.cast<String, dynamic>()))
        .toList();
  }

  Future<AddressModel> addAddress(AddressModel address) async {
    final data = await _client.post<Map<String, dynamic>>(
      ApiPaths.addresses,
      body: address.toApiPayload(),
    );
    return _parseAddress(data);
  }

  Future<AddressModel> updateAddress(AddressModel address) async {
    final data = await _client.patch<Map<String, dynamic>>(
      '${ApiPaths.addresses}/${address.id}',
      body: address.toApiPayload(),
    );
    return _parseAddress(data);
  }

  Future<void> deleteAddress(String id) async {
    await _client.delete<dynamic>('${ApiPaths.addresses}/$id');
  }

  Future<AddressModel> setDefault(String id) async {
    final data = await _client.patch<Map<String, dynamic>>('${ApiPaths.addresses}/$id/default');
    return _parseAddress(data);
  }
}
