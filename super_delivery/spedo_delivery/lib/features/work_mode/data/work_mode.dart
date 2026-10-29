/// The module the rider is working in: Food delivery, Parcel delivery or Rider.
///
/// Three app modules over **two** server modes. k9's `setWorkMode` accepts
/// exactly `all | taxi | delivery`, and parcel jobs ride the same dispatcher as
/// passenger trips (`matchingService.js` picks the `parcel` vs `taxi`
/// capability from the ride's `serviceType`). So:
///
/// | module | wire       | receives                                   |
/// |--------|------------|--------------------------------------------|
/// | food   | `delivery` | food orders                                |
/// | parcel | `taxi`     | ride-dispatcher offers with serviceType parcel |
/// | rider  | `taxi`     | ride-dispatcher offers for passengers      |
///
/// The server cannot tell parcel from rider, so the app does: the choice is
/// kept locally ([WorkModePreferenceStore]) and the incoming-ride controller
/// ignores offers of the other kind via [acceptsOffer].
enum WorkMode {
  /// Restaurant orders.
  food(
    'delivery',
    'Food delivery',
    'Restaurant orders',
    "You're not registered for food delivery",
  ),

  /// Parcel jobs from the ride dispatcher.
  parcel(
    'taxi',
    'Parcel delivery',
    'Send packages',
    "You're not registered for parcel delivery",
  ),

  /// Passenger rides from the ride dispatcher.
  rider(
    'taxi',
    'Rider',
    'Passenger rides',
    "You're not registered for passenger rides",
  );

  const WorkMode(this.wire, this.label, this.description, this._unavailable);

  /// Value sent to `PATCH /taxi/drivers/work-mode`. Parcel and rider share
  /// `taxi`, so switching between them is local only.
  final String wire;
  final String label;
  final String description;
  final String _unavailable;

  bool get acceptsFood => this == WorkMode.food;

  /// True when the ride dispatcher (`Driver.isOnline`, taxi work mode) must be
  /// reachable — both parcel and passenger jobs arrive through it.
  bool get acceptsRides => this != WorkMode.food;

  /// Whether a ride-dispatcher offer belongs to this module. Parcel jobs go to
  /// [parcel] only, passenger rides to [rider] only.
  bool acceptsOffer({required bool isParcel}) {
    switch (this) {
      case WorkMode.food:
        return false;
      case WorkMode.parcel:
        return isParcel;
      case WorkMode.rider:
        return !isParcel;
    }
  }

  /// Whether a raw offer (FCM data map or socket payload) belongs to the
  /// module saved as [module] (`food | parcel | rider`, see
  /// `WorkModePreferenceStore`). Used where only the stored name is available
  /// — the background isolate — and kept identical to the native filter
  /// (`OfferOverlay.belongsToModule` in Kotlin):
  ///
  /// - `new_order` (food) → Food only.
  /// - `ride_request` → never Food; `serviceType` parcel/delivery → Parcel only,
  ///   any other kind (ride) → Rider only.
  /// - No saved module, an unknown module, an unknown push type, or a ride
  ///   push that does not say its kind → let through, as before. A real offer
  ///   must never be dropped because the payload was thinner than expected.
  static bool payloadBelongsTo(String? module, Map<String, dynamic> data) {
    final saved = tryParseModule(module);
    if (saved == null) return true;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'new_order') return saved == WorkMode.food;
    if (type != 'ride_request') return true;
    if (saved == WorkMode.food) return false;
    final kind = (data['serviceType'] ?? '').toString().trim().toLowerCase();
    if (kind.isEmpty) return true;
    return saved.acceptsOffer(isParcel: kind == 'parcel' || kind == 'delivery');
  }

  /// The server capability ([isAllowedFor]) this module needs.
  String get capability {
    switch (this) {
      case WorkMode.food:
        return 'delivery';
      case WorkMode.parcel:
        return 'parcel';
      case WorkMode.rider:
        return 'taxi';
    }
  }

  /// Reads a stored or wire value. Tolerant of the old names (`delivery`,
  /// `taxi`, `all`/`both`) so nothing previously stored fails to load.
  static WorkMode parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'parcel':
        return WorkMode.parcel;
      case 'rider':
      case 'ride':
      case 'taxi':
        return WorkMode.rider;
      default:
        return WorkMode.food;
    }
  }

  /// Like [parse], but null for anything that is not a module name — used for
  /// the local preference, where an unknown value should mean "no preference".
  static WorkMode? tryParseModule(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'food':
        return WorkMode.food;
      case 'parcel':
        return WorkMode.parcel;
      case 'rider':
        return WorkMode.rider;
      default:
        return null;
    }
  }

  /// Works out the app module from what the server stores.
  ///
  /// - `delivery` → [food].
  /// - `taxi` → the locally saved parcel/rider choice if still allowed, else by
  ///   capability (parcel only → parcel, otherwise rider).
  /// - `all` (legacy) → the local choice if allowed, else [food].
  static WorkMode resolve({
    required String serverWire,
    required Set<String> capabilities,
    WorkMode? preferred,
  }) {
    final wire = serverWire.trim().toLowerCase();
    final local =
        preferred != null && preferred.isAllowedFor(capabilities) ? preferred : null;
    if (wire == 'taxi') {
      if (local != null && local.wire == 'taxi') return local;
      final canParcel = WorkMode.parcel.isAllowedFor(capabilities);
      final canRide = WorkMode.rider.isAllowedFor(capabilities);
      return canParcel && !canRide ? WorkMode.parcel : WorkMode.rider;
    }
    if (wire == 'all') return local ?? WorkMode.food;
    return WorkMode.food;
  }

  /// The capability a driver must hold to select this module.
  ///
  /// Mirrors the server's guard (and dispatch's capability filter) so the UI
  /// greys a module out instead of letting the driver pick it and receive a
  /// 400 — or worse, be accepted and never sent a job.
  bool isAllowedFor(Set<String> capabilities) =>
      capabilities.contains(capability);

  String unavailableReason() => _unavailable;
}

