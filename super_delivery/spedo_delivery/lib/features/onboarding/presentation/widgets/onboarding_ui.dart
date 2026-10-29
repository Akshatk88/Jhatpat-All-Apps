import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';

/// Brand yellow with black text — the partner-onboarding look.
class OnboardingColors {
  OnboardingColors._();

  static const Color brand = Color(0xFFFFB800);
  static const Color onBrand = Color(0xFF111111);
  static const Color error = Color(0xFFD92D20);
  static const Color success = Color(0xFF12B76A);

  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF1E1E1E)
      : Colors.white;

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white24
      : const Color(0xFFE4E7EC);

  static Color muted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white70
      : const Color(0xFF667085);

  static Color text(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.white
      : onBrand;
}

/// A vehicle/document image path from the backend as a loadable URL, or ''
/// when it is neither absolute nor host-relative.
String resolveMediaUrl(String raw) {
  final v = raw.trim();
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  if (v.startsWith('/')) return '${AppConstants.apiHost}$v';
  return '';
}

InputDecoration onboardingInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? helper,
}) {
  final radius = BorderRadius.circular(12.r);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    helperMaxLines: 3,
    errorMaxLines: 3,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: OnboardingColors.card(context),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: OnboardingColors.border(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: OnboardingColors.border(context)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: OnboardingColors.brand, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: OnboardingColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: const BorderSide(color: OnboardingColors.error, width: 1.6),
    ),
    floatingLabelStyle: TextStyle(color: OnboardingColors.text(context)),
  );
}

class StepHeading extends StatelessWidget {
  const StepHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              color: OnboardingColors.text(context),
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4.h),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13.sp,
                height: 1.4,
                color: OnboardingColors.muted(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8.h, bottom: 10.h),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: OnboardingColors.muted(context),
        ),
      ),
    );
  }
}

/// Loading / error-with-retry block used by every step that reads the server.
class LoadStateView extends StatelessWidget {
  const LoadStateView.loading({super.key, this.label = 'Loading…'})
    : message = null,
      onRetry = null;

  const LoadStateView.error({
    super.key,
    required String this.message,
    required VoidCallback this.onRetry,
  }) : label = '';

  final String label;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isError = message != null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 32.h, horizontal: 8.w),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isError)
              Icon(
                Icons.cloud_off_rounded,
                size: 40.sp,
                color: OnboardingColors.muted(context),
              )
            else
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: OnboardingColors.brand,
                ),
              ),
            SizedBox(height: 12.h),
            Text(
              isError ? message! : label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5.sp,
                color: OnboardingColors.muted(context),
                height: 1.4,
              ),
            ),
            if (isError) ...[
              SizedBox(height: 12.h),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: OnboardingColors.text(context),
                  side: const BorderSide(color: OnboardingColors.brand),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: OnboardingColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: OnboardingColors.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: OnboardingColors.error,
            size: 18.sp,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: OnboardingColors.error,
                fontSize: 13.sp,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand primary action: yellow fill, black label.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.dimmed = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Still tappable (so it can say what is missing) but looks unfinished.
  final bool dimmed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 50.h),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: OnboardingColors.brand.withValues(
            alpha: dimmed ? 0.45 : 1,
          ),
          foregroundColor: OnboardingColors.onBrand,
          disabledBackgroundColor: OnboardingColors.brand.withValues(
            alpha: 0.5,
          ),
          disabledForegroundColor: OnboardingColors.onBrand,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: OnboardingColors.onBrand,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    SizedBox(width: 6.w),
                    Icon(icon, size: 18.sp),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Camera on Android; gallery everywhere. iOS is gallery-only because the
/// Runner's Info.plist declares no camera usage string, and asking for the
/// camera without one terminates the app.
Future<String?> pickOnboardingImage(BuildContext context) async {
  final allowCamera =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  ImageSource? source = ImageSource.gallery;
  if (allowCamera) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
  if (source == null) return null;
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return picked?.path;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the camera or gallery. Check app permissions.'),
        ),
      );
    }
    return null;
  }
}

/// One image slot: thumbnail or placeholder, label, required marker.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    super.key,
    required this.label,
    required this.path,
    required this.onPicked,
    required this.onRemove,
    this.required = false,
    this.showError = false,
  });

  final String label;
  final String? path;
  final ValueChanged<String> onPicked;
  final VoidCallback onRemove;
  final bool required;
  final bool showError;

  @override
  Widget build(BuildContext context) {
    final hasFile = path != null;
    final borderColor = showError && !hasFile
        ? OnboardingColors.error
        : hasFile
        ? OnboardingColors.brand
        : OnboardingColors.border(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () async {
          final picked = await pickOnboardingImage(context);
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: OnboardingColors.card(context),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: borderColor, width: hasFile ? 1.4 : 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: SizedBox(
                  width: 52.w,
                  height: 52.w,
                  child: hasFile
                      ? Image.file(
                          File(path!),
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )
                      : Container(
                          color: OnboardingColors.brand.withValues(alpha: 0.14),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: OnboardingColors.onBrand,
                            size: 22.sp,
                          ),
                        ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: label,
                        children: [
                          if (required)
                            const TextSpan(
                              text: ' *',
                              style: TextStyle(color: OnboardingColors.error),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w600,
                        color: OnboardingColors.text(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      hasFile
                          ? 'Tap to change'
                          : (showError ? 'Photo required' : 'Tap to add a photo'),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: showError && !hasFile
                            ? OnboardingColors.error
                            : OnboardingColors.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasFile)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: OnboardingColors.muted(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A network image with an icon fallback, for vehicle art.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.url,
    required this.fallback,
    this.size = 44,
  });

  final String url;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(url);
    final icon = Icon(fallback, size: size * 0.6, color: OnboardingColors.onBrand);
    if (resolved.isEmpty) return SizedBox(width: size, height: size, child: icon);
    return SizedBox(
      width: size,
      height: size,
      child: CachedNetworkImage(
        imageUrl: resolved,
        fit: BoxFit.contain,
        placeholder: (_, _) => icon,
        errorWidget: (_, _, _) => icon,
      ),
    );
  }
}
