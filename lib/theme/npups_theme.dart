import 'package:flutter/material.dart';

// ──────────────────────────────────────────────────────────────────────────────
// NPUPS Design System — Colour Palette, Light & Dark Themes
// Aligned with NPUPS Scope Document §8.1 Logo Design Brief colour palette
// and Trinidad & Tobago national branding guidelines.
// Dark theme preserves the navy/teal identity at reduced brightness.
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

  // National colours (Trinidad & Tobago)
  static const Color trinidadRed = Color(0xFFCE1126);
  static const Color trinidadBlack = Color(0xFF000000);

  // Semantic
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFD68910);
  static const Color error = Color(0xFFC0392B);
  static const Color info = Color(0xFF2980B9);

  // Light surfaces
  static const Color surface = Color(0xFFF8FAFB);
  static const Color card = Colors.white;
  static const Color inputFill = Color(0xFFF0F4F8);
  static const Color border = Color(0xFFDDE8F2);

  // Light text
  static const Color textPrimary = Color(0xFF1A252F);
  static const Color textSecondary = Color(0xFF666666);
  static const Color textOnPrimary = Colors.white;
  static const Color textHint = Color(0xFF9CA3AF);

  // ── Dark theme surfaces (navy-based, matches brand identity) ──────────────
  static const Color darkBackground = Color(0xFF0D1520);
  static const Color darkSurface = Color(0xFF131E2E);
  static const Color darkCard = Color(0xFF182336);
  static const Color darkCardElevated = Color(0xFF1E2D42);
  static const Color darkInputFill = Color(0xFF0F1A28);
  static const Color darkBorder = Color(0xFF243550);

  // Dark text
  static const Color darkTextPrimary = Color(0xFFE4EAF4);
  static const Color darkTextSecondary = Color(0xFF8FA8C8);
  static const Color darkTextHint = Color(0xFF556A88);

  // Accent adjusted for dark backgrounds (slightly brighter)
  static const Color darkAccent = Color(0xFF3D9BD1);
  static const Color darkAccentLight = Color(0xFF5DADE2);

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

  static const LinearGradient darkPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1A2E), Color(0xFF182336), Color(0xFF1F3A5A)],
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
      dividerTheme: const DividerThemeData(color: NpupsColors.border),
      chipTheme: ChipThemeData(
        backgroundColor: NpupsColors.inputFill,
        selectedColor: NpupsColors.accent.withValues(alpha: 0.15),
        labelStyle: const TextStyle(color: NpupsColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: NpupsColors.primaryLight,
        onPrimary: Colors.white,
        primaryContainer: NpupsColors.primary,
        onPrimaryContainer: NpupsColors.darkTextPrimary,
        secondary: NpupsColors.darkAccent,
        onSecondary: Colors.white,
        secondaryContainer: NpupsColors.accentDark,
        onSecondaryContainer: NpupsColors.darkTextPrimary,
        surface: NpupsColors.darkSurface,
        onSurface: NpupsColors.darkTextPrimary,
        onSurfaceVariant: NpupsColors.darkTextSecondary,
        error: NpupsColors.error,
        onError: Colors.white,
        outline: NpupsColors.darkBorder,
        outlineVariant: NpupsColors.darkBorder.withValues(alpha: 0.5),
        inverseSurface: NpupsColors.darkTextPrimary,
        onInverseSurface: NpupsColors.darkSurface,
        shadow: Colors.black54,
        scrim: Colors.black54,
      ),
      scaffoldBackgroundColor: NpupsColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: NpupsColors.primaryDark,
        foregroundColor: NpupsColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: NpupsColors.darkBorder, width: 0.5),
        ),
        color: NpupsColors.darkCard,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NpupsColors.darkAccent,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: NpupsColors.darkAccent.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: NpupsColors.darkAccentLight),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NpupsColors.darkAccentLight,
          side: const BorderSide(color: NpupsColors.darkAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NpupsColors.darkInputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.darkAccent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NpupsColors.error),
        ),
        hintStyle: const TextStyle(color: NpupsColors.darkTextHint, fontSize: 14),
        labelStyle: const TextStyle(color: NpupsColors.darkTextSecondary, fontSize: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: NpupsColors.darkCard,
        indicatorColor: NpupsColors.darkAccent.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: NpupsColors.darkTextSecondary, fontSize: 12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: NpupsColors.darkAccentLight);
          }
          return const IconThemeData(color: NpupsColors.darkTextSecondary);
        }),
        elevation: 8,
        shadowColor: Colors.black54,
      ),
      dividerTheme: const DividerThemeData(color: NpupsColors.darkBorder),
      chipTheme: ChipThemeData(
        backgroundColor: NpupsColors.darkCardElevated,
        selectedColor: NpupsColors.darkAccent.withValues(alpha: 0.3),
        labelStyle: const TextStyle(color: NpupsColors.darkTextPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: NpupsColors.darkBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: NpupsColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NpupsColors.darkBorder, width: 0.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: NpupsColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: NpupsColors.darkBorder, width: 0.5),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: NpupsColors.darkTextPrimary,
        iconColor: NpupsColors.darkTextSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? NpupsColors.darkAccent : NpupsColors.darkTextHint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? NpupsColors.darkAccent.withValues(alpha: 0.4)
                : NpupsColors.darkBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? NpupsColors.darkAccent : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: NpupsColors.darkTextSecondary),
      ),
    );
  }
}

// Global theme-mode notifier so any widget can toggle dark/light.
class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  static final ThemeModeNotifier _instance = ThemeModeNotifier._internal();
  factory ThemeModeNotifier() => _instance;
  ThemeModeNotifier._internal() : super(ThemeMode.light);

  void toggle() {
    value = value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDark => value == ThemeMode.dark;
}
