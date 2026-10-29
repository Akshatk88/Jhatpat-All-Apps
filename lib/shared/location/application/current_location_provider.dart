import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:superapp_user/core/i18n/language_provider.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/location/location_service.dart';
import 'package:superapp_user/modules/food/application/providers/location_providers.dart';
import 'package:superapp_user/shared/address/data/address_model.dart';

/// The device's current location and resolved address — fetched **once** for
/// the whole app.
///
/// Before this, four call sites each ran their own GPS fix and reverse geocode
/// (`near_you_viewmodel`, `zone_viewmodel`, taxi's `home_providers`, and the
/// address screen). Switching Food -> Rides therefore re-acquired GPS and
/// re-geocoded every time, which is slow, drains battery, and bills a Google
/// Geocoding call per switch.
///
/// Deliberately **not** `autoDispose`: the whole point is that it survives
/// module switches. It is refreshed only on an explicit user action — pull to
/// refresh, or tapping the address in the header.
final currentLocationProvider =
    AsyncNotifierProvider<CurrentLocationController, UserLocationResult>(
  CurrentLocationController.new,
);

class CurrentLocationController extends AsyncNotifier<UserLocationResult> {
  static const _prefsKey = 'selected_location_v1';

  /// Starts from the location the user last picked (a saved address or a
  /// "use my current location" fix), so the header, food feed and ride pickup
  /// all reopen on the same place. Falls back to a fresh GPS fix.
  @override
  Future<UserLocationResult> build() async {
    final saved = await _loadSaved();
    if (saved != null) {
      ref.read(selectedLocationLabelProvider.notifier).set(saved.label);
      return saved.result;
    }
    return ref.read(locationServiceProvider).getCurrentLocationAndAddress();
  }

  /// Re-acquires the GPS fix and makes it the app-wide location. Keeps the
  /// previous value on screen while in flight so the header does not flash
  /// empty.
  Future<void> refresh() async {
    final previous = state.value;
    try {
      final result =
          await ref.read(locationServiceProvider).getCurrentLocationAndAddress();
      if (result.isSuccess) {
        await useCurrentLocation(result);
      } else {
        state = AsyncValue.data(previous ?? result);
      }
    } catch (error, stack) {
      // A failed refresh must not blank out a location we already had.
      state = previous != null
          ? AsyncValue.data(previous)
          : AsyncValue.error(error, stack);
    }
  }

  /// Makes a GPS fix the caller already has (e.g. the address screen's "use
  /// my current location" button) the app-wide location.
  Future<void> useCurrentLocation(UserLocationResult result) async {
    if (result.latitude == null || result.longitude == null) return;
    state = AsyncValue.data(result);
    ref.read(selectedLocationLabelProvider.notifier).set(null);
    await _save(result, label: null);
  }

  /// Makes a saved address the app-wide location — what the header shows and
  /// what food and rides use as "where I am".
  Future<void> selectAddress(AddressModel address) async {
    final result = UserLocationResult(
      latitude: address.latitude ?? state.value?.latitude,
      longitude: address.longitude ?? state.value?.longitude,
      street: address.street,
      area: address.street.isNotEmpty ? address.street : address.city,
      city: address.city,
      state: address.state,
      pincode: address.zipCode,
      fullAddress: address.fullAddress,
    );
    final label =
        address.title.trim().isNotEmpty ? address.title.trim() : address.type;
    state = AsyncValue.data(result);
    ref.read(selectedLocationLabelProvider.notifier).set(label);
    await _save(result, label: label);
  }

  Future<void> _save(UserLocationResult r, {required String? label}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'label': label,
          'latitude': r.latitude,
          'longitude': r.longitude,
          'building': r.building,
          'street': r.street,
          'area': r.area,
          'landmark': r.landmark,
          'city': r.city,
          'state': r.state,
          'pincode': r.pincode,
          'fullAddress': r.fullAddress,
        }),
      );
    } catch (_) {
      // Persisting is a convenience; the in-memory selection still applies.
    }
  }

  Future<({UserLocationResult result, String? label})?> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final lat = (m['latitude'] as num?)?.toDouble();
      final lng = (m['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      String s(String k) => (m[k] ?? '').toString();
      return (
        result: UserLocationResult(
          latitude: lat,
          longitude: lng,
          building: s('building'),
          street: s('street'),
          area: s('area'),
          landmark: s('landmark'),
          city: s('city'),
          state: s('state'),
          pincode: s('pincode'),
          fullAddress: s('fullAddress'),
        ),
        label: m['label'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Name of the picked saved address ("Home", "Office"), or null when the
/// app-wide location is the device's own GPS fix.
final selectedLocationLabelProvider =
    NotifierProvider<SelectedLocationLabel, String?>(SelectedLocationLabel.new);

class SelectedLocationLabel extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? label) => state = label;
}

/// Short label for the header — Area or Locality name.
final currentLocationLabelProvider = Provider<String>((ref) {
  ref.watch(localeProvider);
  final picked = ref.watch(selectedLocationLabelProvider);
  if (picked != null && picked.isNotEmpty) return picked;
  final result = ref.watch(currentLocationProvider).value;
  if (result == null) return 'Locating…';
  final area = result.area.trim();
  if (area.isNotEmpty && !area.startsWith('Lat:')) {
    return area.contains(',') ? area.split(',').first.trim() : area;
  }
  final city = result.city.trim();
  if (city.isNotEmpty && !city.startsWith('Lat:')) return city;
  return 'Current location'.tr;
});

/// Full address line under the label — formatted as "Area, City, State".
final currentAddressLineProvider = Provider<String>((ref) {
  ref.watch(localeProvider);
  final async = ref.watch(currentLocationProvider);
  final result = async.value;
  if (result == null) {
    return async.isLoading ? 'Finding your location…'.tr : '';
  }
  if (result.isServiceDisabled) return 'Turn on location services'.tr;
  if (result.isPermissionDenied || result.isPermanentlyDenied) {
    return 'Location permission needed'.tr;
  }

  // A picked saved address shows exactly as the user saved it.
  final picked = ref.watch(selectedLocationLabelProvider);
  if (picked != null && result.fullAddress.trim().isNotEmpty) {
    return result.fullAddress.trim();
  }

  final area = result.area.trim();
  final city = result.city.trim();
  final state = result.state.trim();

  final parts = <String>[];
  if (area.isNotEmpty && !area.startsWith('Lat:')) {
    parts.add(area);
  }
  if (city.isNotEmpty && !city.startsWith('Lat:') && !parts.contains(city)) {
    parts.add(city);
  }
  if (state.isNotEmpty && !state.startsWith('Lat:') && !parts.contains(state)) {
    parts.add(state);
  }

  if (parts.isNotEmpty) {
    return parts.join(', ');
  }

  final full = result.fullAddress.trim();
  if (full.isNotEmpty && !full.startsWith('Lat:')) return full;

  return 'Tap to set your address'.tr;
});
