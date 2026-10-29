import 'package:superapp_user/core/i18n/tr.dart';

class Validators {
  Validators._();

  static String? phone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      return 'Enter a valid 10-digit phone number'.tr;
    }
    return null;
  }

  static String? otp(String? value, {int length = 4}) {
    if ((value ?? '').length != length) {
      return 'Enter the {length}-digit OTP'.trArgs({'length': length});
    }
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '{field} is required'.trArgs({'field': field.tr});
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
    if (!regex.hasMatch(value.trim())) {
      return 'Enter a valid email address'.tr;
    }
    return null;
  }
}
