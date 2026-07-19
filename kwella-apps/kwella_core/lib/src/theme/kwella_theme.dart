import 'package:flutter/material.dart';

import 'kwella_colors.dart';

// ---------------------------------------------------------------------------
// KwellaTheme – centralised MaterialApp theme factory
//
// lightTheme       → legacy Rider application (Community Cream foundation)
// darkTheme        → legacy Driver application (Deep Slate foundation)
// kwellaDarkTheme  → v2 Electric Lime dark-mode-first theme (both apps)
//
// Both legacy themes share the same CATA Transit Green as their primary
// action colour, preserving brand consistency across both surfaces.
// The v2 kwellaDarkTheme uses Electric Lime (#DFFF00) as the primary CTA.
// ---------------------------------------------------------------------------

/// Provides production-ready [ThemeData] objects for the Kwella apps.
///
/// Consume these themes in your [MaterialApp]:
/// ```dart
/// MaterialApp(
///   theme: KwellaTheme.kwellaDarkTheme, // v2 dark-mode-first (recommended)
/// )
/// ```
abstract final class KwellaTheme {
  // ── v2 Electric Lime Dark Theme ──────────────────────────────────────────

  /// Electric Lime–accented dark theme per v2 Kwella design spec.
  ///
  /// - Canvas: #121212
  /// - Primary CTA: #DFFF00 (Electric Lime)
  /// - Surface (card/sheet): #1E1E1E
  /// - Primary text: #FFFFFF / Secondary: #A0A0A0
  static ThemeData get kwellaDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: KwellaColors.canvas,
      colorScheme: const ColorScheme.dark(
        primary: KwellaColors.electricLime,
        onPrimary: Color(0xFF1A1A00),
        secondary: KwellaColors.electricLimeDim,
        onSecondary: Color(0xFF1A1A00),
        surface: KwellaColors.elevatedCard,
        onSurface: KwellaColors.textPrimary,
        surfaceContainerHighest: KwellaColors.elevatedCard2,
        error: KwellaColors.errorRed,
        onError: Colors.white,
        outline: KwellaColors.borderDark,
        outlineVariant: Color(0xFF383838),
        inversePrimary: Color(0xFF1A1A00),
        primaryContainer: KwellaColors.elevatedCard,
        onPrimaryContainer: KwellaColors.electricLime,
        secondaryContainer: KwellaColors.electricLimeSurface,
        onSecondaryContainer: KwellaColors.electricLime,
        tertiary: KwellaColors.onlineDot,
        onTertiary: Color(0xFF003900),
      ),
      fontFamily: 'Outfit',
      // ── Typography ────────────────────────────────────────────────────
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineLarge: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: KwellaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: KwellaColors.textPrimary),
        bodyMedium: TextStyle(color: KwellaColors.textSecondary),
        bodySmall: TextStyle(color: KwellaColors.textSecondary),
        labelLarge: TextStyle(
          color: Color(0xFF1A1A00),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          color: KwellaColors.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
      // ── Input fields ──────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KwellaColors.elevatedCard2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KwellaColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KwellaColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: KwellaColors.electricLime, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KwellaColors.errorRed),
        ),
        labelStyle: const TextStyle(color: KwellaColors.textSecondary),
        hintStyle: const TextStyle(color: KwellaColors.textSecondary),
        prefixIconColor: KwellaColors.textSecondary,
        suffixIconColor: KwellaColors.textSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // ── Elevated Button ───────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: KwellaColors.electricLime,
          foregroundColor: const Color(0xFF1A1A00),
          disabledBackgroundColor: KwellaColors.borderDark,
          disabledForegroundColor: KwellaColors.textSecondary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      // ── Outlined Button ───────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KwellaColors.electricLime,
          side: const BorderSide(color: KwellaColors.electricLimeBorder),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      // ── Text Button ───────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: KwellaColors.electricLime,
          textStyle: const TextStyle(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // ── Card ─────────────────────────────────────────────────────────
      cardTheme: const CardThemeData(
        color: KwellaColors.elevatedCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: KwellaColors.borderDark),
        ),
        margin: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      ),
      // ── BottomSheet ───────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KwellaColors.elevatedCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        elevation: 8,
        showDragHandle: true,
        dragHandleColor: KwellaColors.borderDark,
      ),
      // ── AppBar ────────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: KwellaColors.canvas,
        foregroundColor: KwellaColors.textPrimary,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: KwellaColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: KwellaColors.textPrimary),
      ),
      // ── Chip ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: KwellaColors.elevatedCard2,
        selectedColor: KwellaColors.electricLimeSurface,
        labelStyle:
            const TextStyle(color: KwellaColors.textSecondary, fontSize: 13),
        side: const BorderSide(color: KwellaColors.borderDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCheckmark: false,
      ),
      // ── Divider ──────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: KwellaColors.borderDark,
        thickness: 1,
        space: 1,
      ),
      // ── Icon ─────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: KwellaColors.textSecondary,
        size: 24,
      ),
      // ── Switch ───────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF1A1A00);
          }
          return KwellaColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return KwellaColors.electricLime;
          }
          return KwellaColors.elevatedCard2;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return KwellaColors.borderDark;
        }),
      ),
      // ── SnackBar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: KwellaColors.elevatedCard,
        contentTextStyle:
            const TextStyle(color: KwellaColors.textPrimary, fontSize: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),
    );
  }

  // ── Light theme (legacy Rider) ───────────────────────────────────────────

  /// Community Cream–based light theme — legacy Rider application.
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

  // ── Dark theme (legacy Driver) ───────────────────────────────────────────

  /// Deep Slate–based dark theme — legacy Driver application.
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
