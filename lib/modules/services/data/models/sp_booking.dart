import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';

String _str(dynamic value) => value?.toString().trim() ?? '';

/// Reads a field that mongoose may have returned either as a raw ObjectId
/// string or as a populated sub-document.
///
/// `GET /sp/users/bookings` returns lean documents with `vendorId` populated to
/// a name/phone object, while the list endpoint and the socket payloads send
/// the bare id. Anything that walks into `json['vendorId']['name']` blindly
/// crashes on half the responses.
Map<String, dynamic>? _populated(dynamic value) =>
    value is Map ? value.cast<String, dynamic>() : null;

String _idOf(dynamic value) {
  if (value is Map) return _str(value['_id'] ?? value['id']);
  return _str(value);
}

/// Where a booking is in its lifecycle.
///
/// Mirrors `BOOKING_STATUS` in `serviceProvider/utils/constants.js` exactly.
/// [unknown] exists so a status added on the server rolls out without crashing
/// already-installed apps — it renders as its raw string and blocks nothing.
enum SpBookingStatus {
  searching,
  requested,
  awaitingPayment,
  pending,
  confirmed,
  accepted,
  assigned,
  journeyStarted,
  visited,
  inProgress,
  workDone,
  completed,
  noVendors,
  cancelled,
  rejected,
  unknown;

  static const _wire = {
    'searching': searching,
    'requested': requested,
    'awaiting_payment': awaitingPayment,
    'pending': pending,
    'confirmed': confirmed,
    'accepted': accepted,
    'assigned': assigned,
    'journey_started': journeyStarted,
    'visited': visited,
    'in_progress': inProgress,
    'work_done': workDone,
    'completed': completed,
    'no_vendors': noVendors,
    'cancelled': cancelled,
    'rejected': rejected,
  };

  static SpBookingStatus parse(dynamic raw) =>
      _wire[_str(raw).toLowerCase()] ?? unknown;

  /// Still looking for someone to take the job. The wave scheduler is running
  /// and the customer should be watching the searching screen.
  bool get isSearching => this == searching || this == requested;

  /// Nobody is coming — terminal, but for a different reason than a cancel.
  bool get isDead =>
      this == cancelled || this == rejected || this == noVendors;

  bool get isFinished => this == completed || this == workDone || isDead;

  /// A partner is assigned and the job is underway, so the tracking view and
  /// its live-location socket room are worth opening.
  bool get isLive =>
      this == accepted ||
      this == assigned ||
      this == journeyStarted ||
      this == visited ||
      this == inProgress;

  /// True once someone is physically on the way — this is when the map and the
  /// visit OTP become relevant.
  bool get isEnRoute => this == journeyStarted;

  String get label => switch (this) {
        searching => 'Finding a professional',
        requested => 'Waiting for confirmation',
        awaitingPayment => 'Payment pending',
        pending => 'Pending',
        confirmed => 'Confirmed',
        accepted => 'Confirmed',
        assigned => 'Professional assigned',
        journeyStarted => 'On the way',
        visited => 'Arrived',
        inProgress => 'Work in progress',
        workDone => 'Completed',
        completed => 'Completed',
        noVendors => 'No professionals available',
        cancelled => 'Cancelled',
        rejected => 'Rejected',
        unknown => 'Updating',
      };
}

/// Mirrors `PAYMENT_STATUS` in the same constants file.
enum SpPaymentStatus {
  pending,
  success,
  failed,
  refunded,
  collectedByVendor,
  planCovered,
  unknown;

  static const _wire = {
    'pending': pending,
    'success': success,
    'failed': failed,
    'refunded': refunded,
    'collected_by_vendor': collectedByVendor,
    'plan_covered': planCovered,
  };

  static SpPaymentStatus parse(dynamic raw) =>
      _wire[_str(raw).toLowerCase()] ?? unknown;

  /// Money has come to rest — nothing left for the customer to pay.
  bool get isSettled =>
      this == success || this == collectedByVendor || this == planCovered;

  String get label => switch (this) {
        pending => 'Payment pending',
        success => 'Paid',
        failed => 'Payment failed',
        refunded => 'Refunded',
        collectedByVendor => 'Paid at doorstep',
        planCovered => 'Covered by your plan',
        unknown => '—',
      };
}

/// The service address on a booking.
///
/// **This is not the same shape as the super app's shared address book.** Food
/// and taxi use `{street, city, state, zipCode, location:{Point}}`; SP uses
/// `{addressLine1, addressLine2, city, state, pincode, landmark, lat, lng}`.
/// The two live in different collections and were deliberately not merged —
/// see the integration plan §4.2, which flags the overlapping `addresses[]`
/// sub-schema as a silent-corruption risk. [fromSharedAddress] does the
/// translation at the one point where it is needed.
class SpBookingAddress {
  const SpBookingAddress({
    this.type = 'home',
    required this.addressLine1,
    this.addressLine2 = '',
    required this.city,
    required this.state,
    required this.pincode,
    this.landmark = '',
    this.lat,
    this.lng,
  });

