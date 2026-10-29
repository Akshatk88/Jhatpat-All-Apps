import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/features/safety/application/emergency_contacts_controller.dart';
import 'package:food_user_application/features/safety/data/models/emergency_contact.dart';

const _jhatpatYellow = Color(0xFFFFB800);
const _dangerRed = Color(0xFFE53935);

/// Same rule the server applies (`EMERGENCY_CONTACT_NAME_REGEX`), so the form
/// rejects a name before the round trip rather than after.
final _nameRule = RegExp(r"^[A-Za-z]+(?:[ .'-][A-Za-z]+)*$");

/// The driver's emergency contacts — offered for a call from the SOS sheet.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(emergencyContactsControllerProvider);
    final list = async.value;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[600];

    Widget body;
    if (list == null && async.isLoading) {
      body = const Center(child: CircularProgressIndicator(color: _jhatpatYellow));
    } else if (list == null && async.hasError) {
      final err = async.error;
      body = _ErrorView(
        message: err is AppError ? err.message : 'Could not load your contacts.',
        onRetry: () => ref.read(emergencyContactsControllerProvider.notifier).reload(),
      );
    } else {
      final data = list!;
      body = RefreshIndicator(
        color: Colors.black,
        backgroundColor: _jhatpatYellow,
        onRefresh: () async {
          ref.read(emergencyContactsControllerProvider.notifier).reload();
          await ref.read(emergencyContactsControllerProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
          children: [
            Container(
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: _jhatpatYellow.withValues(alpha: isDark ? 0.14 : 0.15),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_rounded, color: textColor, size: 22.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'People you trust. They appear in the SOS screen during a '
                      'trip so you can call them in one tap. Up to ${data.limit}.',
                      style: TextStyle(color: textColor, fontSize: 13.sp, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            if (data.contacts.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 40.h),
                child: Column(
                  children: [
                    Icon(Icons.contact_phone_outlined, size: 56.sp, color: subText),
                    SizedBox(height: 12.h),
                    Text(
                      'No emergency contacts yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Add a family member or friend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: subText, fontSize: 13.sp),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < data.contacts.length; i++) ...[
                      _ContactTile(contact: data.contacts[i]),
                      if (i != data.contacts.length - 1)
                        Divider(
                          height: 1,
                          indent: 16.w,
                          endIndent: 16.w,
                          color: (subText ?? Colors.grey).withValues(alpha: 0.15),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final canAdd = list != null && !list.isFull;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency contacts')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: body,
          ),
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              backgroundColor: _jhatpatYellow,
              foregroundColor: Colors.black,
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(
                'Add contact',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
    );
  }

  Future<void> _showAddSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (_) => const _AddContactSheet(),
    );
  }
}

class _ContactTile extends ConsumerStatefulWidget {
  const _ContactTile({required this.contact});

  final EmergencyContact contact;

  @override
  ConsumerState<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends ConsumerState<_ContactTile> {
  bool _deleting = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('${widget.contact.name} will no longer appear in SOS.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove', style: TextStyle(color: _dangerRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final result = await ref
        .read(emergencyContactsControllerProvider.notifier)
        .remove(widget.contact.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    result.when(
      success: (_) {},
      failure: (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: _dangerRed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = widget.contact;
    final initial = c.name.isEmpty ? '?' : c.name[0].toUpperCase();
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      leading: CircleAvatar(
        backgroundColor: _jhatpatYellow,
        foregroundColor: Colors.black,
        child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      title: Text(
        c.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
      ),
      subtitle: Text(c.phone, style: TextStyle(fontSize: 12.sp)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Call',
            icon: Icon(Icons.call_rounded,
                color: isDark ? Colors.white : Colors.black87),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.phone)),
          ),
          _deleting
              ? Padding(
                  padding: EdgeInsets.all(12.r),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline_rounded, color: _dangerRed),
                  onPressed: _delete,
                ),
        ],
      ),
    );
  }
}

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _serverError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final result = await ref
        .read(emergencyContactsControllerProvider.notifier)
        .add(_name.text.trim(), _phone.text.trim());
    if (!mounted) return;
    result.when(
      success: (_) => Navigator.of(context).pop(),
      failure: (e) => setState(() {
        _saving = false;
        _serverError = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add emergency contact',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp),
              ),
              SizedBox(height: 16.h),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Enter a name';
                  if (!_nameRule.hasMatch(s)) return 'Use letters only';
                  return null;
                },
              ),
              SizedBox(height: 12.h),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91 ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => RegExp(r'^\d{10}$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Enter a 10-digit mobile number',
                onFieldSubmitted: (_) => _save(),
              ),
              if (_serverError != null) ...[
                SizedBox(height: 10.h),
                Text(
                  _serverError!,
                  style: TextStyle(color: _dangerRed, fontSize: 13.sp),
                ),
              ],
              SizedBox(height: 18.h),
              SizedBox(
                height: 50.h,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _jhatpatYellow,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.r),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Save contact',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.sp,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48.sp, color: Colors.grey),
            SizedBox(height: 12.h),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.sp)),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _jhatpatYellow,
                foregroundColor: Colors.black,
                elevation: 0,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
