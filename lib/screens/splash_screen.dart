import 'dart:async';
import 'package:flutter/material.dart';
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
        final healthy = await exam.apiService.checkHealth();
        if (healthy && mounted) {
          await Future.wait([
            exam.fetchStatus(),
            exam.fetchPlan(),
            exam.fetchHistory(),
          ]);
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
    return Scaffold(
      backgroundColor: AppConstants.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Static Ambient Background Glow (RepaintBoundary to avoid GPU redraws)
          const RepaintBoundary(
            child: Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x1F38BDF8), // Subtle cyan glow ~12%
                        Color(0x088ED5FF),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.55, 1.0],
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
                          color: AppConstants.surfaceContainerHigh.withValues(alpha: 0.6),
                          border: Border.all(
                            color: AppConstants.primaryContainer.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: GrokAvatar(
                            mood: AvatarAgentMood.idle,
                            size: 132,
                            glowColor: AppConstants.primaryContainer,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 26),

                    // Brand Pill Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                        border: Border.all(color: AppConstants.outlineCard),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.auto_awesome, color: AppConstants.primary, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'AI VOICE TUTOR',
                            style: TextStyle(
                              color: AppConstants.primary,
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
                    const Text(
                      AppConstants.appTitle,
                      style: TextStyle(
                        color: AppConstants.textPrimary,
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
                        color: AppConstants.textSecondary.withValues(alpha: 0.85),
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
                        child: const LinearProgressIndicator(
                          backgroundColor: AppConstants.surfaceContainerHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryContainer),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Quiet Status
                    const Text(
                      'Caricamento tutor vocale...',
                      style: TextStyle(
                        color: AppConstants.textTertiary,
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
                  'Powered by LiveKit & Gemini AI',
                  style: TextStyle(
                    color: AppConstants.textTertiary.withValues(alpha: 0.5),
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
