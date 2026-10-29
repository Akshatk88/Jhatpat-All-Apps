import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'work_mode.dart';

/// Remembers which modules the rider switched on.
///
/// Needed because the server stores `taxi` for both Parcel delivery and Rider;
/// without this an app restart could not tell which of the two are on. The
/// server remains the authority for food vs taxi.
///
/// It is also the **native side's copy of the modules**. The offer alert is
/// raised by Kotlin (`IncomingOrderReceiver` → `OfferOverlay.belongsToModule`)
/// straight off the FCM broadcast, before any Dart runs, and it reads this
/// value from the `FlutterSharedPreferences` file as `flutter.work_module`. So
/// [WorkModeController] writes the set it is actually in — every load and
/// every switch — and the format here (`work_module` = comma-separated
/// `food,parcel,rider`) must not change without the Kotlin side.
class WorkModePreferenceStore {
  static const _key = 'work_module';

  Future<WorkModeSet?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return WorkModeSet.decode(prefs.getString(_key));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WorkModeSet modes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, modes.encode());
    } catch (_) {
      // A lost preference only means falling back to the capability default.
    }
  }
}

final workModePreferenceStoreProvider = Provider<WorkModePreferenceStore>(
  (ref) => WorkModePreferenceStore(),
);
