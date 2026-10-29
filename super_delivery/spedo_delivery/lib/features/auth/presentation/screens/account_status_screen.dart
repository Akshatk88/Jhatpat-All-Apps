import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/result.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../onboarding/application/registration_wizard_controller.dart';
import '../../../onboarding/presentation/widgets/onboarding_ui.dart';
import '../../../onboarding/presentation/widgets/service_step.dart'
    show classIcon;
import '../../application/auth_controller.dart';
import '../../application/auth_state.dart';
import '../../data/models/delivery_partner.dart';

/// Pending / rejected application.
///
/// A partner who is not approved holds no token — the backend issues none
/// before approval — so the taxi `approval-status`, `documents/:key` and
/// `vehicle` routes (and `/food/delivery/reverify`, which needs an approved
/// account) are all out of reach here. What this screen knows comes from the
/// verify-otp / register replies; a rejected partner fixes their application
/// by registering again, which the backend allows for a rejected phone.
class AccountStatusScreen extends ConsumerStatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  ConsumerState<AccountStatusScreen> createState() =>
      _AccountStatusScreenState();
}

class _AccountStatusScreenState extends ConsumerState<AccountStatusScreen> {
  bool _isChecking = false;

  /// With a token, re-read `/auth/me`. Without one (the normal case before
  /// approval) the only way to ask is to verify the number again.
  Future<void> _refreshStatus(String? phone) async {
    setState(() => _isChecking = true);
    final controller = ref.read(authControllerProvider.notifier);
    final hasToken = await ref.read(tokenStorageProvider).hasAccessToken();
    if (hasToken) {
      await controller.checkAuthStatus();
      if (mounted) setState(() => _isChecking = false);
      return;
    }
    if (phone == null || phone.isEmpty) {
      controller.resetToUnauthenticated();
      if (mounted) context.go('/phone-login');
      return;
    }
    final result = await controller.requestOtp(phone);
    if (!mounted) return;
    setState(() => _isChecking = false);
    result.when(
      success: (_) {
        final router = GoRouter.of(context);
        controller.resetToUnauthenticated();
        // Login underneath, so the OTP screen's back arrow has somewhere to
        // return to; pushed a frame later, once the `go` has settled.
        router.go('/phone-login');
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => router.push('/otp-verify', extra: phone),
        );
      },
      failure: (e) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message))),
    );
  }

  void _reapply() {
    final ok = ref.read(authControllerProvider.notifier).startReapplication();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please log in again with your number to update your application.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final pending = authState is AuthPendingApproval ? authState : null;
    final isRejected = pending?.isRejected ?? false;
    final rejectionReason = pending?.rejectionReason;
    final partner = pending?.partner;
    final phone = pending?.phone ?? partner?.phone;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 32.h).clamp(0.0, double.infinity),
                  maxWidth: 560,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 12.h),
                    Center(
                      child: Container(
                        width: 88.w,
                        height: 88.w,
                        decoration: BoxDecoration(
                          color: (isRejected
                                  ? OnboardingColors.error
                                  : OnboardingColors.brand)
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRejected
                              ? Icons.assignment_late_rounded
                              : Icons.hourglass_top_rounded,
                          color: isRejected
                              ? OnboardingColors.error
                              : OnboardingColors.onBrand,
                          size: 44.sp,
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      isRejected
                          ? 'Application not approved'
                          : 'Application under review',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w800,
                        color: OnboardingColors.text(context),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      isRejected
                          ? 'You can fix what was wrong and send your '
                                'application again.'
                          : 'Our team is reviewing your documents. This '
                                'usually takes 24–48 hours. We will notify '
                                'you once approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.sp,
                        height: 1.5,
                        color: OnboardingColors.muted(context),
                      ),
                    ),
                    if (isRejected) ...[
                      SizedBox(height: 16.h),
                      _ReasonCard(reason: rejectionReason),
                    ],
                    if (partner != null) ...[
                      SizedBox(height: 16.h),
                      _ApplicationSummary(
                        partner: partner,
                        isRejected: isRejected,
                      ),
                    ],
                    SizedBox(height: 24.h),
                    if (isRejected) ...[
                      BrandButton(
                        label: 'Fix & re-apply',
                        icon: Icons.edit_document,
                        onPressed: _reapply,
                      ),
                      SizedBox(height: 10.h),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isChecking
                          ? null
                          : () => _refreshStatus(phone),
                      icon: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Check status'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OnboardingColors.text(context),
                        minimumSize: Size(0, 48.h),
                        side: const BorderSide(color: OnboardingColors.brand),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    ),
                    if (phone != null && phone.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h),
                        child: Text(
                          "We'll send an OTP to +91 $phone to check.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: OnboardingColors.muted(context),
                          ),
                        ),
                      ),
                    SizedBox(height: 8.h),
                    TextButton(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).logout(),
                      child: Text(
                        'Log out',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: OnboardingColors.muted(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final text = reason?.trim() ?? '';
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: OnboardingColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: OnboardingColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reason from our team',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: OnboardingColors.error,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            text.isNotEmpty
                ? text
                : 'No reason was given. Contact support if you are unsure '
                      'what to change.',
            style: TextStyle(
              fontSize: 14.sp,
              height: 1.45,
              color: OnboardingColors.text(context),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DocState { submitted, missing, reupload }

/// What was submitted, set against what the catalogue asks this partner for
/// now. The backend keeps no per-document verdict — the review covers the
/// application as a whole — so a document is "submitted" or "missing" here,
/// and on a rejection every photo has to be sent again.
class _ApplicationSummary extends ConsumerWidget {
  const _ApplicationSummary({required this.partner, required this.isRejected});

  final DeliveryPartner partner;
  final bool isRejected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cls = partner.driverClass ?? '';
    final reqAsync = cls.isEmpty
        ? null
        : ref.watch(
            onboardingRequirementsProvider((
              driverClass: cls,
              intentsCsv: partner.serviceIntents.join(','),
            )),
          );
    final classLabel = (ref.watch(onboardingOptionsProvider).value ?? const [])
        .where((c) => c.key == cls)
        .firstOrNull
        ?.label;

    final submitted = {
      for (final d in partner.onboardingDocuments)
        if (d.key.isNotEmpty) d.key: d,
    };

    final rows = <(String, _DocState, String)>[];
    final req = reqAsync?.value;
    if (req != null) {
      for (final doc in req.documents) {
        final s = submitted.remove(doc.key);
        final has = s != null && s.hasImage;
        if (!has && !doc.isRequired) continue;
        rows.add((
          doc.name,
          !has
              ? _DocState.missing
              : (isRejected ? _DocState.reupload : _DocState.submitted),
          doc.isRequired ? 'Required' : 'Optional',
        ));
      }
    }
    for (final s in submitted.values) {
      rows.add((
        s.name.isNotEmpty ? s.name : s.key,
        isRejected ? _DocState.reupload : _DocState.submitted,
        '',
      ));
    }
    // Applications from before the document catalogue carried these three.
    if (partner.onboardingDocuments.isEmpty) {
      for (final (name, url) in [
        ('Aadhaar card', partner.aadharPhoto),
        ('Driving licence', partner.drivingLicensePhoto),
      ]) {
        if (url != null && url.isNotEmpty) {
          rows.add((
            name,
            isRejected ? _DocState.reupload : _DocState.submitted,
            '',
          ));
        }
      }
    }

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: OnboardingColors.card(context),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: OnboardingColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                classIcon(cls),
                size: 22.sp,
                color: OnboardingColors.text(context),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  classLabel ?? 'Your application',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: OnboardingColors.text(context),
                  ),
                ),
              ),
            ],
          ),
          if ((partner.vehicleNumber ?? '').isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              'Vehicle ${partner.vehicleNumber}'
              '${(partner.vehicleName ?? '').isNotEmpty ? ' · ${partner.vehicleName}' : ''}',
              style: TextStyle(
                fontSize: 13.sp,
                color: OnboardingColors.muted(context),
              ),
            ),
          ],
          SizedBox(height: 12.h),
          Text(
            'DOCUMENTS',
            style: TextStyle(
              fontSize: 11.sp,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
              color: OnboardingColors.muted(context),
            ),
          ),
          SizedBox(height: 4.h),
          if (reqAsync != null && reqAsync.isLoading && rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: const LinearProgressIndicator(
                color: OnboardingColors.brand,
              ),
            )
          else if (rows.isEmpty)
            Text(
              'No documents on record.',
              style: TextStyle(
                fontSize: 13.sp,
                color: OnboardingColors.muted(context),
              ),
            )
          else
            for (final (name, state, note) in rows)
              _DocStatusRow(name: name, state: state, note: note),
          if (reqAsync != null && reqAsync.hasError)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                "Couldn't load the current document list.",
                style: TextStyle(
                  fontSize: 12.sp,
                  color: OnboardingColors.muted(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocStatusRow extends StatelessWidget {
  const _DocStatusRow({
    required this.name,
    required this.state,
    required this.note,
  });

  final String name;
  final _DocState state;
  final String note;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (state) {
      _DocState.submitted => (
        Icons.check_circle_rounded,
        OnboardingColors.success,
        'Submitted · in review',
      ),
      _DocState.missing => (
        Icons.error_outline_rounded,
        OnboardingColors.error,
        'Not submitted',
      ),
      _DocState.reupload => (
        Icons.upload_rounded,
        const Color(0xFFB54708),
        'Upload again',
      ),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: color),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w600,
                    color: OnboardingColors.text(context),
                  ),
                ),
                Text(
                  note.isEmpty ? label : '$label · $note',
                  style: TextStyle(fontSize: 12.sp, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

