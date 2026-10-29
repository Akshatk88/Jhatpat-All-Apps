import 'package:flutter/material.dart';

import '../../../onboarding/presentation/screens/registration_wizard_screen.dart';

/// `/register` — partner sign-up.
///
/// The old single static form (fixed vehicle list, four hardcoded documents,
/// a DriveU opt-in and a UPI QR upload the backend ignored on this route) is
/// replaced by the backend-driven wizard: what the partner is asked for now
/// comes from `/food/delivery/onboarding/*`.
class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key, this.phone = ''});

  final String phone;

  @override
  Widget build(BuildContext context) => RegistrationWizardScreen(phone: phone);
}
