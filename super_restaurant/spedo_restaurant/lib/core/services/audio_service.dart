import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  return AudioService();
});

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playRefreshSound() async {
    try {
      await _player.play(AssetSource('sound/refersh.mp4'));
    } catch (e) {
      // Ignore errors for sound playback
    }
  }
}

/// The looping new-order ringtone played by the in-app request screen.
///
/// The same `tujh_bin` sound as the new-order notification, looped until the
/// request is accepted, rejected, expires, or the restaurant mutes it. One
/// shared player, so a second request can never stack a second ring on top.
class OrderRingtone {
  OrderRingtone._();

  static AudioPlayer? _player;
  static bool _ringing = false;

  static bool get isRinging => _ringing;

  static Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      // stop() may have been called while the line above was in flight.
      if (!_ringing) return;
      await player.play(AssetSource('sound/tujh_bin.mp3'));
    } catch (_) {
      _ringing = false;
    }
  }

  static Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _player?.stop();
    } catch (_) {
      // Nothing useful to do — the player is reset on the next start().
    }
  }
}
