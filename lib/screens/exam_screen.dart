import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/avatar/avatar_models.dart';
import '../widgets/avatar/grok_avatar.dart';

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  void _confirmExit(BuildContext context) {
    final exam = context.read<ExamProvider>();
    final colors = context.colors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusLg)),
        title: Text(
          'Uscire dalla chiamata?',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        content: Text(
          exam.isDirectTestMode
              ? 'La sessione di test diretto verrà chiusa e tornerai alla home.'
              : 'La sessione verrà salvata e tornerai alla schermata principale.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annulla', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (exam.isDirectTestMode) {
                await exam.endDirectTest();
              } else {
                await exam.pauseExam();
              }
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
            ),
            child: const Text('Esci dalla chiamata', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<ExamProvider>();
    final colors = context.colors;
    final status = exam.sessionStatus;
    final mood = exam.avatarMood;
    final glow = exam.avatarGlowColor;

    final rawTopic = status?.currentConceptId ?? '';
    final topicName = exam.isDirectTestMode
        ? '⚡ Test Vocale Diretto'
        : (rawTopic.isNotEmpty ? rawTopic.replaceAll('_', ' ') : 'Simulazione Orale');

    final currentQuestion = exam.currentAiQuestion;

    String stateLabel;
    if (exam.isDirectTestMode) {
      if (exam.isAiSpeaking) {
        stateLabel = 'Docente AI sta parlando';
      } else if (exam.isStudentSpeaking) {
        stateLabel = 'In ascolto della tua voce...';
      } else if (exam.isAiThinking) {
        stateLabel = 'Elaborazione risposta...';
      } else {
        stateLabel = '⚡ Connessione Diretta Gemini';
      }
    } else {
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
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              children: [
                // 1. Top Navigation Bar (Close & Centered Topic Header)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                      tooltip: 'Esci dalla chiamata',
                      onPressed: () => _confirmExit(context),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            topicName,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (!exam.isDirectTestMode && status != null && status.planStep.isNotEmpty && status.planStep != '0/0')
                            Text(
                              'Passo ${status.planStep}',
                              style: TextStyle(
                                color: colors.primaryGlow,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48), // Balances the leading close button
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
                    color: colors.surfaceContainerLow,
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

                // 3. Question Card (Exclusive AI Question without conversational chatter)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 88, maxHeight: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(color: colors.outlineCard),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            exam.isDirectTestMode ? Icons.bolt_rounded : Icons.help_outline_rounded,
                            size: 13.5,
                            color: glow,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            exam.isDirectTestMode ? "TEST DIRETTO STREAMING" : "DOMANDA D'ESAME",
                            style: TextStyle(
                              color: glow,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        exam.isDirectTestMode
                            ? (exam.isAiSpeaking
                                ? 'AI in conversazione diretta...'
                                : 'Parla liberamente. Connessione audio diretta attiva senza database né filtri.')
                            : (currentQuestion.isNotEmpty
                                ? currentQuestion
                                : (exam.isConnected
                                    ? 'In attesa della domanda del docente...'
                                    : 'Connessione alla stanza vocale...')),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

        // 4. Floating Control Dock (Tactile Minimalist: Mic ON/OFF + End Call only)
                // RepaintBoundary isolates this static dock from the high-frequency
                // avatar repaints (60fps loop animation).
                RepaintBoundary(
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                    border: Border.all(color: colors.outlineCard),
                    boxShadow: [
                      BoxShadow(
                        color: colors.floatingNavShadow,
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Microphone ON / OFF
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => exam.toggleMicrophone(),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: exam.isMicMuted
                                  ? colors.error.withValues(alpha: 0.16)
                                  : colors.surfaceContainerHighest,
                              border: Border.all(
                                color: exam.isMicMuted
                                    ? colors.error.withValues(alpha: 0.5)
                                    : colors.outlineVariant,
                              ),
                            ),
                            child: Icon(
                              exam.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              color: exam.isMicMuted ? colors.error : colors.textPrimary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // End Call / Uscita dalla Chiamata
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _confirmExit(context),
                          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.error,
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x66EF4444),
                                  blurRadius: 14,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ), // End RepaintBoundary for control dock

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
