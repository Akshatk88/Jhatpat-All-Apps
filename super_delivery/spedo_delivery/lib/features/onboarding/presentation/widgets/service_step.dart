import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import 'eligibility_checklist.dart';
import 'onboarding_ui.dart';

IconData classIcon(String key) => switch (key) {
  'two_wheeler' => Icons.two_wheeler,
  'passenger_taxi' => Icons.local_taxi,
  'parcel_vehicle' => Icons.local_shipping,
  _ => Icons.directions_car_filled_outlined,
};

/// Step 1 — "What do you want to do?", from `/onboarding/options`.
class ServiceStep extends ConsumerWidget {
  const ServiceStep({super.key, required this.showErrors});

  final bool showErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(onboardingOptionsProvider);
    final draft = ref.watch(registrationWizardProvider);
    final controller = ref.read(registrationWizardProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'What do you want to do?',
          subtitle:
              'Pick the vehicle you have, then the kind of work you want. '
              'This decides which vehicles and documents we ask for.',
        ),
        options.when(
          loading: () =>
              const LoadStateView.loading(label: 'Loading options…'),
          error: (e, _) => LoadStateView.error(
            message: e is OnboardingLoadException
                ? e.message
                : 'Could not load the options.',
            onRetry: () => ref.invalidate(onboardingOptionsProvider),
          ),
          data: (classes) {
            if (classes.isEmpty) {
              return LoadStateView.error(
                message: 'No services are open for sign-up right now.',
                onRetry: () => ref.invalidate(onboardingOptionsProvider),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cls in classes)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: _ClassCard(
                      cls: cls,
                      selected: draft.driverClass == cls.key,
                      selectedIntents: draft.intents,
                      showErrors: showErrors,
                      onSelect: () => controller.selectClass(cls),
                      onToggleIntent: controller.toggleIntent,
                    ),
                  ),
              ],
            );
          },
        ),
        SizedBox(height: 16.h),
        const EligibilityChecklist(),
      ],
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({
    required this.cls,
    required this.selected,
    required this.selectedIntents,
    required this.showErrors,
    required this.onSelect,
    required this.onToggleIntent,
  });

  final OnboardingClass cls;
  final bool selected;
  final List<String> selectedIntents;
  final bool showErrors;
  final VoidCallback onSelect;
  final ValueChanged<String> onToggleIntent;

  @override
  Widget build(BuildContext context) {
    final multi = cls.intents.length > 1;
    final noIntent = selected && cls.intents.isNotEmpty && selectedIntents.isEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? OnboardingColors.brand.withValues(alpha: 0.10)
            : OnboardingColors.card(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: selected
              ? OnboardingColors.brand
              : OnboardingColors.border(context),
          width: selected ? 1.8 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              borderRadius: BorderRadius.circular(14.r),
              onTap: onSelect,
              child: Padding(
                padding: EdgeInsets.all(14.w),
                child: Row(
                  children: [
                    Container(
                      width: 46.w,
                      height: 46.w,
                      decoration: BoxDecoration(
                        color: selected
                            ? OnboardingColors.brand
                            : OnboardingColors.brand.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(
                        classIcon(cls.key),
                        color: OnboardingColors.onBrand,
                        size: 26.sp,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        cls.label,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: OnboardingColors.text(context),
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected
                          ? OnboardingColors.onBrand
                          : OnboardingColors.muted(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected && cls.intents.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    multi
                        ? 'Select all that apply'
                        : 'Included',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: OnboardingColors.muted(context),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      for (final intent in cls.intents)
                        _IntentChip(
                          label: intent.label,
                          selected: selectedIntents.contains(intent.key),
                          onTap: () => onToggleIntent(intent.key),
                        ),
                    ],
                  ),
                  if (showErrors && noIntent) ...[
                    SizedBox(height: 8.h),
                    Text(
                      'Pick at least one option.',
                      style: TextStyle(
                        color: OnboardingColors.error,
                        fontSize: 12.5.sp,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A wrapping selectable chip — long labels break onto a second line instead
/// of overflowing on a 320dp screen.
class _IntentChip extends StatelessWidget {
  const _IntentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? OnboardingColors.brand : OnboardingColors.card(context),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? OnboardingColors.brand
                : OnboardingColors.border(context),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18.sp,
                  color: selected
                      ? OnboardingColors.onBrand
                      : OnboardingColors.muted(context),
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? OnboardingColors.onBrand
                          : OnboardingColors.text(context),
                    ),
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
