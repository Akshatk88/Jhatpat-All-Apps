import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:superapp_user/shared/session/presentation/system/presentation/widgets/system_status_view.dart';

class ServerErrorScreen extends StatelessWidget {
  final VoidCallback? onRetry;

  const ServerErrorScreen({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SystemStatusView(
      icon: Icons.cloud_off_rounded,
      title: 'Something went wrong'.tr,
      message: "Our servers are taking a bit longer than usual to respond. Please try again in a moment.".tr,
      primaryActionLabel: 'Retry'.tr,
      onPrimaryAction: onRetry ?? () => Navigator.of(context).maybePop(),
    );
  }
}
