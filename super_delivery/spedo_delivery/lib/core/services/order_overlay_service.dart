import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:food_user_application/core/presentation/widgets/offer_request_card.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';
import 'package:food_user_application/features/rides/presentation/ride_job_kind.dart';
import 'package:food_user_application/features/rides/presentation/widgets/driveu_job_banner.dart';
import '../network/api_endpoints.dart';
import 'sound_service.dart';

const _applicationId = 'com.delivery.jhatpat';
const _pendingOrderPrefsKey = 'pending_overlay_order';

/// The offer the overlay card shows. Written by the native
/// `OfferOverlay.kt` (as `flutter.overlay_offer`) or by [OrderOverlayService.
/// showForOrder]; deliberately NOT the key main.dart consumes on resume, so a
/// ride offer is never turned into an in-app food order.
const _overlayOfferPrefsKey = 'overlay_offer';

/// Native receiver for the card's buttons (OfferActionReceiver.kt).
const _actionReceiver = '$_applicationId.OfferActionReceiver';

/// SharedPreferences that reflect what is actually on disk right now.
///
/// The offer key is written by one side (the native receiver or the FCM
/// background isolate) and read by another (the overlay engine).
/// getInstance() hands back a per-isolate cached singleton holding a snapshot
/// taken the first time it was called in that isolate, and it never re-reads on
/// its own — so a reader whose isolate was already warm sees a value from before
/// the write and concludes there is no pending order.
///
/// Every cross-isolate read of that key goes through here.
Future<SharedPreferences> _freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    await prefs.reload();
  } catch (_) {
    // Best effort — fall back to whatever the cache holds.
  }
  return prefs;
}

/// A usable access token for the overlay (and, through the shared mirror, the
/// native responder), renewing it when it is about to expire or [force]d.
///
/// The access token lives 15 minutes. An offer arriving while the app has
/// been closed longer than that found only an expired token: the ride fetch
/// got 401, the card stayed blank and Accept/Reject failed. The overlay is a
/// separate engine without the app's refresh interceptor, so it renews here
/// with the mirrored refresh token (the server returns the same refresh
/// token, so the app's own copy stays valid) and writes the new access token
/// back to the mirror.
Future<String?> _overlayAccessToken({bool force = false}) async {
  final prefs = await _freshPrefs();
  final token = prefs.getString('native_access_token');
  if (!force && token != null && token.isNotEmpty && !_expiresSoon(token)) {
    return token;
  }
  final refresh = prefs.getString('native_refresh_token');
  final host = prefs.getString('native_api_base_url');
  if (refresh == null || refresh.isEmpty || host == null || host.isEmpty) {
    return token; // nothing to renew with; try what we have
  }
  final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request =
        await client.postUrl(Uri.parse('$base${ApiEndpoints.refreshToken}'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'refreshToken': refresh}));
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return token;
    final decoded = jsonDecode(body);
    final data = decoded is Map && decoded['data'] is Map ? decoded['data'] : decoded;
    final fresh = data is Map ? data['accessToken']?.toString() : null;
    if (fresh == null || fresh.isEmpty) return token;
    await prefs.setString('native_access_token', fresh);
    final newRefresh = data['refreshToken']?.toString();
    if (newRefresh != null && newRefresh.isNotEmpty) {
      await prefs.setString('native_refresh_token', newRefresh);
    }
    return fresh;
  } catch (e) {
    debugPrint('[Overlay] Token refresh failed: $e');
    return token;
  } finally {
    client.close(force: true);
  }
}

/// True when the JWT expires within a minute (or can't be read).
bool _expiresSoon(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.length != 3) return true;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final exp = payload is Map ? payload['exp'] : null;
    if (exp is! num) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    return expiry.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  } catch (_) {
    return true;
  }
}

String? _offerIdOf(Map<dynamic, dynamic>? data) =>
    (data?['orderMongoId'] ?? data?['orderId'] ?? data?['_id'] ?? data?['rideId'])
        ?.toString();

