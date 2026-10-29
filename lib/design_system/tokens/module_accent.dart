import 'package:flutter/material.dart';

/// Per-module brand colour.
///
/// This is how the super app stays visually coherent while each module keeps
/// its own identity — the hub and shared screens use [hub], and entering a
/// module re-accents that route subtree only.
///
/// Note the two inherited brands were *different* oranges: Justorder shipped
/// `0xFFFF7A00` and UdanX `0xFFFF5C2B`. Both are preserved here rather than
/// silently reconciled — which one (if either) becomes the super-app brand is
/// a product decision, not an architectural one.
enum ModuleAccent {
  /// Hub and shared surfaces (wallet, activity, profile, settings).
  hub(Color(0xFFFFB800), Color(0xFFE5A600)),

  /// Jhatpat Golden Yellow.
  food(Color(0xFFFFB800), Color(0xFFE5A600)),

  /// UdanX orange.
  taxi(Color(0xFFFFB800), Color(0xFFE5A600)),

  parcel(Color(0xFFFFB800), Color(0xFFE5A600)),


  /// Home services — teal, deliberately far from both inherited oranges so a
  /// user can tell at a glance which vertical they are inside.
  services(Color(0xFFFFB800), Color(0xFFE5A600));

  const ModuleAccent(this.primary, this.primaryVariant);

  /// Main brand colour for the module.
  final Color primary;

  /// Slightly shifted variant, used for buttons and pressed states.
  final Color primaryVariant;
}
