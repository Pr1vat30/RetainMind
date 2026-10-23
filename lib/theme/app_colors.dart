import 'package:flutter/material.dart';

/// Semantic Design System Color Tokens according to DESIGN.md
/// Supports both Dark (Tactile Modern Minimalist with Ethereal Cyan Glow)
/// and Light (Clean Porcelain Minimalist with Radiant Sky Cyan) themes.
class AppColors extends ThemeExtension<AppColors> {
  final Brightness brightness;

  // Canvas Base & Surfaces
  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color surfaceVariant;

  // Backward-compatibility aliases
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color surfaceHighest;

  // Accents & Glow
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color primaryGlow;
  final Color inversePrimary;

  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color accent;

  // Hero Gradient
  final List<Color> heroGradient;

  // Text & Foregrounds
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color inverseSurface;
  final Color inverseOnSurface;

  // Status & Feedback
  final Color success;
  final Color warning;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  // Outlines & Borders
  final Color outline;
  final Color outlineVariant;
  final Color outlineCard;
  final Color outlineCyan;

  // Shadows
  final Color cardShadow;
  final Color floatingNavShadow;

  const AppColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.surfaceVariant,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.surfaceHighest,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primaryGlow,
    required this.inversePrimary,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.accent,
    required this.heroGradient,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.outline,
    required this.outlineVariant,
    required this.outlineCard,
    required this.outlineCyan,
    required this.cardShadow,
    required this.floatingNavShadow,
  });

  /// 100% Faithful Existing Dark Theme Colors (Untouched & Preserved)
  factory AppColors.dark() {
    return const AppColors(
      brightness: Brightness.dark,
      background: Color(0xFF121416),
      surface: Color(0xFF121416),
      surfaceDim: Color(0xFF121416),
      surfaceBright: Color(0xFF38393C),
      surfaceContainerLowest: Color(0xFF0C0E10),
      surfaceContainerLow: Color(0xFF1A1C1E),
      surfaceContainer: Color(0xFF1E2022),
      surfaceContainerHigh: Color(0xFF282A2C),
      surfaceContainerHighest: Color(0xFF333537),
      surfaceVariant: Color(0xFF333537),
      surfaceCard: Color(0xFF1A1C1E),
      surfaceElevated: Color(0xFF282A2C),
      surfaceHighest: Color(0xFF333537),
      primary: Color(0xFF8ED5FF),
      onPrimary: Color(0xFF00354A),
      primaryContainer: Color(0xFF38BDF8),
      onPrimaryContainer: Color(0xFF004965),
      primaryGlow: Color(0xFF67E8F9),
      inversePrimary: Color(0xFF00668A),
      secondary: Color(0xFF54D8E8),
      onSecondary: Color(0xFF00363C),
      secondaryContainer: Color(0xFF02AEBE),
      onSecondaryContainer: Color(0xFF003B42),
      tertiary: Color(0xFF98D3FF),
      onTertiary: Color(0xFF00344D),
      tertiaryContainer: Color(0xFF43BBFF),
      onTertiaryContainer: Color(0xFF00486A),
      accent: Color(0xFF38BDF8),
      heroGradient: [
        Color(0xFF70D6FF),
        Color(0xFF38BDF8),
        Color(0xFF00A7C0),
      ],
      textPrimary: Color(0xFFE2E2E5),
      textSecondary: Color(0xFFBDC8D1),
      textTertiary: Color(0xFF87929A),
      onSurface: Color(0xFFE2E2E5),
      onSurfaceVariant: Color(0xFFBDC8D1),
      inverseSurface: Color(0xFFE2E2E5),
      inverseOnSurface: Color(0xFF2F3133),
      success: Color(0xFF34D399),
      warning: Color(0xFFFBBF24),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      outline: Color(0xFF87929A),
      outlineVariant: Color(0xFF3E484F),
      outlineCard: Color(0x14FFFFFF),
      outlineCyan: Color(0x4038BDF8),
      cardShadow: Color(0x80000000),
      floatingNavShadow: Color(0x80000000),
    );
  }

  /// Generated Light Theme according to DESIGN.md Material 3 Specification
  factory AppColors.light() {
    return const AppColors(
      brightness: Brightness.light,
      background: Color(0xFFF8F9FC),
      surface: Color(0xFFF8F9FC),
      surfaceDim: Color(0xFFD8DADD),
      surfaceBright: Color(0xFFFFFFFF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF1F4F8),
      surfaceContainer: Color(0xFFE8EDF2),
      surfaceContainerHigh: Color(0xFFDFE6ED),
      surfaceContainerHighest: Color(0xFFD4DCDE),
      surfaceVariant: Color(0xFFDCE4EC),
      surfaceCard: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFF1F4F8),
      surfaceHighest: Color(0xFFDFE6ED),
      primary: Color(0xFF00668A),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF38BDF8),
      onPrimaryContainer: Color(0xFF00354A),
      primaryGlow: Color(0xFF0284C7),
      inversePrimary: Color(0xFF8ED5FF),
      secondary: Color(0xFF006874),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFF91F1FF),
      onSecondaryContainer: Color(0xFF001F23),
      tertiary: Color(0xFF00658D),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFC9E6FF),
      onTertiaryContainer: Color(0xFF001E2F),
      accent: Color(0xFF0284C7),
      heroGradient: [
        Color(0xFF70D6FF),
        Color(0xFF38BDF8),
        Color(0xFF00A7C0),
      ],
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      textTertiary: Color(0xFF64748B),
      onSurface: Color(0xFF0F172A),
      onSurfaceVariant: Color(0xFF475569),
      inverseSurface: Color(0xFF2F3133),
      inverseOnSurface: Color(0xFFF0F1F3),
      success: Color(0xFF059669),
      warning: Color(0xFFD97706),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      outline: Color(0xFF71787E),
      outlineVariant: Color(0xFFCBD5E1),
      outlineCard: Color(0x12000000),
      outlineCyan: Color(0x3300668A),
      cardShadow: Color(0x0D000000),
      floatingNavShadow: Color(0x1A000000),
    );
  }

  /// Resolves the pedagogical color according to active theme mode
  Color getPedagogicalColor(String state) {
    final isDark = brightness == Brightness.dark;
    switch (state.toUpperCase()) {
      case 'EXPLORATION':
        return isDark ? primaryContainer : const Color(0xFF0284C7);
      case 'CAUSAL_NARROWING':
        return isDark ? secondary : const Color(0xFF0891B2);
      case 'SCAFFOLDING':
        return warning;
      case 'CONCEPTUAL_COLLISION':
        return isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
      case 'PREREQUISITE_FALLBACK':
        return error;
      default:
        return isDark ? primaryContainer : const Color(0xFF0284C7);
    }
  }

  /// Helper to fetch [AppColors] from the current [BuildContext]
  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.dark()
        : AppColors.light();
  }

  @override
  ThemeExtension<AppColors> copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? surfaceVariant,
    Color? surfaceCard,
    Color? surfaceElevated,
    Color? surfaceHighest,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryGlow,
    Color? inversePrimary,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? accent,
    List<Color>? heroGradient,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? inverseSurface,
    Color? inverseOnSurface,
    Color? success,
    Color? warning,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? outline,
    Color? outlineVariant,
    Color? outlineCard,
    Color? outlineCyan,
    Color? cardShadow,
    Color? floatingNavShadow,
  }) {
    return AppColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceBright: surfaceBright ?? this.surfaceBright,
      surfaceContainerLowest: surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest ?? this.surfaceContainerHighest,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      primaryGlow: primaryGlow ?? this.primaryGlow,
      inversePrimary: inversePrimary ?? this.inversePrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      tertiary: tertiary ?? this.tertiary,
      onTertiary: onTertiary ?? this.onTertiary,
      tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer ?? this.onTertiaryContainer,
      accent: accent ?? this.accent,
      heroGradient: heroGradient ?? this.heroGradient,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      inverseOnSurface: inverseOnSurface ?? this.inverseOnSurface,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      outlineCard: outlineCard ?? this.outlineCard,
      outlineCyan: outlineCyan ?? this.outlineCyan,
      cardShadow: cardShadow ?? this.cardShadow,
      floatingNavShadow: floatingNavShadow ?? this.floatingNavShadow,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      surfaceBright: Color.lerp(surfaceBright, other.surfaceBright, t)!,
      surfaceContainerLowest: Color.lerp(surfaceContainerLowest, other.surfaceContainerLowest, t)!,
      surfaceContainerLow: Color.lerp(surfaceContainerLow, other.surfaceContainerLow, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceContainerHigh: Color.lerp(surfaceContainerHigh, other.surfaceContainerHigh, t)!,
      surfaceContainerHighest: Color.lerp(surfaceContainerHighest, other.surfaceContainerHighest, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHighest: Color.lerp(surfaceHighest, other.surfaceHighest, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      primaryGlow: Color.lerp(primaryGlow, other.primaryGlow, t)!,
      inversePrimary: Color.lerp(inversePrimary, other.inversePrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      secondaryContainer: Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      onSecondaryContainer: Color.lerp(onSecondaryContainer, other.onSecondaryContainer, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      onTertiary: Color.lerp(onTertiary, other.onTertiary, t)!,
      tertiaryContainer: Color.lerp(tertiaryContainer, other.tertiaryContainer, t)!,
      onTertiaryContainer: Color.lerp(onTertiaryContainer, other.onTertiaryContainer, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      heroGradient: [
        Color.lerp(heroGradient[0], other.heroGradient[0], t)!,
        Color.lerp(heroGradient[1], other.heroGradient[1], t)!,
        Color.lerp(heroGradient[2], other.heroGradient[2], t)!,
      ],
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      inverseSurface: Color.lerp(inverseSurface, other.inverseSurface, t)!,
      inverseOnSurface: Color.lerp(inverseOnSurface, other.inverseOnSurface, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineVariant: Color.lerp(outlineVariant, other.outlineVariant, t)!,
      outlineCard: Color.lerp(outlineCard, other.outlineCard, t)!,
      outlineCyan: Color.lerp(outlineCyan, other.outlineCyan, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      floatingNavShadow: Color.lerp(floatingNavShadow, other.floatingNavShadow, t)!,
    );
  }
}

/// Convenient extension on [BuildContext] to access design tokens
extension AppThemeContextExtension on BuildContext {
  AppColors get colors => AppColors.of(this);
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
  TextTheme get typography => Theme.of(this).textTheme;
}
