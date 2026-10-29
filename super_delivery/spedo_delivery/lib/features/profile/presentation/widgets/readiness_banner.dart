import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/services/device_readiness_service.dart';
import '../../application/availability_controller.dart';
import '../screens/delivery_readiness_screen.dart';

/// Persistent warning while the rider is online but a device setting that
/// delivers offers has regressed (notification permission revoked, alert
/// channel muted, battery restriction back, ...).
///
/// Setup is checked before going online, but nothing stops the rider (or an OS
/// update, or a battery "optimiser") undoing it later. Re-checked on every
/// resume and whenever the rider goes online; renders nothing when all is well.
class ReadinessBanner extends ConsumerStatefulWidget {
  const ReadinessBanner({super.key});

  @override
  ConsumerState<ReadinessBanner> createState() => _ReadinessBannerState();
}

class _ReadinessBannerState extends ConsumerState<ReadinessBanner>
    with WidgetsBindingObserver {
  List<ReadinessCheck> _missing = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _recheck() async {
    if (!Platform.isAndroid) return;
    final checks = await DeviceReadinessService.evaluate();
    if (!mounted) return;
    setState(() {
      // Autostart can never be read back, so it is never "missing" here.
      _missing = checks
          .where((c) => c.critical && !c.satisfied && c.id != 'autostart')
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(availabilityControllerProvider);
    ref.listen<bool>(availabilityControllerProvider, (prev, next) {
      if (next && prev != true) _recheck();
    });
    if (!online || _missing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: 8.h),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DeliveryReadinessScreen()),
          );
          _recheck();
        },
        child: Container(
          padding: EdgeInsets.all(12.r),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'You may miss orders: ${_missing.map((c) => c.title).join(', ')}.'
                  ' Tap to fix.',
                  style: TextStyle(fontSize: 12.5.sp, height: 1.35),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
