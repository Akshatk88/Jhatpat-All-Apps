import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/core/i18n/language_provider.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:superapp_user/design_system/theme/app_theme.dart';
import 'package:superapp_user/design_system/theme/theme_color_provider.dart';
import 'package:superapp_user/design_system/theme/theme_provider.dart';
import 'package:superapp_user/app/routing/app_router.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:superapp_user/core/push/push_providers.dart';
import 'package:superapp_user/core/push/push_service.dart';
import 'package:superapp_user/modules/services/application/sp_push_sink.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';

class SuperApp extends ConsumerStatefulWidget {
  const SuperApp({super.key});

  @override
  ConsumerState<SuperApp> createState() => _SuperAppState();
}

class _SuperAppState extends ConsumerState<SuperApp> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Push listeners are wired once for the app's lifetime. Deep links are
    // handed to the router rather than the service touching navigation itself.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pushService = ref.read(pushServiceProvider);
      await pushService.initialize(
        onDeepLink: _handleDeepLink,
        onPermanentlyDenied: _showPermissionExplanationDialog,
      );

      final user = ref.read(authViewModelProvider).value;
      await pushService.performAppStartCheck(
        isLoggedIn: user != null,
        user: user,
      );
    });
  }

  void _showPermissionExplanationDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notifications Disabled'.tr),
        content: Text(
          'Notifications are required to receive real-time updates about your food orders (Order Accepted, Out for Delivery, Delivered, etc.). Please enable notifications in App Settings.'.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Later'.tr),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5700),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: Text('Open Settings'.tr, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Routes an order push to the tracking screen.
  void _handleDeepLink(PushDeepLink link) {
    if (link.isRideEvent) {
      final router = ref.read(routerProvider);
      final status = (link.status ?? '').toLowerCase();
      if (status == 'cancelled' || link.type.contains('cancel')) {
        router.go('/taxi');
      } else if (status == 'completed') {
        router.push('/taxi/rides/${link.rideId}/rate');
      } else {
        router.push('/taxi/rides/${link.rideId}/track');
      }
      return;
    }
    final orderId = link.trackableOrderId;
    if (!link.isOrderEvent || orderId == null || orderId.isEmpty) return;
    // Route is declared as /orders/track/:id — a path param, not a query.
    ref.read(routerProvider).push('/orders/track/$orderId');
  }

  @override
  Widget build(BuildContext context) {
    final goRouter = ref.watch(routerProvider);

    // Register the device against the account on login; unregister on logout so
    // the next user of the device is not targeted.
    ref.listen(authViewModelProvider, (previous, next) {
      final was = previous?.value?.id;
      final now = next.value?.id;
      if (was == now && now != null) return;
      final push = ref.read(pushServiceProvider);
      if (now != null) {
        // Each module that keeps its own token list registers a sink; the push
        // service fans the token out to all of them. Done here rather than in
        // the module because logout has to clear SP's token even for a session
        // where the customer never opened the Services tab.
        push.addTokenSink(ref.read(spPushTokenSinkProvider));
        push.registerToken(user: next.value);
      } else if (previous?.value != null && now == null) {
        push.unregisterToken();
      }
    });

    // Rebuilds MaterialApp (and therefore every widget under it) whenever the
    // user picks a different app theme color — the single trigger that makes
    // the centralized ThemeColorNotifier's change reach the whole app.
    ref.watch(themeColorProvider);

    // App language. Strings go through `.tr`, which reads a static rather
    // than the context, so on a change every element is marked dirty once —
    // the open screen redraws in the new language without losing its place.
    final languageCode = ref.watch(localeProvider);
    ref.listen(localeProvider, (prev, next) {
      if (prev == next) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void rebuild(Element el) {
          el.markNeedsBuild();
          el.visitChildren(rebuild);
        }

        WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
      });
    });

    return Builder(
      builder: (context) => ScreenUtilInit(
        designSize: _designSizeFor(MediaQuery.sizeOf(context)),
        minTextAdapt: true,
        builder: (context, child) => MaterialApp.router(
          title: 'JhatPat',
          scaffoldMessengerKey: _scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ref.watch(themeProvider),
          // System widgets (date pickers, dialogs' OK/Cancel) follow too.
          locale: Locale(languageCode),
          supportedLocales: const [Locale('en'), Locale('hi')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: goRouter,
        ),
      ),
    );
  }

  /// ScreenUtil scales `.w`/`.sp` by width/375 and `.h` by height/812. That
  /// is right on portrait phones, which keep exactly the 375×812 design. On a
  /// tablet, desktop window or a phone in landscape it made text and boxes
  /// 2–3x bigger while `.h` heights got squashed, so there the design size is
  /// chosen to give one uniform scale (from the shortest side, 0.85–1.2) on
  /// both axes.
  static Size _designSizeFor(Size screen) {
    const design = Size(375, 812);
    if (screen.isEmpty) return design;
    final isPortraitPhone =
        screen.width <= 450 && screen.height >= screen.width;
    if (isPortraitPhone) return design;
    final scale = (screen.shortestSide / design.width).clamp(0.85, 1.2);
    return Size(screen.width / scale, screen.height / scale);
  }
}

