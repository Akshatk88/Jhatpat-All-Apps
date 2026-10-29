import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/core/i18n/language_provider.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/haptics.dart';

/// English / हिन्दी picker. Used from the header's language button, from
/// profile, and once after login ([firstTime]: must pick, no dismiss).
Future<void> showLanguageSheet(BuildContext context, {bool firstTime = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: !firstTime,
    enableDrag: !firstTime,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LanguageSheet(firstTime: firstTime),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet({required this.firstTime});

  final bool firstTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = ref.watch(localeProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15171C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC803),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.translate_rounded, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Both scripts, so it reads right whichever language
                        // the app is in when this opens.
                        Text(
                          'Choose language / भाषा चुनें',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You can change it any time from the top bar.'.tr,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final lang in supportedLanguages) ...[
                _LanguageOption(
                  native: lang['native']!,
                  label: lang['label']!,
                  letter: lang['code'] == 'hi' ? 'अ' : 'A',
                  selected: lang['code'] == current,
                  isDark: isDark,
                  onTap: () {
                    Haptics.light();
                    ref.read(localeProvider.notifier).setLocale(lang['code']!);
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.native,
    required this.label,
    required this.letter,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String native;
  final String label;
  final String letter;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFFFFF6D6)
          : (isDark ? const Color(0xFF1F2229) : Colors.white),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFB800)
                  : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFFC803) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      native,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: selected || !isDark
                            ? const Color(0xFF0F172A)
                            : Colors.white,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? const Color(0xFFE5A600) : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