/// The modules the rider has switched on — any combination of Food delivery,
/// Parcel delivery and Rider, at least one.
///
/// Exposes the same questions [WorkMode] answers (`acceptsFood`,
/// `acceptsOffer`, `wire`, ...) so filters ask "is this kind of job on?"
/// without caring how many modules are on.
///
/// Server mapping (k9 only knows `all | taxi | delivery`):
/// food only → `delivery`; parcel/rider without food → `taxi`; food plus
/// either → `all`. Parcel vs rider is filtered on the device.
class WorkModeSet {
  const WorkModeSet(this.modules);

  final Set<WorkMode> modules;

  static const food = WorkModeSet({WorkMode.food});

  bool contains(WorkMode mode) => modules.contains(mode);
  bool get isEmpty => modules.isEmpty;

  bool get acceptsFood => modules.contains(WorkMode.food);

  /// True when the ride dispatcher must be reachable (parcel or passenger).
  bool get acceptsRides =>
      modules.contains(WorkMode.parcel) || modules.contains(WorkMode.rider);

  /// Whether a ride-dispatcher offer belongs to an enabled module.
  bool acceptsOffer({required bool isParcel}) =>
      modules.contains(isParcel ? WorkMode.parcel : WorkMode.rider);

  /// Value for `PATCH /taxi/drivers/work-mode`.
  String get wire {
    if (acceptsFood && acceptsRides) return 'all';
    if (acceptsRides) return 'taxi';
    return 'delivery';
  }

  /// In display order: Food, Parcel, Rider.
  List<WorkMode> get ordered =>
      WorkMode.values.where(modules.contains).toList(growable: false);

  /// "Food delivery + Rider".
  String get label => ordered.map((m) => m.label).join(' + ');

  WorkModeSet toggled(WorkMode mode) => WorkModeSet(
        modules.contains(mode)
            ? (Set.of(modules)..remove(mode))
            : (Set.of(modules)..add(mode)),
      );

  /// Only the modules [capabilities] allow.
  WorkModeSet allowedBy(Set<String> capabilities) =>
      WorkModeSet(modules.where((m) => m.isAllowedFor(capabilities)).toSet());

  /// Stored form, also read by the Kotlin offer filter: `food,parcel,rider`.
  String encode() => ordered.map((m) => m.name).join(',');

  /// Reads [encode]'s output; also the old single-module values. Null when
  /// nothing usable is stored.
  static WorkModeSet? decode(String? raw) {
    final modules = (raw ?? '')
        .split(',')
        .map(WorkMode.tryParseModule)
        .whereType<WorkMode>()
        .toSet();
    return modules.isEmpty ? null : WorkModeSet(modules);
  }

  /// Works out the enabled modules from what the server stores plus the
  /// rider's saved choice (the server cannot tell parcel from rider).
  static WorkModeSet resolve({
    required String serverWire,
    required Set<String> capabilities,
    WorkModeSet? preferred,
  }) {
    final wire = serverWire.trim().toLowerCase();
    final allowedTaxi = {WorkMode.parcel, WorkMode.rider}
        .where((m) => m.isAllowedFor(capabilities))
        .toSet();
    final local = preferred?.allowedBy(capabilities);
    final localTaxi =
        local?.modules.where((m) => m != WorkMode.food).toSet() ?? const {};
    final taxiPart = localTaxi.isNotEmpty ? localTaxi : allowedTaxi;

    if (wire == 'taxi' && taxiPart.isNotEmpty) return WorkModeSet(taxiPart);
    if (wire == 'all') {
      final modules = {
        if (WorkMode.food.isAllowedFor(capabilities)) WorkMode.food,
        ...taxiPart,
      };
      return modules.isEmpty ? food : WorkModeSet(modules);
    }
    return food;
  }

  /// Same rule as [WorkMode.payloadBelongsTo], for the stored set.
  static bool payloadBelongsTo(String? stored, Map<String, dynamic> data) {
    final set = decode(stored);
    if (set == null) return true;
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'new_order') return set.acceptsFood;
    if (type != 'ride_request') return true;
    if (!set.acceptsRides) return false;
    final kind = (data['serviceType'] ?? '').toString().trim().toLowerCase();
    if (kind.isEmpty) return true;
    return set.acceptsOffer(isParcel: kind == 'parcel' || kind == 'delivery');
  }

  @override
  bool operator ==(Object other) =>
      other is WorkModeSet &&
      other.modules.length == modules.length &&
      other.modules.containsAll(modules);

  @override
  int get hashCode => Object.hashAllUnordered(modules);
}