/// The over-other-apps offer card for a job that arrives while the app is not
/// in front.
///
/// Who opens it, per app state:
/// - App in front: never — the in-app offer screen handles the offer.
/// - App not in front, phone unlocked, "display over other apps" granted:
///   `IncomingOrderReceiver.kt` opens it straight off the FCM broadcast
///   (`OfferOverlay.kt`), next to a ringing heads-up notification.
/// - Locked/dark phone or no permission: not used; the native notification and
///   its full-screen `IncomingOrderActivity` cover it.
/// - [showForOrder] from the Dart background handler is only the fallback for
///   a push the native receiver never saw.
///
/// Ringing: when opened natively the card is SILENT and the notification rings
/// (FLAG_INSISTENT); the sound pill mutes that notification. Only the Dart
/// fallback, which has no notification, rings from the card itself.
class OrderOverlayService {
  /// Set on a payload opened by [showForOrder]: no native notification exists,
  /// so the card plays the tone itself.
  static const selfRingingKey = '_overlayRings';

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  static Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  /// Opens the card for [data]. Safe to call from the background FCM isolate.
  ///
  /// Returns whether the window is confirmed running. Some OEM ROMs
  /// (MIUI/ColorOS/etc.) silently drop `TYPE_APPLICATION_OVERLAY` windows even
  /// with the permission granted, and the plugin call can also throw outright.
  static Future<bool> showForOrder(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return false;
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;

    final encoded = jsonEncode(data);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_overlayOfferPrefsKey, encoded);

      // Starting it again while it is up makes the plugin tear the window
      // down; a live card only gets the new data.
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData(encoded);
        return true;
      }

      await FlutterOverlayWindow.showOverlay(
        // Full screen, like the in-app offer screen. A Flutter view never
        // reports its content height to Android, so anything but a fixed size
        // is decided by the OEM's window manager and clipped on some phones.
        height: WindowSize.matchParent,
        width: WindowSize.matchParent,
        // Centre, NOT topCenter: the native receiver (OfferOverlay.kt) starts
        // the same window with the plugin's default centre gravity, and
        // _fitWindowToCard positions the card with centre-gravity maths. A
        // topCenter window took that offset from the top instead and pushed
        // the card's upper half off the screen.
        alignment: OverlayAlignment.center,
        // Focusable and touchable: the buttons take taps.
        flag: OverlayFlag.focusPointer,
        enableDrag: false,
        positionGravity: PositionGravity.none,
        visibility: NotificationVisibility.visibilityPublic,
        overlayTitle: 'New job offer',
      );

      // Give the platform channel a moment to actually add the window
      // before trusting it succeeded.
      await Future.delayed(const Duration(milliseconds: 400));
      final active = await FlutterOverlayWindow.isActive();

      // Also push the payload over the in-memory channel: the overlay's disk
      // read has proven fragile on some ROMs. Retried because the overlay
      // engine registers its listener asynchronously and an early send is
      // dropped; the card de-duplicates by offer id.
      if (active) {
        for (var attempt = 0; attempt < 4; attempt++) {
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          try {
            await FlutterOverlayWindow.shareData(encoded);
          } catch (_) {
            // Engine not ready yet — next attempt.
          }
        }
      }
      return active;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAppWithOrder(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingOrderPrefsKey, jsonEncode(data));
    await reopenApp();
  }

  static Future<void> close() async {
    if (!Platform.isAndroid) return;
    await _closeWindow();
  }

  /// Closes the card if it is showing [orderId] — used when another rider
  /// accepted first.
  ///
  /// If the stored payload is for a DIFFERENT offer the window is left alone: a
  /// newer offer has already replaced this one in place, and closing would
  /// throw away a live offer.
  static Future<void> closeForOrder(String orderId) async {
    if (!Platform.isAndroid) return;

    final prefs = await _freshPrefs();
    final raw = prefs.getString(_overlayOfferPrefsKey);
    if (raw != null) {
      try {
        final pendingId = _offerIdOf(jsonDecode(raw) as Map);
        if (pendingId != null && pendingId != orderId) return;
      } catch (_) {
        // Unreadable payload — treat as ours and clear it.
      }
      await prefs.remove(_overlayOfferPrefsKey);
    }

    await close();
  }

  static Future<Map<String, dynamic>?> consumePendingOrder() async {
    final prefs = await _freshPrefs();
    final raw = prefs.getString(_pendingOrderPrefsKey);
    if (raw == null) return null;
    await prefs.remove(_pendingOrderPrefsKey);
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> reopenApp() async {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: _applicationId,
      componentName: '$_applicationId.MainActivity',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
    );
    await intent.launch();
  }
}

