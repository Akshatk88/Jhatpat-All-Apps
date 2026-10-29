import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks booking/order confirmations aloud in Hindi.
///
/// One engine for the whole app so a new announcement always cuts off the
/// previous one. Every call is guarded — a device without a TTS engine (or
/// without the Hindi voice) must never break the screen that asked to speak.
class HindiAnnouncer {
  HindiAnnouncer._();
  static final HindiAnnouncer instance = HindiAnnouncer._();

  final FlutterTts _tts = FlutterTts();
  Future<void>? _setup;
  int _generation = 0;

  /// True while an announcement is playing — drives the "Suniye"/"Stop" pill.
  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);

  Future<void> _ensureSetup() => _setup ??= _configure();

  Future<void> _configure() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      // Always Hindi: the announcements are written in Devanagari, which an
      // English voice cannot read (it goes silent). Google's TTS engine ships
      // Hindi on Android and downloads the voice on first use if missing.
      await _tts.setLanguage('hi-IN');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      _tts.setErrorHandler((message) {
        developer.log('[TTS] error: $message', name: 'TTS');
        isSpeaking.value = false;
      });
    } catch (e) {
      developer.log('[TTS] setup failed: $e', name: 'TTS');
    }
  }

  /// Stops anything already playing, then speaks [text]. Never throws.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final generation = ++_generation;
    try {
      await _ensureSetup();
      await _tts.stop();
      if (generation != _generation) return;
      isSpeaking.value = true;
      await _tts.speak(text);
    } catch (e) {
      developer.log('[TTS] speak failed: $e', name: 'TTS');
    } finally {
      if (generation == _generation) isSpeaking.value = false;
    }
  }

  /// Stops the current announcement, if any. Never throws.
  Future<void> stop() async {
    _generation++;
    isSpeaking.value = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Only auto-announce while the app is actually in front of the user.
  static bool get appInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// "120 rupaye" / "120 rupaye 50 paise".
  static String rupees(num amount) {
    final paise = (amount * 100).round();
    final whole = paise ~/ 100;
    final rest = paise % 100;
    return rest == 0 ? '$whole रुपये' : '$whole रुपये $rest पैसे';
  }

  /// "2.3 kilometer".
  static String kilometers(num km) => '${km.toStringAsFixed(1)} किलोमीटर';

  /// Drops 6-digit pincodes, which TTS reads out as one long number.
  static String address(String raw) => raw
      .replaceAll(RegExp(r'[\s,-]*\b\d{6}\b'), '')
      .replaceAll(RegExp(r'\s*,\s*,'), ',')
      .trim()
      .replaceAll(RegExp(r'[,\s]+$'), '');
}
