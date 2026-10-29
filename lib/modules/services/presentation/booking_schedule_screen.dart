import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/booking_draft_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// Step 2 of the funnel: where, and when.
///
/// The address is collected here rather than reused from the super app's shared
/// address book, because the two shapes are genuinely different — the shared
/// book has `street`/`zipCode` and no pincode or landmark, while SP requires
/// `addressLine1`, `city`, `state` and `pincode` and its dispatcher geocodes
/// the result to find nearby professionals. A silent translation would produce
/// bookings nobody can be dispatched to. Saved SP addresses (from
/// `GET /sp/users/profile`) are offered as one-tap fills, which covers the
/// repeat case.
class BookingScheduleScreen extends ConsumerStatefulWidget {
  const BookingScheduleScreen({super.key});

  @override
  ConsumerState<BookingScheduleScreen> createState() =>
      _BookingScheduleScreenState();
}

class _BookingScheduleScreenState extends ConsumerState<BookingScheduleScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _line1;
  late final TextEditingController _line2;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _landmark;
  late final TextEditingController _notes;

  DateTime? _date;
  SpTimeSlot? _slot;

  /// Kept so the address's coordinates survive a one-tap fill. The dispatcher
  /// prefers `lat`/`lng` over geocoding the text, and dropping them would make
  /// partner discovery measurably worse.
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(bookingDraftProvider);
    final address = draft.address;

    _line1 = TextEditingController(text: address?.addressLine1 ?? '');
    _line2 = TextEditingController(text: address?.addressLine2 ?? '');
    _city = TextEditingController(text: address?.city ?? '');
    _state = TextEditingController(text: address?.state ?? '');
    _pincode = TextEditingController(text: address?.pincode ?? '');
    _landmark = TextEditingController(text: address?.landmark ?? '');
    _notes = TextEditingController(text: draft.notes);
    _lat = address?.lat;
    _lng = address?.lng;

    _date = draft.date;
    _slot = draft.slot;
  }

  @override
  void dispose() {
    for (final controller in [
      _line1, _line2, _city, _state, _pincode, _landmark, _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fillFrom(SpBookingAddress address) {
    setState(() {
      _line1.text = address.addressLine1;
      _line2.text = address.addressLine2;
      _city.text = address.city;
      _state.text = address.state;
      _pincode.text = address.pincode;
      _landmark.text = address.landmark;
      _lat = address.lat;
      _lng = address.lng;
    });
  }

  SpBookingAddress get _address => SpBookingAddress(
        addressLine1: _line1.text.trim(),
        addressLine2: _line2.text.trim(),
        city: _city.text.trim(),
        state: _state.text.trim(),
        pincode: _pincode.text.trim(),
        landmark: _landmark.text.trim(),
        lat: _lat,
        lng: _lng,
      );

  void _continue() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_date == null || _slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please pick a date and an arrival window.'.tr)),
      );
      return;
    }

    ref.read(bookingDraftProvider.notifier)
      ..setAddress(_address)
      ..setSchedule(date: _date!, slot: _slot!)
      ..setNotes(_notes.text.trim());

    // Guard rather than assume: entering this screen without a service (a
    // restored draft from an older build, say) would otherwise create a
    // booking with no serviceId and fail server-side validation.
    if (!ref.read(bookingDraftProvider).canReview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please pick a service first.'.tr)),
      );
      context.go(ServicesRoutePaths.home);
      return;
    }

    context.push(ServicesRoutePaths.review);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final saved = ref.watch(spProfileProvider).value?.addresses ?? const [];

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('When & where'.tr),
        backgroundColor: spSurface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (draft.service != null)
              SpCard(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.handyman_rounded, color: spAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${draft.service!.title}'
                        '${draft.quantity > 1 ? '  ×${draft.quantity}' : ''}',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: spTextPrimary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const _Heading('Service address'),

            if (saved.isNotEmpty)
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: saved.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ActionChip(
                    avatar: const Icon(Icons.place_rounded, size: 16, color: spAccent),
                    label: Text(
                      saved[index].addressLine1.isEmpty
                          ? saved[index].type
                          : saved[index].addressLine1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _fillFrom(saved[index]),
                  ),
                ),
              ),

            _Field(controller: _line1, label: 'House / flat, building', required: true),
            _Field(controller: _line2, label: 'Area, street (optional)'),
            _Field(controller: _landmark, label: 'Landmark (optional)'),
            Row(
              children: [
                Expanded(child: _Field(controller: _city, label: 'City', required: true)),
                Expanded(child: _Field(controller: _state, label: 'State', required: true)),
              ],
            ),
            _Field(
              controller: _pincode,
              label: 'Pincode',
              required: true,
              keyboardType: TextInputType.number,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Required'.tr;
                // Indian PIN codes are 6 digits and never start with 0.
                if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(text)) {
                  return 'Enter a valid 6-digit pincode'.tr;
                }
                return null;
              },
            ),

            const _Heading('Preferred date'),
            _DateStrip(
              selected: _date,
              onSelected: (date) => setState(() => _date = date),
            ),

            const _Heading('Arrival window'),
            _SlotGrid(
              date: _date,
              selected: _slot,
              onSelected: (slot) => setState(() => _slot = slot),
            ),

            const _Heading('Anything we should know? (optional)'),
            _Field(
              controller: _notes,
              label: 'e.g. AC is on the second floor balcony',
              maxLines: 3,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: spAccent,
                foregroundColor: spOnAccent,
                elevation: 0,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Review booking'.tr,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          text.tr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: spTextPrimary(context),
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.required = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.words,
        validator: validator ??
            (required
                ? (value) => (value?.trim().isEmpty ?? true) ? 'Required'.tr : null
                : null),
        decoration: InputDecoration(
          labelText: label.tr,
          filled: true,
          fillColor: spSurface(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: spBorder(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: spBorder(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: spAccent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// The next 14 days.
class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelected});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final date = start.add(Duration(days: index));
          final isSelected = selected != null &&
              selected!.year == date.year &&
              selected!.month == date.month &&
              selected!.day == date.day;

          return InkWell(
            onTap: () => onSelected(date),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 62,
              decoration: BoxDecoration(
                color: isSelected ? spAccent : spSurface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? spAccent : spBorder(context),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    index == 0 ? 'Today'.tr : DateFormat('EEE').format(date),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? spOnAccent : spTextSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? spOnAccent : spTextPrimary(context),
                    ),
                  ),
                  Text(
                    DateFormat('MMM').format(date),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isSelected ? Colors.black54 : spTextSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.date,
    required this.selected,
    required this.onSelected,
  });

  final DateTime? date;
  final SpTimeSlot? selected;
  final ValueChanged<SpTimeSlot> onSelected;

  /// A window that has already started today cannot be booked. Parsed from the
  /// slot's own label so the list stays the single source of the windows.
  bool _isPast(SpTimeSlot slot) {
    if (date == null) return false;
    final now = DateTime.now();
    if (date!.year != now.year || date!.month != now.month || date!.day != now.day) {
      return false;
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(slot.start);
    if (match == null) return false;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final isPm = match.group(3) == 'PM';
    if (isPm && hour != 12) hour += 12;
    if (!isPm && hour == 12) hour = 0;
    return DateTime(now.year, now.month, now.day, hour, minute).isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final slot in SpTimeSlot.options)
            Builder(builder: (context) {
              final past = _isPast(slot);
              final isSelected = selected == slot;
              return InkWell(
                onTap: past ? null : () => onSelected(slot),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: isSelected ? spAccent : spSurface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? spAccent : spBorder(context),
                    ),
                  ),
                  child: Text(
                    slot.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: past
                          ? spTextSecondary(context).withValues(alpha: 0.45)
                          : (isSelected ? spOnAccent : spTextPrimary(context)),
                      decoration: past ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
