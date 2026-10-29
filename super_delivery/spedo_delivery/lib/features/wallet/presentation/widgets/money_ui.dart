import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Jhatpat money accents shared by the ride wallet, QR collection and
/// incentives screens.
class MoneyColors {
  MoneyColors._();

  static const Color yellow = Color(0xFFFFB800);
  static const Color black = Color(0xFF111111);
  static const Color green = Color(0xFF1EBE5D);
  static const Color red = Color(0xFFE53935);
}

class MoneyButtons {
  MoneyButtons._();

  static ButtonStyle primary() => ElevatedButton.styleFrom(
        backgroundColor: MoneyColors.yellow,
        foregroundColor: MoneyColors.black,
        disabledBackgroundColor: MoneyColors.yellow.withValues(alpha: 0.4),
        disabledForegroundColor: MoneyColors.black.withValues(alpha: 0.5),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
        textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.sp),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      );

  static ButtonStyle dark() => ElevatedButton.styleFrom(
        backgroundColor: MoneyColors.black,
        foregroundColor: MoneyColors.yellow,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
        textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.sp),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      );

  static ButtonStyle outlined(Color color) => OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
        textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.sp),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      );
}

/// `₹1,234.50` — Indian digit grouping, 2 decimals (0 when [decimals] is 0).
String formatRupees(double value, {int decimals = 2}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0];
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final chunks = <String>[];
    while (rest.length > 2) {
      chunks.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) chunks.insert(0, rest);
    grouped = '${chunks.join(',')},$last3';
  }
  final body = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  return '${negative ? '-' : ''}₹$body';
}

/// Compact amount: no decimals when whole, else 2.
String formatRupeesShort(double value) =>
    formatRupees(value, decimals: value == value.roundToDouble() ? 0 : 2);

/// Asks for an amount in rupees between [min] and [max] (either may be null).
/// Returns null when cancelled.
Future<double?> showAmountDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String? helper,
  double? min,
  double? max,
  String? maxError,
  List<double> quickAmounts = const [],
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _AmountDialog(
      title: title,
      actionLabel: actionLabel,
      helper: helper,
      min: min,
      max: max,
      maxError: maxError,
      quickAmounts: quickAmounts,
    ),
  );
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.actionLabel,
    required this.helper,
    required this.min,
    required this.max,
    required this.maxError,
    required this.quickAmounts,
  });

  final String title;
  final String actionLabel;
  final String? helper;
  final double? min;
  final double? max;
  final String? maxError;
  final List<double> quickAmounts;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final amt = double.tryParse(value ?? '');
    if (amt == null || amt <= 0) return 'Enter a valid amount';
    final min = widget.min;
    final max = widget.max;
    if (min != null && min > 0 && amt < min) {
      return 'Minimum is ${formatRupeesShort(min)}';
    }
    if (max != null && amt > max) {
      return widget.maxError ?? 'Maximum is ${formatRupeesShort(max)}';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(double.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                prefixText: '₹ ',
                labelText: 'Amount',
                helperText: widget.helper,
                helperMaxLines: 3,
                errorMaxLines: 2,
              ),
              validator: _validate,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (widget.quickAmounts.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  for (final amount in widget.quickAmounts)
                    ActionChip(
                      label: Text(formatRupeesShort(amount)),
                      onPressed: () =>
                          _controller.text = amount.toStringAsFixed(0),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: MoneyButtons.primary(),
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
