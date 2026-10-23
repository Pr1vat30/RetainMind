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

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start smooth entry animation
    _animController.forward();

    // Launch background prefetch and transition
    _initializeApp();
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final startTime = DateTime.now();
    final exam = context.read<ExamProvider>();

    // 1. Asynchronously prefetch data without blocking or triggering setState during animation
    unawaited(() async {
      try {
        // Pre-request microphone permission ahead of time so the user experiences zero audio lag/prompts
        await Permission.microphone.request();

        final healthy = await exam.apiService.checkHealth();
        if (healthy && mounted) {
          await Future.wait([
            exam.fetchStatus(),
            exam.fetchPlan(),
            exam.fetchHistory(),
          ]);

          // Prewarm Pipecat session state for the active course
          await exam.prewarmExamSession();
        }
      } catch (_) {}
    }());

    // 2. Minimum deliberate splash duration (1.6s) for visual polish
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 1600) - elapsed;
    final delay = remaining > Duration.zero ? remaining : Duration.zero;

    final completer = Completer<void>();
    _transitionTimer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;

    if (!mounted) return;

    // 3. Smooth fade out and transition into MainShell
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
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

                    // Minimal Smooth Progress Line
                    SizedBox(
                      width: 110,
                      height: 3.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        child: LinearProgressIndicator(
                          backgroundColor: colors.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.primaryContainer),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Quiet Status
                    Text(
                      'Caricamento tutor vocale...',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
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
