import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/session_models.dart';

class BktProgressBar extends StatelessWidget {
  final SessionStatusInfo? statusInfo;

  const BktProgressBar({super.key, required this.statusInfo});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = (statusInfo?.planProgressPercentage ?? 0.0) / 100.0;
    final concept = statusInfo?.currentConceptId.isNotEmpty == true
        ? statusInfo!.currentConceptId.replaceAll('_', ' ').toUpperCase()
        : 'IN ATTESA';
    final step = statusInfo?.planStep ?? '0/0';
    final fsmState = statusInfo?.pedagogicalState ?? 'EXPLORATION';
    final stateColor = colors.getPedagogicalColor(fsmState);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: colors.outlineCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.school, size: 16, color: colors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Argomento: $concept',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: stateColor.withValues(alpha: 0.6), width: 1),
                ),
                child: Text(
                  fsmState,
                  style: TextStyle(
                    color: stateColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primaryContainer),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progresso esame: ${(progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
              Text(
                'Passo $step',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
