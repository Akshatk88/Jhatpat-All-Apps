import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/booking_draft_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// One service, and the entry point into the booking funnel.
///
/// Reachable two ways, and both must work:
///  * warm, from the category list, with the model already in `extra`
///  * cold, from a deep link or a restored process, with only the id
///
/// [preloaded] is `Object?` rather than `SpService?` because it comes straight
/// off `GoRouterState.extra`. Casting it unconditionally is the single most
/// common crash in this codebase's route table, so it is type-tested instead.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.serviceId, this.preloaded});

  final String serviceId;
  final Object? preloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warm = preloaded is SpService ? preloaded as SpService : null;
    if (warm != null && warm.id == serviceId) {
      return _Body(service: warm);
    }

    // Cold entry. There is no `GET /sp/public/services/:id`, so the id is
    // resolved by listing and filtering — the lists are small and cached.
    final services = ref.watch(spServicesProvider(const SpServiceQuery()));

    return switch (services) {
      AsyncData(:final value) => () {
          final match = value.where((s) => s.id == serviceId).firstOrNull;
          if (match != null) return _Body(service: match);
          return Scaffold(
            appBar: AppBar(title: Text('Service'.tr)),
            body: SpErrorState(
              message: 'This service is no longer available.'.tr,
              onRetry: () => context.go(ServicesRoutePaths.home),
            ),
          );
        }(),
      AsyncError() => Scaffold(
          appBar: AppBar(title: Text('Service'.tr)),
          body: SpErrorState(
            message: 'We could not load this service.'.tr,
            onRetry: () => ref.invalidate(spServicesProvider),
          ),
        ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator(color: spAccent))),
    };
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.service});

  final SpService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    // Quantity applies to this service only — a stale count carried over from a
    // different service would silently multiply the wrong price.
    final quantity = draft.service?.id == service.id ? draft.quantity : 1;
    final linePaise = service.effectivePricePaise * quantity;

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: spSurface(context),
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: SmartImage(
                url: service.iconUrl,
                category: ImageCategory.category,
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (service.brandName.isNotEmpty)
                    Text(
                      service.brandName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: spAccentText(context),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    service.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: spTextPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatPaise(service.effectivePricePaise),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: spTextPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (service.hasDiscount)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            formatPaise(service.basePricePaise),
                            style: TextStyle(
                              fontSize: 15,
                              color: spTextSecondary(context),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      if (service.pricingUnit.isNotEmpty)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4, left: 6),
                            child: Text(
                              'per {unit}'.trArgs({'unit': service.pricingUnit}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: spTextSecondary(context),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (service.description.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'About this service'.tr,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: spTextPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      service.description,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: spTextSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _QuantityStepper(
                    quantity: quantity,
                    onChanged: (value) {
                      // Selecting the service first means the stepper always
                      // edits this service's draft, never a leftover one.
                      final controller = ref.read(bookingDraftProvider.notifier);
                      if (draft.service?.id != service.id) {
                        controller.startWith(service);
                      }
                      controller.setQuantity(value);
                    },
                  ),
                  const SizedBox(height: 20),
                  const _Assurances(),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BookBar(
        totalPaise: linePaise,
        onBook: () {
          ref.read(bookingDraftProvider.notifier).startWith(service);
          if (quantity != 1) {
            ref.read(bookingDraftProvider.notifier).setQuantity(quantity);
          }
          context.push(ServicesRoutePaths.schedule);
        },
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Quantity'.tr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: spTextPrimary(context),
          ),
        ),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: spBorder(context)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: spTextPrimary(context),
                  ),
                ),
              ),
              IconButton(
                // Capped at 10, matching the clamp in the draft controller —
                // an uncapped stepper would let the UI show a total the
                // controller then silently refuses to use.
                onPressed: quantity < 10 ? () => onChanged(quantity + 1) : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Assurances extends StatelessWidget {
  const _Assurances();

  static const _items = [
    (Icons.verified_user_rounded, 'Verified professionals'),
    (Icons.currency_rupee_rounded, 'Transparent pricing'),
    (Icons.lock_clock_rounded, 'OTP-verified visit'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (icon, label) in _items)
          Expanded(
            child: Column(
              children: [
                Icon(icon, size: 22, color: spAccent),
                const SizedBox(height: 6),
                Text(
                  label.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
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

class _BookBar extends StatelessWidget {
  const _BookBar({required this.totalPaise, required this.onBook});

  final int totalPaise;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: spSurface(context),
          border: Border(top: BorderSide(color: spBorder(context))),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatPaise(totalPaise),
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: spTextPrimary(context),
                  ),
                ),
                Text(
                  '+ visiting charge'.tr,
                  style: TextStyle(fontSize: 11.5, color: spTextSecondary(context)),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: spAccent,
                    foregroundColor: spOnAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Schedule service'.tr,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
