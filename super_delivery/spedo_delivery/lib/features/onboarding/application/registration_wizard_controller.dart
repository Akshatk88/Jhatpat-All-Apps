import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/services/referral_tracking_service.dart';
import '../../../core/storage/token_storage.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/models/delivery_partner.dart';
import '../data/onboarding_models.dart';
import '../data/onboarding_repository.dart';
import 'registration_draft.dart';

/// A load failure carrying the server's message, for `AsyncValue.error`.
class OnboardingLoadException implements Exception {
  const OnboardingLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Never auto-retried: the step shows the error and a Retry button, and the
/// partner decides when to try again.
Duration? _noRetry(int _, Object _) => null;

final onboardingOptionsProvider = FutureProvider<List<OnboardingClass>>((
  ref,
) async {
  final result = await ref.read(onboardingRepositoryProvider).getOptions();
  return result.when(
    success: (classes) => classes,
    failure: (e) => throw OnboardingLoadException(e.message),
  );
}, retry: _noRetry);

final onboardingRequirementsProvider =
    FutureProvider.family<OnboardingRequirements, RequirementsQuery>((
      ref,
      query,
    ) async {
      final result = await ref
          .read(onboardingRepositoryProvider)
          .getRequirements(query);
      return result.when(
        success: (r) => r,
        failure: (e) => throw OnboardingLoadException(e.message),
      );
    }, retry: _noRetry);

/// Operating cities for the City picker. An error or an empty list leaves the
/// field as free text — the city is never blocked on this read.
final onboardingOperatingCitiesProvider = FutureProvider<List<String>>((
  ref,
) async {
  final result = await ref
      .read(onboardingRepositoryProvider)
      .getOperatingCities();
  return result.when(
    success: (names) => names,
    failure: (e) => throw OnboardingLoadException(e.message),
  );
}, retry: _noRetry);

/// The most uploads one `/register` may carry (`MAX_UPLOAD_FILES` in the
/// backend's multer config); beyond it multer refuses the whole request.
const int kMaxRegistrationFiles = 20;

class RegistrationWizardController extends Notifier<RegistrationDraft> {
  Timer? _vehicleDebounce;
  int _vehicleCheckSeq = 0;

  @override
  RegistrationDraft build() {
    ref.onDispose(() => _vehicleDebounce?.cancel());
    return const RegistrationDraft();
  }

  /// Bind the draft to the number being registered, keeping progress when it
  /// is the same partner coming back, and prefilling from a rejected
  /// application when there is one.
  void attach({required String phone, DeliveryPartner? previous}) {
    var draft = state;
    if (draft.phone != phone) {
      draft = RegistrationDraft(phone: phone);
    }
    if (previous != null && draft.prefilledFromId != _prefillId(previous)) {
      draft = _prefill(RegistrationDraft(phone: phone), previous);
    }
    state = draft;
    if (draft.referralCode.isEmpty) unawaited(_loadReferral());
  }

  String _prefillId(DeliveryPartner p) => p.id.isNotEmpty ? p.id : 'rejected';

  RegistrationDraft _prefill(RegistrationDraft base, DeliveryPartner p) {
    // Photos cannot be carried over: the validator accepts no URLs for them,
    // so a re-application uploads every image again. Text is kept.
    final docs = <String, DocumentUpload>{
      for (final d in p.onboardingDocuments)
        if (d.key.isNotEmpty && d.number.isNotEmpty)
          d.key: DocumentUpload(number: d.number),
    };
    final cls = p.driverClass ?? '';
    return base.copyWith(
      prefilledFromId: _prefillId(p),
      driverClass: cls,
      intents: cls.isEmpty ? const [] : p.serviceIntents,
      name: p.name,
      email: p.email ?? '',
      address: p.address ?? '',
      city: p.city ?? '',
      state: p.state ?? '',
      vehicleTypeId: p.vehicleType ?? '',
      vehicleName: p.vehicleName ?? '',
      vehicleNumber: p.vehicleNumber ?? '',
      documents: docs,
    );
  }

  Future<void> _loadReferral() async {
    final code = await ReferralTrackingService.getReferralCode();
    // An install-referrer value that is not a partner id would only fail the
    // referral check on the personal step; it is not offered.
    if (code != null &&
        isValidPartnerReferralCode(code) &&
        state.referralCode.isEmpty) {
      state = state.copyWith(referralCode: code);
    }
  }

  // ---- navigation ---------------------------------------------------------

  void goTo(WizardStep step) {
    final furthest = step.index > state.furthestStep.index
        ? step
        : state.furthestStep;
    state = state.copyWith(step: step, furthestStep: furthest);
  }

