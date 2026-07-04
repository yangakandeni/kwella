import 'package:flutter/material.dart';

import 'kwella_colors.dart';

// ---------------------------------------------------------------------------
// KwellaTheme – centralised MaterialApp theme factory
//
// lightTheme  → Rider application (Community Cream foundation)
// darkTheme   → Driver application (Deep Slate foundation)
//
// Both themes share the same CATA Transit Green as their primary action
// colour, preserving brand consistency across both surfaces.
// ---------------------------------------------------------------------------

/// Provides production-ready [ThemeData] objects for the Kwella apps.
///
/// Consume these themes in your [MaterialApp]:
/// ```dart
/// MaterialApp(
///   theme: KwellaTheme.lightTheme,   // Rider app
///   darkTheme: KwellaTheme.darkTheme, // Driver app
/// )
/// ```
abstract final class KwellaTheme {
  // ── Light theme (Rider) ──────────────────────────────────────────────────

  /// Community Cream–based light theme optimised for the Rider application.
  static ThemeData get lightTheme {
    const seed = KwellaColors.cataTransitGreen;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        surface: KwellaColors.communityCream,
        primary: KwellaColors.cataTransitGreen,
        onSurface: KwellaColors.textOnLight,
      ),
      scaffoldBackgroundColor: KwellaColors.communityCream,
      fontFamily: 'Outfit',
      // ── Text ──────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayMedium: TextStyle(
          color: KwellaColors.textOnLight,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        bodyMedium: TextStyle(color: KwellaColors.textOnLightMuted),
        labelLarge: TextStyle(
          color: KwellaColors.textOnLight,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      // ── Input fields ──────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KwellaColors.creamCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KwellaColors.creamBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KwellaColors.creamBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KwellaColors.cataTransitGreen, width: 2),
        ),
        labelStyle:
            const TextStyle(color: KwellaColors.textOnLightMuted),
        prefixIconColor: KwellaColors.textOnLightMuted,
      ),
      // ── Buttons ───────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: KwellaColors.cataTransitGreen,
          foregroundColor: KwellaColors.deepSlate,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      // ── App bar ───────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: KwellaColors.communityCream,
        foregroundColor: KwellaColors.textOnLight,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
    );

    return base;
  }

  // ── Dark theme (Driver) ──────────────────────────────────────────────────

  /// Deep Slate–based dark theme optimised for the Driver application.
  static ThemeData get darkTheme {
    const seed = KwellaColors.cataTransitGreen;

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        surface: KwellaColors.deepSlate,
        primary: KwellaColors.cataTransitGreen,
        onSurface: KwellaColors.textOnDark,
      ),
      scaffoldBackgroundColor: KwellaColors.deepSlate,
      fontFamily: 'Outfit',
      // ── Text ──────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayMedium: TextStyle(
          color: KwellaColors.textOnDark,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        bodyMedium: TextStyle(color: KwellaColors.textOnDarkMuted),
        labelLarge: TextStyle(
          color: KwellaColors.textOnDark,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      // ── Input fields ──────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KwellaColors.deepSlateCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KwellaColors.deepSlateBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KwellaColors.deepSlateBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: KwellaColors.cataTransitGreen, width: 2),
        ),
        labelStyle:
            const TextStyle(color: KwellaColors.textOnDarkMuted),
        prefixIconColor: KwellaColors.textOnDarkMuted,
      ),
      // ── Buttons ───────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: KwellaColors.cataTransitGreen,
          foregroundColor: KwellaColors.deepSlate,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      // ── App bar ───────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: KwellaColors.deepSlateCard,
        foregroundColor: KwellaColors.textOnDark,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
    );

    return base;
  }
}
