import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// MedTrack 360 — Brand Colours
class MedTrackColors {
  MedTrackColors._();

  // Primary
  static const Color teal = Color(0xFF0D9488);
  static const Color tealLight = Color(0xFF14B8A6);
  static const Color tealDark = Color(0xFF0F766E);

  // Secondary
  static const Color slateGrey = Color(0xFF64748B);
  static const Color slateGreyLight = Color(0xFF94A3B8);
  static const Color slateGreyDark = Color(0xFF475569);

  // Background / surface
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);

  // Semantic
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color success = Color(0xFF22C55E);
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFFCBD5E1);

  // Rail / nav
  static const Color navRailBg = Color(0xFF0F2027);
  static const Color navRailIndicator = Color(0xFF134E4A);
}

/// Shared shape tokens
class MedTrackShapes {
  MedTrackShapes._();

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(12));
  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(8));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(8));
  static const BorderRadius chipRadius = BorderRadius.all(Radius.circular(6));
}

/// Shared elevation / shadow tokens
class MedTrackShadows {
  MedTrackShadows._();

  static List<BoxShadow> get card => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.03),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
}

/// MedTrack 360 — ThemeData factory
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: MedTrackColors.teal,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFCCFBF1),
        onPrimaryContainer: MedTrackColors.tealDark,
        secondary: MedTrackColors.slateGrey,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFE2E8F0),
        onSecondaryContainer: MedTrackColors.slateGreyDark,
        tertiary: const Color(0xFF8B5CF6),
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFEDE9FE),
        onTertiaryContainer: const Color(0xFF4C1D95),
        error: MedTrackColors.error,
        onError: Colors.white,
        errorContainer: MedTrackColors.errorContainer,
        onErrorContainer: const Color(0xFF7F1D1D),
        surface: MedTrackColors.surface,
        onSurface: MedTrackColors.textPrimary,
        surfaceContainerHighest: MedTrackColors.surfaceVariant,
        onSurfaceVariant: MedTrackColors.slateGrey,
        outline: const Color(0xFFE2E8F0),
        outlineVariant: const Color(0xFFF1F5F9),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: MedTrackColors.textPrimary,
        onInverseSurface: MedTrackColors.background,
        inversePrimary: MedTrackColors.tealLight,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: MedTrackColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: MedTrackColors.textPrimary,
        letterSpacing: -0.25,
      ),
      headlineLarge: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: MedTrackColors.textPrimary,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: MedTrackColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: MedTrackColors.textPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: MedTrackColors.textPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: MedTrackColors.textPrimary,
        letterSpacing: 0.1,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: MedTrackColors.textSecondary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: MedTrackColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: MedTrackColors.textPrimary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: MedTrackColors.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: MedTrackColors.textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: MedTrackColors.background,

      // ── AppBar ──────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: MedTrackColors.surface,
        foregroundColor: MedTrackColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: MedTrackColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: MedTrackColors.slateGrey),
      ),

      // ── Card ────────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: MedTrackColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: MedTrackShapes.cardRadius,
          side: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── NavigationRail ──────────────────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: MedTrackColors.navRailBg,
        selectedIconTheme: const IconThemeData(color: Colors.white, size: 22),
        unselectedIconTheme: IconThemeData(
          color: Colors.white.withValues(alpha: 0.45),
          size: 22,
        ),
        selectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: Colors.white.withValues(alpha: 0.45),
        ),
        indicatorColor: MedTrackColors.navRailIndicator,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        elevation: 0,
        useIndicator: true,
        minWidth: 76,
        minExtendedWidth: 200,
        labelType: NavigationRailLabelType.all,
      ),

      // ── ElevatedButton ──────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MedTrackColors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: MedTrackShapes.buttonRadius,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── OutlinedButton ──────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MedTrackColors.teal,
          side: const BorderSide(color: MedTrackColors.teal),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: MedTrackShapes.buttonRadius,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── TextButton ──────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MedTrackColors.teal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: const RoundedRectangleBorder(
            borderRadius: MedTrackShapes.buttonRadius,
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── InputDecoration ─────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MedTrackColors.surfaceVariant,
        hoverColor: const Color(0xFFE2E8F0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: MedTrackShapes.inputRadius,
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MedTrackShapes.inputRadius,
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MedTrackShapes.inputRadius,
          borderSide: const BorderSide(color: MedTrackColors.teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: MedTrackShapes.inputRadius,
          borderSide: const BorderSide(color: MedTrackColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: MedTrackShapes.inputRadius,
          borderSide: const BorderSide(color: MedTrackColors.error, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: MedTrackColors.textDisabled,
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: MedTrackColors.textSecondary,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: MedTrackColors.teal,
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: MedTrackColors.surfaceVariant,
        selectedColor: const Color(0xFFCCFBF1),
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: const RoundedRectangleBorder(
          borderRadius: MedTrackShapes.chipRadius,
        ),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),

      // ── Divider ─────────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ──────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: MedTrackColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: MedTrackColors.textPrimary,
        ),
      ),

      // ── SnackBar ────────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MedTrackColors.textPrimary,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Colors.white,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── DataTable ───────────────────────────────────────────────────────────
      dataTableTheme: DataTableThemeData(
        headingTextStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: MedTrackColors.textSecondary,
          letterSpacing: 0.5,
        ),
        dataTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: MedTrackColors.textPrimary,
        ),
        headingRowColor: WidgetStateProperty.all(MedTrackColors.surfaceVariant),
        dividerThickness: 1,
        columnSpacing: 20,
        horizontalMargin: 16,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
      ),

      // ── Tooltip ─────────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: MedTrackColors.textPrimary,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}
