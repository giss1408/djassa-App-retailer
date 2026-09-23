import 'package:flutter/material.dart';

/// Visual baseline for the merchant app.
///
/// Three constraints drive every choice here:
///
/// * **Sunlight.** The app is used at a market stall at midday. Contrast is
///   high and surfaces stay light; a dark theme is unreadable on a cheap LCD
///   outdoors.
/// * **Cheap panels.** Low-end screens render thin weights as grey mush, so
///   body text never goes below 15sp and never below w400.
/// * **Thumbs, fast.** A merchant taps while holding goods and counting change.
///   Targets are at least 48dp, which is also the Android accessibility floor.
///
/// No Material icon font is bundled (see pubspec), so any glyph must be drawn
/// or come from a text label.
ThemeData djassaTheme() {
  // Djassa's palette, shared with the public site in ../djassa-FE.
  const ink = Color(0xFF1A1714);
  const paper = Color(0xFFFCFAF7);
  const orange = Color(0xFFD1571E);

  final scheme = ColorScheme.fromSeed(
    seedColor: orange,
    brightness: Brightness.light,
    surface: paper,
  ).copyWith(onSurface: ink);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    // Ripples and long transitions cost frames on a 2014-era GPU.
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: ink,
        height: 1.2,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 16, color: ink, height: 1.4),
      bodySmall: TextStyle(fontSize: 15, color: ink, height: 1.4),
      labelMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      // A visible, filled field reads better in bright light than an
      // underline that disappears against glare.
      filled: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
  );
}
