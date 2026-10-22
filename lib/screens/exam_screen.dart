import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/avatar/avatar_models.dart';
import '../widgets/avatar/grok_avatar.dart';
import '../widgets/transcript_bubble.dart';
import 'report_screen.dart';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  void _showTranscriptHistory(BuildContext context) {
    final exam = context.read<ExamProvider>();
    final turns = exam.transcriptTurns;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusXl)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Storico della Sessione',
                        style: TextStyle(
                          color: AppConstants.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppConstants.textSecondary, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(color: AppConstants.outline),
                  const SizedBox(height: 8),
                  Expanded(
                    child: turns.isEmpty
                        ? const Center(
                            child: Text(
                              'Nessun turno registrato finora.',
                              style: TextStyle(color: AppConstants.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: turns.length,
                            itemBuilder: (context, idx) {
                              return TranscriptBubble(turn: turns[idx]);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmExit(BuildContext context) {
    final exam = context.read<ExamProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        title: const Text(
          'Concludere la simulazione?',
          style: TextStyle(
            color: AppConstants.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        content: const Text(
          'Puoi sospendere la sessione per riprenderla in un secondo momento, oppure terminarla per consultare il report finale.',
          style: TextStyle(color: AppConstants.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla', style: TextStyle(color: AppConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await exam.pauseExam();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Metti in Pausa', style: TextStyle(color: AppConstants.warning, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await exam.endExam();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportScreen(showBackButton: true)),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primary,
              foregroundColor: AppConstants.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
            ),
            child: const Text('Termina Sessione', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final status = exam.sessionStatus;
    final turns = exam.transcriptTurns;
    final mood = exam.avatarMood;
    final glow = exam.avatarGlowColor;

    final rawTopic = status?.currentConceptId ?? '';
    final topicName = rawTopic.isNotEmpty
        ? rawTopic.replaceAll('_', ' ')
        : 'Simulazione Orale';

    final latestTurn = turns.isNotEmpty ? turns.last : null;

    String stateLabel;
    switch (mood) {
      case AvatarAgentMood.speaking:
        stateLabel = 'Docente AI sta parlando';
        break;
      case AvatarAgentMood.listening:
        stateLabel = 'In ascolto della tua voce...';
        break;
      case AvatarAgentMood.thinking:
        stateLabel = 'Elaborazione socratica';
        break;
      case AvatarAgentMood.scaffolding:
        stateLabel = 'Guida personalizzata';
        break;
      case AvatarAgentMood.narrowing:
        stateLabel = 'Approfondimento mirato';
        break;
      case AvatarAgentMood.collision:
        stateLabel = 'Chiarimento concettuale';
        break;
      case AvatarAgentMood.paused:
        stateLabel = 'Sessione in pausa';
        break;
      case AvatarAgentMood.idle:
        stateLabel = 'Pronta per il tuo intervento';
        break;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: AppConstants.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // 1. Top Navigation Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppConstants.textSecondary),
                      onPressed: () => _confirmExit(context),
                    ),
                    Column(
                      children: [
                        Text(
                          topicName,
                          style: const TextStyle(
                            color: AppConstants.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (status != null && status.planStep.isNotEmpty && status.planStep != '0/0')
                          Text(
                            'Passo ${status.planStep}',
                            style: const TextStyle(
                              color: AppConstants.primaryGlow,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.history_rounded, color: AppConstants.textSecondary),
                      tooltip: 'Storico conversazione',
                      onPressed: () => _showTranscriptHistory(context),
                    ),
                  ],
                ),

                const Spacer(flex: 2),

                // 2. Central Living Grok Avatar
                GrokAvatar(
                  mood: mood,
                  size: 200,
                  glowColor: glow,
                  isSpeaking: exam.isAiSpeaking,
                  isListening: exam.isStudentSpeaking,
                ),

                const SizedBox(height: 20),

                // State Pill (DESIGN.md Pill Token)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppConstants.surfaceCard,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    border: Border.all(color: glow.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    stateLabel,
                    style: TextStyle(
                      color: glow,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // 3. Subtitle / Live Transcript Card
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 80, maxHeight: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppConstants.surfaceCard,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(color: AppConstants.outlineCard),
                  ),
                  child: Center(
                    child: latestTurn == null
                        ? Text(
                            exam.isConnected ? 'Inizia a parlare liberamente...' : 'Connessione alla stanza vocale...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppConstants.textSecondary, fontSize: 13),
                          )
                        : Text(
                            latestTurn.content,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppConstants.textPrimary,
                              fontSize: 13.5,
                              height: 1.35,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // 4. Floating Control Dock (Tactile Modern Minimalist)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppConstants.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    border: Border.all(color: AppConstants.outline),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mute / Unmute
                      IconButton(
                        icon: Icon(
                          exam.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          color: exam.isMicMuted ? AppConstants.error : AppConstants.textPrimary,
                          size: 22,
                        ),
                        tooltip: exam.isMicMuted ? 'Riattiva Microfono' : 'Disattiva Microfono',
                        onPressed: () => exam.toggleMicrophone(),
                      ),
                      const SizedBox(width: 14),

                      // Speakerphone / Earpiece
                      IconButton(
                        icon: Icon(
                          exam.isSpeakerphoneOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
                          color: exam.isSpeakerphoneOn ? AppConstants.primaryGlow : AppConstants.textSecondary,
                          size: 22,
                        ),
                        tooltip: exam.isSpeakerphoneOn ? 'Vivavoce Hi-Fi Attivo' : 'Capsula Auricolare',
                        onPressed: () => exam.toggleSpeakerphone(),
                      ),
                      const SizedBox(width: 14),

                      // Pause / Resume
                      IconButton(
                        icon: Icon(
                          status?.status == 'PAUSED' ? Icons.play_arrow_rounded : Icons.pause_rounded,
                          color: AppConstants.primaryGlow,
                          size: 26,
                        ),
                        onPressed: () {
                          if (status?.status == 'PAUSED') {
                            exam.resumeExam();
                          } else {
                            exam.pauseExam();
                          }
                        },
                      ),
                      const SizedBox(width: 14),

                      // Termina / Stop
                      IconButton(
                        icon: const Icon(
                          Icons.stop_rounded,
                          color: AppConstants.error,
                          size: 22,
                        ),
                        onPressed: () => _confirmExit(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
