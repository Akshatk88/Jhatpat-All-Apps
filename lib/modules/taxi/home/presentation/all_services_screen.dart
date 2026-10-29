import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/home/data/models/app_module_model.dart';

/// "Services" tab of the rides bottom nav: every ride service as a large
/// picture card, then the other Jhatpat verticals, then a short trust strip.
///
/// Service icons come from the backend only when they are absolute URLs —
/// most are not, which is why this screen used to show the same placeholder
/// grid icon for everything. Each service now falls back to the same bundled
/// artwork the rides home uses.
class AllServicesScreen extends ConsumerWidget {
  const AllServicesScreen({super.key});

  static const _brand = Color(0xFFFFB800);
  static const _brandDark = Color(0xFFE5A600);
  static const _brandTint = Color(0xFFFFF8E1);

  /// Shown while the module list loads or if it fails, so the tab is never
  /// empty.
  static const List<AppModuleModel> _fallbackModules = [
    AppModuleModel(
      id: 'ride',
      name: 'Ride',
      transportType: 'taxi',
      serviceType: 'normal',
      orderBy: 0,
      shortDescription: 'Bike, auto & cabs in minutes',
      description: '',
      mobileMenuIcon: '',
      active: true,
    ),
    AppModuleModel(
      id: 'parcel',
      name: 'Parcel',
      transportType: 'delivery',
      serviceType: 'parcel',
      orderBy: 3,
      shortDescription: 'Send packages across the city',
      description: '',
      mobileMenuIcon: '',
      active: true,
    ),
  ];

  static String _typeOf(AppModuleModel m) =>
      '${m.serviceType} ${m.transportType} ${m.name}'.toLowerCase();

  static String _routeFor(AppModuleModel m) {
    final type = _typeOf(m);
    if (type.contains('parcel') || type.contains('delivery')) {
      return '/parcel/vehicles';
    }
    // Outstation is a ride type with no screen of its own; it starts the normal
    // booking funnel, same as the rides home.
    return '/taxi/destination';
  }

  static String _assetFor(AppModuleModel m) {
    final type = _typeOf(m);
    if (type.contains('bike') || type.contains('moto')) {
      return 'assets/images/taxi/bike_service.png';
    }
    if (type.contains('parcel') || type.contains('delivery')) {
      return 'assets/images/taxi/parcel_service.png';
    }
    if (type.contains('outstation') || type.contains('intercity')) {
      return 'assets/images/taxi/outstation_service.png';
    }
    return 'assets/images/taxi/taxi_service.png';
  }

  static String _taglineFor(AppModuleModel m) {
    if (m.shortDescription.trim().isNotEmpty) return m.shortDescription.trim();
    final type = _typeOf(m);
    if (type.contains('parcel') || type.contains('delivery')) {
      return 'Send packages across the city';
    }
    if (type.contains('outstation')) return 'Comfortable intercity trips';
    return 'Quick rides, anytime';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    final modulesAsync = ref.watch(appModulesProvider);
    final fromApi = (modulesAsync.value ?? const <AppModuleModel>[])
        .where((m) => m.active)
        .toList()
      ..sort((a, b) => a.orderBy.compareTo(b.orderBy));
    final services = fromApi.isNotEmpty ? fromApi : _fallbackModules;

    void open(String route) {
      Haptics.light();
      context.push(route);
    }

    // On tablets / desktop the content stays a readable column instead of
    // stretching edge to edge.
    final width = MediaQuery.sizeOf(context).width;
    final hPad = width > 752 ? (width - 720) / 2 : 16.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 24),
      children: [
        Text(
          'All Services'.tr,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Everything Jhatpat can do for you'.tr,
          style: TextStyle(fontSize: 13, color: textSecondary),
        ),
        const SizedBox(height: 16),

        // --- Ride services: two large picture cards per row ---
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: services.length,
          // Two cards per row on phones, more on wider screens.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 168,
          ),
          itemBuilder: (context, index) {
            final m = services[index];
            return _ServiceCard(
              title: m.name.tr,
              tagline: _taglineFor(m).tr,
              iconUrl: m.mobileMenuIcon,
              fallbackAsset: _assetFor(m),
              cardColor: cardColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              isDark: isDark,
              onTap: () => open(_routeFor(m)),
            );
          },
        ),

        const SizedBox(height: 24),
        Text(
          'More on Jhatpat'.tr,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _WideCard(
          title: 'Food Delivery'.tr,
          subtitle: 'Order from restaurants near you'.tr,
          icon: Icons.restaurant_rounded,
          background: _brand,
          foreground: Colors.black,
          onTap: () => open('/food'),
        ),
        const SizedBox(height: 12),
        _WideCard(
          title: 'Parcel Delivery'.tr,
          subtitle: 'Bike, auto or truck — pick up in minutes'.tr,
          icon: Icons.inventory_2_rounded,
          background: isDark ? const Color(0xFF121212) : const Color(0xFF18181B),
          foreground: Colors.white,
          accent: _brand,
          onTap: () => open('/parcel'),
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? cardColor : _brandTint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              _TrustItem(
                icon: Icons.verified_user_rounded,
                label: 'Verified\ncaptains'.tr,
                color: isDark ? _brand : _brandDark,
                textColor: textPrimary,
              ),
              _TrustItem(
                icon: Icons.shield_rounded,
                label: 'Safe\nrides'.tr,
                color: isDark ? _brand : _brandDark,
                textColor: textPrimary,
              ),
              _TrustItem(
                icon: Icons.support_agent_rounded,
                label: '24x7\nsupport'.tr,
                color: isDark ? _brand : _brandDark,
                textColor: textPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.title,
    required this.tagline,
    required this.iconUrl,
    required this.fallbackAsset,
    required this.cardColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String tagline;
  final String iconUrl;
  final String fallbackAsset;
  final Color cardColor;
  final Color textPrimary;
  final Color textSecondary;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final asset = Image.asset(
      fallbackAsset,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.local_taxi_rounded,
        color: Color(0xFFE5A600),
        size: 40,
      ),
    );

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : AllServicesScreen._brandTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: iconUrl.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: iconUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => asset,
                          errorWidget: (context, url, error) => asset,
                        )
                      : asset,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: AllServicesScreen._brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideCard extends StatelessWidget {
  const _WideCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;

  /// Icon bubble colour; defaults to a translucent [foreground].
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bubble = accent ?? foreground.withValues(alpha: 0.12);
    final bubbleIcon = accent != null ? Colors.black : foreground;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bubble,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: bubbleIcon, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
