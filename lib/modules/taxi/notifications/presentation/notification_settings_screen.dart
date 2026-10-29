import 'package:superapp_user/core/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:superapp_user/design_system/components/ride/custom_app_bar.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class _NotificationPrefKeys {
  static const rideUpdates = 'notif_pref_ride_updates';
  static const promotions = 'notif_pref_promotions';
  static const walletAlerts = 'notif_pref_wallet_alerts';
}

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  late Box _settings;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(localStorageServiceProvider).settings;
  }

  bool _get(String key) => _settings.get(key, defaultValue: true) as bool;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Notification settings'.tr),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Ride updates'.tr),
            subtitle: Text('Driver arrival, trip status and OTP alerts'.tr),
            value: _get(_NotificationPrefKeys.rideUpdates),
            onChanged: (v) => setState(() => _settings.put(_NotificationPrefKeys.rideUpdates, v)),
          ),
          SwitchListTile(
            title: Text('Promotions & offers'.tr),
            subtitle: Text('New promo codes and discounts'.tr),
            value: _get(_NotificationPrefKeys.promotions),
            onChanged: (v) => setState(() => _settings.put(_NotificationPrefKeys.promotions, v)),
          ),
          SwitchListTile(
            title: Text('Wallet alerts'.tr),
            subtitle: Text('Top-ups, payments and refunds'.tr),
            value: _get(_NotificationPrefKeys.walletAlerts),
            onChanged: (v) => setState(() => _settings.put(_NotificationPrefKeys.walletAlerts, v)),
          ),
        ],
      ),
    );
  }
}
