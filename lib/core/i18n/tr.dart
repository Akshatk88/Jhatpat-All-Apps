import 'package:superapp_user/core/i18n/hi_strings.dart';

/// The language the UI is currently drawn in. Kept as a plain static so
/// `'Text'.tr` works anywhere — widgets, view models, snackbars — without a
/// BuildContext. [languageProvider] is the only writer; on a change the app
/// root rebuilds every widget so the new strings appear at once.
class AppLanguage {
  AppLanguage._();

  static String code = 'en';

  static bool get isHindi => code == 'hi';
}

/// UI-string translation.
///
/// English is the key: `Text('Book now'.tr)`. A string with no Hindi entry
/// simply stays English, so a missed string degrades instead of breaking.
/// Only app-authored copy goes through this — data from the backend
/// (restaurant names, dishes, addresses) is shown as-is.
extension TrString on String {
  String get tr {
    if (!AppLanguage.isHindi) return this;
    return hiStrings[this] ?? this;
  }

  /// For copy with values in it: `'{count} items'.trArgs({'count': n})`.
  /// The placeholder names must match between English and Hindi entries.
  String trArgs(Map<String, Object?> args) {
    var out = tr;
    args.forEach((key, value) => out = out.replaceAll('{$key}', '${value ?? ''}'));
    return out;
  }
}
