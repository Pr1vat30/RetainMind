import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/avatar/avatar_models.dart';
import '../widgets/avatar/grok_avatar.dart';
import '../widgets/study_calendar_widget.dart';

class ReportScreen extends StatefulWidget {
  final bool showBackButton;

  const ReportScreen({super.key, this.showBackButton = false});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  // 0: Calendario & Attività Generali, 1: Diagnostica IA Sessione
  late int _selectedSegment;

  @override
  void initState() {
    super.initState();
    _selectedSegment = widget.showBackButton ? 1 : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExamProvider>().loadReport();
      context.read<ExamProvider>().fetchHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final analytics = StudyAnalytics.fromHistory(exam.historyItems);

    return Scaffold(
      backgroundColor: AppConstants.background,
      appBar: widget.showBackButton
          ? AppBar(
              backgroundColor: AppConstants.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppConstants.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'Riepilogo Sessione',
                style: TextStyle(color: AppConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppConstants.primaryContainer,
          backgroundColor: AppConstants.surfaceContainerHigh,
          onRefresh: () async {
            await Future.wait([
              exam.loadReport(),
              exam.fetchHistory(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 16, 20, widget.showBackButton ? 24 : 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.showBackButton) ...[
                  const Text(
                    'Report di Apprendimento',
                    style: TextStyle(
                      color: AppConstants.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Calendario delle sessioni, costanza e sintesi didattica',
                    style: TextStyle(color: AppConstants.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                ],

                // Segment Selector: [Calendario & Attività] vs [Diagnostica IA]
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppConstants.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    border: Border.all(color: AppConstants.outlineCard),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedSegment = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _selectedSegment == 0
                                  ? AppConstants.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 16,
                                  color: _selectedSegment == 0
                                      ? AppConstants.onPrimaryContainer
                                      : AppConstants.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Calendario & Attività',
                                  style: TextStyle(
                                    color: _selectedSegment == 0
                                        ? AppConstants.onPrimaryContainer
                                        : AppConstants.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: _selectedSegment == 0 ? FontWeight.bold : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedSegment = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _selectedSegment == 1
                                  ? AppConstants.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.psychology_rounded,
                                  size: 16,
                                  color: _selectedSegment == 1
                                      ? AppConstants.onPrimaryContainer
                                      : AppConstants.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Diagnostica IA',
                                  style: TextStyle(
                                    color: _selectedSegment == 1
                                        ? AppConstants.onPrimaryContainer
                                        : AppConstants.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: _selectedSegment == 1 ? FontWeight.bold : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content View according to selected segment
                if (_selectedSegment == 0) ...[
                  // 1. Study Streak Hero Card
                  StudyStreakCard(analytics: analytics),

                  const SizedBox(height: 16),

                  // 2. Interactive Study Calendar
                  StudyCalendarCard(analytics: analytics),

                  const SizedBox(height: 20),

                  // 3. Learning Habits & Macro Metrics Grid
                  StudyHabitsGrid(analytics: analytics),

                  const SizedBox(height: 20),

                  // 4. Weekly Study Rhythm (Lun - Dom)
                  WeeklyStudyRhythmCard(analytics: analytics),

                  const SizedBox(height: 20),
                ] else ...[
                  // SEGMENT 1: Demo Placeholder - Only GrokAvatar & Not Available
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const GrokAvatar(
                            mood: AvatarAgentMood.idle,
                            size: 160,
                            glowColor: AppConstants.primaryGlow,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Not available',
                            style: TextStyle(
                              color: AppConstants.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Funzionalità di diagnostica IA in arrivo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
