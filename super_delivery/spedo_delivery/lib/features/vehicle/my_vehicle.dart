import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/core/network/api_endpoints.dart';
import 'package:food_user_application/core/network/dio_client.dart';
import 'package:food_user_application/features/onboarding/data/onboarding_models.dart';
import 'package:food_user_application/features/onboarding/data/onboarding_repository.dart';
// Result's `when` resolves only where the declaring library is imported.
import 'package:food_user_application/core/error/result.dart';

/// The rider's vehicle as the ride dispatcher sees it (`GET /taxi/drivers/me`).
///
/// Ride and parcel dispatch match a driver on `vehicleTypeId` (or the vehicle
/// type / icon key). A delivery partner approved through the food flow gets a
/// taxi Driver whose `vehicleTypeId` is empty — the catalogue id the rider
/// picked at onboarding sits in `vehicleType` instead — so no booking ever
/// matches them ("No drivers available"). This reads that state so the app
/// can fix it through the driver's own `PATCH /taxi/drivers/vehicle`.
class MyVehicle {
  const MyVehicle({
    required this.vehicleTypeId,
    required this.vehicleType,
    required this.vehicleIconType,
    required this.vehicleNumber,
    required this.driverClass,
    required this.approved,
  });

  final String vehicleTypeId;
  final String vehicleType;
  final String vehicleIconType;
  final String vehicleNumber;
  final String driverClass;
  final bool approved;

  static final _objectId = RegExp(r'^[a-f0-9]{24}$');

  /// True when ride/parcel dispatch cannot match this driver to any vehicle.
  bool get needsVehicleType => vehicleTypeId.isEmpty;

  /// The catalogue id chosen at onboarding, when that is what `vehicleType`
  /// holds — the right default to set as `vehicleTypeId`.
  String? get onboardingVehicleId =>
      _objectId.hasMatch(vehicleType) ? vehicleType : null;

  factory MyVehicle.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => (v ?? '').toString().trim();
    return MyVehicle(
      vehicleTypeId: s(json['vehicleTypeId']) == 'null' ? '' : s(json['vehicleTypeId']),
      vehicleType: s(json['vehicleType']),
      vehicleIconType: s(json['vehicleIconType']),
      vehicleNumber: s(json['vehicleNumber']),
      driverClass: s(json['driverClass']),
      approved: json['approve'] != false &&
          s(json['status']).toLowerCase() != 'pending',
    );
  }
}

class MyVehicleRepository {
  MyVehicleRepository(this._dio);
  final Dio _dio;

  Future<MyVehicle?> fetch() async {
    try {
      final res = await _dio.get(ApiEndpoints.driverMe);
      final data = res.data is Map ? res.data['data'] : null;
      if (data is! Map) return null;
      final driver = data['driver'] is Map ? data['driver'] : data;
      return MyVehicle.fromJson(Map<String, dynamic>.from(driver as Map));
    } on DioException {
      return null;
    }
  }

  /// `PATCH /taxi/drivers/vehicle` — sets vehicleTypeId, vehicleType and
  /// vehicleIconType from the catalogue entry. Returns the server's message,
  /// or throws with the error message.
  Future<String> setVehicleType(String vehicleTypeId) async {
    try {
      final res = await _dio.patch(
        '/taxi/drivers/vehicle',
        data: {'vehicleTypeId': vehicleTypeId},
      );
      final body = res.data;
      return (body is Map ? body['message'] : null)?.toString() ??
          'Vehicle updated';
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? (body['message'] ?? body['error']) : null;
      throw Exception(msg?.toString() ?? 'Could not update vehicle');
    }
  }
}

final myVehicleRepositoryProvider = Provider<MyVehicleRepository>(
  (ref) => MyVehicleRepository(ref.read(dioProvider)),
);

final myVehicleProvider = FutureProvider.autoDispose<MyVehicle?>(
  (ref) => ref.read(myVehicleRepositoryProvider).fetch(),
);

/// The vehicle types a driver can pick.
///
/// Source is the ride catalogue the passenger app books from
/// (`GET /taxi/users/vehicle-types`) — that is what dispatch matches on, and
/// it returns every active type. The onboarding requirements endpoint is only
/// a fallback: filtered by driver class it came back empty for riders whose
/// class it doesn't map, showing "No vehicle types are set up".
final vehicleCatalogueProvider =
    FutureProvider.autoDispose.family<List<OnboardingVehicleType>, String>(
  (ref, driverClass) async {
    try {
      final res = await ref.read(dioProvider).get('/taxi/users/vehicle-types');
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      final list = data is Map
          ? data['results']
          : (data is List ? data : (body is Map ? body['results'] : null));
      if (list is List) {
        final types = list
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .where((m) =>
                m['active'] != false &&
                '${m['status'] ?? 1}' != '0' &&
                // Ride/parcel dispatch types only — not food.
                ['taxi', 'delivery', 'both', '']
                    .contains('${m['transport_type'] ?? ''}'.toLowerCase()))
            .map((m) => OnboardingVehicleType(
                  id: '${m['_id'] ?? m['id'] ?? ''}',
                  name: '${m['name'] ?? ''}',
                  iconType: '${m['icon_types'] ?? ''}',
                  transportType: '${m['transport_type'] ?? ''}',
                  image: '${m['image'] ?? m['map_icon'] ?? ''}',
                  capacity: int.tryParse('${m['capacity'] ?? 0}') ?? 0,
                ))
            .where((t) => t.id.isNotEmpty && t.name.isNotEmpty)
            .toList();
        if (types.isNotEmpty) return types;
      }
    } on DioException {
      // fall through to the onboarding catalogue
    }

    final result = await ref.read(onboardingRepositoryProvider).getRequirements(
          (driverClass: driverClass, intentsCsv: ''),
        );
    return result.when(
      success: (req) => req.vehicleTypes,
      failure: (_) => const <OnboardingVehicleType>[],
    );
  },
);

