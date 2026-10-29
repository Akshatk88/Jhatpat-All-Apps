/// Data shapes for the backend-driven partner onboarding.
///
/// Everything here mirrors what `food/delivery/services/onboardingRequirements
/// .service.js` serialises — the class/intent tree, the vehicle catalogue
/// filtered to that answer, and the admin's needed-document catalogue. The app
/// hardcodes none of it, so a document or vehicle type the admin adds reaches
/// the next applicant without a release.
library;

String _str(Object? v) => v == null ? '' : v.toString();

/// One sub-option under a class ("Bike Taxi + Bike parcel").
class OnboardingIntent {
  const OnboardingIntent({required this.key, required this.label});

  final String key;
  final String label;

  factory OnboardingIntent.fromJson(Map<String, dynamic> json) =>
      OnboardingIntent(key: _str(json['key']), label: _withoutMedical(_str(json['label'])));
}

/// What the partner owns — the first question onboarding asks.
class OnboardingClass {
  const OnboardingClass({
    required this.key,
    required this.label,
    required this.intents,
  });

  /// `two_wheeler` | `passenger_taxi` | `parcel_vehicle` (backend enum).
  final String key;
  final String label;
  final List<OnboardingIntent> intents;

  factory OnboardingClass.fromJson(Map<String, dynamic> json) {
    final raw = json['intents'];
    return OnboardingClass(
      key: _str(json['key']),
      label: _str(json['label']),
      intents: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => OnboardingIntent.fromJson(Map<String, dynamic>.from(e)))
                .where((i) => i.key.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

/// A vehicle type from the taxi vehicle catalogue. [id] is what
/// `vehicleType` is registered as — the admin panel resolves it back to a name.
class OnboardingVehicleType {
  const OnboardingVehicleType({
    required this.id,
    required this.name,
    required this.iconType,
    required this.transportType,
    required this.image,
    required this.capacity,
  });

  final String id;
  final String name;
  final String iconType;
  final String transportType;
  final String image;
  final int capacity;

  factory OnboardingVehicleType.fromJson(Map<String, dynamic> json) =>
      OnboardingVehicleType(
        id: _str(json['id']),
        name: _str(json['name']),
        iconType: _str(json['iconType']),
        transportType: _str(json['transportType']),
        image: _str(json['image']),
        capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      );
}

/// One entry of the admin's needed-document catalogue.
class OnboardingDocument {
  const OnboardingDocument({
    required this.id,
    required this.name,
    required this.key,
    required this.imageType,
    required this.fieldType,
    required this.placeholder,
    required this.helpText,
    required this.sortOrder,
    required this.isRequired,
  });

  final String id;
  final String name;

  /// Upload/field key: files go up as `doc_<key>_front` / `doc_<key>_back`.
  final String key;

  /// The catalogue's `image_type`: `front_back` (both sides), `front`,
  /// `back`, `image` — or `single`/`double` from the serialiser's fallback.
  final String imageType;
  final String fieldType;
  final String placeholder;
  final String helpText;
  final int sortOrder;
  final bool isRequired;

  bool get needsFront => imageType != 'back';

  bool get needsBack =>
      imageType == 'front_back' || imageType == 'double' || imageType == 'back';

  /// Only `back` documents are a back-side-only upload.
  bool get backOnly => imageType == 'back';

  /// Whether the tile offers a number input. Documents are created with
  /// `field_type: 'text'` unless the admin changed it; select-style types are
  /// vehicle fields, never a number printed on a paper.
  bool get hasNumberField =>
      // Driving licence and RC are photo-only uploads — no number asked.
      legacyKind != LegacyDocKind.drivingLicense &&
      !_rc.hasMatch('$key $name') &&
      (fieldType.isEmpty ||
      fieldType == 'text' ||
      fieldType == 'number' ||
      fieldType == 'textarea');

  static final _rc = RegExp(
    r'(^|[-_ ])rc([-_ ]|$)|registration[-_ ]?cert',
    caseSensitive: false,
  );

  bool get numericNumber => fieldType == 'number';

  /// Which of the three papers the admin panel reads by name this document is,
  /// matched with the backend's own patterns (`mirrorLegacyDocuments`).
  LegacyDocKind? get legacyKind => LegacyDocKind.match('$key $name');

  factory OnboardingDocument.fromJson(Map<String, dynamic> json) =>
      OnboardingDocument(
        id: _str(json['id']),
        name: _str(json['name']),
        key: _str(json['key']),
        imageType: _str(json['imageType']).isEmpty
            ? 'single'
            : _str(json['imageType']),
        fieldType: _str(json['fieldType']),
        placeholder: _str(json['placeholder']),
        helpText: _str(json['helpText']),
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        // Every document is mandatory for a Jhatpat partner, whatever the
        // catalogue's flag says (the backend defaults is_required to false,
        // which made everything optional).
        isRequired: true,
      );
}

/// Aadhaar / PAN / driving licence — the backend copies these numbers into
/// `aadharNumber` / `panNumber` / `drivingLicenseNumber`, so the app holds
/// them to the same formats the register validator enforces on those fields.
enum LegacyDocKind {
  aadhaar,
  pan,
  drivingLicense;

  static final _aadhaar = RegExp(r'aadha?a?r', caseSensitive: false);
  static final _pan = RegExp(
    r'(^|[-_ ])pan([-_ ]|$)|pan[-_ ]?card',
    caseSensitive: false,
  );
  static final _dl = RegExp(
    r'licen[cs]e|(^|[-_ ])dl([-_ ]|$)',
    caseSensitive: false,
  );

  static LegacyDocKind? match(String text) {
    if (_aadhaar.hasMatch(text)) return LegacyDocKind.aadhaar;
    if (_pan.hasMatch(text)) return LegacyDocKind.pan;
    if (_dl.hasMatch(text)) return LegacyDocKind.drivingLicense;
    return null;
  }

  /// The value as the backend stores it.
  String normalize(String raw) {
    final upper = raw.trim().toUpperCase();
    return switch (this) {
      LegacyDocKind.aadhaar => upper.replaceAll(RegExp(r'\s'), ''),
      LegacyDocKind.pan => upper.replaceAll(RegExp(r'\s'), ''),
      LegacyDocKind.drivingLicense => upper.replaceAll(RegExp(r'[\s-]'), ''),
    };
  }

  /// Same patterns as `delivery.validator.js`.
  bool isValid(String normalized) => switch (this) {
    LegacyDocKind.aadhaar => RegExp(r'^[0-9]{12}$').hasMatch(normalized),
    LegacyDocKind.pan => RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(normalized),
    LegacyDocKind.drivingLicense => RegExp(
      r'^[A-Z]{2}[0-9]{1,2}(?:[0-9]{2}|[0-9]{4})[0-9]{4,7}$',
    ).hasMatch(normalized),
  };

  String get invalidMessage => switch (this) {
    LegacyDocKind.aadhaar => 'Enter a valid 12-digit Aadhaar number',
    LegacyDocKind.pan => 'Enter a valid PAN (e.g. ABCDE1234F)',
    LegacyDocKind.drivingLicense =>
      'Enter a valid licence number (e.g. MP0420190012345)',
  };
}

/// `GET /food/delivery/onboarding/requirements` for one answer.
class OnboardingRequirements {
  const OnboardingRequirements({
    required this.driverClass,
    required this.intents,
    required this.vehicleTypes,
    required this.documents,
  });

  final String driverClass;
  final List<String> intents;
  final List<OnboardingVehicleType> vehicleTypes;
  final List<OnboardingDocument> documents;

  factory OnboardingRequirements.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(Object? raw) => raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
    final docs = maps(json['documents'])
        .map(OnboardingDocument.fromJson)
        .where((d) => d.key.isNotEmpty)
        // PAN is no longer collected from partners (removed on the backend
        // too) — hide it even if an old catalogue row still lists it.
        .where((d) => d.legacyKind != LegacyDocKind.pan)
        // The wizard has its own profile-photo tile; an admin "Profile Photo"
        // document would ask for the same picture twice (plus a bogus number).
        .where((d) => !RegExp(r'profile[-_ ]?(photo|pic|image)|selfie',
                caseSensitive: false)
            .hasMatch('${d.key} ${d.name}'))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return OnboardingRequirements(
      driverClass: _str(json['driverClass']),
      intents: json['intents'] is List
          ? (json['intents'] as List).map(_str).toList()
          : const [],
      vehicleTypes: maps(json['vehicleTypes'])
          .map(OnboardingVehicleType.fromJson)
          .where((v) => v.id.isNotEmpty)
          .toList(),
      documents: docs,
    );
  }
}

/// Argument for the requirements provider. A record, so equal answers share
/// one cached fetch.
typedef RequirementsQuery = ({String driverClass, String intentsCsv});

/// A partner referral code as `/food/delivery/register` reads its `ref` field:
/// the referrer's own record id (a 24-hex Mongo ObjectId — `referralCode` is
/// set to `String(partner._id)`). Anything else is silently dropped by the
/// server, so the app refuses it up front instead of losing it.
bool isValidPartnerReferralCode(String raw) =>
    RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(raw.trim());

/// Jhatpat partners do not do medical deliveries, so "Medical" is dropped
/// from the backend's service labels ("Food + Daily needs + Medical + Bike
/// parcel" → "Food + Daily needs + Bike parcel"). Only the shown text
/// changes; the intent key sent on registration is untouched.
String _withoutMedical(String label) {
  final parts = label.split('+').map((p) => p.trim()).toList();
  final kept = parts
      .where((p) => !RegExp(r'^medic(al|ine|ines)?$', caseSensitive: false).hasMatch(p))
      .toList();
  return kept.length == parts.length ? label : kept.join(' + ');
}