  bool back() {
    if (state.step.index == 0) return false;
    goTo(WizardStep.values[state.step.index - 1]);
    return true;
  }

  // ---- step 1: service ----------------------------------------------------

  void selectClass(OnboardingClass cls) {
    if (state.driverClass == cls.key) return;
    // A different class means a different vehicle list and document list.
    state = state.copyWith(
      driverClass: cls.key,
      intents: cls.intents.length == 1 ? [cls.intents.first.key] : const [],
      vehicleTypeId: '',
      vehicleTypeName: '',
      furthestStep: WizardStep.service,
    );
  }

  void toggleIntent(String key) {
    final next = [...state.intents];
    if (!next.remove(key)) next.add(key);
    state = state.copyWith(intents: next, furthestStep: WizardStep.service);
  }

  // ---- step 2: personal ---------------------------------------------------

  void updatePersonal({
    String? name,
    String? email,
    String? address,
    String? city,
    String? state,
    String? referralCode,
  }) {
    this.state = this.state.copyWith(
      name: name,
      email: email,
      address: address,
      city: city,
      state: state,
      referralCode: referralCode,
    );
  }

  void setProfilePhoto(String? path) {
    state = path == null
        ? state.copyWith(clearProfilePhoto: true)
        : state.copyWith(profilePhotoPath: path);
  }

  // ---- step 3: vehicle ----------------------------------------------------

  void selectVehicleType(OnboardingVehicleType type) {
    state = state.copyWith(vehicleTypeId: type.id, vehicleTypeName: type.name);
  }

  /// Clears a selection the current requirements no longer offer.
  void dropVehicleTypeIfMissing(List<OnboardingVehicleType> offered) {
    if (state.vehicleTypeId.isEmpty) return;
    final match = offered.where((v) => v.id == state.vehicleTypeId);
    if (match.isEmpty) {
      state = state.copyWith(vehicleTypeId: '', vehicleTypeName: '');
    } else if (state.vehicleTypeName != match.first.name) {
      state = state.copyWith(vehicleTypeName: match.first.name);
    }
  }

  void setVehicleName(String value) =>
      state = state.copyWith(vehicleName: value);

  /// Debounced live check as the number is typed.
  void setVehicleNumber(String raw) {
    state = state.copyWith(vehicleNumber: raw);
    _vehicleDebounce?.cancel();
    final normalized = normalizeVehicleNumber(raw);
    if (!isPlausibleVehicleNumber(normalized)) {
      _vehicleCheckSeq++;
      state = state.copyWith(vehicleCheck: const VehicleCheck());
      return;
    }
    if (state.vehicleCheck.number == normalized &&
        state.vehicleCheck.status != VehicleCheckStatus.failed) {
      return;
    }
    _vehicleDebounce = Timer(
      const Duration(milliseconds: 600),
      () => checkVehicleNumber(),
    );
  }

  /// Asks the server whether the current number is free. Returns the answer
  /// for the number as it stands; a reply for an outdated number is dropped.
  Future<VehicleCheckStatus> checkVehicleNumber() async {
    _vehicleDebounce?.cancel();
    final normalized = normalizeVehicleNumber(state.vehicleNumber);
    if (!isPlausibleVehicleNumber(normalized)) return VehicleCheckStatus.idle;
    final current = state.vehicleCheck;
    if (current.number == normalized &&
        (current.status == VehicleCheckStatus.available ||
            current.status == VehicleCheckStatus.taken)) {
      return current.status;
    }
    final seq = ++_vehicleCheckSeq;
    state = state.copyWith(
      vehicleCheck: VehicleCheck(
        number: normalized,
        status: VehicleCheckStatus.checking,
      ),
    );
    final result = await ref
        .read(onboardingRepositoryProvider)
        .checkVehicle(normalized);
    if (seq != _vehicleCheckSeq ||
        normalizeVehicleNumber(state.vehicleNumber) != normalized) {
      return VehicleCheckStatus.idle;
    }
    final check = result.when(
      success: (a) => VehicleCheck(
        number: normalized,
        status: a.isAvailable
            ? VehicleCheckStatus.available
            : VehicleCheckStatus.taken,
        message: a.isAvailable
            ? ''
            : (a.message.isNotEmpty
                  ? a.message
                  : 'Vehicle number already registered'),
      ),
      failure: (e) => VehicleCheck(
        number: normalized,
        status: VehicleCheckStatus.failed,
        message: e.message,
      ),
    );
    state = state.copyWith(vehicleCheck: check);
    return check.status;
  }

