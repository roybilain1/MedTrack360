import 'package:flutter/material.dart';

/// ─── MedTrackColors: Unified Design System ─────────────────
/// Matches the Lebanese Ministry of Health POS / website palette.
class MedTrackColors {
  MedTrackColors._();

  // ── Primary ────────────────────────────────────────────────
  static const Color primary = Color(0xFF1B6E4F); // Forest green
  static const Color primaryLight = Color(0xFF2E8B65);
  static const Color primaryDark = Color(0xFF0F4D36);

  // ── Secondary ──────────────────────────────────────────────
  static const Color secondary = Color(0xFFD4A843); // Gold accent
  static const Color secondaryLight = Color(0xFFE8C36A);
  static const Color secondaryDark = Color(0xFFB88E30);

  // ── Surfaces ───────────────────────────────────────────────
  static const Color background = Color(0xFFF5F7F6);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF0F4F2);
  static const Color cardBg = Colors.white;

  // ── Semantic ───────────────────────────────────────────────
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF9A825);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color error = Color(0xFFC62828);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF1565C0);
  static const Color infoLight = Color(0xFFE3F2FD);

  // ── Extended Accents (break green monotony) ────────────────
  static const Color teal = Color(0xFF00897B);
  static const Color tealLight = Color(0xFFE0F2F1);
  static const Color purple = Color(0xFF5E35B1);
  static const Color purpleLight = Color(0xFFEDE7F6);
  static const Color indigo = Color(0xFF3949AB);
  static const Color indigoLight = Color(0xFFE8EAF6);

  // ── Text ───────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A2E23);
  static const Color textSecondary = Color(0xFF5A6E62);
  static const Color textHint = Color(0xFF8A9B91);
  static const Color textOnPrimary = Colors.white;
  static const Color textOnSecondary = Color(0xFF2C2C2C);

  // ── Navigation / Chrome ────────────────────────────────────
  static const Color navBarBg = Colors.white;
  static const Color navBarSelected = Color(0xFF1B6E4F);
  static const Color navBarUnselected = Color(0xFF8A9B91);

  // ── Dividers / Borders ─────────────────────────────────────
  static const Color divider = Color(0xFFE0E6E2);
  static const Color border = Color(0xFFD0D8D3);

  // ── Gradients ──────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryLight],
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F4D36), Color(0xFF1B6E4F), Color(0xFF2E8B65)],
  );

  static const LinearGradient headerAccentGradient = LinearGradient(
    colors: [Color(0xFF2E8B65), Color(0xFFD4A843)],
  );
}

/// ─── AppTheme: ThemeData built from MedTrackColors ──────────
class AppTheme {
  // Keep legacy aliases so existing code doesn't break immediately
  static const Color primaryColor = MedTrackColors.primary;
  static const Color secondaryColor = MedTrackColors.success;
  static const Color accentColor = MedTrackColors.secondary;
  static const Color warningColor = MedTrackColors.warning;
  static const Color errorColor = MedTrackColors.error;
  static const Color surfaceColor = MedTrackColors.background;
  static const Color cardColor = MedTrackColors.cardBg;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: MedTrackColors.primary,
        primary: MedTrackColors.primary,
        onPrimary: MedTrackColors.textOnPrimary,
        secondary: MedTrackColors.secondary,
        onSecondary: MedTrackColors.textOnSecondary,
        error: MedTrackColors.error,
        surface: MedTrackColors.surface,
        onSurface: MedTrackColors.textPrimary,
      ),
      scaffoldBackgroundColor: MedTrackColors.background,

      // ── AppBar ──────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: MedTrackColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: MedTrackColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: MedTrackColors.textSecondary),
      ),

      // ── Card ────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: MedTrackColors.cardBg,
      ),

      // ── Chip ────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: MedTrackColors.surfaceAlt,
        selectedColor: MedTrackColors.primary.withValues(alpha: 0.15),
        labelStyle: const TextStyle(
          fontSize: 13,
          color: MedTrackColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // ── Input ───────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MedTrackColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MedTrackColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MedTrackColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MedTrackColors.primary, width: 2),
        ),
        hintStyle: const TextStyle(color: MedTrackColors.textHint),
      ),

      // ── Elevated Button ─────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MedTrackColors.primary,
          foregroundColor: MedTrackColors.textOnPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Text Button ─────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MedTrackColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // ── Bottom Nav ──────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: MedTrackColors.navBarBg,
        selectedItemColor: MedTrackColors.navBarSelected,
        unselectedItemColor: MedTrackColors.navBarUnselected,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),

      // ── FAB ─────────────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: MedTrackColors.primary,
        foregroundColor: MedTrackColors.textOnPrimary,
        elevation: 4,
      ),

      // ── Divider ─────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: MedTrackColors.divider,
        thickness: 1,
      ),

      // ── Switch / Checkbox ───────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MedTrackColors.primary;
          }
          return Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return MedTrackColors.primary.withValues(alpha: 0.4);
          }
          return Colors.grey.shade300;
        }),
      ),

      // ── SnackBar ────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MedTrackColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Dialog ──────────────────────────────────────────
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
