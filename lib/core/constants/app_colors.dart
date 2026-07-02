// lib/core/constants/app_colors.dart
import 'package:flutter/material.dart';

/// SyncReal Design System — Cyberpunk/Minimalist Palette
///
/// Primary aesthetic: void-black canvas with neon electric purple accents.
/// Every surface should feel like it exists in deep space.
abstract final class AppColors {
  // ─── Backgrounds ──────────────────────────────────────────────────────────
  static const Color black = Color(0xFF000000);
  static const Color surface = Color(0xFF0A0A0A);
  static const Color surfaceElevated = Color(0xFF111111);
  static const Color surfaceCard = Color(0xFF161616);
  static const Color divider = Color(0xFF1E1E1E);

  // ─── Neon Accent — Electric Purple ───────────────────────────────────────
  static const Color neonPurple = Color(0xFFBC13FE);
  static const Color neonPurpleDim = Color(0xFF8B0DBD);
  static const Color neonPurpleFaint = Color(0x33BC13FE); // 20% opacity
  static const Color neonPurpleGlow = Color(0x66BC13FE); // 40% opacity

  // ─── Secondary Accents ────────────────────────────────────────────────────
  static const Color neonCyan = Color(0xFF00F5FF);   // highlights / contrast
  static const Color neonMagenta = Color(0xFFFF0090); // danger / delete
  static const Color neonGreen = Color(0xFF39FF14);  // success / streak

  // ─── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEEEEEE);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textDisabled = Color(0xFF444444);
  static const Color textAccent = neonPurple;

  // ─── Utility ──────────────────────────────────────────────────────────────
  static const Color transparent = Colors.transparent;
  static const Color white = Color(0xFFFFFFFF);

  // ─── Glow Box Shadows ─────────────────────────────────────────────────────
  // ✅ P3 Fix: Migrasi dari .withOpacity() (deprecated) ke .withValues(alpha:)
  static List<BoxShadow> get neonPurpleGlowShadow => [
        BoxShadow(
          color: neonPurple.withValues(alpha: 0.55),
          blurRadius: 18,
          spreadRadius: 2,
        ),
        BoxShadow(
          color: neonPurple.withValues(alpha: 0.25),
          blurRadius: 40,
          spreadRadius: 6,
        ),
      ];

  static List<BoxShadow> get neonCyanGlowShadow => [
        BoxShadow(
          color: neonCyan.withValues(alpha: 0.45),
          blurRadius: 16,
          spreadRadius: 1,
        ),
      ];

  static List<BoxShadow> get neonGreenGlowShadow => [
        BoxShadow(
          color: neonGreen.withValues(alpha: 0.50),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ];
}