  final String type;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String pincode;
  final String landmark;
  final double? lat;
  final double? lng;

  bool get isComplete =>
      addressLine1.isNotEmpty &&
      city.isNotEmpty &&
      state.isNotEmpty &&
      pincode.isNotEmpty;

  String get singleLine => [
        addressLine1,
        if (addressLine2.isNotEmpty) addressLine2,
        if (landmark.isNotEmpty) 'near $landmark',
        city,
        state,
        pincode,
      ].where((p) => p.isNotEmpty).join(', ');

  SpBookingAddress copyWith({
    String? type,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? pincode,
    String? landmark,
    double? lat,
    double? lng,
  }) =>
      SpBookingAddress(
        type: type ?? this.type,
        addressLine1: addressLine1 ?? this.addressLine1,
        addressLine2: addressLine2 ?? this.addressLine2,
        city: city ?? this.city,
        state: state ?? this.state,
        pincode: pincode ?? this.pincode,
        landmark: landmark ?? this.landmark,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );

  factory SpBookingAddress.fromJson(Map<String, dynamic> json) =>
      SpBookingAddress(
        type: _str(json['type']).isEmpty ? 'home' : _str(json['type']),
        addressLine1: _str(json['addressLine1']),
        addressLine2: _str(json['addressLine2']),
        city: _str(json['city']),
        state: _str(json['state']),
        pincode: _str(json['pincode']),
        landmark: _str(json['landmark']),
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'addressLine1': addressLine1,
        'addressLine2': addressLine2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'landmark': landmark,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  /// Best-effort translation from the shared address book's shape.
  ///
  /// The shared model has no `pincode`/`landmark` equivalent beyond `zipCode`,
  /// so the booking form still has to collect what is missing — hence
  /// [isComplete], which the schedule screen gates the Continue button on.
  factory SpBookingAddress.fromSharedAddress({
    String? label,
    String? street,
    String? additionalDetails,
    String? city,
    String? state,
    String? zipCode,
    double? lat,
    double? lng,
  }) =>
      SpBookingAddress(
        type: (label ?? 'home').toLowerCase(),
        addressLine1: _str(street),
        addressLine2: _str(additionalDetails),
        city: _str(city),
        state: _str(state),
        pincode: _str(zipCode),
        lat: lat,
        lng: lng,
      );
}

/// The partner attached to a booking — either the vendor (business) or the
/// worker (the individual who actually turns up).
class SpPartner {
  const SpPartner({
    required this.id,
    required this.name,
    required this.phone,
    required this.businessName,
    required this.photoUrl,
    required this.rating,
  });

  final String id;
  final String name;
  final String phone;
  final String businessName;
  final String photoUrl;
  final double rating;

  String get displayName =>
      businessName.isNotEmpty ? businessName : (name.isNotEmpty ? name : 'Professional'.tr);

