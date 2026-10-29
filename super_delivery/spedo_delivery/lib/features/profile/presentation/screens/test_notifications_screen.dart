import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/order_overlay_service.dart';

/// Diagnostic screen for "pushes aren't arriving": shows which Firebase project
/// the app is on, permissions, the FCM token, and lets the rider save the token
/// and ask the backend to send a test push — with the raw server answer.
class TestNotificationsScreen extends ConsumerStatefulWidget {
  const TestNotificationsScreen({super.key});

  static const expectedProjectId = 'jhatpat-d0e4f';

  @override
  ConsumerState<TestNotificationsScreen> createState() =>
      _TestNotificationsScreenState();
}

class _TestNotificationsScreenState
    extends ConsumerState<TestNotificationsScreen> with WidgetsBindingObserver {
  String? _projectId;
  String? _appId;
  String? _firebaseError;

  AuthorizationStatus? _authStatus;
  String? _permissionError;
  bool _requestingPermission = false;

  bool? _overlayGranted;

  String? _token;
  String? _tokenError;
  bool _loadingToken = true;

  bool _saving = false;
  String? _saveResult;
  bool? _saveOk;

  bool _sending = false;
  int? _testStatus;
  String? _testResult;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFirebase();
    _loadPermissions();
    _loadToken();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPermissions();
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

  Future<void> _loadPermissions() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _authStatus = settings.authorizationStatus;
        _permissionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _permissionError = e.toString());
    }
    if (Platform.isAndroid) {
      try {
        final granted = await OrderOverlayService.hasPermission();
        if (mounted) setState(() => _overlayGranted = granted);
      } catch (_) {
        if (mounted) setState(() => _overlayGranted = null);
      }
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _requestingPermission = true);
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!mounted) return;
      setState(() => _authStatus = settings.authorizationStatus);
    } catch (e) {
      if (!mounted) return;
      setState(() => _permissionError = e.toString());
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _requestOverlay() async {
    try {
      await OrderOverlayService.requestPermission();
    } catch (_) {}
    await _loadPermissions();
  }

  Future<void> _loadToken() async {
    setState(() {
      _loadingToken = true;
      _tokenError = null;
    });
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        if (token == null) _tokenError = 'getToken() returned null';
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
    if (token == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FCM token copied')),
      );
    } catch (_) {}
  }

  String _pretty(Object? data) {
    if (data == null) return '(empty body)';
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return data.toString();
    }
  }

  String _dioErrorText(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    return [
      'HTTP ${status ?? '-'} (${e.type.name})',
      if (body != null) _pretty(body) else (e.message ?? e.toString()),
    ].join('\n');
  }

  Future<void> _saveToken() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _saveOk = false;
        _saveResult = 'No FCM token to save — fix the token error first.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveResult = null;
    });
    try {
      final res = await ref.read(fcmServiceProvider).saveTokenToServer(token);
      if (!mounted) return;
      setState(() {
        _saveOk = true;
        _saveResult = 'HTTP ${res.statusCode}\n${_pretty(res.data)}';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saveOk = false;
        _saveResult = _dioErrorText(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveOk = false;
        _saveResult = e.toString();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest() async {
    setState(() {
      _sending = true;
      _testResult = null;
      _testStatus = null;
    });
    try {
      final res = await ref.read(dioProvider).post(ApiEndpoints.fcmTokenTest);
      if (!mounted) return;
      setState(() {
        _testStatus = res.statusCode;
        _testOk = true;
        _testResult = _pretty(res.data);
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _testStatus = e.response?.statusCode;
        _testOk = false;
        _testResult = e.response?.data != null
            ? _pretty(e.response?.data)
            : '${e.type.name}: ${e.message ?? e.toString()}';
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
    final projectOk =
        _projectId == TestNotificationsScreen.expectedProjectId;
    final authorized = _authStatus == AuthorizationStatus.authorized ||
        _authStatus == AuthorizationStatus.provisional;

    return Scaffold(
      appBar: AppBar(title: const Text('Test notifications')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(16.r),
          children: [
            _section(
              theme,
              title: 'Firebase project',
              ok: _firebaseError == null && projectOk,
              children: [
                if (_firebaseError != null)
                  _mono(theme, _firebaseError!)
                else ...[
                  _kv(theme, 'Project ID', _projectId ?? '-'),
                  _kv(theme, 'App ID', _appId ?? '-'),
                  if (!projectOk)
                    Text(
                      'Expected ${TestNotificationsScreen.expectedProjectId}',
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ],
            ),
            _section(
              theme,
              title: 'Permissions',
              ok: _authStatus == null ? null : authorized,
              children: [
                _kv(theme, 'Notifications',
                    _authStatus?.name ?? (_permissionError ?? 'checking…')),
                if (_authStatus != null && !authorized)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed:
                          _requestingPermission ? null : _requestPermission,
                      child: _requestingPermission
                          ? _spinner()
                          : const Text('Request permission'),
                    ),
                  ),
                if (Platform.isAndroid) ...[
                  _kv(
                    theme,
                    'Display over other apps',
                    _overlayGranted == null
                        ? 'unknown'
                        : (_overlayGranted! ? 'granted' : 'not granted'),
                  ),
                  if (_overlayGranted == false)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: _requestOverlay,
                        child: const Text('Grant overlay permission'),
                      ),
                    ),
                ],
              ],
            ),
            _section(
              theme,
              title: 'FCM token',
              ok: _loadingToken ? null : _token != null,
              children: [
                if (_loadingToken)
                  const Center(child: CircularProgressIndicator())
                else if (_token != null)
                  _mono(theme, _token!)
                else
                  _mono(theme, _tokenError ?? 'No token', color: Colors.red),
                SizedBox(height: 8.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _token == null ? null : _copyToken,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loadingToken ? null : _loadToken,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reload'),
                    ),
                  ],
                ),
              ],
            ),
            _section(
              theme,
              title: 'Save token to server',
              ok: _saveOk,
              children: [
                ElevatedButton(
                  onPressed: _saving ? null : _saveToken,
                  child:
                      _saving ? _spinner() : const Text('Save token to server'),
                ),
                if (_saveResult != null) ...[
                  SizedBox(height: 8.h),
                  _mono(theme, _saveResult!,
                      color: _saveOk == true ? null : Colors.red),
                ],
              ],
            ),
            _section(
              theme,
              title: 'Send test notification',
              ok: _testOk,
              children: [
                ElevatedButton(
                  onPressed: _sending ? null : _sendTest,
                  child: _sending
                      ? _spinner()
                      : const Text('Send test notification'),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Test with the app in background too — lock the phone right '
                  'after tapping.',
                  style: theme.textTheme.bodySmall,
                ),
                if (_testResult != null || _testStatus != null) ...[
                  SizedBox(height: 8.h),
                  _kv(theme, 'HTTP status', '${_testStatus ?? '-'}'),
                  if (_testResult != null)
                    _mono(theme, _testResult!,
                        color: _testOk == true ? null : Colors.red),
                ],
                SizedBox(height: 8.h),
                Text(
                  'If the server says the token is invalid / SenderId mismatch '
                  '/ not found, the backend is using a different Firebase '
                  'project than ${TestNotificationsScreen.expectedProjectId}.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner() => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );

  Widget _section(
    ThemeData theme, {
    required String title,
    required bool? ok,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (ok != null) ...[
                Icon(
                  ok ? Icons.check_circle : Icons.error,
                  color: ok ? Colors.green : Colors.red,
                  size: 20.sp,
                ),
                SizedBox(width: 8.w),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String key, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(key, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _mono(ThemeData theme, String text, {Color? color}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.sp,
          color: color ?? theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
