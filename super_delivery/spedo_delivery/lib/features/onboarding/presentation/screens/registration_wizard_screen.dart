import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/result.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import '../../../auth/data/models/delivery_partner.dart';
import '../../application/registration_draft.dart';
import '../../application/registration_wizard_controller.dart';
import '../../data/onboarding_models.dart';
import '../widgets/documents_step.dart';
import '../widgets/onboarding_ui.dart';
import '../widgets/personal_step.dart';
import '../widgets/review_step.dart';
import '../widgets/service_step.dart';
import '../widgets/vehicle_step.dart';

/// Partner sign-up, driven by the backend's onboarding catalogue:
/// service → details → vehicle → documents → review.
///
/// Progress lives in [registrationWizardProvider], not in this widget, so it
/// survives step changes, back navigation and the screen being rebuilt.
class RegistrationWizardScreen extends ConsumerStatefulWidget {
  const RegistrationWizardScreen({super.key, this.phone = ''});

  final String phone;

  @override
  ConsumerState<RegistrationWizardScreen> createState() =>
      _RegistrationWizardScreenState();
}

class _RegistrationWizardScreenState
    extends ConsumerState<RegistrationWizardScreen> {
  /// The number this registration is for, captured once: submitting changes
  /// the auth state, and a getter re-reading it would then evaluate to ''
  /// and send the registration with no phone on it.
  late final String _phone;
  DeliveryPartner? _previous;

  final _personalKey = GlobalKey<FormState>();
  final _vehicleKey = GlobalKey<FormState>();
  final _documentsKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  late final PersonalFields _personal;
  late final TextEditingController _vehicleName;
  late final TextEditingController _vehicleNumber;
  final Map<String, TextEditingController> _docNumbers = {};

  bool _showErrors = false;
  bool _submitting = false;
  String? _stepError;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _phone = widget.phone.isNotEmpty
        ? widget.phone
        : (auth is AuthNeedsRegistration ? auth.phone : '');
    _previous = auth is AuthNeedsRegistration ? auth.previousApplication : null;

    _personal = PersonalFields(
      name: TextEditingController(),
      email: TextEditingController(),
      address: TextEditingController(),
      city: TextEditingController(),
      state: TextEditingController(),
      referral: TextEditingController(),
    );
    _vehicleName = TextEditingController();
    _vehicleNumber = TextEditingController();

    // Riverpod refuses provider writes while the tree is building (initState
    // runs inside a build), so the draft is bound to this number right after
    // the first frame; until then the body shows a spinner.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(registrationWizardProvider.notifier)
          .attach(phone: _phone, previous: _previous);
      final d = ref.read(registrationWizardProvider);
      _personal.name.text = d.name;
      _personal.email.text = d.email;
      _personal.address.text = d.address;
      _personal.city.text = d.city;
      _personal.state.text = d.state;
      _personal.referral.text = d.referralCode;
      _vehicleName.text = d.vehicleName;
      _vehicleNumber.text = d.vehicleNumber;
      setState(() => _ready = true);
    });

    // The referral code is read from storage asynchronously after attach.
    ref.listenManual(
      registrationWizardProvider.select((s) => s.referralCode),
      (_, next) {
        if (_personal.referral.text.isEmpty && next.isNotEmpty) {
          _personal.referral.text = next;
        }
      },
    );
  }

  bool _ready = false;

  @override
  void dispose() {
    _personal.dispose();
    _vehicleName.dispose();
    _vehicleNumber.dispose();
    for (final c in _docNumbers.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  TextEditingController _docNumber(String key) => _docNumbers.putIfAbsent(
    key,
    () => TextEditingController(
      text: ref.read(registrationWizardProvider).upload(key).number,
    ),
  );

  void _syncPersonal() {
    ref
        .read(registrationWizardProvider.notifier)
        .updatePersonal(
          name: _personal.name.text,
          email: _personal.email.text,
          address: _personal.address.text,
          city: _personal.city.text,
          state: _personal.state.text,
          referralCode: _personal.referral.text,
        );
  }

  RequirementsQuery _query(RegistrationDraft d) =>
      (driverClass: d.driverClass, intentsCsv: d.intentsCsv);

  void _retryRequirements() {
    final d = ref.read(registrationWizardProvider);
    ref.invalidate(onboardingRequirementsProvider(_query(d)));
  }

  void _goTo(WizardStep step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _showErrors = false;
      _stepError = null;
    });
    ref.read(registrationWizardProvider.notifier).goTo(step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _fail(String message) {
    setState(() {
      _showErrors = true;
      _stepError = message;
    });
  }

  Future<void> _next() async {
    final d = ref.read(registrationWizardProvider);
    switch (d.step) {
      case WizardStep.service:
        final classes = ref.read(onboardingOptionsProvider).value;
        if (classes == null) return _fail('Options are still loading.');
        final cls = classes.where((c) => c.key == d.driverClass).firstOrNull;
        if (cls == null) return _fail('Choose what you want to do.');
        if (cls.intents.isNotEmpty && d.intents.isEmpty) {
          return _fail('Pick at least one option under "${cls.label}".');
        }
        _goTo(WizardStep.personal);

      case WizardStep.personal:
        _syncPersonal();
        if (!(_personalKey.currentState?.validate() ?? false)) {
          return _fail('Please fix the highlighted fields.');
        }
        _goTo(WizardStep.vehicle);

      case WizardStep.vehicle:
        final req = ref.read(onboardingRequirementsProvider(_query(d))).value;
        if (req == null) return _fail('Vehicle types are still loading.');
        if (req.vehicleTypes.isEmpty) {
          return _fail('No vehicle types are available for this choice.');
        }
        // Drops a selection the current list does not offer (a prefilled
        // legacy value, or one from before the answer changed).
        ref
            .read(registrationWizardProvider.notifier)
            .dropVehicleTypeIfMissing(req.vehicleTypes);
        if (ref.read(registrationWizardProvider).vehicleTypeId.isEmpty) {
          return _fail('Select your vehicle type.');
        }
        final formOk = _vehicleKey.currentState?.validate() ?? false;
        if (!formOk) return _fail('Please fix the highlighted fields.');
        final status = await ref
            .read(registrationWizardProvider.notifier)
            .checkVehicleNumber();
        if (!mounted) return;
        switch (status) {
          case VehicleCheckStatus.available:
            _goTo(WizardStep.documents);
          case VehicleCheckStatus.taken:
            _vehicleKey.currentState?.validate();
            _fail(
              'This vehicle number is already registered with another '
              'partner.',
            );
          case VehicleCheckStatus.failed:
            final msg = ref.read(registrationWizardProvider).vehicleCheck.message;
            _fail("Couldn't verify the vehicle number. $msg");
          case VehicleCheckStatus.checking:
          case VehicleCheckStatus.idle:
            _fail('Checking the vehicle number — try again in a moment.');
        }

      case WizardStep.documents:
        final req = ref.read(onboardingRequirementsProvider(_query(d))).value;
        if (req == null) return _fail('The document list is still loading.');
        final formOk = _documentsKey.currentState?.validate() ?? true;
        final problems = documentProblems(d, req);
        if (!formOk || problems.isNotEmpty) {
          return _fail(
            problems.isEmpty
                ? 'Please fix the highlighted fields.'
                : problems.length == 1
                ? problems.first
                : '${problems.first} (and ${problems.length - 1} more)',
          );
        }
        _goTo(WizardStep.review);

      case WizardStep.review:
        await _submit();
    }
  }

  Future<void> _submit() async {
    final d = ref.read(registrationWizardProvider);
    final req = ref.read(onboardingRequirementsProvider(_query(d))).value;
    if (req == null) return _fail('Requirements are still loading.');
    // Re-check everything the earlier steps checked: a step can be edited
    // from here and the list may have been refreshed since.
    final problems = documentProblems(d, req);
    final vehicleOk = req.vehicleTypes.any((v) => v.id == d.vehicleTypeId);
    if (!vehicleOk || problems.isNotEmpty) {
      return _fail(
        !vehicleOk ? 'Select your vehicle type.' : problems.first,
      );
    }
    setState(() {
      _submitting = true;
      _stepError = null;
    });
    final result = await ref
        .read(registrationWizardProvider.notifier)
        .submit(req);
    if (!mounted) return;
    setState(() => _submitting = false);
    result.when(
      // The auth state is now pending approval; the router moves on.
      success: (_) {},
      failure: (e) => setState(() => _stepError = e.message),
    );
  }

  Future<void> _handleBack() async {
    if (_submitting) return;
    if (ref.read(registrationWizardProvider).step != WizardStep.service) {
      _syncPersonal();
      _goTo(
        WizardStep.values[ref.read(registrationWizardProvider).step.index - 1],
      );
      return;
    }
    final auth = ref.read(authControllerProvider.notifier);
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave registration?'),
        content: Text(
          _previous != null
              ? 'Your re-application is not submitted yet.'
              : 'What you have filled in is kept until you close the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    if (_previous != null) {
      auth.cancelReapplication();
      return;
    }
    auth.resetToUnauthenticated();
    if (mounted) context.go('/phone-login');
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(registrationWizardProvider);
    final needsReq = d.step.index >= WizardStep.vehicle.index;
    final AsyncValue<OnboardingRequirements>? req =
        needsReq && d.driverClass.isNotEmpty
        ? ref.watch(onboardingRequirementsProvider(_query(d)))
        : null;

    final Widget body = !_ready
        ? const LoadStateView.loading()
        : switch (d.step) {
      WizardStep.service => ServiceStep(showErrors: _showErrors),
      WizardStep.personal => PersonalStep(
        formKey: _personalKey,
        fields: _personal,
        phone: _phone,
        onChanged: _syncPersonal,
      ),
      WizardStep.vehicle => VehicleStep(
        formKey: _vehicleKey,
        requirements: req ?? const AsyncLoading(),
        vehicleName: _vehicleName,
        vehicleNumber: _vehicleNumber,
        showErrors: _showErrors,
        onRetry: _retryRequirements,
      ),
      WizardStep.documents => DocumentsStep(
        formKey: _documentsKey,
        requirements: req ?? const AsyncLoading(),
        numberController: _docNumber,
        showErrors: _showErrors,
        onRetry: _retryRequirements,
      ),
      WizardStep.review => switch (req) {
        AsyncData(:final value) => ReviewStep(
          requirements: value,
          onEdit: _goTo,
          errorText: _stepError,
        ),
        AsyncError(:final error) => LoadStateView.error(
          message: error is OnboardingLoadException
              ? error.message
              : 'Could not load your requirements.',
          onRetry: _retryRequirements,
        ),
        _ => const LoadStateView.loading(),
      },
    };

    final isLast = d.step == WizardStep.review;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _handleBack,
          ),
          title: Text(_previous != null ? 'Fix your application' : 'Become a partner'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
                    child: _WizardProgress(
                      current: d.step,
                      furthest: d.furthestStep,
                      onTap: _submitting ? null : _goTo,
                    ),
                  ),
                  if (_previous != null && d.step == WizardStep.service)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: _ReapplyNote(reason: _previous!.rejectionReason),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                      child: body,
                    ),
                  ),
                  _BottomBar(
                    error: isLast ? null : (_showErrors ? _stepError : null),
                    showBack: d.step != WizardStep.service,
                    onBack: _submitting ? null : _handleBack,
                    nextLabel: isLast ? 'Submit application' : 'Continue',
                    onNext: _next,
                    loading:
                        _submitting ||
                        d.vehicleCheck.status == VehicleCheckStatus.checking &&
                            d.step == WizardStep.vehicle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({
    required this.current,
    required this.furthest,
    required this.onTap,
  });

  final WizardStep current;
  final WizardStep furthest;
  final ValueChanged<WizardStep>? onTap;

  @override
  Widget build(BuildContext context) {
    final steps = WizardStep.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Step ${current.index + 1} of ${steps.length}  ',
                style: TextStyle(color: OnboardingColors.muted(context)),
              ),
              TextSpan(
                text: current.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: OnboardingColors.text(context),
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 13.sp),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            for (final s in steps) ...[
              Expanded(
                child: Semantics(
                  label: 'Step ${s.index + 1}: ${s.label}',
                  button: s.index <= furthest.index && s != current,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap != null &&
                            s.index <= furthest.index &&
                            s.index < current.index
                        ? () => onTap!(s)
                        : null,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.h),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 6,
                        decoration: BoxDecoration(
                          color: s.index <= current.index
                              ? OnboardingColors.brand
                              : OnboardingColors.border(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (s != steps.last) SizedBox(width: 4.w),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReapplyNote extends StatelessWidget {
  const _ReapplyNote({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 4.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: OnboardingColors.brand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(
        [
          if (reason != null && reason!.trim().isNotEmpty)
            'Reason given: ${reason!.trim()}',
          'Your earlier answers are filled in. Photos must be added again.',
        ].join('\n'),
        style: TextStyle(
          fontSize: 12.5.sp,
          height: 1.4,
          color: OnboardingColors.text(context),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.error,
    required this.showBack,
    required this.onBack,
    required this.nextLabel,
    required this.onNext,
    required this.loading,
  });

  final String? error;
  final bool showBack;
  final VoidCallback? onBack;
  final String nextLabel;
  final VoidCallback onNext;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              ErrorBanner(error!),
              SizedBox(height: 10.h),
            ],
            Row(
              children: [
                if (showBack) ...[
                  OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OnboardingColors.text(context),
                      side: BorderSide(color: OnboardingColors.border(context)),
                      minimumSize: Size(0, 50.h),
                      padding: EdgeInsets.symmetric(horizontal: 14.w),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                  SizedBox(width: 10.w),
                ],
                Expanded(
                  child: BrandButton(
                    label: nextLabel,
                    onPressed: onNext,
                    isLoading: loading,
                    icon: Icons.arrow_forward_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