/// Closes the window if it is up.
///
/// Bounded: the plugin never answers `closeOverlay` when the service is
/// already gone (the native side may have just closed it), and an unanswered
/// await would wedge whoever called this.
Future<void> _closeWindow() async {
  try {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay()
          .timeout(const Duration(seconds: 2));
    }
  } catch (_) {}
}

/// Sends one of the card's actions to OfferActionReceiver.kt.
///
/// The receiver takes the payload from what OfferOverlay.kt holds; the type
/// travels too so a ride is never answered as a food order if that is gone.
Future<void> _sendOfferAction(String action, String offerId, {String? type}) {
  return AndroidIntent(
    action: 'com.delivery.jhatpat.OFFER_$action',
    package: _applicationId,
    componentName: _actionReceiver,
    arguments: <String, dynamic>{
      'fsi_order_id': offerId,
      if (type != null && type.isNotEmpty) 'fsi_type': type,
    },
  ).sendBroadcast();
}

class OrderBubbleApp extends StatelessWidget {
  const OrderBubbleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Same design size as the main app, so the shared offer card measures the
    // same in this engine as it does in-app — but scaled against the PHONE's
    // screen, not this window. ScreenUtilInit reads the window, and the window
    // is shrunk to the card: every .h then shrank with it, the card was
    // re-measured shorter, the window shrank again, and the card ended up cut
    // off at the bottom.
    final display = WidgetsBinding.instance.platformDispatcher.displays.first;
    final view = View.of(context);
    ScreenUtil.configure(
      data: MediaQueryData.fromView(view).copyWith(
        size: display.size / display.devicePixelRatio,
      ),
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
    );
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: _OrderOverlayUI(),
    );
  }
}

