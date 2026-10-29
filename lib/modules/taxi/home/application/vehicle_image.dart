import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/modules/taxi/home/data/models/vehicle_type_model.dart';

/// The admin-uploaded picture for [vehicle]: `image` first, `map_icon` when
/// only that one is set. Resolved to an absolute URL, or '' when neither is.
String adminVehicleImage(VehicleTypeModel? vehicle) {
  if (vehicle == null) return '';
  // map_icon is usually a base64 data URI, which a network image cannot
  // fetch (and resolveMedia would mangle into a host path), so skip those.
  for (final raw in [vehicle.image.trim(), vehicle.mapIcon.trim()]) {
    if (raw.isNotEmpty && !raw.startsWith('data:')) {
      return ApiConfig.resolveMedia(raw);
    }
  }
  return '';
}

/// Finds the catalog entry a ride refers to. Rides carry the vehicle type as
/// an id or a display name, sometimes only its icon type, so all three are
/// tried in that order of precision.
VehicleTypeModel? findVehicleType(
  List<VehicleTypeModel> catalog, {
  String? idOrName,
  String? iconType,
}) {
  final key = (idOrName ?? '').trim().toLowerCase();
  if (key.isNotEmpty) {
    for (final v in catalog) {
      if (v.id.toLowerCase() == key || v.name.trim().toLowerCase() == key) {
        return v;
      }
    }
  }
  final icon = (iconType ?? '').trim().toLowerCase();
  if (icon.isNotEmpty) {
    for (final v in catalog) {
      if (v.iconType.toLowerCase() == icon) return v;
    }
  }
  return null;
}
