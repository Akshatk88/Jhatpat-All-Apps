import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';

/// Collects a rating and optional review for a completed booking.
///
/// A sheet rather than a screen: it has one job, it is reached from two places
/// (the bookings list and the tracking screen), and neither should lose its
/// scroll position to it.
Future<void> showRateServiceSheet(
  BuildContext context,
  WidgetRef ref,
  SpBooking booking,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _RateSheet(booking: booking),
  );
}

class _RateSheet extends ConsumerStatefulWidget {
  const _RateSheet({required this.booking});

  final SpBooking booking;

  @override
  ConsumerState<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<_RateSheet> {
  int _rating = 0;
  bool _submitting = false;
  final _review = TextEditingController();

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);

    try {
      await ref.read(servicesDataSourceProvider).review(
            widget.booking.id,
            rating: _rating,
            review: _review.text.trim(),
          );

      if (!mounted) return;
      // Both the detail screen and the list show the rating once it exists.
      ref.invalidate(spBookingProvider(widget.booking.id));
      ref.read(myBookingsProvider.notifier).refresh();

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Thanks for the feedback!'.tr)),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.booking.attendingPartner;

    return Padding(
      // Lifts the sheet clear of the keyboard when the review field is focused.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: spSurface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: spBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How was the service?'.tr,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: spTextPrimary(context),
                ),
              ),
              if (partner != null) ...[
                const SizedBox(height: 4),
                Text(
                  partner.displayName,
                  style: TextStyle(fontSize: 13, color: spTextSecondary(context)),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var star = 1; star <= 5; star++)
                    IconButton(
                      onPressed: () => setState(() => _rating = star),
                      icon: Icon(
                        star <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 38,
                        color: star <= _rating
                            ? AppColors.ratingStar
                            : spTextSecondary(context),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _review,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Tell us more (optional)'.tr,
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkContainer
                      : AppColors.lightContainer,
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  // Disabled until a star is picked — the endpoint requires
                  // `rating` between 1 and 5 and rejects anything else.
                  onPressed: _rating == 0 || _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: spAccent,
                    foregroundColor: spOnAccent,
                    disabledBackgroundColor: spAccent.withValues(alpha: 0.4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(spOnAccent),
                          ),
                        )
                      : Text(
                          'Submit rating'.tr,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
