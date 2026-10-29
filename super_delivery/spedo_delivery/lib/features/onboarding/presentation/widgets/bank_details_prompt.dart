import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import 'onboarding_ui.dart';

/// After approval: asks once — per partner, remembered on the device — for
/// payout details when the partner has neither a bank account nor a UPI id,
/// and hands off to the existing bank form on Driver Details
/// (`PATCH /food/delivery/profile/bank-details`).
///
/// Renders nothing; drop it anywhere inside the approved shell.
class BankDetailsPrompt extends ConsumerStatefulWidget {
  const BankDetailsPrompt({super.key});

  @override
  ConsumerState<BankDetailsPrompt> createState() => _BankDetailsPromptState();
}

class _BankDetailsPromptState extends ConsumerState<BankDetailsPrompt> {
  bool _handled = false;

  static String _key(String partnerId) => 'bank_details_prompted_$partnerId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    if (_handled || !mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) return;
    final user = auth.user;
    if (user.id.isEmpty || user.hasBankDetails) return;
    _handled = true;

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (prefs.getBool(_key(user.id)) == true || !mounted) return;
    await prefs.setBool(_key(user.id), true);
    if (!mounted) return;

    final addNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: OnboardingColors.brand.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.account_balance_rounded,
            color: OnboardingColors.text(ctx),
            size: 28.sp,
          ),
        ),
        title: const Text('Add your payout details'),
        content: const Text(
          'Add your bank account so your earnings can be paid out. '
          'Withdrawals need it.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OnboardingColors.brand,
              foregroundColor: OnboardingColors.onBrand,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add bank details'),
          ),
        ],
      ),
    );
    if (addNow == true && mounted) {
      // Driver Details holds the bank card and its edit form.
      context.push('/driver-details');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The partner can become authenticated after this mounted (e.g. a status
    // refresh), so look again whenever the auth state changes.
    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthAuthenticated) _maybePrompt();
    });
    return const SizedBox.shrink();
  }
}
