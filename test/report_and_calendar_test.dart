import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:retain_mind/models/session_models.dart';
import 'package:retain_mind/providers/exam_provider.dart';
import 'package:retain_mind/screens/report_screen.dart';
import 'package:retain_mind/widgets/avatar/grok_avatar.dart';
import 'package:retain_mind/widgets/study_calendar_widget.dart';

void main() {
  group('StudyAnalytics calculations tests', () {
    test('Empty history produces valid default analytics', () {
      final analytics = StudyAnalytics.fromHistory([]);
      expect(analytics.allSessionDates, isEmpty);
      expect(analytics.sessionsByDate, isEmpty);
      expect(analytics.activeDaysCount, 0);
      expect(analytics.totalSessions, 0);
      expect(analytics.totalTurns, 0);
      expect(analytics.averageTurnsPerSession, 0.0);
      expect(analytics.overallMastery, 0.0);
      expect(analytics.currentStreak, 0);
      expect(analytics.bestStreak, 0);
      expect(analytics.peakHourLabel, 'Inizia la prima sessione');
      expect(analytics.totalSubjects, 0);
    });

    test('Analytics correctly computes active days, streaks and peak hours', () {
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yest = now.subtract(const Duration(days: 1));
      final yestStr = '${yest.year}-${yest.month.toString().padLeft(2, '0')}-${yest.day.toString().padLeft(2, '0')}';
      final dayBefore = now.subtract(const Duration(days: 2));
      final dayBeforeStr = '${dayBefore.year}-${dayBefore.month.toString().padLeft(2, '0')}-${dayBefore.day.toString().padLeft(2, '0')}';

      final history = [
        SessionHistoryItem(
          iteration: 1,
          title: 'Matematica',
          status: 'COMPLETED',
          isCurrent: false,
          turnsCompleted: 10,
          averageMastery: 0.80,
          timestamp: '${todayStr}T14:30:00Z', // Afternoon (12-18)
          sessionDates: [todayStr],
        ),
        SessionHistoryItem(
          iteration: 2,
          title: 'Machine Learning',
          status: 'COMPLETED',
          isCurrent: false,
          turnsCompleted: 6,
          averageMastery: 0.90,
          timestamp: '${yestStr}T15:00:00Z', // Afternoon (12-18)
          sessionDates: [yestStr],
        ),
        SessionHistoryItem(
          iteration: 3,
          title: 'Sistemi Operativi',
          status: 'COMPLETED',
          isCurrent: false,
          turnsCompleted: 4,
          averageMastery: 0.70,
          timestamp: '${dayBeforeStr}T09:00:00Z', // Morning (06-12)
          sessionDates: [dayBeforeStr],
        ),
      ];

      final analytics = StudyAnalytics.fromHistory(history);
      expect(analytics.activeDaysCount, 3);
      expect(analytics.totalSessions, 3);
      expect(analytics.totalTurns, 20);
      expect(analytics.averageTurnsPerSession, closeTo(6.66, 0.1));
      expect(analytics.overallMastery, closeTo(0.80, 0.01));
      expect(analytics.currentStreak, 3);
      expect(analytics.bestStreak, 3);
      expect(analytics.peakHourLabel, contains('Pomeriggio'));
      expect(analytics.totalSubjects, 3);
    });
  });

  group('StudyCalendarCard Widget tests', () {
    testWidgets('Renders calendar header, weekday columns, and displays daily summary', (tester) async {
      final now = DateTime.now();
      final todayNorm = DateTime(now.year, now.month, now.day);
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final history = [
        SessionHistoryItem(
          iteration: 1,
          title: 'Fondamenti di Reti',
          status: 'COMPLETED',
          isCurrent: false,
          turnsCompleted: 8,
          averageMastery: 0.85,
          timestamp: '${todayStr}T10:00:00Z',
          sessionDates: [todayStr],
        ),
      ];
      final analytics = StudyAnalytics.fromHistory(history);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StudyCalendarCard(
                analytics: analytics,
                initialSelectedDay: todayNorm,
              ),
            ),
          ),
        ),
      );

      // Verify header and day labels
      expect(find.text('Calendario Sessioni'), findsOneWidget);
      expect(find.text('LUN'), findsOneWidget);
      expect(find.text('MAR'), findsOneWidget);
      expect(find.text('MER'), findsOneWidget);
      expect(find.text('GIO'), findsOneWidget);
      expect(find.text('VEN'), findsOneWidget);
      expect(find.text('SAB'), findsOneWidget);
      expect(find.text('DOM'), findsOneWidget);

      // Verify daily summary card displays the session info
      expect(find.textContaining('1 sessioni'), findsOneWidget);
      expect(find.textContaining('8 scambi'), findsOneWidget);
      expect(find.textContaining('Fondamenti di Reti'), findsOneWidget);
    });

    testWidgets('StudyStreakCard and WeeklyStudyRhythmCard do not overflow on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final analytics = StudyAnalytics.fromHistory([]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  StudyStreakCard(analytics: analytics),
                  const SizedBox(height: 16),
                  WeeklyStudyRhythmCard(analytics: analytics),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Costanza di Studio'), findsOneWidget);
      expect(find.text('Ritmo Settimanale di Studio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReportScreen Integration tests', () {
    testWidgets('ReportScreen renders Calendario & Attivita tab by default with macro stats', (tester) async {
      final provider = ExamProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ExamProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: ReportScreen(showBackButton: false),
          ),
        ),
      );
      await tester.pump();

      // Top title
      expect(find.text('Report di Apprendimento'), findsOneWidget);
      expect(find.text('Calendario delle sessioni, costanza e sintesi didattica'), findsOneWidget);

      // Segment selectors
      expect(find.text('Calendario & Attività'), findsOneWidget);
      expect(find.text('Diagnostica IA'), findsOneWidget);

      // In Calendario & Attività tab:
      expect(find.text('Costanza di Studio'), findsOneWidget);
      expect(find.text('Calendario Sessioni'), findsOneWidget);
      expect(find.text('Abitudini & Volume di Apprendimento'), findsOneWidget);
      expect(find.text('Ritmo Settimanale di Studio'), findsOneWidget);

      // Verify Cronologia elements are NOT duplicated (e.g. no search bar)
      expect(find.text('Cerca per titolo, argomento o iterazione...'), findsNothing);
    });

    testWidgets('ReportScreen allows switching between Calendario & Attivita and Diagnostica IA', (tester) async {
      final provider = ExamProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ExamProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: ReportScreen(showBackButton: false),
          ),
        ),
      );
      await tester.pump();

      // Switch to Diagnostica IA
      await tester.tap(find.text('Diagnostica IA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Diagnostica IA in demo mode shows GrokAvatar and Not available
      expect(find.byType(GrokAvatar), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);

      // Switch back to Calendario & Attività
      await tester.tap(find.text('Calendario & Attività'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Costanza di Studio'), findsOneWidget);
      expect(find.text('Calendario Sessioni'), findsOneWidget);
    });
  });
}
