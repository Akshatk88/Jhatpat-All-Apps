import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/modules/taxi/auth/application/auth_providers.dart';
import 'package:superapp_user/design_system/components/ride/app_text_field.dart';
import 'package:superapp_user/design_system/components/ride/custom_app_bar.dart';
import 'package:superapp_user/design_system/components/ride/primary_button.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _reasonController = TextEditingController();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Delete account'.tr),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TaxiColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: TaxiColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This submits a request for admin review. Your account, ride history and wallet balance may be permanently removed once approved.'.tr,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _reasonController,
              label: 'Reason for leaving'.tr,
              hint: 'Tell us why you want to delete your account'.tr,
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            TaxiPrimaryButton(
              label: 'Submit deletion request'.tr,
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_reasonController.text.trim().isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete account?'.tr),
        content: Text('This action cannot be undone once approved. Continue?'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete'.tr, style: const TextStyle(color: TaxiColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);
    try {
      await ref.read(taxiAuthRepositoryProvider).requestAccountDeletion(_reasonController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deletion request submitted for review'.tr)),
        );
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit request. Please try again.'.tr)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
