import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/core/services/incoming_alert_channel.dart';
import 'package:food_user_application/core/services/sound_service.dart';

/// Keeps an in-app offer screen ringing until the offer is answered, expires,
/// is withdrawn, or the rider mutes it.
///
/// The one exception is the app sitting in the background while the native
/// alert (notification + lock-screen card) is ringing for the same offer — two
/// copies of the tone slightly out of step is worse than one. Coming back to
/// the app takes the native alert down and the in-app ring resumes.
mixin OfferRinging<T extends StatefulWidget> on State<T> {
  bool soundOn = true;
  bool _ringStopped = false;
  bool _inForeground = true;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<String>? _nativeShownSub;
  StreamSubscription<Map<String, String>>? _resolvedSub;

  /// The offer this screen is ringing for.
  String get ringingOfferId;

  void startRinging() {
    final state = WidgetsBinding.instance.lifecycleState;
    _inForeground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _nativeShownSub = IncomingAlertChannel.nativeAlertShown.listen((id) {
      if (id == ringingOfferId) _applyRing();
    });
    _resolvedSub = IncomingAlertChannel.nativelyResolved.listen((event) {
      if (event['orderId'] == ringingOfferId) stopRinging();
    });
    _applyRing();
  }

  void _onLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _inForeground) return;
    _inForeground = foreground;
    if (foreground && IncomingAlertChannel.hasNativeAlert(ringingOfferId)) {
      // Back in the app: the in-app card is the one alert from here.
      unawaited(IncomingAlertChannel.dismiss(ringingOfferId));
    }
    _applyRing();
  }

  void _applyRing() {
    final nativeHasIt =
        !_inForeground && IncomingAlertChannel.hasNativeAlert(ringingOfferId);
    final ring = soundOn &&
        !_ringStopped &&
        !nativeHasIt &&
        !IncomingAlertChannel.wasAnsweredNatively(ringingOfferId);
    if (ring) {
      SoundService.playRingtone();
    } else {
      SoundService.stopRingtone();
    }
  }

  /// The sound pill: mutes the ringing only, never the offer.
  void toggleSound() {
    HapticService.light();
    setState(() => soundOn = !soundOn);
    _applyRing();
  }

  /// The offer is being answered or has expired — silence for good.
  void stopRinging() {
    _ringStopped = true;
    SoundService.stopRingtone();
  }

  void disposeRinging() {
    _lifecycle?.dispose();
    _nativeShownSub?.cancel();
    _resolvedSub?.cancel();
    SoundService.stopRingtone();
  }
}
