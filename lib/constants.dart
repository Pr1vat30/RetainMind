import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

export 'theme/app_colors.dart';
export 'theme/app_theme.dart';

/// Design System constants according to HTML/DESIGN.md specification
/// Movement: Tactile Modern Dark Minimalist with Ethereal Cyan Glow
/// Also provides generated Light Theme tokens while preserving exact Dark Theme values.
class AppConstants {
  static const String appTitle = 'Retain Mind';
  static const String appSubtitle = 'Assistente Vocale AI per Studio e Simulazioni Orali';

  // Default API Host (Mobile: 192.168.1.8 Mac Wi-Fi LAN, Desktop: 127.0.0.1)
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return 'http://192.168.1.8:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  // --- Context-Aware Design Token Helpers ---
  static AppColors colors(BuildContext context) => AppColors.of(context);
  static AppColors get darkColors => AppColors.dark();
  static AppColors get lightColors => AppColors.light();

  // --- Preserved Static Dark Theme Tokens (for backward compatibility) ---

  // Canvas Base & Matte Surfaces
  static const Color background = Color(0xFF121416);              // #121416 Canvas base
  static const Color surface = Color(0xFF121416);                 // #121416 Surface
  static const Color surfaceContainerLowest = Color(0xFF0C0E10);  // #0c0e10
  static const Color surfaceContainerLow = Color(0xFF1A1C1E);     // #1a1c1e (Feature cards & rows)
  static const Color surfaceContainer = Color(0xFF1E2022);        // #1e2022
  static const Color surfaceContainerHigh = Color(0xFF282A2C);    // #282a2c (Elevated buttons/badges)
  static const Color surfaceContainerHighest = Color(0xFF333537); // #333537
  static const Color surfaceBright = Color(0xFF38393C);

  // Backward compatibility alias for existing widgets
  static const Color surfaceCard = Color(0xFF1A1C1E);
  static const Color surfaceElevated = Color(0xFF282A2C);
  static const Color surfaceHighest = Color(0xFF333537);

  // Primary Accent & Glowing Luminosity
  static const Color primary = Color(0xFF8ED5FF);                 // #8ed5ff Primary Sky
  static const Color onPrimary = Color(0xFF00354A);               // #00354a
  static const Color primaryContainer = Color(0xFF38BDF8);        // #38bdf8 Vibrant Sky Cyan
  static const Color onPrimaryContainer = Color(0xFF004965);      // #004965
  static const Color primaryGlow = Color(0xFF67E8F9);             // #67e8f9 Bright Ice Cyan

  // Secondary Accents
  static const Color secondary = Color(0xFF58D6F1);               // #58d6f1
  static const Color secondaryContainer = Color(0xFF00A7C0);      // #00a7c0
  static const Color onSecondary = Color(0xFF00363F);
  static const Color onSecondaryContainer = Color(0xFF003640);
  static const Color tertiary = Color(0xFF5FDBFF);
  static const Color accent = Color(0xFF38BDF8);

  // Hero Card Gradient (HTML: from-[#70D6FF] via-[#38BDF8] to-[#00A7C0])
  static const List<Color> heroGradient = [
    Color(0xFF70D6FF),
    Color(0xFF38BDF8),
    Color(0xFF00A7C0),
  ];

  // Text & Foregrounds
  static const Color textPrimary = Color(0xFFE2E2E5);             // #e2e2e5 on-surface
  static const Color textSecondary = Color(0xFFBDC8D1);           // #bdc8d1 on-surface-variant
  static const Color textTertiary = Color(0xFF87929A);            // #87929a outline
  static const Color onSurface = Color(0xFFE2E2E5);
  static const Color onSurfaceVariant = Color(0xFFBDC8D1);

  // Status & Feedback
  static const Color success = Color(0xFF34D399);                 // Emerald mint
  static const Color warning = Color(0xFFFBBF24);                 // Amber
  static const Color error = Color(0xFFFFB4AB);                   // #ffb4ab
  static const Color onError = Color(0xFF690005);

  // Outlines & Borders
  static const Color outline = Color(0xFF3E484F);                 // #3e484f outline-variant
  static const Color outlineVariant = Color(0xFF3E484F);          // #3e484f outline-variant
  static const Color outlineCard = Color(0x14FFFFFF);             // Hairline card border
  static const Color outlineCyan = Color(0x4038BDF8);

  // Hyper-rounded Shape Scale (HTML: rounded-[28px], rounded-[24px], rounded-[20px], rounded-full)
  static const double radiusPill = 9999.0;
  static const double radiusHero = 28.0;                          // Hero card 28px
  static const double radiusXl = 28.0;
  static const double radiusCard = 24.0;                          // Feature cards 24px
  static const double radiusLg = 20.0;                          // Document row 20px
  static const double radiusMd = 16.0;
  static const double radiusSm = 12.0;

  // Pedagogical State Colors (Static dark fallback)
  static Color getPedagogicalColor(String state) {
    switch (state.toUpperCase()) {
      case 'EXPLORATION':
        return primaryContainer; // Vibrant Sky Cyan
      case 'CAUSAL_NARROWING':
        return secondary;        // Ice Cyan
      case 'SCAFFOLDING':
        return warning;          // Amber
      case 'CONCEPTUAL_COLLISION':
        return const Color(0xFF818CF8); // Violet Bloom
      case 'PREREQUISITE_FALLBACK':
        return error;            // Coral Red
      default:
        return primaryContainer;
    }
  }

  // Theme-aware pedagogical color
  static Color pedagogicalColor(BuildContext context, String state) {
    return AppColors.of(context).getPedagogicalColor(state);
  }
}
