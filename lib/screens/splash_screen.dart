import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/exam_provider.dart';
import '../widgets/avatar/avatar_models.dart';
import '../widgets/avatar/grok_avatar.dart';
import 'main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  String _statusText = 'Inizializzazione tutor vocale...';
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();

    // 1. Entry Animation (650ms, easeOutCubic)
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: Curves.easeOutCubic,
      ),
    );

    // 2. Continuous Progress Controller (smoothly interpolated)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    );

    // Start entry animation immediately
    _entryController.forward();

    // Launch genuine prefetching and initialization
    _initializeApp();
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _entryController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _updateStage(double targetProgress, String status) {
    if (!mounted) return;
    setState(() {
      _statusText = status;
    });
    _progressController.animateTo(
      targetProgress,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _initializeApp() async {
    final startTime = DateTime.now();
    final exam = context.read<ExamProvider>();

    try {
      // Step 1: Pre-request microphone permission
      _updateStage(0.20, 'Configurazione microfono e audio...');
      await Permission.microphone.request();

      // Step 2: Check server connectivity
      _updateStage(0.42, 'Connessione al server...');
      final healthy = await exam.apiService.checkHealth();

      // Step 3: Fetch active session status, plan, and history in parallel
      if (healthy && mounted) {
        _updateStage(0.72, 'Caricamento percorso didattico e progressi...');
        await Future.wait([
          exam.fetchStatus(),
          exam.fetchPlan(),
          exam.fetchHistory(),
        ]);

        // Step 4: Prewarm WebRTC voice session
        _updateStage(0.90, 'Preparazione sessione vocale...');
        await exam.prewarmExamSession();
      }

      _updateStage(1.0, 'Tutto pronto!');
    } catch (e) {
      debugPrint('Splash preload error: $e');
      _updateStage(1.0, 'Avvio in corso...');
    }

    // Ensure a smooth minimum duration (1050ms) so progress feels fluid and polished
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsed < 1050) {
      await Future.delayed(Duration(milliseconds: 1050 - elapsed));
    }

    if (!mounted) return;

    // Smooth fade out and transition into MainShell
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Static Ambient Background Glow (RepaintBoundary to avoid GPU redraws)
          RepaintBoundary(
            child: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        colors.primaryContainer.withValues(alpha: 0.12),
                        colors.primary.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. Main Animated Content (Fade & Gentle Scale)
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Isolated Avatar Layer (RepaintBoundary)
                    RepaintBoundary(
                      child: Container(
                        width: 154,
                        height: 154,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surfaceContainerHigh.withValues(alpha: 0.6),
                          border: Border.all(
                            color: colors.primaryContainer.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: GrokAvatar(
                            mood: AvatarAgentMood.idle,
                            size: 132,
                            glowColor: colors.primaryContainer,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 26),

                    // Brand Pill Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        border: Border.all(color: colors.outlineCard),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: colors.primary, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'AI VOICE TUTOR',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // App Title
                    Text(
                      AppConstants.appTitle,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Subtitle
                    Text(
                      AppConstants.appSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textSecondary.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Smooth Live Progress Line
                    SizedBox(
                      width: 130,
                      height: 3.5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        child: AnimatedBuilder(
                          animation: _progressAnimation,
                          builder: (context, _) {
                            return LinearProgressIndicator(
                              value: _progressAnimation.value.clamp(0.0, 1.0),
                              backgroundColor: colors.surfaceContainerHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(colors.primaryContainer),
                            );
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Quiet Status
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _statusText,
                        key: ValueKey<String>(_statusText),
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom Footer
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Powered by Pipecat & Gemini AI',
                  style: TextStyle(
                    color: colors.textTertiary.withValues(alpha: 0.5),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
