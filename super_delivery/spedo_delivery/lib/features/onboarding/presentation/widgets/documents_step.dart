import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/registration_draft.dart';
import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import 'onboarding_ui.dart';

/// Whether a document's number must be filled in: every document that has
/// a number field is mandatory, number included.
bool documentNumberRequired(OnboardingDocument doc) =>
    doc.isRequired && doc.hasNumberField;

/// What still blocks the documents step, as one line each. Empty when done.
List<String> documentProblems(
  RegistrationDraft draft,
  OnboardingRequirements req,
) {
  final out = <String>[];
  if (draft.profilePhotoPath == null) out.add('Add a profile photo');
  for (final doc in req.documents) {
    final up = draft.upload(doc.key);
    if (doc.isRequired) {
      if (doc.needsFront && up.frontPath == null) {
        out.add(
          doc.needsBack
              ? '${doc.name}: add the front photo'
              : '${doc.name}: add a photo',
        );
      }
      if (doc.needsBack && up.backPath == null) {
        out.add('${doc.name}: add the back photo');
      }
    }
    final number = up.number.trim();
    final kind = doc.legacyKind;
    if (doc.hasNumberField) {
      if (number.isEmpty && documentNumberRequired(doc)) {
        out.add('${doc.name}: enter the number');
      } else if (number.isNotEmpty &&
          kind != null &&
          !kind.isValid(kind.normalize(number))) {
        out.add('${doc.name}: ${kind.invalidMessage.toLowerCase()}');
      }
    }
  }
  return out;
}

/// Step 4 — the admin's document catalogue for this partner, plus the
/// profile photo.
class DocumentsStep extends ConsumerWidget {
  const DocumentsStep({
    super.key,
    required this.formKey,
    required this.requirements,
    required this.numberController,
    required this.showErrors,
    required this.onRetry,
  });

  final GlobalKey<FormState> formKey;
  final AsyncValue<OnboardingRequirements> requirements;
  final TextEditingController Function(String key) numberController;
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
            title: 'Documents',
            subtitle:
                'Clear, uncropped photos in good light. Our team reviews '
                'each one before you can start.',
          ),
          const SectionLabel('Profile photo'),
          PhotoSlot(
            label: 'Your photo (face clearly visible)',
            path: draft.profilePhotoPath,
            required: true,
            showError: showErrors,
            onPicked: controller.setProfilePhoto,
            onRemove: () => controller.setProfilePhoto(null),
          ),
          SizedBox(height: 16.h),
          requirements.when(
            loading: () =>
                const LoadStateView.loading(label: 'Loading required documents…'),
            error: (e, _) => LoadStateView.error(
              message: e is OnboardingLoadException
                  ? e.message
                  : 'Could not load the document list.',
              onRetry: onRetry,
            ),
            data: (req) {
              if (req.documents.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Text(
                    'No other documents are needed for this service.',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: OnboardingColors.muted(context),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Required for your service'),
                  for (final doc in req.documents)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.h),
                      child: _DocumentTile(
                        doc: doc,
                        upload: draft.upload(doc.key),
                        numberController: numberController(doc.key),
                        showErrors: showErrors,
                        onNumberChanged: (v) =>
                            controller.setDocumentNumber(doc.key, v),
                        onImage: (back, path) => controller.setDocumentImage(
                          doc.key,
                          back: back,
                          path: path,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.upload,
    required this.numberController,
    required this.showErrors,
    required this.onNumberChanged,
    required this.onImage,
  });

  final OnboardingDocument doc;
  final DocumentUpload upload;
  final TextEditingController numberController;
  final bool showErrors;
  final ValueChanged<String> onNumberChanged;
  final void Function(bool back, String? path) onImage;

  bool get _complete {
    if (doc.needsFront && !doc.backOnly && upload.frontPath == null) {
      return false;
    }
    if (doc.needsBack && upload.backPath == null) return false;
    if (documentNumberRequired(doc) && upload.number.trim().isEmpty) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final kind = doc.legacyKind;
    final numberRequired = documentNumberRequired(doc);
    final numberLabel = doc.placeholder.isNotEmpty
        ? doc.placeholder
        : '${doc.name} number';
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: OnboardingColors.card(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: _complete
              ? OnboardingColors.brand.withValues(alpha: 0.7)
              : OnboardingColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.description_outlined,
                size: 20.sp,
                color: OnboardingColors.text(context),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  doc.name,
                  style: TextStyle(
                    fontSize: 14.5.sp,
                    fontWeight: FontWeight.w700,
                    color: OnboardingColors.text(context),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              _Tag(
                text: doc.isRequired ? 'Required' : 'Optional',
                strong: doc.isRequired,
              ),
            ],
          ),
          if (doc.helpText.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              doc.helpText,
              style: TextStyle(
                fontSize: 12.sp,
                height: 1.35,
                color: OnboardingColors.muted(context),
              ),
            ),
          ],
          if (doc.hasNumberField) ...[
            SizedBox(height: 10.h),
            TextFormField(
              controller: numberController,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: kind == LegacyDocKind.aadhaar || doc.numericNumber
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: [
                if (kind == LegacyDocKind.aadhaar)
                  FilteringTextInputFormatter.digitsOnly,
                // The server keeps 120 characters of a document number.
                LengthLimitingTextInputFormatter(
                  kind == LegacyDocKind.aadhaar ? 12 : 40,
                ),
              ],
              decoration: onboardingInputDecoration(
                context,
                label: numberRequired ? '$numberLabel *' : '$numberLabel (optional)',
              ),
              onChanged: onNumberChanged,
              validator: (v) {
                final raw = (v ?? '').trim();
                if (raw.isEmpty) {
                  return numberRequired ? 'Enter the ${doc.name} number' : null;
                }
                if (kind != null && !kind.isValid(kind.normalize(raw))) {
                  return kind.invalidMessage;
                }
                return null;
              },
            ),
          ],
          if (doc.needsFront && !doc.backOnly) ...[
            SizedBox(height: 10.h),
            PhotoSlot(
              label: doc.needsBack ? 'Front side' : 'Photo',
              path: upload.frontPath,
              required: doc.isRequired,
              showError: showErrors && doc.isRequired,
              onPicked: (p) => onImage(false, p),
              onRemove: () => onImage(false, null),
            ),
          ],
          if (doc.needsBack) ...[
            SizedBox(height: 10.h),
            PhotoSlot(
              label: 'Back side',
              path: upload.backPath,
              required: doc.isRequired,
              showError: showErrors && doc.isRequired,
              onPicked: (p) => onImage(true, p),
              onRemove: () => onImage(true, null),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.strong});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: strong
            ? OnboardingColors.brand
            : OnboardingColors.border(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          color: strong ? OnboardingColors.onBrand : OnboardingColors.text(context),
        ),
      ),
    );
  }
}