/// Chrome for the overlay's loading state.
///
/// Keeps the placeholder anchored below the real status bar / notch inset,
/// with everything under it transparent and dismissing on tap so it never
/// becomes a screen-blocker.
class _OverlayShell extends StatelessWidget {
  const _OverlayShell({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Material(
      color: Colors.transparent,
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, topInset + 48, 16, 0),
            child: child,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderOverlayUI extends StatefulWidget {
  const _OrderOverlayUI();

  @override
  State<_OrderOverlayUI> createState() => _OrderOverlayUIState();
}

/// The over-other-apps offer, drawn with the same [OfferRequestView] as the
/// in-app offer screens so the rider sees one design everywhere.
///
/// The engine behind this is cached by the plugin and outlives the window, so
/// this state survives between offers: every offer goes through [_show], and
/// every close through [_reset].
class _OrderOverlayUIState extends State<_OrderOverlayUI>
    with WidgetsBindingObserver {
  // The card is a popup at the top, not a full-screen sheet: once it has
  // laid out, the window is shrunk to it and moved up. The native side opens
  // the window full-size and centred (the plugin's defaults), so both the
  // size and the offset are set from here.
  final GlobalKey _cardKey = GlobalKey();
  double? _windowHeight;

  void _fitWindowToCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.hasSize) return;
      final height = (box.size.height + 28).clamp(120.0, 520.0).ceilToDouble(); // + margins/shadow
      if (_windowHeight == height) return;
      _windowHeight = height;
      final display = WidgetsBinding.instance.platformDispatcher.displays.first;
      final screenHeight = display.size.height / display.devicePixelRatio;
      // Centre gravity: y is the offset of the window centre from the
      // screen centre. Place the top just under the status bar.
      const top = 32.0;
      final y = top + height / 2 - screenHeight / 2;
      await FlutterOverlayWindow.resizeOverlay(-1, height.toInt(), false);
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(0, y));
    });
  }

  Map<String, dynamic>? _orderData;

  /// The ride as the API knows it — the push carries only ids.
  TaxiRide? _ride;

  /// FCM data values are always Strings, so parse rather than cast.
  static double _num(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().trim() ?? '') ?? 0.0;
  }

  static String? _str(Object? v) {
    final text = v?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static bool _isRide(Map<String, dynamic> data) =>
      data['type']?.toString() == 'ride_request';

  final ValueNotifier<int> _secondsLeft = ValueNotifier<int>(60);
  int _totalSeconds = 60;
  Timer? _countdownTimer;
  Timer? _failsafeTimer;
  Timer? _watchdog;
  bool _closing = false;
  bool _loading = false;
  bool _submitting = false;
  bool _soundOn = true;

  /// True only for the Dart-fallback card, which has no notification ringing
  /// for it (see [OrderOverlayService.selfRingingKey]).
  bool _selfRinging = false;

  /// Never cancelled: the plugin's listener stream is single-subscription, so
  /// a cancelled subscription could not be replaced for the next offer.
  StreamSubscription<dynamic>? _dataSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _dataSub = FlutterOverlayWindow.overlayListener.listen((event) {
      try {
        final decoded = event is Map ? event : jsonDecode(event.toString());
        if (decoded is! Map || !mounted) return;
        // The native side closed the window: drop this offer's state.
        if (decoded['overlayCommand'] == 'close') {
          _reset();
          return;
        }
        final map = Map<String, dynamic>.from(decoded);
        // Sends are retried to beat the race with this listener registering,
        // so the same offer arrives more than once. Re-applying it would reset
        // the countdown; only a genuinely different offer does.
        final incomingId = _offerIdOf(map);
        if (incomingId != null && incomingId == _offerIdOf(_orderData)) return;
        _show(map);
      } catch (e) {
        debugPrint('[Overlay] Ignoring unreadable shared data: $e');
      }
    });

    _armWatchdog();
    _loadOrder();
  }

  /// A new window attaching to this cached engine changes the view metrics —
  /// the one signal this side gets that the card was opened again.
  @override
  void didChangeMetrics() {
    if (_orderData == null && !_loading) {
      _armWatchdog();
      _loadOrder();
    }
  }

  /// Closes a window that never got an offer to show, so it cannot sit on the
  /// screen as an empty loading card.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 5), () {
      if (_orderData == null) {
        debugPrint('[Overlay] Nothing rendered within 5s — closing.');
        _forceClose();
      }
    });
  }

  Future<void> _loadOrder({int attempt = 0}) async {
    _loading = true;
    try {
      // _freshPrefs, not getInstance(): the latter is a per-isolate snapshot
      // that never re-reads, so a reused overlay engine would miss the write.
      final prefs = await _freshPrefs();
      final raw = prefs.getString(_overlayOfferPrefsKey);
      if (raw == null) {
        if (attempt < 5 && mounted && _orderData == null) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted && _orderData == null) await _loadOrder(attempt: attempt + 1);
        }
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map || !mounted) return;
      final map = Map<String, dynamic>.from(decoded);
      final incomingId = _offerIdOf(map);
      // Already on screen from the in-memory channel.
      if (incomingId != null && incomingId == _offerIdOf(_orderData)) return;
      _show(map);
    } catch (e) {
      debugPrint('[Overlay] Could not read the offer: $e');
    } finally {
      if (attempt == 0) _loading = false;
    }
  }

  void _show(Map<String, dynamic> data) {
    final isRide = _isRide(data);
    final expiresIn = _num(data['expiresInSec'] ?? data['expiresInSeconds']);
    _watchdog?.cancel();
    _failsafeTimer?.cancel();
    // Outlives the longest accept window the card will count down.
    _failsafeTimer = Timer(const Duration(seconds: 330), _forceClose);
    setState(() {
      _orderData = data;
      _ride = null;
      _submitting = false;
      _soundOn = true;
      _selfRinging = data[OrderOverlayService.selfRingingKey]?.toString() == 'true';
      // Same windows as the native alert: a sent one wins, else 60s for food
      // (what the push promises) and 45s for rides.
      _totalSeconds =
          expiresIn > 0 ? expiresIn.round().clamp(1, 300) : (isRide ? 45 : 60);
    });
    _secondsLeft.value = _totalSeconds;
    _startCountdown();
    if (isRide) {
      _hydrateRide(_offerIdOf(data));
    } else {
      // Renew the mirrored token now, so the native Accept/Reject
      // (OrderResponder.kt reads the same mirror) has a valid one.
      unawaited(_overlayAccessToken());
    }
  }

  /// The ride push carries no fare or addresses; the in-app screen fetches the
  /// ride, and so does this, with the credentials mirrored for native code.
  Future<void> _hydrateRide(String? rideId) async {
    if (rideId == null || rideId.isEmpty) return;
    final ride = await _fetchRide(rideId);
    if (!mounted || ride == null || _offerIdOf(_orderData) != rideId) return;
    if (ride.stage != RideStage.searching) {
      // Someone else took it, or the passenger cancelled.
      _dismissNatively(rideId);
      _forceClose();
      return;
    }
    setState(() => _ride = ride);
  }

  static Future<TaxiRide?> _fetchRide(String rideId, {bool retried = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final prefs = await _freshPrefs();
      final token = await _overlayAccessToken(force: retried);
      final host = prefs.getString('native_api_base_url');
      if (token == null || token.isEmpty || host == null || host.isEmpty) {
        return null;
      }
      final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
      final request =
          await client.getUrl(Uri.parse('$base${ApiEndpoints.rideById(rideId)}'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 && !retried) {
        client.close(force: true);
        return await _fetchRide(rideId, retried: true);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      dynamic decoded = jsonDecode(body);
      if (decoded is Map && decoded.containsKey('data')) decoded = decoded['data'];
      if (decoded is Map && decoded['ride'] is Map) decoded = decoded['ride'];
      if (decoded is! Map) return null;
      return TaxiRide.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('[Overlay] Ride fetch failed for $rideId: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_selfRinging && _soundOn) SoundService.playRingtone();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft.value <= 1) {
        timer.cancel();
        // Expired: take the ringing notification down with the card.
        final id = _offerIdOf(_orderData);
        if (id != null) _dismissNatively(id);
        _forceClose();
      } else {
        _secondsLeft.value--;
      }
    });
  }

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    if (_selfRinging) {
      if (_soundOn && !_submitting) {
        SoundService.playRingtone();
      } else {
        SoundService.stopRingtone();
      }
      return;
    }
    // The notification is what rings: re-post it silently or loudly.
    final id = _offerIdOf(_orderData);
    if (id == null) return;
    _sendOfferAction(_soundOn ? 'UNMUTE' : 'MUTE', id).catchError((Object e) {
      debugPrint('[Overlay] Sound toggle failed: $e');
    });
  }

  void _dismissNatively(String id) {
    if (_selfRinging) return;
    _sendOfferAction('DISMISS', id).catchError((Object _) {});
  }

  /// Drops the current offer's state without touching the window.
  void _reset() {
    // The next offer opens in a fresh full-size window: fit it again.
    _windowHeight = null;
    _countdownTimer?.cancel();
    _failsafeTimer?.cancel();
    _watchdog?.cancel();
    if (_selfRinging) SoundService.stopRingtone();
    if (!mounted) return;
    setState(() {
      _orderData = null;
      _ride = null;
      _submitting = false;
      _selfRinging = false;
    });
  }

  Future<void> _forceClose() async {
    if (_closing) return;
    _closing = true;
    try {
      _reset();
      await SoundService.stopRingtone();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_overlayOfferPrefsKey);
      await _closeWindow();
    } catch (_) {
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _failsafeTimer?.cancel();
    _watchdog?.cancel();
    _dataSub?.cancel();
    _secondsLeft.dispose();
    SoundService.stopRingtone();
    super.dispose();
  }

  /// Accept goes through the same native code as the notification's Accept
  /// (OfferActionReceiver → IncomingOrderActivity): one accept-once guard
  /// across every surface, the food accept sent at once, the ride claimed by
  /// the app over the socket, and the app opened on the job.
  Future<void> _accept() async {
    if (_submitting) return;
    final data = _orderData;
    final id = _offerIdOf(data);
    setState(() => _submitting = true);
    _countdownTimer?.cancel();
    await SoundService.stopRingtone();

    if (id != null && id.isNotEmpty) {
      try {
        await _sendOfferAction('ACCEPT', id, type: data?['type']?.toString());
      } catch (e) {
        debugPrint('[Overlay] Native accept failed, handing to the app: $e');
        // Last resort, food only: main.dart sends it once on resume.
        if (data != null && !_isRide(data)) {
          await OrderOverlayService.openAppWithOrder({...data, 'autoAccept': true});
        } else {
          await OrderOverlayService.reopenApp();
        }
      }
    }
    await _forceClose();
  }

  /// Declines without opening the app, through the notification's own Reject
  /// path (food: reject API; ride: no REST reject, so it lapses on dispatch's
  /// timer).
  Future<void> _reject() async {
    if (_submitting) return;
    final data = _orderData;
    final id = _offerIdOf(data);
    setState(() => _submitting = true);
    _countdownTimer?.cancel();
    await SoundService.stopRingtone();
    if (id != null && id.isNotEmpty) {
      try {
        await _sendOfferAction('REJECT', id, type: data?['type']?.toString());
      } catch (e) {
        debugPrint('[Overlay] Native reject failed: $e');
        if (data != null && !_isRide(data)) await _rejectOverNetwork(id);
      }
    }
    await _forceClose();
  }

  /// Same call and credentials as `OrderResponder.kt`. Best effort: dispatch's
  /// own timeout reassigns the order if this never lands.
  static Future<void> _rejectOverNetwork(String orderId) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final prefs = await _freshPrefs();
      final token = await _overlayAccessToken();
      final host = prefs.getString('native_api_base_url');
      if (token == null || token.isEmpty || host == null || host.isEmpty) return;
      final base = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
      final request = await client.openUrl(
        'PATCH',
        Uri.parse('$base${ApiEndpoints.orderReject(orderId)}'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
    } catch (e) {
      debugPrint('[Overlay] Reject failed for $orderId: $e');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // NEVER return an empty widget here.
    //
    // The window is already attached by the time build runs. Returning
    // SizedBox.shrink() leaves a full-height window with nothing drawn in it and
    // no way for the rider to get rid of it — the original home-screen freeze.
    final data = _orderData;
    if (data == null) {
      return _OverlayShell(
        onDismiss: _forceClose,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'New job incoming…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    _fitWindowToCard();
    return _isRide(data) ? _buildRide(data) : _buildFood(data);
  }

  Widget _buildFood(Map<String, dynamic> data) {
    // This map came from an FCM push, where EVERY value is a String — parse,
    // never cast. Only real figures are shown; a missing one hides its line.
    final fare = [
      data['earningAmount'],
      data['riderEarning'],
      data['earnings'],
      data['price'],
    ].map(_num).firstWhere((v) => v > 0, orElse: () => 0);

    // Rider-to-restaurant distance is per-rider, so it only rides on the socket
    // payload — one FCM message is built for the whole broadcast.
    final pickupKm = _num(data['pickupDistanceKm']);
    final tripKm = _num(data['tripDistanceKm'] ?? data['distance']);
    final tripMins = _num(data['tripDurationMins']);

    final restaurantName = _str(data['restaurantName']);
    final pickupAddr =
        _str(data['restaurantAddress']) ?? _str(data['pickupAddress']) ?? '';
    final pickup = restaurantName != null
        ? OfferStop(name: restaurantName, detail: pickupAddr)
        : OfferStop.fromAddress(pickupAddr.isEmpty ? 'Pickup location' : pickupAddr);

    final dropAddr = _str(data['dropAddress']) ?? _str(data['customerAddress']);
    final drop = dropAddr != null
        ? OfferStop.fromAddress(dropAddr)
        : OfferStop(name: _str(data['customerName']) ?? 'Drop location');

    return OfferRequestView(
      compact: true,
      cardKey: _cardKey,
      secondsLeft: _secondsLeft,
      totalSeconds: _totalSeconds,
      fare: fare > 0 ? fare : null,
      bonus: _num(data['bonus'] ?? data['incentive']),
      jobLabel: 'Food delivery',
      jobIcon: Icons.delivery_dining_rounded,
      pickup: OfferStop(
        name: pickup.name,
        detail: pickup.detail,
        distance: pickupKm > 0 ? '${pickupKm.toStringAsFixed(1)} km' : null,
        duration: pickupKm > 0 ? '(${OfferRequestView.minsForKm(pickupKm)} mins)' : null,
      ),
      drop: OfferStop(
        name: drop.name,
        detail: drop.detail,
        distance: tripKm > 0 ? '${tripKm.toStringAsFixed(1)} km' : null,
        duration: tripMins > 0 ? '(${tripMins.toStringAsFixed(0)} mins)' : null,
      ),
      soundOn: _soundOn,
      onToggleSound: _toggleSound,
      resolving: _submitting,
      onAccept: _accept,
      onDecline: _reject,
    );
  }

  /// Laid out like IncomingRideScreen. Until the ride is fetched, the push's
  /// own text stands in ("Pickup: <address>" is its notification body).
  Widget _buildRide(Map<String, dynamic> data) {
    final ride = _ride;
    final kind = (data['serviceType'] ?? '').toString().trim().toLowerCase();
    final isParcel = ride?.isParcel ?? (kind == 'parcel' || kind == 'delivery');

    final pushBody = _str(data['gcm.notification.body']) ?? _str(data['gcm.n.body']);
    final pickupAddr = (ride != null && ride.pickupAddress.isNotEmpty)
        ? ride.pickupAddress
        : _str(data['pickupAddress']) ??
            (pushBody != null && pushBody.startsWith('Pickup:')
                ? pushBody.substring('Pickup:'.length).trim()
                : 'Pickup location');
    final dropAddr = (ride != null && ride.dropAddress.isNotEmpty)
        ? ride.dropAddress
        : _str(data['dropAddress']) ?? 'Drop location';

    final fare = ride?.fare ?? _num(data['fare'] ?? data['earnings'] ?? data['price']);

    return OfferRequestView(
      compact: true,
      cardKey: _cardKey,
      secondsLeft: _secondsLeft,
      totalSeconds: _totalSeconds,
      fare: fare > 0 ? fare : null,
      bonus: ride?.bonus ?? _num(data['bonus'] ?? data['incentive']),
      jobLabel: ride != null ? RideJobKind.labelOf(ride) : (isParcel ? 'Parcel' : 'Ride'),
      jobIcon: ride != null
          ? RideJobKind.iconOf(ride)
          : (isParcel ? Icons.inventory_2_rounded : Icons.directions_car_rounded),
      banner: ride != null ? DriveUJobBanner(ride: ride) : null,
      paymentNote: ride == null ? null : (ride.isCash ? 'Collect cash' : 'Paid online'),
      paymentNoteColor:
          ride == null ? null : (ride.isCash ? const Color(0xFFB7791F) : kOfferGreen),
      pickup: OfferStop.fromAddress(pickupAddr),
      drop: OfferStop.fromAddress(
        dropAddr,
        distance: ride != null && ride.distanceMeters > 0
            ? '${ride.distanceKm.toStringAsFixed(1)} km'
            : null,
        duration: ride != null && ride.durationMinutes > 0
            ? '(${ride.durationMinutes} mins)'
            : null,
      ),
      soundOn: _soundOn,
      onToggleSound: _toggleSound,
      resolving: _submitting,
      onAccept: _accept,
      onDecline: _reject,
    );
  }
}