  static SpPartner? fromJson(dynamic value) {
    final json = _populated(value);
    // A bare ObjectId string means "assigned, but this endpoint didn't populate
    // it" — there is nothing to show, so treat it as absent rather than
    // rendering an empty card.
    if (json == null) return null;
    final id = _str(json['_id'] ?? json['id']);
    if (id.isEmpty) return null;
    return SpPartner(
      id: id,
      name: _str(json['name']),
      phone: _str(json['phone']),
      businessName: _str(json['businessName']),
      photoUrl: ApiConfig.resolveMedia(_str(json['profilePhoto'])),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One line on the final bill, as generated by the vendor or worker.
class SpBillLine {
  const SpBillLine({
    required this.name,
    required this.quantity,
    required this.totalPaise,
  });

  final String name;
  final int quantity;
  final int totalPaise;

  factory SpBillLine.fromJson(Map<String, dynamic> json) => SpBillLine(
        name: _str(json['name'] ?? json['title'] ?? json['serviceName']),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        totalPaise: paiseOf(json['total'] ?? json['price'] ?? json['amount']),
      );
}

/// A service booking.
///
/// Parses both the lean list documents from `GET /sp/users/bookings` and the
/// fully-populated detail document from `GET /sp/users/bookings/:id`, so one
/// type serves the list, the tracking screen and the socket refresh.
class SpBooking {
  const SpBooking({
    required this.id,
    required this.bookingNumber,
    required this.status,
    required this.paymentStatus,
    required this.serviceName,
    required this.serviceCategory,
    required this.categoryIconUrl,
    required this.brandName,
    required this.brandIconUrl,
    required this.basePricePaise,
    required this.discountPaise,
    required this.taxPaise,
    required this.visitingChargesPaise,
    required this.finalAmountPaise,
    required this.paymentMethod,
    required this.address,
    required this.scheduledDate,
    required this.scheduledTime,
    required this.slotStart,
    required this.slotEnd,
    required this.vendor,
    required this.worker,
    required this.visitOtp,
    required this.paymentOtp,
    required this.rating,
    required this.review,
    required this.billLines,
    required this.billTotalPaise,
    required this.cancellationReason,
    required this.createdAt,
    required this.completedAt,
  });

  final String id;
  final String bookingNumber;
  final SpBookingStatus status;
  final SpPaymentStatus paymentStatus;

  final String serviceName;
  final String serviceCategory;
  final String categoryIconUrl;
  final String brandName;
  final String brandIconUrl;

  final int basePricePaise;
  final int discountPaise;
  final int taxPaise;
  final int visitingChargesPaise;
  final int finalAmountPaise;
  final String paymentMethod;

  final SpBookingAddress address;
  final DateTime? scheduledDate;
  final String scheduledTime;
  final String slotStart;
  final String slotEnd;

  final SpPartner? vendor;
  final SpPartner? worker;

  /// Shown to the customer so they can read it out to the professional at the
  /// door. Only returned by the detail endpoint (`.select('+visitOtp')`).
  final String visitOtp;

  /// Read out only when handing over cash / confirming payment at the door.
  final String paymentOtp;

  final double rating;
  final String review;
  final List<SpBillLine> billLines;
  final int billTotalPaise;
  final String cancellationReason;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Whoever is actually coming to the address: the assigned worker if there is
  /// one, otherwise the vendor doing the job themselves (the `/self/*` flow).
  SpPartner? get attendingPartner => worker ?? vendor;

  bool get hasBill => billLines.isNotEmpty || billTotalPaise > 0;

  /// The amount the customer still owes, in paise. Zero once settled.
  int get outstandingPaise {
    if (paymentStatus.isSettled) return 0;
    return hasBill ? billTotalPaise : finalAmountPaise;
  }

  bool get canCancel => !status.isFinished;

  bool get canReview =>
      (status == SpBookingStatus.completed || status == SpBookingStatus.workDone) &&
      rating <= 0;

  bool get canReschedule =>
      status == SpBookingStatus.searching ||
      status == SpBookingStatus.requested ||
      status == SpBookingStatus.accepted ||
      status == SpBookingStatus.assigned ||
      status == SpBookingStatus.confirmed;

  factory SpBooking.fromJson(Map<String, dynamic> json) {
    final slot = (json['timeSlot'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final bill = (json['bill'] as Map?)?.cast<String, dynamic>();

    // The bill's line items live under one of three keys depending on whether
    // the vendor billed services, parts, or both.
    final billItems = <SpBillLine>[
      for (final key in const ['items', 'services', 'parts'])
        for (final line in (bill?[key] as List? ?? const []))
          SpBillLine.fromJson((line as Map).cast<String, dynamic>()),
    ];

    return SpBooking(
      id: _idOf(json['_id'] ?? json['id']),
      bookingNumber: _str(json['bookingNumber']),
      status: SpBookingStatus.parse(json['status']),
      paymentStatus: SpPaymentStatus.parse(json['paymentStatus']),
      serviceName: _str(json['serviceName']).isNotEmpty
          ? _str(json['serviceName'])
          : _str(_populated(json['serviceId'])?['title']),
      serviceCategory: _str(json['serviceCategory']),
      categoryIconUrl: ApiConfig.resolveMedia(_str(json['categoryIcon'])),
      brandName: _str(json['brandName']),
      brandIconUrl: ApiConfig.resolveMedia(_str(json['brandIcon'])),
      basePricePaise: paiseOf(json['basePrice']),
      discountPaise: paiseOf(json['discount']),
      taxPaise: paiseOf(json['tax']),
      visitingChargesPaise: paiseOf(json['visitingCharges']),
      finalAmountPaise: paiseOf(json['finalAmount']),
      paymentMethod: _str(json['paymentMethod']),
      address: SpBookingAddress.fromJson(
        (json['address'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      scheduledDate: DateTime.tryParse(_str(json['scheduledDate']))?.toLocal(),
      scheduledTime: _str(json['scheduledTime']),
      slotStart: _str(slot['start']),
      slotEnd: _str(slot['end']),
      vendor: SpPartner.fromJson(json['vendorId']),
      worker: SpPartner.fromJson(json['workerId']),
      visitOtp: _str(json['visitOtp']),
      paymentOtp: _str(json['paymentOtp']),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      review: _str(json['review']),
      billLines: billItems,
      billTotalPaise: paiseOf(
        bill?['totalAmount'] ?? bill?['grandTotal'] ?? bill?['total'],
      ),
      cancellationReason: _str(json['cancellationReason']),
      createdAt: DateTime.tryParse(_str(json['createdAt']))?.toLocal(),
      completedAt: DateTime.tryParse(_str(json['completedAt']))?.toLocal(),
    );
  }
}
