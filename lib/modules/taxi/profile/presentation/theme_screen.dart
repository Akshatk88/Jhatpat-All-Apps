import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/design_system/theme/taxi_theme_provider.dart';
import 'package:superapp_user/design_system/components/ride/custom_app_bar.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    Widget option(ThemeMode value, IconData icon, String title, String subtitle) {
      final selected = mode == value;
      return RadioListTile<ThemeMode>(
        value: value,
        groupValue: mode,
        onChanged: (v) => ref.read(themeModeProvider.notifier).setThemeMode(v!),
        secondary: Icon(icon),
        title: Text(title.tr),
        subtitle: Text(subtitle.tr),
        selected: selected,
      );
    }

    return Scaffold(
      appBar: CustomAppBar(title: 'App theme'.tr),
      body: ListView(
        children: [
          option(ThemeMode.system, Icons.brightness_auto_rounded, 'System default',
              'Match your device settings'),
          option(ThemeMode.light, Icons.light_mode_rounded, 'Light', 'Bright, high-contrast theme'),
          option(ThemeMode.dark, Icons.dark_mode_rounded, 'Dark', 'Easy on the eyes at night'),
        ],
      ),
    );
  }
}