/// Profile → My vehicle: shows the vehicle type dispatch uses and lets the
/// rider set it.
class MyVehicleScreen extends ConsumerStatefulWidget {
  const MyVehicleScreen({super.key});

  @override
  ConsumerState<MyVehicleScreen> createState() => _MyVehicleScreenState();
}

class _MyVehicleScreenState extends ConsumerState<MyVehicleScreen> {
  String? _picked;
  bool _saving = false;

  Future<void> _save(MyVehicle current) async {
    final id = _picked ?? current.onboardingVehicleId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update vehicle type?'),
        content: const Text(
          'Your vehicle goes to the admin for approval. Until it is approved '
          'you will not get ride or parcel requests. Food orders are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final msg =
          await ref.read(myVehicleRepositoryProvider).setVehicleType(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      ref.invalidate(myVehicleProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFF04438),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicleAsync = ref.watch(myVehicleProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My vehicle')),
      body: vehicleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _retry(),
        data: (vehicle) {
          if (vehicle == null) return _retry();
          final catalogue =
              ref.watch(vehicleCatalogueProvider(vehicle.driverClass));
          final selectedId =
              _picked ?? (vehicle.vehicleTypeId.isNotEmpty
                  ? vehicle.vehicleTypeId
                  : vehicle.onboardingVehicleId);

          return ListView(
            padding: EdgeInsets.all(16.r),
            children: [
              _StatusCard(vehicle: vehicle),
              SizedBox(height: 20.h),
              Text(
                'Vehicle type',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8.h),
              catalogue.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => const Text('Could not load vehicle types'),
                data: (types) {
                  if (types.isEmpty) {
                    return const Text('No vehicle types are set up by the admin yet.');
                  }
                  return Column(
                    children: [
                      for (final t in types)
                        _VehicleOption(
                          type: t,
                          selected: t.id == selectedId,
                          onTap: () => setState(() => _picked = t.id),
                        ),
                    ],
                  );
                },
              ),
              SizedBox(height: 20.h),
              SizedBox(
                height: 52.h,
                child: ElevatedButton(
                  onPressed: _saving ||
                          selectedId == null ||
                          (selectedId == vehicle.vehicleTypeId)
                      ? null
                      : () => _save(vehicle),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          vehicle.needsVehicleType
                              ? 'Set vehicle type'
                              : 'Change vehicle type',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _retry() => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(myVehicleProvider),
          child: const Text('Could not load your vehicle. Tap to retry'),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.vehicle});
  final MyVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final bad = vehicle.needsVehicleType;
    final pending = !bad && !vehicle.approved;
    final color = bad
        ? const Color(0xFFD92D20)
        : pending
            ? const Color(0xFFB54708)
            : const Color(0xFF067647);
    final text = bad
        ? 'Vehicle type not set — ride and parcel requests cannot reach you. '
            'Pick your vehicle below and tap "Set vehicle type".'
        : pending
            ? 'Vehicle sent for admin approval. Ride and parcel requests start after approval.'
            : 'Vehicle type set. Ride and parcel requests can reach you.';
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bad
                ? Icons.error_outline_rounded
                : pending
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_outline_rounded,
            color: color,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: color, fontSize: 12.5.sp)),
                if (vehicle.vehicleNumber.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    vehicle.vehicleNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleOption extends StatelessWidget {
  const _VehicleOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final OnboardingVehicleType type;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    final k = '${type.iconType} ${type.name}'.toLowerCase();
    if (k.contains('auto') || k.contains('rickshaw')) {
      return Icons.electric_rickshaw_rounded;
    }
    if (k.contains('bike') || k.contains('scoot') || k.contains('moto')) {
      return Icons.two_wheeler_rounded;
    }
    if (k.contains('truck') || k.contains('tempo')) {
      return Icons.local_shipping_rounded;
    }
    return Icons.local_taxi_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Material(
        color: selected ? const Color(0xFFFFF6D6) : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFFB800)
                    : const Color(0xFFE2E8F0),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44.r,
                  height: 44.r,
                  child: type.image.startsWith('http')
                      ? Image.network(
                          type.image,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(_icon),
                        )
                      : Icon(_icon),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    type.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? const Color(0xFFE5A600)
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Home-screen warning when ride/parcel are on but dispatch can't match the
/// rider to a vehicle. Tapping it opens [MyVehicleScreen].
class VehicleTypeBanner extends ConsumerWidget {
  const VehicleTypeBanner({super.key, required this.ridesOn});

  /// Only shown while Parcel or Rider is switched on.
  final bool ridesOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ridesOn) return const SizedBox.shrink();
    final vehicle = ref.watch(myVehicleProvider).value;
    if (vehicle == null || !vehicle.needsVehicleType) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Material(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyVehicleScreen()),
            );
            ref.invalidate(myVehicleProvider);
          },
          child: Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: const Color(0xFFFDA29B)),
            ),
            child: Row(
              children: [
                Icon(Icons.two_wheeler_rounded,
                    color: const Color(0xFFD92D20), size: 22.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    'Vehicle type not set — ride and parcel requests cannot '
                    'reach you. Tap to set it.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF912018),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: const Color(0xFFD92D20), size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
