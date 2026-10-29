import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/app/routing/route_names.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/shared/profile/data/user_model.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:superapp_user/shared/address/presentation/viewmodels/address_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/coupons/viewmodels/coupons_viewmodel.dart';
import 'package:superapp_user/shared/profile/presentation/viewmodels/notifications_viewmodel.dart';
import 'package:superapp_user/shared/profile/presentation/push_test_screen.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/orders_viewmodel.dart';
import 'package:superapp_user/shared/wallet/presentation/viewmodels/wallet_viewmodel.dart';
import 'package:superapp_user/design_system/theme/theme_provider.dart';
import 'package:superapp_user/modules/food/presentation/home/viewmodels/veg_filter_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _getThemeString(ThemeMode mode) {
    if (mode == ThemeMode.light) return 'Light';
    if (mode == ThemeMode.dark) return 'Dark';
    return 'System';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondaryColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final cardColor = isDark ? AppColors.cardDark : Colors.white;

    final user = ref.watch(authViewModelProvider).value;
    final isLoggedIn = user != null;

    final addresses = ref.watch(addressViewModelProvider);
    final coupons = ref.watch(couponsViewModelProvider);
    final notificationSettings = ref.watch(notificationsViewModelProvider);
    final walletState = isLoggedIn ? ref.watch(walletViewModelProvider) : null;
    final walletBalance = walletState?.wallet.balance ?? 0.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          // Tablets / desktop: keep the cards a readable width, centred.
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width > 760
                ? (MediaQuery.sizeOf(context).width - 720) / 2
                : 20,
            12,
            MediaQuery.sizeOf(context).width > 760
                ? (MediaQuery.sizeOf(context).width - 720) / 2
                : 20,
            28,
          ),
          children: [
            // 1. Header
            _buildHeader(context, textColor, secondaryColor, isLoggedIn),

            const SizedBox(height: 20),

            // 2. User Profile Card / Guest Card
            if (isLoggedIn)
              _buildUserProfileCard(user, isDark, textColor, secondaryColor)
            else
              _buildGuestCard(context, isDark, textColor, secondaryColor),

            const SizedBox(height: 16),

            // 3. Wallet & Coupons Quick Row
            _buildWalletCouponsRow(
              walletBalance,
              coupons.length,
              cardColor,
              isDark,
              textColor,
              secondaryColor,
              isLoggedIn,
            ),

            const SizedBox(height: 16),

            // 4. Cart & Saved Addresses Quick Row
            _buildCartAddressesRow(
              addresses.length,
              cardColor,
              isDark,
              textColor,
              secondaryColor,
              isLoggedIn,
            ),

            const SizedBox(height: 16),

            // 5. Account & Preferences Group
            _buildPreferencesGroupCard(
              notificationSettings,
              cardColor,
              isDark,
              textColor,
              secondaryColor,
              isLoggedIn,
            ),

            const SizedBox(height: 16),

            // 6. Order History Card (Breakdown + View All)
            _buildOrderHistoryCard(
              cardColor,
              isDark,
              textColor,
              secondaryColor,
              isLoggedIn,
            ),

            const SizedBox(height: 16),

            // 7. Rewards & Sharing Group
            _buildRewardsSharingGroupCard(
              user?.referralCode ?? '',
              cardColor,
              isDark,
              textColor,
              secondaryColor,
            ),

            const SizedBox(height: 16),

            // 8. Help, Support & Legal Group
            _buildHelpLegalGroupCard(
              cardColor,
              isDark,
              textColor,
              secondaryColor,
            ),

            const SizedBox(height: 20),

            // 9. Session Action (Logout or Login)
            if (isLoggedIn)
              _buildLogoutButton(cardColor, isDark)
            else
              _buildLoginButton(cardColor),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Top Profile Header
  Widget _buildHeader(
    BuildContext context,
    Color textColor,
    Color secondaryColor,
    bool isLoggedIn,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile'.tr,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isLoggedIn
                    ? 'Manage your account, orders & preferences'.tr
                    : 'Log in to unlock orders, addresses & rewards'.tr,
                style: TextStyle(fontSize: 13, color: secondaryColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// User Profile Card with Edit Profile action
  Widget _buildUserProfileCard(
    UserModel? user,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final avatarUrl = user?.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFB800).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFB800),
                        width: 2,
                      ),
                    ),
                    child: avatarUrl == null
                        ? ClipOval(
                            child: Image.asset(
                              'assets/images/user_avatar_3d.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.person_rounded,
                                color: Color(0xFFFFB800),
                                size: 34,
                              ),
                            ),
                          )
                        : ClipOval(
                            child: avatarUrl.startsWith('/')
                                ? Image.file(File(avatarUrl), fit: BoxFit.cover)
                                : (avatarUrl.startsWith('assets/')
                                      ? Image.asset(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.network(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Icon(
                                            Icons.person_rounded,
                                            color: Color(0xFFFFB800),
                                            size: 34,
                                          ),
                                        )),
                          ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () {
                        Haptics.light();
                        context.push(RouteNames.editProfile);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFB800),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.black,
                          size: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'User'.tr,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user?.phone ?? '',
                      style: TextStyle(fontSize: 13, color: secondaryColor),
                    ),
                    Text(
                      user?.email ?? '',
                      style: TextStyle(fontSize: 13, color: secondaryColor),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFFB800)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Haptics.light();
                context.push(RouteNames.editProfile);
              },
              icon: const Icon(
                Icons.edit_outlined,
                size: 16,
                color: Color(0xFFE5A600),
              ),
              label: Text(
                'Edit Profile'.tr,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Guest Card when logged out
  Widget _buildGuestCard(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFB800).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFFFFB800),
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guest User'.tr,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sign in to access your orders, saved addresses & profile details.'.tr,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: secondaryColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB800),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Haptics.light();
                context.push(
                  '${RouteNames.login}?from=${Uri.encodeComponent(RouteNames.profile)}',
                );
              },
              child: Text(
                'LOG IN / SIGN UP'.tr,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Wallet & Coupons Row
  Widget _buildWalletCouponsRow(
    double walletBalance,
    int couponCount,
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    bool isLoggedIn,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          // Wallet Tile
          Expanded(
            child: InkWell(
              onTap: () {
                Haptics.light();
                _protectedNavigation(RouteNames.wallet, isLoggedIn);
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFFFFB800),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: // One line, shrunk to fit: the half-width tiles are too narrow for
                    // "View Balance" / "Saved Addresses", which used to break mid-word.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wallet'.tr,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isLoggedIn ? '₹${walletBalance.toStringAsFixed(2)}' : 'View Balance'.tr,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFFFB800),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 38,
            color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
          ),
          const SizedBox(width: 12),

          // Coupons Tile
          Expanded(
            child: InkWell(
              onTap: () {
                Haptics.light();
                _showCouponsModal();
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_offer_rounded,
                      color: Color(0xFFFFB800),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: // One line, shrunk to fit: the half-width tiles are too narrow for
                    // "View Balance" / "Saved Addresses", which used to break mid-word.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coupons'.tr,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '{count} Active'.trArgs({'count': couponCount}),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFFFB800),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// My Cart & Saved Addresses Row
  Widget _buildCartAddressesRow(
    int addressCount,
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    bool isLoggedIn,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          // My Cart Tile
          Expanded(
            child: InkWell(
              onTap: () {
                Haptics.light();
                context.go(RouteNames.cart);
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: Color(0xFFFFB800),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: // One line, shrunk to fit: the half-width tiles are too narrow for
                    // "View Balance" / "Saved Addresses", which used to break mid-word.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Cart'.tr,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'View Cart'.tr,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFFFB800),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 38,
            color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
          ),
          const SizedBox(width: 12),

          // Saved Addresses Tile
          Expanded(
            child: InkWell(
              onTap: () {
                Haptics.light();
                if (isLoggedIn) {
                  _showAddressManagerModal();
                } else {
                  context.push(
                    '${RouteNames.login}?from=${Uri.encodeComponent(RouteNames.addAddress)}',
                  );
                }
              },
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFFFFB800),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: // One line, shrunk to fit: the half-width tiles are too narrow for
                    // "View Balance" / "Saved Addresses", which used to break mid-word.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved Addresses'.tr,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '{count} Saved'.trArgs({'count': addressCount}),
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFFFFB800),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Account & Preferences Group
  Widget _buildPreferencesGroupCard(
    NotificationSettingsState notifSettings,
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    bool isLoggedIn,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // 1. Notifications Preferences
          _buildMenuRow(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications & Alerts'.tr,
            subtitle: 'Push alerts & promo settings'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: _showNotificationsModal,
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 1b. Push diagnostics (the test endpoint needs auth)
          if (isLoggedIn) ...[
            _buildMenuRow(
              icon: Icons.notification_add_outlined,
              title: 'Test notifications',
              subtitle: 'Check FCM setup & send a test push',
              textColor: textColor,
              secondaryColor: secondaryColor,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PushTestScreen()),
              ),
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: isDark ? AppColors.borderDark : AppColors.dividerLight,
            ),
          ],

          // 2. Veg Mode Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF39C96B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: Color(0xFF39C96B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Veg Mode'.tr,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Show only vegetarian food items'.tr,
                        style: TextStyle(fontSize: 12, color: secondaryColor),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: ref.watch(vegFilterProvider),
                  activeThumbColor: const Color(0xFF39C96B),
                  onChanged: (val) {
                    Haptics.light();
                    ref.read(vegFilterProvider.notifier).set(val);
                  },
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 3. Appearance
          _buildMenuRow(
            icon: Icons.palette_outlined,
            title: 'Appearance Settings'.tr,
            subtitle: 'Theme: {mode} mode'.trArgs({
              'mode': _getThemeString(ref.watch(themeProvider)).tr,
            }),
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: _showAppearanceModal,
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // (App Theme colour picker removed: the app ships one brand theme.)

          // 4. Favorites
          _buildMenuRow(
            icon: Icons.favorite_border_rounded,
            title: 'Favorites'.tr,
            subtitle: 'Your favorite restaurants & dishes'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () => context.push(RouteNames.favorites),
          ),
        ],
      ),
    );
  }

  /// Order History Summary Card
  Widget _buildOrderHistoryCard(
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
    bool isLoggedIn,
  ) {
    // Watch the orders state — updates automatically when any order changes.
    final ordersState = ref.watch(ordersViewModelProvider);
    final upcoming = isLoggedIn ? ordersState.upcomingCount.toString() : '0';
    final completed = isLoggedIn ? ordersState.completedCount.toString() : '0';
    final cancelled = isLoggedIn ? ordersState.cancelledCount.toString() : '0';
    final refunded = isLoggedIn ? ordersState.refundedCount.toString() : '0';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'My Orders'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Flexible: at large text sizes on a 320dp phone the title plus
              // this link were wider than the card.
              Flexible(
                child: InkWell(
                onTap: () =>
                    _protectedNavigation(RouteNames.orders, isLoggedIn),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'View All Orders'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE5A600),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFFFB800),
                      size: 16,
                    ),
                  ],
                ),
              ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _orderStat(
                Icons.shopping_bag_rounded,
                const Color(0xFFFFB800),
                upcoming,
                'Upcoming'.tr,
                textColor,
                secondaryColor,
              ),
              _orderStat(
                Icons.check_circle_rounded,
                const Color(0xFF39C96B),
                completed,
                'Completed'.tr,
                textColor,
                secondaryColor,
              ),
              _orderStat(
                Icons.cancel_rounded,
                const Color(0xFFFF6464),
                cancelled,
                'Cancelled'.tr,
                textColor,
                secondaryColor,
              ),
              _orderStat(
                Icons.replay_circle_filled_rounded,
                const Color(0xFFFFB800),
                refunded,
                'Refunds'.tr,
                textColor,
                secondaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderStat(
    IconData icon,
    Color color,
    String value,
    String label,
    Color textColor,
    Color secondaryColor,
  ) {
    return Expanded(
      child: Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: TextStyle(fontSize: 11.5, color: secondaryColor)),
        ),
      ],
      ),
    );
  }

  /// Rewards & Sharing Group
  Widget _buildRewardsSharingGroupCard(
    String referralCode,
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // 1. Refer & Earn
          _buildMenuRow(
            icon: Icons.card_giftcard_rounded,
            title: 'Refer & Earn'.tr,
            subtitle: 'Code: {code} • Share & earn ₹100'.trArgs({'code': referralCode}),
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () {
              Haptics.light();
              context.push(RouteNames.referral);
            },
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 2. Rate App
          _buildMenuRow(
            icon: Icons.star_border_rounded,
            title: 'Rate App'.tr,
            subtitle: 'Love our app? Leave us a 5-star rating'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: _showRateAppModal,
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 3. Share App
          _buildMenuRow(
            icon: Icons.share_outlined,
            title: 'Share App'.tr,
            subtitle: 'Share JhatPat food delivery app with friends'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () {
              Haptics.light();
              Clipboard.setData(
                const ClipboardData(
                  text:
                      'Check out JhatPat app for delicious food delivery: https://jhatpattaxi.com',
                ),
              );
              AppSnackbar.success(
                context,
                'App invite link copied to clipboard! 🚀'.tr,
                duration: const Duration(seconds: 2),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Help, Support & Legal Group
  Widget _buildHelpLegalGroupCard(
    Color cardColor,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: AppColors.shadow1,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          // 1. Help & Support
          _buildMenuRow(
            icon: Icons.headset_mic_outlined,
            title: 'Help & Support'.tr,
            subtitle: 'FAQs, order refund status & 24/7 support'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () => context.push(RouteNames.helpSupport),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 2. About Us
          _buildMenuRow(
            icon: Icons.info_outline_rounded,
            title: 'About Us'.tr,
            subtitle: 'Version 1.2.0 • JhatPat Food & Drink'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () => context.push(RouteNames.about),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 3. Privacy Policy
          _buildMenuRow(
            icon: Icons.shield_outlined,
            title: 'Privacy Policy'.tr,
            subtitle: 'How we protect & manage your data'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () => context.push(RouteNames.privacyPolicy),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: isDark ? AppColors.borderDark : AppColors.dividerLight,
          ),

          // 4. Terms & Conditions
          _buildMenuRow(
            icon: Icons.description_outlined,
            title: 'Terms & Conditions'.tr,
            subtitle: 'Service rules & delivery terms'.tr,
            textColor: textColor,
            secondaryColor: secondaryColor,
            onTap: () => context.push(RouteNames.termsConditions),
          ),
        ],
      ),
    );
  }

  /// Reusable Menu Row with right arrow chevron navigation indicator
  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color secondaryColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: secondaryColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: secondaryColor, size: 18),
          ],
        ),
      ),
    );
  }

  void _protectedNavigation(String targetRoute, bool isLoggedIn) {
    if (isLoggedIn) {
      context.push(targetRoute);
    } else {
      context.push(
        '${RouteNames.login}?from=${Uri.encodeComponent(targetRoute)}',
      );
    }
  }

  /// Log Out Button
  Widget _buildLogoutButton(Color cardColor, bool isDark) {
    return InkWell(
      onTap: () {
        Haptics.medium();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Log Out'.tr),
            content: Text(
              'Are you sure you want to log out of your account?'.tr,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel'.tr),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6464),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Captured before the await: the profile screen is replaced
                  // below, and nothing else routes a logged-out user anywhere
                  // (the router has no auth guard) — they were left on a
                  // profile screen with no user, i.e. blank.
                  final router = GoRouter.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(authViewModelProvider.notifier).logout();
                  router.go(AppRoutePaths.authPhone);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Logged out successfully'.tr),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  'Log Out'.tr,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, color: Color(0xFFFF6464), size: 20),
            const SizedBox(width: 10),
            Text(
              'Log Out'.tr,
              style: const TextStyle(
                color: Color(0xFFFF6464),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Log In Button
  Widget _buildLoginButton(Color cardColor) {
    return InkWell(
      onTap: () {
        Haptics.light();
        context.push(
          '${RouteNames.login}?from=${Uri.encodeComponent(RouteNames.profile)}',
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB800),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.login_rounded, color: Colors.black, size: 20),
            const SizedBox(width: 10),
            Text(
              'Log In to Account'.tr,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DYNAMIC INTERACTIVE MODALS & BOTTOM SHEETS
  // ==========================================

  void _showAddressManagerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final addresses = ref.watch(addressViewModelProvider);

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Saved Addresses 📍'.tr,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: addresses.length,
                  itemBuilder: (context, i) {
                    final addr = addresses[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: Icon(
                          addr.type == 'Home'
                              ? Icons.home_rounded
                              : (addr.type == 'Work'
                                    ? Icons.work_rounded
                                    : Icons.location_on_rounded),
                          color: const Color(0xFFFFB800),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                addr.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (addr.isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFFB800,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'DEFAULT'.tr,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFE5A600),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          addr.fullAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () {
                            Haptics.light();
                            ref
                                .read(addressViewModelProvider.notifier)
                                .deleteAddress(addr.id);
                          },
                        ),
                        onTap: () {
                          Haptics.light();
                          ref
                              .read(addressViewModelProvider.notifier)
                              .setDefaultAddress(addr.id);
                        },
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                  ),
                  onPressed: () {
                    Haptics.light();
                    Navigator.pop(ctx);
                    context.push(RouteNames.addAddress);
                  },
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: Text(
                    'Add New Address'.tr,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCouponsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final coupons = ref.watch(couponsViewModelProvider);

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available Coupons 🏷️'.tr,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: coupons.length,
                  itemBuilder: (context, i) {
                    final c = coupons[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Flexible(
                              child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFB800,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                c.code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE5A600),
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.discountText,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.description,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Haptics.light();
                                Clipboard.setData(ClipboardData(text: c.code));
                                Navigator.pop(ctx);
                                AppSnackbar.success(
                                  context,
                                  'Coupon code {code} copied!'.trArgs({'code': c.code}),
                                );
                              },
                              child: Text(
                                'COPY'.tr,
                                style: const TextStyle(
                                  color: Color(0xFFE5A600),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNotificationsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final notifSettings = ref.watch(notificationsViewModelProvider);

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification Preferences 🔔'.tr,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Order Status & Delivery Alerts'.tr),
                    value: notifSettings.orderStatus,
                    activeThumbColor: const Color(0xFFFFB800),
                    onChanged: (val) {
                      Haptics.light();
                      ref
                          .read(notificationsViewModelProvider.notifier)
                          .toggleOrderStatus(val);
                    },
                  ),
                  SwitchListTile(
                    title: Text('Promotional Offers & Discounts'.tr),
                    value: notifSettings.promoOffers,
                    activeThumbColor: const Color(0xFFFFB800),
                    onChanged: (val) {
                      Haptics.light();
                      ref
                          .read(notificationsViewModelProvider.notifier)
                          .togglePromoOffers(val);
                    },
                  ),
                  SwitchListTile(
                    title: Text('App Sound & Haptic Alerts'.tr),
                    value: notifSettings.soundAlerts,
                    activeThumbColor: const Color(0xFFFFB800),
                    onChanged: (val) {
                      Haptics.light();
                      ref
                          .read(notificationsViewModelProvider.notifier)
                          .toggleSoundAlerts(val);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAppearanceModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Theme Appearance 🎨'.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _themeOptionTile(
                ctx,
                'Light Mode',
                'Light',
                Icons.wb_sunny_outlined,
              ),
              _themeOptionTile(
                ctx,
                'Dark Mode',
                'Dark',
                Icons.dark_mode_outlined,
              ),
              _themeOptionTile(
                ctx,
                'System Default',
                'System',
                Icons.settings_brightness_outlined,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeOptionTile(
    BuildContext ctx,
    String label,
    String value,
    IconData icon,
  ) {
    final currentThemeValue = _getThemeString(ref.watch(themeProvider));
    final isSelected = currentThemeValue == value;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFFFFB800) : Colors.grey,
      ),
      title: Text(
        label.tr,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: Color(0xFFFFB800))
          : null,
      onTap: () {
        Haptics.light();
        ref.read(themeProvider.notifier).setTheme(value);
        Navigator.pop(ctx);
      },
    );
  }

  void _showRateAppModal() {
    int rating = 5;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enjoying JhatPat? ⭐'.tr,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a star to rate your experience'.tr,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFFFB800),
                          size: 36,
                        ),
                        onPressed: () {
                          Haptics.light();
                          setSheetState(() => rating = index + 1);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                      ),
                      onPressed: () {
                        Haptics.success();
                        Navigator.pop(ctx);
                        AppSnackbar.success(
                          context,
                          'Thank you for giving us {rating} stars! ❤️'.trArgs({'rating': rating}),
                        );
                      },
                      child: Text(
                        'Submit Rating'.tr,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
