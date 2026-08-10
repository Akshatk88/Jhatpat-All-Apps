import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/core/utils/taxi_validators.dart';
import 'package:superapp_user/design_system/components/ride/app_text_field.dart';
import 'package:superapp_user/design_system/components/ride/primary_button.dart';
import 'package:superapp_user/modules/taxi/auth/application/auth_providers.dart';

class TaxiProfileSetupScreen extends ConsumerStatefulWidget {
  final String phone;
  const TaxiProfileSetupScreen({super.key, required this.phone});

  @override
  ConsumerState<TaxiProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<TaxiProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _referralController = TextEditingController();
  String? _gender;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).completeSignup(
            phone: widget.phone,
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            gender: _gender,
            referralCode: _referralController.text.trim(),
          );
      if (mounted) context.go('/auth/location-permission');
    } catch (error) {
      if (mounted) SnackbarUtils.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _referralController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create your profile', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text(
                  'Tell us a little about yourself to finish setting up your account.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                AppTextField(
                  label: 'Full name',
                  hint: 'Enter your full name',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline_rounded,
                  validator: (v) => Validators.required(v, field: 'Name'),
                ),
                const SizedBox(height: 18),
                AppTextField(
                  label: 'Email (optional)',
                  hint: 'you@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.alternate_email_rounded,
                  validator: Validators.email,
                ),
                const SizedBox(height: 18),
                Text('Gender (optional)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: ['male', 'female', 'other'].map((option) {
                    final selected = _gender == option;
                    return ChoiceChip(
                      label: Text(option[0].toUpperCase() + option.substring(1)),
                      selected: selected,
                      onSelected: (_) => setState(() => _gender = option),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                AppTextField(
                  label: 'Referral code (optional)',
                  hint: 'Enter referral code',
                  controller: _referralController,
                  prefixIcon: Icons.card_giftcard_rounded,
                ),
                const SizedBox(height: 32),
                TaxiPrimaryButton(
                  label: 'Create account',
                  isLoading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
