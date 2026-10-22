import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/session_models.dart';

class TranscriptBubble extends StatelessWidget {
  final DialogueTurn turn;

  const TranscriptBubble({super.key, required this.turn});

  @override
  Widget build(BuildContext context) {
    final isAssistant = turn.role.toLowerCase() == 'assistant' ||
        turn.role.toLowerCase() == 'examiner';
    final studentClean = turn.studentResponse.trim();
    final isStudentSilence = studentClean.isEmpty ||
        studentClean == '-' ||
        studentClean == '—' ||
        studentClean == '–' ||
        studentClean == '...' ||
        studentClean.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').isEmpty;

    if (!isAssistant && isStudentSilence) {
      return const SizedBox.shrink();
    }

    final hasBoth = turn.aiQuestion.isNotEmpty && !isStudentSilence;

    Color outcomeColor = AppConstants.textSecondary;
    if (turn.evaluationOutcome.toUpperCase() == 'ACCURATE') {
      outcomeColor = AppConstants.success;
    } else if (turn.evaluationOutcome.toUpperCase() == 'PARTIAL') {
      outcomeColor = AppConstants.warning;
    } else if (turn.evaluationOutcome.toUpperCase().contains('MISCONCEPTION') ||
        turn.evaluationOutcome.toUpperCase().contains('INCORRECT')) {
      outcomeColor = AppConstants.error;
    }

    if (hasBoth) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppConstants.surfaceCard,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: AppConstants.outlineCard,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, size: 14, color: AppConstants.primaryGlow),
                    const SizedBox(width: 6),
                    Text(
                      'Turno #${turn.turnNumber}${turn.conceptId.isNotEmpty ? " • ${turn.conceptId.replaceAll('_', ' ')}" : ""}',
                      style: const TextStyle(
                        color: AppConstants.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (turn.evaluationOutcome.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: outcomeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    ),
                    child: Text(
                      turn.evaluationOutcome,
                      style: TextStyle(
                        color: outcomeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👨‍🏫 ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Text(
                    turn.aiQuestion,
                    style: const TextStyle(
                      color: AppConstants.primaryGlow,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.surfaceElevated,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎓 ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      turn.studentResponse,
                      style: const TextStyle(
                        color: AppConstants.textPrimary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (turn.scoreDelta != 0.0) ...[
              const SizedBox(height: 8),
              Text(
                'ΔPadronanza: ${turn.scoreDelta > 0 ? "+" : ""}${turn.scoreDelta.toStringAsFixed(2)}',
                style: TextStyle(
                  color: turn.scoreDelta > 0
                      ? AppConstants.success
                      : AppConstants.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Color roleColor = isAssistant ? AppConstants.primary : AppConstants.success;
    String roleLabel = isAssistant ? '👨‍🏫 Docente AI' : '🎓 Studente';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAssistant
            ? AppConstants.surfaceCard
            : AppConstants.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: isAssistant
              ? AppConstants.outlineCard
              : AppConstants.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                roleLabel,
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (turn.evaluationOutcome.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: outcomeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                  ),
                  child: Text(
                    turn.evaluationOutcome,
                    style: TextStyle(
                      color: outcomeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            turn.content,
            style: const TextStyle(
              color: AppConstants.textPrimary,
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          if (turn.scoreDelta != 0.0) ...[
            const SizedBox(height: 4),
            Text(
              'ΔMastery: ${turn.scoreDelta > 0 ? "+" : ""}${turn.scoreDelta.toStringAsFixed(2)}',
              style: TextStyle(
                color: turn.scoreDelta > 0
                    ? AppConstants.success
                    : AppConstants.error,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
