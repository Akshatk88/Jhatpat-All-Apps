import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:food_user_application/core/error/result.dart';

import '../../data/ride_payment_qr_repository.dart';
import 'money_ui.dart';

/// Shows a UPI QR for the passenger to scan and resolves `true` once
/// Razorpay confirms the payment (k9 `/taxi/drivers/payments/qr/status`),
/// `false`/`null` if the driver closes it first.
///
/// Wiring (rides feature): from the fare-collection step of a cash ride,
///
/// ```dart
/// final paid = await showRideQrPaymentSheet(context, rideId: ride.id, amount: ride.fare);
/// if (paid == true) {
///   // complete with paymentMethod 'online', collectedByDriver false —
///   // k9 settles an online ride whose QR it has verified as paid.
/// }
/// ```
Future<bool?> showRideQrPaymentSheet(
  BuildContext context, {
  required String rideId,
  required double amount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => RideQrPaymentSheet(rideId: rideId, amount: amount),
  );
}

class RideQrPaymentSheet extends ConsumerStatefulWidget {
  const RideQrPaymentSheet({
    super.key,
    required this.rideId,
    required this.amount,
  });

  final String rideId;
  final double amount;

  @override
  ConsumerState<RideQrPaymentSheet> createState() => _RideQrPaymentSheetState();
}

enum _Phase { creating, waiting, paid, failed }

class _RideQrPaymentSheetState extends ConsumerState<RideQrPaymentSheet> {
  static const _pollEvery = Duration(seconds: 4);

  _Phase _phase = _Phase.creating;
  RideQrPayment? _qr;
  Uint8List? _qrBytes;
  String? _error;
  Timer? _poll;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _poll?.cancel();
    setState(() {
      _phase = _Phase.creating;
      _error = null;
    });
    final result = await ref
        .read(ridePaymentQrRepositoryProvider)
        .create(rideId: widget.rideId, amount: widget.amount);
    if (!mounted) return;
    result.when(
      success: (qr) {
        setState(() {
          _qr = qr;
          _qrBytes = _decodeDataUrl(qr.imageUrl);
          _phase = _Phase.waiting;
        });
        _poll = Timer.periodic(_pollEvery, (_) => _checkStatus());
      },
      failure: (e) => setState(() {
        _phase = _Phase.failed;
        _error = e.message;
      }),
    );
  }

  Future<void> _checkStatus({bool manual = false}) async {
    if (_polling || _phase != _Phase.waiting) return;
    _polling = true;
    final result =
        await ref.read(ridePaymentQrRepositoryProvider).status(widget.rideId);
    _polling = false;
    if (!mounted || _phase != _Phase.waiting) return;
    result.when(
      success: (status) {
        if (status.paid) {
          _poll?.cancel();
          setState(() => _phase = _Phase.paid);
        } else if (status.isDead) {
          _poll?.cancel();
          setState(() {
            _phase = _Phase.failed;
            _error = 'This QR has ${status.status}. Generate a new one.';
          });
        } else if (manual) {
          _snack('Payment not received yet');
        }
      },
      // A transient failure must not end the wait; the next tick retries.
      failure: (e) {
        if (manual) _snack(e.message);
      },
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Uint8List? _decodeDataUrl(String url) {
    if (!url.startsWith('data:')) return null;
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 18.h),
              Text(
                'Scan to pay',
                style: TextStyle(
                  color: subText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.sp,
                ),
              ),
              SizedBox(height: 6.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRupees(_qr?.amount ?? widget.amount),
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 34.sp,
                    height: 1,
                  ),
                ),
              ),
              SizedBox(height: 18.h),
              _body(textColor, subText),
              SizedBox(height: 20.h),
              ..._actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Color textColor, Color subText) {
    switch (_phase) {
      case _Phase.creating:
        return SizedBox(
          height: 220.r,
          child: const Center(
            child: CircularProgressIndicator(color: MoneyColors.yellow),
          ),
        );
      case _Phase.failed:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Column(
            children: [
              Icon(Icons.error_outline_rounded, size: 40.sp, color: Colors.redAccent),
              SizedBox(height: 10.h),
              Text(
                _error ?? 'Something went wrong',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 13.sp),
              ),
            ],
          ),
        );
      case _Phase.paid:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Column(
            children: [
              Icon(Icons.check_circle_rounded, size: 56.sp, color: MoneyColors.green),
              SizedBox(height: 10.h),
              Text(
                'Payment received',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16.sp,
                ),
              ),
            ],
          ),
        );
      case _Phase.waiting:
        final qr = _qr!;
        final size = 220.r;
        final image = _qrBytes != null
            ? Image.memory(_qrBytes!, width: size, height: size, fit: BoxFit.contain)
            : Image.network(
                qr.imageUrl,
                width: size,
                height: size,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : SizedBox(
                        width: size,
                        height: size,
                        child: const Center(
                          child: CircularProgressIndicator(color: MoneyColors.yellow),
                        ),
                      ),
                errorBuilder: (_, _, _) => SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: Text(
                      'QR image failed to load',
                      style: TextStyle(color: subText, fontSize: 12.sp),
                    ),
                  ),
                ),
              );
        return Column(
          children: [
            Container(
              padding: EdgeInsets.all(10.r),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: MoneyColors.yellow, width: 2),
              ),
              child: image,
            ),
            SizedBox(height: 14.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14.r,
                  height: 14.r,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MoneyColors.yellow,
                  ),
                ),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    'Waiting for the passenger to pay…',
                    style: TextStyle(color: subText, fontSize: 12.sp),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  List<Widget> _actions() {
    switch (_phase) {
      case _Phase.creating:
        return [_secondary('Cancel', () => Navigator.of(context).pop(false))];
      case _Phase.waiting:
        return [
          _primary('I have been paid — check', () => _checkStatus(manual: true)),
          SizedBox(height: 8.h),
          _secondary('Cancel', () => Navigator.of(context).pop(false)),
        ];
      case _Phase.failed:
        return [
          _primary('Generate new QR', _create),
          SizedBox(height: 8.h),
          _secondary('Cancel', () => Navigator.of(context).pop(false)),
        ];
      case _Phase.paid:
        return [_primary('Done', () => Navigator.of(context).pop(true))];
    }
  }

  Widget _primary(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: MoneyButtons.primary(),
          child: Text(label, textAlign: TextAlign.center),
        ),
      );

  Widget _secondary(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          child: Text(label, style: TextStyle(fontSize: 13.sp)),
        ),
      );
}
