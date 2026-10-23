import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:retain_mind/providers/exam_provider.dart';
import 'package:retain_mind/widgets/avatar/bloub_morphing_avatar.dart';
import 'package:retain_mind/widgets/exam_launch_loader.dart';

void main() {
  group('BloubMorphingAvatar Rendering & Morphing Tests', () {
    testWidgets('BloubMorphingAvatar renders in Avatar mode (dotsMorphProgress = 0.0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BloubMorphingAvatar(
                size: 150,
                glowColor: Colors.cyan,
                dotsMorphProgress: 0.0,
                dotsWaveProgress: 0.0,
                winkProgress: 0.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BloubMorphingAvatar), findsOneWidget);
    });

    testWidgets('BloubMorphingAvatar renders in Three Dots mode (dotsMorphProgress = 1.0) with wave motion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BloubMorphingAvatar(
                size: 180,
                glowColor: Colors.cyan,
                dotsMorphProgress: 1.0,
                dotsWaveProgress: 0.5,
                winkProgress: 0.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BloubMorphingAvatar), findsOneWidget);
    });

    testWidgets('BloubMorphingAvatar renders playful Wink (winkProgress = 1.0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BloubMorphingAvatar(
                size: 200,
                glowColor: Colors.cyan,
                dotsMorphProgress: 0.0,
                dotsWaveProgress: 0.0,
                winkProgress: 1.0,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BloubMorphingAvatar), findsOneWidget);
    });

    testWidgets('BloubMorphingAvatar renders intermediate morphing states without exceptions', (tester) async {
      for (final progress in [0.25, 0.5, 0.75]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: BloubMorphingAvatar(
                  size: 160,
                  dotsMorphProgress: progress,
                  dotsWaveProgress: 0.3,
                  winkProgress: 0.5,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(BloubMorphingAvatar), findsOneWidget);
      }
    });
  });

  group('ExamLaunchTransitionOverlay Flow Tests', () {
    testWidgets('launchExamWithLoader executes full animation choreography and loads data', (tester) async {
      final examProvider = ExamProvider();
      bool onConnectCalled = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ExamProvider>.value(value: examProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        launchExamWithLoader(
                          ctx,
                          startCenter: const Offset(280, 200),
                          startSize: 105,
                          onConnect: () async {
                            onConnectCalled = true;
                          },
                        );
                      },
                      child: const Text('Launch Exam'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Tap launch
      await tester.tap(find.text('Launch Exam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify overlay is mounted and avatar is flying
      expect(find.byType(ExamLaunchTransitionOverlay), findsOneWidget);
      expect(find.byType(BloubMorphingAvatar), findsOneWidget);

      // Advance flight to center (480ms)
      await tester.pump(const Duration(milliseconds: 500));

      // Advance dots morph and background loading (360ms + 1100ms)
      await tester.pump(const Duration(milliseconds: 1500));
      expect(onConnectCalled, isTrue);

      // Advance reverse dots morph + wink + flight to call
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('launchExamWithLoader propagates error when onConnect fails', (tester) async {
      final examProvider = ExamProvider();
      Object? caughtError;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ExamProvider>.value(value: examProvider),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await launchExamWithLoader(
                            ctx,
                            onConnect: () async {
                              throw Exception('Network timeout test');
                            },
                          );
                        } catch (e) {
                          caughtError = e;
                        }
                      },
                      child: const Text('Fail Exam'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Fail Exam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Advance flight to center & morph
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify error was caught and propagated
      expect(caughtError, isNotNull);
      expect(caughtError.toString(), contains('Network timeout test'));
    });
  });
}
