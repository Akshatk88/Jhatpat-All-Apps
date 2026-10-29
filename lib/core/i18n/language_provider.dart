import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/storage/storage_keys.dart';
import 'package:superapp_user/core/storage/storage_providers.dart';

/// The app language ('en' | 'hi'), persisted in the settings box.
class LocaleNotifier extends Notifier<String> {
  static const _chosenKey = 'language_chosen';

  @override
  String build() {
    final box = ref.read(localStorageServiceProvider).settings;
    final stored = (box.get(StorageKeys.localeCode) as String?) ?? 'en';
    final code = _isSupported(stored) ? stored : 'en';
    AppLanguage.code = code;
    return code;
  }

  static bool _isSupported(String code) =>
      supportedLanguages.any((l) => l['code'] == code);

  void setLocale(String code) {
    if (!_isSupported(code)) return;
    AppLanguage.code = code;
    final box = ref.read(localStorageServiceProvider).settings;
    box.put(StorageKeys.localeCode, code);
    box.put(_chosenKey, true);
    state = code;
  }

  /// Whether the rider has picked a language yet (asked once after login).
  bool get hasChosen =>
      ref.read(localStorageServiceProvider).settings.get(_chosenKey) == true;

  /// Records the current language as chosen without changing it.
  void markChosen() =>
      ref.read(localStorageServiceProvider).settings.put(_chosenKey, true);
}

final localeProvider =
    NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

/// The languages the app is actually translated into.
const supportedLanguages = [
  {'code': 'en', 'label': 'English', 'native': 'English'},
  {'code': 'hi', 'label': 'Hindi', 'native': 'हिन्दी'},
];
