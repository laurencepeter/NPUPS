import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────────────────────────────────────
// WorkForce
// Aligned with WorkForce design system colour palette
// /
// Dark theme preserves the navy/teal identity at reduced brightness.
// ──────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Primary — Navy
  static const Color primary = Color(0xFF1A2C4E);
  static const Color primaryLight = Color(0xFF2A4470);
  static const Color primaryDark = Color(0xFF0F1A2E);

  // Accent — Teal/Cyan (digital identity)
  static const Color accent = Color(0xFF2980B9);
  static const Color accentLight = Color(0xFF5DADE2);
  static const Color accentDark = Color(0xFF1F6391);

  // Accent colours
  static const Color brandRed = Color(0xFFCE1126);
  static const Color brandBlack = Color(0xFF000000);

  // Semantic
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFD68910);
  static const Color error = Color(0xFFC0392B);
  static const Color info = Color(0xFF2980B9);

  // Light surfaces (raw constants — used inside theme definitions only)
  static const Color lightSurface = Color(0xFFF8FAFB);
  static const Color lightCard = Colors.white;
  static const Color lightInputFill = Color(0xFFF0F4F8);
  static const Color lightBorder = Color(0xFFDDE8F2);

  // Light text (raw constants)
  static const Color lightTextPrimary = Color(0xFF1A252F);
  static const Color lightTextSecondary = Color(0xFF666666);
  static const Color textOnPrimary = Colors.white;
  static const Color lightTextHint = Color(0xFF9CA3AF);

  // ── Theme-aware accessors ─────────────────────────────────────────────────
  // These resolve to light/dark variants based on the active ThemeModeNotifier.
  // They cannot be used inside `const` expressions — remove `const` from any
  // widget literal that references them.
  static bool get _isDark => ThemeModeNotifier().isDark;

  static Color get surface => _isDark ? darkBackground : lightSurface;
  static Color get card => _isDark ? darkCard : lightCard;
  static Color get cardElevated => _isDark ? darkCardElevated : lightCard;
  static Color get inputFill => _isDark ? darkInputFill : lightInputFill;
  static Color get border => _isDark ? darkBorder : lightBorder;
  static Color get textPrimary => _isDark ? darkTextPrimary : lightTextPrimary;
  static Color get textSecondary =>
      _isDark ? darkTextSecondary : lightTextSecondary;
  static Color get textHint => _isDark ? darkTextHint : lightTextHint;
  static Color get scaffoldBackground =>
      _isDark ? darkBackground : lightSurface;

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

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.lightSurface,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.lightSurface,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: AppColors.lightCard,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
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
        fillColor: AppColors.lightInputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: const TextStyle(color: AppColors.lightTextHint, fontSize: 14),
        labelStyle:
            const TextStyle(color: AppColors.lightTextSecondary, fontSize: 14),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.lightBorder),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightInputFill,
        selectedColor: AppColors.accent.withValues(alpha: 0.15),
        labelStyle: const TextStyle(color: AppColors.lightTextPrimary),
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
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primary,
        onPrimaryContainer: AppColors.darkTextPrimary,
        secondary: AppColors.darkAccent,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.accentDark,
        onSecondaryContainer: AppColors.darkTextPrimary,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkTextPrimary,
        onSurfaceVariant: AppColors.darkTextSecondary,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.darkBorder,
        outlineVariant: AppColors.darkBorder.withValues(alpha: 0.5),
        inverseSurface: AppColors.darkTextPrimary,
        onInverseSurface: AppColors.darkSurface,
        shadow: Colors.black54,
        scrim: Colors.black54,
      ),
      scaffoldBackgroundColor: AppColors.darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.darkBorder, width: 0.5),
        ),
        color: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkAccent,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.darkAccent.withValues(alpha: 0.4),
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
        style: TextButton.styleFrom(foregroundColor: AppColors.darkAccentLight),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkAccentLight,
          side: const BorderSide(color: AppColors.darkAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkInputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.darkAccent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: const TextStyle(color: AppColors.darkTextHint, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkCard,
        indicatorColor: AppColors.darkAccent.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.darkAccentLight);
          }
          return const IconThemeData(color: AppColors.darkTextSecondary);
        }),
        elevation: 8,
        shadowColor: Colors.black54,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.darkBorder),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkCardElevated,
        selectedColor: AppColors.darkAccent.withValues(alpha: 0.3),
        labelStyle: const TextStyle(color: AppColors.darkTextPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkBorder, width: 0.5),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.darkBorder, width: 0.5),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppColors.darkTextPrimary,
        iconColor: AppColors.darkTextSecondary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.darkAccent : AppColors.darkTextHint),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.darkAccent.withValues(alpha: 0.4)
                : AppColors.darkBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.darkAccent : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: AppColors.darkTextSecondary),
      ),
    );
  }
}

// Global theme-mode notifier so any widget can toggle dark/light.
// Persists the chosen mode to shared_preferences so the preference survives
// browser refreshes and app restarts.
class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  static final ThemeModeNotifier _instance = ThemeModeNotifier._internal();
  factory ThemeModeNotifier() => _instance;
  ThemeModeNotifier._internal() : super(ThemeMode.light);

  static const _key = 'theme_is_dark';

  /// Load persisted theme on startup. Call once before runApp().
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_key) ?? false;
    value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  void toggle() {
    value = value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark);
  }

  bool get isDark => value == ThemeMode.dark;
}
