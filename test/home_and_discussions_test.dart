import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:retain_mind_def/models/session_models.dart';
import 'package:retain_mind_def/providers/exam_provider.dart';
import 'package:retain_mind_def/screens/discussion_detail_screen.dart';
import 'package:retain_mind_def/screens/home_screen.dart';
import 'package:retain_mind_def/screens/main_shell.dart';
import 'package:retain_mind_def/screens/previous_discussions_screen.dart';
import 'package:retain_mind_def/widgets/new_discussion_modal.dart';

void main() {
  testWidgets('HomeScreen displays first-access UI adapted for empty state and file upload', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ExamProvider()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify Tier Free exists, Livello 4 is gone
    expect(find.text('Tier Free'), findsOneWidget);
    expect(find.text('Livello 4'), findsNothing);

    // Verify I tuoi Progressi exists, Esplora Materie is gone
    expect(find.text('I tuoi Progressi'), findsOneWidget);
    expect(find.text('Esplora Materie'), findsNothing);

    // Verify Hero Banner adapted for first session
    expect(find.text('PRIMA SESSIONE'), findsOneWidget);
    expect(find.text('Inizia la tua Prima Simulazione'), findsOneWidget);
    expect(find.text('Carica File & Inizia'), findsOneWidget);

    // Verify Nuova conversazione and Carica Documento (Card 2 dynamic adaptation)
    expect(find.text('Nuova'), findsOneWidget);
    expect(find.text('conversazione'), findsOneWidget);
    expect(find.text('Carica'), findsOneWidget);
    expect(find.text('Documento'), findsOneWidget);

    // Verify old cards are gone
    expect(find.text('Domande Mirate'), findsNothing);
    expect(find.text('Interrogazione'), findsNothing);

    // Verify Voice Assistant banner is gone
    expect(find.text('Voice Assistant pronto'), findsNothing);

    // Verify Documenti & Sessioni and Carica file header action
    expect(find.text('Documenti & Sessioni'), findsOneWidget);
    expect(find.text('Carica file'), findsAtLeastNWidgets(1));
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    // Verify clean empty state container
    expect(find.text('Nessun documento caricato'), findsOneWidget);
    expect(find.text('Carica Documento & Inizia'), findsOneWidget);
    expect(find.text('Diritto_Costituzionale_Cap4.pdf'), findsNothing);
    expect(find.text('Termodinamica_Appunti_Prof_Rossi.pdf'), findsNothing);
    expect(find.text('0 sessioni'), findsOneWidget);
    expect(find.text('Sessioni svolte'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.text('0 scambi'), findsOneWidget);
  });

  testWidgets('HomeScreen displays Ripeti conversazione when history exists', (tester) async {
    final mockItems = [
      SessionHistoryItem(
        iteration: 1,
        title: 'Diritto Costituzionale #1',
        status: 'COMPLETED',
        isCurrent: false,
        turnsCompleted: 5,
        averageMastery: 0.80,
        masteredConcepts: ['Fonti'],
        weakConcepts: [],
        timestamp: '2026-10-20T10:00:00Z',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(create: (_) => _MockExamProviderWithHistory(mockItems)),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // With history present, Card 2 shows Ripeti conversazione
    expect(find.text('Nuova'), findsOneWidget);
    expect(find.text('Ripeti'), findsOneWidget);
    expect(find.text('conversazione'), findsNWidgets(2));
    expect(find.text('Cronologia'), findsAtLeastNWidgets(1));
    expect(find.text('Diritto Costituzionale #1'), findsOneWidget);
  });

  testWidgets('MainShell has History in navbar instead of Sillabo', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ExamProvider()),
        ],
        child: const MaterialApp(
          home: MainShell(),
        ),
      ),
    );

    await tester.pump();

    // Navbar items
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);

    // Sillabo shouldn't be a navbar tab anymore
    expect(find.text('Sillabo / Programma'), findsNothing);
  });

  testWidgets('PreviousDiscussionsScreen renders with empty state, controls, and delete all button', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ExamProvider()),
        ],
        child: const MaterialApp(
          home: PreviousDiscussionsScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Cronologia Discussioni'), findsOneWidget);
    expect(find.text('Tutte'), findsOneWidget);
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Completate'), findsOneWidget);
    expect(find.text('Inizia la tua Prima Discussione'), findsOneWidget);
    expect(find.text('Carica File & Inizia'), findsOneWidget);

    // Verify clear all history button is present
    expect(find.byIcon(Icons.delete_sweep_rounded), findsOneWidget);
  });

  testWidgets('DiscussionDetailScreen renders Copertura & Esito, Sillabo, and Trascrizione tabs', (tester) async {
    final item = SessionHistoryItem(
      iteration: 2,
      title: 'Diritto Costituzionale #2',
      status: 'COMPLETED',
      isCurrent: false,
      turnsCompleted: 6,
      averageMastery: 0.82,
      masteredConcepts: ['Fonti del Diritto', 'Articolo 1'],
      weakConcepts: ['Procedimento Legislativo'],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ExamProvider()),
        ],
        child: MaterialApp(
          home: DiscussionDetailScreen(item: item),
        ),
      ),
    );

    await tester.pump();

    // Verify Tabs
    expect(find.text('Copertura & Esito'), findsOneWidget);
    expect(find.text('Sillabo'), findsOneWidget);
    expect(find.text('Trascrizione'), findsOneWidget);

    // Verify Verdict Card & Metrics in Tab 1
    expect(find.text('ESAME COMPLETATO CON SUCCESSO'), findsOneWidget);
    expect(find.text('28 / 30'), findsOneWidget);
    expect(find.text('82%'), findsAtLeastNWidgets(1));
    expect(find.text('Alta'), findsOneWidget);

    // Verify Sections in Tab 1
    expect(find.text('Copertura degli Argomenti'), findsOneWidget);
    expect(find.text('Cosa Ripassare Prima'), findsOneWidget);
    expect(find.text('Confronto con le Prove Precedenti'), findsOneWidget);

    // Verify Action CTA
    expect(find.text('Avvia Nuova Iterazione Adattiva'), findsOneWidget);

    // Switch to Sillabo tab
    await tester.tap(find.text('Sillabo'));
    await tester.pump();

    // Switch to Trascrizione tab
    await tester.tap(find.text('Trascrizione'));
    await tester.pumpAndSettle();

    // Verify empty state in transcript tab
    expect(find.text('Nessuno scambio registrato'), findsOneWidget);
  });

  testWidgets('DiscussionDetailScreen with dialogue turns renders filters and export notes button', (tester) async {
    final item = SessionHistoryItem(
      iteration: 1,
      title: 'Diritto Costituzionale #1',
      status: 'COMPLETED',
      isCurrent: false,
      turnsCompleted: 2,
      averageMastery: 0.85,
      masteredConcepts: ['Fonti'],
      weakConcepts: [],
    );

    final mockTurns = [
      DialogueTurn(
        turnNumber: 1,
        role: 'assistant',
        content: 'Quali sono le fonti del diritto primarie?',
        aiQuestion: 'Quali sono le fonti del diritto primarie?',
        studentResponse: 'Le leggi ordinarie del Parlamento e gli atti aventi forza di legge.',
        conceptId: 'Fonti del Diritto',
        evaluationOutcome: 'Risposta corretta e precisa',
        pedagogicalState: 'ASSESSMENT',
        scoreDelta: 0.25,
        timestamp: '2026-10-20T10:00:00Z',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(create: (_) => _MockExamProviderWithTurns([item], mockTurns)),
        ],
        child: MaterialApp(
          home: DiscussionDetailScreen(item: item),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Switch to Trascrizione tab
    await tester.tap(find.text('Trascrizione'));
    await tester.pumpAndSettle();

    // Verify filter chips and export notes button
    expect(find.text('Tutti (1)'), findsOneWidget);
    expect(find.text('✓ Corrette'), findsOneWidget);
    expect(find.text('⚠ Da Rivedere'), findsOneWidget);
    expect(find.text('Esporta Note'), findsOneWidget);
  });

  testWidgets('PreviousDiscussionsScreen does not overflow on narrow screens (320px)', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockItems = [
      SessionHistoryItem(
        iteration: 1,
        title: 'Discussione Molto Lunga Diritto Amministrativo Generale',
        status: 'COMPLETED',
        isCurrent: false,
        turnsCompleted: 8,
        averageMastery: 0.65,
        masteredConcepts: ['Fonti'],
        weakConcepts: ['Procedimento', 'Ricorsi'],
        timestamp: '2026-10-20T15:30:00Z',
      ),
      SessionHistoryItem(
        iteration: 2,
        title: 'Diritto Penale Parte Generale',
        status: 'PAUSED',
        isCurrent: true,
        turnsCompleted: 3,
        averageMastery: 0.75,
        masteredConcepts: ['Dolo'],
        weakConcepts: [],
        timestamp: '2026-10-20T16:00:00Z',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(create: (_) => _MockExamProviderWithHistory(mockItems)),
        ],
        child: const MaterialApp(
          home: PreviousDiscussionsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify both items and their buttons are rendered without RenderFlex overflow
    expect(find.text('Sillabo & Trascrizione'), findsNWidgets(2));
    expect(find.text('Ripeti con adattamento'), findsOneWidget);
    expect(find.text('Riprendi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NewDiscussionModal defaults to Carica Documento and allows switching to Genera con IA', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ExamProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NewDiscussionModal(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title and Tabs
    expect(find.text('Nuova Discussione Orale'), findsOneWidget);
    expect(find.text('Carica Documento'), findsWidgets);
    expect(find.text('Genera con IA'), findsOneWidget);
    expect(find.text('DEFAULT'), findsOneWidget);

    // Default mode is upload document: file picker prompt is visible
    expect(find.text('Tocca per selezionare PDF o dispense'), findsOneWidget);
    expect(find.text('Carica Documento & Inizia Orale'), findsOneWidget);

    // Switch to Genera con IA mode
    await tester.tap(find.text('Genera con IA'));
    await tester.pumpAndSettle();

    // Verify AI mode fields
    expect(find.text('Argomento o Tema d\'Esame'), findsOneWidget);
    expect(find.text('Genera Esame con IA & Inizia'), findsOneWidget);
    expect(find.text('Suggerimenti di Argomenti Rapidi'), findsOneWidget);

    // Tap a suggested topic chip
    await tester.tap(find.text('Diritto Costituzionale: Il Parlamento'));
    await tester.pumpAndSettle();

    // Verify topic is inserted
    expect(find.text('Diritto Costituzionale: Il Parlamento'), findsWidgets);

    // Switch back to Carica Documento
    await tester.tap(find.text('Carica Documento').first);
    await tester.pumpAndSettle();

    expect(find.text('Tocca per selezionare PDF o dispense'), findsOneWidget);
    expect(find.text('Carica Documento & Inizia Orale'), findsOneWidget);
  });

  testWidgets('Nuova conversazione under I tuoi Progressi shows bottom sheet with Carica Documento default and Genera con IA', (tester) async {
    final mockItems = [
      SessionHistoryItem(
        iteration: 1,
        title: 'Diritto Costituzionale #1',
        status: 'COMPLETED',
        isCurrent: false,
        turnsCompleted: 5,
        averageMastery: 0.80,
        masteredConcepts: ['Fonti'],
        weakConcepts: [],
        timestamp: '2026-10-20T10:00:00Z',
      ),
    ];

    final mockPlan = ExaminationPlanModel(
      hasPlan: true,
      title: 'Diritto Costituzionale',
      conceptOrder: ['c1'],
      totalConcepts: 1,
      concepts: [
        ConceptItemModel(
          conceptId: 'c1',
          conceptName: 'Fonti del Diritto',
          difficulty: 1.0,
          prerequisites: [],
          mainQuestion: 'Cosa sono le fonti?',
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(
            create: (_) => _MockExamProviderWithHistoryAndPlan(mockItems, mockPlan),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    // Verify Sessioni svolte displays 1 sessione
    expect(find.text('1 sessione'), findsOneWidget);
    expect(find.text('Sessioni svolte'), findsOneWidget);

    // Tap "Nuova" card under I tuoi progressi
    await tester.tap(find.text('Nuova'));
    await tester.pump(const Duration(milliseconds: 300));

    // Bottom sheet options: Nuova conversazione only has document & AI topic creation
    expect(find.text('Scegli come avviare la nuova discussione d\'esame:'), findsOneWidget);
    expect(find.text('Carica un documento'), findsOneWidget);
    expect(find.text('Genera da argomento'), findsOneWidget);
    expect(find.text('Ricomincia Sessione sul Corso Attuale'), findsNothing);
    expect(find.text('DEFAULT'), findsOneWidget);
    expect(find.text('WITH AI'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Close bottom sheet cleanly
    Navigator.of(tester.element(find.text('Carica un documento'))).pop();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap "Ripeti" card: now contains "Ricomincia Sessione sul Corso Attuale"
    await tester.tap(find.text('Ripeti'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ripeti Conversazione'), findsOneWidget);
    expect(find.text('Ripetizione Adattiva (Consigliata)'), findsOneWidget);
    expect(find.text('Ricomincia Sessione sul Corso Attuale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen hasResumableSession keeps single line subtitle and equal width rounded pills', (tester) async {
    final mockStatus = SessionStatusInfo(
      hasActiveSession: true,
      status: 'PAUSED',
      studentId: 'student_1',
      currentConceptId: 'Reti_Neurali_Convoluzionali_Profondi_ed_Architetture_Moderne',
      pedagogicalState: 'EXPLORATION',
      currentIteration: 2,
      planProgressPercentage: 0.45,
      planStep: '3/7',
      deferredQueue: [],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(create: (_) => _MockExamProviderWithActiveSession(mockStatus)),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify Resumable UI
    expect(find.text('SESSIONE IN CORSO'), findsOneWidget);
    expect(find.text('Riprendi Sessione'), findsOneWidget);
    expect(find.text('Riprendi Ora'), findsOneWidget);

    // Verify Fermo su text has maxLines: 1 to avoid wrapping
    final fermoSuFinder = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.startsWith('Fermo su:') ?? false),
    );
    expect(fermoSuFinder, findsOneWidget);
    final Text textWidget = tester.widget<Text>(fermoSuFinder);
    expect(textWidget.maxLines, 1);
    expect(textWidget.overflow, TextOverflow.clip);

    // Verify the two rounded pills have identical width matching the larger one
    final topPillFinder = find.ancestor(
      of: find.text('SESSIONE IN CORSO'),
      matching: find.byType(Container),
    ).first;
    final bottomPillFinder = find.ancestor(
      of: find.text('Riprendi Ora'),
      matching: find.byType(Container),
    ).first;

    final topPillSize = tester.getSize(topPillFinder);
    final bottomPillSize = tester.getSize(bottomPillFinder);

    expect(topPillSize.width, equals(bottomPillSize.width));
    expect(topPillSize.width > 0, isTrue);

    // Verify no ellipsis on rounded pill texts
    final topTextWidget = tester.widget<Text>(find.text('SESSIONE IN CORSO'));
    final bottomTextWidget = tester.widget<Text>(find.text('Riprendi Ora'));
    expect(topTextWidget.overflow, isNot(TextOverflow.ellipsis));
    expect(bottomTextWidget.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('HomeScreen cards display Nuova and Ripeti next to icon, and conversazione underneath', (tester) async {
    final mockItems = [
      SessionHistoryItem(
        iteration: 1,
        title: 'Diritto Costituzionale #1',
        status: 'COMPLETED',
        isCurrent: false,
        turnsCompleted: 5,
        averageMastery: 0.80,
        masteredConcepts: ['Fonti'],
        weakConcepts: [],
        timestamp: '2026-10-20T10:00:00Z',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ExamProvider>(create: (_) => _MockExamProviderWithHistory(mockItems)),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify Card 1 layout: "Nuova" is in a Row with the icon, "conversazione" is a sibling below the Row
    final nuovaFinder = find.text('Nuova');
    final ripetiFinder = find.text('Ripeti');
    expect(nuovaFinder, findsOneWidget);
    expect(ripetiFinder, findsOneWidget);

    final nuovaRow = find.ancestor(of: nuovaFinder, matching: find.byType(Row)).first;
    expect(find.descendant(of: nuovaRow, matching: find.byIcon(Icons.add_comment_rounded)), findsOneWidget);
    expect(find.descendant(of: nuovaRow, matching: find.text('conversazione')), findsNothing);

    final ripetiRow = find.ancestor(of: ripetiFinder, matching: find.byType(Row)).first;
    expect(find.descendant(of: ripetiRow, matching: find.byIcon(Icons.replay_rounded)), findsOneWidget);
    expect(find.descendant(of: ripetiRow, matching: find.text('conversazione')), findsNothing);
  });
}

class _MockExamProviderWithActiveSession extends ExamProvider {
  final SessionStatusInfo mockStatus;
  _MockExamProviderWithActiveSession(this.mockStatus);

  @override
  SessionStatusInfo? get sessionStatus => mockStatus;
}

class _MockExamProviderWithHistoryAndPlan extends ExamProvider {
  final List<SessionHistoryItem> mockHistory;
  final ExaminationPlanModel mockPlan;

  _MockExamProviderWithHistoryAndPlan(this.mockHistory, this.mockPlan);

  @override
  List<SessionHistoryItem> get historyItems => mockHistory;

  @override
  ExaminationPlanModel? get examinationPlan => mockPlan;
}

class _MockExamProviderWithHistory extends ExamProvider {
  final List<SessionHistoryItem> mockHistory;
  _MockExamProviderWithHistory(this.mockHistory);

  @override
  List<SessionHistoryItem> get historyItems => mockHistory;
}

class _MockExamProviderWithTurns extends ExamProvider {
  final List<SessionHistoryItem> mockHistory;
  final List<DialogueTurn> mockTurns;
  _MockExamProviderWithTurns(this.mockHistory, this.mockTurns);

  @override
  List<SessionHistoryItem> get historyItems => mockHistory;

  @override
  Future<List<DialogueTurn>> fetchTranscriptForIteration(int iteration, {String? courseId}) async {
    return mockTurns;
  }
}
