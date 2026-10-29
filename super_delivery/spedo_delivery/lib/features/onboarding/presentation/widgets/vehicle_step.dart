import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/registration_draft.dart';
import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import 'onboarding_ui.dart';
import 'service_step.dart' show classIcon;

/// Step 3 — the vehicle, from the catalogue filtered to the partner's answer.
class VehicleStep extends ConsumerWidget {
  const VehicleStep({
    super.key,
    required this.formKey,
    required this.requirements,
    required this.vehicleName,
    required this.vehicleNumber,
    required this.showErrors,
    required this.onRetry,
  });

  final GlobalKey<FormState> formKey;
  final AsyncValue<OnboardingRequirements> requirements;
  final TextEditingController vehicleName;
  final TextEditingController vehicleNumber;
  final bool showErrors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(registrationWizardProvider);
    final controller = ref.read(registrationWizardProvider.notifier);

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(
            title: 'Your vehicle',
            subtitle: 'Choose the type that matches the vehicle you will use.',
          ),
          requirements.when(
            loading: () =>
                const LoadStateView.loading(label: 'Loading vehicle types…'),
            error: (e, _) => LoadStateView.error(
              message: e is OnboardingLoadException
                  ? e.message
                  : 'Could not load vehicle types.',
              onRetry: onRetry,
            ),
            data: (req) {
              if (req.vehicleTypes.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ErrorBanner(
                      'No vehicle types are available for this choice yet. '
                      'Go back and pick a different option, or contact support.',
                    ),
                    SizedBox(height: 8.h),
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check again'),
                    ),
                  ],
                );
              }
              return LayoutBuilder(
                builder: (context, c) {
                  final columns = c.maxWidth >= 520 ? 3 : 2;
                  final spacing = 10.w;
                  final width =
                      (c.maxWidth - spacing * (columns - 1)) / columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final v in req.vehicleTypes)
                        SizedBox(
                          width: width,
                          child: _VehicleCard(
                            vehicle: v,
                            driverClass: draft.driverClass,
                            selected: draft.vehicleTypeId == v.id,
                            onTap: () => controller.selectVehicleType(v),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          if (showErrors &&
              draft.vehicleTypeId.isEmpty &&
              (requirements.value?.vehicleTypes.isNotEmpty ?? false)) ...[
            SizedBox(height: 10.h),
            const ErrorBanner('Select your vehicle type.'),
          ],
          SizedBox(height: 20.h),
          const SectionLabel('Vehicle details'),
          TextFormField(
            controller: vehicleName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: onboardingInputDecoration(
              context,
              label: 'Vehicle name / model (optional)',
              hint: 'e.g. Honda Activa 6G',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            onChanged: controller.setVehicleName,
          ),
          SizedBox(height: 12.h),
          TextFormField(
            controller: vehicleNumber,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 \-]')),
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: onboardingInputDecoration(
              context,
              label: 'Vehicle number *',
              hint: 'e.g. MP04AB1234',
              prefixIcon: const Icon(Icons.pin_outlined),
              suffixIcon: _CheckIndicator(check: draft.vehicleCheck),
            ),
            onChanged: controller.setVehicleNumber,
            onFieldSubmitted: (_) => controller.checkVehicleNumber(),
            validator: (v) {
              final n = normalizeVehicleNumber(v ?? '');
              if (n.isEmpty) return 'Enter your vehicle number';
              if (!isPlausibleVehicleNumber(n)) {
                return 'Enter a valid registration number';
              }
              final check = draft.vehicleCheck;
              if (check.number == n &&
                  check.status == VehicleCheckStatus.taken) {
                return check.message.isNotEmpty
                    ? check.message
                    : 'Vehicle number already registered';
              }
              return null;
            },
          ),
          _CheckMessage(
            check: draft.vehicleCheck,
            current: normalizeVehicleNumber(draft.vehicleNumber),
            // Once the form has been validated the field's own error text
            // already says "taken" — do not say it twice.
            hideTaken: showErrors,
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.driverClass,
    required this.selected,
    required this.onTap,
  });

  final OnboardingVehicleType vehicle;
  final String driverClass;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: vehicle.name,
      child: Material(
        color: selected
            ? OnboardingColors.brand.withValues(alpha: 0.12)
            : OnboardingColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
          side: BorderSide(
            color: selected
                ? OnboardingColors.brand
                : OnboardingColors.border(context),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        color: OnboardingColors.brand.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: MediaImage(
                        url: vehicle.image,
                        fallback: classIcon(driverClass),
                        size: 40.w,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 20.sp,
                      color: selected
                          ? OnboardingColors.onBrand
                          : OnboardingColors.muted(context),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Text(
                  vehicle.name.isEmpty ? 'Vehicle' : vehicle.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: OnboardingColors.text(context),
                  ),
                ),
                if (vehicle.capacity > 0)
                  Text(
                    'Capacity ${vehicle.capacity}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: OnboardingColors.muted(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckIndicator extends StatelessWidget {
  const _CheckIndicator({required this.check});
  final VehicleCheck check;

  @override
  Widget build(BuildContext context) {
    return switch (check.status) {
      VehicleCheckStatus.checking => const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: OnboardingColors.brand,
          ),
        ),
      ),
      VehicleCheckStatus.available => const Icon(
        Icons.check_circle_rounded,
        color: OnboardingColors.success,
      ),
      VehicleCheckStatus.taken => const Icon(
        Icons.error_rounded,
        color: OnboardingColors.error,
      ),
      VehicleCheckStatus.failed => Icon(
        Icons.wifi_off_rounded,
        color: OnboardingColors.muted(context),
      ),
      VehicleCheckStatus.idle => const SizedBox.shrink(),
    };
  }
}

class _CheckMessage extends StatelessWidget {
  const _CheckMessage({
    required this.check,
    required this.current,
    required this.hideTaken,
  });
  final VehicleCheck check;
  final String current;
  final bool hideTaken;

  @override
  Widget build(BuildContext context) {
    if (check.number != current) return const SizedBox.shrink();
    if (hideTaken && check.status == VehicleCheckStatus.taken) {
      return const SizedBox.shrink();
    }
    final (String text, Color color) = switch (check.status) {
      VehicleCheckStatus.available => (
        'Available to register',
        OnboardingColors.success,
      ),
      VehicleCheckStatus.taken => (
        check.message.isNotEmpty
            ? check.message
            : 'Vehicle number already registered',
        OnboardingColors.error,
      ),
      VehicleCheckStatus.failed => (
        "Couldn't check this number: ${check.message}",
        OnboardingColors.muted(context),
      ),
      VehicleCheckStatus.checking => (
        'Checking availability…',
        OnboardingColors.muted(context),
      ),
      VehicleCheckStatus.idle => ('', Colors.transparent),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 6.h, left: 4.w),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5.sp, color: color),
      ),
    );
  }
}
