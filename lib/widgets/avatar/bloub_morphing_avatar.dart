import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../constants.dart';
import 'avatar_math.dart';
import 'avatar_models.dart';

/// Highly expressive animated Bloub avatar based on https://github.com/jeremy-prt/bloub
/// Capable of morphing between:
/// 1. Full 3D living companion sphere with aura and projected eyes.
/// 2. Fluid three-dot loading sequence (● ● ●) with wave bouncing physics.
/// 3. Playful cheerful wink (fa l'occhiolino) upon completion.
class BloubMorphingAvatar extends StatelessWidget {
  final double size;
  final Color? glowColor;
  final double dotsMorphProgress; // 0.0 = full avatar sphere, 1.0 = three dots
  final double dotsWaveProgress;  // 0.0 -> 1.0 continuous wave phase
  final double winkProgress;      // 0.0 = standard, 1.0 = full wink
  final double breathCycle;       // 0.0 -> 1.0 breathing pulse
  final AvatarAgentMood mood;

  const BloubMorphingAvatar({
    super.key,
    required this.size,
    this.glowColor,
    this.dotsMorphProgress = 0.0,
    this.dotsWaveProgress = 0.0,
    this.winkProgress = 0.0,
    this.breathCycle = 0.0,
    this.mood = AvatarAgentMood.idle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeGlow = glowColor ?? colors.primaryGlow;

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(size, size),
        painter: _BloubMorphingPainter(
          mood: mood,
          glowColor: activeGlow,
          dotsMorphProgress: dotsMorphProgress.clamp(0.0, 1.0),
          dotsWaveProgress: dotsWaveProgress,
          winkProgress: winkProgress.clamp(0.0, 1.0),
          breathCycle: breathCycle,
        ),
      ),
    );
  }
}

class _BloubMorphingPainter extends CustomPainter {
  final AvatarAgentMood mood;
  final Color glowColor;
  final double dotsMorphProgress;
  final double dotsWaveProgress;
  final double winkProgress;
  final double breathCycle;

