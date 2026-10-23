import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:retain_mind/constants.dart';
import 'package:retain_mind/providers/exam_provider.dart';
import 'package:retain_mind/screens/home_screen.dart';

void main() {
  group('Theme System & Tokens Unit Tests', () {
    test('Dark theme tokens match DESIGN.md exact values and untouched defaults', () {
      final darkColors = AppColors.dark();
      expect(darkColors.brightness, Brightness.dark);
      expect(darkColors.background, const Color(0xFF121416));
      expect(darkColors.surfaceCard, const Color(0xFF1A1C1E));
      expect(darkColors.surfaceElevated, const Color(0xFF282A2C));
      expect(darkColors.primaryContainer, const Color(0xFF38BDF8));
      expect(darkColors.primary, const Color(0xFF8ED5FF));
      expect(darkColors.textPrimary, const Color(0xFFE2E2E5));
      expect(darkColors.textSecondary, const Color(0xFFBDC8D1));
      expect(darkColors.textTertiary, const Color(0xFF87929A));
    });

    test('Light theme tokens follow DESIGN.md porcelain & cyan specifications', () {
      final lightColors = AppColors.light();
      expect(lightColors.brightness, Brightness.light);
      expect(lightColors.background, const Color(0xFFF8F9FC));
      expect(lightColors.surfaceCard, const Color(0xFFFFFFFF));
      expect(lightColors.surfaceContainerLow, const Color(0xFFF1F4F8));
      expect(lightColors.primaryContainer, const Color(0xFF38BDF8));
      expect(lightColors.primary, const Color(0xFF00668A));
      expect(lightColors.textPrimary, const Color(0xFF0F172A));
      expect(lightColors.textSecondary, const Color(0xFF475569));
      expect(lightColors.textTertiary, const Color(0xFF64748B));
      expect(lightColors.success, const Color(0xFF059669));
      expect(lightColors.warning, const Color(0xFFD97706));
      expect(lightColors.error, const Color(0xFFBA1A1A));
    });

    test('AppColors lerp seamlessly interpolates between dark and light', () {
      final dark = AppColors.dark();
      final light = AppColors.light();
      final midDark = dark.lerp(light, 0.4);
      final midLight = dark.lerp(light, 0.6);

      expect(midDark.brightness, Brightness.dark);
      expect(midLight.brightness, Brightness.light);
      expect(midDark.primaryContainer, const Color(0xFF38BDF8));
    });

    test('ExamProvider defaults to ThemeMode.dark and can switch to ThemeMode.light', () {
      final provider = ExamProvider();
      expect(provider.themeMode, ThemeMode.dark);

      bool notified = false;
      provider.addListener(() {
        notified = true;
      });

      provider.setThemeMode(ThemeMode.light);
      expect(provider.themeMode, ThemeMode.light);
      expect(notified, isTrue);

      provider.setThemeMode(ThemeMode.system);
      expect(provider.themeMode, ThemeMode.system);
    });
  });

  group('Widget Rendering in Light and Dark Themes', () {
    testWidgets('RetainMindApp renders properly in ThemeMode.light without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ExamProvider>(
              create: (_) {
                final p = ExamProvider();
                p.setThemeMode(ThemeMode.light);
                return p;
              },
            ),
          ],
          child: Consumer<ExamProvider>(
            builder: (context, exam, _) {
              return MaterialApp(
                title: AppConstants.appTitle,
                debugShowCheckedModeBanner: false,
                themeMode: exam.themeMode,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: Builder(
                  builder: (ctx) {
                    final colors = ctx.colors;
                    expect(colors.brightness, Brightness.light);
                    expect(colors.background, const Color(0xFFF8F9FC));
                    return Scaffold(
                      backgroundColor: colors.background,
                      body: Center(
                        child: Text(
                          'Test Light Theme',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Test Light Theme'), findsOneWidget);
    });

    testWidgets('RetainMindApp dynamically re-renders when switching from Dark to Light', (WidgetTester tester) async {
      final examProvider = ExamProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ExamProvider>.value(value: examProvider),
          ],
          child: Consumer<ExamProvider>(
            builder: (context, exam, _) {
              return MaterialApp(
                themeMode: exam.themeMode,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: Builder(
                  builder: (ctx) {
                    final isDark = ctx.isDarkMode;
                    return Scaffold(
                      backgroundColor: ctx.colors.background,
                      body: Text(isDark ? 'Mode: Dark' : 'Mode: Light'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Mode: Dark'), findsOneWidget);

      // Switch to Light Mode
      examProvider.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(find.text('Mode: Light'), findsOneWidget);

      // Switch back to Dark Mode
      examProvider.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('Mode: Dark'), findsOneWidget);
    });

    testWidgets('HomeScreen renders with correct light/dark background and theme colors', (WidgetTester tester) async {
      final examProvider = ExamProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ExamProvider>.value(value: examProvider),
          ],
          child: Consumer<ExamProvider>(
            builder: (context, exam, _) {
              return MaterialApp(
                themeMode: exam.themeMode,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: const HomeScreen(),
              );
            },
          ),
        ),
      );

      await tester.pump();

      // In Dark Mode
      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, const Color(0xFF121416));

      // Switch to Light Mode
      examProvider.setThemeMode(ThemeMode.light);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, const Color(0xFFF8F9FC));
    });
  });
}
