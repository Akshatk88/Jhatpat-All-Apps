import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/shared/session/presentation/system/presentation/widgets/system_status_view.dart';

/// Store URLs must be supplied once the app is published under a real bundle id.
const String _androidStoreUrl = '';
const String _iosStoreUrl = '';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  Future<void> _openStore(BuildContext context) async {
    final url = Theme.of(context).platform == TargetPlatform.iOS ? _iosStoreUrl : _androidStoreUrl;
    if (url.isEmpty) {
      SnackbarUtils.error(context, 'App store link is not configured yet'.tr);
      return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: SystemStatusView(
        icon: Icons.system_update_alt_rounded,
        title: 'Update required'.tr,
        message: 'A new version of the app is available with important fixes and improvements. Please update to continue.'.tr,
        primaryActionLabel: 'Update now'.tr,
        onPrimaryAction: () => _openStore(context),
      ),
    );
  }
}
