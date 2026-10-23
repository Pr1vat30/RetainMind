import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/new_discussion_modal.dart';

class SyllabusScreen extends StatelessWidget {
  const SyllabusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final plan = exam.examinationPlan;
    final currentConceptId = exam.sessionStatus?.currentConceptId;
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Programma di Studio',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan != null && plan.hasPlan
                              ? '${plan.title} • ${plan.totalConcepts} argomenti'
                              : 'Percorso di studio e sequenza didattica',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => NewDiscussionModal.show(context),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Carica File', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Content List
              Expanded(
                child: plan == null || !plan.hasPlan
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 44,
                              color: colors.textSecondary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Nessun programma didattico',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Carica dispense o slide in formato PDF per creare automaticamente\nil sillabo degli argomenti e avviare l\'interrogazione.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => NewDiscussionModal.show(context),
                                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                                  label: const Text('Carica Documento & Crea Sillabo'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colors.primaryContainer,
                                    foregroundColor: colors.onPrimaryContainer,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => exam.fetchPlan(),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Ricarica'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.primary,
                                    side: BorderSide(color: colors.outlineCard),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: plan.concepts.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = plan.concepts[index];
                          final isCurrent = item.conceptId == currentConceptId;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? colors.primary.withValues(alpha: 0.12)
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                              border: Border.all(
                                color: isCurrent
                                    ? colors.primary.withValues(alpha: 0.4)
                                    : colors.outlineCard,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isCurrent
                                            ? colors.primary
                                            : colors.surfaceContainerHigh,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: isCurrent ? colors.onPrimary : colors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.conceptName,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? colors.primaryGlow
                                                  : colors.textPrimary,
                                              fontSize: 14,
                                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                            ),
                                          ),
                                          if (item.mainQuestion.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              item.mainQuestion,
                                              style: TextStyle(
                                                color: colors.textSecondary,
                                                fontSize: 12,
                                                height: 1.25,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isCurrent)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colors.primary.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                        ),
                                        child: Text(
                                          'In Corso',
                                          style: TextStyle(
                                            color: colors.primaryGlow,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (item.prerequisites.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    children: item.prerequisites.map((p) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                        ),
                                        child: Text(
                                          'Prereq: ${p.replaceAll('_', ' ')}',
                                          style: TextStyle(
                                            color: colors.textTertiary,
                                            fontSize: 10,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
