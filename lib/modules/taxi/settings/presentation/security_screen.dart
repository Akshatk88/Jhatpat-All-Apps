import 'package:superapp_user/core/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/design_system/components/ride/custom_app_bar.dart';
import 'package:superapp_user/core/i18n/tr.dart';

const _appLockKey = 'security_app_lock_enabled';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _appLock = false;

  @override
  void initState() {
    super.initState();
    _appLock = ref.read(localStorageServiceProvider).settings.get(_appLockKey, defaultValue: false) as bool;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Security'.tr),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('App lock'.tr),
            subtitle: Text('Ask for confirmation before opening the app'.tr),
            value: _appLock,
            onChanged: (v) {
              setState(() => _appLock = v);
              ref.read(localStorageServiceProvider).settings.put(_appLockKey, v);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text('Emergency contacts'.tr),
            subtitle: Text('Manage who is alerted during SOS'.tr),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/taxi/emergency-contacts'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.phonelink_lock_outlined),
            title: Text('Active session'.tr),
            subtitle: Text('You are signed in on this device via phone number verification'.tr),
          ),
        ],
      ),
    );
  }
}
