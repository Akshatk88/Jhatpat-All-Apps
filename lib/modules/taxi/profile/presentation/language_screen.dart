import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/design_system/components/ride/custom_app_bar.dart';
import 'package:superapp_user/modules/taxi/profile/application/locale_provider.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(localeProvider);

    return Scaffold(
      appBar: CustomAppBar(title: 'Language'.tr),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: supportedLanguages.length,
        itemBuilder: (context, index) {
          final lang = supportedLanguages[index];
          final isSelected = lang['code'] == selected;
          return ListTile(
            title: Text(lang['label']!.tr),
            subtitle: Text(lang['native']!),
            trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: TaxiColors.primary) : null,
            onTap: () {
              ref.read(localeProvider.notifier).setLocale(lang['code']!);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Language set to {language}'.trArgs({'language': lang['label']!.tr}))),
              );
            },
          );
        },
      ),
    );
  }
}
