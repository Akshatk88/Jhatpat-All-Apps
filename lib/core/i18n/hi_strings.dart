import 'package:superapp_user/core/i18n/hi/hi_common.dart';
import 'package:superapp_user/core/i18n/hi/hi_food.dart';
import 'package:superapp_user/core/i18n/hi/hi_food2.dart';
import 'package:superapp_user/core/i18n/hi/hi_parcel.dart';
import 'package:superapp_user/core/i18n/hi/hi_services.dart';
import 'package:superapp_user/core/i18n/hi/hi_shared.dart';
import 'package:superapp_user/core/i18n/hi/hi_taxi.dart';

/// Every Hindi UI string, English text → Hindi. Split per area so each part
/// of the app keeps its own list; when two areas translate the same English
/// string, the later one here wins (they should agree anyway).
final Map<String, String> hiStrings = {
  ...hiCommon,
  ...hiShared,
  ...hiFood,
  ...hiFood2,
  ...hiTaxi,
  ...hiParcel,
  ...hiServices,
};