  // ---- step 4: documents --------------------------------------------------

  void setDocumentNumber(String key, String number) {
    final docs = {...state.documents};
    docs[key] = state.upload(key).copyWith(number: number);
    state = state.copyWith(documents: docs);
  }

  void setDocumentImage(String key, {required bool back, String? path}) {
    final docs = {...state.documents};
    final current = state.upload(key);
    docs[key] = back
        ? (path == null
              ? current.copyWith(clearBack: true)
              : current.copyWith(backPath: path))
        : (path == null
              ? current.copyWith(clearFront: true)
              : current.copyWith(frontPath: path));
    state = state.copyWith(documents: docs);
  }

  // ---- submit -------------------------------------------------------------

  /// `POST /food/delivery/register` as multipart.
  ///
  /// Only documents in [requirements] are sent, so uploads left over from a
  /// class the partner switched away from never reach the server.
  Future<Result<void, AppError>> submit(
    OnboardingRequirements requirements,
  ) async {
    final d = state;
    final fcmToken = await ref.read(tokenStorageProvider).getFcmToken();

    final form = FormData();
    void field(String k, String v) => form.fields.add(MapEntry(k, v));

    field('name', d.name.trim());
    field('phone', d.phone);
    field('countryCode', '+91');
    if (d.email.trim().isNotEmpty) field('email', d.email.trim());
    if (d.address.trim().isNotEmpty) field('address', d.address.trim());
    if (d.city.trim().isNotEmpty) field('city', d.city.trim());
    if (d.state.trim().isNotEmpty) field('state', d.state.trim());
    field('driverClass', d.driverClass);
    // The validator takes an array or a string; the service splits a string
    // on commas, which is the one shape multipart carries unambiguously.
    field('serviceIntents', d.intentsCsv);
    // The taxi vehicle-catalogue id; the admin panel resolves it to a name.
    field('vehicleType', d.vehicleTypeId);
    if (d.vehicleName.trim().isNotEmpty) {
      field('vehicleName', d.vehicleName.trim());
    }
    field('vehicleNumber', normalizeVehicleNumber(d.vehicleNumber));
    if (isValidPartnerReferralCode(d.referralCode)) {
      field('ref', d.referralCode.trim());
    }
    if (fcmToken != null && fcmToken.isNotEmpty) field('fcmToken', fcmToken);
    field('platform', 'mobile');

    try {
      final files = <MapEntry<String, MultipartFile>>[];
      if (d.profilePhotoPath != null) {
        files.add(
          MapEntry(
            'profilePhoto',
            await MultipartFile.fromFile(d.profilePhotoPath!),
          ),
        );
      }
      for (final doc in requirements.documents) {
        final up = d.upload(doc.key);
        final number = up.number.trim();
        final hasAny =
            number.isNotEmpty || up.frontPath != null || up.backPath != null;
        if (!hasAny) continue;
        field('docname_${doc.key}', doc.name);
        if (number.isNotEmpty && doc.hasNumberField) {
          final kind = doc.legacyKind;
          field('docnum_${doc.key}', kind != null ? kind.normalize(number) : number);
        }
        if (up.frontPath != null && doc.needsFront) {
          files.add(
            MapEntry(
              'doc_${doc.key}_front',
              await MultipartFile.fromFile(up.frontPath!),
            ),
          );
        }
        if (up.backPath != null && doc.needsBack) {
          files.add(
            MapEntry(
              'doc_${doc.key}_back',
              await MultipartFile.fromFile(up.backPath!),
            ),
          );
        }
      }
      if (files.length > kMaxRegistrationFiles) {
        return Result.failure(
          UnknownError(
            'Too many photos in one application (${files.length}, maximum '
            '$kMaxRegistrationFiles). Please contact support.',
          ),
        );
      }
      form.files.addAll(files);
    } on Exception catch (_) {
      return Result.failure(
        UnknownError(
          'One of the selected photos could not be read. Please pick it again.',
        ),
      );
    }

    final result = await ref
        .read(authControllerProvider.notifier)
        .register(form);
    return result.when(
      success: (_) {
        reset();
        ref.invalidate(onboardingRequirementsProvider);
        return const Result.success(null);
      },
      failure: (e) => Result.failure(e),
    );
  }

  void reset() {
    _vehicleDebounce?.cancel();
    _vehicleCheckSeq++;
    state = const RegistrationDraft();
  }
}

final registrationWizardProvider =
    NotifierProvider<RegistrationWizardController, RegistrationDraft>(
      RegistrationWizardController.new,
    );
