import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const _red = Color(0xFFF04438);

/// Asks the driver why they are cancelling an accepted ride.
///
/// Resolves to the reason text to send as `{ reason }` to
/// `POST /taxi/drivers/rides/:id/cancel`, or null if the driver backs out.
/// A reason is required: one of the fixed list, or free text for "Other".
Future<String?> showDriverCancelReasonSheet(
  BuildContext context, {
  required String partyLabel,
  required String note,
  bool rejectOffer = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CancelReasonSheet(
      partyLabel: partyLabel,
      note: note,
      rejectOffer: rejectOffer,
    ),
  );
}

class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet({
    required this.partyLabel,
    required this.note,
    this.rejectOffer = false,
  });

  final String partyLabel;
  final String note;
  final bool rejectOffer;

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  static const _other = 'Other';
  static const _maxOther = 200;

  List<String> get _reasons => widget.rejectOffer
      ? const [
          "Too far",
          "Busy with another order",
          "Vehicle problem",
          "Taking a break",
          "Wrong area",
          _other,
        ]
      : [
          '${widget.partyLabel} not reachable',
          '${widget.partyLabel} asked to cancel',
          'Wrong pickup location',
          'Vehicle problem',
          'Too far from pickup',
          'Emergency',
          _other,
        ];

  final _otherCtrl = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _selected != null &&
      (_selected != _other || _otherCtrl.text.trim().length >= 3);

  void _confirm() {
    if (!_valid) return;
    final text = _selected == _other ? _otherCtrl.text.trim() : _selected!;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final muted = isDark ? Colors.grey[400] : Colors.grey[600];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181C25) : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 22.h, 24.w, 4.h),
                  child: Text(
                    widget.rejectOffer
                        ? "Why did you reject this job?"
                        : "Why are you cancelling?",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18.sp,
                      color: fg,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 8.h),
                  child: Text(
                    widget.rejectOffer
                        ? widget.note
                        : 'The ${widget.partyLabel.toLowerCase()} is waiting and will '
                            'be matched with another driver. ${widget.note}',
                    style: TextStyle(fontSize: 13.sp, color: muted),
                  ),
                ),
                RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  child: Column(
                    children: [
                      for (final r in _reasons)
                        RadioListTile<String>(
                          value: r,
                          activeColor: _red,
                          dense: true,
                          title: Text(
                            r,
                            style: TextStyle(fontSize: 14.sp, color: fg),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_selected == _other)
                  Padding(
                    padding: EdgeInsets.fromLTRB(24.w, 4.h, 24.w, 8.h),
                    child: TextField(
                      controller: _otherCtrl,
                      maxLength: _maxOther,
                      maxLines: 3,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 14.sp, color: fg),
                      decoration: InputDecoration(
                        hintText: 'Tell us the reason (required)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 4.h),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _red,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                      onPressed: _valid ? _confirm : null,
                      child: Text(widget.rejectOffer ? 'Submit reason' : 'Confirm cancellation'),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
                  child: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(widget.rejectOffer ? 'Skip' : 'Keep this ride'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
