import 'package:flutter/material.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/tokens/module_accent.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';

/// Small shared pieces for the services module.
///
/// Everything here is composition over `design_system/` primitives, not a
/// second design system — these exist because the same three or four
/// arrangements recur across eight screens, and copying them would drift.

/// The module accent, resolved once so screens don't reach for a raw hex.
const Color spAccent = Color(0xFFFFB800);
Color get spAccentDark => ModuleAccent.services.primaryVariant;

/// Text/icons drawn ON an [spAccent] fill — black, as yellow won't carry white.
const Color spOnAccent = Color(0xFF121212);

/// Accent-coloured *text* on a plain surface: yellow reads on dark surfaces,
/// but not on white, so light mode falls back to near-black.
Color spAccentText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? spAccent : spOnAccent;

Color spSurface(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.cardDark
        : AppColors.surfaceLight;

Color spBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.borderDark
        : AppColors.borderLight;

Color spTextPrimary(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;

Color spTextSecondary(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

/// A titled row with an optional "See all".
/// A titled row with an optional "View all >".
class SpSectionHeader extends StatelessWidget {
  const SpSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.actionLabel = 'View all',
  });

  final String title;
  final VoidCallback? onSeeAll;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: spTextPrimary(context),
              ),
            ),
          ),
          if (onSeeAll != null)
            InkWell(
              onTap: onSeeAll,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel.tr,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: spAccentText(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: spAccentText(context),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Colour-coded lifecycle chip.
class SpStatusChip extends StatelessWidget {
  const SpStatusChip({super.key, required this.status, this.compact = false});

  final SpBookingStatus status;
  final bool compact;

  Color get _colour {
    if (status.isDead) return AppColors.error;
    if (status == SpBookingStatus.completed || status == SpBookingStatus.workDone) {
      return AppColors.success;
    }
    if (status.isSearching) return AppColors.rating;
    return spAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label.tr,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: _colour == spAccent ? spAccentText(context) : _colour,
        ),
      ),
    );
  }
}

/// One line of a price breakdown. [emphasised] renders the grand total.
class SpPriceRow extends StatelessWidget {
  const SpPriceRow({
    super.key,
    required this.label,
    required this.pricePaise,
    this.emphasised = false,
    this.isCredit = false,
  });

  final String label;
  final int pricePaise;
  final bool emphasised;

  /// Discounts and savings — rendered green with a leading minus.
  final bool isCredit;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasised ? 16 : 14,
      fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
      color: isCredit
          ? AppColors.success
          : (emphasised ? spTextPrimary(context) : spTextSecondary(context)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            '${isCredit ? '- ' : ''}${formatPaise(pricePaise)}',
            style: style.copyWith(
              color: isCredit ? AppColors.success : spTextPrimary(context),
              fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded card with the module's surface treatment.
class SpCard extends StatelessWidget {
  const SpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: spSurface(context),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: spBorder(context)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Category tile for the home grid.
class SpCategoryTile extends StatelessWidget {
  const SpCategoryTile({super.key, required this.category, required this.onTap});

  final SpCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFF3F4F6),
              width: 1,
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    child: SmartImage(
                      url: category.iconUrl,
                      category: ImageCategory.category,
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (category.hasSaleBadge)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'SALE'.tr,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                category.title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bookable service, as shown in a list.
class SpServiceCard extends StatelessWidget {
  const SpServiceCard({super.key, required this.service, required this.onTap});

  final SpService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SmartImage(
              url: service.iconUrl,
              category: ImageCategory.category,
              width: 76,
              height: 76,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: spTextPrimary(context),
                  ),
                ),
                if (service.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    service.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: spTextSecondary(context),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatPaise(service.effectivePricePaise),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: spTextPrimary(context),
                      ),
                    ),
                    if (service.hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        formatPaise(service.basePricePaise),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: spTextSecondary(context),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    if (service.pricingUnit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        '/ ${service.pricingUnit}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: spTextSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: spAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: spAccent.withValues(alpha: 0.35)),
            ),
            child: Text(
              'Book'.tr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: spAccentText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder rows while a list loads.
class SpListSkeleton extends StatelessWidget {
  const SpListSkeleton({super.key, this.itemCount = 5, this.height = 100});

  final int itemCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppColors.cardDark
        : const Color(0xFFEFF1F4);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) => Container(
        height: height,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

/// Failure state with a retry, for anything fed by a `FutureProvider`.
class SpErrorState extends StatelessWidget {
  const SpErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: spTextSecondary(context)),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: spTextSecondary(context)),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: spAccentText(context),
                side: const BorderSide(color: spAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Try again'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
