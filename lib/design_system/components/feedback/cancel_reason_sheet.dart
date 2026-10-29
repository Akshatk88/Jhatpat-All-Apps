import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';

/// Preset reasons for each kind of thing a customer can cancel.
class CancelReasons {
  CancelReasons._();

  static const food = [
    'Ordered by mistake',
    'Want to change items or address',
    'Delivery is taking too long',
    'Found a better price elsewhere',
    'Restaurant asked me to cancel',
  ];

  static const ride = [
    'Driver is taking too long',
    'Driver asked me to cancel',
    'Booked by mistake',
    'Changed my plans',
    'Found another ride',
  ];

  static const parcel = [
    'Captain is taking too long',
    'Booked by mistake',
    'Wrong pickup or drop address',
    'Parcel is not ready',
    'Changed my plans',
  ];

  static const service = [
    'Booked by mistake',
    'Professional is taking too long',
    'Want a different time',
    'No longer need the service',
  ];
}

/// Asks why the customer is cancelling. Returns the reason, or null when they
/// keep the order. A reason is mandatory: confirm stays disabled until one is
/// picked (or typed, for "Other").
Future<String?> askCancelReason(
  BuildContext context, {
  required String title,
  required List<String> reasons,
  String confirmLabel = 'Cancel',
  String keepLabel = 'Keep it',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CancelReasonSheet(
      title: title,
      reasons: reasons,
      confirmLabel: confirmLabel,
      keepLabel: keepLabel,
    ),
  );
}

class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet({
    required this.title,
    required this.reasons,
    required this.confirmLabel,
    required this.keepLabel,
  });

  final String title;
  final List<String> reasons;
  final String confirmLabel;
  final String keepLabel;

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  static const _other = '__other__';
  String? _picked;
  final _otherText = TextEditingController();

  @override
  void dispose() {
    _otherText.dispose();
    super.dispose();
  }

  String? get _reason {
    if (_picked == null) return null;
    if (_picked == _other) {
      final t = _otherText.text.trim();
      return t.isEmpty ? null : t;
    }
    return _picked;
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title.tr,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Please tell us why you are cancelling'.tr,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            for (final r in [...widget.reasons, _other])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _picked == r
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _picked == r ? const Color(0xFFFF6464) : null,
                ),
                title: Text(r == _other ? 'Other'.tr : r.tr),
                onTap: () => setState(() => _picked = r),
              ),
            if (_picked == _other)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: TextField(
                  controller: _otherText,
                  autofocus: true,
                  maxLength: 200,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Write your reason'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(widget.keepLabel.tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6464),
                      foregroundColor: Colors.white,
                    ),
                    onPressed:
                        reason == null ? null : () => Navigator.pop(context, reason),
                    child: Text(widget.confirmLabel.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
