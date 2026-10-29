import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/network/network_providers.dart';
import 'package:superapp_user/core/push/push_providers.dart';
import 'package:superapp_user/core/push/push_service.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';

/// Diagnostic screen for push delivery: shows which Firebase project the app
/// is on, the permission state and FCM token, and lets the user re-save the
/// token and ask the backend (`POST /fcm-tokens/test`) to send a test push.
class PushTestScreen extends ConsumerStatefulWidget {
  const PushTestScreen({super.key});

  static const expectedProjectId = 'jhatpat-d0e4f';

  @override
  ConsumerState<PushTestScreen> createState() => _PushTestScreenState();
}

class _PushTestScreenState extends ConsumerState<PushTestScreen> {
  String? _projectId;
  String? _appId;
  String? _firebaseError;

  AuthorizationStatus? _authStatus;
  String? _permissionError;
  bool _requestingPermission = false;

  String? _token;
  String? _tokenError;
  bool _loadingToken = false;

  bool _saving = false;
  String? _saveResult;
  bool? _saveOk;

  bool _sending = false;
  String? _sendResult;
  bool? _sendOk;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadFirebase();
    await Future.wait([_loadPermission(), _loadToken()]);
  }

  Future<void> _loadFirebase() async {
    try {
      await ensureFirebaseInitialized();
      final options = Firebase.app().options;
      if (!mounted) return;
      setState(() {
        _projectId = options.projectId;
        _appId = options.appId;
        _firebaseError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _firebaseError = e.toString());
    }
  }

  Future<void> _loadPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _authStatus = settings.authorizationStatus;
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
      final settings = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (!mounted) return;
      setState(() {
        _authStatus = settings.authorizationStatus;
        _permissionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _permissionError = e.toString());
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _loadToken() async {
    setState(() => _loadingToken = true);
    try {
      final existing = ref.read(pushServiceProvider).token;
      final token = (existing != null && existing.isNotEmpty)
          ? existing
          : await FirebaseMessaging.instance.getToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _tokenError = (token == null || token.isEmpty) ? 'getToken() returned null' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _token = null;
        _tokenError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _loadingToken = false);
    }
  }

  Future<void> _copyToken() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    AppSnackbar.success(context, 'FCM token copied');
  }

  Future<void> _saveToken() async {
    setState(() {
      _saving = true;
      _saveResult = null;
      _saveOk = null;
    });
    try {
      final user = ref.read(authViewModelProvider).value;
      final push = ref.read(pushServiceProvider);
      // Same path the app uses after login (food backend + every token sink).
      await push.registerToken(user: user);
      final token = push.token;
      if (token == null || token.isEmpty) {
        throw Exception('PushService has no token after registerToken() — see [FCM] logs');
      }
      // registerToken() swallows the backend outcome, so repeat the
      // idempotent upsert once to surface what the server actually said.
      final res = await ref.read(apiClientProvider).raw.post(
            ApiPaths.fcmSaveMobile,
            data: {'token': token},
            options: Options(validateStatus: (_) => true),
          );
      final code = res.statusCode ?? 0;
      if (!mounted) return;
      setState(() {
        _token = token;
        _saveOk = code >= 200 && code < 300;
        _saveResult = 'HTTP $code\n${_pretty(res.data)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveOk = false;
        _saveResult = _describeError(e);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest() async {
    setState(() {
      _sending = true;
      _sendResult = null;
      _sendOk = null;
    });
    try {
      // Raw Dio (still carries the bearer via ApiClient's interceptor) so the
      // full status + body is visible instead of a collapsed Failure.
      final res = await ref.read(apiClientProvider).raw.post(
            ApiPaths.fcmTest,
            options: Options(validateStatus: (_) => true),
          );
      final code = res.statusCode ?? 0;
      final body = res.data;
      final envelopeOk = !(body is Map && body['success'] == false);
      if (!mounted) return;
      setState(() {
        _sendOk = code >= 200 && code < 300 && envelopeOk;
        _sendResult = 'HTTP $code${code == 401 ? ' (session expired — log in again)' : ''}\n${_pretty(body)}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendOk = false;
        _sendResult = _describeError(e);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _pretty(dynamic data) {
    if (data == null) return '(empty body)';
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return data.toString();
    }
  }

  String _describeError(Object e) {
    if (e is DioException) {
      final r = e.response;
      return 'DioException (${e.type.name})'
          '${r != null ? '\nHTTP ${r.statusCode}\n${_pretty(r.data)}' : ''}'
          '${e.message != null ? '\n${e.message}' : ''}';
    }
    if (e is Failure) return '${e.runtimeType}: ${e.message}';
    return e.toString();
  }

  bool get _authorized =>
      _authStatus == AuthorizationStatus.authorized ||
      _authStatus == AuthorizationStatus.provisional;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final cardColor = isDark ? AppColors.cardDark : Colors.white;
    final codeBg = isDark ? const Color(0xFF1B1B1B) : const Color(0xFFF4F5F7);

    final projectOk = _projectId == PushTestScreen.expectedProjectId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Test notifications'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          // Tablets / desktop: keep the cards a readable width, centred.
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width > 752
                ? (MediaQuery.sizeOf(context).width - 720) / 2
                : 16,
            8,
            MediaQuery.sizeOf(context).width > 752
                ? (MediaQuery.sizeOf(context).width - 720) / 2
                : 16,
            28,
          ),
          children: [
            // 1. Firebase project
            _card(
              cardColor,
              title: 'Firebase project',
              textColor: textColor,
              children: [
                if (_firebaseError != null)
                  _statusLine(Icons.error_rounded, AppColors.error, _firebaseError!, textColor)
                else if (_projectId == null)
                  const _Loading()
                else ...[
                  _statusLine(
                    projectOk ? Icons.check_circle_rounded : Icons.error_rounded,
                    projectOk ? AppColors.success : AppColors.error,
                    projectOk
                        ? _projectId!
                        : '$_projectId (expected ${PushTestScreen.expectedProjectId})',
                    textColor,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    'App ID: ${_appId ?? '-'}',
                    style: TextStyle(fontSize: 12.5, color: secondaryColor),
                  ),
                ],
              ],
            ),

            // 2. Permission
            _card(
              cardColor,
              title: 'Notification permission',
              textColor: textColor,
              children: [
                if (_permissionError != null)
                  _statusLine(Icons.error_rounded, AppColors.error, _permissionError!, textColor)
                else if (_authStatus == null)
                  const _Loading()
                else
                  _statusLine(
                    _authorized ? Icons.check_circle_rounded : Icons.block_rounded,
                    _authorized ? AppColors.success : AppColors.error,
                    _authStatus!.name,
                    textColor,
                  ),
                if (_authStatus != null && !_authorized) ...[
                  const SizedBox(height: 10),
                  _primaryButton(
                    label: 'Request permission',
                    loading: _requestingPermission,
                    onPressed: _requestPermission,
                  ),
                ],
              ],
            ),

            // 3. Token
            _card(
              cardColor,
              title: 'FCM token',
              textColor: textColor,
              children: [
                if (_loadingToken)
                  const _Loading()
                else if (_tokenError != null)
                  _statusLine(Icons.error_rounded, AppColors.error, _tokenError!, textColor)
                else
                  _codeBox(_token ?? '-', codeBg, textColor),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _primaryButton(
                        label: 'Copy',
                        icon: Icons.copy_rounded,
                        onPressed: (_token == null || _token!.isEmpty) ? null : _copyToken,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _primaryButton(
                        label: 'Save token to server',
                        loading: _saving,
                        onPressed: _saveToken,
                      ),
                    ),
                  ],
                ),
                if (_saveResult != null) ...[
                  const SizedBox(height: 10),
                  _resultBox(_saveOk == true, _saveResult!, codeBg, textColor),
                ],
              ],
            ),

            // 4. Send test
            _card(
              cardColor,
              title: 'Send test notification',
              textColor: textColor,
              children: [
                Text(
                  'Asks the server (POST ${ApiPaths.fcmTest}) to push to this account\'s saved tokens.',
                  style: TextStyle(fontSize: 12.5, color: secondaryColor),
                ),
                const SizedBox(height: 10),
                _primaryButton(
                  label: 'Send test notification',
                  icon: Icons.send_rounded,
                  loading: _sending,
                  onPressed: _sendTest,
                ),
                if (_sendResult != null) ...[
                  const SizedBox(height: 10),
                  _resultBox(_sendOk == true, _sendResult!, codeBg, textColor),
                ],
                const SizedBox(height: 10),
                Text(
                  'If the server says the token is invalid / SenderId mismatch / not found, '
                  'the backend is using a different Firebase project than '
                  '${PushTestScreen.expectedProjectId}.',
                  style: TextStyle(fontSize: 12.5, color: secondaryColor, height: 1.4),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Test with the app in background too — lock the phone right after tapping.',
                      style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    Color cardColor, {
    required String title,
    required Color textColor,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _statusLine(IconData icon, Color color, String text, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            text,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
          ),
        ),
      ],
    );
  }

  Widget _codeBox(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: SelectableText(
        text,
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: textColor, height: 1.35),
      ),
    );
  }

  Widget _resultBox(bool ok, String text, Color bg, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: ok ? AppColors.success : AppColors.error,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              ok ? 'Success' : 'Failed',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ok ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _codeBox(text, bg, textColor),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    IconData? icon,
    bool loading = false,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.black54,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.black),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary),
        ),
      ),
    );
  }
}
