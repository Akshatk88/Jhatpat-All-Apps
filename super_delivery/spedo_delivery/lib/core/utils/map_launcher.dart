import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn navigation / the dialer.
///
/// `canLaunchUrl` is deliberately NOT used as a gate: on Android 11+ it
/// returns false for any scheme not declared under `<queries>` in the
/// manifest (this app declares only PROCESS_TEXT), which made the Navigate
/// and Call buttons silently do nothing. `launchUrl` itself needs no query
/// declaration — it simply fails when nothing can handle the intent, so each
/// option is tried in turn and the next one used on failure.
class MapLauncher {
  static Future<bool> launchGoogleMaps(double lat, double lng) async {
    final candidates = <Uri>[
      if (Platform.isAndroid) Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      if (Platform.isIOS)
        Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
      ),
      if (Platform.isAndroid) Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
      if (Platform.isIOS) Uri.parse('maps://?daddr=$lat,$lng&dirflg=d'),
    ];

    for (final uri in candidates) {
      if (await _tryLaunch(uri)) return true;
    }
    return false;
  }

  /// Opens the dialer with [phone] filled in. Returns false when nothing could
  /// handle it (or there is no number).
  static Future<bool> dial(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return false;
    return _tryLaunch(Uri(scheme: 'tel', path: digits));
  }

  static Future<bool> _tryLaunch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
