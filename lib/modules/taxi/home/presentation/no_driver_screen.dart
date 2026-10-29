import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/design_system/components/ride/empty_state.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_controller.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_state.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class NoDriverScreen extends ConsumerWidget {
  const NoDriverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No drivers available'.tr,
        message: 'We couldn\'t find a driver nearby right now. Please try again in a moment.'.tr,
        actionLabel: 'Try again'.tr,
        onAction: () {
          final controller = ref.read(bookingControllerProvider.notifier);
          controller.goToStep(BookingStep.confirming);
          context.pushReplacement('/taxi/confirm');
        },
      ),
    );
  }
}
