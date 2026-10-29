import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:food_user_application/features/auth/domain/restaurant_model.dart';
import 'package:food_user_application/features/restaurant_profile/presentation/controllers/restaurant_profile_controller.dart';

/// Shows the restaurant's permanent scan-to-menu QR code.
///
/// The code itself is generated once, server-side, on first approval (see
/// ensureRestaurantQrCode() on the backend) and never changes after that --
/// so it is safe to print once and keep using indefinitely. Customers scan
/// it from the Spedo user app's Food home page to land directly on this
/// restaurant's full menu.
class RestaurantQrScreen extends ConsumerWidget {
  const RestaurantQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurantAsync = ref.watch(restaurantProfileControllerProvider);
    final restaurant = restaurantAsync.value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('My QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: restaurantAsync.isLoading
                  ? const CircularProgressIndicator()
                  : _buildContent(context, restaurant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, RestaurantModel? restaurant) {
    final qrCodeUrl = restaurant?.qrCodeUrl ?? '';
    final isApproved = restaurant?.isApproved ?? false;

    if (!isApproved) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.orange.shade300),
          const SizedBox(height: 16),
          const Text(
            'Your QR code will appear here once your restaurant is approved.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      );
    }

    if (qrCodeUrl.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 64, color: Colors.orange.shade300),
          const SizedBox(height: 16),
          const Text(
            "Your QR code is being generated. Pull to refresh in a moment.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          restaurant?.restaurantName ?? '',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8)),
            ],
          ),
          child: CachedNetworkImage(
            imageUrl: qrCodeUrl,
            width: 240,
            height: 240,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox(
              width: 240,
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, __, ___) => const SizedBox(
              width: 240,
              height: 240,
              child: Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'This code is permanent. Print it and display it at your restaurant --\n'
          'customers scan it in the Jhatpat app to open your full menu instantly.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
      ],
    );
  }
}
