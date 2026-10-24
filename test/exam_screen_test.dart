import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:retain_mind/providers/exam_provider.dart';
import 'package:retain_mind/screens/exam_screen.dart';

void main() {
  group('ExamProvider AI Question extraction and cleaning tests', () {
    test('cleanAiQuestion strips conversational preamble and isolates question', () {
      const raw1 =
          'Perfetto, iniziamo subito! Cosa sono gli alberi di decisione e qual è la loro struttura logica generale?';
      expect(
        ExamProvider.cleanAiQuestion(raw1),
        'Cosa sono gli alberi di decisione e qual è la loro struttura logica generale?',
      );

      const raw2 = 'Molto bene. Come viene calcolata l\'impurità di Gini e come guida la scelta dei migliori split?';
      expect(
        ExamProvider.cleanAiQuestion(raw2),
        'Come viene calcolata l\'impurità di Gini e come guida la scelta dei migliori split?',
      );

      const raw3 =
          'Nessun problema, lasciamo da parte questo argomento per ora. Passiamo ad altro: Qual è la differenza tra bagging e boosting?';
      expect(
        ExamProvider.cleanAiQuestion(raw3),
        'Qual è la differenza tra bagging e boosting?',
      );
    });

    test('cleanAiQuestion returns clean question when already stripped', () {
      const q = 'Cos\'è una matrice di confusione?';
      expect(ExamProvider.cleanAiQuestion(q), q);
    });
  });

  group('ExamScreen UI Minimalist Calling Interface tests', () {
    testWidgets('Renders microphone toggle and call-end button, but no pause or speakerphone toggles', (tester) async {
      final provider = ExamProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ExamProvider>.value(
            value: provider,
            child: const ExamScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Microphone toggle MUST be present
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      // 2. End Call button MUST be present
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

      // 3. Pause / Resume button MUST be removed
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

      // 4. Speakerphone / Audio toggle MUST be removed
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);

      // 5. History sheet button in top bar MUST be removed
      expect(find.byIcon(Icons.history_rounded), findsNothing);

      // 6. DOMANDA D'ESAME label MUST be displayed
      expect(find.text('DOMANDA D\'ESAME'), findsOneWidget);

      // Clean disposal
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('Tapping end call button opens exit confirmation dialog', (tester) async {
      final provider = ExamProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ExamProvider>.value(
            value: provider,
            child: const ExamScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Tap End Call button
      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Dialog opens with correct options
      expect(find.text('Uscire dalla chiamata?'), findsOneWidget);
      expect(find.text('La sessione verrà salvata e tornerai alla schermata principale.'), findsOneWidget);
      expect(find.text('Annulla'), findsOneWidget);
      expect(find.text('Esci dalla chiamata'), findsOneWidget);

      // Tap Annulla dismisses dialog
      await tester.tap(find.text('Annulla'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Uscire dalla chiamata?'), findsNothing);

      // Clean disposal
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('Renders standard exam calling UI and exit dialog', (tester) async {
      final provider = ExamProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ExamProvider>.value(
            value: provider,
            child: const ExamScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Tap End Call and verify exit dialog text in standard mode
      await tester.tap(find.byIcon(Icons.call_end_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('La sessione verrà salvata e tornerai alla schermata principale.'), findsOneWidget);
      await tester.tap(find.text('Annulla'));
      await tester.pump(const Duration(milliseconds: 200));

      // Clean disposal
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
