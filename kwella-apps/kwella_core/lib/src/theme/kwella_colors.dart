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

  /// Warm premium off-white – legacy Rider app background / light surfaces.
  static const Color communityCream = Color(0xFFFDFBF7);

  /// High-contrast charcoal/off-black – legacy Driver app background.
  static const Color deepSlate = Color(0xFF1E2229);

  /// High-visibility neon green – legacy CTA colour.
  static const Color cataTransitGreen = Color(0xFF00E676);

  // ── Electric Lime Dark-Mode Palette (v2 design spec) ────────────────────

  /// Primary canvas background — dark-mode-first app base.
  /// Maps to `#121212` per Kwella v2 design spec.
  static const Color canvas = Color(0xFF121212);

  /// First-level elevated card / bottom sheet surface.
  static const Color elevatedCard = Color(0xFF1E1E1E);

  /// Second-level card surface (cards within sheets).
  static const Color elevatedCard2 = Color(0xFF242424);

  /// Electric Lime — primary CTA, bids, active badges (neon accent).
  static const Color electricLime = Color(0xFFDFFF00);

  /// Slightly dimmed Electric Lime for hover/pressed states.
  static const Color electricLimeDim = Color(0xFFCCFF00);

  /// Subtle Electric Lime tint for backgrounds / chips.
  static const Color electricLimeSurface = Color(0x1FDFFF00); // ~12% opacity

  /// Electric Lime border / ring.
  static const Color electricLimeBorder = Color(0x4DDFFF00); // ~30% opacity

  /// High-contrast white for primary text on dark surfaces.
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Muted gray for secondary / hint text on dark surfaces.
  static const Color textSecondary = Color(0xFFA0A0A0);

  /// Subtle divider / border on dark surfaces.
  static const Color borderDark = Color(0xFF2C2C2C);

  /// Dark map road colour for vector map style.
  static const Color mapRoad = Color(0xFF2A2D32);

  /// Semi-transparent scrim for modals / overlays (52% black).
  static const Color scrim = Color(0x85000000);

  // ── Derived tones (from legacy palette) ──────────────────────────────────

  /// Slightly elevated surface in dark (driver) contexts.
  static const Color deepSlateCard = Color(0xFF272D36);

  /// Subtle border/divider on dark surfaces (legacy).
  static const Color deepSlateBorder = Color(0xFF323A47);

  /// Primary text on dark (driver) backgrounds (legacy).
  static const Color textOnDark = Color(0xFFF0F4FF);

  /// Secondary/muted text on dark backgrounds (legacy).
  static const Color textOnDarkMuted = Color(0xFF8B97B8);

  /// Primary text on light (rider) backgrounds (legacy).
  static const Color textOnLight = Color(0xFF1A1F2B);

  /// Secondary/muted text on light backgrounds (legacy).
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

  /// Online / active indicator dot.
  static const Color onlineDot = Color(0xFF69FF47);
}
