import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superapp_user/design_system/components/nav/module_top_nav.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/module_registry.dart';

/// Renders the service switcher with the real registry and checks the tabs.
///
/// The bug this guards: the bar used to hold its own hardcoded list, so
/// "Services" never appeared no matter what the registry said.
///
/// Run with:  flutter test test/module_top_nav_test.dart
void main() {
  Future<void> pumpNav(WidgetTester tester, {required ModuleId active}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final registry = container.read(moduleRegistryProvider);

    final items = [
      for (final module in registry.enabled)
        NavItem(
          id: module.id,
          label: module.label,
          tagline: module.tagline,
          imageAsset: module.navIconAsset,
          fallbackIcon: module.icon,
          route: module.entryRoute,
        ),
    ];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            // Phone-width so the 4-tab layout is exercised at a realistic size.
            body: SizedBox(
              width: 360,
              child: ModuleTopNav(activeModule: active, items: items),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows a tab for every enabled module, including Services',
      (tester) async {
    await pumpNav(tester, active: ModuleId.food);

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Parcel'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);

    // Rental is disabled, so it must not be offered.
    expect(find.text('Rentals'), findsNothing);
  });

  testWidgets('lays out four tabs without overflowing a 360dp bar',
      (tester) async {
    await pumpNav(tester, active: ModuleId.services);
    // A RenderFlex overflow is reported as a test failure by the framework, so
    // reaching here with no exception is the assertion.
    expect(tester.takeException(), isNull);
    expect(find.text('Services'), findsOneWidget);
  });

  testWidgets('the active module is the one that is not tappable',
      (tester) async {
    await pumpNav(tester, active: ModuleId.services);

    final inkWells = tester
        .widgetList<InkWell>(find.byType(InkWell))
        .where((w) => w.onTap == null)
        .toList();

    // Exactly one tab is inert: the one you are already on.
    expect(inkWells.length, 1);
  });
}
