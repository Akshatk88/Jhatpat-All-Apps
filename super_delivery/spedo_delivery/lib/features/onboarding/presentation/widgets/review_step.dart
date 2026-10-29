import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/registration_draft.dart';
import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import 'onboarding_ui.dart';

/// Step 5 — everything at a glance, each block with a way back to fix it.
class ReviewStep extends ConsumerWidget {
  const ReviewStep({
    super.key,
    required this.requirements,
    required this.onEdit,
    this.errorText,
  });

  final OnboardingRequirements requirements;
  final ValueChanged<WizardStep> onEdit;
  final String? errorText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(registrationWizardProvider);
    final classes = ref.watch(onboardingOptionsProvider).value ?? const [];
    final cls = classes.where((c) => c.key == d.driverClass).firstOrNull;
    final intentLabels = [
      for (final key in d.intents)
        cls?.intents.where((i) => i.key == key).firstOrNull?.label ?? key,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Review & submit',
          subtitle: 'Check everything once. You can go back to any section.',
        ),
        _Section(
          title: 'Service',
          onEdit: () => onEdit(WizardStep.service),
          rows: [
            ('Vehicle class', cls?.label ?? d.driverClass),
            ('Work', intentLabels.isEmpty ? '—' : intentLabels.join('\n')),
          ],
        ),
        _Section(
          title: 'Your details',
          onEdit: () => onEdit(WizardStep.personal),
          rows: [
            ('Name', d.name.trim()),
            ('Mobile', '+91 ${d.phone}'),
            if (d.email.trim().isNotEmpty) ('Email', d.email.trim()),
            ('Address', d.address.trim()),
            ('City / State', '${d.city.trim()}, ${d.state.trim()}'),
            if (d.referralCode.trim().isNotEmpty)
              ('Referral code', d.referralCode.trim()),
          ],
        ),
        _Section(
          title: 'Vehicle',
          onEdit: () => onEdit(WizardStep.vehicle),
          rows: [
            ('Type', d.vehicleTypeName.isEmpty ? '—' : d.vehicleTypeName),
            if (d.vehicleName.trim().isNotEmpty)
              ('Model', d.vehicleName.trim()),
            ('Number', normalizeVehicleNumber(d.vehicleNumber)),
          ],
        ),
        _Section(
          title: 'Documents',
          onEdit: () => onEdit(WizardStep.documents),
          rows: const [],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DocRow(
                name: 'Profile photo',
                detail: '',
                images: [?d.profilePhotoPath],
              ),
              for (final doc in requirements.documents)
                if (_hasAnything(d.upload(doc.key)))
                  _DocRow(
                    name: doc.name,
                    detail: _numberFor(doc, d.upload(doc.key)),
                    images: [
                      if (doc.needsFront) ?d.upload(doc.key).frontPath,
                      if (doc.needsBack) ?d.upload(doc.key).backPath,
                    ],
                  )
                else if (!doc.isRequired)
                  _DocRow(name: doc.name, detail: 'Skipped', images: const []),
            ],
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: 4.h),
          ErrorBanner(errorText!),
        ],
        SizedBox(height: 8.h),
        Text(
          'By submitting you confirm these details are yours and correct. '
          'Approval usually takes 24–48 hours.',
          style: TextStyle(
            fontSize: 12.sp,
            height: 1.4,
            color: OnboardingColors.muted(context),
          ),
        ),
      ],
    );
  }

  static bool _hasAnything(DocumentUpload u) =>
      u.number.trim().isNotEmpty || u.frontPath != null || u.backPath != null;

  static String _numberFor(OnboardingDocument doc, DocumentUpload u) {
    final n = u.number.trim();
    if (n.isEmpty || !doc.hasNumberField) return '';
    final kind = doc.legacyKind;
    final value = kind != null ? kind.normalize(n) : n;
    // Aadhaar is shown masked, as everywhere else it is displayed.
    if (kind == LegacyDocKind.aadhaar && value.length > 4) {
      return 'XXXX XXXX ${value.substring(value.length - 4)}';
    }
    return value;
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.onEdit,
    required this.rows,
    this.child,
  });

  final String title;
  final VoidCallback onEdit;
  final List<(String, String)> rows;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(14.w, 6.h, 6.w, 12.h),
      decoration: BoxDecoration(
        color: OnboardingColors.card(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: OnboardingColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: OnboardingColors.text(context),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 16.sp),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: OnboardingColors.text(context),
                ),
              ),
            ],
          ),
          for (final (label, value) in rows)
            Padding(
              padding: EdgeInsets.only(top: 6.h, right: 8.w),
              child: Wrap(
                spacing: 8.w,
                runSpacing: 2.h,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: 96.w),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: OnboardingColors.muted(context),
                      ),
                    ),
                  ),
                  Text(
                    value.isEmpty ? '—' : value,
                    style: TextStyle(
                      fontSize: 13.5.sp,
                      fontWeight: FontWeight.w600,
                      color: OnboardingColors.text(context),
                    ),
                  ),
                ],
              ),
            ),
          ?child,
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.name,
    required this.detail,
    required this.images,
  });

  final String name;
  final String detail;
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8.h, right: 8.w),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w600,
                    color: OnboardingColors.text(context),
                  ),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: OnboardingColors.muted(context),
                    ),
                  ),
              ],
            ),
          ),
          for (final path in images)
            Padding(
              padding: EdgeInsets.only(left: 6.w),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6.r),
                child: Image.file(
                  File(path),
                  width: 36.w,
                  height: 36.w,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  errorBuilder: (_, _, _) => SizedBox(
                    width: 36.w,
                    height: 36.w,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
