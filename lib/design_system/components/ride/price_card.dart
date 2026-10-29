import 'package:flutter/material.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/core/utils/taxi_formatters.dart';

class PriceCard extends StatelessWidget {
  final String label;
  final double amount;
  final List<MapEntry<String, double>>? breakdown;

  const PriceCard({
    super.key,
    required this.label,
    required this.amount,
    this.breakdown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TaxiColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(width: 12),
              Text(Formatters.currency(amount), style: AppTextStylesPrice.style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          if (breakdown != null) ...[
            const Divider(height: 24),
            ...breakdown!.map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Formatters.currency(entry.value),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AppTextStylesPrice {
  static const style = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 20,
    color: TaxiColors.primary,
  );
}
