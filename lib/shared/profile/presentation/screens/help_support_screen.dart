import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/app/routing/route_names.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _makePhoneCall(BuildContext context, String phoneNumber) async {
    Haptics.light();
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (context.mounted) {
          AppSnackbar.error(context, 'Could not launch dialer for {phone}'.trArgs({'phone': phoneNumber}));
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.info(context, 'Calling {phone}...'.trArgs({'phone': phoneNumber}));
      }
    }
  }

  Future<void> _sendEmail(BuildContext context, String emailAddress) async {
    Haptics.light();
    final Uri launchUri = Uri(
      scheme: 'mailto',
      path: emailAddress,
      queryParameters: {'subject': 'Support Request - JhatPat App'},
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (context.mounted) {
          AppSnackbar.error(context, 'Could not open email client for {email}'.trArgs({'email': emailAddress}));
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackbar.info(context, 'Opening mail to {email}...'.trArgs({'email': emailAddress}));
      }
    }
  }

  void _showInfoModal(BuildContext context, String title, String content) {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
        final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

        return Container(
          padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 28.h),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.borderDark : const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                content,
                style: TextStyle(
                  fontSize: 13.5.sp,
                  height: 1.4,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                height: 44.h,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text('Got It'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.backgroundDark : const Color(0xFFF9FAFB);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryTextColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.chevron_left_rounded, size: 28.sp, color: textColor),
          onPressed: () {
            Haptics.light();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Help & Support'.tr,
          style: TextStyle(
            color: textColor,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HERO BANNER CARD
              _buildHeroCard(isDark, textColor, secondaryTextColor),

              SizedBox(height: 20.h),

              // 2. QUICK HELP SECTION
              _buildSectionTitle('Quick Help'.tr, textColor),
              SizedBox(height: 10.h),
              _buildQuickHelpCard(context, isDark, textColor, secondaryTextColor),

              SizedBox(height: 20.h),

              // 3. CONTACT US SECTION (DYNAMIC CALL, MAIL, CHAT)
              _buildSectionTitle('Contact Us'.tr, textColor),
              SizedBox(height: 10.h),
              _buildContactUsCard(context, isDark, textColor, secondaryTextColor),

              SizedBox(height: 20.h),

              // 4. SUPPORT INFORMATION SECTION
              _buildSectionTitle('Support Information'.tr, textColor),
              SizedBox(height: 10.h),
              _buildSupportInfoCard(isDark, textColor, secondaryTextColor),

              SizedBox(height: 24.h),

              // 5. FOOTER
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      color: const Color(0xFFFFB800),
                      size: 16.sp,
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'Thank you for choosing JhatPat!'.tr,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'We\'re always here to help you.'.tr,
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Hero Card: Headphones Illustration + Help Text
  Widget _buildHeroCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1E1E1E),
                  const Color(0xFF181818),
                ]
              : [
                  const Color(0xFFFFFDF5),
                  const Color(0xFFFFF8E1),
                ],
        ),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFFFE8A3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We\'re here to'.tr,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'help you!'.tr,
                  style: TextStyle(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE5A600),
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Facing an issue? Our support team is ready to assist you.'.tr,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    color: secondaryTextColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          SizedBox(
            width: 125.w,
            height: 115.h,
            child: Image.asset(
              'assets/images/help_support_headphones.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.headset_mic_rounded,
                color: AppColors.primary,
                size: 64.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    );
  }

  /// 2. Quick Help Card: FAQs, Order Issues, Refund & Payments, Report a Problem
  Widget _buildQuickHelpCard(
      BuildContext context, bool isDark, Color textColor, Color secondaryTextColor) {
    final items = [
      {
        'icon': Icons.description_outlined,
        'title': 'FAQs',
        'subtitle': 'Find answers to common questions',
        'details': 'Browse our comprehensive list of answers regarding ordering, payments, delivery times, and account management.',
      },
      {
        'icon': Icons.assignment_outlined,
        'title': 'Order Issues',
        'subtitle': 'Help with your orders and tracking',
        'details': 'Missing item or wrong order? Track your order live or request an instant check from our support executive.',
      },
      {
        'icon': Icons.replay_rounded,
        'title': 'Refund & Payments',
        'subtitle': 'Queries about refunds and payments',
        'details': 'Refunds are automatically processed to your original payment method or JhatPat Wallet within 24-48 hours.',
      },
      {
        'icon': Icons.shield_outlined,
        'title': 'Report a Problem',
        'subtitle': 'Let us know if something went wrong',
        'details': 'Please describe the issue you experienced and our quality team will investigate and compensate accordingly.',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFEEEEEE),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;

          return InkWell(
            onTap: () => _showInfoModal(
              context,
              (item['title'] as String).tr,
              (item['details'] as String).tr,
            ),
            borderRadius: BorderRadius.vertical(
              top: index == 0 ? Radius.circular(16.r) : Radius.zero,
              bottom: isLast ? Radius.circular(16.r) : Radius.zero,
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8.r),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: const Color(0xFFFFB800),
                          size: 18.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (item['title'] as String).tr,
                              style: TextStyle(
                                fontSize: 13.5.sp,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              (item['subtitle'] as String).tr,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isDark ? AppColors.borderDark : const Color(0xFFCCCCCC),
                        size: 18.sp,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: 14.w,
                    endIndent: 14.w,
                    color: isDark ? AppColors.borderDark : const Color(0xFFF2F2F2),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 3. Contact Us Card: Call Us (Dynamic Phone Call), Email Us (Dynamic Mail Composer), Live Chat
  Widget _buildContactUsCard(
      BuildContext context, bool isDark, Color textColor, Color secondaryTextColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFEEEEEE),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. CALL US -> DYNAMIC PHONE CALL
          InkWell(
            onTap: () => _makePhoneCall(context, '9301988718'),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.phone_in_talk_rounded,
                      color: const Color(0xFF16A34A),
                      size: 18.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Call Us'.tr,
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Speak with our support team'.tr,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '9301988718',
                    style: TextStyle(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFE5A600),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.borderDark : const Color(0xFFCCCCCC),
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: 14.w,
            endIndent: 14.w,
            color: isDark ? AppColors.borderDark : const Color(0xFFF2F2F2),
          ),

          // 2. EMAIL US -> DYNAMIC MAIL COMPOSER
          InkWell(
            onTap: () => _sendEmail(context, 'tanuchouhan161@gmaim.com'),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mail_outline_rounded,
                      color: const Color(0xFF0284C7),
                      size: 18.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Email Us'.tr,
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'We reply as soon as possible'.tr,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'tanuchouhan161@gmaim.com',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFE5A600),
                      ),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.borderDark : const Color(0xFFCCCCCC),
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            indent: 14.w,
            endIndent: 14.w,
            color: isDark ? AppColors.borderDark : const Color(0xFFF2F2F2),
          ),

          // 3. LIVE CHAT -> CHAT SCREEN
          InkWell(
            onTap: () {
              Haptics.light();
              context.push(RouteNames.chat);
            },
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16.r)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.r),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF8E1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: const Color(0xFFE5A600),
                      size: 18.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Chat'.tr,
                          style: TextStyle(
                            fontSize: 13.5.sp,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          'Chat with our support team'.tr,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: const Color(0xFFFFE8A3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'Available 9AM - 9PM'.tr,
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF121212),
                      ),
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppColors.borderDark : const Color(0xFFCCCCCC),
                    size: 18.sp,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Support Information Card: Support Hours | Response Time | We Care
  Widget _buildSupportInfoCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFDF5),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFFFE8A3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Support Hours
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(7.r),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF0C2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    color: AppColors.primary,
                    size: 16.sp,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Support Hours'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  '9AM - 9PM\nEveryday'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: secondaryTextColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 48.h,
            width: 1,
            color: isDark ? const Color(0xFF333333) : const Color(0xFFFFE8A3),
          ),

          // 2. Response Time
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(7.r),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF0C2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.primary,
                    size: 16.sp,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Response Time'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Within 24 hours'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 48.h,
            width: 1,
            color: isDark ? const Color(0xFF333333) : const Color(0xFFFFE8A3),
          ),

          // 3. We Care
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(7.r),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF0C2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: AppColors.primary,
                    size: 16.sp,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'We Care'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Your satisfaction is\nour priority'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: secondaryTextColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
