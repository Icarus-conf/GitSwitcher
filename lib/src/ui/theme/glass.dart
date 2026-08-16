import 'package:flutter/material.dart';

/// Design tokens for GitSwitcher's glass surfaces.
///
/// In a glass interface the material carries the design, so the palette stays
/// almost entirely achromatic and lets each account supply the only real hue.
/// That is the app's whole job: telling identities apart at a glance.
class Glass {
  const Glass._();

  // Structure
  static const double radius = 16;
  static const double slabPadding = 18;
  static const double gutter = 14;

  // Achromatic ground
  static const Color ink = Color(0xFF0B0D10);
  static const Color frost = Color(0xFFF2F5F9);

  /// The active account's state colour. macOS uses this green for "live".
  static const Color live = Color(0xFF30D158);

  /// Per-account accents, from the macOS system palette. Assigned by position
  /// so an account keeps its colour for as long as the list is stable.
  static const List<Color> accents = [
    Color(0xFF0A84FF), // blue
    Color(0xFFBF5AF2), // purple
    Color(0xFFFF9F0A), // orange
    Color(0xFF64D2FF), // teal
    Color(0xFFFF375F), // pink
  ];

  static Color accentFor(int index) => accents[index % accents.length];

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// The slab fill.
  ///
  /// These sit on top of the window's frosted vibrancy layer, so they only
  /// need enough opacity to separate a card from that ground — the blur has
  /// already been done underneath.
  static Color slabFill(BuildContext context, {required bool lit}) {
    if (isDark(context)) {
      return Colors.white.withValues(alpha: lit ? 0.20 : 0.10);
    }
    return Colors.white.withValues(alpha: lit ? 0.85 : 0.58);
  }

  static Color slabStroke(BuildContext context, {required bool lit}) {
    if (isDark(context)) {
      return Colors.white.withValues(alpha: lit ? 0.30 : 0.14);
    }
    return Colors.white.withValues(alpha: lit ? 0.95 : 0.62);
  }

  static Color primaryText(BuildContext context) =>
      isDark(context) ? const Color(0xFFF7F9FC) : ink;

  static Color secondaryText(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.58)
      : ink.withValues(alpha: 0.55);

  /// Machine-written identifiers: usernames, emails, key paths, folder rules.
  ///
  /// These are set in mono on purpose. The human name is who you are; the
  /// monospaced string is what git and gh actually record.
  static TextStyle mono(
    BuildContext context, {
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['SFMono-Regular', 'Menlo', 'Courier'],
      fontSize: size,
      fontWeight: weight,
      letterSpacing: 0,
      color: color ?? secondaryText(context),
    );
  }

  static TextStyle display(
    BuildContext context, {
    double size = 17,
    FontWeight weight = FontWeight.w600,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: -0.4,
      color: primaryText(context),
    );
  }

  static TextStyle body(BuildContext context, {double size = 13}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: secondaryText(context),
      );

  /// Small uppercase section marker.
  static TextStyle eyebrow(BuildContext context) => TextStyle(
        fontFamily: 'SF Mono',
        fontFamilyFallback: const ['SFMono-Regular', 'Menlo', 'Courier'],
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: secondaryText(context),
      );
}
