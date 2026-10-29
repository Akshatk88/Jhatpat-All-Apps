import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_user_application/core/network/dio_client.dart';
import 'package:food_user_application/core/services/fcm_service.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';

/// Firebase project the app is expected to be registered against.
const _kExpectedProjectId = 'jhatpat-d0e4f';

/// Opens the push-notification diagnostics sheet.
Future<void> showTestNotificationsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const TestNotificationsSheet(),
  );
}

/// Shows, step by step, where push delivery breaks: Firebase project,
/// permission, token, token save, and a server-sent test push.
class TestNotificationsSheet extends ConsumerStatefulWidget {
  const TestNotificationsSheet({super.key});

  @override
  ConsumerState<TestNotificationsSheet> createState() =>
      _TestNotificationsSheetState();
}

class _TestNotificationsSheetState
    extends ConsumerState<TestNotificationsSheet> {
  String? _projectId;
  String? _appId;
  String? _firebaseError;

  AuthorizationStatus? _permission;
  String? _permissionError;
  bool _requestingPermission = false;

  String? _token;
  String? _tokenError;
  bool _loadingToken = true;

  bool _saving = false;
  bool? _saveOk;
  String? _saveMessage;

  bool _sending = false;
  String? _testResult;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _loadFirebase();
    _loadPermission();
    _loadToken();
    _loadOverlay();
  }

  void _loadFirebase() {
    try {
      final options = Firebase.app().options;
      _projectId = options.projectId;
      _appId = options.appId;
    } catch (e) {
      _firebaseError = e.toString();
    }
  }

  bool? _overlayGranted;
  bool _requestingOverlay = false;

  Future<void> _loadOverlay() async {
    final granted = await OrderOverlayService.hasPermission();
    if (mounted) setState(() => _overlayGranted = granted);
  }

  Future<void> _requestOverlay() async {
    setState(() => _requestingOverlay = true);
    final granted = await OrderOverlayService.requestPermission();
    if (mounted) {
      setState(() {
        _overlayGranted = granted;
        _requestingOverlay = false;
      });
    }
  }

  Future<void> _loadPermission() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _permission = settings.authorizationStatus;
        _permissionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _permissionError = e.toString());
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _requestingPermission = true);
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      if (mounted) setState(() => _permissionError = e.toString());
    }
    await _loadPermission();
    if (mounted) setState(() => _requestingPermission = false);
  }

  Future<void> _loadToken() async {
    setState(() {
      _loadingToken = true;
      _tokenError = null;
    });
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _token = token;
        if (token == null || token.isEmpty) {
          _tokenError = 'FCM returned no token for this device';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _tokenError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingToken = false);
    }
  }

  Future<void> _copyToken() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied')));
    } catch (_) {}
  }

  Future<void> _saveToken() async {
    setState(() {
      _saving = true;
      _saveOk = null;
      _saveMessage = null;
    });
    try {
      final ok = await ref.read(fcmServiceProvider).saveTokenToServer();
      if (!mounted) return;
      setState(() {
        _saveOk = ok;
        _saveMessage = ok
            ? 'Token saved to server'
            : (FcmService.lastRegistrationError ??
                  'Not saved (are you signed in?)');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveOk = false;
        _saveMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _pretty(Object? data) {
    if (data == null) return 'null';
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return data.toString();
    }
  }

  Future<void> _sendTest() async {
    setState(() {
      _sending = true;
      _testOk = null;
      _testResult = null;
    });
    try {
      final response = await ref
          .read(dioProvider)
          .post('/fcm-tokens/test', data: <String, dynamic>{});
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testResult =
            'HTTP ${response.statusCode}\n'
            '(data field; success:true wrapper removed by the client)\n'
            '${_pretty(response.data)}';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult =
            'HTTP ${e.response?.statusCode ?? '-'}\n'
            '${e.response != null ? _pretty(e.response?.data) : (e.error ?? e.message ?? e.type.name).toString()}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectOk = _projectId == _kExpectedProjectId;
    final permissionOk =
        _permission == AuthorizationStatus.authorized ||
        _permission == AuthorizationStatus.provisional;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Test notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 1. Firebase project
              _section(
                theme,
                title: 'Firebase project',
                ok: _firebaseError == null && projectOk,
                child: _firebaseError != null
                    ? SelectableText(_firebaseError!)
                    : SelectableText(
                        'Project: ${_projectId ?? '-'}'
                        '${projectOk ? '' : '  (expected $_kExpectedProjectId)'}\n'
                        'App id: ${_appId ?? '-'}',
                      ),
              ),

              // 2. Permission
              _section(
                theme,
                title: 'Notification permission',
                ok: _permissionError == null && permissionOk,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      _permissionError ?? (_permission?.name ?? 'checking…'),
                    ),
                    if (_permission != null &&
                        _permission != AuthorizationStatus.authorized) ...[
                      const SizedBox(height: 8),
                      _button(
                        label: 'Request permission',
                        loading: _requestingPermission,
                        onPressed: _requestPermission,
                      ),
                    ],
                  ],
                ),
              ),

              // 2b. Display over other apps
              _section(
                theme,
                title: 'Display over other apps',
                ok: _overlayGranted,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _overlayGranted == null
                          ? 'checking…'
                          : _overlayGranted!
                          ? 'Allowed — new orders pop up over other apps.'
                          : 'Not allowed — new orders only ring as a '
                                'notification while the app is closed.',
                    ),
                    if (_overlayGranted == false) ...[
                      const SizedBox(height: 8),
                      _button(
                        label: 'Allow',
                        loading: _requestingOverlay,
                        onPressed: _requestOverlay,
                      ),
                    ],
                  ],
                ),
              ),

              // 3. Token
              _section(
                theme,
                title: 'FCM token',
                ok: _loadingToken
                    ? null
                    : (_tokenError == null && (_token?.isNotEmpty ?? false)),
                child: _loadingToken
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_token != null && _token!.isNotEmpty)
                            SelectableText(
                              _token!,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          if (_tokenError != null)
                            SelectableText(
                              _tokenError!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: (_token?.isNotEmpty ?? false)
                                    ? _copyToken
                                    : null,
                                icon: const Icon(Icons.copy, size: 18),
                                label: const Text('Copy'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _loadToken,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Reload'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),

              // 4. Save token
              _section(
                theme,
                title: 'Save token to server',
                ok: _saveOk,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _button(
                      label: 'Save token to server',
                      loading: _saving,
                      onPressed: _saveToken,
                    ),
                    if (_saveMessage != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(_saveMessage!),
                    ],
                  ],
                ),
              ),

              // 5. Send test
              _section(
                theme,
                title: 'Send test notification',
                ok: _testOk,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _button(
                      label: 'Send test notification',
                      loading: _sending,
                      onPressed: _sendTest,
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _testResult!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'If the server says the token is invalid / SenderId '
                      'mismatch / not found, the backend is using a different '
                      'Firebase project than $_kExpectedProjectId.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),
              Text(
                'Test with the app in background too — lock the phone right '
                'after tapping.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    ThemeData theme, {
    required String title,
    required Widget child,
    bool? ok,
  }) {
    final Widget status = ok == null
        ? Icon(Icons.help_outline, color: theme.disabledColor, size: 20)
        : ok
        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
        : Icon(Icons.cancel, color: theme.colorScheme.error, size: 20);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              status,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: TextStyle(
              color: ok == false && title == 'Firebase project'
                  ? theme.colorScheme.error
                  : null,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
