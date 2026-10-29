/// The partner's answers so far, held in memory across every wizard step.
///
/// Immutable: each edit produces a new draft through the controller, so a
/// step that rebuilds always sees the latest answers, and going back never
/// loses anything.
library;

enum WizardStep {
  service('Service'),
  personal('Details'),
  vehicle('Vehicle'),
  documents('Documents'),
  review('Review');

  const WizardStep(this.label);
  final String label;
}

/// What the partner has filled in for one catalogue document.
class DocumentUpload {
  const DocumentUpload({this.number = '', this.frontPath, this.backPath});

  final String number;
  final String? frontPath;
  final String? backPath;

  DocumentUpload copyWith({
    String? number,
    String? frontPath,
    String? backPath,
    bool clearFront = false,
    bool clearBack = false,
  }) => DocumentUpload(
    number: number ?? this.number,
    frontPath: clearFront ? null : (frontPath ?? this.frontPath),
    backPath: clearBack ? null : (backPath ?? this.backPath),
  );
}

enum VehicleCheckStatus { idle, checking, available, taken, failed }

/// The live `check-vehicle` answer, tied to the number it was asked for so a
/// stale answer is never trusted for an edited number.
class VehicleCheck {
  const VehicleCheck({
    this.number = '',
    this.status = VehicleCheckStatus.idle,
    this.message = '',
  });

  final String number;
  final VehicleCheckStatus status;
  final String message;
}

class RegistrationDraft {
  const RegistrationDraft({
    this.step = WizardStep.service,
    this.phone = '',
    this.driverClass = '',
    this.intents = const [],
    this.name = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.referralCode = '',
    this.vehicleTypeId = '',
    this.vehicleTypeName = '',
    this.vehicleName = '',
    this.vehicleNumber = '',
    this.vehicleCheck = const VehicleCheck(),
    this.documents = const {},
    this.profilePhotoPath,
    this.prefilledFromId,
    this.furthestStep = WizardStep.service,
  });

  final WizardStep step;

  /// Whose registration this is — a draft for another number is discarded.
  final String phone;
  final String driverClass;

  /// In the order the partner picked them.
  final List<String> intents;
  final String name;
  final String email;
  final String address;
  final String city;
  final String state;
  final String referralCode;
  final String vehicleTypeId;
  final String vehicleTypeName;
  final String vehicleName;
  final String vehicleNumber;
  final VehicleCheck vehicleCheck;

  /// Keyed by catalogue document key.
  final Map<String, DocumentUpload> documents;
  final String? profilePhotoPath;

  /// The rejected application this draft was prefilled from, if any.
  final String? prefilledFromId;

  /// The furthest step reached, so the progress bar can offer jumps back.
  final WizardStep furthestStep;

  String get intentsCsv => intents.join(',');

  DocumentUpload upload(String key) => documents[key] ?? const DocumentUpload();

  RegistrationDraft copyWith({
    WizardStep? step,
    String? phone,
    String? driverClass,
    List<String>? intents,
    String? name,
    String? email,
    String? address,
    String? city,
    String? state,
    String? referralCode,
    String? vehicleTypeId,
    String? vehicleTypeName,
    String? vehicleName,
    String? vehicleNumber,
    VehicleCheck? vehicleCheck,
    Map<String, DocumentUpload>? documents,
    String? profilePhotoPath,
    bool clearProfilePhoto = false,
    String? prefilledFromId,
    WizardStep? furthestStep,
  }) {
    return RegistrationDraft(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      driverClass: driverClass ?? this.driverClass,
      intents: intents ?? this.intents,
      name: name ?? this.name,
      email: email ?? this.email,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      referralCode: referralCode ?? this.referralCode,
      vehicleTypeId: vehicleTypeId ?? this.vehicleTypeId,
      vehicleTypeName: vehicleTypeName ?? this.vehicleTypeName,
      vehicleName: vehicleName ?? this.vehicleName,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleCheck: vehicleCheck ?? this.vehicleCheck,
      documents: documents ?? this.documents,
      profilePhotoPath: clearProfilePhoto
          ? null
          : (profilePhotoPath ?? this.profilePhotoPath),
      prefilledFromId: prefilledFromId ?? this.prefilledFromId,
      furthestStep: furthestStep ?? this.furthestStep,
    );
  }
}

/// Vehicle numbers are stored upper-cased with no spaces or hyphens, and the
/// availability check is asked for exactly the value that will be submitted.
String normalizeVehicleNumber(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

bool isPlausibleVehicleNumber(String normalized) =>
    RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(normalized) &&
    RegExp(r'[0-9]').hasMatch(normalized) &&
    RegExp(r'[A-Z]').hasMatch(normalized);
