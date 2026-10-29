import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/module_registry.dart';

/// Pins the contract that registering a module is enough for it to appear
/// everywhere the user can reach it.
///
/// This exists because it was **not** true. The service switcher at the top of
/// every module home carried a hardcoded three-item list, so adding the
/// services module put a tile on the hub and mounted its routes, but left the
/// navigation bar showing Food / Rides / Parcel only. The hub and the switcher
/// now derive from this same registry; these tests fail if either drifts back
/// to its own list.
///
/// Run with:  flutter test test/module_registration_test.dart
void main() {
  late ProviderContainer container;
  late ModuleRegistry registry;

  setUp(() {
    container = ProviderContainer();
    registry = container.read(moduleRegistryProvider);
  });

  tearDown(() => container.dispose());

  test('services is registered and enabled', () {
    final services = registry.byId(ModuleId.services);
    expect(services, isNotNull, reason: 'ServicesModule missing from the registry');
    expect(services!.isEnabled, isTrue);
    expect(registry.enabled.map((m) => m.id), contains(ModuleId.services));
  });

  test('every enabled module can render a switcher tab', () {
    for (final module in registry.enabled) {
      expect(module.label, isNotEmpty, reason: '${module.id.name} has no label');
      expect(module.tagline, isNotEmpty, reason: '${module.id.name} has no tagline');
      expect(module.entryRoute, startsWith('/${module.id.name}'),
          reason: '${module.id.name} entryRoute is not namespaced');
    }
  });

  test('switcher labels and taglines stay short enough for a 4-tab bar', () {
    // The bar divides the screen evenly, so a long string does not wrap — it
    // ellipsises away to nothing. These bounds are what the compact type sizes
    // in ModuleTopNav were chosen against.
    for (final module in registry.enabled) {
      expect(module.label.length, lessThanOrEqualTo(10),
          reason: '"${module.label}" will be clipped in the switcher');
      expect(module.tagline.length, lessThanOrEqualTo(16),
          reason: '"${module.tagline}" will be clipped in the switcher');
    }
  });

  test('enabled modules come back in hub order, with no duplicate order', () {
    final orders = registry.enabled.map((m) => m.order).toList();
    expect(orders, orderedEquals(List.of(orders)..sort()));
    expect(orders.toSet().length, orders.length, reason: 'two modules share an order');
  });

  test('a disabled module is hidden rather than removed', () {
    // Rental is off until the backend serves its routes. It must still be
    // registered — deep links into it should 404 through the router, not blow
    // up a registry lookup.
    final rental = registry.byId(ModuleId.rental);
    expect(rental, isNotNull);
    expect(rental!.isEnabled, isFalse);
    expect(registry.enabled.map((m) => m.id), isNot(contains(ModuleId.rental)));
  });

  test('module route prefixes are unique', () {
    final prefixes = registry.all.map((m) => m.entryRoute).toList();
    expect(prefixes.toSet().length, prefixes.length);
  });
}
