import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/ride_completion_payment_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:confetti/confetti.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/taxi_formatters.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_controller.dart';

class RatingReviewScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RatingReviewScreen({super.key, required this.rideId});

  @override
  ConsumerState<RatingReviewScreen> createState() => _RatingReviewScreenState();
}

class _RatingReviewScreenState extends ConsumerState<RatingReviewScreen> {
  int _rating = 0;
  double _selectedTip = 0.0;
  final _commentController = TextEditingController();
  bool _submitting = false;
  late ConfettiController _confettiController;

  final List<double> _tipOptions = [0, 10, 20, 50];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiController.play();
    // An `online` ride arrives here with the fare still uncollected — the
    // backend's complete-payment endpoints existed but nothing called them.
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectFareIfDue());
  }

  Future<void> _collectFareIfDue() async {
    final ride = ref.read(rideTrackingControllerProvider(widget.rideId)).ride;
    if (ride == null) return;
    if ((ride.paymentMethod ?? 'cash').toLowerCase() != 'online') return;
    if (ride.fare <= 0) return;
    if (!mounted) return;

    await RideCompletionPaymentSheet.show(
      context,
      rideId: widget.rideId,
      amount: ride.fare,
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final controller = ref.read(rideTrackingControllerProvider(widget.rideId).notifier);
    final success = await controller.submitReview(
      rating: _rating > 0 ? _rating : 5,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      tipAmount: _selectedTip,
    );
    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        SnackbarUtils.success(context, 'Thank you for your feedback!'.tr);
        context.go('/taxi');
      } else {
        context.go('/taxi');
      }
    }
  }

  void _shareReceipt(dynamic ride, String driverName, double totalFare) {
    final dateStr = Formatters.date(ride?.completedAt ?? DateTime.now());
    final fareStr = totalFare.toStringAsFixed(2);
    final text = 'Trip Receipt\nDate: {date}\nDriver: {driver}\nFare: ₹{fare}\nThank you for riding!'
        .trArgs({'date': dateStr, 'driver': driverName, 'fare': fareStr});
    Share.share(text);
  }

  String _getRatingFeedbackText(int rating) {
    switch (rating) {
      case 0:
        return '';
      case 1:
        return 'Poor'.tr;
      case 2:
        return 'Okay'.tr;
      case 3:
        return 'Good'.tr;
      case 4:
        return 'Very Good'.tr;
      case 5:
        return 'Excellent'.tr;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(rideTrackingControllerProvider(widget.rideId)).ride;

    final completedDate = ride?.completedAt ?? ride?.scheduledAt ?? ride?.acceptedAt ?? DateTime.now();
    final pickup = (ride?.pickupAddress.isNotEmpty == true) ? ride!.pickupAddress : 'Pickup location'.tr;
    final drop = (ride?.dropAddress.isNotEmpty == true)
        ? ride!.dropAddress
        : 'Drop location'.tr;
    final driverName = (ride?.driver?.name.isNotEmpty == true) ? ride!.driver!.name : 'Your driver'.tr;
    final vehicleNo = (ride?.driver?.vehicleNumber.isNotEmpty == true) ? ride!.driver!.vehicleNumber : '';
    final vehicleType = (ride?.driver?.vehicleMake.isNotEmpty == true)
        ? ride!.driver!.vehicleMake
        : (ride?.vehicleType?.isNotEmpty == true ? ride!.vehicleType! : 'Bike');
    final driverRating = (ride?.driver?.rating != null && ride!.driver!.rating > 0)
        ? ride.driver!.rating.toStringAsFixed(1)
        : 'New'.tr;
    final baseFare = (ride?.fare != null && ride!.fare > 0) ? ride.fare : 0.0;
    final totalFare = baseFare + _selectedTip;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // --- TOP CONFETTI & CHECKMARK HEADER ---
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x3310B981),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'You have arrived!'.tr,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Thanks for riding with us 👋'.tr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- CARD 1: TRIP RECEIPT ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row with Date & Share
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: Color(0xFFE5A600),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trip Receipt'.tr,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${Formatters.date(completedDate)} • ${Formatters.time(completedDate)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => _shareReceipt(ride, driverName, totalFare),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.share_outlined, size: 14, color: Color(0xFF0F172A)),
                                const SizedBox(width: 5),
                                Text(
                                  'Share'.tr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Driver Row (Avatar, Name, Vehicle, Rating, Bike graphic)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: (ride?.driver?.profileImage != null && ride!.driver!.profileImage.isNotEmpty)
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: ride.driver!.profileImage,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.person, color: Color(0xFF0F172A), size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$vehicleNo • $vehicleType',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                                    const SizedBox(width: 3),
                                    Text(
                                      driverRating,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.two_wheeler_rounded,
                            size: 42,
                            color: Color(0xFF0F172A),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pickup & Drop Timeline Sub-box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pickup,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'PICKUP'.tr,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF15803D),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 12,
                                child: VerticalDivider(
                                  color: Color(0xFFCBD5E1),
                                  thickness: 1.5,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE5A600),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  drop,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DROP'.tr,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF121212),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Base fare & Tip rows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Base fare'.tr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '₹${baseFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tip'.tr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '₹${_selectedTip.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    ),

                    // Total Amount Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount'.tr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '₹${totalFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF121212),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- CARD 2: TIP YOUR DRIVER ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tip your driver'.tr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Thank your driver with a tip'.tr,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Horizontal Tip selector chips
                    Row(
                      children: [
                        ..._tipOptions.map((amount) {
                          final isSelected = _selectedTip == amount;
                          final label = amount == 0 ? 'No tip'.tr : '₹${amount.toInt()}';
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => setState(() => _selectedTip = amount),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFF8E1) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFFFFB800) : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                      color: isSelected ? const Color(0xFF121212) : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final val = await _showCustomTipDialog(context);
                              if (val != null) setState(() => _selectedTip = val);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                'Other'.tr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- CARD 3: RATING CARD ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'How was your trip with {name}?'.trArgs({'name': driverName}),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5 Star rating buttons
                    // Each star gets an equal share of the card and shrinks to
                    // fit, so five always fit — fixed 40px stars plus padding
                    // overflowed on narrow phones / large display size.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Row(
                        children: List.generate(5, (index) {
                          final starIndex = index + 1;
                          final isFilled = _rating >= starIndex;
                          return Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _rating = starIndex),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Icon(
                                    isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                                    size: 40,
                                    color: isFilled ? const Color(0xFFFFB800) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRatingFeedbackText(_rating),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- BOTTOM PRIMARY BUTTON: DONE ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF121212),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Done'.tr,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF121212),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
          ),
        ),
      ],
    ),
  );
  }

  Future<double?> _showCustomTipDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter custom tip amount'.tr),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'e.g. 30'.tr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              Navigator.pop(context, val);
            },
            child: Text('OK'.tr),
          ),
        ],
      ),
    );
  }
}
