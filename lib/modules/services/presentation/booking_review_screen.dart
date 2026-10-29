import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/booking_draft_controller.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/application/sp_payment_controller.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// Step 3: confirm the price, pick how to pay, create the booking.
///
/// The order of operations matters and is not interchangeable:
///
///   1. create the booking  (it lands in `searching`; the server starts hunting
///      for a professional in the background immediately)
///   2. settle payment, if the method is one that charges now
///   3. route to the searching screen
///
/// Payment cannot come first — `POST /sp/payments/create-order` takes a
/// `bookingId`, so the booking has to exist. And a payment failure must not
/// discard the booking: the customer can still pay at the door, so a failed
/// charge downgrades to "pay after service" rather than throwing the job away.
class BookingReviewScreen extends ConsumerStatefulWidget {
  const BookingReviewScreen({super.key});

  @override
  ConsumerState<BookingReviewScreen> createState() => _BookingReviewScreenState();
}

class _BookingReviewScreenState extends ConsumerState<BookingReviewScreen> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);

    final draft = ref.read(bookingDraftProvider);
    final method = draft.paymentMethod;

    final bookingId = await ref.read(bookingDraftProvider.notifier).submit();

    if (!mounted) return;

    if (bookingId == null) {
      setState(() => _busy = false);
      final error = ref.read(bookingDraftProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Could not create the booking.'.tr)),
      );
      return;
    }

    // The booking exists from here on. Whatever happens to the payment, the
    // customer must end up on the searching screen, not stranded on this one.
    final payment = await ref
        .read(spPaymentControllerProvider)
        .settle(bookingId: bookingId, method: method);

    if (!mounted) return;

    // Make the new booking visible in the list and on the home card.
    unawaited(ref.read(myBookingsProvider.notifier).refresh());

    if (!payment.isOk && payment.message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('{message} You can still pay after the service.'.trArgs({'message': payment.message})),
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (payment.message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payment.message)),
      );
    }

    // `go`, not `push`: the funnel is finished and must not be reachable with
    // the back button — returning to a review screen whose draft has been
    // cleared would show an empty summary and a Confirm that creates nothing.
    context.go(ServicesRoutePaths.searchingFor(bookingId));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    final walletPaise = ref.watch(spWalletBalanceProvider).value ?? 0;
    final profile = ref.watch(spProfileProvider).value;
    final penaltyPaise = profile?.walletPenaltyPaise ?? 0;

    if (draft.service == null || !draft.canReview) {
      // A restored-but-incomplete draft, or a deep link straight here.
      return Scaffold(
        appBar: AppBar(title: Text('Review'.tr)),
        body: SpErrorState(
          message: 'Your booking details are incomplete.'.tr,
          onRetry: () => context.go(ServicesRoutePaths.home),
        ),
      );
    }

    final service = draft.service!;
    final totalPaise = draft.totalPaise + penaltyPaise;
    final walletCovers = walletPaise >= totalPaise;

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Review & confirm'.tr),
        backgroundColor: spSurface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 16, bottom: 32),
        children: [
          SpCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.handyman_rounded, color: spAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: spTextPrimary(context),
                        ),
                      ),
                      if (draft.quantity > 1)
                        Text(
                          'Quantity {count}'.trArgs({'count': draft.quantity}),
                          style: TextStyle(
                            fontSize: 13,
                            color: spTextSecondary(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconRow(
                  icon: Icons.event_rounded,
                  title: DateFormat('EEEE, d MMMM').format(draft.date!),
                  subtitle: draft.slot!.label,
                ),
                const SizedBox(height: 14),
                _IconRow(
                  icon: Icons.place_rounded,
                  title: 'Service address'.tr,
                  subtitle: draft.address!.singleLine,
                ),
                if (draft.notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _IconRow(
                    icon: Icons.sticky_note_2_rounded,
                    title: 'Your note'.tr,
                    subtitle: draft.notes,
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pop(),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Change'.tr,
                        style: TextStyle(color: spAccentText(context), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),

          SpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bill summary'.tr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: spTextPrimary(context),
                  ),
                ),
                const SizedBox(height: 8),
                SpPriceRow(
                  label: '${'Service'.tr}${draft.quantity > 1 ? ' ×${draft.quantity}' : ''}',
                  pricePaise: draft.itemsPaise,
                ),
                if (draft.savingsPaise > 0)
                  SpPriceRow(
                    label: 'Discount'.tr,
                    pricePaise: draft.savingsPaise,
                    isCredit: true,
                  ),
                if (draft.taxPaise > 0)
                  SpPriceRow(label: 'Taxes'.tr, pricePaise: draft.taxPaise),
                SpPriceRow(
                  label: 'Visiting charge'.tr,
                  pricePaise: BookingDraft.visitingChargesPaise,
                ),
                // Surfaced rather than hidden: the backend adds any outstanding
                // cancellation penalty to this booking's total automatically,
                // and being charged an unexplained extra is worse than being
                // told about it here.
                if (penaltyPaise > 0)
                  SpPriceRow(
                    label: 'Previous cancellation fee'.tr,
                    pricePaise: penaltyPaise,
                  ),
                Divider(color: spBorder(context), height: 24),
                SpPriceRow(
                  label: 'Total'.tr,
                  pricePaise: totalPaise,
                  emphasised: true,
                ),
                const SizedBox(height: 6),
                Text(
                  'The final bill may change if the professional finds extra work or parts are needed. You approve it before paying.'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: spTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'How would you like to pay?'.tr,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),

          for (final method in SpPaymentMethod.values)
            if (method != SpPaymentMethod.online && (method != SpPaymentMethod.plan || (profile?.planActive ?? false)))
              _PaymentOption(
                method: method,
                selected: draft.paymentMethod == method,
                // The wallet is offered only when it actually covers the job.
                // The backend rejects a short balance with a 400, and finding
                // that out after tapping Confirm is a bad way to learn it.
                enabled: method != SpPaymentMethod.wallet || walletCovers,
                subtitle: switch (method) {
                  SpPaymentMethod.wallet => walletCovers
                      ? 'Balance {amount}'.trArgs({'amount': formatPaise(walletPaise)})
                      : 'Balance {amount} — not enough'.trArgs({'amount': formatPaise(walletPaise)}),
                  SpPaymentMethod.payAtHome =>
                    'Cash or online once the work is done'.tr,
                  SpPaymentMethod.online => 'Card or net banking'.tr,
                  SpPaymentMethod.plan => profile?.planName ?? 'Active plan'.tr,
                },
                onTap: () => ref
                    .read(bookingDraftProvider.notifier)
                    .setPaymentMethod(method),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _busy ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: spAccent,
                foregroundColor: spOnAccent,
                disabledBackgroundColor: spAccent.withValues(alpha: 0.5),
                elevation: 0,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(spOnAccent),
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Confirm booking · {amount}'.trArgs({'amount': formatPaise(totalPaise)}),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: spTextSecondary(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: spTextPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: spTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.subtitle,
    required this.onTap,
  });

  final SpPaymentMethod method;
  final bool selected;
  final bool enabled;
  final String subtitle;
  final VoidCallback onTap;

  IconData get _icon => switch (method) {
        SpPaymentMethod.payAtHome => Icons.home_work_rounded,
        SpPaymentMethod.wallet => Icons.account_balance_wallet_rounded,
        SpPaymentMethod.online => Icons.credit_card_rounded,
        SpPaymentMethod.plan => Icons.workspace_premium_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SpCard(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Icon(_icon, size: 20, color: selected ? spAccent : spTextSecondary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label.tr,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: spTextPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: spTextSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? spAccent : spTextSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
