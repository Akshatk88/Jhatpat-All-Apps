import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/shared/wallet/data/wallet_model.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:superapp_user/shared/referral/presentation/viewmodels/referral_viewmodel.dart';
import 'package:superapp_user/shared/referral/presentation/widgets/ticket_clipper.dart';

class ReferralTicketCard extends ConsumerWidget {
  final double? width;
  final double? height;

  static const double aspectRatio = 417 / 520;

  const ReferralTicketCard({
    super.key,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(referralDetailsProvider).value ?? const ReferralDetails();
    final user = ref.watch(authViewModelProvider).value;

    final code = details.referralCode.isNotEmpty
        ? details.referralCode
        : (user?.referralCode.isNotEmpty == true ? user!.referralCode : 'SUVO25');
    final rewardStr = details.rewardAmount > 0
        ? '₹${details.rewardAmount.toStringAsFixed(0)}'
        : '₹100';

    final cardWidth = width ?? 260.w;
    final cardHeight = height ?? (cardWidth / aspectRatio);
    final notch = 14.r;

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipPath(
        clipper: TicketCardClipper(notch: notch),
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFB800), Color(0xFFFFC72C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Top Logo Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(6.r),
                        decoration: const BoxDecoration(
                          color: Colors.black12,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fastfood_rounded,
                          color: Colors.black,
                          size: 18.sp,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          'SUVIO FOOD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      'TICKET'.tr,
                      style: TextStyle(
                        color: const Color(0xFFFFC72C),
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              // 2. Dashed Divider Line (Custom Row of small containers)
              Row(
                children: List.generate(
                  24,
                  (index) => Expanded(
                    child: Container(
                      height: 1.5.h,
                      color: index % 2 == 0 ? Colors.black38 : Colors.transparent,
                    ),
                  ),
                ),
              ),

              // 3. Center Reward Amount
              Column(
                children: [
                  Text(
                    'YOU & YOUR FRIEND GET'.tr,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    rewardStr,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 34.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'On 1st successful order'.tr,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),

              // 4. Bottom Referral Code Box
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Column(
                  children: [
                    Text(
                      'REFERRAL CODE'.tr,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      code,
                      style: TextStyle(
                        color: const Color(0xFF121212),
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
