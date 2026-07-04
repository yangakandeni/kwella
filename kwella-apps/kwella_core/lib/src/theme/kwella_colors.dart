import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Kwella Design System – Brand Color Palette
//
// All colour definitions live here. To fine-tune any hue, change it once
// in this file and every app that depends on kwella_core picks it up
// automatically — no other files need touching.
// ---------------------------------------------------------------------------

/// Kwella brand colours.
///
/// Each constant is a compile-time [Color] value so it can be used inside
/// `const` widget constructors without boxing overhead.
abstract final class KwellaColors {
  // ── Primary brand ────────────────────────────────────────────────────────

  /// Warm premium off-white – Rider app background / light surfaces.
  static const Color communityCream = Color(0xFFFDFBF7);

  /// High-contrast charcoal/off-black – Driver app background / dark surfaces.
  static const Color deepSlate = Color(0xFF1E2229);

  /// High-visibility neon green – Primary CTA / action colour for both apps.
  static const Color cataTransitGreen = Color(0xFF00E676);

  // ── Derived tones (computed from brand primitives) ───────────────────────

  /// Slightly elevated surface in dark (driver) contexts.
  static const Color deepSlateCard = Color(0xFF272D36);

  /// Subtle border/divider on dark surfaces.
  static const Color deepSlateBorder = Color(0xFF323A47);

  /// Primary text on dark (driver) backgrounds.
  static const Color textOnDark = Color(0xFFF0F4FF);

  /// Secondary/muted text on dark backgrounds.
  static const Color textOnDarkMuted = Color(0xFF8B97B8);

  /// Primary text on light (rider) backgrounds.
  static const Color textOnLight = Color(0xFF1A1F2B);

  /// Secondary/muted text on light backgrounds.
  static const Color textOnLightMuted = Color(0xFF6B7489);

  /// Subtle border/divider on light surfaces.
  static const Color creamBorder = Color(0xFFE8E4DC);

  /// Slightly elevated surface in light (rider) contexts.
  static const Color creamCard = Color(0xFFF5F2EC);

  // ── Semantic colours ─────────────────────────────────────────────────────

  /// Error / destructive action colour – used in both themes.
  static const Color errorRed = Color(0xFFFF5370);

  /// Success accent – mirrors the transit green at reduced saturation.
  static const Color successGreen = Color(0xFF00C853);

  /// Warning amber – used for non-critical callouts.
  static const Color warningAmber = Color(0xFFFFAB40);
}
