import 'package:flutter/material.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Design System — Colour Palette & Theme
// Aligned with NPUPS Scope Document §8.1 Logo Design Brief colour palette
// and Trinidad & Tobago national branding guidelines.
// ──────────────────────────────────────────────────────────────────────────────

class NpupsColors {
  NpupsColors._();

  // Primary — Navy (Ministry branding)
  static const Color primary = Color(0xFF1A2C4E);
  static const Color primaryLight = Color(0xFF2A4470);
  static const Color primaryDark = Color(0xFF0F1A2E);

  // Accent — Teal/Cyan (digital identity)
  static const Color accent = Color(0xFF2980B9);
  static const Color accentLight = Color(0xFF5DADE2);
  static const Color accentDark = Color(0xFF1F6391);

  // National colours (optional accents per §8.1)
  static const Color trinidadRed = Color(0xFFCE1126);
  static const Color trinidadBlack = Color(0xFF000000);

  // Semantic
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFD68910);
  static const Color error = Color(0xFFC0392B);
  static const Color info = Color(0xFF2980B9);

  // Surfaces
  static const Color surface = Color(0xFFF8FAFB);
  static const Color card = Colors.white;
  static const Color inputFill = Color(0xFFF0F4F8);
  static const Color border = Color(0xFFDDE8F2);

  // Text
  static const Color textPrimary = Color(0xFF1A252F);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textOnPrimary = Colors.white;
  static const Color textHint = Color(0xFF9CA3AF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF1E3A5F), accent],
  );

  static const LinearGradient loginGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0F1A2E),
      Color(0xFF1A2C4E),
      Color(0xFF1E3A5F),
    ],
  );
}

class NpupsTheme {
  NpupsTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NpupsColors.primary,
        primary: NpupsColors.primary,
        secondary: NpupsColors.accent,
        surface: NpupsColors.surface,
        error: NpupsColors.error,
      ),
      scaffoldBackgroundColor: NpupsColors.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: NpupsColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: NpupsColors.card,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NpupsColors.accent,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NpupsColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.error),
        ),
        hintStyle: const TextStyle(color: NpupsColors.textHint, fontSize: 14),
        labelStyle: const TextStyle(color: NpupsColors.textSecondary, fontSize: 14),
      ),
    );
  }
}
