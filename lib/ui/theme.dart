import 'package:flutter/material.dart';

/// Hossouko design tokens, shared with the public site (hossouko-Web
/// src/styles/tokens.css) and the customer app (hossouko-App-user/lib/ui/theme.dart)
/// so the site and both apps read as one product.
///
/// This file used to hold its own approximation of the brand palette
/// (`0xFF1A1714` ink, `0xFFD1571E` orange). Those values had drifted from the
/// canonical ones below — close enough to pass a glance, wrong enough that the
/// merchant app was subtly a different colour from everything else with the
/// Hossouko name on it. Copied verbatim from hossouko-App-user rather than
/// re-derived, so a future token change only has one other file to check
/// against.
///
/// Contrast rules carried over from the site:
/// * [orange] is a graphics colour (fills, rules, icons). White text on it is
///   only ~3.4:1, so text on an orange surface uses [orangeDeep] or larger type.
/// * [orangeDeep] and [green] both take white text at 4.5:1 or better.
class HossoukoColors {
  const HossoukoColors._();

  static const ink = Color(0xFF18221F);
  static const inkSoft = Color(0xFF3D4A44);
  static const muted = Color(0xFF5A615A);
  static const paper = Color(0xFFF5F1E8);
  static const surface = Colors.white;
  static const line = Color(0xFFE7E1D4);

  static const orange = Color(0xFFE65E32);
  static const orangeDeep = Color(0xFFC94A22);
  static const orangeDark = Color(0xFF9E3517);
  static const orangeTint = Color(0xFFFDE9DF);

  static const green = Color(0xFF234B39);
  static const greenDark = Color(0xFF173427);
  static const greenLight = Color(0xFF75975D);
  static const greenTint = Color(0xFFE3EDE5);

  static const sand = Color(0xFFF1E9D6);
  static const clay = Color(0xFFD6A284);

  static const success = Color(0xFF12855A);
  static const danger = Color(0xFFC62828);
  static const warningTint = Color(0xFFFFF3D6);

  /// Header gradient: deep orange to burnt; white text stays above 4.5:1.
  static const headerGradient = LinearGradient(
    colors: [orangeDeep, orangeDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const loyaltyGradient = LinearGradient(
    colors: [green, greenDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class HossoukoRadius {
  const HossoukoRadius._();

  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 22.0;
  static const xl = 28.0;
}

/// Soft, low shadow: depth without the muddy grey a strong shadow leaves on a
/// cheap panel.
const hossoukoShadow = [
  BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6)),
];

/// Lifted surfaces sitting on a coloured header (the day's total, a search
/// field).
const hossoukoShadowStrong = [
  BoxShadow(color: Color(0x2E3B1406), blurRadius: 28, offset: Offset(0, 12)),
];

/// The site's display face (hossouko-Web: Instrument Serif). Used for large
/// titles and numerals only; everything functional stays in the system sans,
/// which is sharper at small sizes on a low-density screen — the reason this
/// stays true even after adopting the icon font and the serif display face.
const serif = 'InstrumentSerif';

TextStyle serifStyle(double size, {Color color = HossoukoColors.ink, FontStyle? style, double height = 1.05}) =>
    TextStyle(fontFamily: serif, fontSize: size, color: color, fontStyle: style, height: height, fontWeight: FontWeight.w400);

/// Hossouko's palette, shared with the public site and the customer app.
///
/// Three constraints from the merchant app's own brief still drive every
/// choice here, even after adopting the customer app's visual language:
///
/// * **Sunlight.** The app is used at a market stall at midday. Contrast is
///   high and surfaces stay light; a dark theme is unreadable on a cheap LCD
///   outdoors.
/// * **Cheap panels.** Low-end screens render thin weights as grey mush, so
///   body text never goes below 15sp and never below w400.
/// * **Thumbs, fast.** A merchant taps while holding goods and counting change.
///   Targets are at least 48dp, which is also the Android accessibility floor.
ThemeData hossoukoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HossoukoColors.orange,
    brightness: Brightness.light,
    primary: HossoukoColors.orangeDeep,
    onPrimary: Colors.white,
    secondary: HossoukoColors.green,
    onSecondary: Colors.white,
    surface: HossoukoColors.surface,
    onSurface: HossoukoColors.ink,
    error: HossoukoColors.danger,
    outlineVariant: HossoukoColors.line,
  );
  final roundedMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(HossoukoRadius.md));
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(HossoukoRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HossoukoColors.paper,
    // The plain ripple: the M3 sparkle shader costs frames on entry-level GPUs.
    splashFactory: InkRipple.splashFactory,
    dividerColor: HossoukoColors.line,
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontFamily: serif, fontSize: 44, color: HossoukoColors.ink, height: 1.0),
      headlineMedium: TextStyle(fontFamily: serif, fontSize: 34, color: HossoukoColors.ink, height: 1.05),
      headlineSmall: TextStyle(fontFamily: serif, fontSize: 28, color: HossoukoColors.ink, height: 1.1),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: HossoukoColors.ink, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: HossoukoColors.ink),
      titleSmall: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: HossoukoColors.ink),
      // 15sp floor kept even though the customer app allows 15 for bodyMedium
      // too: a thin weight on a cheap panel in direct sunlight is the one
      // regression this theme cannot afford to reintroduce.
      bodyLarge: TextStyle(fontSize: 16, color: HossoukoColors.ink, height: 1.45),
      bodyMedium: TextStyle(fontSize: 15, color: HossoukoColors.ink, height: 1.45, fontWeight: FontWeight.w400),
      bodySmall: TextStyle(fontSize: 15, color: HossoukoColors.muted, height: 1.4, fontWeight: FontWeight.w400),
      labelLarge: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HossoukoColors.inkSoft, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: HossoukoColors.muted, letterSpacing: 0.4),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: HossoukoColors.paper,
      foregroundColor: HossoukoColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: serif, fontSize: 24, color: HossoukoColors.ink),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: HossoukoColors.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HossoukoRadius.lg),
        side: const BorderSide(color: HossoukoColors.line),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: HossoukoColors.surface,
      selectedColor: HossoukoColors.ink,
      side: BorderSide(color: HossoukoColors.line),
      shape: StadiumBorder(),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: HossoukoColors.ink, fontSize: 14.5),
      secondaryLabelStyle: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14.5),
      showCheckmark: false,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HossoukoColors.orangeDeep,
        foregroundColor: Colors.white,
        disabledBackgroundColor: HossoukoColors.line,
        // 52dp kept from the original theme, not the customer app's 56: a
        // merchant's thumb needs the Android floor, not more chrome.
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: roundedMd,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HossoukoColors.ink,
        side: const BorderSide(color: HossoukoColors.line, width: 1.5),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: roundedMd,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HossoukoColors.orangeDeep,
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        minimumSize: const Size(48, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HossoukoColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(HossoukoColors.line),
      enabledBorder: border(HossoukoColors.line),
      disabledBorder: border(HossoukoColors.line),
      focusedBorder: border(HossoukoColors.orangeDeep, 2),
      labelStyle: const TextStyle(fontSize: 16, color: HossoukoColors.muted),
      prefixIconColor: HossoukoColors.muted,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HossoukoColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(HossoukoRadius.xl))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: HossoukoColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HossoukoRadius.lg)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HossoukoColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HossoukoRadius.sm)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: HossoukoColors.orangeDeep),
  );
}
