import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/core/services/location_service.dart';
import 'package:food_user_application/features/safety/application/emergency_contacts_controller.dart';
import 'package:food_user_application/features/safety/data/safety_repository.dart';
import 'package:food_user_application/features/support/data/support_repository.dart';

const _sosRed = Color(0xFFE53935);
const _jhatpatYellow = Color(0xFFFFB800);

/// The national emergency number. Always offered, whatever the server says.
const String kEmergencyNumber = '112';

/// What the SOS should tell the safety desk about the job in progress.
class SosRequest {
  const SosRequest({
    this.rideId,
    this.serviceType = 'general',
    this.pickupAddress,
    this.dropAddress,
    this.notes,
  });

  /// Taxi ride / parcel id. Food orders have none — they go as `general` with
  /// the order code in [notes].
  final String? rideId;

  /// ride | parcel | general.
  final String serviceType;
  final String? pickupAddress;
  final String? dropAddress;
  final String? notes;
}

/// Confirm, raise the SOS with the current position, then offer calls.
Future<void> runSosFlow(
  BuildContext context,
  SosRequest request,
) async {
  HapticService.heavy();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.sos_rounded, color: _sosRed, size: 40),
      title: const Text('Send SOS alert?'),
      content: const Text(
        'Jhatpat\'s safety team will be alerted with your current location '
        'and this trip\'s details. Use this only in an emergency.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _sosRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Send SOS'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SosSheet(request: request),
  );
}

/// A round red SOS button, sized to sit beside the other map-overlay buttons.
class SosButton extends StatelessWidget {
  const SosButton({super.key, required this.request, this.size});

  /// Built lazily so it reflects the trip at the moment of the tap.
  final SosRequest Function() request;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final d = size ?? 40.r;
    return Semantics(
      button: true,
      label: 'SOS emergency alert',
      child: GestureDetector(
        onTap: () => runSosFlow(context, request()),
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _sosRed,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _sosRed.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.all(4.r),
              child: Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.sp,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SendState { sending, sent, failed }

class _SosSheet extends ConsumerStatefulWidget {
  const _SosSheet({required this.request});

  final SosRequest request;

  @override
  ConsumerState<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends ConsumerState<_SosSheet> {
  _SendState _state = _SendState.sending;
  String? _error;
  bool _locationShared = false;

  /// Helplines the operator configured (`/food/delivery/emergency-help`):
  /// label -> number. Empty until loaded, or if none are set.
  List<(String, String)> _helplines = const [];

  @override
  void initState() {
    super.initState();
    _send();
    _loadHelplines();
  }

  Future<Position?> _position() async {
    final cached = ref.read(locationServiceProvider).lastPosition;
    if (cached != null) return cached;
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition()
              .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _send() async {
    setState(() {
      _state = _SendState.sending;
      _error = null;
    });
    final pos = await _position();
    final r = widget.request;
    final result = await ref.read(safetyRepositoryProvider).triggerSos(
          rideId: r.rideId,
          serviceType: r.serviceType,
          lat: pos?.latitude,
          lng: pos?.longitude,
          pickupAddress: r.pickupAddress,
          dropAddress: r.dropAddress,
          notes: r.notes,
        );
    if (!mounted) return;
    result.when(
      success: (_) {
        HapticService.heavy();
        setState(() {
          _state = _SendState.sent;
          _locationShared = pos != null;
        });
      },
      failure: (e) => setState(() {
        _state = _SendState.failed;
        _error = e.message;
      }),
    );
  }

  Future<void> _loadHelplines() async {
    final result = await ref.read(supportRepositoryProvider).getEmergencyHelp();
    if (!mounted) return;
    result.when(
      success: (data) {
        final lines = <(String, String)>[];
        void add(String label, Object? value) {
          final v = value?.toString().trim() ?? '';
          if (v.isNotEmpty && v != kEmergencyNumber) lines.add((label, v));
        }

        add('Accident helpline', data['accidentHelpline']);
        add('Medical emergency', data['medicalEmergency']);
        add('Police', data['contactPolice']);
        setState(() => _helplines = lines);
      },
      failure: (_) {},
    );
  }

  Future<void> _dial(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialer. Call $phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[700];
    final contacts =
        ref.watch(emergencyContactsControllerProvider).value?.contacts ?? const [];

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatus(textColor, subText),
              SizedBox(height: 18.h),
              SizedBox(
                height: 54.h,
                child: ElevatedButton.icon(
                  onPressed: () => _dial(kEmergencyNumber),
                  icon: Icon(Icons.call_rounded, size: 20.sp),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Call $kEmergencyNumber (Emergency)',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.sp,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _sosRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27.r),
                    ),
                  ),
                ),
              ),
              for (final (label, phone) in _helplines)
                _callRow(Icons.support_agent_rounded, label, phone, textColor, subText),
              for (final c in contacts)
                _callRow(Icons.person_rounded, c.name, c.phone, textColor, subText),
              SizedBox(height: 8.h),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(Color textColor, Color? subText) {
    final (IconData icon, Color color, String title, String body) = switch (_state) {
      _SendState.sending => (
          Icons.sos_rounded,
          _sosRed,
          'Sending SOS…',
          'Alerting Jhatpat\'s safety team.',
        ),
      _SendState.sent => (
          Icons.check_circle_rounded,
          const Color(0xFF1EBE5D),
          'SOS sent',
          _locationShared
              ? 'The safety team has your location and trip details. '
                  'If you are in danger, call $kEmergencyNumber now.'
              : 'The safety team has your trip details (your location was '
                  'unavailable). If you are in danger, call $kEmergencyNumber now.',
        ),
      _SendState.failed => (
          Icons.error_rounded,
          _sosRed,
          'SOS not sent',
          _error ?? 'Something went wrong.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_state == _SendState.sending)
              SizedBox(
                width: 24.r,
                height: 24.r,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _sosRed,
                ),
              )
            else
              Icon(icon, color: color, size: 26.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18.sp,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Text(body, style: TextStyle(color: subText, fontSize: 13.sp, height: 1.35)),
        if (_state == _SendState.failed) ...[
          SizedBox(height: 10.h),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _send,
              icon: Icon(Icons.refresh_rounded, size: 18.sp),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                backgroundColor: _jhatpatYellow,
                side: BorderSide.none,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _callRow(
    IconData icon,
    String label,
    String phone,
    Color textColor,
    Color? subText,
  ) {
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () => _dial(phone),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: (subText ?? Colors.grey).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20.sp, color: textColor),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                        ),
                      ),
                      Text(phone, style: TextStyle(color: subText, fontSize: 12.sp)),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(8.r),
                  decoration: const BoxDecoration(
                    color: _jhatpatYellow,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.call_rounded, size: 16.sp, color: Colors.black),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
