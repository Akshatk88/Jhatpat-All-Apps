import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import 'work_mode.dart';

/// What the driver is set up for and which module they are working in.
class WorkModeStatus {
  const WorkModeStatus({
    required this.mode,
    required this.capabilities,
    this.serverWire = 'delivery',
    this.driverClass = '',
    this.taxiOnline = false,
  });

  /// The modules switched on (any of food / parcel / rider).
  final WorkModeSet mode;

  /// `taxi` / `delivery` / `parcel` — what the operator has approved this
  /// driver for. A module outside these is disabled in the UI.
  final Set<String> capabilities;

  /// What the server actually stores (`all | taxi | delivery`). Parcel and
  /// rider both map to `taxi`, so a switch between them needs no server call.
  final String serverWire;

  /// `two_wheeler | passenger_taxi | parcel_vehicle`, or '' when unset.
  final String driverClass;

  /// `Driver.isOnline` on the taxi document when it was last read (only
  /// `GET /taxi/drivers/me` carries it). Parcel and Rider keep the food
  /// availability offline, so after an app restart this — not the food
  /// partner's availability — says whether the rider left the ride dispatcher
  /// switched on.
  final bool taxiOnline;

  bool get canDoFood => WorkMode.food.isAllowedFor(capabilities);
  bool get canDoParcel => WorkMode.parcel.isAllowedFor(capabilities);
  bool get canDoRides => WorkMode.rider.isAllowedFor(capabilities);

  /// Re-derives [mode] from [serverWire] with the rider's saved choice.
  WorkModeStatus resolvedWith(WorkModeSet? preferred) => copyWith(
        mode: WorkModeSet.resolve(
          serverWire: serverWire,
          capabilities: capabilities,
          preferred: preferred,
        ),
      );

  WorkModeStatus copyWith({WorkModeSet? mode}) => WorkModeStatus(
        mode: mode ?? this.mode,
        capabilities: capabilities,
        serverWire: serverWire,
        driverClass: driverClass,
        taxiOnline: taxiOnline,
      );

  static const fallback = WorkModeStatus(
    mode: WorkModeSet.food,
    capabilities: {'delivery'},
  );

  /// Used when the driver document cannot be read. Keeps the module the rider
  /// last picked on this device instead of dropping them into Food — on a
  /// flaky start that would put a Rider back on the food dispatcher and let
  /// food offers ring while they are carrying a passenger.
  static WorkModeStatus offlineFallback(WorkModeSet? preferred) {
    if (preferred == null || preferred.isEmpty || preferred == WorkModeSet.food) {
      return fallback;
    }
    return WorkModeStatus(
      mode: preferred,
      capabilities: {
        'delivery',
        for (final m in preferred.modules) m.capability,
      },
      serverWire: preferred.wire,
    );
  }
}

class WorkModeRepository {
  WorkModeRepository(this._dio);

  final Dio _dio;

  /// Reads the driver document for the current work mode and capabilities.
  Future<Result<WorkModeStatus, AppError>> fetch() async {
    try {
      final res = await _dio.get(ApiEndpoints.driverMe);
      final driver = _driverOf(res.data);
      return Result.success(_statusOf(driver));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // An unexpected body shape must not leave the switcher spinning.
      return Result.failure(NetworkError('Could not read work mode: $e'));
    }
  }

  Future<Result<WorkModeStatus, AppError>> setMode(WorkModeSet mode) async {
    try {
      final res = await _dio.patch(
        ApiEndpoints.workMode,
        data: {'workMode': mode.wire},
      );
      final data = res.data is Map<String, dynamic>
          ? (res.data['data'] as Map<String, dynamic>? ?? const {})
          : const <String, dynamic>{};
      return Result.success(_statusOf(data));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      return Result.failure(NetworkError('Could not update work mode'));
    }
  }

  Map<String, dynamic> _driverOf(dynamic body) {
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is Map<String, dynamic>) {
      final driver = data['driver'];
      if (driver is Map<String, dynamic>) return driver;
      return data;
    }
    return const {};
  }

  WorkModeStatus _statusOf(Map<String, dynamic> json) {
    final raw = json['serviceCapabilities'];
    final caps = raw is List
        ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    // An empty list from the server means "taxi only" — that is the schema
    // default, and treating it as "no capabilities" would disable every
    // option and leave the driver stuck.
    final capabilities = caps.isEmpty ? {'taxi'} : caps;
    final wire = (json['workMode']?.toString() ?? '').trim().toLowerCase();
    final serverWire = wire.isEmpty ? 'delivery' : wire;
    return WorkModeStatus(
      // No saved preference here; the controller re-resolves with it.
      mode: WorkModeSet.resolve(serverWire: serverWire, capabilities: capabilities),
      capabilities: capabilities,
      serverWire: serverWire,
      driverClass: json['driverClass']?.toString() ?? '',
      taxiOnline: json['isOnline'] == true,
    );
  }

  AppError _mapError(DioException e) {
    final data = e.response?.data;
    final message = data is Map
        ? (data['message'] ?? data['error'])?.toString()
        : null;
    return NetworkError(message ?? e.message ?? 'Could not update work mode');
  }
}

final workModeRepositoryProvider = Provider<WorkModeRepository>((ref) {
  return WorkModeRepository(ref.read(dioProvider));
});
