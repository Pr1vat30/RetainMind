import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/pipecat_service.dart';

class AudioVisualizer extends StatefulWidget {
  final SpeakingStateEnum speakingState;
  final bool isMuted;

  const AudioVisualizer({
    super.key,
    required this.speakingState,
    this.isMuted = false,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.10).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color glowColor;
    String statusText;
    IconData statusIcon;

    if (widget.isMuted) {
      glowColor = colors.textSecondary;
      statusText = 'MICROFONO MUTATO';
      statusIcon = Icons.mic_off;
    } else {
      switch (widget.speakingState) {
        case SpeakingStateEnum.aiSpeaking:
          glowColor = colors.primaryGlow;
          statusText = 'DOCENTE AI STA PARLANDO';
          statusIcon = Icons.volume_up;
          break;
        case SpeakingStateEnum.studentSpeaking:
          glowColor = colors.success;
          statusText = 'TU STAI PARLANDO';
          statusIcon = Icons.mic;
          break;
        case SpeakingStateEnum.idle:
          glowColor = colors.accent;
          statusText = 'IN ASCOLTO';
          statusIcon = Icons.hearing;
          break;
        case SpeakingStateEnum.thinking:
          glowColor = colors.warning;
          statusText = 'ELABORAZIONE RISPOSTA';
          statusIcon = Icons.psychology;
          break;
      }
    }

    final isPulsing =
        widget.speakingState != SpeakingStateEnum.idle && !widget.isMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            final scale = isPulsing ? _scaleAnimation.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glowColor.withValues(alpha: 0.35),
                      glowColor.withValues(alpha: 0.05),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.4),
                      blurRadius: isPulsing ? 32 : 16,
                      spreadRadius: isPulsing ? 6 : 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surfaceContainerLow,
                      border: Border.all(
                        color: glowColor,
                        width: 2.5,
                      ),
                    ),
                    child: Icon(
                      statusIcon,
                      size: 40,
                      color: glowColor,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppConstants.radiusPill),
            border: Border.all(
              color: glowColor.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  color: glowColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
