import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';

import 'package:superapp_user/core/speech/hindi_announcer.dart';

/// Small yellow pill that replays (or stops) a Hindi announcement.
class AnnounceButton extends StatelessWidget {
  final String text;
  const AnnounceButton({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final announcer = HindiAnnouncer.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: announcer.isSpeaking,
      builder: (context, speaking, _) {
        return Material(
          color: const Color(0xFFFFB800),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: text.trim().isEmpty
                ? null
                : () => speaking ? announcer.stop() : announcer.speak(text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                    size: 16,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    speaking ? 'Stop'.tr : 'Suniye'.tr,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
