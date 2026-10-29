import 'package:flutter/material.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';

class TaxiPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool useAccentGradient;

  const TaxiPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.useAccentGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final gradient = useAccentGradient
        ? TaxiColors.accentGradient
        : const [TaxiColors.primary, TaxiColors.primaryDark];

    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : onPressed,
            child: SizedBox(
              height: 56,
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.black,
                        ),
                      )
                    // One Text.rich instead of an icon + label Row: a long
                    // label ellipsises in a narrow slot, yet it stays safe
                    // when a caller drops the button into a Row without
                    // Expanded (unbounded width), where a Flexible would throw.
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (icon != null) ...[
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Icon(
                                    icon,
                                    color: useAccentGradient
                                        ? TaxiColors.primary
                                        : Colors.black,
                                    size: 20,
                                  ),
                                ),
                                const WidgetSpan(child: SizedBox(width: 8)),
                              ],
                              TextSpan(text: label),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: useAccentGradient
                                ? TaxiColors.primary
                                : Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