  _BloubMorphingPainter({
    required this.mood,
    required this.glowColor,
    required this.dotsMorphProgress,
    required this.dotsWaveProgress,
    required this.winkProgress,
    required this.breathCycle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final sphereRadius = size.width * 0.38;

    // Organic breathing oscillation
    final breathPulse = math.sin(breathCycle * 2 * math.pi);
    final auraBreathe = 1.0 + (breathPulse * 0.08);

    // Dynamic morphing factor with smooth easeInOut curve
    final morph = Curves.easeInOutCubic.transform(dotsMorphProgress);

    // 1. Aura & Luminescent Halo Glow
    final baseAuraRadius = sphereRadius * 1.60 * auraBreathe;
    final auraAlpha = ((0.28 + (winkProgress * 0.35)) * (1.0 - morph * 0.25)).clamp(0.0, 1.0);

    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: auraAlpha),
          glowColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseAuraRadius));
    canvas.drawCircle(center, baseAuraRadius, auraPaint);

    // 2. Three Dots Configuration & Wave Physics
    // In three-dots state, dots spread horizontally with a travelling sinusoidal bounce
    final dotTargetRadius = sphereRadius * 0.22;
    final spreadDistance = sphereRadius * 0.68;
    final waveAmplitude = sphereRadius * 0.26 * morph;

    final leftWaveY = math.sin(dotsWaveProgress * 2 * math.pi) * waveAmplitude;
    final centerWaveY = math.sin(dotsWaveProgress * 2 * math.pi - 0.75) * waveAmplitude;
    final rightWaveY = math.sin(dotsWaveProgress * 2 * math.pi - 1.50) * waveAmplitude;

    final centerDotRadius = _lerpDouble(sphereRadius, dotTargetRadius, morph);
    final sideDotRadius = dotTargetRadius * morph;

    final centerDotPos = Offset(center.dx, center.dy + (centerWaveY * morph));
    final leftDotPos = Offset(center.dx - (spreadDistance * morph), center.dy + (leftWaveY * morph));
    final rightDotPos = Offset(center.dx + (spreadDistance * morph), center.dy + (rightWaveY * morph));

    // Wink head perk & bouncy deformation
    final winkBounceX = 1.0 + (0.05 * math.sin(winkProgress * math.pi));
    final winkBounceY = 1.0 - (0.04 * math.sin(winkProgress * math.pi));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(winkBounceX, winkBounceY);
    canvas.translate(-center.dx, -center.dy);

    // 3. Render 3D Ink Spheres (Center, Left, Right)
    if (sideDotRadius > 0.5) {
      _drawSphericalDot(canvas, leftDotPos, sideDotRadius);
      _drawSphericalDot(canvas, rightDotPos, sideDotRadius);
    }
    _drawSphericalDot(canvas, centerDotPos, centerDotRadius);

    // 4. Render Face & Eyes when in Avatar mode (fades out as it morphs into dots)
    final eyeOpacity = ((1.0 - (dotsMorphProgress * 2.8))).clamp(0.0, 1.0);
    if (eyeOpacity > 0.01) {
      _drawFace(canvas, centerDotPos, centerDotRadius, eyeOpacity);
    }

    canvas.restore();
  }

  void _drawSphericalDot(Canvas canvas, Offset dotCenter, double radius) {
    if (radius <= 0.2) return;

    // Rich deep 3D spherical radial gradient (Bloub body)
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.40),
        radius: 0.95,
        colors: const [
          Color(0xFF2E3856), // Specular highlight
          Color(0xFF131722), // Midnight ink core
          Color(0xFF090B10), // Shadow baseline
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: dotCenter, radius: radius));
    canvas.drawCircle(dotCenter, radius, bodyPaint);

    // Ambient rim highlight along the upper crest
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * 0.07)
      ..shader = RadialGradient(
        center: const Alignment(-0.30, -0.40),
        radius: 1.0,
        colors: [
          glowColor.withValues(alpha: 0.85),
          glowColor.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: dotCenter, radius: radius));
    canvas.drawCircle(dotCenter, radius, rimPaint);
  }

  void _drawFace(Canvas canvas, Offset faceCenter, double radius, double opacity) {
    // Composite head gaze: incorporates cheerful head-cock on wink
    final headGaze = HeadGaze(
      yaw: -3.0 * winkProgress,
      pitch: 2.5 * winkProgress,
      roll: 8.5 * winkProgress,
    );

    final (eye0, eye1) = computeEyePoses(headGaze, radius);

    // Left eye: wide open, sparkling with joyful arch
    final leftEyeConfig = AvatarEyeConfig(
      width: 0.188,
      height: 0.42,
      open: 1.0 + (0.15 * winkProgress),
      tilt: 4.5 * winkProgress,
      arch: 0.12 * winkProgress,
    );

    // Right eye: executes the adorable, unmistakable wink crescent (fa l'occhiolino)
    final rightEyeConfig = AvatarEyeConfig(
      width: 0.188,
      height: 0.40,
      open: (1.0 - (winkProgress * 0.92)).clamp(0.08, 1.0),
      tilt: -11.0 * winkProgress,
      arch: 0.95 * winkProgress,
    );

    canvas.save();
    canvas.translate(faceCenter.dx, faceCenter.dy);

    _drawEyeWithOpacity(canvas, eye0, leftEyeConfig, radius, opacity);
    _drawEyeWithOpacity(canvas, eye1, rightEyeConfig, radius, opacity);

    canvas.restore();
  }

  void _drawEyeWithOpacity(
    Canvas canvas,
    EyePose eyePose,
    AvatarEyeConfig cfg,
    double sphereRadius,
    double opacity,
  ) {
    if (eyePose.depth <= 0) return;

    final eyeWidth = sphereRadius * cfg.width;
    final eyeHeight = cfg.arch.abs() > 0.04
        ? math.max(sphereRadius * cfg.height * cfg.open, sphereRadius * cfg.height * 0.18)
        : sphereRadius * cfg.height * cfg.open;

    if (eyeHeight < 0.8 && cfg.arch.abs() <= 0.04) return;

    canvas.save();
    canvas.translate(eyePose.x, eyePose.y);

    // 3D tangent transformation matrix
    final transform = Matrix4.identity();
    transform.setValues(
      eyePose.a, eyePose.b, 0, 0,
      eyePose.c, eyePose.d, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    );
    canvas.transform(transform.storage);

    if (cfg.tilt != 0.0) {
      canvas.rotate(cfg.tilt * math.pi / 180.0);
    }

    final eyePaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final halfW = eyeWidth / 2;
    final halfH = eyeHeight / 2;

    // Draw happy curved crescent arch if arch is active (classic wink)
    if (cfg.arch > 0.04) {
      final archOffset = cfg.arch * (eyeHeight * 0.40);
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
      canvas.drawPath(path, eyePaint);
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
      canvas.drawRRect(eyeRRect, eyePaint);
    }

    canvas.restore();
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _BloubMorphingPainter oldDelegate) {
    return oldDelegate.dotsMorphProgress != dotsMorphProgress ||
        oldDelegate.dotsWaveProgress != dotsWaveProgress ||
        oldDelegate.winkProgress != winkProgress ||
        oldDelegate.breathCycle != breathCycle ||
        oldDelegate.glowColor != glowColor;
  }
}
