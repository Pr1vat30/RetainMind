import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Design System Theme configuration matching DESIGN.md
/// Font Family: Plus Jakarta Sans
class AppTheme {
  AppTheme._();

  /// Plus Jakarta Sans TextTheme according to DESIGN.md Typography Scale
  static TextTheme _buildTextTheme(Brightness brightness, AppColors colors) {
    final baseTheme = ThemeData(brightness: brightness).textTheme;
    final jakartaTheme = GoogleFonts.plusJakartaSansTextTheme(baseTheme);

    return jakartaTheme.copyWith(
      // headline-xl: 36px, 700, line-height 44px, letter-spacing -0.02em
      displayLarge: jakartaTheme.displayLarge?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 44 / 36,
        letterSpacing: -0.02 * 36,
        color: colors.textPrimary,
      ),
      // headline-lg: 28px, 700, line-height 36px, letter-spacing -0.015em
      headlineLarge: jakartaTheme.headlineLarge?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 36 / 28,
        letterSpacing: -0.015 * 28,
        color: colors.textPrimary,
      ),
      // headline-md: 22px, 600, line-height 28px, letter-spacing -0.01em
      headlineMedium: jakartaTheme.headlineMedium?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 28 / 22,
        letterSpacing: -0.01 * 22,
        color: colors.textPrimary,
      ),
      // headline-sm: 18px, 600, line-height 24px
      headlineSmall: jakartaTheme.headlineSmall?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
        letterSpacing: -0.2,
        color: colors.textPrimary,
      ),
      // title-large: 18px, 700
      titleLarge: jakartaTheme.titleLarge?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colors.textPrimary,
      ),
      // title-medium: 16px, 600
      titleMedium: jakartaTheme.titleMedium?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      // title-small: 14px, 600
      titleSmall: jakartaTheme.titleSmall?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      // body-lg: 16px, 400, line-height 24px
      bodyLarge: jakartaTheme.bodyLarge?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
        color: colors.textPrimary,
      ),
      // body-md: 14px, 400, line-height 20px
      bodyMedium: jakartaTheme.bodyMedium?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 20 / 14,
        color: colors.textSecondary,
      ),
      // body-sm: 12px, 400, line-height 16px
      bodySmall: jakartaTheme.bodySmall?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 16 / 12,
        color: colors.textTertiary,
      ),
      // label-lg: 14px, 600, line-height 20px
      labelLarge: jakartaTheme.labelLarge?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 20 / 14,
        color: colors.textPrimary,
      ),
      // label-md: 12px, 600, line-height 16px, letter-spacing 0.01em
      labelMedium: jakartaTheme.labelMedium?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 0.01 * 12,
        color: colors.textSecondary,
      ),
      // label-sm: 10px, 600, line-height 14px, letter-spacing 0.02em
      labelSmall: jakartaTheme.labelSmall?.copyWith(
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 14 / 10,
        letterSpacing: 0.02 * 10,
        color: colors.textTertiary,
      ),
    );
  }

  /// Dark Theme (Tactile Modern Minimalist with Ethereal Cyan Glow)
  /// Exactly preserves the existing visual styling and color values
  static ThemeData get darkTheme {
    final colors = AppColors.dark();
    final textTheme = _buildTextTheme(Brightness.dark, colors);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      colorScheme: ColorScheme.dark(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        primaryContainer: colors.primaryContainer,
        onPrimaryContainer: colors.onPrimaryContainer,
        inversePrimary: colors.inversePrimary,
        secondary: colors.secondary,
        onSecondary: colors.onSecondary,
        secondaryContainer: colors.secondaryContainer,
        onSecondaryContainer: colors.onSecondaryContainer,
        tertiary: colors.tertiary,
        onTertiary: colors.onTertiary,
        tertiaryContainer: colors.tertiaryContainer,
        onTertiaryContainer: colors.onTertiaryContainer,
        surface: colors.surface,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        surfaceContainerLowest: colors.surfaceContainerLowest,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        outline: colors.outline,
        outlineVariant: colors.outlineVariant,
        error: colors.error,
        onError: colors.onError,
        errorContainer: colors.errorContainer,
        onErrorContainer: colors.onErrorContainer,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: BorderSide(color: colors.outlineCard),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999.0),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outlineCard),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999.0),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: BorderSide(color: colors.outlineCard),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
      ),
      extensions: [colors],
    );
  }

  /// Light Theme (Clean Porcelain Minimalist with Radiant Sky Cyan)
  /// Crafted according to DESIGN.md Material 3 specification
  static ThemeData get lightTheme {
    final colors = AppColors.light();
    final textTheme = _buildTextTheme(Brightness.light, colors);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      colorScheme: ColorScheme.light(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        primaryContainer: colors.primaryContainer,
        onPrimaryContainer: colors.onPrimaryContainer,
        inversePrimary: colors.inversePrimary,
        secondary: colors.secondary,
        onSecondary: colors.onSecondary,
        secondaryContainer: colors.secondaryContainer,
        onSecondaryContainer: colors.onSecondaryContainer,
        tertiary: colors.tertiary,
        onTertiary: colors.onTertiary,
        tertiaryContainer: colors.tertiaryContainer,
        onTertiaryContainer: colors.onTertiaryContainer,
        surface: colors.surface,
        onSurface: colors.onSurface,
        onSurfaceVariant: colors.onSurfaceVariant,
        surfaceContainerLowest: colors.surfaceContainerLowest,
        surfaceContainerLow: colors.surfaceContainerLow,
        surfaceContainer: colors.surfaceContainer,
        surfaceContainerHigh: colors.surfaceContainerHigh,
        surfaceContainerHighest: colors.surfaceContainerHighest,
        outline: colors.outline,
        outlineVariant: colors.outlineVariant,
        error: colors.error,
        onError: colors.onError,
        errorContainer: colors.errorContainer,
        onErrorContainer: colors.onErrorContainer,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: BorderSide(color: colors.outlineCard),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999.0),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colors.outlineCard),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999.0),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: BorderSide(color: colors.outlineCard),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
      ),
      extensions: [colors],
    );
  }
}
