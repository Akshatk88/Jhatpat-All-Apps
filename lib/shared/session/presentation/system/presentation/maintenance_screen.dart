import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:superapp_user/shared/session/presentation/system/presentation/widgets/system_status_view.dart';

class MaintenanceScreen extends StatelessWidget {
  final VoidCallback? onRetry;

  const MaintenanceScreen({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SystemStatusView(
      icon: Icons.build_circle_outlined,
      title: 'Under maintenance'.tr,
      message: "We're currently performing scheduled maintenance to improve your experience. Please check back shortly.".tr,
      primaryActionLabel: 'Try again'.tr,
      onPrimaryAction: onRetry ?? () => Navigator.of(context).maybePop(),
    );
  }
}
