import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/_taxi_staging/core/theme/app_colors.dart';
import 'package:superapp_user/_taxi_staging/shared/widgets/primary_button.dart';

class AccountCreatedScreen extends StatelessWidget {
  const AccountCreatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                height: 150,
                width: 150,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: TaxiColors.accentGradient),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, size: 72, color: TaxiColors.primary),
              ),
              const SizedBox(height: 32),
              Text(
                'You\'re all set!',
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has been created successfully. Let\'s book your first ride.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              TaxiPrimaryButton(
                label: 'Go to Home',
                onPressed: () => context.go('/home'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
