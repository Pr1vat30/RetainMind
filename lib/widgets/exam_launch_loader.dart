import 'dart:async';
import 'package:flutter/material.dart';
import '../constants.dart';
import '../screens/exam_screen.dart';
import 'avatar/bloub_morphing_avatar.dart';

/// Launches the AI oral examination calling screen ([ExamScreen]) with a high-fidelity
/// Bloub avatar loading animation inspired by https://github.com/jeremy-prt/bloub.
///
/// Animation choreography:
/// 1. The Bloub avatar expands from the Hero banner position and glides towards the center.
/// 2. It morphs into 3 bouncing, pulsating glowing dots (● ● ●) while loading session data & messages.
/// 3. Once loading is complete, the dots merge back into the sphere and the avatar winks (fa l'occhiolino).
/// 4. The avatar glides into the exact position of the active call screen ([ExamScreen]) and seamlessly transitions.
Future<void> launchExamWithLoader(
  BuildContext context, {
  required Future<void> Function() onConnect,
  Offset? startCenter,
  double? startSize,
  String? title,
  String? subtitle,
  String initialSubtitle = 'Caricamento informazioni e messaggi...',
  String completedSubtitle = 'Pronto! Si comincia 😉',
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final effectiveInitialSubtitle = subtitle ?? initialSubtitle;

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
            title: title,
            initialSubtitle: effectiveInitialSubtitle,
            completedSubtitle: completedSubtitle,
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 250),
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
  final String? title;
  final String initialSubtitle;
  final String completedSubtitle;

  const ExamLaunchTransitionOverlay({
    super.key,
    required this.onConnect,
    this.startCenter,
    this.startSize,
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

  // Dots morph controller: sphere -> 3 dots (forward) and 3 dots -> sphere (reverse)
  late AnimationController _dotsMorphController;
  late Animation<double> _dotsMorphCurved;

  // Wave bouncing controller for the three dots
  late AnimationController _dotsWaveController;

  // Living breathing pulse controller
  late AnimationController _breathController;

  // Wink controller: executes playful wink upon completion
  late AnimationController _winkController;

  // Flight controller: screen center -> call avatar position
  late AnimationController _flightToCallController;
  late Animation<double> _flightToCallCurved;

  // Subtitle text state
  late String _currentSubtitle;
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentSubtitle = widget.initialSubtitle;

    // 1. Flight to Center (480ms)
    _flightToCenterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _flightToCenterCurved = CurvedAnimation(
      parent: _flightToCenterController,
      curve: Curves.easeOutBack,
    );

    // 2. Dots Morph (360ms)
    _dotsMorphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _dotsMorphCurved = CurvedAnimation(
      parent: _dotsMorphController,
      curve: Curves.easeInOutCubic,
    );

    // 3. Dots Wave Bounce (looping 1100ms)
    _dotsWaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // 4. Subtle Living Breath (looping 3000ms)
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // 5. Wink Controller (450ms)
    _winkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    // 6. Flight to Call Position (380ms)
    _flightToCallController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _flightToCallCurved = CurvedAnimation(
      parent: _flightToCallController,
      curve: Curves.easeInOutCubic,
    );

    // Kick off choreography after first layout pass
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
      // Phase 1: Fly from banner to screen center
      await _flightToCenterController.forward();

      // Phase 2: Morph into 3 pulsating dots
      _dotsWaveController.repeat();
      await _dotsMorphController.forward();

      // Phase 3: Execute background loading while 3 dots bounce in wave motion
      // Enforce a minimum display time of 1100ms so the morph animation is appreciated
      final startTime = DateTime.now();
      await widget.onConnect();
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < 1100) {
        await Future.delayed(Duration(milliseconds: 1100 - elapsed));
      }

      if (!mounted) return;

      setState(() {
        _isDataLoaded = true;
        _currentSubtitle = widget.completedSubtitle;
      });

      // Phase 4: Stop wave & morph back into single avatar sphere
      _dotsWaveController.stop();
      await _dotsMorphController.reverse();

      if (!mounted) return;

      // Phase 5: Cheerful Wink (fa l'occhiolino)
      await _winkController.forward();
      await Future.delayed(const Duration(milliseconds: 320));
      await _winkController.reverse();

      if (!mounted) return;

      // Phase 6: Fly smoothly to call screen position
      await _flightToCallController.forward();

      if (!mounted) return;

      // Phase 7: Transition into ExamScreen seamlessly
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const ExamScreen(),
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 260),
        ),
      );
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
          // Compute current Avatar Center and Size
          final tCenter = _flightToCenterCurved.value;
          final tCall = _flightToCallCurved.value;

          Offset currentCenter;
          double currentSize;

          if (tCall > 0.0) {
            // Gliding from center to call position
            currentCenter = Offset.lerp(centerTarget, callTarget, tCall)!;
            currentSize = centerSize + ((callSize - centerSize) * tCall);
          } else {
            // Gliding from banner to center
            currentCenter = Offset.lerp(bannerCenter, centerTarget, tCenter)!;
            currentSize = bannerSize + ((centerSize - bannerSize) * tCenter);
          }

          final dotsMorph = _dotsMorphCurved.value;
          final dotsWave = _dotsWaveController.value;
          final breath = _breathController.value;
          final wink = _winkController.value;

          // Background backdrop opacity
          final bgAlpha = (0.78 + (tCenter * 0.18) - (tCall * 0.15)).clamp(0.0, 0.96);

          return Scaffold(
            backgroundColor: colors.background.withValues(alpha: bgAlpha),
            body: Stack(
              children: [
                // Subtle radial light ambient aura centered on avatar
                Positioned(
                  left: currentCenter.dx - (currentSize * 1.2),
                  top: currentCenter.dy - (currentSize * 1.2),
                  width: currentSize * 2.4,
                  height: currentSize * 2.4,
                  child: IgnorePointer(
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

                // Status Subtitle (visible during loading wave and wink)
                if (tCenter > 0.6 && tCall < 0.6)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: centerTarget.dy + (centerSize * 0.58) + 16,
                    child: AnimatedOpacity(
                      opacity: (dotsMorph > 0.2 || _isDataLoaded) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
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
              ],
            ),
          );
        },
      ),
    );
  }
}
