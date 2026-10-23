import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../constants.dart';
import 'avatar_math.dart';
import 'avatar_models.dart';

enum _BlinkStyle {
  single,
  doubleBlink,
  slow,
}

class GrokAvatar extends StatefulWidget {
  final AvatarAgentMood mood;
  final double size;
  final Color? glowColor;
  final bool isSpeaking;
  final bool isListening;
  final VoidCallback? onTap;
  final bool enableInteractiveGaze;

  const GrokAvatar({
    super.key,
    required this.mood,
    this.size = 220.0,
    this.glowColor,
    this.isSpeaking = false,
    this.isListening = false,
    this.onTap,
    this.enableInteractiveGaze = true,
  });

  @override
  State<GrokAvatar> createState() => _GrokAvatarState();
}

class _GrokAvatarState extends State<GrokAvatar>
    with TickerProviderStateMixin {
  late AnimationController _loopController;
  late AnimationController _poseTransitionController;
  late AnimationController _gazeController;
  late AnimationController _blinkController;
  late AnimationController _gestureController;

  AvatarPose _currentPose = AvatarPose.forMood(AvatarAgentMood.idle);
  AvatarPose _targetPose = AvatarPose.forMood(AvatarAgentMood.idle);

  HeadGaze _startGazeOffset = HeadGaze.zero;
  HeadGaze _targetGazeOffset = HeadGaze.zero;
  HeadGaze _interactiveGaze = HeadGaze.zero;

  AvatarGesture _currentGesture = AvatarGesture.none;
  _BlinkStyle _blinkStyle = _BlinkStyle.single;

  final math.Random _random = math.Random();
  Timer? _blinkTimer;
  Timer? _gazeTimer;
  Timer? _gestureTimer;

  // Pointer tracking throttle — limits setState to ~30fps (33ms) to avoid
  // 60-120 layout passes per second on drag/hover (significant on Android mid-range).
  int _lastPointerUpdateMs = 0;

  @override
  void initState() {
    super.initState();

    // 1. Continuous breathing, organic float oscillation, speech cadence & orbit cycle
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // 2. Pose transition controller for smooth morphing between mood changes
    _poseTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    // 3. Saccadic gaze movement controller
    _gazeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    // 4. Spontaneous blinking controller
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    // 5. Micro-gesture controller (nods, perks, curious tilts)
    _gestureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _targetPose = AvatarPose.forMood(widget.mood);
    _currentPose = _targetPose;

    _scheduleNextBlink();
    _scheduleNextGazeShift();
    _scheduleNextGesture();
  }

  // --- 1. Natural Blinking Variations (Single, Double-Blink, Slow) ---

  void _scheduleNextBlink() {
    _blinkTimer?.cancel();
    final nextBlinkMs = 2400 + _random.nextInt(3400);
    _blinkTimer = Timer(Duration(milliseconds: nextBlinkMs), () {
      if (!mounted) return;
      _triggerBlink();
    });
  }

  void _triggerBlink({bool forceDouble = false}) {
    if (!mounted) return;

    if (forceDouble) {
      _blinkStyle = _BlinkStyle.doubleBlink;
    } else {
      final roll = _random.nextDouble();
      if (roll < 0.22) {
        _blinkStyle = _BlinkStyle.doubleBlink;
      } else if (roll < 0.34) {
        _blinkStyle = _BlinkStyle.slow;
      } else {
        _blinkStyle = _BlinkStyle.single;
      }
    }

    final durationMs = switch (_blinkStyle) {
      _BlinkStyle.single => 160,
      _BlinkStyle.doubleBlink => 320,
      _BlinkStyle.slow => 300,
    };

    _blinkController.duration = Duration(milliseconds: durationMs);

    if (_blinkStyle == _BlinkStyle.doubleBlink) {
      // Complete double-flutter in a single forward pass (0.0 -> 1.0)
      _blinkController.forward(from: 0.0).then((_) {
        if (mounted) {
          _blinkController.value = 0.0;
          _scheduleNextBlink();
        }
      });
    } else {
      // Single and slow blinks use forward & reverse
      _blinkController.forward(from: 0.0).then((_) {
        if (mounted) {
          _blinkController.reverse().then((_) {
            if (mounted) {
              _scheduleNextBlink();
            }
          });
        }
      });
    }
  }

  // --- 2. Autonomous Gaze Saccades & Living Direction Shifts ---

  void _scheduleNextGazeShift() {
    _gazeTimer?.cancel();
    final nextGazeMs = 2200 + _random.nextInt(3200);
    _gazeTimer = Timer(Duration(milliseconds: nextGazeMs), () {
      if (!mounted) return;
      _performGazeShift();
      _scheduleNextGazeShift();
    });
  }

  void _performGazeShift() {
    if (!mounted) return;
    _startGazeOffset = HeadGaze.lerp(
      _startGazeOffset,
      _targetGazeOffset,
      Curves.fastOutSlowIn.transform(_gazeController.value),
    );
    _targetGazeOffset = _pickNextGazeOffset();

    // Saccade duration: snappy yet smooth
    final saccadeMs = 320 + _random.nextInt(160);
    _gazeController.duration = Duration(milliseconds: saccadeMs);
    _gazeController.forward(from: 0.0);

    // Biological detail: eyes often execute a light blink during a gaze saccade
    if (_random.nextDouble() < 0.32 && !_blinkController.isAnimating) {
      _triggerBlink();
    }
  }

  HeadGaze _pickNextGazeOffset() {
    switch (widget.mood) {
      case AvatarAgentMood.thinking:
        // Searching high & low in thought
        const options = [
          HeadGaze(yaw: -6.0, pitch: 4.0, roll: 2.0),
          HeadGaze(yaw: 14.0, pitch: 8.0, roll: 10.0),
          HeadGaze(yaw: 6.0, pitch: 10.0, roll: 4.0),
          HeadGaze(yaw: -10.0, pitch: -6.0, roll: -4.0),
          HeadGaze(yaw: 16.0, pitch: -8.0, roll: 8.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.listening:
        // Attentive tracking: focused with subtle curious tilts
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 4.0, pitch: 2.0, roll: 6.0),
          HeadGaze(yaw: -4.0, pitch: 1.0, roll: -5.0),
          HeadGaze(yaw: 0.0, pitch: 4.0, roll: 2.0),
          HeadGaze(yaw: 5.0, pitch: -2.0, roll: 4.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.speaking:
        // Conversational shifts: articulates with dynamic head sway
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 7.0, pitch: 3.0, roll: -3.0),
          HeadGaze(yaw: -7.0, pitch: 2.0, roll: 3.0),
          HeadGaze(yaw: 2.0, pitch: -3.0, roll: 0.0),
          HeadGaze(yaw: -3.0, pitch: 3.0, roll: -2.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.collision:
        // Quizzical challenge
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 6.0, pitch: 4.0, roll: 6.0),
          HeadGaze(yaw: -8.0, pitch: 2.0, roll: -8.0),
          HeadGaze(yaw: 4.0, pitch: -4.0, roll: 8.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.scaffolding:
        // Warm encouraging connection
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 4.0, pitch: 2.0, roll: 4.0),
          HeadGaze(yaw: -4.0, pitch: 2.0, roll: -4.0),
          HeadGaze(yaw: 0.0, pitch: 4.0, roll: 0.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.narrowing:
        // Focused analytical scrutiny
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 2.0, pitch: 1.0, roll: 1.0),
          HeadGaze(yaw: -2.0, pitch: 1.0, roll: -1.0),
          HeadGaze(yaw: 0.0, pitch: -2.0, roll: 0.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.paused:
        // Sleepy relaxing drift
        const options = [
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          HeadGaze(yaw: 2.0, pitch: -3.0, roll: 2.0),
          HeadGaze(yaw: -2.0, pitch: -2.0, roll: -2.0),
        ];
        return options[_random.nextInt(options.length)];

      case AvatarAgentMood.idle:
        // Living companion idle: alternates between direct eye contact with student,
        // ambient curiosity to the sides, and gentle glances down.
        // Base idle pose is HeadGaze.rest (yaw: 28.49, pitch: 28.62, roll: -13.0).
        const options = [
          // Direct eye contact with user
          HeadGaze(yaw: -28.49, pitch: -24.62, roll: 13.0),
          // Direct with curious head-cock
          HeadGaze(yaw: -25.0, pitch: -21.0, roll: 18.0),
          // Ambient glance left
          HeadGaze(yaw: -44.0, pitch: -18.0, roll: 16.0),
          // Ambient glance right
          HeadGaze(yaw: -10.0, pitch: -16.0, roll: 5.0),
          // Classic distance rest
          HeadGaze(yaw: 0.0, pitch: 0.0, roll: 0.0),
          // Pondering upward
          HeadGaze(yaw: -16.0, pitch: -8.0, roll: 10.0),
          // Glancing down thoughtfully
          HeadGaze(yaw: -28.0, pitch: -34.0, roll: 12.0),
        ];
        return options[_random.nextInt(options.length)];
    }
  }

  // --- 3. Expressive Micro-Gestures (Nods, Perks, Curious Tilts) ---

  void _scheduleNextGesture() {
    _gestureTimer?.cancel();
    final nextMs = widget.isListening
        ? 2600 + _random.nextInt(1800)
        : 6500 + _random.nextInt(4500);

    _gestureTimer = Timer(Duration(milliseconds: nextMs), () {
      if (!mounted) return;
      if (widget.isListening) {
        // Affirmative listening nod
        _triggerGesture(AvatarGesture.nod);
      } else if (widget.mood == AvatarAgentMood.idle && !_gestureController.isAnimating) {
        // Subtle curious head cock or ponder
        final gesture = _random.nextBool()
            ? AvatarGesture.curiousTilt
            : AvatarGesture.ponder;
        _triggerGesture(gesture);
      }
      _scheduleNextGesture();
    });
  }

  void _triggerGesture(AvatarGesture gesture) {
    if (!mounted) return;
    _currentGesture = gesture;
    final durationMs = switch (gesture) {
      AvatarGesture.nod => 460,
      AvatarGesture.perk => 560,
      AvatarGesture.curiousTilt => 680,
      AvatarGesture.shake => 440,
      AvatarGesture.ponder => 600,
      AvatarGesture.wink => 640,
      AvatarGesture.none => 300,
    };
    _gestureController.duration = Duration(milliseconds: durationMs);
    _gestureController.forward(from: 0.0).then((_) {
      if (mounted) {
        _currentGesture = AvatarGesture.none;
      }
    });
  }

  // --- 4. Interactive Touch & Pointer Tracking ---

  void _handlePointerMove(Offset localPos) {
    if (!widget.enableInteractiveGaze) return;

    // Throttle to ~30fps (33ms) to avoid excessive setState calls on drag/hover.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPointerUpdateMs < 33) return;
    _lastPointerUpdateMs = nowMs;

    final half = widget.size / 2;
    final dx = ((localPos.dx - half) / half).clamp(-1.2, 1.2);
    final dy = ((localPos.dy - half) / half).clamp(-1.2, 1.2);

    setState(() {
      _interactiveGaze = HeadGaze(
        yaw: dx * 18.0,
        pitch: -dy * 16.0,
        roll: dx * 6.0,
      );
    });
  }

  void _handlePointerExit() {
    if (!widget.enableInteractiveGaze) return;
    setState(() {
      _interactiveGaze = HeadGaze.zero;
    });
  }

  void _handleTap() {
    _triggerGesture(AvatarGesture.perk);
    _triggerBlink(forceDouble: true);
    widget.onTap?.call();
  }

  @override
  void didUpdateWidget(covariant GrokAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood ||
        oldWidget.isSpeaking != widget.isSpeaking ||
        oldWidget.isListening != widget.isListening) {
      _currentPose = AvatarPose.lerp(
        _currentPose,
        _targetPose,
        _poseTransitionController.value,
      );
      _targetPose = AvatarPose.forMood(widget.mood);
      _poseTransitionController.forward(from: 0.0);

      // Trigger a responsive gesture on state shift
      if (widget.isListening && !oldWidget.isListening) {
        _triggerGesture(AvatarGesture.curiousTilt);
      } else if (widget.isSpeaking && !oldWidget.isSpeaking) {
        _triggerGesture(AvatarGesture.perk);
      }
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _gazeTimer?.cancel();
    _gestureTimer?.cancel();
    _loopController.dispose();
    _poseTransitionController.dispose();
    _gazeController.dispose();
    _blinkController.dispose();
    _gestureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        onHover: (event) => _handlePointerMove(event.localPosition),
        onExit: (_) => _handlePointerExit(),
        child: GestureDetector(
          onTap: _handleTap,
          onPanUpdate: (details) => _handlePointerMove(details.localPosition),
          onPanEnd: (_) => _handlePointerExit(),
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _loopController,
              _poseTransitionController,
              _gazeController,
              _blinkController,
              _gestureController,
            ]),
            builder: (context, _) {
              final loopVal = _loopController.value;

              // 1. Organic Breathing with Secondary Harmonic (Fluid breathing curve)
              final breath = math.sin(loopVal * 2 * math.pi) * 0.75 +
                  math.sin(loopVal * 4 * math.pi) * 0.25;
              final breathVelocity = math.cos(loopVal * 2 * math.pi);

              // 2. Multi-Harmonic Speech Resonance (Natural voice bounce & phonetic modulation)
              double speechWobble = 0.0;
              double speechPitchOffset = 0.0;
              double speechEyeExpand = 0.0;
              if (widget.isSpeaking) {
                final speechCadence = (
                  math.sin(loopVal * 8 * math.pi) * 0.50 +
                  math.sin(loopVal * 14 * math.pi) * 0.35 +
                  math.sin(loopVal * 22 * math.pi) * 0.15
                );
                speechWobble = speechCadence * 0.045;
                speechPitchOffset = speechCadence * 2.8;
                speechEyeExpand = speechCadence.abs() * 0.07;
              }

              // 3. Listening Head Posture & Attentive Drift
              final listeningNod = widget.isListening
                  ? math.sin(loopVal * 3 * math.pi) * 1.6
                  : 0.0;

              // 4. Interpolate Base Pose between Moods
              final tPose = Curves.easeInOutCubic.transform(_poseTransitionController.value);
              final basePose = AvatarPose.lerp(_currentPose, _targetPose, tPose);

              // 5. Evaluate Blink Factor (Smooth Single, Double-Flutter, or Slow)
              final bVal = _blinkController.value;
              double closedFraction = 0.0;
              if (_blinkStyle == _BlinkStyle.doubleBlink) {
                // Double blink piecewise curve in single forward cycle
                if (bVal <= 0.25) {
                  closedFraction = bVal / 0.25;
                } else if (bVal <= 0.50) {
                  closedFraction = 1.0 - ((bVal - 0.25) / 0.25) * 0.55;
                } else if (bVal <= 0.75) {
                  closedFraction = 0.45 + ((bVal - 0.50) / 0.25) * 0.55;
                } else {
                  closedFraction = 1.0 - ((bVal - 0.75) / 0.25);
                }
              } else {
                closedFraction = bVal;
              }
              final blinkFactor = 1.0 - (closedFraction * 0.96);

              // 6. Evaluate Micro-Gestures
              final gVal = _gestureController.value;
              double gesturePitch = 0.0;
              double gestureYaw = 0.0;
              double gestureRoll = 0.0;
              double gestureFloat = 0.0;
              double gestureScaleX = 0.0;
              double gestureScaleY = 0.0;
              double gestureGlow = 1.0;
              double gestureEyeArch = 0.0;
              double gestureEyeScale = 0.0;

              if (_gestureController.isAnimating) {
                switch (_currentGesture) {
                  case AvatarGesture.nod:
                    // Affirmative listening nod (dip pitch and return smoothly)
                    final nodProg = math.sin(gVal * math.pi);
                    gesturePitch = -nodProg * 7.5;
                    gestureFloat = nodProg * 2.5;
                    break;

                  case AvatarGesture.perk:
                    // Happy bounce on tap/greeting (spring hop, wide eyes, glow surge)
                    final perkHop = math.sin(gVal * math.pi);
                    gestureFloat = -perkHop * 13.0;
                    gestureScaleX = -(perkHop * 0.04);
                    gestureScaleY = perkHop * 0.07;
                    gestureGlow = 1.0 + (perkHop * 0.85);
                    gestureEyeArch = perkHop * 0.45; // happy crescent eyes
                    gestureEyeScale = perkHop * 0.12;
                    gestureRoll = math.sin(gVal * 2 * math.pi) * 6.0;
                    break;

                  case AvatarGesture.curiousTilt:
                    // Curious head-cock with eye widening
                    final tiltProg = math.sin(gVal * math.pi);
                    gestureRoll = tiltProg * 11.0;
                    gestureEyeScale = tiltProg * 0.08;
                    gesturePitch = tiltProg * 2.0;
                    break;

                  case AvatarGesture.shake:
                    // Subtle inquisitive head shake
                    gestureYaw = math.sin(gVal * 3 * math.pi) * 6.0;
                    break;

                  case AvatarGesture.ponder:
                    // Thoughtful look up & slight squint
                    final ponderProg = math.sin(gVal * math.pi);
                    gesturePitch = ponderProg * 5.0;
                    gestureEyeScale = -ponderProg * 0.08;
                    break;

                  case AvatarGesture.wink:
                    // Playful wink with head tilt, perk bounce & luminous aura
                    final winkProg = math.sin(gVal * math.pi);
                    gestureRoll = winkProg * 8.0;
                    gesturePitch = -winkProg * 3.0;
                    gestureFloat = -winkProg * 7.0;
                    gestureGlow = 1.0 + (winkProg * 0.95);
                    gestureScaleX = winkProg * 0.04;
                    gestureScaleY = -winkProg * 0.03;
                    break;

                  case AvatarGesture.none:
                    break;
                }
              }

              final isWinking = _currentGesture == AvatarGesture.wink && _gestureController.isAnimating;
              final winkAmount = isWinking ? math.sin(gVal * math.pi) : 0.0;

              // 7. Dynamic Gaze Saccade Interpolation
              final tGaze = Curves.fastOutSlowIn.transform(_gazeController.value);
              final activeGazeOffset = HeadGaze.lerp(_startGazeOffset, _targetGazeOffset, tGaze);

              // 8. Composite Head Gaze (Base + Saccade Offset + Gesture + Interactive + Breath + Speech)
              final finalGaze = basePose.gaze.offset(
                yaw: activeGazeOffset.yaw + gestureYaw + _interactiveGaze.yaw - (winkAmount * 3.0),
                pitch: activeGazeOffset.pitch + (breath * 1.5) + listeningNod +
                    speechPitchOffset + gesturePitch + _interactiveGaze.pitch,
                roll: activeGazeOffset.roll + gestureRoll + _interactiveGaze.roll,
              );

              // 9. Composite Eye Configuration
              final leftEye = basePose.leftEye.copyWith(
                open: (basePose.leftEye.open * blinkFactor * (1.0 + winkAmount * 0.15)).clamp(0.0, 1.0),
                height: basePose.leftEye.height * (1.0 + gestureEyeScale + speechEyeExpand),
                arch: (basePose.leftEye.arch + gestureEyeArch + winkAmount * 0.15).clamp(-1.0, 1.0),
                tilt: basePose.leftEye.tilt + winkAmount * 4.0,
              );
              final rightEye = basePose.rightEye.copyWith(
                open: (basePose.rightEye.open * blinkFactor * (1.0 - winkAmount * 0.92)).clamp(0.08, 1.0),
                height: basePose.rightEye.height * (1.0 + gestureEyeScale + speechEyeExpand),
                arch: (basePose.rightEye.arch + gestureEyeArch + winkAmount * 0.95).clamp(-1.0, 1.0),
                tilt: basePose.rightEye.tilt - winkAmount * 10.0,
              );

              // 10. Buoyant Squash & Stretch (Inertia physics matching vertical motion)
              final organicSquash = breathVelocity * 0.016;

              final activePose = AvatarPose(
                gaze: finalGaze,
                leftEye: leftEye,
                rightEye: rightEye,
                bodyScaleX: basePose.bodyScaleX - organicSquash + speechWobble + gestureScaleX,
                bodyScaleY: basePose.bodyScaleY + organicSquash - speechWobble + gestureScaleY,
                floatOffset: basePose.floatOffset + (breath * 4.5) + listeningNod + gestureFloat,
                hasOrbitRing: basePose.hasOrbitRing,
                glowIntensity: basePose.glowIntensity * gestureGlow,
              );

              final glow = widget.glowColor ?? context.colors.primaryGlow;

              return CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _BloubAvatarPainter(
                  pose: activePose,
                  glowColor: glow,
                  loopProgress: loopVal,
                  isSpeaking: widget.isSpeaking,
                  isListening: widget.isListening,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BloubAvatarPainter extends CustomPainter {
  final AvatarPose pose;
  final Color glowColor;
  final double loopProgress;
  final bool isSpeaking;
  final bool isListening;

  static final Paint _whiteFillPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Paint _ringStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _sparkPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _dotGlowPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _auraPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _bodyPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;

  _BloubAvatarPainter({
    required this.pose,
    required this.glowColor,
    required this.loopProgress,
    required this.isSpeaking,
    required this.isListening,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + pose.floatOffset);
    final radius = size.width * 0.38;

    // 1. Aura & Living Ambient Halo Glow (breathes and surges dynamically)
    final auraPulse = 1.0 + (math.sin(loopProgress * 2 * math.pi) * 0.08);
    final auraAlphaBase = isSpeaking ? 0.48 : (isListening ? 0.38 : 0.22);
    final auraAlpha = (auraAlphaBase * pose.glowIntensity * auraPulse).clamp(0.0, 1.0);

    _auraPaint.shader = RadialGradient(
      colors: [
        glowColor.withValues(alpha: auraAlpha),
        glowColor.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: center, radius: radius * 1.65));
    canvas.drawCircle(center, radius * 1.65, _auraPaint);

    // 2. Orbit Ring & Luminous Comet Trail (Thinking / Evaluating state)
    if (pose.hasOrbitRing) {
      _ringStrokePaint.color = glowColor.withValues(alpha: 0.35);

      final ringRect = Rect.fromCenter(
        center: center,
        width: radius * 2.35,
        height: radius * 1.15,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-0.35); // tilt orbit
      canvas.translate(-center.dx, -center.dy);
      canvas.drawOval(ringRect, _ringStrokePaint);

      final angle = loopProgress * 2 * math.pi;

      // Trailing luminous sparks (comet effect behind orbiting satellite)
      const trailOffsets = [0.18, 0.34, 0.50];
      const trailSizes = [3.0, 2.2, 1.4];
      const trailAlphas = [0.55, 0.30, 0.12];

      for (int i = 0; i < trailOffsets.length; i++) {
        final tAngle = angle - trailOffsets[i];
        final tx = center.dx + (radius * 1.175) * math.cos(tAngle);
        final ty = center.dy + (radius * 0.575) * math.sin(tAngle);
        _sparkPaint.color = glowColor.withValues(alpha: trailAlphas[i]);
        canvas.drawCircle(Offset(tx, ty), trailSizes[i], _sparkPaint);
      }

      // Main orbiting satellite dot
      final px = center.dx + (radius * 1.175) * math.cos(angle);
      final py = center.dy + (radius * 0.575) * math.sin(angle);

      _dotGlowPaint.shader = RadialGradient(
        colors: [glowColor, glowColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: Offset(px, py), radius: 14));
      canvas.drawCircle(Offset(px, py), 14, _dotGlowPaint);

      canvas.drawCircle(Offset(px, py), 4.2, _whiteFillPaint);
      canvas.restore();
    }

    // 3. Body Silhouette (Organic sphere with fluid squash & stretch)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(pose.bodyScaleX, pose.bodyScaleY);

    // Deep sleek ink sphere with 3D spherical gradient
    _bodyPaint.shader = RadialGradient(
      center: const Alignment(-0.35, -0.40),
      radius: 0.95,
      colors: const [
        Color(0xFF2E3856), // Subtle highlight
        Color(0xFF131722), // Deep body
        Color(0xFF090B10), // Shadow
      ],
      stops: const [0.0, 0.65, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));

    canvas.drawCircle(Offset.zero, radius, _bodyPaint);

    // Outer edge rim light
    _rimPaint.shader = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      radius: 1.0,
      colors: [
        glowColor.withValues(alpha: 0.75),
        glowColor.withValues(alpha: 0.18),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    canvas.drawCircle(Offset.zero, radius, _rimPaint);

    // 4. Render Projected Capsule Eyes
    final (eye0, eye1) = computeEyePoses(pose.gaze, radius);
    _drawEye(canvas, eye0, pose.leftEye, radius);
    _drawEye(canvas, eye1, pose.rightEye, radius);

    canvas.restore();
  }

  void _drawEye(
    Canvas canvas,
    EyePose eyePose,
    AvatarEyeConfig cfg,
    double sphereRadius,
  ) {
    if (eyePose.depth <= 0) return; // Behind sphere

    final eyeWidth = sphereRadius * cfg.width;
    final eyeHeight = cfg.arch.abs() > 0.04
        ? math.max(sphereRadius * cfg.height * cfg.open, sphereRadius * cfg.height * 0.16)
        : sphereRadius * cfg.height * cfg.open;

    if (eyeHeight < 0.8 && cfg.arch.abs() <= 0.04) return; // Fully closed during blink

    canvas.save();
    // 1. Move to projected eye center on sphere
    canvas.translate(eyePose.x, eyePose.y);

    // 2. Apply 3D tangent transformation matrix
    final transform = Matrix4.identity();
    transform.setValues(
      eyePose.a, eyePose.b, 0, 0,
      eyePose.c, eyePose.d, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    );
    canvas.transform(transform.storage);

    // 3. Apply individual expression tilt (in degrees)
    if (cfg.tilt != 0.0) {
      canvas.rotate(cfg.tilt * math.pi / 180.0);
    }

    final halfW = eyeWidth / 2;
    final halfH = eyeHeight / 2;

    // 4. Draw rounded capsule eye or happy crescent if arch is active
    if (cfg.arch > 0.04) {
      final archOffset = cfg.arch * (eyeHeight * 0.35);
      final path = Path()
        ..moveTo(-halfW, -archOffset * 0.2)
        ..quadraticBezierTo(0, -halfH - archOffset, halfW, -archOffset * 0.2)
        ..arcToPoint(
          Offset(halfW, halfH - archOffset * 0.2),
          radius: Radius.circular(halfW),
          clockwise: true,
        )
        ..quadraticBezierTo(0, -archOffset, -halfW, halfH - archOffset * 0.2)
        ..arcToPoint(
          Offset(-halfW, -archOffset * 0.2),
          radius: Radius.circular(halfW),
          clockwise: true,
        )
        ..close();
      canvas.drawPath(path, _whiteFillPaint);
    } else {
      final eyeRect = Rect.fromCenter(
        center: Offset.zero,
        width: eyeWidth,
        height: eyeHeight,
      );
      final eyeRRect = RRect.fromRectAndRadius(
        eyeRect,
        Radius.circular(halfW),
      );
      canvas.drawRRect(eyeRRect, _whiteFillPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BloubAvatarPainter oldDelegate) {
    // Only repaint when the data that drives the visual output has actually changed.
    // Comparing the pose object is sufficient because AnimatedBuilder already invalidates
    // the widget on every animation tick — this prevents the painter from being unnecessarily
    // re-evaluated when Flutter decides to mark the layer dirty for other reasons.
    return oldDelegate.pose != pose ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.loopProgress != loopProgress ||
        oldDelegate.isSpeaking != isSpeaking ||
        oldDelegate.isListening != isListening;
  }
}
