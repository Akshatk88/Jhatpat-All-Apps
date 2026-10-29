import 'dart:io';

import 'package:flutter/material.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';

bool _askedThisSession = false;

/// Asks — once per app session, with an explanation first — for Android's
/// "Display over other apps", which lets a new order come up over whatever
/// app is open instead of only as a notification. Called when the restaurant
/// is (or goes) Online, the moment orders can start arriving.
Future<void> maybePromptOverlayPermission(BuildContext context) async {
  if (!Platform.isAndroid || _askedThisSession) return;
  // Another dialog (e.g. the battery prompt) is up — try again next time.
  if (ModalRoute.of(context)?.isCurrent == false) return;
  _askedThisSession = true;
  if (await OrderOverlayService.hasPermission()) return;
  if (!context.mounted) return;

  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Show new orders over other apps'),
      content: const Text(
        'Allow Jhatpat Restaurant to display over other apps so a new order '
        'pops up with Accept / Reject on screen — even while you are using '
        'another app — instead of only in the notification bar.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (allow == true) await OrderOverlayService.requestPermission();
}
