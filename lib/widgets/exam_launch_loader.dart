import 'dart:async';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../screens/exam_screen.dart';
import 'avatar/bloub_morphing_avatar.dart';

/// Launches the AI oral examination calling screen ([ExamScreen]) with a high-fidelity
/// Bloub avatar loading animation.
///
/// Behavior:
/// - When [directToDots] is true (or [startCenter] is null), the overlay appears directly
///   centered with the 3 pulsating wave dots (● ● ●), without any flight from the banner.
/// - When [directToDots] is false and [startCenter] is provided (e.g. clicking the main CTA
///   button on the Home banner), the avatar glides from the banner to the center, morphs into
///   the 3 wave dots while connecting, and seamlessly transitions into the call.
Future<void> launchExamWithLoader(
  BuildContext context, {
  required Future<void> Function() onConnect,
  Offset? startCenter,
  double? startSize,
  bool directToDots = false,
  String? title,
  String? subtitle,
  String initialSubtitle = 'Caricamento informazioni e messaggi...',
  String completedSubtitle = 'Pronto! Si comincia 😉',
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final effectiveInitialSubtitle = subtitle ?? initialSubtitle;
  final effectiveDirectToDots = directToDots || startCenter == null;

  try {
    final result = await nav.push<Object?>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return ExamLaunchTransitionOverlay(
            onConnect: onConnect,
            startCenter: startCenter,
            startSize: startSize,
            directToDots: effectiveDirectToDots,
            title: title,
            initialSubtitle: effectiveInitialSubtitle,
            completedSubtitle: completedSubtitle,
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );

    if (result != null && result is Exception) {
      throw result;
    }
  } catch (e) {
    rethrow;
  }
}

class ExamLaunchTransitionOverlay extends StatefulWidget {
  final Future<void> Function() onConnect;
  final Offset? startCenter;
  final double? startSize;
  final bool directToDots;
  final String? title;
  final String initialSubtitle;
  final String completedSubtitle;

  const ExamLaunchTransitionOverlay({
    super.key,
    required this.onConnect,
    this.startCenter,
    this.startSize,
    this.directToDots = false,
    this.title,
    this.initialSubtitle = 'Caricamento informazioni e messaggi...',
    this.completedSubtitle = 'Pronto! Si comincia 😉',
  });

  @override
  State<ExamLaunchTransitionOverlay> createState() => _ExamLaunchTransitionOverlayState();
}

class _ExamLaunchTransitionOverlayState extends State<ExamLaunchTransitionOverlay>
    with TickerProviderStateMixin {
  // Flight controller: banner -> screen center
  late AnimationController _flightToCenterController;
  late Animation<double> _flightToCenterCurved;

  // Dots morph controller: sphere (0.0) <-> 3 dots (1.0)
  late AnimationController _dotsMorphController;
  late Animation<double> _dotsMorphCurved;

  // Wave bouncing controller for the 3 glowing dots
  late AnimationController _dotsWaveController;

  // Living breathing pulse controller
  late AnimationController _breathController;

  // Wink controller: playful cheerful wink
  late AnimationController _winkController;

  // Flight controller: screen center -> call avatar position
  late AnimationController _flightToCallController;
  late Animation<double> _flightToCallCurved;

  late String _currentSubtitle;
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentSubtitle = widget.initialSubtitle;

    // 1. Flight to Center (280ms, snappy easeOutCubic)
    _flightToCenterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _flightToCenterCurved = CurvedAnimation(
      parent: _flightToCenterController,
      curve: Curves.easeOutCubic,
    );

    // 2. Dots Morph (180ms)
    _dotsMorphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _dotsMorphCurved = CurvedAnimation(
      parent: _dotsMorphController,
      curve: Curves.easeInOutCubic,
    );

    // 3. Dots Wave Bounce (looping 900ms)
    _dotsWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 4. Living Breath (looping 2600ms)
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    // 5. Wink Controller (200ms)
    _winkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // 6. Flight to Call Position (180ms)
    _flightToCallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _flightToCallCurved = CurvedAnimation(
      parent: _flightToCallController,
      curve: Curves.easeOutCubic,
    );

    // If directToDots is enabled, jump directly into centered 3-dots state immediately
    if (widget.directToDots) {
      _flightToCenterController.value = 1.0;
      _dotsMorphController.value = 1.0;
      _dotsWaveController.repeat();
    }

    // Execute the sequence after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runFullSequence();
    });
  }

  @override
  void dispose() {
    _flightToCenterController.dispose();
    _dotsMorphController.dispose();
    _dotsWaveController.dispose();
    _breathController.dispose();
    _winkController.dispose();
    _flightToCallController.dispose();
    super.dispose();
  }

  Future<void> _runFullSequence() async {
    try {
      final startTime = DateTime.now();

      if (widget.directToDots) {
        // --- DIRECT TO 3 DOTS (NO TRANSITION FROM BANNER) ---
        // Connect and load session in parallel with active 3-dots wave
        await widget.onConnect();

        // Enforce a small smooth threshold (420ms) so dots don't flash instantaneously
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsed < 420) {
          await Future.delayed(Duration(milliseconds: 420 - elapsed));
        }

        if (!mounted) return;

        setState(() {
          _isDataLoaded = true;
          _currentSubtitle = widget.completedSubtitle;
        });

        _dotsWaveController.stop();
        await _dotsMorphController.reverse();

        if (!mounted) return;

        // Transition seamlessly into ExamScreen
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const ExamScreen(),
            transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      } else {
        // --- FULL BANNER TRANSITION (ONLY FROM MAIN HOME BUTTON) ---
        // Launch onConnect concurrently so network time overlaps with banner flight
        final connectFuture = widget.onConnect();

        // Phase 1: Glide from banner to center
        await _flightToCenterController.forward();

        // Phase 2: Morph smoothly into 3 wave dots
        _dotsWaveController.repeat();
        await _dotsMorphController.forward();

        // Phase 3: Wait for connection/loading to finish
        await connectFuture;
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsed < 650) {
          await Future.delayed(Duration(milliseconds: 650 - elapsed));
        }

        if (!mounted) return;

        setState(() {
          _isDataLoaded = true;
          _currentSubtitle = widget.completedSubtitle;
        });

        // Phase 4: Stop wave & morph back to avatar sphere
        _dotsWaveController.stop();
        await _dotsMorphController.reverse();

        if (!mounted) return;

        // Phase 5: Playful quick wink
        await _winkController.forward();
        await _winkController.reverse();

        if (!mounted) return;

        // Phase 6: Glide to call avatar position
        await _flightToCallController.forward();

        if (!mounted) return;

        // Phase 7: Transition into ExamScreen
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const ExamScreen(),
            transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 220),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screenSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    // 1. Initial Banner Avatar Coordinates (default: matches right side of Hero Banner)
    final bannerCenter = widget.startCenter ??
        Offset(screenSize.width * 0.74, padding.top + 195.0);
    final bannerSize = widget.startSize ?? 105.0;

    // 2. Screen Center Coordinates (Loading Phase)
    final centerTarget = Offset(screenSize.width * 0.5, screenSize.height * 0.40);
    const centerSize = 180.0;

    // 3. Call Avatar Coordinates (matches exact GrokAvatar spot on ExamScreen)
    final availableCallHeight = screenSize.height - padding.top - padding.bottom;
    final callTarget = Offset(
      screenSize.width * 0.5,
      padding.top + 48.0 + (availableCallHeight * 0.22) + 100.0,
    );
    const callSize = 200.0;

    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _flightToCenterController,
          _dotsMorphController,
          _dotsWaveController,
          _breathController,
          _winkController,
          _flightToCallController,
        ]),
        builder: (context, _) {
          final tCenter = _flightToCenterCurved.value;
          final tCall = _flightToCallCurved.value;

          Offset currentCenter;
          double currentSize;

          if (widget.directToDots) {
            // In direct mode: stays in center until call transition
            if (tCall > 0.0) {
              currentCenter = Offset.lerp(centerTarget, callTarget, tCall)!;
              currentSize = centerSize + ((callSize - centerSize) * tCall);
            } else {
              currentCenter = centerTarget;
              currentSize = centerSize;
            }
          } else {
            if (tCall > 0.0) {
              currentCenter = Offset.lerp(centerTarget, callTarget, tCall)!;
              currentSize = centerSize + ((callSize - centerSize) * tCall);
            } else {
              currentCenter = Offset.lerp(bannerCenter, centerTarget, tCenter)!;
              currentSize = bannerSize + ((centerSize - bannerSize) * tCenter);
            }
          }

          final dotsMorph = _dotsMorphCurved.value;
          final dotsWave = _dotsWaveController.value;
          final breath = _breathController.value;
          final wink = _winkController.value;

          // Background backdrop opacity (smooth gradient)
          final bgAlpha = widget.directToDots
              ? 0.90
              : (0.78 + (tCenter * 0.18) - (tCall * 0.15)).clamp(0.0, 0.96);

          return Scaffold(
            backgroundColor: colors.background.withValues(alpha: bgAlpha),
            body: Stack(
              children: [
                // Ambient Radial Aura centered on Avatar
                Positioned(
                  left: currentCenter.dx - (currentSize * 1.2),
                  top: currentCenter.dy - (currentSize * 1.2),
                  width: currentSize * 2.4,
                  height: currentSize * 2.4,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colors.primaryContainer.withValues(alpha: 0.18),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Animated Bloub Avatar
                Positioned(
                  left: currentCenter.dx - (currentSize / 2),
                  top: currentCenter.dy - (currentSize / 2),
                  width: currentSize,
                  height: currentSize,
                  child: BloubMorphingAvatar(
                    size: currentSize,
                    glowColor: colors.primaryGlow,
                    dotsMorphProgress: dotsMorph,
                    dotsWaveProgress: dotsWave,
                    winkProgress: wink,
                    breathCycle: breath,
                  ),
                ),

                // Status Subtitle (visible during loading wave and completion)
                if ((widget.directToDots || tCenter > 0.6) && tCall < 0.6)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: centerTarget.dy + (centerSize * 0.58) + 16,
                    child: RepaintBoundary(
                      child: AnimatedOpacity(
                        opacity: (dotsMorph > 0.2 || _isDataLoaded) ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
                                border: Border.all(
                                  color: colors.primaryContainer.withValues(alpha: _isDataLoaded ? 0.6 : 0.25),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.cardShadow,
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!_isDataLoaded) ...[
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        color: colors.primaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ] else ...[
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 15,
                                      color: colors.primaryContainer,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Text(
                                      _currentSubtitle,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
