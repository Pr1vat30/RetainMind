import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/session_models.dart';
import '../providers/exam_provider.dart';
import '../widgets/avatar/avatar_models.dart';
import '../widgets/avatar/grok_avatar.dart';
import '../widgets/new_discussion_modal.dart';
import '../widgets/exam_launch_loader.dart';
import 'discussion_detail_screen.dart';
import 'previous_discussions_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenSyllabus;
  final VoidCallback? onOpenCronologia;

  const HomeScreen({
    super.key,
    this.onOpenSyllabus,
    this.onOpenCronologia,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppColors get colors => context.colors;
  bool get isDark => context.isDarkMode;
  bool _backendHealthy = false;
  final GlobalKey _bannerAvatarKey = GlobalKey();

  // Cached layout measurements for dynamic pills to avoid recomputing TextPainter on every tick
  String? _cachedTopPillText;
  String? _cachedBottomPillText;
  TextScaler? _cachedTextScaler;
  double? _cachedDynamicPillWidth;

  Offset? _getBannerAvatarCenter() {
    final renderBox = _bannerAvatarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final pos = renderBox.localToGlobal(Offset.zero);
      return Offset(pos.dx + renderBox.size.width / 2, pos.dy + renderBox.size.height / 2);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    final provider = context.read<ExamProvider>();
    final healthy = await provider.apiService.checkHealth();
    if (mounted) {
      setState(() {
        _backendHealthy = healthy;
      });
      await Future.wait([
        provider.fetchStatus(),
        provider.fetchPlan(),
        provider.fetchHistory(),
      ]);
      if (provider.historyItems.isNotEmpty || provider.sessionStatus != null) {
        if (!_backendHealthy && mounted) {
          setState(() {
            _backendHealthy = true;
          });
        }
      }
      if (provider.prewarmedSession == null) {
        unawaited(provider.prewarmExamSession());
      }
    }
  }

  Future<void> _resumeExam() async {
    final exam = context.read<ExamProvider>();
    try {
      await launchExamWithLoader(
        context,
        onConnect: () => exam.resumeExamAndConnect(),
        startCenter: _getBannerAvatarCenter(),
        startSize: 105.0,
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

  Future<void> _startNewExam({bool adapt = false}) async {
    final exam = context.read<ExamProvider>();
    try {
      await launchExamWithLoader(
        context,
        onConnect: () => exam.startNewExam(adapt: adapt),
        startCenter: _getBannerAvatarCenter(),
        startSize: 105.0,
        initialSubtitle: adapt
            ? 'Preparazione sessione adattiva...'
            : 'Creazione nuova sessione d\'esame...',
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

  Future<void> _startDirectTest() async {
    final exam = context.read<ExamProvider>();
    try {
      await launchExamWithLoader(
        context,
        onConnect: () => exam.startDirectTestSession(),
        startCenter: _getBannerAvatarCenter(),
        startSize: 105.0,
        initialSubtitle: 'Connessione vocale diretta (Gemini Live)...',
        completedSubtitle: 'Pronto! Parla liberamente ⚡',
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

  void _showNewConversationDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusCard)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nuova Conversazione',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Scegli come avviare la nuova discussione d\'esame:',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Option 1 (DEFAULT): Upload Document
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  NewDiscussionModal.show(context, initialMode: NewDiscussionMode.uploadDocument);
                },
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: colors.primaryContainer.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Icon(Icons.upload_file_rounded, color: colors.primaryContainer, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Carica un documento',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'DEFAULT',
                                    style: TextStyle(
                                      color: colors.primaryContainer,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Importa PDF, dispense o appunti per avviare una discussione d\'esame.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 2: Generate with AI from Topic
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  NewDiscussionModal.show(context, initialMode: NewDiscussionMode.aiTopic);
                },
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: colors.outlineCard,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: colors.secondary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Genera da argomento',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colors.secondary.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'WITH AI',
                                    style: TextStyle(
                                      color: colors.secondary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Nessun file necessario: l\'IA crea l\'intero programma da un tema a scelta.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 3: Direct Voice Test (Zero Latency / No DB Benchmark)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _startDirectTest();
                },
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: colors.primaryGlow.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primaryGlow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Icon(Icons.bolt_rounded, color: colors.primaryGlow, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Test Vocale Diretto (Zero Latenza)',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: colors.primaryGlow.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'BENCHMARK',
                                    style: TextStyle(
                                      color: colors.primaryGlow,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Connessione vocale pura senza database, vettori o piani d\'esame.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showRepeatConversationDialog(BuildContext context) {
    final exam = context.read<ExamProvider>();
    final plan = exam.examinationPlan;

    if (plan == null || !plan.hasPlan) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: colors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusSm)),
          content: const Text('Carica prima un documento per avviare o ripetere una sessione.'),
        ),
      );
      NewDiscussionModal.show(context);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusCard)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ripeti Conversazione',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Ricomincia la sessione di studio per consolidare la tua preparazione:',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Option 1: Adaptive
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _startNewExam(adapt: true);
                },
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: colors.primaryContainer.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Icon(Icons.psychology_outlined, color: colors.primaryContainer, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ripetizione Adattiva (Consigliata)',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'La docente focalizzerà le domande sui concetti dove hai mostrato incertezze per consolidare la preparazione.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Option 2: Clean from scratch on current course
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _startNewExam(adapt: false);
                },
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(
                      color: colors.outlineCard,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                        ),
                        child: Icon(Icons.restart_alt_rounded, color: colors.textSecondary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ricomincia Sessione sul Corso Attuale',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Inizia dall\'inizio del programma già aperto con domande esplorative standard.',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showConversationDetails(BuildContext context, SessionHistoryItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiscussionDetailScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDarkMode;
    final exam = context.watch<ExamProvider>();
    final status = exam.sessionStatus;
    final plan = exam.examinationPlan;
    final history = exam.historyItems;

    final isPaused = status?.status == 'PAUSED';
    final hasActiveSession = status?.hasActiveSession == true && status?.status != 'NOT_INITIALIZED';
    final hasResumableSession = hasActiveSession || isPaused;

    final rawTopic = status?.currentConceptId ?? '';
    final topicName = rawTopic.isNotEmpty
        ? rawTopic.replaceAll('_', ' ')
        : (plan?.title ?? 'Studio Generale');

    // Calculated Study Progress Stats
    final totalTurns = history.fold<int>(0, (sum, item) => sum + item.turnsCompleted);
    final displayTurns = totalTurns > 0
        ? totalTurns
        : (exam.diagnosticReport?.totalTurns ?? 0);
    final avgMastery = (history.isNotEmpty && history.last.averageMastery != null)
        ? history.last.averageMastery
        : exam.diagnosticReport?.overallMasteryScore;
    final masteryText = avgMastery != null ? '${(avgMastery * 100).toInt()}%' : '--';
    final sessionsCount = history.length;
    final sessionsText = sessionsCount == 1 ? '1 sessione' : '$sessionsCount sessioni';

    // Dynamic sizing for Resumable Session rounded pills (matches the larger of the two)
    final topPillText = hasResumableSession
        ? 'SESSIONE IN CORSO'
        : (history.isEmpty ? 'PRIMA SESSIONE' : 'TUTOR ATTIVO');
    final topPillStyle = TextStyle(
      color: isDark ? colors.surfaceContainerLowest : const Color(0xFF0F172A),
      fontSize: 10.5,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.4,
    );

    final bottomPillText = hasResumableSession
        ? 'Riprendi Ora'
        : (history.isEmpty
            ? 'Carica File & Inizia'
            : (plan == null || !plan.hasPlan
                ? 'Nuova Sessione'
                : 'Inizia Ora'));
    final bottomPillStyle = TextStyle(
      color: isDark ? colors.onSurface : const Color(0xFF0F172A),
      fontSize: 13,
      fontWeight: FontWeight.bold,
    );

    double? dynamicPillWidth;
    if (hasResumableSession) {
      final textScaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
      if (_cachedDynamicPillWidth != null &&
          _cachedTopPillText == topPillText &&
          _cachedBottomPillText == bottomPillText &&
          _cachedTextScaler == textScaler) {
        dynamicPillWidth = _cachedDynamicPillWidth;
      } else {
        final topPainter = TextPainter(
          text: TextSpan(text: topPillText, style: topPillStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
        final bottomPainter = TextPainter(
          text: TextSpan(text: bottomPillText, style: bottomPillStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();

        final topNaturalWidth = 20.0 + 14.0 + 4.0 + topPainter.width + 8.0;
        final bottomNaturalWidth = 28.0 + 18.0 + 6.0 + bottomPainter.width + 8.0;
        dynamicPillWidth = math.max(topNaturalWidth, bottomNaturalWidth).ceilToDouble();
        topPainter.dispose();
        bottomPainter.dispose();

        _cachedTopPillText = topPillText;
        _cachedBottomPillText = bottomPillText;
        _cachedTextScaler = textScaler;
        _cachedDynamicPillWidth = dynamicPillWidth;
      }
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: colors.primaryContainer,
          backgroundColor: colors.surfaceContainerHigh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top Bar: OraleIA brand + Notifications & Profile (HTML: h-16 header)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.surfaceContainerHigh,
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            color: colors.primary,
                            size: 19,
                          ),
                        ),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Retain Mind',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Home',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.bolt_rounded,
                            size: 24,
                            color: colors.primaryGlow,
                          ),
                          tooltip: 'Test Vocale Diretto (Zero Latenza)',
                          onPressed: _startDirectTest,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.notifications_none_rounded,
                            size: 22,
                            color: colors.textSecondary,
                          ),
                          onPressed: () {},
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 18,
                            color: colors.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // 2. Welcome Sub-Header & Motivation (HTML: Ciao, Matteo 👋 + Livello 4)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Ciao, Studente',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 6),
                              Text('👋', style: TextStyle(fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        border: Border.all(color: colors.outlineCard),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspace_premium_outlined, color: colors.primary, size: 15),
                          SizedBox(width: 5),
                          Text(
                            'Tier Free',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Connection Alert Banner if server is unreachable
                if (!_backendHealthy && history.isEmpty && status == null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                      border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: colors.warning, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Server non raggiungibile su ${exam.apiService.baseUrl}. Assicurati che il Mac e lo smartphone siano sulla stessa rete Wi-Fi.',
                            style: TextStyle(color: colors.textPrimary, fontSize: 12, height: 1.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _refreshAll,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('Riprova', style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                // 3. Hero Banner: Sky-Blue Tactile Card with 3D Companion (HTML Banner)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors.heroGradient,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusHero),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primaryContainer.withValues(alpha: isDark ? 0.38 : 0.25),
                        blurRadius: 36,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Left content
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Pill Badge
                            Container(
                              width: dynamicPillWidth,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLowest.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        hasResumableSession
                                            ? Icons.play_circle_filled_rounded
                                            : (history.isEmpty ? Icons.auto_awesome_rounded : Icons.verified_rounded),
                                        size: 14,
                                        color: colors.surfaceContainerLowest,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        topPillText,
                                        style: topPillStyle,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              hasResumableSession
                                  ? 'Riprendi Sessione'
                                  : (history.isEmpty ? 'Inizia la tua Prima Simulazione' : 'Simulazione Orale AI'),
                              style: TextStyle(
                                color: isDark ? colors.surfaceContainerLowest : const Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasResumableSession
                                  ? 'Fermo su: $topicName'
                                  : (plan != null && plan.hasPlan
                                      ? 'Materia: ${plan.title}'
                                      : 'Carica slide, dispense o PDF per avviare la tua prima interrogazione vocale.'),
                              style: TextStyle(
                                color: (isDark ? colors.surfaceContainerLowest : const Color(0xFF1E293B)).withValues(alpha: 0.85),
                                fontSize: 12.5,
                                height: 1.3,
                              ),
                              maxLines: hasResumableSession ? 1 : 2,
                              overflow: hasResumableSession ? TextOverflow.clip : TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 14),

                            // CTA Pill Button (HTML: rounded-full bg-surface-container-lowest)
                            GestureDetector(
                              onTap: exam.isLoading || !_backendHealthy
                                  ? null
                                  : () {
                                      if (hasResumableSession) {
                                        _resumeExam();
                                      } else {
                                        NewDiscussionModal.show(context);
                                      }
                                    },
                              child: Container(
                                width: dynamicPillWidth,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isDark ? colors.surfaceContainerLowest : Colors.white,
                                  borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isDark ? colors.surfaceContainerLowest : Colors.black).withValues(alpha: isDark ? 0.35 : 0.12),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          hasResumableSession
                                              ? Icons.play_arrow_rounded
                                              : (history.isEmpty ? Icons.upload_file_rounded : Icons.mic_none_rounded),
                                          size: 18,
                                          color: colors.primary,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          bottomPillText,
                                          style: bottomPillStyle,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Right Content: Interactive GrokAvatar / Robot Companion
                      Expanded(
                        flex: 4,
                        child: Center(
                          child: GrokAvatar(
                            key: _bannerAvatarKey,
                            mood: isPaused ? AvatarAgentMood.paused : AvatarAgentMood.idle,
                            size: 105,
                            glowColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // 4. Quick Study Progress Stats (I tuoi Progressi)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'I tuoi Progressi',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (history.isEmpty) {
                          NewDiscussionModal.show(context);
                        } else if (widget.onOpenCronologia != null) {
                          widget.onOpenCronologia!();
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PreviousDiscussionsScreen()),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            history.isEmpty ? 'Inizia ora' : 'Cronologia',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(Icons.chevron_right_rounded, size: 16, color: colors.primary),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Progress Stat Capsules
                Row(
                  children: [
                    Expanded(
                      child: _buildProgressStatCard(
                        icon: Icons.school_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        value: sessionsText,
                        label: 'Sessioni svolte',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildProgressStatCard(
                        icon: Icons.speed_rounded,
                        iconColor: colors.primary,
                        value: masteryText,
                        label: 'Padronanza',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildProgressStatCard(
                        icon: Icons.graphic_eq_rounded,
                        iconColor: colors.secondary,
                        value: '$displayTurns scambi',
                        label: 'Pratica vocale',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // 5. Feature Cards Grid: 2 Columns: Nuova conversazione & Carica Documento / Ripeti
                Row(
                  children: [
                    // Card 1: Nuova conversazione
                    Expanded(
                      child: InkWell(
                        onTap: () => _showNewConversationDialog(context),
                        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                            border: Border.all(color: colors.outlineCard),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Icon (left) + "Nuova" (right-aligned, height 44 matching icon)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(Icons.add_comment_rounded, color: colors.primary, size: 22),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 44,
                                      alignment: Alignment.center,
                                      child: Text(
                                        'Nuova',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // "conversazione" placed below both icon and text
                              Text(
                                'conversazione',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                history.isEmpty
                                    ? 'Avvia la tua prima discussione orale con l\'assistente'
                                    : 'Inizia una nuova sessione caricando appunti o con l\'ai',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Inizia ora',
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_rounded, size: 16, color: colors.primary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Card 2: Carica Documento (if first time) / Ripeti conversazione (if has history)
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (history.isEmpty || plan == null || !plan.hasPlan) {
                            NewDiscussionModal.show(context);
                          } else {
                            _showRepeatConversationDialog(context);
                          }
                        },
                        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                            border: Border.all(color: colors.outlineCard),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Row: Icon (left) + "Ripeti" (or "Carica", right-aligned, height 44 matching icon)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      history.isEmpty ? Icons.upload_file_rounded : Icons.replay_rounded,
                                      color: colors.secondary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 44,
                                      alignment: Alignment.center,
                                      child: Text(
                                        history.isEmpty ? 'Carica' : 'Ripeti',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // "conversazione" (or "Documento") placed below both icon and text
                              Text(
                                history.isEmpty ? 'Documento' : 'conversazione',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                history.isEmpty
                                    ? 'Importa slide, PDF o dispense per preparare l\'interrogazione'
                                    : 'Ripeti focalizzandoti sulle lacune della sessione precedente',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    history.isEmpty ? 'Carica file' : 'Riavvia test',
                                    style: TextStyle(
                                      color: colors.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Icon(
                                    history.isEmpty ? Icons.upload_rounded : Icons.replay_rounded,
                                    size: 16,
                                    color: colors.secondary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // 6. Recent Documents & Conversations Section (HTML: Documenti Recenti)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Documenti & Sessioni',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    // Testo e freccetta per reindirizzare (o caricare file se primo accesso)
                    InkWell(
                      onTap: () {
                        if (history.isEmpty) {
                          NewDiscussionModal.show(context);
                        } else if (widget.onOpenCronologia != null) {
                          widget.onOpenCronologia!();
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PreviousDiscussionsScreen()),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              history.isEmpty ? 'Carica file' : 'Cronologia',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              history.isEmpty ? Icons.upload_rounded : Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // If real history exists, render ONLY recent sessions (latest 3 items)
                if (history.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      final recentHistory = history.take(3).toList();
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: recentHistory.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final item = recentHistory[idx];
                          final isCurrent = item.isCurrent;
                          final isItemPaused = isCurrent && isPaused;

                          return InkWell(
                            onTap: () => _showConversationDetails(context, item),
                            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                                border: Border.all(
                                  color: isCurrent
                                      ? colors.primaryContainer.withValues(alpha: 0.4)
                                      : colors.outlineCard,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      isCurrent ? Icons.mic_rounded : Icons.description_outlined,
                                      color: isCurrent
                                          ? (isItemPaused ? colors.warning : colors.primaryContainer)
                                          : colors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            color: colors.textPrimary,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Text(
                                              '${item.turnsCompleted} scambi',
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 3,
                                              height: 3,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: colors.textTertiary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              item.averageMastery != null
                                                  ? '${(item.averageMastery! * 100).toInt()}% assimilato'
                                                  : (isCurrent ? 'In corso' : 'Completata'),
                                              style: TextStyle(
                                                color: (item.averageMastery ?? 0) >= 0.70
                                                    ? colors.primary
                                                    : (isCurrent ? colors.warning : colors.textSecondary),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colors.surfaceContainer,
                                    ),
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: colors.textSecondary,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (history.length > 3) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          if (widget.onOpenCronologia != null) {
                            widget.onOpenCronologia!();
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PreviousDiscussionsScreen()),
                            );
                          }
                        },
                        icon: Icon(Icons.history_rounded, size: 16, color: colors.primary),
                        label: Text(
                          'Vedi tutte le ${history.length} discussioni precedenti',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ] else
                  // Clean empty state when no study documents or sessions have been recorded
                  InkWell(
                    onTap: () => NewDiscussionModal.show(context),
                    borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                        border: Border.all(color: colors.outlineCard),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surfaceContainerHigh,
                            ),
                            child: Icon(
                              Icons.upload_file_rounded,
                              color: colors.primaryContainer,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nessun documento caricato',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Carica i tuoi appunti o slide in formato PDF per avviare la simulazione d\'esame.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => NewDiscussionModal.show(context),
                            icon: const Icon(Icons.upload_file_rounded, size: 16),
                            label: const Text('Carica Documento & Inizia'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primaryContainer,
                              foregroundColor: colors.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStatCard({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
