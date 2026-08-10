import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/_taxi_staging/core/theme/app_colors.dart';
import 'package:superapp_user/_taxi_staging/core/utils/snackbar_utils.dart';
import 'package:superapp_user/_taxi_staging/shared/widgets/app_text_field.dart';
import 'package:superapp_user/_taxi_staging/shared/widgets/custom_app_bar.dart';
import 'package:superapp_user/_taxi_staging/shared/widgets/empty_state.dart';
import 'package:superapp_user/_taxi_staging/shared/widgets/primary_button.dart';
import 'package:superapp_user/_taxi_staging/features/promo/application/promo_providers.dart';
import 'package:superapp_user/_taxi_staging/features/home/application/booking_controller.dart';

class PromoScreen extends ConsumerStatefulWidget {
  const PromoScreen({super.key});

  @override
  ConsumerState<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends ConsumerState<PromoScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _apply(String code) {
    ref.read(bookingControllerProvider.notifier).applyPromoCode(code);
    SnackbarUtils.success(context, 'Promo "$code" applied');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final promosAsync = ref.watch(availablePromosProvider);
    final applied = ref.watch(bookingControllerProvider).promoCode;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Apply promo code'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _codeController,
                    hint: 'Enter promo code',
                    prefixIcon: Icons.local_offer_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                TaxiPrimaryButton(
                  label: 'Apply',
                  onPressed: () {
                    if (_codeController.text.trim().isNotEmpty) {
                      _apply(_codeController.text.trim());
                    }
                  },
                ),
              ],
            ),
          ),
          if (applied != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Chip(
                label: Text('Applied: $applied'),
                onDeleted: () => ref.read(bookingControllerProvider.notifier).applyPromoCode(null),
              ),
            ),
          Expanded(
            child: promosAsync.when(
              data: (promos) => promos.isEmpty
                  ? const EmptyState(
                      icon: Icons.local_offer_outlined,
                      title: 'No promos available',
                      message: 'Check back later for new offers and discounts.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: promos.length,
                      itemBuilder: (context, index) {
                        final promo = promos[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: const Icon(Icons.local_offer_rounded, color: TaxiColors.primary),
                            title: Text(promo.title),
                            subtitle: Text(promo.description),
                            trailing: TextButton(
                              onPressed: () => _apply(promo.code),
                              child: Text(promo.code),
                            ),
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load promos',
                message: 'Please check your connection and try again.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
