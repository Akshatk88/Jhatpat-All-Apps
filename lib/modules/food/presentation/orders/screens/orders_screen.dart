import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/modules/food/data/models/order_model.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/components/layout/app_refresh_indicator.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/app/routing/route_names.dart';
import 'package:superapp_user/modules/food/presentation/orders/utils/reorder.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/orders_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/orders/widgets/rate_order_sheet.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  String _selectedFilter = 'All'; // 'All', 'Delivered', 'Cancelled'
  String? _reorderingOrderId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ordersViewModelProvider.notifier).refresh();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(ordersViewModelProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showFilterModal() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final filters = ['All', 'Delivered', 'Cancelled'];

        return Container(
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter Orders 🔍'.tr,
                style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12.h),
              ...filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return ListTile(
                  title: Text(
                    filter.tr,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected ? const Color(0xFFE5A600) : null,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFFFFB800),
                        )
                      : null,
                  onTap: () {
                    Haptics.light();
                    setState(() => _selectedFilter = filter);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : const Color(0xFF1E1E1E);
    final secondaryColor = isDark
        ? AppColors.textSecondaryDark
        : const Color(0xFF6B7280);
    final backgroundColor = isDark
        ? AppColors.backgroundDark
        : const Color(0xFFF4F6F8);

    final ordersState = ref.watch(ordersViewModelProvider);

    List<OrderModel> activeList = ordersState.active;
    List<OrderModel> pastList = ordersState.past;

    // Apply Filter
    if (_selectedFilter == 'Delivered') {
      pastList = pastList
          .where((o) => o.isDelivered || o.orderStatus == 'delivered')
          .toList();
    } else if (_selectedFilter == 'Cancelled') {
      pastList = pastList
          .where((o) => o.isCancelled || o.orderStatus.contains('cancelled'))
          .toList();
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // 1. ORANGE GRADIENT TOP HEADER WITH TAB BAR
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFB800), Color(0xFFFFC700)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // App Bar Row
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 14.h),
                    child: Row(
                      children: [
                        _CircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () {
                            Haptics.light();
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go(RouteNames.home);
                            }
                          },
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'My Orders'.tr,
                                style: TextStyle(
                                  color: const Color(0xFF121212),
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'Track, view and reorder your food'.tr,
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  fontSize: 11.5.sp,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _CircleIconButton(
                          icon: Icons.tune_rounded,
                          onTap: _showFilterModal,
                        ),
                      ],
                    ),
                  ),

                  // White rounded container holding the TabBar
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: isDark ? AppColors.primary : const Color(0xFF121212),
                      unselectedLabelColor: isDark ? AppColors.textSecondaryDark : const Color(0xFF6B7280),
                      indicatorColor: const Color(0xFFFFB800),
                      indicatorWeight: 3.h,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.normal,
                      ),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 16.sp),
                              SizedBox(width: 6.w),
                              Flexible(
                                child: Text(
                                  'Active Orders ({count})'.trArgs({'count': activeList.length}),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 16.sp),
                              SizedBox(width: 6.w),
                              Flexible(
                                child: Text(
                                  'Past Orders ({count})'.trArgs({'count': pastList.length}),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. TAB BAR VIEW CONTENT
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrdersTabList(
                  context: context,
                  orders: activeList,
                  isActiveTab: true,
                  isDark: isDark,
                  textColor: textColor,
                  secondaryColor: secondaryColor,
                ),
                _buildOrdersTabList(
                  context: context,
                  orders: pastList,
                  isActiveTab: false,
                  isDark: isDark,
                  textColor: textColor,
                  secondaryColor: secondaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTabList({
    required BuildContext context,
    required List<OrderModel> orders,
    required bool isActiveTab,
    required bool isDark,
    required Color textColor,
    required Color secondaryColor,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20.r),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF8E1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_rounded,
                size: 40.sp,
                color: const Color(0xFFFFB800),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              isActiveTab ? 'No Active Orders'.tr : 'No Past Orders'.tr,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              isActiveTab
                  ? 'Your active food orders will appear here.'.tr
                  : 'You have no past completed or cancelled orders.'.tr,
              style: TextStyle(fontSize: 12.sp, color: secondaryColor),
            ),
          ],
        ),
      );
    }

    return AppRefreshIndicator(
      onRefresh: () => ref.read(ordersViewModelProvider.notifier).refresh(isRefresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 20.h),
        itemCount: orders.length + 1, // Orders + Need Help Card at bottom
        itemBuilder: (context, index) {
          if (index == orders.length) {
            return _buildNeedHelpCard(
              context,
              isDark,
              textColor,
              secondaryColor,
            );
          }

          final order = orders[index];
          return _buildOrderCard(
            context,
            order,
            isDark,
            textColor,
            secondaryColor,
          );
        },
      ),
    );
  }

  /// Single Order Card matching screenshot 100%
  Widget _buildOrderCard(
    BuildContext context,
    OrderModel order,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    final createdDate = order.createdAt?.toLocal();
    final dateStr = createdDate != null ? DateFormat('dd MMM yyyy').format(createdDate) : '01 Aug 2026';
    final timeStr = createdDate != null ? DateFormat('hh:mm a').format(createdDate) : '03:08 PM';
    final fullOrderedStr = createdDate != null ? DateFormat('dd MMM yyyy, hh:mm a').format(createdDate) : '01 Aug 2026, 03:06 PM';

    final totalItems = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final isCancelled = order.isCancelled || order.orderStatus.contains('cancelled');
    final isDelivered = order.isDelivered || order.orderStatus == 'delivered';

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20.r),
          onTap: () {
            Haptics.light();
            context.push('/orders/details/${order.id}');
          },
          child: Padding(
            padding: EdgeInsets.all(16.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TOP HEADER ROW (Logo, Name, Order ID, Date/Time, Status Badge)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restaurant Circle Image
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24.r),
                      child: Container(
                        width: 46.w,
                        height: 46.h,
                        decoration: const BoxDecoration(
                          color: Color(0xFF111111),
                          shape: BoxShape.circle,
                        ),
                        child: SmartImage(
                          url: order.restaurantImage.isNotEmpty
                              ? order.restaurantImage
                              : 'assets/images/about_hero.png',
                          category: ImageCategory.restaurant,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.restaurantName.isNotEmpty
                                ? order.restaurantName
                                : 'JhatPat',
                            style: TextStyle(
                              fontSize: 16.5.sp,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            'Order ID: #{id}'.trArgs({'id': order.orderNumber.isNotEmpty ? order.orderNumber : order.id}),
                            style: TextStyle(
                              fontSize: 11.5.sp,
                              color: secondaryColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4.h),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 12.sp,
                                  color: const Color(0xFFFFB800),
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: secondaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5.w),
                                  child: Text(
                                    '|',
                                    style: TextStyle(
                                      fontSize: 11.sp,
                                      color: secondaryColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.access_time_outlined,
                                  size: 12.sp,
                                  color: const Color(0xFFFFB800),
                                ),
                                SizedBox(width: 4.w),
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: secondaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 6.w),
                    // Capped so a long backend status label ellipsizes
                    // instead of squeezing the name column to nothing.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 130.w),
                      child: _buildStatusBadge(order),
                    ),
                  ],
                ),

                SizedBox(height: 14.h),

                // ITEMS & TOTAL PRICE ROW
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 7.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5.r),
                      ),
                      child: Text(
                        '${totalItems}x',
                        style: TextStyle(
                          color: const Color(0xFFE5A600),
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        totalItems == 1 ? '1 item'.tr : '{count} items'.trArgs({'count': totalItems}),
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: textColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '₹${order.total.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 12.h),

                // RATE CTA (if delivered & not rated)
                if (isDelivered && !order.hasRated) ...[
                  _buildRateCta(context, order, isDark, textColor, secondaryColor),
                  SizedBox(height: 12.h),
                ],

                // REORDER BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 44.h,
                  child: ElevatedButton.icon(
                    onPressed: _reorderingOrderId == order.id
                        ? null
                        : () async {
                            Haptics.medium();
                            if (order.isActive) {
                              context.push('/orders/track/${order.id}');
                              return;
                            }
                            setState(() => _reorderingOrderId = order.id);
                            final buyAgainItems = await resolveReorderItems(
                              ref,
                              order,
                            );
                            if (!mounted) return;
                            setState(() => _reorderingOrderId = null);
                            if (!context.mounted) return;
                            context.push(
                              RouteNames.buyAgain,
                              extra: buyAgainItems,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCancelled
                          ? (isDark ? const Color(0xFF2C1E1E) : const Color(0xFFFFF0F0))
                          : const Color(0xFFFFB800),
                      foregroundColor: isCancelled
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF121212),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        side: isCancelled
                            ? const BorderSide(color: Color(0xFFFECACA), width: 1)
                            : BorderSide.none,
                      ),
                    ),
                    icon: _reorderingOrderId == order.id
                        ? SizedBox(
                            width: 16.sp,
                            height: 16.sp,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isCancelled ? const Color(0xFFDC2626) : const Color(0xFF121212),
                            ),
                          )
                        : Icon(
                            order.isActive
                                ? Icons.navigation_rounded
                                : Icons.refresh_rounded,
                            size: 18.sp,
                            color: isCancelled ? const Color(0xFFDC2626) : const Color(0xFF121212),
                          ),
                    label: Text(
                      order.isActive ? 'TRACK ORDER'.tr : 'REORDER'.tr,
                      style: TextStyle(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w600,
                        color: isCancelled ? const Color(0xFFDC2626) : const Color(0xFF121212),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 12.h),

                // FOOTER ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Ordered: {date}'.trArgs({'date': fullOrderedStr}),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: secondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '|  ',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: secondaryColor.withValues(alpha: 0.4),
                          ),
                        ),
                        RichText(
                          text: TextSpan(
                            text: 'Bill Total: '.tr,
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: secondaryColor,
                            ),
                            children: [
                              TextSpan(
                                text: '₹${order.total.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600,
                                  color: isCancelled
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFE5A600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderModel order) {
    if (order.isDelivered || order.orderStatus == 'delivered') {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: const Color(0xFF16A34A),
              size: 14.sp,
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                'Delivered'.tr,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF15803D),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else if (order.isCancelled || order.orderStatus.contains('cancelled')) {
      final label = order.cancelledBy.toLowerCase() == 'restaurant'
          ? 'Cancelled by restaurant'.tr
          : 'Cancelled by you'.tr;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEED),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cancel_rounded,
              color: const Color(0xFFDC2626),
              size: 14.sp,
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFDC2626),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_bike_rounded,
              color: const Color(0xFFFFB800),
              size: 14.sp,
            ),
            SizedBox(width: 4.w),
            Flexible(
              child: Text(
                order.statusLabel.isNotEmpty ? order.statusLabel.tr : 'On the Way'.tr,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE5A600),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
  }

  /// Prompts the user to rate a delivered order that hasn't been rated yet.
  Widget _buildRateCta(
    BuildContext context,
    OrderModel order,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: () => _openRatingSheet(context, order),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.star_rounded, color: const Color(0xFF16A34A), size: 18.sp),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'Rate your food & delivery experience'.tr,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF15803D),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18.sp,
              color: const Color(0xFF15803D),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRatingSheet(BuildContext context, OrderModel order) async {
    Haptics.light();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RateOrderSheet(order: order),
    );
    if (result == true && context.mounted) {
      AppSnackbar.success(context, 'Thanks for rating your order!'.tr);
    }
  }

  /// Need Help? Card at bottom of screen matching screenshot
  Widget _buildNeedHelpCard(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color secondaryColor,
  ) {
    return Container(
      margin: EdgeInsets.only(top: 6.h, bottom: 20.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF231A14) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? const Color(0xFF3D2B1F) : const Color(0xFFFFE8A3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(7.r),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified_user_rounded,
              color: const Color(0xFFFFB800),
              size: 18.sp,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need Help?'.tr,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'For any issue with your order, contact our support team.'.tr,
                  style: TextStyle(fontSize: 10.5.sp, color: secondaryColor),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          InkWell(
            onTap: () {
              Haptics.light();
              context.push(RouteNames.helpSupport);
            },
            borderRadius: BorderRadius.circular(20.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: const Color(0xFFFFE8A3), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.headset_mic_rounded,
                    color: const Color(0xFFFFB800),
                    size: 14.sp,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'Contact Support'.tr,
                    style: TextStyle(
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE5A600),
                    ),
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

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        width: 38.w,
        height: 38.h,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF1E1E1E), size: 20.sp),
      ),
    );
  }
}

