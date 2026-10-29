import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import 'onboarding_ui.dart';

/// The text controllers the wizard screen owns for the personal step, so
/// typed values survive moving between steps.
class PersonalFields {
  PersonalFields({
    required this.name,
    required this.email,
    required this.address,
    required this.city,
    required this.state,
    required this.referral,
  });

  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController address;
  final TextEditingController city;
  final TextEditingController state;
  final TextEditingController referral;

  void dispose() {
    for (final c in [name, email, address, city, state, referral]) {
      c.dispose();
    }
  }
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Step 2 — who the partner is.
class PersonalStep extends ConsumerWidget {
  const PersonalStep({
    super.key,
    required this.formKey,
    required this.fields,
    required this.phone,
    required this.onChanged,
  });

  final GlobalKey<FormState> formKey;
  final PersonalFields fields;
  final String phone;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(onboardingOperatingCitiesProvider).value ?? const <String>[];
    final gap = SizedBox(height: 12.h);
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(
            title: 'Your details',
            subtitle: 'As they appear on your ID — our team checks them.',
          ),
          TextFormField(
            controller: fields.name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: onboardingInputDecoration(
              context,
              label: 'Full name *',
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            onChanged: (_) => onChanged(),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Enter your full name';
              if (t.length < 2) return 'Name is too short';
              return null;
            },
          ),
          gap,
          TextFormField(
            initialValue: phone.isEmpty ? '' : '+91 $phone',
            enabled: false,
            decoration: onboardingInputDecoration(
              context,
              label: 'Mobile number',
              prefixIcon: const Icon(Icons.phone_iphone_rounded),
              helper: 'Verified with OTP',
            ),
          ),
          gap,
          TextFormField(
            controller: fields.email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: onboardingInputDecoration(
              context,
              label: 'Email (optional)',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
            ),
            onChanged: (_) => onChanged(),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              return _emailPattern.hasMatch(t) ? null : 'Enter a valid email';
            },
          ),
          gap,
          TextFormField(
            controller: fields.address,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            minLines: 1,
            maxLines: 3,
            decoration: onboardingInputDecoration(
              context,
              label: 'Address *',
              prefixIcon: const Icon(Icons.home_outlined),
            ),
            onChanged: (_) => onChanged(),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter your address' : null,
          ),
          gap,
          LayoutBuilder(
            builder: (context, c) {
              final city = TextFormField(
                controller: fields.city,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: onboardingInputDecoration(
                  context,
                  label: 'City *',
                ).copyWith(
                  suffixIcon: cities.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Choose operating city',
                          icon: const Icon(Icons.location_city_rounded),
                          onPressed: () async {
                            final picked = await _pickCity(
                              context,
                              cities,
                              fields.city.text,
                            );
                            if (picked == null) return;
                            fields.city.text = picked;
                            onChanged();
                          },
                        ),
                ),
                onChanged: (_) => onChanged(),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your city' : null,
              );
              final state = TextFormField(
                controller: fields.state,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: onboardingInputDecoration(
                  context,
                  label: 'State *',
                ),
                onChanged: (_) => onChanged(),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your state' : null,
              );
              // Side by side only when each half still fits a label at large
              // text; otherwise stacked.
              if (c.maxWidth < 360) {
                return Column(children: [city, gap, state]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: city),
                  SizedBox(width: 12.w),
                  Expanded(child: state),
                ],
              );
            },
          ),
          gap,
          TextFormField(
            controller: fields.referral,
            textInputAction: TextInputAction.done,
            maxLength: 64,
            decoration: onboardingInputDecoration(
              context,
              label: 'Referral code (optional)',
              prefixIcon: const Icon(Icons.card_giftcard_rounded),
            ).copyWith(
              counterText: '',
              helperText: 'The code from the partner who invited you',
            ),
            onChanged: (_) => onChanged(),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty || isValidPartnerReferralCode(t)) return null;
              return 'This is not a valid referral code — check it or clear it';
            },
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet of the admin's operating cities. Returns the chosen name.
Future<String?> _pickCity(
  BuildContext context,
  List<String> cities,
  String current,
) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Text(
                'Where will you work?',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: OnboardingColors.text(ctx),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cities.length,
                itemBuilder: (_, i) {
                  final name = cities[i];
                  final selected =
                      name.toLowerCase() == current.trim().toLowerCase();
                  return ListTile(
                    leading: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.location_on_outlined,
                      color: selected ? OnboardingColors.brand : null,
                    ),
                    title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(ctx).pop(name),
                  );
                },
              ),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}
