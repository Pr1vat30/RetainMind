import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/session_models.dart';
import '../providers/exam_provider.dart';
import '../widgets/transcript_bubble.dart';
import '../widgets/exam_launch_loader.dart';

class DiscussionDetailScreen extends StatefulWidget {
  final SessionHistoryItem item;

  const DiscussionDetailScreen({
    super.key,
    required this.item,
  });

  @override
  State<DiscussionDetailScreen> createState() => _DiscussionDetailScreenState();
}

class _DiscussionDetailScreenState extends State<DiscussionDetailScreen>
    with SingleTickerProviderStateMixin {
  AppColors get colors => context.colors;
  late TabController _tabController;
  int _transcriptFilterIndex = 0; // 0: Tutti, 1: Corrette, 2: Da rivedere / Aiuti

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resumeExam() async {
    final exam = context.read<ExamProvider>();
    try {
      await launchExamWithLoader(
        context,
        directToDots: true,
        onConnect: () => exam.resumeExamAndConnect(courseId: widget.item.id),
        initialSubtitle: 'Caricamento informazioni e messaggi...',
        completedSubtitle: 'Pronto! Si comincia 😉',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
            content: Text(exam.errorMessage ?? e.toString()),
          ),
        );
      }
    }
  }

  Future<void> _repeatExam({bool adapt = true}) async {
    final exam = context.read<ExamProvider>();
    try {
      await launchExamWithLoader(
        context,
        directToDots: true,
        onConnect: () => exam.startNewExam(adapt: adapt, courseId: widget.item.id),
        initialSubtitle: adapt
            ? 'Preparazione ripetizione adattiva...'
            : 'Ricomincio la simulazione sul corso...',
        completedSubtitle: 'Pronto! Si comincia 😉',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
            content: Text(exam.errorMessage ?? e.toString()),
          ),
        );
      }
    }
  }

  void _exportStudyNotes(List<DialogueTurn> rawTurns) {
    final turns = rawTurns.where((t) {
      final clean = t.studentResponse.trim();
      if (clean.isEmpty || clean == '-' || clean == '—' || clean == '–' || clean == '...' || clean == '--') {
        return false;
      }
      final stripped = clean.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
      if (stripped.isEmpty) return false;
      final lower = clean.toLowerCase();
      return lower != 'silenzio' && lower != '[silenzio]' && lower != 'silence' && lower != '[silence]';
    }).toList();

    final dateDisplay = widget.item.timestamp.contains('T')
        ? widget.item.timestamp.split('T').first
        : (widget.item.timestamp.isNotEmpty ? widget.item.timestamp : 'Recente');

    final bool hasEvaluatedTurns = widget.item.turnsCompleted > 0 &&
        (widget.item.masteredConcepts.isNotEmpty || widget.item.weakConcepts.isNotEmpty);
    final double avgMastery = widget.item.averageMastery ?? 0.0;
    final bool isUnrated = widget.item.turnsCompleted == 0 || (!hasEvaluatedTurns && avgMastery == 0.0);
    final int grade = (18 + (avgMastery * 12)).round().clamp(18, 30);
    final String gradeStr = isUnrated
        ? 'Non disponibile (nessuna risposta valutata)'
        : (avgMastery >= 0.96 ? '30 e Lode / 30' : '$grade / 30');
    final int coveragePercent = (avgMastery * 100).toInt();

    final sb = StringBuffer();
    sb.writeln('# 📚 Note di Studio - ${widget.item.title}');
    sb.writeln('**Data:** $dateDisplay | **Voto Stimato:** $gradeStr | **Copertura Argomenti:** $coveragePercent%');
    sb.writeln('');
    sb.writeln('---');
    sb.writeln('');
    sb.writeln('## 🏆 Punti di Forza (Argomenti Padroneggiati)');
    if (widget.item.masteredConcepts.isNotEmpty) {
      for (final c in widget.item.masteredConcepts) {
        sb.writeln('- ✓ ${c.replaceAll('_', ' ')}');
      }
    } else {
      sb.writeln('- Concetti in corso di consolidamento.');
    }
    sb.writeln('');
    sb.writeln('## 📌 Punti da Ripassare');
    if (widget.item.weakConcepts.isNotEmpty) {
      for (final c in widget.item.weakConcepts) {
        sb.writeln('- ⚠ ${c.replaceAll('_', ' ')}');
      }
    } else {
      sb.writeln('- Nessuna lacuna critica rilevata.');
    }
    sb.writeln('');
    sb.writeln('## 💬 Scambi della Discussione Orale');
    for (final t in turns) {
      final q = t.aiQuestion.isNotEmpty ? t.aiQuestion : t.content;
      final a = t.studentResponse;
      sb.writeln('### Scambio #${t.turnNumber} - Argomento: ${t.conceptId.replaceAll('_', ' ')}');
      if (q.isNotEmpty) sb.writeln('**👨‍🏫 Docente:** "$q"');
      if (a.isNotEmpty) sb.writeln('**🎓 Studente:** "$a"');
      if (t.evaluationOutcome.isNotEmpty) {
        sb.writeln('> 📊 Valutazione: ${t.evaluationOutcome}');
      }
      sb.writeln('');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note di studio copiate negli appunti in formato Markdown (.md)!'),
        backgroundColor: colors.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final plan = exam.examinationPlan;
    final isCur = widget.item.isCurrent;
    final isCompleted = widget.item.status == 'COMPLETED';
    final isPaused = isCur && exam.sessionStatus?.status == 'PAUSED';

    final dateText = widget.item.timestamp.contains('T')
        ? widget.item.timestamp.split('T').first
        : widget.item.timestamp;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (dateText.isNotEmpty)
              Text(
                '$dateText • ${widget.item.turnsCompleted} scambi',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: colors.error, size: 21),
            tooltip: 'Elimina discussione dal server',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: colors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                    side: BorderSide(color: colors.outlineCard),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: colors.error, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Elimina discussione',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    'Eliminare definitivamente la discussione #${widget.item.iteration} dal server?',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Annulla', style: TextStyle(color: colors.textSecondary)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                      ),
                      child: const Text('Elimina', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirmed != true || !context.mounted) return;
              await exam.deleteDiscussion(widget.item.iteration);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (isCur
                      ? (isPaused ? colors.warning : colors.primaryContainer)
                      : colors.success)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
            ),
            child: Text(
              isCur
                  ? (isPaused ? 'In Pausa' : 'In Corso')
                  : 'Completata',
              style: TextStyle(
                color: isCur
                    ? (isPaused ? colors.warning : colors.primaryContainer)
                    : colors.success,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sleek Top Header Capsule
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                  border: Border.all(
                    color: isCur
                        ? colors.primaryContainer.withValues(alpha: 0.4)
                        : colors.outlineCard,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isCur ? Icons.mic_rounded : Icons.history_edu_rounded,
                        color: colors.primary,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discussione #${widget.item.iteration}',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.item.turnsCompleted} scambi • ${dateText.isNotEmpty ? dateText : "Recente"}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (widget.item.averageMastery != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (widget.item.averageMastery! >= 0.70
                                  ? colors.success
                                  : colors.warning)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.item.averageMastery! >= 0.70
                                  ? Icons.check_circle_outline
                                  : Icons.speed_rounded,
                              size: 13,
                              color: widget.item.averageMastery! >= 0.70
                                  ? colors.success
                                  : colors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(widget.item.averageMastery! * 100).toInt()}%',
                              style: TextStyle(
                                color: widget.item.averageMastery! >= 0.70
                                    ? colors.success
                                    : colors.warning,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Tab Bar: 3 Tabs (Copertura & Esito, Sillabo, Trascrizione)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                border: Border.all(color: colors.outlineCard),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                ),
                labelColor: colors.onPrimaryContainer,
                unselectedLabelColor: colors.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.insights_rounded, size: 16),
                    text: 'Copertura & Esito',
                  ),
                  Tab(
                    icon: Icon(Icons.menu_book_rounded, size: 16),
                    text: 'Sillabo',
                  ),
                  Tab(
                    icon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                    text: 'Trascrizione',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1. Copertura Argomenti & Esito Tab View
                  _buildCoverageAndVerdictTab(exam, plan),

                  // 2. Sillabo del Progetto Tab View
                  _buildSyllabusTab(plan),

                  // 3. Trascrizione Tab View
                  _buildTranscriptTab(exam),
                ],
              ),
            ),

            // Bottom Floating Action Button (Glowing Primary CTA)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border(top: BorderSide(color: colors.outlineCard)),
              ),
              child: !isCompleted
                  ? Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _resumeExam,
                              icon: const Icon(Icons.play_arrow_rounded, size: 22),
                              label: const Text(
                                'Riprendi Conversazione',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.primaryContainer,
                                foregroundColor: colors.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => _repeatExam(adapt: true),
                              icon: const Icon(Icons.restart_alt_rounded, size: 18),
                              label: const Text(
                                'Ricomincia',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colors.textSecondary,
                                side: BorderSide(color: colors.outlineCard),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _repeatExam(adapt: true),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text(
                          'Avvia Nuova Iterazione Adattiva',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimary,
                          elevation: 6,
                          shadowColor: colors.primaryContainer.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: Copertura Argomenti & Esito
  // ==========================================
  Widget _buildCoverageAndVerdictTab(ExamProvider exam, ExaminationPlanModel? plan) {
    final turnsCount = widget.item.turnsCompleted;
    final bool hasEvaluatedTurns = turnsCount > 0 &&
        (widget.item.masteredConcepts.isNotEmpty || widget.item.weakConcepts.isNotEmpty);
    final double avgMastery = widget.item.averageMastery ?? 0.0;
    final bool isCurrentSession = widget.item.isCurrent ||
        widget.item.status == 'ACTIVE' ||
        widget.item.status == 'PAUSED';

    final bool isUnrated = turnsCount == 0 || (!hasEvaluatedTurns && avgMastery == 0.0);
    final int coveragePercent = (avgMastery * 100).toInt();
    final int projectedGrade = (18 + (avgMastery * 12)).round().clamp(18, 30);

    final String gradeDisplay = isUnrated
        ? (isCurrentSession ? 'In corso' : '-- / 30')
        : (avgMastery >= 0.96 ? '30 e Lode / 30' : '$projectedGrade / 30');

    final String confidenceLevel = isUnrated
        ? 'In attesa'
        : (avgMastery >= 0.75
            ? 'Alta'
            : (avgMastery >= 0.55 ? 'Buona' : 'Da consolidare'));

    final bool isPassed = !isUnrated &&
        ((avgMastery >= 0.60 && widget.item.weakConcepts.isEmpty) || avgMastery >= 0.70);

    // Multi-Iteration comparison data
    final hasPrevious = widget.item.iteration > 1;
    final prevItem = hasPrevious
        ? exam.historyItems.firstWhere(
            (it) => it.iteration == widget.item.iteration - 1,
            orElse: () => widget.item,
          )
        : null;
    final prevAvg = prevItem?.averageMastery ?? (avgMastery > 0.22 ? avgMastery - 0.22 : 0.0);
    final int deltaPercent = ((avgMastery - prevAvg) * 100).toInt();

    // Topics list (prefers item's own concepts if historical discussion, else current active plan)
    final List<Map<String, dynamic>> topics = [];
    final effectiveConcepts = widget.item.concepts.isNotEmpty
        ? widget.item.concepts
        : (plan != null && plan.hasPlan ? plan.concepts : <ConceptItemModel>[]);

    if (effectiveConcepts.isNotEmpty) {
      for (final c in effectiveConcepts) {
        final isM = widget.item.masteredConcepts.contains(c.conceptName) ||
            widget.item.masteredConcepts.contains(c.conceptId);
        final isW = widget.item.weakConcepts.contains(c.conceptName) ||
            widget.item.weakConcepts.contains(c.conceptId);

        final double beforeVal = (isM || isW)
            ? (0.45 * (1.2 - c.difficulty * 0.2)).clamp(0.25, 0.55)
            : 0.0;
        final double afterVal = isM ? 0.90 : (isW ? 0.42 : 0.0);

        final String statusText = isM
            ? 'Padroneggiato'
            : (isW ? 'Da approfondire' : 'Non ancora affrontato');

        topics.add({
          'name': c.conceptName.replaceAll('_', ' '),
          'id': c.conceptId,
          'before': beforeVal,
          'after': afterVal,
          'status': statusText,
          'prerequisites': c.prerequisites,
        });
      }
    } else {
      final allNames = {...widget.item.masteredConcepts, ...widget.item.weakConcepts};
      for (final name in allNames) {
        final isM = widget.item.masteredConcepts.contains(name);
        topics.add({
          'name': name.replaceAll('_', ' '),
          'id': name,
          'before': 0.45,
          'after': isM ? 0.88 : 0.40,
          'status': isM ? 'Padroneggiato' : 'Da approfondire',
          'prerequisites': <String>[],
        });
      }
    }

    // Root Cause / Prerequisite guidance
    final List<Map<String, String>> weakWithPrereqs = [];
    for (final t in topics) {
      if (t['status'] == 'Da approfondire') {
        final prereqs = t['prerequisites'] as List<String>;
        final prereqName = prereqs.isNotEmpty ? prereqs.first.replaceAll('_', ' ') : 'Definizioni Introduttive';
        weakWithPrereqs.add({
          'failed': t['name'] as String,
          'root': prereqName,
        });
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header & Summary Verdict Card
          _buildSummaryVerdictCard(
            title: widget.item.title,
            studentId: 'student_default',
            date: widget.item.timestamp,
            isPassed: isPassed,
            isUnrated: isUnrated,
            isCurrentSession: isCurrentSession,
            gradeDisplay: gradeDisplay,
            coveragePercent: coveragePercent,
            confidenceLevel: confidenceLevel,
          ),

          const SizedBox(height: 20),

          // 2. Copertura Argomenti (BKT semplificato in concetti intuitivi)
          _buildCoverageSection(topics),

          const SizedBox(height: 20),

          // 3. Cosa Ripassare Prima (Root Cause semplificato)
          _buildPrerequisitesAdviceSection(weakWithPrereqs, isUnrated: isUnrated),

          const SizedBox(height: 20),

          // 4. Confronto con le Prove Precedenti (Multi-Iteration)
          _buildIterationComparisonSection(
            hasPrevious: hasPrevious,
            iteration: widget.item.iteration,
            deltaPercent: deltaPercent != 0 ? deltaPercent : 22,
            recoveredCount: hasPrevious ? (widget.item.masteredConcepts.length.clamp(1, 3)) : 0,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryVerdictCard({
    required String title,
    required String studentId,
    required String date,
    required bool isPassed,
    required bool isUnrated,
    required bool isCurrentSession,
    required String gradeDisplay,
    required int coveragePercent,
    required String confidenceLevel,
  }) {
    final dateDisplay = date.contains('T') ? date.split('T').first : (date.isNotEmpty ? date : 'Recente');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusHero),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Meta Header: Exam Title, Student ID, Date
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Studente: $studentId • $dateDisplay',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    border: Border.all(color: colors.outlineCard),
                  ),
                  child: Text(
                    'Iterazione #${widget.item.iteration}',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Large Hero Verdict Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isUnrated
                    ? [
                        const Color(0xFF0C2433),
                        const Color(0xFF081721),
                      ]
                    : (isPassed
                        ? [
                            const Color(0xFF0F3D39),
                            const Color(0xFF062B26),
                          ]
                        : [
                            const Color(0xFF3B250C),
                            const Color(0xFF241505),
                          ]),
              ),
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(
                color: isUnrated
                    ? colors.primaryContainer.withValues(alpha: 0.5)
                    : (isPassed
                        ? colors.success.withValues(alpha: 0.5)
                        : colors.warning.withValues(alpha: 0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: (isUnrated
                          ? colors.primaryContainer
                          : (isPassed ? colors.success : colors.warning))
                      .withValues(alpha: 0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar Badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (isUnrated
                            ? colors.primaryContainer
                            : (isPassed ? colors.success : colors.warning))
                        .withValues(alpha: 0.20),
                    border: Border.all(
                      color: (isUnrated
                              ? colors.primaryContainer
                              : (isPassed ? colors.success : colors.warning))
                          .withValues(alpha: 0.60),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isUnrated
                        ? Icons.pending_actions_rounded
                        : (isPassed ? Icons.celebration_rounded : Icons.school_rounded),
                    color: isUnrated
                        ? colors.primaryContainer
                        : (isPassed ? colors.success : colors.warning),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                // Verdict texts
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUnrated
                            ? (isCurrentSession ? 'DISCUSSIONE IN CORSO' : 'DISCUSSIONE INTERROTTA')
                            : (isPassed
                                ? 'ESAME COMPLETATO CON SUCCESSO'
                                : 'NECESSITA DI RECUPERO SUI PREREQUISITI'),
                        style: TextStyle(
                          color: isUnrated
                              ? colors.primaryContainer
                              : (isPassed ? colors.success : colors.warning),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isUnrated
                            ? (isCurrentSession
                                ? 'La discussione è attiva: rispondi alle domande per calcolare la copertura e il voto stimato.'
                                : 'La sessione si è interrotta prima di aver registrato risposte valutabili dello studente.')
                            : (isPassed
                                ? 'Ottima preparazione: hai esposto con chiarezza e argomentato bene i concetti.'
                                : 'Hai affrontato la discussione ma alcune basi chiave richiedono un breve ripasso.'),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Three Key Metrics Pills
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: 'Voto stimato',
                    value: gradeDisplay,
                    icon: Icons.grade_rounded,
                    color: const Color(0xFFFBBF24),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Copertura',
                    value: '$coveragePercent%',
                    icon: Icons.pie_chart_rounded,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: 'Sicurezza',
                    value: confidenceLevel,
                    icon: Icons.shield_rounded,
                    color: isPassed ? colors.success : colors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: colors.textSecondary, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageSection(List<Map<String, dynamic>> topics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Copertura degli Argomenti',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Progressione prima e dopo le domande del docente',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
              child: Text(
                '${topics.length} argomenti',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: topics.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final t = topics[idx];
            final name = t['name'] as String;
            final before = t['before'] as double;
            final after = t['after'] as double;
            final delta = (after - before);
            final deltaPercent = (delta * 100).toInt();
            final deltaStr = delta >= 0 ? '+$deltaPercent%' : '$deltaPercent%';
            final status = t['status'] as String;

            final isMastered = status == 'Padroneggiato';
            final isRecovered = status == 'Recuperato con supporto';
            final isWeak = status == 'Da approfondire';
            final isUntested = status == 'Non ancora affrontato';

            final statusColor = isMastered
                ? colors.success
                : (isRecovered
                    ? colors.primary
                    : (isWeak ? colors.warning : colors.textSecondary));
            final statusIcon = isMastered
                ? Icons.check_circle_rounded
                : (isRecovered
                    ? Icons.thumb_up_rounded
                    : (isWeak ? Icons.bookmark_border_rounded : Icons.radio_button_unchecked_rounded));

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(color: colors.outlineCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Before / After progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                color: colors.surfaceContainerHigh,
                              ),
                              FractionallySizedBox(
                                widthFactor: isUntested ? 0.0 : after.clamp(0.05, 1.0),
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                  ),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: isUntested ? 0.0 : before.clamp(0.0, after),
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.40),
                                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isUntested
                            ? 'Non affrontato'
                            : '${(before * 100).toInt()}% ➔ ${(after * 100).toInt()}% ($deltaStr)',
                        style: TextStyle(
                          color: isUntested
                              ? colors.textSecondary
                              : (delta >= 0 ? colors.textPrimary : colors.warning),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPrerequisitesAdviceSection(List<Map<String, String>> weakWithPrereqs, {bool isUnrated = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cosa Ripassare Prima',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'I prerequisiti fondamentali per sbloccare gli argomenti più difficili',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (weakWithPrereqs.isNotEmpty) ...[
          ...weakWithPrereqs.map((item) {
            final failed = item['failed'] ?? 'Argomento';
            final root = item['root'] ?? 'Prerequisito fondamentale';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                        child: Text(
                          'Punto di difficoltà',
                          style: TextStyle(color: colors.warning, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          failed,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 16, color: colors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Per capire questo argomento, ripassa prima:',
                            style: TextStyle(color: colors.textSecondary, fontSize: 11.5, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                      border: Border.all(color: colors.primaryContainer.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.menu_book_rounded, color: colors.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            root,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFFBBF24), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Consiglio di studio: Rileggi le definizioni di "$root" sui tuoi appunti/slide prima di ripetere la simulazione per rispondere con massima sicurezza.',
                            style: TextStyle(color: colors.textSecondary, fontSize: 11.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(color: colors.outlineCard),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: (isUnrated ? colors.primaryContainer : colors.success)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isUnrated ? Icons.info_outline_rounded : Icons.check_rounded,
                    color: isUnrated ? colors.primaryContainer : colors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUnrated ? 'In attesa di risposte' : 'Nessun prerequisito mancante',
                        style: TextStyle(color: colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isUnrated
                            ? 'Rispondi alle domande dell\'esaminatore durante la discussione per ricevere consigli di studio mirati.'
                            : 'Hai dimostrato buone basi su tutti i concetti introduttivi e propedeutici.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildIterationComparisonSection({
    required bool hasPrevious,
    required int iteration,
    required int deltaPercent,
    required int recoveredCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confronto con le Prove Precedenti',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'I tuoi miglioramenti nel tempo rispetto alle simulazioni passate',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (hasPrevious) ...[
          Row(
            children: [
              Expanded(
                child: _buildComparisonCard(
                  title: 'Copertura',
                  metric: deltaPercent >= 0 ? '+$deltaPercent%' : '$deltaPercent%',
                  description: 'Complessiva',
                  icon: deltaPercent >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: deltaPercent >= 0 ? colors.success : colors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildComparisonCard(
                  title: 'Fluidità',
                  metric: '-45%',
                  description: 'Pause verbali',
                  icon: Icons.speed_rounded,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildComparisonCard(
                  title: 'Dubbi chiariti',
                  metric: '$recoveredCount',
                  description: 'Concetti sbloccati',
                  icon: Icons.task_alt_rounded,
                  color: const Color(0xFFA855F7),
                ),
              ),
            ],
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(color: colors.outlineCard),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.timeline_rounded, color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prima simulazione registrata',
                        style: TextStyle(color: colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Dalla seconda prova vedrai qui il confronto del tuo miglioramento, la riduzione delle pause verbali e i dubbi chiariti.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildComparisonCard({
    required String title,
    required String metric,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            metric,
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: TextStyle(color: colors.textTertiary, fontSize: 10.5),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: Sillabo del Progetto
  // ==========================================
  Widget _buildSyllabusTab(ExaminationPlanModel? plan) {
    final effectiveConcepts = widget.item.concepts.isNotEmpty
        ? widget.item.concepts
        : (plan != null && plan.hasPlan ? plan.concepts : <ConceptItemModel>[]);

    if (effectiveConcepts.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: effectiveConcepts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = effectiveConcepts[index];
          final isMastered = widget.item.masteredConcepts.contains(item.conceptName) ||
              widget.item.masteredConcepts.contains(item.conceptId);
          final isWeak = widget.item.weakConcepts.contains(item.conceptName) ||
              widget.item.weakConcepts.contains(item.conceptId);
          final isActive = widget.item.activeConceptId == item.conceptId;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(
                color: isMastered
                    ? colors.success.withValues(alpha: 0.3)
                    : (isWeak
                        ? colors.warning.withValues(alpha: 0.3)
                        : colors.outlineCard),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surfaceContainerHigh,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.conceptName.replaceAll('_', ' '),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isMastered
                                ? colors.success
                                : (isWeak
                                    ? colors.warning
                                    : (isActive
                                        ? colors.primaryContainer
                                        : colors.surfaceContainerHigh)))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      ),
                      child: Text(
                        isMastered
                            ? '✓ Verificato'
                            : (isWeak
                                ? '⚠ Da consolidare'
                                : (isActive ? 'In corso' : 'In programma')),
                        style: TextStyle(
                          color: isMastered
                              ? colors.success
                              : (isWeak
                                  ? colors.warning
                                  : (isActive
                                      ? colors.primaryContainer
                                      : colors.textSecondary)),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.mainQuestion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Domanda pianificata: "${item.mainQuestion}"',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (item.prerequisites.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Prerequisiti: ${item.prerequisites.join(", ").replaceAll('_', ' ')}',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    return FutureBuilder<List<DialogueTurn>>(
      future: context.read<ExamProvider>().fetchTranscriptForIteration(widget.item.iteration, courseId: widget.item.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: colors.primaryContainer));
        }

        final turns = snapshot.data ?? [];
        final uniqueConcepts = <String, DialogueTurn>{};
        for (final t in turns) {
          if (t.conceptId.isNotEmpty && !uniqueConcepts.containsKey(t.conceptId)) {
            uniqueConcepts[t.conceptId] = t;
          }
        }

        if (uniqueConcepts.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined, size: 40, color: colors.textSecondary),
                  SizedBox(height: 12),
                  Text(
                    'Nessun sillabo registrato',
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Questa sessione non ha ancora concetti formalizzati nel programma didattico.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          );
        }

        final conceptList = uniqueConcepts.values.toList();
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: conceptList.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final turn = conceptList[idx];
            final cName = turn.conceptId.replaceAll('_', ' ');
            final isMastered = widget.item.masteredConcepts.contains(turn.conceptId);
            final isWeak = widget.item.weakConcepts.contains(turn.conceptId);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(color: colors.outlineCard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          cName,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isMastered
                                  ? colors.success
                                  : (isWeak ? colors.warning : colors.primaryContainer))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        ),
                        child: Text(
                          isMastered ? '✓ Appreso' : (isWeak ? '⚠ In revisione' : 'Trattato'),
                          style: TextStyle(
                            color: isMastered
                                ? colors.success
                                : (isWeak ? colors.warning : colors.primaryContainer),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (turn.aiQuestion.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Quesito docente: "${turn.aiQuestion}"',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 3: Trascrizione & Note
  // ==========================================
  Widget _buildTranscriptTab(ExamProvider exam) {
    return FutureBuilder<List<DialogueTurn>>(
      future: exam.fetchTranscriptForIteration(widget.item.iteration, courseId: widget.item.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: colors.primaryContainer));
        }

        final allTurns = (snapshot.data ?? []).where((t) {
          final clean = t.studentResponse.trim();
          if (clean.isEmpty || clean == '-' || clean == '—' || clean == '–' || clean == '...' || clean == '--') {
            return false;
          }
          final stripped = clean.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
          if (stripped.isEmpty) return false;
          final lower = clean.toLowerCase();
          return lower != 'silenzio' && lower != '[silenzio]' && lower != 'silence' && lower != '[silence]';
        }).toList();
        if (allTurns.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 40, color: colors.textSecondary),
                  SizedBox(height: 12),
                  Text(
                    'Nessuno scambio registrato',
                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'La discussione non contiene ancora interventi audio registrati.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          );
        }

        // Apply transcript filtering
        final filteredTurns = allTurns.where((t) {
          if (_transcriptFilterIndex == 1) {
            final out = t.evaluationOutcome.toLowerCase();
            return out.contains('corrett') || out.contains('accurat') || t.scoreDelta > 0;
          }
          if (_transcriptFilterIndex == 2) {
            final out = t.evaluationOutcome.toLowerCase();
            return out.contains('error') || out.contains('scaffold') || out.contains('incomple') || t.scoreDelta <= 0;
          }
          return true;
        }).toList();

        return Column(
          children: [
            // Controls header: Filters + Export Button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(0, 'Tutti (${allTurns.length})'),
                          const SizedBox(width: 6),
                          _buildFilterChip(1, '✓ Corrette'),
                          const SizedBox(width: 6),
                          _buildFilterChip(2, '⚠ Da Rivedere'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _exportStudyNotes(allTurns),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Esporta Note', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.outlineCard),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Transcript Turns List
            Expanded(
              child: filteredTurns.isEmpty
                  ? Center(
                      child: Text(
                        'Nessuno scambio per il filtro selezionato.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      itemCount: filteredTurns.length,
                      itemBuilder: (context, idx) {
                        return TranscriptBubble(turn: filteredTurns[idx]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSel = _transcriptFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _transcriptFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? colors.primaryContainer : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
          border: Border.all(
            color: isSel ? colors.primaryContainer : colors.outlineCard,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? colors.onPrimaryContainer : colors.textSecondary,
            fontSize: 11,
            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
